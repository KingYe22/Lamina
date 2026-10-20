import AppKit
import LaminaCore

struct NewDocSpec {
    var name: String
    var width: Double
    var height: Double
    var unit: UnitKind
    var colorMode: ColorMode
    var artboards: Int
    var bleed: Double
    var raster: Double
    var portrait: Bool

    func pointSize() -> Vec2 {
        let w = portrait ? width : height
        let h = portrait ? height : width
        func pts(_ value: Double) -> Double {
            switch unit {
            case .pt: return value
            case .mm: return value * 72.0 / 25.4
            case .inch: return value * 72.0
            case .px: return value
            }
        }
        return Vec2(max(1, pts(w)), max(1, pts(h)))
    }
}

final class AppRoot: NSView {
    let workspace: Workspace
    let home = HomeView()
    let editor: EditorShell
    let dialog = NewDocumentDialog()
    private(set) var showingEditor = false

    init(workspace: Workspace) {
        self.workspace = workspace
        editor = EditorShell(workspace: workspace)
        super.init(frame: .zero)
        home.workspace = workspace
        dialog.onClose = { [weak self] in self?.dialog.isHidden = true }
        dialog.onCreate = { [weak self] spec in
            self?.create(spec)
        }
        home.onNew = { [weak self] in self?.showDialog() }
        home.onOpen = { [weak self] in self?.workspace.perform("打开文档") }
        addSubview(home)
        addSubview(editor)
        addSubview(dialog)
        editor.isHidden = true
        dialog.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        home.frame = bounds
        editor.frame = bounds
        dialog.frame = bounds
    }

    func showHome() {
        showingEditor = false
        home.isHidden = false
        editor.isHidden = true
        home.needsDisplay = true
        window?.makeFirstResponder(nil)
    }

    func showEditor() {
        showingEditor = true
        home.isHidden = true
        editor.isHidden = false
        dialog.isHidden = true
        editor.sync()
        window?.makeFirstResponder(editor.canvas.drawing)
    }

    func showDialog() {
        dialog.isHidden = false
        dialog.syncPresets()
    }

    func create(_ spec: NewDocSpec) {
        layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let session = workspace.active
        session.model.viewportSize = Vec2(Double(editor.canvas.bounds.width), Double(max(editor.canvas.bounds.height, 400)))
        session.model.newDocument(
            size: spec.pointSize(),
            title: spec.name.isEmpty ? "未标题-1" : spec.name,
            colorMode: spec.colorMode,
            units: spec.unit,
            artboardCount: max(1, spec.artboards),
            rasterPPI: spec.raster,
            zoomTo: 1.0 / 3.0
        )
        showEditor()
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.window.setFill()
        bounds.fill()
    }
}

final class DocumentTabBar: NSView {
    weak var workspace: Workspace?

    override func draw(_ dirtyRect: NSRect) {
        Theme.window.setFill()
        bounds.fill()
        guard let model = workspace?.active.model else { return }
        let zoom = String(format: "%.2f%%", model.zoom * 100)
        let mode = model.document.colorMode == .cmyk ? "CMYK" : "RGB"
        let preview = model.outline ? "轮廓" : "预览"
        let title = "\(model.document.title) @ \(zoom) (\(mode)/\(preview))" as NSString
        let font = NSFont.systemFont(ofSize: 12)
        let size = title.size(withAttributes: [.font: font])
        let rect = NSRect(x: 12, y: 4, width: size.width + 28, height: bounds.height - 6)
        Theme.pasteboard.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        title.draw(at: NSPoint(x: rect.minX + 12, y: rect.midY - 7), withAttributes: [
            .font: font, .foregroundColor: Theme.text
        ])
    }
}

