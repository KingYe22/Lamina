import AppKit
import LaminaCore
import MetalKit

final class PasteboardMetalView: MTKView, MTKViewDelegate {
    private var queue: MTLCommandQueue?

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        isPaused = true
        enableSetNeedsDisplay = true
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
        delegate = self
        queue = self.device?.makeCommandQueue()
        clearColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor,
              let buffer = queue?.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

final class CanvasHost: NSView {
    let metal = PasteboardMetalView(frame: .zero, device: nil)
    let drawing = VectorCanvas()

    var workspace: Workspace? {
        get { drawing.workspace }
        set { drawing.workspace = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        metal.autoresizingMask = [.width, .height]
        drawing.autoresizingMask = [.width, .height]
        addSubview(metal)
        addSubview(drawing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        metal.frame = bounds
        drawing.frame = bounds
    }

    func sync() {
        metal.isHidden = true
        drawing.needsDisplay = true
        if !metal.isHidden { metal.setNeedsDisplay(metal.bounds) }
        window?.invalidateCursorRects(for: drawing)
    }
}

final class VectorCanvas: NSView {
    var workspace: Workspace? {
        didSet { registerForDraggedTypes([.fileURL]) }
    }
    private var panAtDown = Vec2.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    /// The canvas is not a text client. Returning nil keeps the Pinyin input method
    /// from claiming letter keys before keyDown.
    override var inputContext: NSTextInputContext? { nil }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        NSTextInputContext.current?.discardMarkedText()
        NSTextInputContext.current?.deactivate()
        return ok
    }

    override func keyDown(with event: NSEvent) {
        guard let workspace else { return }
        _ = KeyRouter.handle(event, workspace: workspace)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            workspace?.active.model.spaceHeld = false
            if workspace?.active.model.livePaths.isEmpty == false {
                workspace?.active.model.updateLiveModifiers(
                    shift: event.modifierFlags.contains(.shift),
                    option: event.modifierFlags.contains(.option)
                )
            }
            needsDisplay = true
            return
        }
    }

    override func flagsChanged(with event: NSEvent) {
        workspace?.active.model.updateLiveModifiers(
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option)
        )
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard let model = workspace?.active.model else { return }
        model.viewportSize = Vec2(Double(bounds.width), Double(bounds.height))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model = workspace?.active.model else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(Theme.pasteboard.cgColor)
        context.fill(bounds)
        var options = DrawOptions()
        options.outline = model.outline
        options.showArtboards = model.showArtboards
        options.showEdges = model.showEdges
        options.showBoundingBox = model.showBoundingBox
        options.showGuides = model.showGuides
        options.showGrid = model.showGrid
        options.transparencyGrid = model.transparencyGrid
        options.showPerspective = model.showPerspective
        options.perspectivePlane = model.perspectivePlane
        options.overprintPreview = model.overprintPreview
        options.zoom = model.zoom
        options.pan = model.pan
        options.viewport = model.viewportSize
        options.selection = model.selection
        options.selectedAnchors = model.selectedAnchors
        options.tool = model.tool
        options.penNodes = model.penNodes
        options.hover = model.hover
        options.hint = model.interactionHint
        options.showAnchors = model.showAnchors
        options.showHandles = model.showHandles
        options.rubberBand = model.rubberBand
        options.livePaths = model.livePaths
        options.liveOutline = model.liveOutline
        options.perspective = model.perspectiveGrid
        options.glyphNudge = model.glyphNudge
        context.saveGState()
        CanvasDrawing.draw(model.document, options: options, in: context, size: bounds.size)
        context.restoreGState()
        drawArtboardLabel(model)
        drawMeasure(model)
        if model.showRulers { drawRulers(model, in: context) }
    }

    private func drawMeasure(_ model: EditorModel) {
        guard !model.liveLabel.isEmpty else { return }
        let viewX = (model.liveAnchor.x - model.pan.x) * model.zoom + 16
        let viewY = bounds.height - (model.liveAnchor.y - model.pan.y) * model.zoom + 16
        let text = model.liveLabel as NSString
        let font = NSFont.systemFont(ofSize: 11)
        let size = text.size(withAttributes: [.font: font])
        var rect = NSRect(x: viewX, y: viewY, width: size.width + 12, height: size.height + 6)
        if rect.maxX > bounds.width - 4 { rect.origin.x = bounds.width - rect.width - 4 }
        if rect.maxY > bounds.height - 4 { rect.origin.y = bounds.height - rect.height - 4 }
        NSColor(calibratedWhite: 0.32, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        text.draw(at: NSPoint(x: rect.minX + 6, y: rect.minY + 3), withAttributes: [
            .font: font, .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 1)
        ])
    }

