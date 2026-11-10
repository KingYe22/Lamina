import AppKit
import LaminaCore

struct DockedColumn {
    var id: String
    var width: CGFloat
    var place: DockPlace
}

extension NSView {
    var editorShell: EditorShell? {
        var view: NSView? = self
        while let current = view {
            if let shell = current as? EditorShell { return shell }
            view = current.superview
        }
        return nil
    }
}

/// Blue docking chrome, in a window above floating panels and the floating toolbar.
///
/// Tint alpha 0.20 and the outline's 2 pt stroke were not in the capture.
/// The bar color, the 6 pt thickness, and the bar's rectangle were.
final class DockIndicatorCanvas: NSView {
    enum Piece {
        case fill(NSRect, CGFloat)
        case stroke(NSRect)
    }

    var pieces: [Piece] = []

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // One device-RGB source for every piece. The right bar, the toolbar-right
        // bar, and the window-edge bar are all steps from DockBarDrawing.
        let space = CGColorSpaceCreateDeviceRGB()
        context.setFillColorSpace(space)
        context.setStrokeColorSpace(space)
        for piece in pieces {
            switch piece {
            case .fill(let rect, let alpha):
                guard !rect.isEmpty else { continue }
                setDeviceColor(context, alpha: alpha)
                context.fill(rect)
            case .stroke(let rect):
                guard rect.width > 2, rect.height > 2 else { continue }
                setDeviceColor(context, alpha: 1)
                context.setLineWidth(CGFloat(2))
                context.stroke(rect.insetBy(dx: 1, dy: 1))
            }
        }
    }

    private func setDeviceColor(_ context: CGContext, alpha: CGFloat) {
        let paint = DockBarDrawing.source(alpha: Double(alpha))
        context.setFillColor(
            red: CGFloat(paint.red),
            green: CGFloat(paint.green),
            blue: CGFloat(paint.blue),
            alpha: CGFloat(paint.alpha)
        )
        context.setStrokeColor(
            red: CGFloat(paint.red),
            green: CGFloat(paint.green),
            blue: CGFloat(paint.blue),
            alpha: CGFloat(paint.alpha)
        )
    }
}

/// Non-activating, click-through. `.popUpMenu` sits above the floating toolbar panel.
final class DockIndicatorPanel: NSPanel {
    let canvas = DockIndicatorCanvas()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        colorSpace = NSColorSpace.deviceRGB
        contentView = canvas
        canvas.wantsLayer = false
        canvas.frame = contentView?.bounds ?? .zero
        canvas.autoresizingMask = [.width, .height]
    }

    func present(screen: NSRect, pieces: [DockIndicatorCanvas.Piece]) {
        colorSpace = .deviceRGB
        setFrame(screen, display: false)
        canvas.pieces = pieces
        canvas.needsDisplay = true
        orderFrontRegardless()
    }

    func conceal() {
        canvas.pieces = []
        orderOut(nil)
    }
}
