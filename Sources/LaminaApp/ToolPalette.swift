import AppKit
import LaminaCore

final class ToolButton: NSView {
    var tool: Tool = .selection
    var group: [Tool] = []
    var chartKinds: [ChartKind] = []
    var warpKinds: [WarpToolKind] = []
    var symbolKinds: [SymbolToolKind] = []
    var isCurrent = false
    var onSelect: ((Tool) -> Void)?
    var onChart: ((ChartKind) -> Void)?
    var onWarp: ((WarpToolKind) -> Void)?
    var onSymbol: ((SymbolToolKind) -> Void)?
    var onOptions: (() -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        if isCurrent {
            Theme.accent.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }
        let symbol = ToolSymbol.image(for: tool)
        let tint: NSColor = isCurrent ? .white : Theme.text
        if let symbol {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let image = symbol.withSymbolConfiguration(config) ?? symbol
            image.isTemplate = true
            tint.set()
            let side: CGFloat = 16
            image.draw(in: NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            let title = String(tool.title.prefix(1)) as NSString
            title.draw(at: NSPoint(x: 10, y: 8), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: tint])
        }
        if group.count > 1 || !chartKinds.isEmpty || !warpKinds.isEmpty || !symbolKinds.isEmpty {
            Theme.dim.setFill()
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: bounds.maxX - 7, y: bounds.maxY - 5))
            mark.line(to: NSPoint(x: bounds.maxX - 4, y: bounds.maxY - 5))
            mark.line(to: NSPoint(x: bounds.maxX - 5.5, y: bounds.maxY - 3))
            mark.close()
            mark.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let until = Date().addingTimeInterval(0.35)
        var released = false
        while Date() < until {
            guard let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: until, inMode: .eventTracking, dequeue: true) else { break }
            if next.type == .leftMouseUp {
                released = true
                break
            }
        }
        if event.clickCount >= 2 {
            onOptions?()
            return
        }
        if !released, group.count > 1 || !chartKinds.isEmpty || !warpKinds.isEmpty || !symbolKinds.isEmpty {
            popFlyout()
        } else {
            onSelect?(tool)
        }
    }

    private func popFlyout() {
        let menu = NSMenu()
        if !chartKinds.isEmpty {
            for kind in chartKinds {
                let item = NSMenuItem(title: kind.title, action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = "chart:\(kind.rawValue)"
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: bounds.width + 4, y: 4), in: self)
            return
        }
        if !warpKinds.isEmpty {
            for kind in warpKinds {
                let item = NSMenuItem(title: kind.title, action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = "warp:\(kind.rawValue)"
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: bounds.width + 4, y: 4), in: self)
            return
        }
        if !symbolKinds.isEmpty {
            for kind in symbolKinds {
                let item = NSMenuItem(title: kind.title, action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = "symbol:\(kind.rawValue)"
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: bounds.width + 4, y: 4), in: self)
            return
        }
        for candidate in group {
            let item = NSMenuItem(title: candidate.title, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.rawValue
            item.state = candidate == tool ? .on : .off
            if let image = ToolSymbol.image(for: candidate) {
                item.image = image
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.width + 4, y: 4), in: self)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        if raw.hasPrefix("chart:"), let kind = ChartKind(rawValue: String(raw.dropFirst("chart:".count))) {
            onChart?(kind)
            return
        }
        if raw.hasPrefix("warp:"), let kind = WarpToolKind(rawValue: String(raw.dropFirst("warp:".count))) {
            onWarp?(kind)
            return
        }
        if raw.hasPrefix("symbol:"), let kind = SymbolToolKind(rawValue: String(raw.dropFirst("symbol:".count))) {
            onSymbol?(kind)
            return
        }
        guard let tool = Tool(rawValue: raw) else { return }
        onSelect?(tool)
    }
}