    private func drawArtboardLabel(_ model: EditorModel) {
        guard model.document.artboards.indices.contains(model.document.activeArtboard) else { return }
        let board = model.document.artboards[model.document.activeArtboard]
        let index = model.document.activeArtboard + 1
        let label = String(format: "%02d - %@", index, board.name) as NSString
        let viewX = (board.rect.x - model.pan.x) * model.zoom
        let top = bounds.height - (board.rect.y - model.pan.y) * model.zoom
        label.draw(at: NSPoint(x: viewX, y: top + 4), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: Theme.dim
        ])
    }

    private func drawRulers(_ model: EditorModel, in context: CGContext) {
        let thickness: CGFloat = 18
        context.setFillColor(Theme.chrome.cgColor)
        context.fill(CGRect(x: 0, y: bounds.height - thickness, width: bounds.width, height: thickness))
        context.fill(CGRect(x: 0, y: 0, width: thickness, height: bounds.height))
        context.setFillColor(Theme.dim.cgColor)
        let step = max(32.0, (50 / model.zoom).rounded())
        var x = (model.pan.x / step).rounded(.down) * step
        let limitX = model.pan.x + Double(bounds.width) / model.zoom
        while x < limitX {
            let viewX = (x - model.pan.x) * model.zoom
            let label = String(Int(x.rounded())) as NSString
            label.draw(at: NSPoint(x: CGFloat(viewX + 2), y: bounds.height - 14), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: Theme.dim])
            x += step
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    private var cursor: NSCursor {
        switch workspace?.active.model.tool {
        case .hand: return .openHand
        case .zoom: return .crosshair
        case .text, .areaText, .verticalText, .pathText, .touchType: return .iBeam
        case .pen, .curvature, .addAnchor, .deleteAnchor, .convertAnchor: return .crosshair
        default: return .arrow
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model = workspace?.active.model else { return }
        panAtDown = model.pan
        let before = documentPoint(event, pan: model.pan)
        let oldZoom = model.zoom
        model.pointerDown(at: before, shift: event.modifierFlags.contains(.shift), option: event.modifierFlags.contains(.option), command: event.modifierFlags.contains(.command), space: model.spaceHeld, stylus: stylus(event), clickCount: event.clickCount)
        if model.tool == .zoom, abs(model.zoom - oldZoom) > 0.0001 {
            let loc = convert(event.locationInWindow, from: nil)
            model.pan = Vec2(
                before.x - Double(loc.x) / model.zoom,
                before.y - (Double(bounds.height) - Double(loc.y)) / model.zoom
            )
        }
        needsDisplay = true
        workspace?.touch()
    }

    override func mouseMoved(with event: NSEvent) {
        guard let model = workspace?.active.model else { return }
        model.pointerMove(to: documentPoint(event, pan: model.pan))
        let penLike: Set<Tool> = [.pen, .curvature, .addAnchor, .deleteAnchor, .convertAnchor]
        if penLike.contains(model.tool), !model.penNodes.isEmpty || model.rubberBand {
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model = workspace?.active.model else { return }
        let pan = model.tool == .hand ? panAtDown : model.pan
        let point = documentPoint(event, pan: pan)
        model.pointerDrag(to: point, shift: event.modifierFlags.contains(.shift), option: event.modifierFlags.contains(.option), command: event.modifierFlags.contains(.command), space: model.spaceHeld, stylus: stylus(event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let model = workspace?.active.model else { return }
        let pan = model.tool == .hand ? panAtDown : model.pan
        let point = documentPoint(event, pan: pan)
        let oldZoom = model.zoom
        model.pointerUp(at: point, shift: event.modifierFlags.contains(.shift), option: event.modifierFlags.contains(.option), command: event.modifierFlags.contains(.command), space: model.spaceHeld, stylus: stylus(event))
        if model.tool == .zoom, abs(model.zoom - oldZoom) > 0.0001 {
            let loc = convert(event.locationInWindow, from: nil)
            model.pan = Vec2(
                point.x - Double(loc.x) / model.zoom,
                point.y - (Double(bounds.height) - Double(loc.y)) / model.zoom
            )
        }
        needsDisplay = true
        workspace?.touch()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let model = workspace?.active.model else { return }
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            zoom(by: event.scrollingDeltaY > 0 ? 1.06 : 0.94, around: convert(event.locationInWindow, from: nil))
        } else {
            model.pan.x -= Double(event.scrollingDeltaX) / model.zoom
            model.pan.y -= Double(event.scrollingDeltaY) / model.zoom
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + Double(event.magnification), around: convert(event.locationInWindow, from: nil))
    }

    private func zoom(by factor: Double, around loc: NSPoint) {
        guard let model = workspace?.active.model else { return }
        let before = documentPoint(viewPoint: loc, pan: model.pan, zoom: model.zoom)
        model.zoom = min(64, max(0.02, model.zoom * factor))
        model.pan = Vec2(
            before.x - Double(loc.x) / model.zoom,
            before.y - (Double(bounds.height) - Double(loc.y)) / model.zoom
        )
        model.status = "\(Int(model.zoom * 100))%"
        needsDisplay = true
        workspace?.touch()
    }

    private func stylus(_ event: NSEvent) -> StylusSample {
        let tilt = event.tilt
        let bearing = atan2(Double(tilt.y), Double(tilt.x))
        let magnitude = min(1, hypot(Double(tilt.x), Double(tilt.y)))
        return StylusSample(
            pressure: Double(event.pressure),
            tilt: magnitude,
            bearing: bearing,
            rotation: Double(event.rotation),
            wheel: min(1, max(0, Double(event.tangentialPressure) * 0.5 + 0.5))
        )
    }

    private func documentPoint(_ event: NSEvent, pan: Vec2) -> Vec2 {
        documentPoint(viewPoint: convert(event.locationInWindow, from: nil), pan: pan, zoom: workspace?.active.model.zoom ?? 1)
    }

    private func documentPoint(viewPoint: NSPoint, pan: Vec2, zoom: Double) -> Vec2 {
        Vec2(
            Double(viewPoint.x) / zoom + pan.x,
            (Double(bounds.height) - Double(viewPoint.y)) / zoom + pan.y
        )
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let workspace, let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else { return false }
        for url in urls { workspace.open(url: url, place: true) }
        return true
    }
}