final class IllustratorStatusBar: NSView {
    weak var workspace: Workspace?

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        Theme.line.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)).fill()
        guard let model = workspace?.active.model else { return }
        let hint = Self.hint(for: model.tool) as NSString
        hint.draw(at: NSPoint(x: 10, y: 6), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.dim
        ])
        let zoom = String(format: "%.2f%%", model.zoom * 100)
        let boards = max(model.document.artboards.count, 1)
        let index = min(model.document.activeArtboard + 1, boards)
        let right = "\(zoom) ▾    0°    ‹ \(index) / \(boards) ›    \(model.tool.title)" as NSString
        let font = NSFont.systemFont(ofSize: 11)
        let size = right.size(withAttributes: [.font: font])
        right.draw(at: NSPoint(x: bounds.width - size.width - 12, y: 6), withAttributes: [
            .font: font, .foregroundColor: Theme.text
        ])
    }

    override func mouseDown(with event: NSEvent) {
        guard let workspace else { return }
        let x = convert(event.locationInWindow, from: nil).x
        if x > bounds.width - 70 { return }
        if x > bounds.width - 160 { workspace.perform("画板适合窗口大小") }
    }

    private static func hint(for tool: Tool) -> String {
        switch tool {
        case .selection: return "选择工具：单击以选择对象。按住空格拖移可平移画布。"
        case .directSelection: return "直接选择工具：单击锚点或路径段。"
        case .pen: return "钢笔工具：单击以放置锚点，拖移以拉出手柄。"
        case .text: return "文字工具：单击画板以输入点文字。"
        case .zoom: return "缩放工具：单击放大，按住 Option 单击缩小。"
        case .hand: return "抓手工具：拖移以平移画布。"
        default: return "\(tool.title)：在画板上单击或拖移。按住空格可临时平移。"
        }
    }
}

final class ContextBar: NSView {
    weak var workspace: Workspace?

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        Theme.line.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()
        let tool = workspace?.active.model.tool.title ?? "选择"
        let title = "上下文    \(tool)    属性    对齐    路径查找器" as NSString
        title.draw(at: NSPoint(x: 12, y: 7), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.text
        ])
    }
}

final class FloatingPanels: NSView {
    weak var workspace: Workspace?
    private var alignPage = true
    private var strokePage = true

    override var isFlipped: Bool { true }

    func sync() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        var y: CGFloat = 0
        y = card(title: "外观", y: y, height: 92) { rect in
            let lines = ["未选择对象", "描边    1 pt", "填色", "不透明度：默认值"]
            self.lines(lines, in: rect)
        }
        y += 8
        y = card(title: alignPage ? "变换    对齐    路径查找器" : "变换    对齐    路径查找器", y: y, height: 148) { rect in
            self.section("对齐对象", y: rect.minY + 8)
            self.iconRow(["左", "中", "右", "上", "中", "下"], y: rect.minY + 24)
            self.section("分布对象", y: rect.minY + 50)
            self.iconRow(["横", "纵"], y: rect.minY + 66)
            self.section("分布间距", y: rect.minY + 92)
            self.iconRow(["间距横", "间距纵"], y: rect.minY + 108)
        }
        y += 8
        _ = card(title: "描边    透明度", y: y, height: 168) { rect in
            let rows = ["粗细    1 pt", "端点    平头    圆头    方头", "边角    尖角    圆角    斜角", "限制    4", "对齐描边    居中", "虚线    关", "箭头    无", "配置文件    均匀"]
            self.lines(rows, in: rect)
        }
    }

    private func card(title: String, y: CGFloat, height: CGFloat, body: (NSRect) -> Void) -> CGFloat {
        let rect = NSRect(x: 0, y: y, width: bounds.width, height: height)
        Theme.panel.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        (title as NSString).draw(at: NSPoint(x: 8, y: rect.minY + 6), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: Theme.text
        ])
        body(NSRect(x: rect.minX + 8, y: rect.minY + 24, width: rect.width - 16, height: rect.height - 30))
        return rect.maxY
    }

    private func lines(_ rows: [String], in rect: NSRect) {
        var y = rect.minY
        for row in rows {
            (row as NSString).draw(at: NSPoint(x: rect.minX, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.dim
            ])
            y += 16
        }
    }

    private func section(_ title: String, y: CGFloat) {
        (title as NSString).draw(at: NSPoint(x: 8, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: Theme.dim
        ])
    }

    private func iconRow(_ titles: [String], y: CGFloat) {
        var x: CGFloat = 8
        for title in titles {
            let rect = NSRect(x: x, y: y, width: 28, height: 18)
            Theme.raised.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            let font = NSFont.systemFont(ofSize: 9)
            let size = (title as NSString).size(withAttributes: [.font: font])
            (title as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: [
                .font: font, .foregroundColor: Theme.text
            ])
            x += 30
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let workspace else { return }
        let point = convert(event.locationInWindow, from: nil)
        if point.y < 250 {
            let titles = ["水平左对齐", "水平居中对齐", "水平右对齐", "垂直顶对齐", "垂直居中对齐", "垂直底对齐"]
            let index = Int((point.x - 8) / 30)
            if titles.indices.contains(index), point.y > 110, point.y < 160 {
                workspace.perform(titles[index])
            }
        }
    }
}