enum ToolSymbol {
    static func image(for tool: Tool) -> NSImage? {
        let name: String
        switch tool {
        case .selection: name = "arrow.up.left"
        case .directSelection: name = "cursorarrow"
        case .groupSelection: name = "square.on.square"
        case .magicWand: name = "wand.and.stars"
        case .lasso: name = "lasso"
        case .pen: name = "pencil.tip"
        case .addAnchor: name = "plus"
        case .deleteAnchor: name = "minus"
        case .convertAnchor: name = "point.topleft.down.to.point.bottomright.curvepath"
        case .curvature: name = "scribble.variable"
        case .text, .touchType: name = "textformat"
        case .areaText: name = "text.alignleft"
        case .pathText: name = "text.below.line"
        case .verticalText: name = "textformat.size"
        case .line: name = "line.diagonal"
        case .arc: name = "point.topleft.down.curvedto.point.bottomright.up"
        case .spiral: name = "hurricane"
        case .rectGrid: name = "rectangle.split.3x3"
        case .polarGrid: name = "circle.grid.cross"
        case .rectangle: name = "rectangle"
        case .roundedRectangle: name = "rectangle.roundedtop"
        case .ellipse: name = "circle"
        case .polygon: name = "pentagon"
        case .star: name = "star"
        case .flare: name = "sun.max"
        case .brush: name = "paintbrush.pointed"
        case .blobBrush: name = "paintbrush"
        case .shaper: name = "scribble"
        case .pencil: name = "pencil"
        case .smooth: name = "waveform.path"
        case .pathEraser: name = "eraser"
        case .joinTool: name = "point.3.connected.trianglepath.dotted"
        case .eraser: name = "eraser.fill"
        case .scissors: name = "scissors"
        case .knife: name = "line.diagonal.arrow"
        case .rotate: name = "rotate.right"
        case .reflect: name = "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .scale: name = "arrow.up.left.and.arrow.down.right"
        case .shear: name = "skew"
        case .reshape: name = "point.topleft.down.to.point.bottomright.filled.curvepath"
        case .width: name = "lineweight"
        case .warp: name = "trapezoid.and.line.horizontal"
        case .freeTransform: name = "crop"
        case .puppet: name = "figure.walk"
        case .shapeBuilder: name = "square.on.circle"
        case .livePaintBucket: name = "paintbucket"
        case .livePaintSelection: name = "hand.point.up.left"
        case .perspectiveGrid: name = "grid"
        case .perspectiveSelection: name = "square.grid.3x3"
        case .mesh: name = "circle.hexagongrid"
        case .gradient: name = "circle.lefthalf.filled"
        case .eyedropper: name = "eyedropper"
        case .measure: name = "ruler"
        case .blend: name = "circle.dotted"
        case .symbolSprayer: name = "sparkles"
        case .columnGraph: name = "chart.bar"
        case .artboard: name = "rectangle.dashed"
        case .slice: name = "scissors"
        case .hand: name = "hand.raised"
        case .rotateView: name = "rotate.3d"
        case .zoom: name = "plus.magnifyingglass"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: tool.title)
    }
}

final class FillStrokeControl: NSView {
    var fill: Paint?
    var stroke: Paint?
    var fillActive = true
    var onFill: (() -> Void)?
    var onStroke: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let strokeRect = NSRect(x: 14, y: 6, width: 22, height: 22)
        let fillRect = NSRect(x: 4, y: 16, width: 22, height: 22)
        strokeSquare(strokeRect, paint: stroke, active: !fillActive)
        strokeSquare(fillRect, paint: fill, active: fillActive)
    }

    private func strokeSquare(_ rect: NSRect, paint: Paint?, active: Bool) {
        let path = NSBezierPath(rect: rect)
        NSColor.white.setFill()
        path.fill()
        if let paint, case .solid(let color) = paint {
            color.nsColor.setFill()
            path.fill()
        } else if paint != nil {
            Theme.accent.setFill()
            path.fill()
        } else {
            NSColor.white.setFill()
            path.fill()
            NSColor.systemRed.setStroke()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 3, y: rect.minY + 3))
            slash.line(to: NSPoint(x: rect.maxX - 3, y: rect.maxY - 3))
            slash.lineWidth = 1.5
            slash.stroke()
        }
        (active ? Theme.accent : NSColor.black.withAlphaComponent(0.45)).setStroke()
        path.lineWidth = active ? 2 : 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y > 16 { onFill?() } else { onStroke?() }
    }
}