final class PropertiesDock: NSView {
    weak var workspace: Workspace?
    private let tabs = ["属性", "注释", "图层", "库"]
    private var tab = "属性"

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    func sync() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        var x: CGFloat = 8
        for name in tabs {
            let font = NSFont.systemFont(ofSize: 12, weight: name == tab ? .semibold : .regular)
            let color = name == tab ? Theme.text : Theme.dim
            (name as NSString).draw(at: NSPoint(x: x, y: 8), withAttributes: [.font: font, .foregroundColor: color])
            if name == tab {
                Theme.accent.setFill()
                NSBezierPath(rect: NSRect(x: x, y: 26, width: name.count > 2 ? 28 : 24, height: 2)).fill()
            }
            x += 52
        }
        guard tab == "属性", let model = workspace?.active.model else {
            let note = tab == "图层" ? layerText() : "\(tab) 为空"
            (note as NSString).draw(at: NSPoint(x: 12, y: 48), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.dim
            ])
            return
        }
        let unit: String
        switch model.document.units {
        case .mm: unit = "毫米"
        case .pt: unit = "点"
        case .px: unit = "像素"
        case .inch: unit = "英寸"
        }
        let board = model.document.artboards.indices.contains(model.document.activeArtboard)
            ? model.document.artboards[model.document.activeArtboard].name
            : "画板 1"
        let blocks = [
            "未选择对象",
            "",
            "文档",
            "单位    \(unit)",
            "画板    \(board)",
            "编辑画板",
            "",
            "标尺与网格",
            "显示标尺    \(model.showRulers ? "开" : "关")",
            "显示网格    \(model.showGrid ? "开" : "关")",
            "",
            "参考线",
            "显示参考线    \(model.showGuides ? "开" : "关")",
            "锁定参考线    \(model.lockGuides ? "开" : "关")",
            "",
            "对齐选项",
            "对齐网格    \(model.snapGrid ? "开" : "关")",
            "对齐点    \(model.snapPoint ? "开" : "关")",
            "智能参考线    \(model.smartGuides ? "开" : "关")",
            "",
            "首选项",
            "键盘增量    \(Int(model.nudge))",
            "使用预览边界",
            "缩放圆角",
            "缩放描边和效果",
            "",
            "快速操作",
            "文档设置",
            "首选项"
        ]
        var y: CGFloat = 40
        for line in blocks {
            let font = line == "文档" || line == "标尺与网格" || line == "参考线" || line == "对齐选项" || line == "首选项" || line == "快速操作"
                ? NSFont.systemFont(ofSize: 11, weight: .semibold)
                : NSFont.systemFont(ofSize: 12)
            (line as NSString).draw(at: NSPoint(x: 12, y: y), withAttributes: [.font: font, .foregroundColor: Theme.text])
            y += line.isEmpty ? 8 : 18
        }
    }

    private func layerText() -> String {
        guard let layers = workspace?.active.model.document.layers else { return "图层" }
        return layers.map(\.name).joined(separator: "\n")
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y < 32 {
            let index = Int((point.x - 8) / 52)
            if tabs.indices.contains(index) { tab = tabs[index]; needsDisplay = true }
            return
        }
        guard let workspace else { return }
        let title = textLine(at: point)
        switch title {
        case "编辑画板": workspace.active.model.tool = .artboard
        case "显示标尺    开", "显示标尺    关": workspace.perform("显示标尺")
        case "显示网格    开", "显示网格    关": workspace.perform("显示网格")
        case "显示参考线    开", "显示参考线    关": workspace.perform("隐藏参考线")
        case "锁定参考线    开", "锁定参考线    关": workspace.perform("锁定参考线")
        case "对齐网格    开", "对齐网格    关": workspace.perform("对齐网格")
        case "对齐点    开", "对齐点    关": workspace.perform("对齐点")
        case "智能参考线    开", "智能参考线    关": workspace.perform("显示/隐藏智能参考线")
        case "文档设置": workspace.perform("打开“文档设置”对话框")
        case "首选项": workspace.perform("打开“偏好设置”对话框")
        default: break
        }
        workspace.touch()
    }

    private func textLine(at point: NSPoint) -> String {
        let lines = ["", "", "", "", "", "编辑画板"]
        let y0: CGFloat = 40
        let index = Int((point.y - y0) / 18)
        if index == 5 { return "编辑画板" }
        _ = lines
        let map: [(ClosedRange<CGFloat>, String)] = [
            (148...166, modelFlag("显示标尺")),
            (166...184, modelFlag("显示网格")),
            (210...228, modelFlag("显示参考线")),
            (228...246, modelFlag("锁定参考线")),
            (274...292, modelFlag("对齐网格")),
            (292...310, modelFlag("对齐点")),
            (310...328, modelFlag("智能参考线")),
            (418...436, "文档设置"),
            (436...454, "首选项")
        ]
        return map.first { $0.0.contains(point.y) }?.1 ?? ""
    }

    private func modelFlag(_ name: String) -> String { name }
}

final class HomeView: NSView {
    weak var workspace: Workspace?
    var onNew: (() -> Void)?
    var onOpen: (() -> Void)?
    private let newButton = NSButton(title: "新文件", target: nil, action: nil)
    private let openButton = NSButton(title: "打开", target: nil, action: nil)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        newButton.target = self
        newButton.action = #selector(pressNew)
        newButton.isBordered = false
        newButton.attributedTitle = NSAttributedString(string: "新文件", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
        ])
        openButton.target = self
        openButton.action = #selector(pressOpen)
        openButton.isBordered = false
        openButton.contentTintColor = Theme.text
        openButton.font = NSFont.systemFont(ofSize: 14)
        addSubview(newButton)
        addSubview(openButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        newButton.frame = NSRect(x: 24, y: 64, width: 172, height: 36)
        openButton.frame = NSRect(x: 24, y: 112, width: 80, height: 28)
    }

    @objc private func pressNew() { onNew?() }
    @objc private func pressOpen() { onOpen?() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.window.setFill()
        bounds.fill()
        let title = "Lamina" as NSString
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let size = title.size(withAttributes: [.font: font])
        title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: 8), withAttributes: [
            .font: font, .foregroundColor: Theme.text
        ])
        Theme.panel.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 28, width: 220, height: bounds.height - 28)).fill()
        Theme.homeBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: 24, y: 64, width: 172, height: 36), xRadius: 4, yRadius: 4).fill()
        ("最近使用项" as NSString).draw(at: NSPoint(x: 248, y: 56), withAttributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: Theme.text
        ])
        let recent = UserDefaults.standard.stringArray(forKey: Workspace.recentKey) ?? []
        let names = recent.isEmpty ? ["尚无最近使用的文件"] : recent.map { URL(fileURLWithPath: $0).lastPathComponent }
        let columns = 3
        for (index, name) in names.prefix(6).enumerated() {
            let col = index % columns
            let row = index / columns
            let rect = NSRect(x: 248 + CGFloat(col) * 180, y: 100 + CGFloat(row) * 170, width: 160, height: 150)
            Theme.raised.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: rect.minX + 28, y: rect.minY + 18, width: 104, height: 86)).fill()
            (name as NSString).draw(in: NSRect(x: rect.minX + 8, y: rect.maxY - 28, width: rect.width - 16, height: 20), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.text
            ])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if NSRect(x: 24, y: 64, width: 172, height: 36).contains(point) { onNew?() }
        else if NSRect(x: 24, y: 108, width: 80, height: 28).contains(point) { onOpen?() }
    }
}