final class ToolPalette: NSView {
    weak var workspace: Workspace?
    private let scroll = NSScrollView()
    private let column = NSView()
    private let fillControl = FillStrokeControl()
    private var buttons: [ToolButton] = []
    private var remembered: [String: Tool] = [:]
    private var advanced = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.chrome.cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = column
        addSubview(scroll)
        addSubview(fillControl)
        fillControl.onFill = { [weak self] in self?.activateFill(true) }
        fillControl.onStroke = { [weak self] in self?.activateFill(false) }
        fillControl.toolTip = "填色 / 描边   X 切换   D 默认   ⇧X 互换   < 颜色   > 渐变   / 无"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        fillControl.frame = NSRect(x: 4, y: 8, width: bounds.width - 8, height: 44)
        scroll.frame = NSRect(x: 0, y: 58, width: bounds.width, height: bounds.height - 66)
        let height = CGFloat(buttons.count) * 34 + 8
        column.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(height, scroll.contentSize.height))
        var y = column.bounds.height - 36
        for button in buttons {
            button.frame = NSRect(x: (column.bounds.width - 32) / 2, y: y, width: 32, height: 32)
            y -= 34
        }
    }

    func sync() {
        guard let model = workspace?.active.model else { return }
        if advanced != model.toolbarAdvanced || buttons.isEmpty {
            advanced = model.toolbarAdvanced
            rebuild(model)
        }
        let groups = advanced ? ToolGroups.advanced : ToolGroups.basic
        for (index, button) in buttons.enumerated() where index < groups.count {
            let group = groups[index]
            if group.contains(model.tool) {
                remembered[groupKey(group)] = model.tool
                button.tool = model.tool
            }
            button.isCurrent = group.contains(model.tool)
            button.needsDisplay = true
        }
        fillControl.fill = model.currentFill
        fillControl.stroke = model.currentStroke?.paint
        fillControl.fillActive = model.activeAttrIsFill
        fillControl.needsDisplay = true
        needsLayout = true
    }

    private func rebuild(_ model: EditorModel) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        let groups = model.toolbarAdvanced ? ToolGroups.advanced : ToolGroups.basic
        for group in groups {
            let button = ToolButton()
            button.group = group
            button.tool = remembered[groupKey(group)] ?? group[0]
            if group.contains(model.tool) { button.tool = model.tool }
            button.chartKinds = group == [.columnGraph] ? ChartKind.allCases : []
            button.warpKinds = group == [.warp] ? WarpToolKind.allCases : []
            button.symbolKinds = group == [.symbolSprayer] ? SymbolToolKind.allCases : []
            if !button.chartKinds.isEmpty { button.toolTip = "图表  \(model.chartKind.title)" }
            else if !button.warpKinds.isEmpty { button.toolTip = "变形  \(model.warpKind.title)" }
            else if !button.symbolKinds.isEmpty { button.toolTip = model.symbolKind.title }
            else { button.toolTip = tip(button.tool) }
            button.onSelect = { [weak self] tool in
                guard let self, let model = self.workspace?.active.model else { return }
                self.remembered[self.groupKey(group)] = tool
                model.tool = tool
                model.status = tool.title
                self.workspace?.touch()
            }
            button.onChart = { [weak self] kind in
                guard let model = self?.workspace?.active.model else { return }
                model.chartKind = kind
                model.tool = .columnGraph
                model.status = kind.title
                self?.workspace?.touch()
            }
            button.onWarp = { [weak self] kind in
                guard let model = self?.workspace?.active.model else { return }
                model.warpKind = kind
                model.tool = .warp
                model.status = kind.title
                self?.workspace?.touch()
            }
            button.onSymbol = { [weak self] kind in
                guard let model = self?.workspace?.active.model else { return }
                model.symbolKind = kind
                model.tool = .symbolSprayer
                model.status = kind.title
                self?.workspace?.touch()
            }
            button.onOptions = { [weak self] in
                guard let model = self?.workspace?.active.model else { return }
                model.tool = button.tool
                model.requestToolOptions()
                self?.workspace?.touch()
            }
            column.addSubview(button)
            buttons.append(button)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        if column.frame.height > clip.bounds.height {
            clip.scroll(to: NSPoint(x: 0, y: column.frame.height - clip.bounds.height))
            scroll.reflectScrolledClipView(clip)
        }
    }

    private func activateFill(_ fill: Bool) {
        guard let model = workspace?.active.model else { return }
        model.activeAttrIsFill = fill
        model.status = fill ? "填色" : "描边"
        workspace?.touch()
    }

    private func groupKey(_ group: [Tool]) -> String { group.map(\.rawValue).joined(separator: "|") }

    private func tip(_ tool: Tool) -> String {
        let title = Keymap.toolForTitle.first { $0.value == tool }?.key
        if let title, let chord = Keymap.chords(forTitle: title).first {
            return "\(tool.title)  \(chord.display)"
        }
        return tool.title
    }
}

enum ToolGroups {
    static let advanced: [[Tool]] = [
        [.selection, .directSelection, .groupSelection],
        [.magicWand, .lasso],
        [.pen, .addAnchor, .deleteAnchor, .convertAnchor],
        [.curvature],
        [.text, .areaText, .pathText, .verticalText, .touchType],
        [.line, .arc, .spiral, .rectGrid, .polarGrid],
        [.rectangle, .roundedRectangle, .ellipse, .polygon, .star, .flare],
        [.brush, .blobBrush],
        [.shaper, .pencil, .smooth, .pathEraser, .joinTool],
        [.eraser, .scissors, .knife],
        [.rotate, .reflect],
        [.scale, .shear, .reshape],
        [.width, .warp],
        [.freeTransform, .puppet],
        [.shapeBuilder, .livePaintBucket, .livePaintSelection],
        [.perspectiveGrid, .perspectiveSelection],
        [.mesh],
        [.gradient],
        [.eyedropper, .measure],
        [.blend],
        [.symbolSprayer],
        [.columnGraph],
        [.artboard],
        [.slice],
        [.hand, .rotateView],
        [.zoom]
    ]

    static let basic: [[Tool]] = [
        [.selection, .directSelection, .groupSelection],
        [.pen, .addAnchor, .deleteAnchor, .convertAnchor, .curvature],
        [.text, .areaText, .pathText],
        [.line, .rectangle, .roundedRectangle, .ellipse, .polygon, .star],
        [.hand],
        [.zoom]
    ]
}