final class NewDocumentDialog: NSView {
    var onCreate: ((NewDocSpec) -> Void)?
    var onClose: (() -> Void)?
    private let nameField = NSTextField(string: "未标题-1")
    private let widthField = NSTextField(string: "210")
    private let heightField = NSTextField(string: "297")
    private let bleedField = NSTextField(string: "0")
    private let countField = NSTextField(string: "1")
    private var unit: UnitKind = .mm
    private var mode: ColorMode = .cmyk
    private var portrait = true
    private var raster = 72.0
    private var preset = "A4"
    private let tabs = ["最近使用项", "已保存", "移动设备", "Web", "打印", "品牌", "社交媒体", "图稿和插图", "胶片和视频"]
    private var tab = "打印"
    private let card = NSView()
    private let closeButton = NSButton(title: "关闭", target: nil, action: nil)
    private let createButton = NSButton(title: "创建", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(card)
        card.wantsLayer = true
        card.layer?.backgroundColor = Theme.panel.cgColor
        card.layer?.cornerRadius = 8
        for field in [nameField, widthField, heightField, bleedField, countField] {
            field.font = NSFont.systemFont(ofSize: 12)
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            card.addSubview(field)
        }
        closeButton.target = self
        closeButton.action = #selector(pressClose)
        closeButton.isBordered = false
        createButton.target = self
        createButton.action = #selector(pressCreate)
        createButton.isBordered = false
        createButton.attributedTitle = NSAttributedString(string: "创建", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ])
        closeButton.attributedTitle = NSAttributedString(string: "关闭", attributes: [
            .foregroundColor: Theme.text,
            .font: NSFont.systemFont(ofSize: 13)
        ])
        card.addSubview(closeButton)
        card.addSubview(createButton)
    }

    @objc private func pressClose() { onClose?() }
    @objc private func pressCreate() { onCreate?(currentSpec()) }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func syncPresets() { needsDisplay = true }

    override func layout() {
        super.layout()
        card.frame = NSRect(x: (bounds.width - 860) / 2, y: (bounds.height - 560) / 2, width: 860, height: 560)
        nameField.frame = NSRect(x: 430, y: 470, width: 220, height: 24)
        widthField.frame = NSRect(x: 430, y: 400, width: 90, height: 24)
        heightField.frame = NSRect(x: 540, y: 400, width: 90, height: 24)
        countField.frame = NSRect(x: 430, y: 300, width: 80, height: 24)
        bleedField.frame = NSRect(x: 430, y: 250, width: 70, height: 24)
        closeButton.frame = NSRect(x: 640, y: 16, width: 90, height: 28)
        createButton.frame = NSRect(x: 740, y: 16, width: 96, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()
        guard card.frame.width > 0 else { return }
        drawCard()
    }

    private func drawCard() {
        let origin = card.frame.origin
        func text(_ string: String, _ x: CGFloat, _ y: CGFloat, bold: Bool = false, color: NSColor = Theme.text) {
            (string as NSString).draw(at: NSPoint(x: origin.x + x, y: origin.y + y), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: bold ? .semibold : .regular),
                .foregroundColor: color
            ])
        }
        var x: CGFloat = 16
        for name in tabs {
            let color = name == tab ? Theme.text : Theme.dim
            text(name, x, 528, bold: name == tab, color: color)
            x += CGFloat(name.count) * 12 + 16
        }
        text("预设详细信息", 430, 500, bold: true)
        text("名称", 430, 448)
        text("宽度", 430, 378)
        text("高度", 540, 378)
        text("单位    \(unitLabel)", 430, 348)
        text("方向    \(portrait ? "纵向" : "横向")", 430, 328)
        text("画板", 430, 278)
        text("出血    上 下 左 右    链接", 510, 254)
        text("背景内容    白色", 430, 210)
        text("高级选项", 430, 170, bold: true)
        text("颜色模式    \(mode == .cmyk ? "CMYK" : "RGB")", 430, 140)
        text("光栅效果    \(Int(raster)) ppi", 430, 116)
        let presets = [("自定", "210 × 297 毫米"), ("A4", "210 × 297 毫米"), ("信纸", "216 × 279 毫米"), ("网页-大", "1920 × 1080 像素")]
        for (index, item) in presets.enumerated() {
            let rect = NSRect(x: origin.x + 20, y: origin.y + 400 - CGFloat(index) * 78, width: 180, height: 68)
            (item.0 == preset ? Theme.accent.withAlphaComponent(0.35) : Theme.raised).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            (item.0 as NSString).draw(at: NSPoint(x: rect.minX + 10, y: rect.maxY - 24), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: Theme.text
            ])
            (item.1 as NSString).draw(at: NSPoint(x: rect.minX + 10, y: rect.minY + 12), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.dim
            ])
        }
        Theme.raised.setFill()
        NSBezierPath(roundedRect: NSRect(x: origin.x + 640, y: origin.y + 16, width: 90, height: 28), xRadius: 4, yRadius: 4).fill()
        Theme.homeBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: origin.x + 740, y: origin.y + 16, width: 96, height: 28), xRadius: 4, yRadius: 4).fill()
    }

    private var unitLabel: String {
        switch unit {
        case .mm: return "毫米"
        case .pt: return "点"
        case .px: return "像素"
        case .inch: return "英寸"
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let local = NSPoint(x: point.x - card.frame.minX, y: point.y - card.frame.minY)
        if NSRect(x: 740, y: 16, width: 96, height: 28).contains(local) {
            onCreate?(currentSpec())
            return
        }
        if NSRect(x: 640, y: 16, width: 90, height: 28).contains(local) {
            onClose?()
            return
        }
        let presets = ["自定", "A4", "信纸", "网页-大"]
        for (index, name) in presets.enumerated() {
            let rect = NSRect(x: 20, y: 400 - CGFloat(index) * 78, width: 180, height: 68)
            if rect.contains(local) { applyPreset(name) }
        }
        if local.y > 320 && local.y < 348 && local.x > 430 { portrait.toggle(); needsDisplay = true }
        if local.y > 130 && local.y < 156 && local.x > 430 {
            mode = mode == .cmyk ? .rgb : .cmyk
            needsDisplay = true
        }
        var tabX: CGFloat = 16
        for name in tabs {
            let width = CGFloat(name.count) * 12 + 16
            if NSRect(x: tabX, y: 516, width: width, height: 28).contains(local) {
                tab = name
                needsDisplay = true
            }
            tabX += width
        }
    }

    private func applyPreset(_ name: String) {
        preset = name
        switch name {
        case "网页-大":
            unit = .px; mode = .rgb; widthField.stringValue = "1920"; heightField.stringValue = "1080"; portrait = true
        case "信纸":
            unit = .mm; mode = .cmyk; widthField.stringValue = "215.9"; heightField.stringValue = "279.4"
        default:
            unit = .mm; mode = .cmyk; widthField.stringValue = "210"; heightField.stringValue = "297"
        }
        needsDisplay = true
    }

    private func currentSpec() -> NewDocSpec {
        NewDocSpec(
            name: nameField.stringValue,
            width: Double(widthField.stringValue) ?? 210,
            height: Double(heightField.stringValue) ?? 297,
            unit: unit,
            colorMode: mode,
            artboards: max(1, Int(countField.stringValue) ?? 1),
            bleed: Double(bleedField.stringValue) ?? 0,
            raster: raster,
            portrait: portrait
        )
    }
}
