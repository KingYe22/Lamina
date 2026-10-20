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
    var bleedTop: Double = 0
    var bleedBottom: Double = 0
    var bleedLeft: Double = 0
    var bleedRight: Double = 0
    /// 默认、像素预览、叠印预览
    var preview: String = "默认"

    func pointSize() -> Vec2 {
        func pts(_ value: Double) -> Double {
            switch unit {
            case .pt: return value
            case .mm: return value * 72.0 / 25.4
            case .inch: return value * 72.0
            case .px: return value
            }
        }
        return Vec2(max(1, pts(width)), max(1, pts(height)))
    }
}

/// The only content that may drag the window. Tool surfaces return false
/// from mouseDownCanMoveWindow, and the window itself is not movable by its background.
final class TitleDragStrip: NSView {
    /// Sits in the title-bar band. AppKit drags the window from here because
    /// this view allows it; the canvas and the tools do not.
    override var mouseDownCanMoveWindow: Bool { true }
}

final class AppRoot: NSView {
    let workspace: Workspace
    let home = HomeView()
    let editor: EditorShell
    let dialog = NewDocumentDialog()
    private let titleDrag = TitleDragStrip()
    private(set) var showingEditor = false

    override var mouseDownCanMoveWindow: Bool { false }

    /// The content view is not a text client. A nil context keeps Pinyin from
    /// claiming letter keys while the workspace is focused.
    override var inputContext: NSTextInputContext? { nil }

    override func interpretKeyEvents(_ eventArray: [NSEvent]) {}

    override func keyDown(with event: NSEvent) {
        if KeyRouter.handle(event, workspace: workspace) == nil { return }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        editor = EditorShell(workspace: workspace)
        super.init(frame: .zero)
        home.workspace = workspace
        dialog.onClose = { [weak self] in self?.dismissDialog() }
        workspace.onDismissDialog = { [weak self] in
            guard let self, !self.dialog.isHidden else { return false }
            self.dismissDialog()
            return true
        }
        dialog.onCreate = { [weak self] spec in
            self?.create(spec)
        }
        workspace.onAcceptDialog = { [weak self] in
            guard let self, !self.dialog.isHidden else { return false }
            self.dialog.accept()
            return true
        }
        home.onNew = { [weak self] in self?.showDialog() }
        home.onOpen = { [weak self] in self?.workspace.perform("打开文档") }
        addSubview(home)
        addSubview(editor)
        addSubview(titleDrag)
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
        titleDrag.frame = NSRect(x: 78, y: bounds.height - 28, width: max(0, bounds.width - 78), height: 28)
    }

    func showHome() {
        showingEditor = false
        workspace.editorIsKey = false
        home.isHidden = false
        editor.isHidden = true
        home.needsDisplay = true
        window?.makeFirstResponder(nil)
        KeyProbe.bump(workspace)
    }

    func showEditor() {
        showingEditor = true
        workspace.editorIsKey = true
        home.isHidden = true
        editor.isHidden = false
        dialog.isHidden = true
        editor.sync()
        window?.endEditing(for: nil)
        PanelField.disarmAll(in: window)
        focusCanvas()
        DispatchQueue.main.async { [weak self] in self?.focusCanvas() }
    }

    private func dismissDialog() {
        dialog.isHidden = true
        if showingEditor { CanvasFocus.restore(in: window) }
        KeyProbe.bump(workspace)
    }

    func showDialog() {
        dialog.isHidden = false
        dialog.syncPresets()
        dialog.needsLayout = true
        layoutSubtreeIfNeeded()
        if showingEditor {
            CanvasFocus.restore(in: window)
        } else {
            window?.makeFirstResponder(nil)
        }
        KeyProbe.bump(workspace)
    }

    private func focusCanvas() {
        guard showingEditor, !PanelField.anyArmed(in: window) else { return }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.initialFirstResponder = editor.canvas.drawing
        window?.makeFirstResponder(editor.canvas.drawing)
        NSTextInputContext.current?.discardMarkedText()
        NSTextInputContext.current?.deactivate()
        KeyProbe.bump(workspace)
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
        session.model.pixelPreview = spec.preview == "像素" || spec.preview == "像素预览"
        session.model.overprintPreview = spec.preview == "叠印" || spec.preview == "叠印预览"
        session.model.outline = false
        showEditor()
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.window.setFill()
        bounds.fill()
    }
}

final class DocumentTabBar: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    weak var workspace: Workspace?

    override func draw(_ dirtyRect: NSRect) {
        Theme.window.setFill()
        bounds.fill()
        guard let model = workspace?.active.model else { return }
        let zoom = String(format: "%.2f%%", model.zoom * 100)
        let mode = model.document.colorMode == .cmyk ? "CMYK" : "RGB"
        let preview = model.outline ? "轮廓" : "预览"
        let title = "\(model.document.title) @ \(zoom) (\(mode)/\(preview))" as NSString
        let font = Theme.ui(12)
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
    override var mouseDownCanMoveWindow: Bool { false }
    weak var workspace: Workspace?

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        Theme.line.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)).fill()
        guard let model = workspace?.active.model else { return }
        let hint = Self.hint(for: model.tool) as NSString
        hint.draw(at: NSPoint(x: 10, y: 6), withAttributes: [
            .font: Theme.ui(11), .foregroundColor: Theme.dim
        ])
        let zoom = String(format: "%.2f%%", model.zoom * 100)
        let boards = max(model.document.artboards.count, 1)
        let index = min(model.document.activeArtboard + 1, boards)
        let right = "\(zoom) ▾    0°    ‹ \(index) / \(boards) ›    \(model.tool.title)" as NSString
        let font = Theme.ui(11)
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
    override var mouseDownCanMoveWindow: Bool { false }
    weak var workspace: Workspace?

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        Theme.line.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()
        let model = workspace?.active.model
        let tool = model?.tool ?? .selection
        let icon = NSRect(x: 8, y: (bounds.height - 16) / 2, width: 16, height: 16)
        ToolIcons.draw(tool, in: icon, color: Theme.text)
        var x = icon.maxX + 6
        x = label(tool.title, x: x, weight: .semibold)
        x = divider(x)
        x = chip({ PanelIcons.sliders(in: $0) }, title: "属性", x: x)
        x = chip({ PanelIcons.align(0, in: $0) }, title: "对齐", x: x)
        _ = chip({ PanelIcons.pathfinder(0, in: $0) }, title: "路径查找器", x: x)
    }

    private func label(_ text: String, x: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        let font = Theme.ui(11, weight: weight)
        let size = (text as NSString).size(withAttributes: [.font: font])
        (text as NSString).draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2), withAttributes: [
            .font: font, .foregroundColor: Theme.text
        ])
        return x + size.width + 8
    }

    private func divider(_ x: CGFloat) -> CGFloat {
        Theme.line.setFill()
        NSBezierPath(rect: NSRect(x: x, y: 6, width: 1, height: bounds.height - 12)).fill()
        return x + 10
    }

    private func chip(_ draw: (NSRect) -> Void, title: String, x: CGFloat) -> CGFloat {
        let icon = NSRect(x: x, y: (bounds.height - 14) / 2, width: 14, height: 14)
        draw(icon)
        return label(title, x: icon.maxX + 4)
    }

    override func mouseDown(with event: NSEvent) {
        workspace?.active.model.status = "上下文任务栏"
        workspace?.touch()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        Hover.install(on: self)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let tool = workspace?.active.model.tool ?? .selection
        if point.x < 90 {
            RichTooltip.shared.show(from: self, localPoint: point, title: ToolTips.heading(tool), body: ToolTips.body(tool))
        } else if point.x < 170 {
            RichTooltip.shared.show(from: self, localPoint: point, title: "属性", body: "打开属性面板，查看当前选择的选项。")
        } else if point.x < 230 {
            RichTooltip.shared.show(from: self, localPoint: point, title: "对齐", body: "按所选对象或画板对齐、分布。")
        } else {
            RichTooltip.shared.show(from: self, localPoint: point, title: "路径查找器", body: "用形状模式合并、减去或相交路径。")
        }
    }

    override func mouseExited(with event: NSEvent) { RichTooltip.shared.hide() }
}

final class FloatingPanels: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    weak var workspace: Workspace?
    private let weightField = PanelField(text: "1 pt")
    private let limitField = PanelField(text: "4")
    private let spacingField = PanelField(text: "0")
    private var groupTab = 1
    private var strokeTab = 0
    private var cap = 0
    private var corner = 0
    private var strokePlace = 0
    private var dashed = false
    private var strokeVisible = true
    private var fillVisible = true
    private var alignTarget = 0
    private let alignTargets = ["对齐所选对象", "对齐画板", "关键对象"]
    private let appearanceHeight: CGFloat = 124
    private let alignHeight: CGFloat = 198
    private let strokeHeight: CGFloat = 236
    private let gap: CGFloat = 8

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for field in [weightField, limitField, spacingField] {
            addSubview(field)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync() { needsDisplay = true }

    override func layout() {
        super.layout()
        let strokeRectMinY = strokeY + 26
        weightField.frame = NSRect(x: 44, y: strokeRectMinY - 2, width: 76, height: 20)
        limitField.frame = NSRect(x: 112, y: strokeRectMinY + 86, width: 36, height: 22)
        let alignRectMinY = alignY + 26
        spacingField.frame = NSRect(x: 78, y: alignRectMinY + 108, width: 54, height: 22)
        weightField.isHidden = strokeTab != 0
        limitField.isHidden = strokeTab != 0
        spacingField.isHidden = groupTab != 1
    }

    private var alignY: CGFloat { appearanceHeight + gap }
    private var strokeY: CGFloat { alignY + alignHeight + gap }

    override func draw(_ dirtyRect: NSRect) {
        card(y: 0, height: appearanceHeight, tabs: ["外观"], active: 0)
        drawAppearance(NSRect(x: 8, y: 26, width: bounds.width - 16, height: appearanceHeight - 32))
        card(y: alignY, height: alignHeight, tabs: ["变换", "对齐", "路径查找器"], active: groupTab)
        drawGroup(NSRect(x: 8, y: alignY + 26, width: bounds.width - 16, height: alignHeight - 32))
        card(y: strokeY, height: strokeHeight, tabs: ["描边", "透明度"], active: strokeTab)
        drawStroke(NSRect(x: 8, y: strokeY + 26, width: bounds.width - 16, height: strokeHeight - 32))
    }

    private func card(y: CGFloat, height: CGFloat, tabs: [String], active: Int) {
        let rect = NSRect(x: 0, y: y, width: bounds.width, height: height)
        Theme.panel.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        var x: CGFloat = 8
        for (index, tab) in tabs.enumerated() {
            let font = Theme.ui(11, weight: index == active ? .semibold : .regular)
            let color = index == active ? Theme.text : Theme.dim
            (tab as NSString).draw(at: NSPoint(x: x, y: y + 6), withAttributes: [.font: font, .foregroundColor: color])
            x += (tab as NSString).size(withAttributes: [.font: font]).width + 10
        }
        PanelIcons.menu(in: NSRect(x: bounds.width - 20, y: y + 6, width: 12, height: 12))
    }

    private func drawAppearance(_ rect: NSRect) {
        ("未选择对象" as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY), withAttributes: [
            .font: Theme.ui(11, weight: .semibold), .foregroundColor: Theme.heading
        ])
        rowEye(rect.minX, rect.minY + 22, open: strokeVisible, color: .black, title: "描边", detail: "1 pt")
        rowEye(rect.minX, rect.minY + 44, open: fillVisible, color: .white, title: "填色", detail: "")
        ("不透明度" as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY + 70), withAttributes: [
            .font: Theme.ui(11), .foregroundColor: Theme.dim
        ])
        PanelIcons.popup(NSRect(x: rect.minX + 64, y: rect.minY + 66, width: rect.width - 64, height: 20), title: "默认")
    }

    private func rowEye(_ x: CGFloat, _ y: CGFloat, open: Bool, color: NSColor, title: String, detail: String) {
        PanelIcons.eye(in: NSRect(x: x, y: y, width: 16, height: 12), open: open)
        PanelIcons.swatch(in: NSRect(x: x + 22, y: y - 1, width: 14, height: 14), color: color)
        (title as NSString).draw(at: NSPoint(x: x + 42, y: y), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: Theme.text
        ])
        if !detail.isEmpty {
            (detail as NSString).draw(at: NSPoint(x: x + 78, y: y), withAttributes: [
                .font: Theme.ui(11), .foregroundColor: Theme.dim
            ])
        }
    }

    private func drawGroup(_ rect: NSRect) {
        switch groupTab {
        case 0:
            let labels = ["X", "Y", "W", "H"]
            let values = ["0", "0", "210", "297"]
            for index in 0..<4 {
                let y = rect.minY + CGFloat(index) * 28
                (labels[index] as NSString).draw(at: NSPoint(x: rect.minX, y: y + 2), withAttributes: [
                    .font: Theme.ui(11), .foregroundColor: Theme.dim
                ])
                PanelIcons.stepper(NSRect(x: rect.minX + 22, y: y, width: 120, height: 20), title: values[index])
            }
        case 2:
            caption("形状模式", y: rect.minY)
            iconRow(4, y: rect.minY + 16) { PanelIcons.pathfinder($0, in: $1) }
            caption("路径查找器", y: rect.minY + 48)
            iconRow(4, y: rect.minY + 64) { PanelIcons.pathfinder(($0 + 1) % 4, in: $1) }
        default:
            caption("对齐对象", y: rect.minY)
            iconRow(6, y: rect.minY + 16) { PanelIcons.align($0, in: $1) }
            caption("分布对象", y: rect.minY + 46)
            iconRow(6, y: rect.minY + 62) { PanelIcons.distribute($0, in: $1) }
            caption("分布间距", y: rect.minY + 92)
            let spacing = iconRow(2, y: rect.minY + 108) { PanelIcons.spacing(horizontal: $0 == 1, in: $1) }
            PanelIcons.field(NSRect(x: spacing + 6, y: rect.minY + 108, width: 54, height: 22), text: "0", align: .center)
            PanelIcons.popup(NSRect(x: rect.minX, y: rect.minY + 140, width: rect.width, height: 22), title: alignTargets[alignTarget])
        }
    }

    private func drawStroke(_ rect: NSRect) {
        if strokeTab == 1 {
            ("不透明度" as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY + 4), withAttributes: [
                .font: Theme.ui(11), .foregroundColor: Theme.dim
            ])
            PanelIcons.stepper(NSRect(x: rect.minX + 64, y: rect.minY, width: 110, height: 22), title: "100%")
            ("混合模式" as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY + 36), withAttributes: [
                .font: Theme.ui(11), .foregroundColor: Theme.dim
            ])
            PanelIcons.popup(NSRect(x: rect.minX, y: rect.minY + 56, width: rect.width, height: 22), title: "正常")
            return
        }
        caption("粗细", y: rect.minY)
        PanelIcons.stepper(NSRect(x: rect.minX + 36, y: rect.minY - 2, width: 92, height: 20), title: "1 pt")
        PanelIcons.popup(NSRect(x: rect.minX + 134, y: rect.minY - 2, width: max(40, rect.width - 134), height: 20), title: "")
        caption("端点", y: rect.minY + 26)
        iconRow(3, y: rect.minY + 42, selected: cap) { PanelIcons.cap($0, in: $1) }
        caption("边角", y: rect.minY + 70)
        let afterCorner = iconRow(3, y: rect.minY + 86, selected: corner) { PanelIcons.corner($0, in: $1) }
        PanelIcons.field(NSRect(x: afterCorner + 8, y: rect.minY + 86, width: 36, height: 22), text: "4", align: .center)
        caption("对齐描边", y: rect.minY + 114)
        iconRow(3, y: rect.minY + 130, selected: strokePlace) { PanelIcons.strokeAlign($0, in: $1) }
        PanelIcons.checkbox(at: NSPoint(x: rect.minX, y: rect.minY + 160), on: dashed, title: "")
        var dashX = rect.minX + 22
        for _ in 0..<6 {
            PanelIcons.field(NSRect(x: dashX, y: rect.minY + 156, width: 26, height: 20), text: "", align: .center)
            dashX += 29
        }
        PanelIcons.popup(NSRect(x: rect.minX, y: rect.minY + 182, width: rect.width * 0.48, height: 20), title: "箭头")
        PanelIcons.popup(NSRect(x: rect.minX + rect.width * 0.52, y: rect.minY + 182, width: rect.width * 0.48, height: 20), title: "配置文件")
    }

    @discardableResult
    private func iconRow(_ count: Int, y: CGFloat, selected: Int = -1, draw: (Int, NSRect) -> Void) -> CGFloat {
        var x: CGFloat = 8
        let width: CGFloat = count >= 6 ? 26 : 28
        for index in 0..<count {
            let rect = NSRect(x: x, y: y, width: width, height: 22)
            PanelIcons.well(rect, selected: index == selected)
            draw(index, rect.insetBy(dx: 1, dy: 1))
            x += width + 4
        }
        return x
    }

    private func caption(_ text: String, y: CGFloat) {
        (text as NSString).draw(at: NSPoint(x: 8, y: y), withAttributes: [
            .font: Theme.ui(11), .foregroundColor: Theme.dim
        ])
    }

    override func mouseDown(with event: NSEvent) {
        CanvasFocus.restore(in: window)
        let point = convert(event.locationInWindow, from: nil)
        if point.y < appearanceHeight {
            if NSRect(x: 8, y: 48, width: 18, height: 16).contains(point) { strokeVisible.toggle() }
            if NSRect(x: 8, y: 70, width: 18, height: 16).contains(point) { fillVisible.toggle() }
        } else if point.y < alignY + alignHeight {
            let localX = point.x
            let tab = tabIndex(["变换", "对齐", "路径查找器"], x: localX)
            if point.y < alignY + 22, let tab { groupTab = tab }
            else if groupTab == 1, let index = iconIndex(count: 6, y: alignY + 26 + 16, point: point) {
                let names = ["水平左对齐", "水平居中对齐", "水平右对齐", "垂直顶对齐", "垂直居中对齐", "垂直底对齐"]
                workspace?.perform(names[index])
            } else if groupTab == 1, point.y > alignY + 160 {
                alignTarget = (alignTarget + 1) % alignTargets.count
            }
        } else {
            if point.y < strokeY + 22 {
                let tab = tabIndex(["描边", "透明度"], x: point.x)
                if let tab { strokeTab = tab }
            } else if strokeTab == 0 {
                if let index = iconIndex(count: 3, y: strokeY + 26 + 42, point: point, width: 28) { cap = index }
                if let index = iconIndex(count: 3, y: strokeY + 26 + 86, point: point, width: 28) { corner = index }
                if let index = iconIndex(count: 3, y: strokeY + 26 + 130, point: point, width: 28) { strokePlace = index }
                if point.x < 28, abs(point.y - (strokeY + 186)) < 14 { dashed.toggle() }
            }
        }
        needsDisplay = true
        needsLayout = true
        workspace?.touch()
    }

    private func tabIndex(_ titles: [String], x: CGFloat) -> Int? {
        var cursor: CGFloat = 8
        let font = Theme.ui(11, weight: .semibold)
        for (index, title) in titles.enumerated() {
            let width = (title as NSString).size(withAttributes: [.font: font]).width + 10
            if x >= cursor && x < cursor + width { return index }
            cursor += width
        }
        return nil
    }

    private func iconIndex(count: Int, y: CGFloat, point: NSPoint, width: CGFloat = 26) -> Int? {
        guard abs(point.y - (y + 11)) < 14 else { return nil }
        let index = Int((point.x - 8) / (width + 4))
        return (0..<count).contains(index) ? index : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        Hover.install(on: self)
    }

    override func mouseExited(with event: NSEvent) { RichTooltip.shared.hide() }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let tip = panelTip(at: point) else { RichTooltip.shared.hide(); return }
        RichTooltip.shared.show(from: self, localPoint: point, title: tip.0, body: tip.1)
    }

    private func panelTip(at point: NSPoint) -> (String, String)? {
        if point.y < appearanceHeight {
            if point.y < 48 { return ("外观", "当前对象的填色、描边和不透明度。") }
            if point.y < 66 { return ("描边", "显示或隐藏描边，单击色块更改描边色。") }
            if point.y < 88 { return ("填色", "显示或隐藏填色，单击色块更改填色。") }
            return ("不透明度", "选择对象的不透明度混合。")
        }
        if point.y < alignY + alignHeight {
            if point.y < alignY + 22 { return ("面板菜单", "切换变换、对齐和路径查找器。") }
            if groupTab == 1 {
                let names = ["水平左对齐", "水平居中对齐", "水平右对齐", "垂直顶对齐", "垂直居中对齐", "垂直底对齐"]
                if let index = iconIndex(count: 6, y: alignY + 42, point: point) {
                    return (names[index], "按所选对象或画板对齐。")
                }
                if iconIndex(count: 6, y: alignY + 88, point: point) != nil {
                    return ("分布对象", "使所选对象的间距或边缘均匀分布。")
                }
                if iconIndex(count: 2, y: alignY + 134, point: point, width: 28) != nil {
                    return ("分布间距", "按输入的间距分布对象。")
                }
                return ("对齐", "选择对齐目标：所选对象、画板或关键对象。")
            }
            return ("变换", "查看和更改位置与大小。")
        }
        if point.y < strokeY + 22 { return ("描边", "打开描边或透明度设置。右上角是面板菜单。") }
        if strokeTab != 0 { return ("透明度", "设置不透明度和混合模式。") }
        if iconIndex(count: 3, y: strokeY + 68, point: point, width: 28) != nil {
            return ("端点", "平头、圆头或方头端点。")
        }
        if iconIndex(count: 3, y: strokeY + 112, point: point, width: 28) != nil {
            return ("边角", "尖角、圆角或斜角。")
        }
        if iconIndex(count: 3, y: strokeY + 156, point: point, width: 28) != nil {
            return ("对齐描边", "描边居中、内侧或外侧。")
        }
        if point.y > strokeY + 170 && point.y < strokeY + 200 {
            return ("虚线", "勾选后用六个数值设置线段和间隙。")
        }
        return ("描边", "设置粗细、箭头和宽度配置文件。")
    }
}

final class PropertiesDock: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    weak var workspace: Workspace?
    private let nudgeField = PanelField(text: "1 pt")
    private let tabs = ["属性", "注释", "图层", "库"]
    private var tab = "属性"

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(nudgeField)
        nudgeField.onLeave = { [weak self] in self?.applyNudge() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync() { needsDisplay = true }

    func nudgeFieldCenter() -> NSPoint {
        nudgeField.convert(NSPoint(x: nudgeField.bounds.midX, y: nudgeField.bounds.midY), to: self)
    }

    override func layout() {
        super.layout()
        nudgeField.frame = NSRect(x: max(0, bounds.width - 108), y: 442, width: 80, height: 22)
        nudgeField.isHidden = tab != "属性"
    }

    private func applyNudge() {
        guard let model = workspace?.active.model else { return }
        let cleaned = nudgeField.stringValue.replacingOccurrences(of: "pt", with: "").trimmingCharacters(in: .whitespaces)
        if let number = Double(cleaned) {
            model.nudge = min(64, max(0.1, number))
        }
        nudgeField.stringValue = "\(Int(model.nudge)) pt"
    }

    private var usePreviewBounds = true
    private var scaleCorners = false
    private var scaleEffects = false

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        var x: CGFloat = 8
        for name in tabs {
            let font = Theme.ui(12, weight: name == tab ? .semibold : .regular)
            let color = name == tab ? Theme.text : Theme.dim
            (name as NSString).draw(at: NSPoint(x: x, y: 8), withAttributes: [.font: font, .foregroundColor: color])
            if name == tab {
                Theme.accent.setFill()
                NSBezierPath(rect: NSRect(x: x, y: 26, width: 28, height: 2)).fill()
            }
            x += 52
        }
        PanelIcons.menu(in: NSRect(x: bounds.width - 22, y: 8, width: 14, height: 12))
        guard tab == "属性", let model = workspace?.active.model else {
            let note = tab == "图层" ? layerText() : "\(tab) 为空"
            (note as NSString).draw(at: NSPoint(x: 12, y: 48), withAttributes: [
                .font: Theme.ui(12), .foregroundColor: Theme.dim
            ])
            return
        }
        let unit = Self.unitName(model.document.units)
        let board = model.document.artboards.indices.contains(model.document.activeArtboard)
            ? model.document.artboards[model.document.activeArtboard].name
            : "画板 1"
        ("未选择对象" as NSString).draw(at: NSPoint(x: 12, y: 40), withAttributes: [
            .font: Theme.ui(11, weight: .semibold), .foregroundColor: Theme.heading
        ])
        section("文档", y: 66)
        labeledPopup("单位", unit, y: 88)
        labeledPopup("画板", board, y: 114)
        PanelIcons.well(NSRect(x: 12, y: 140, width: 28, height: 24), selected: false)
        PanelIcons.artboard(in: NSRect(x: 16, y: 143, width: 20, height: 18))
        ("编辑画板" as NSString).draw(at: NSPoint(x: 46, y: 144), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: Theme.text
        ])
        section("标尺与网格", y: 176)
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 198), on: model.showRulers, title: "显示标尺")
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 220), on: model.showGrid, title: "显示网格")
        section("参考线", y: 250)
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 272), on: model.showGuides, title: "显示参考线")
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 294), on: model.lockGuides, title: "锁定参考线")
        section("对齐选项", y: 324)
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 346), on: model.snapGrid, title: "对齐网格")
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 368), on: model.snapPoint, title: "对齐点")
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 390), on: model.smartGuides, title: "智能参考线")
        section("首选项", y: 420)
        ("键盘增量" as NSString).draw(at: NSPoint(x: 12, y: 446), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: Theme.text
        ])
        PanelIcons.stepper(NSRect(x: bounds.width - 108, y: 442, width: 96, height: 22), title: "\(Int(model.nudge)) pt")
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 472), on: usePreviewBounds, title: "使用预览边界")
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 494), on: scaleCorners, title: "缩放圆角")
        PanelIcons.checkbox(at: NSPoint(x: 12, y: 516), on: scaleEffects, title: "缩放描边和效果")
        section("快速操作", y: 546)
        quickButton(NSRect(x: 12, y: 570, width: 120, height: 26), draw: { PanelIcons.gear(in: $0) }, title: "文档设置")
        quickButton(NSRect(x: 140, y: 570, width: 110, height: 26), draw: { PanelIcons.sliders(in: $0) }, title: "首选项")
    }

    private func section(_ title: String, y: CGFloat) {
        (title as NSString).draw(at: NSPoint(x: 12, y: y), withAttributes: [
            .font: Theme.ui(11, weight: .semibold), .foregroundColor: Theme.heading
        ])
    }

    private func labeledPopup(_ label: String, _ value: String, y: CGFloat) {
        (label as NSString).draw(at: NSPoint(x: 12, y: y + 2), withAttributes: [
            .font: Theme.ui(11), .foregroundColor: Theme.dim
        ])
        PanelIcons.popup(NSRect(x: 72, y: y, width: bounds.width - 84, height: 22), title: value)
    }

    private func quickButton(_ rect: NSRect, draw: (NSRect) -> Void, title: String) {
        PanelIcons.well(rect, selected: false)
        draw(NSRect(x: rect.minX + 4, y: rect.minY + 4, width: 16, height: 16))
        (title as NSString).draw(at: NSPoint(x: rect.minX + 24, y: rect.minY + 5), withAttributes: [
            .font: Theme.ui(11), .foregroundColor: Theme.text
        ])
    }

    private static func unitName(_ unit: UnitKind) -> String {
        switch unit {
        case .mm: return "毫米"
        case .pt: return "点"
        case .px: return "像素"
        case .inch: return "英寸"
        }
    }

    private func layerText() -> String {
        guard let layers = workspace?.active.model.document.layers else { return "图层" }
        return layers.map(\.name).joined(separator: "\n")
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y < 32 {
            if point.x > bounds.width - 28 { return }
            let index = Int((point.x - 8) / 52)
            if tabs.indices.contains(index) { tab = tabs[index]; needsDisplay = true; needsLayout = true }
            return
        }
        CanvasFocus.restore(in: window)
        guard tab == "属性", let workspace else { return }
        let model = workspace.active.model
        if NSRect(x: 72, y: 88, width: bounds.width - 84, height: 22).contains(point) {
            let order: [UnitKind] = [.mm, .pt, .px, .inch]
            let index = order.firstIndex(of: model.document.units) ?? 0
            model.document.units = order[(index + 1) % order.count]
        } else if NSRect(x: 12, y: 140, width: 120, height: 24).contains(point) {
            model.tool = .artboard
        } else if hit(point, y: 198) { workspace.perform("显示标尺") }
        else if hit(point, y: 220) { workspace.perform("显示网格") }
        else if hit(point, y: 272) { workspace.perform("隐藏参考线") }
        else if hit(point, y: 294) { workspace.perform("锁定参考线") }
        else if hit(point, y: 346) { workspace.perform("对齐网格") }
        else if hit(point, y: 368) { workspace.perform("对齐点") }
        else if hit(point, y: 390) { workspace.perform("显示/隐藏智能参考线") }
        else if NSRect(x: bounds.width - 108, y: 442, width: 96, height: 22).contains(point) {
            model.nudge = min(64, model.nudge + (point.x > bounds.width - 20 ? 1 : -1))
        } else if hit(point, y: 472) { usePreviewBounds.toggle() }
        else if hit(point, y: 494) { scaleCorners.toggle() }
        else if hit(point, y: 516) { scaleEffects.toggle() }
        else if NSRect(x: 12, y: 570, width: 120, height: 26).contains(point) {
            workspace.perform("打开“文档设置”对话框")
        } else if NSRect(x: 140, y: 570, width: 110, height: 26).contains(point) {
            workspace.perform("打开“偏好设置”对话框")
        }
        workspace.touch()
    }

    private func hit(_ point: NSPoint, y: CGFloat) -> Bool {
        NSRect(x: 8, y: y - 2, width: bounds.width - 16, height: 18).contains(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        Hover.install(on: self)
    }

    override func mouseExited(with event: NSEvent) { RichTooltip.shared.hide() }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let tip: (String, String)
        if point.y < 32 {
            tip = ("属性", "在属性、注释、图层和库之间切换。右侧是面板菜单。")
        } else if point.y < 160 {
            tip = ("文档", "更改单位、画板，或进入画板编辑。")
        } else if point.y < 250 {
            tip = ("标尺与网格", "显示或隐藏标尺和网格。")
        } else if point.y < 324 {
            tip = ("参考线", "显示或锁定参考线。")
        } else if point.y < 420 {
            tip = ("对齐选项", "对齐网格、对齐点或智能参考线。")
        } else if point.y < 546 {
            tip = ("首选项", "键盘增量、预览边界、缩放圆角和描边。")
        } else {
            tip = ("快速操作", "打开文档设置或首选项。")
        }
        RichTooltip.shared.show(from: self, localPoint: point, title: tip.0, body: tip.1)
    }
}

final class HomeView: NSView {
    weak var workspace: Workspace?
    override var mouseDownCanMoveWindow: Bool { false }
    var onNew: (() -> Void)?
    var onOpen: (() -> Void)?
    private let newButton = NSButton(title: "新文件", target: nil, action: nil)
    private let openButton = NSButton(title: "打开", target: nil, action: nil)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        newButton.target = self
        newButton.action = #selector(pressNew)
        newButton.refusesFirstResponder = true
        newButton.isBordered = false
        newButton.attributedTitle = NSAttributedString(string: "新文件", attributes: [
            .foregroundColor: NSColor.white,
            .font: Theme.ui(14, weight: .semibold)
        ])
        openButton.target = self
        openButton.action = #selector(pressOpen)
        openButton.refusesFirstResponder = true
        openButton.isBordered = false
        openButton.contentTintColor = Theme.text
        openButton.font = Theme.ui(14)
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

    func newButtonCenter() -> NSPoint {
        NSPoint(x: newButton.frame.midX, y: newButton.frame.midY)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.window.setFill()
        bounds.fill()
        let title = "Lamina" as NSString
        let font = Theme.ui(13, weight: .semibold)
        let size = title.size(withAttributes: [.font: font])
        title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: 8), withAttributes: [
            .font: font, .foregroundColor: Theme.text
        ])
        Theme.panel.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 28, width: 220, height: bounds.height - 28)).fill()
        Theme.homeBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: 24, y: 64, width: 172, height: 36), xRadius: 4, yRadius: 4).fill()
        ("最近使用项" as NSString).draw(at: NSPoint(x: 248, y: 56), withAttributes: [
            .font: Theme.ui(18, weight: .semibold), .foregroundColor: Theme.text
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
                .font: Theme.ui(11), .foregroundColor: Theme.text
            ])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if NSRect(x: 24, y: 64, width: 172, height: 36).contains(point) { onNew?() }
        else if NSRect(x: 24, y: 108, width: 80, height: 28).contains(point) { onOpen?() }
    }
}

private struct DocPreset {
    var name: String
    var detail: String
    var width: Double
    var height: Double
    var unit: UnitKind
    var mode: ColorMode
    var raster: Double = 72
}

/// Left padding for the new-document fields. The system bezel is not used.
final class DialogFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let box = super.drawingRect(forBounds: rect)
        return NSRect(x: box.minX + 6, y: box.minY, width: max(0, box.width - 10), height: box.height)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        drawingRect(forBounds: rect)
    }
}

final class DialogField: PanelField {
    convenience init(text: String, size: CGFloat = 12) {
        self.init(frame: .zero)
        let cell = DialogFieldCell(textCell: text)
        cell.isEditable = true
        cell.isSelectable = true
        cell.isScrollable = true
        cell.usesSingleLineMode = true
        cell.drawsBackground = true
        cell.backgroundColor = Theme.field
        cell.textColor = Theme.text
        cell.font = Theme.ui(size)
        cell.alignment = .left
        cell.isBordered = false
        cell.isBezeled = false
        self.cell = cell
        stringValue = text
        font = Theme.ui(size)
        alignment = .left
        backgroundColor = Theme.field
        textColor = Theme.text
    }
}

final class DialogPushButton: NSButton {
    var primary = false
    private var hovered = false
    private var pressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = false
        refusesFirstResponder = true
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        title = ""
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        pressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        pressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        let word = primary ? "创建" : "关闭"
        let font = Theme.ui(13, weight: .semibold)
        if primary {
            let fill = pressed ? Theme.accentDown : (hovered ? Theme.accentHover : Theme.accent)
            fill.setFill()
            path.fill()
        } else {
            if pressed {
                Theme.fieldBorder.setFill()
                path.fill()
            } else if hovered {
                Theme.line.setFill()
                path.fill()
            }
            Theme.secondaryStroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let color: NSColor = primary ? .white : Theme.text
        let size = (word as NSString).size(withAttributes: [.font: font])
        (word as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2 - 1),
            withAttributes: [.font: font, .foregroundColor: color]
        )
    }
}

/// Illustrator 2026「新建文档」: dimmed workspace and the dark preset sheet.
final class NewDocumentDialog: NSView {
    var onCreate: ((NewDocSpec) -> Void)? {
        get { sheet.onCreate }
        set { sheet.onCreate = newValue }
    }
    var onClose: (() -> Void)? {
        get { sheet.onClose }
        set { sheet.onClose = newValue }
    }
    private let sheet = NewDocSheet()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(sheet)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    func syncPresets() {
        sheet.needsDisplay = true
        sheet.needsLayout = true
    }

    func accept() {
        sheet.submit()
    }

    override func layout() {
        super.layout()
        let size = NSSize(width: min(1000, bounds.width - 80), height: min(680, bounds.height - 80))
        sheet.frame = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        sheet.layoutSubtreeIfNeeded()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.5).setFill()
        bounds.fill()
        guard sheet.frame.width > 1 else { return }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowBlurRadius = 16
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        Theme.window.setFill()
        NSBezierPath(roundedRect: sheet.frame, xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    func createButtonCenter() -> NSPoint {
        sheet.convert(sheet.createButtonLocalCenter(), to: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {}
}

final class NewDocSheet: NSView {
    var onCreate: ((NewDocSpec) -> Void)?
    var onClose: (() -> Void)?

    static let tabHeight: CGFloat = 44
    static let detailWidth: CGFloat = 320
    static let cardSize = NSSize(width: 196, height: 184)
    static let cardGap: CGFloat = 16
    static let cardMargin: CGFloat = 24

    private let categories = ["最近使用项", "已保存", "移动设备", "Web", "打印", "品牌", "社交媒体", "图稿和插图", "电影和视频", "免费模板"]
    private let catalog: [String: [DocPreset]] = [
        "移动设备": [
            DocPreset(name: "iPhone", detail: "390 × 844 像素", width: 390, height: 844, unit: .px, mode: .rgb),
            DocPreset(name: "iPad", detail: "768 × 1024 像素", width: 768, height: 1024, unit: .px, mode: .rgb),
            DocPreset(name: "Android", detail: "360 × 800 像素", width: 360, height: 800, unit: .px, mode: .rgb),
            DocPreset(name: "Apple Watch", detail: "184 × 224 像素", width: 184, height: 224, unit: .px, mode: .rgb)
        ],
        "Web": [
            DocPreset(name: "网页 — 大", detail: "1920 × 1080 像素", width: 1920, height: 1080, unit: .px, mode: .rgb),
            DocPreset(name: "网页 — 中", detail: "1366 × 768 像素", width: 1366, height: 768, unit: .px, mode: .rgb),
            DocPreset(name: "网页 — 小", detail: "1280 × 800 像素", width: 1280, height: 800, unit: .px, mode: .rgb)
        ],
        "打印": [
            DocPreset(name: "A4", detail: "210 × 297 毫米", width: 210, height: 297, unit: .mm, mode: .cmyk, raster: 300),
            DocPreset(name: "A3", detail: "297 × 420 毫米", width: 297, height: 420, unit: .mm, mode: .cmyk, raster: 300),
            DocPreset(name: "A5", detail: "148 × 210 毫米", width: 148, height: 210, unit: .mm, mode: .cmyk, raster: 300),
            DocPreset(name: "信纸", detail: "216 × 279 毫米", width: 215.9, height: 279.4, unit: .mm, mode: .cmyk, raster: 300),
            DocPreset(name: "Tabloid", detail: "279 × 432 毫米", width: 279.4, height: 431.8, unit: .mm, mode: .cmyk, raster: 300),
            DocPreset(name: "A2", detail: "420 × 594 毫米", width: 420, height: 594, unit: .mm, mode: .cmyk, raster: 300)
        ],
        "品牌": [
            DocPreset(name: "名片", detail: "90 × 50 毫米", width: 90, height: 50, unit: .mm, mode: .cmyk, raster: 300),
            DocPreset(name: "信头", detail: "210 × 297 毫米", width: 210, height: 297, unit: .mm, mode: .cmyk, raster: 300),
            DocPreset(name: "标志", detail: "500 × 500 像素", width: 500, height: 500, unit: .px, mode: .rgb)
        ],
        "社交媒体": [
            DocPreset(name: "Instagram 帖子", detail: "1080 × 1080 像素", width: 1080, height: 1080, unit: .px, mode: .rgb),
            DocPreset(name: "Instagram 故事", detail: "1080 × 1920 像素", width: 1080, height: 1920, unit: .px, mode: .rgb),
            DocPreset(name: "Facebook 封面", detail: "820 × 312 像素", width: 820, height: 312, unit: .px, mode: .rgb)
        ],
        "图稿和插图": [
            DocPreset(name: "自定", detail: "800 × 600 点", width: 800, height: 600, unit: .pt, mode: .rgb),
            DocPreset(name: "正方形", detail: "1000 × 1000 像素", width: 1000, height: 1000, unit: .px, mode: .rgb),
            DocPreset(name: "A4", detail: "210 × 297 毫米", width: 210, height: 297, unit: .mm, mode: .cmyk, raster: 300)
        ],
        "电影和视频": [
            DocPreset(name: "HDTV 1080", detail: "1920 × 1080 像素", width: 1920, height: 1080, unit: .px, mode: .rgb),
            DocPreset(name: "4K UHD", detail: "3840 × 2160 像素", width: 3840, height: 2160, unit: .px, mode: .rgb),
            DocPreset(name: "电影 2K", detail: "2048 × 1080 像素", width: 2048, height: 1080, unit: .px, mode: .rgb)
        ],
        "免费模板": [
            DocPreset(name: "海报", detail: "1080 × 1920 像素", width: 1080, height: 1920, unit: .px, mode: .rgb),
            DocPreset(name: "传单", detail: "148 × 210 毫米", width: 148, height: 210, unit: .mm, mode: .cmyk, raster: 300),
            DocPreset(name: "名片", detail: "90 × 50 毫米", width: 90, height: 50, unit: .mm, mode: .cmyk, raster: 300)
        ]
    ]

    private var saved: [DocPreset] = []
    private var category = "打印"
    private var presetIndex = 0
    private var hoverIndex: Int?
    private var unit: UnitKind = .mm
    private var mode: ColorMode = .cmyk
    private var portrait = true
    private var raster = 300.0
    private var preview = "默认值"
    private var advancedOpen = true
    private var moreOpen = false
    private var bleedLinked = true

    private let nameField = DialogField(text: "未标题-1", size: 13)
    private let widthField = DialogField(text: "210")
    private let heightField = DialogField(text: "297")
    private let countField = DialogField(text: "1")
    private let bleedTop = DialogField(text: "0")
    private let bleedBottom = DialogField(text: "0")
    private let bleedLeft = DialogField(text: "0")
    private let bleedRight = DialogField(text: "0")
    private let closeButton = DialogPushButton()
    private let createButton = DialogPushButton()

    private let sectionLabel = NewDocSheet.makeLabel("预设详细信息")
    private let nameLabel = NewDocSheet.makeLabel("名称")
    private let widthLabel = NewDocSheet.makeLabel("宽度")
    private let heightLabel = NewDocSheet.makeLabel("高度")
    private let unitLabel = NewDocSheet.makeLabel("单位")
    private let orientLabel = NewDocSheet.makeLabel("方向")
    private let countLabel = NewDocSheet.makeLabel("画板")
    private let bleedLabel = NewDocSheet.makeLabel("出血")
    private let topLabel = NewDocSheet.makeLabel("上")
    private let bottomLabel = NewDocSheet.makeLabel("下")
    private let leftLabel = NewDocSheet.makeLabel("左")
    private let rightLabel = NewDocSheet.makeLabel("右")
    private let advancedLabel = NewDocSheet.makeLabel("高级选项", size: 11, weight: .semibold, color: Theme.heading)
    private let modeLabel = NewDocSheet.makeLabel("颜色模式")
    private let rasterLabel = NewDocSheet.makeLabel("栅格效果")
    private let previewLabel = NewDocSheet.makeLabel("预览模式")

    private var categoryRects: [NSRect] = []
    private var moreRect = NSRect.zero
    private var presetRects: [NSRect] = []
    private var saveRect = NSRect.zero
    private var unitRect = NSRect.zero
    private var portraitRect = NSRect.zero
    private var landscapeRect = NSRect.zero
    private var linkRect = NSRect.zero
    private var advancedRect = NSRect.zero
    private var modeRect = NSRect.zero
    private var rasterRect = NSRect.zero
    private var previewRect = NSRect.zero
    private var moreSettingsRect = NSRect.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        appearance = NSAppearance(named: .darkAqua)
        for field in [nameField, widthField, heightField, countField, bleedTop, bleedBottom, bleedLeft, bleedRight] {
            addSubview(field)
        }
        for label in [sectionLabel, nameLabel, widthLabel, heightLabel, unitLabel, orientLabel, countLabel, bleedLabel, topLabel, bottomLabel, leftLabel, rightLabel, advancedLabel, modeLabel, rasterLabel, previewLabel] {
            addSubview(label)
        }
        bleedTop.onLeave = { [weak self] in self?.syncBleeds(from: self?.bleedTop) }
        bleedBottom.onLeave = { [weak self] in self?.syncBleeds(from: self?.bleedBottom) }
        bleedLeft.onLeave = { [weak self] in self?.syncBleeds(from: self?.bleedLeft) }
        bleedRight.onLeave = { [weak self] in self?.syncBleeds(from: self?.bleedRight) }
        closeButton.target = self
        closeButton.action = #selector(pressClose)
        createButton.primary = true
        createButton.target = self
        createButton.action = #selector(pressCreate)
        addSubview(closeButton)
        addSubview(createButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    func createButtonLocalCenter() -> NSPoint {
        NSPoint(x: createButton.frame.midX, y: createButton.frame.midY)
    }

    func submit() { onCreate?(currentSpec()) }

    @objc private func pressClose() { onClose?() }
    @objc private func pressCreate() { submit() }

    private static func makeLabel(_ text: String, size: CGFloat = 11, weight: NSFont.Weight = .regular, color: NSColor = Theme.dim) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = Theme.ui(size, weight: weight)
        field.textColor = color
        field.refusesFirstResponder = true
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func presets(for name: String) -> [DocPreset] {
        if name == "已保存" { return saved }
        if name == "最近使用项" {
            let recent = UserDefaults.standard.stringArray(forKey: Workspace.recentKey) ?? []
            return recent.prefix(6).map { path in
                let title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                return DocPreset(name: title, detail: "最近使用", width: 210, height: 297, unit: .mm, mode: .cmyk, raster: 300)
            }
        }
        return catalog[name] ?? []
    }

    private var currentPresets: [DocPreset] { presets(for: category) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let next = presetRects.firstIndex { $0.contains(point) }
        if next != hoverIndex {
            hoverIndex = next
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        layoutTabs()
        layoutCards()
        layoutDetails()
        needsDisplay = true
    }

    private func layoutTabs() {
        let moreFont = Theme.ui(13)
        let moreWidth = ("查看更多" as NSString).size(withAttributes: [.font: moreFont]).width
        moreRect = NSRect(x: bounds.width - 16 - moreWidth, y: bounds.height - Self.tabHeight, width: moreWidth, height: Self.tabHeight)
        let fonts = categories.map { Theme.ui(13, weight: $0 == category ? .semibold : .regular) }
        let widths = zip(categories, fonts).map { name, font in
            (name as NSString).size(withAttributes: [.font: font]).width
        }
        let limit = moreRect.minX - 16
        var gap: CGFloat = 18
        let textWidth = widths.reduce(0, +)
        let needed = textWidth + gap * CGFloat(max(categories.count - 1, 1))
        if 12 + needed > limit {
            gap = max(8, (limit - 12 - textWidth) / CGFloat(max(categories.count - 1, 1)))
        }
        categoryRects = []
        var x: CGFloat = 16
        for width in widths {
            categoryRects.append(NSRect(x: x, y: bounds.height - Self.tabHeight, width: width, height: Self.tabHeight))
            x += width + gap
        }
    }

    private func layoutCards() {
        presetRects = []
        let items = currentPresets
        let columns = 3
        let card = Self.cardSize
        let originX = Self.cardMargin
        var y = bounds.height - Self.tabHeight - Self.cardMargin - card.height
        var index = 0
        while index < items.count && presetRects.count < 9 {
            for column in 0..<columns where index < items.count {
                let x = originX + CGFloat(column) * (card.width + Self.cardGap)
                presetRects.append(NSRect(x: x, y: y, width: card.width, height: card.height))
                index += 1
            }
            y -= card.height + Self.cardGap
        }
    }

    private func layoutDetails() {
        let pad: CGFloat = 20
        let x = bounds.width - Self.detailWidth + pad
        let width = Self.detailWidth - pad * 2
        var top = bounds.height - Self.tabHeight - 16

        func place(_ label: NSTextField) {
            label.isHidden = false
            label.frame = NSRect(x: x, y: top - 14, width: width, height: 14)
            top -= 16
        }

        place(sectionLabel)
        place(nameLabel)
        let save: CGFloat = 28
        nameField.frame = NSRect(x: x, y: top - 24, width: width - save - 8, height: 24)
        saveRect = NSRect(x: x + width - save, y: top - 24, width: save, height: 24)
        top -= 32

        let column = (width - 8) / 2
        widthLabel.isHidden = false
        heightLabel.isHidden = false
        widthLabel.frame = NSRect(x: x, y: top - 14, width: column, height: 14)
        heightLabel.frame = NSRect(x: x + column + 8, y: top - 14, width: column, height: 14)
        top -= 16
        widthField.frame = NSRect(x: x, y: top - 24, width: column, height: 24)
        heightField.frame = NSRect(x: x + column + 8, y: top - 24, width: column, height: 24)
        top -= 32

        place(unitLabel)
        unitRect = NSRect(x: x, y: top - 24, width: width, height: 24)
        top -= 32

        place(orientLabel)
        portraitRect = NSRect(x: x, y: top - 32, width: 88, height: 32)
        landscapeRect = NSRect(x: x + 96, y: top - 32, width: 88, height: 32)
        top -= 40

        place(countLabel)
        countField.frame = NSRect(x: x, y: top - 24, width: width, height: 24)
        top -= 32

        place(bleedLabel)
        let box: CGFloat = 56
        topLabel.frame = NSRect(x: x, y: top - 18, width: 14, height: 16)
        bleedTop.frame = NSRect(x: x + 16, y: top - 24, width: box, height: 24)
        bottomLabel.frame = NSRect(x: x + 80, y: top - 18, width: 14, height: 16)
        bleedBottom.frame = NSRect(x: x + 96, y: top - 24, width: box, height: 24)
        linkRect = NSRect(x: x + width - 24, y: top - 24, width: 24, height: 24)
        top -= 28
        leftLabel.frame = NSRect(x: x, y: top - 18, width: 14, height: 16)
        bleedLeft.frame = NSRect(x: x + 16, y: top - 24, width: box, height: 24)
        rightLabel.frame = NSRect(x: x + 80, y: top - 18, width: 14, height: 16)
        bleedRight.frame = NSRect(x: x + 96, y: top - 24, width: box, height: 24)
        top -= 32

        advancedLabel.isHidden = false
        advancedRect = NSRect(x: x, y: top - 16, width: width, height: 16)
        advancedLabel.frame = NSRect(x: x + 16, y: top - 16, width: width - 16, height: 16)
        top -= 22

        if advancedOpen {
            modeLabel.isHidden = false
            rasterLabel.isHidden = false
            previewLabel.isHidden = false
            place(modeLabel)
            modeRect = NSRect(x: x, y: top - 24, width: width, height: 24)
            top -= 32
            place(rasterLabel)
            rasterRect = NSRect(x: x, y: top - 24, width: width, height: 24)
            top -= 32
            place(previewLabel)
            previewRect = NSRect(x: x, y: top - 24, width: width, height: 24)
            top -= 28
        } else {
            modeLabel.isHidden = true
            rasterLabel.isHidden = true
            previewLabel.isHidden = true
            modeRect = .zero
            rasterRect = .zero
            previewRect = .zero
        }

        moreSettingsRect = NSRect(x: x, y: max(56, top - 16), width: width, height: 16)
        let buttonWidth: CGFloat = 76
        createButton.frame = NSRect(x: bounds.width - 20 - buttonWidth, y: 16, width: buttonWidth, height: 32)
        closeButton.frame = NSRect(x: createButton.frame.minX - 12 - buttonWidth, y: 16, width: buttonWidth, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        Theme.window.setFill()
        bounds.fill()

        let detail = NSRect(x: bounds.width - Self.detailWidth, y: 0, width: Self.detailWidth, height: bounds.height - Self.tabHeight)
        Theme.panel.setFill()
        detail.fill()
        Theme.line.setFill()
        NSRect(x: detail.minX, y: detail.minY, width: 1, height: detail.height).fill()
        NSRect(x: 0, y: bounds.height - Self.tabHeight, width: bounds.width, height: 1).fill()

        drawTabs()
        drawCards()
        drawControls()
        NSGraphicsContext.restoreGraphicsState()

        Theme.line.setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    private func drawTabs() {
        for (index, name) in categories.enumerated() where index < categoryRects.count {
            let rect = categoryRects[index]
            let on = name == category
            let font = Theme.ui(13, weight: on ? .semibold : .regular)
            let color: NSColor = on ? Theme.text : Theme.dim
            (name as NSString).draw(at: NSPoint(x: rect.minX, y: rect.midY - 8), withAttributes: [
                .font: font, .foregroundColor: color
            ])
            if on {
                Theme.text.setFill()
                NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2).fill()
            }
        }
        ("查看更多" as NSString).draw(at: NSPoint(x: moreRect.minX, y: moreRect.midY - 8), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: Theme.dim
        ])
    }

    private func drawCards() {
        let items = currentPresets
        if items.isEmpty {
            let note = category == "已保存" ? "尚无已保存的预设" : "尚无最近使用的文件"
            (note as NSString).draw(at: NSPoint(x: Self.cardMargin, y: bounds.midY), withAttributes: [
                .font: Theme.ui(12), .foregroundColor: Theme.dim
            ])
            return
        }
        for (index, item) in items.enumerated() where index < presetRects.count {
            let rect = presetRects[index]
            let on = index == presetIndex
            let hover = index == hoverIndex
            let card = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            if on || hover {
                Theme.panel.setFill()
                card.fill()
            }
            if on {
                Theme.focus.setStroke()
                card.lineWidth = 1
                card.stroke()
            }
            let page = pageRect(in: rect, preset: item)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: page, xRadius: 1, yRadius: 1).fill()
            Theme.fieldBorder.setStroke()
            let pagePath = NSBezierPath(roundedRect: page, xRadius: 1, yRadius: 1)
            pagePath.lineWidth = 1
            pagePath.stroke()
            Theme.accent.withAlphaComponent(0.35).setFill()
            NSRect(x: page.minX + 8, y: page.midY + 4, width: page.width - 16, height: 3).fill()
            NSRect(x: page.minX + 8, y: page.midY - 6, width: page.width * 0.55, height: 3).fill()
            (item.name as NSString).draw(in: NSRect(x: rect.minX + 12, y: rect.minY + 26, width: rect.width - 24, height: 16), withAttributes: [
                .font: Theme.ui(12, weight: .semibold),
                .foregroundColor: Theme.text
            ])
            (item.detail as NSString).draw(in: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 14), withAttributes: [
                .font: Theme.ui(11),
                .foregroundColor: Theme.dim
            ])
        }
    }

    private func pageRect(in card: NSRect, preset: DocPreset) -> NSRect {
        let box = NSRect(x: card.minX + 28, y: card.minY + 56, width: card.width - 56, height: card.height - 78)
        let aspect = CGFloat(preset.width / max(preset.height, 1))
        var pageW = box.width
        var pageH = pageW / max(aspect, 0.2)
        if pageH > box.height {
            pageH = box.height
            pageW = pageH * aspect
        }
        return NSRect(x: box.midX - pageW / 2, y: box.midY - pageH / 2, width: pageW, height: pageH)
    }

    private func drawControls() {
        drawSave(saveRect)
        drawMenu(unitRect, title: unitTitle)
        drawOrient(portraitRect, portrait: true, selected: portrait)
        drawOrient(landscapeRect, portrait: false, selected: !portrait)
        drawLink(linkRect)
        drawDisclosure(advancedRect, open: advancedOpen)
        if advancedOpen {
            drawMenu(modeRect, title: mode == .cmyk ? "CMYK 颜色" : "RGB 颜色")
            drawMenu(rasterRect, title: "\(Int(raster)) ppi")
            drawMenu(previewRect, title: preview)
        }
        ("更多设置" as NSString).draw(at: NSPoint(x: moreSettingsRect.minX + 16, y: moreSettingsRect.minY), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: Theme.text
        ])
        drawDisclosure(moreSettingsRect, open: moreOpen)
        if moreOpen {
            ("颜色配置文件    默认" as NSString).draw(at: NSPoint(x: moreSettingsRect.minX, y: moreSettingsRect.minY - 22), withAttributes: [
                .font: Theme.ui(11), .foregroundColor: Theme.dim
            ])
        }
    }

    private func drawMenu(_ rect: NSRect, title: String) {
        guard rect.width > 1 else { return }
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        Theme.field.setFill()
        path.fill()
        Theme.fieldBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
        (title as NSString).draw(at: NSPoint(x: rect.minX + 8, y: rect.midY - 7), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: Theme.text
        ])
        chevronDown(in: NSRect(x: rect.maxX - 16, y: rect.midY - 3, width: 8, height: 6))
    }

    private func drawOrient(_ rect: NSRect, portrait flag: Bool, selected: Bool) {
        guard rect.width > 1 else { return }
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        Theme.field.setFill()
        path.fill()
        (selected ? Theme.focus : Theme.fieldBorder).setStroke()
        path.lineWidth = 1
        path.stroke()
        let page = flag
            ? NSRect(x: rect.minX + 10, y: rect.minY + 6, width: 12, height: 18)
            : NSRect(x: rect.minX + 8, y: rect.minY + 8, width: 18, height: 12)
        NSColor.white.setFill()
        NSBezierPath(rect: page).fill()
        Theme.dim.setStroke()
        NSBezierPath(rect: page).stroke()
        let word = flag ? "纵向" : "横向"
        (word as NSString).draw(at: NSPoint(x: rect.minX + 32, y: rect.midY - 7), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: Theme.text
        ])
    }

    private func drawSave(_ rect: NSRect) {
        guard rect.width > 1 else { return }
        Theme.icon.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.minX + 6, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX + 6, y: rect.minY + 6))
        path.line(to: NSPoint(x: rect.maxX - 6, y: rect.minY + 6))
        path.line(to: NSPoint(x: rect.maxX - 6, y: rect.midY))
        path.move(to: NSPoint(x: rect.midX, y: rect.maxY - 5))
        path.line(to: NSPoint(x: rect.midX, y: rect.midY - 1))
        path.move(to: NSPoint(x: rect.midX - 4, y: rect.midY + 3))
        path.line(to: NSPoint(x: rect.midX, y: rect.midY - 1))
        path.line(to: NSPoint(x: rect.midX + 4, y: rect.midY + 3))
        path.stroke()
    }

    private func drawLink(_ rect: NSRect) {
        guard rect.width > 1 else { return }
        let color: NSColor = bleedLinked ? Theme.focus : Theme.dim
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        let left = NSRect(x: rect.minX + 3, y: rect.midY - 4, width: 8, height: 8)
        let right = NSRect(x: rect.midX, y: rect.midY - 4, width: 8, height: 8)
        path.appendOval(in: left)
        path.appendOval(in: right)
        path.move(to: NSPoint(x: left.midX, y: left.midY))
        path.line(to: NSPoint(x: right.midX, y: right.midY))
        path.stroke()
    }

    private func drawDisclosure(_ rect: NSRect, open: Bool) {
        guard rect.width > 1 else { return }
        if open {
            chevronDown(in: NSRect(x: rect.minX, y: rect.midY - 3, width: 8, height: 6))
        } else {
            chevronRight(in: NSRect(x: rect.minX, y: rect.midY - 4, width: 6, height: 8))
        }
    }

    private func chevronDown(in rect: NSRect) {
        Theme.dim.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.midX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.stroke()
    }

    private func chevronRight(in rect: NSRect) {
        Theme.dim.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, rect) in categoryRects.enumerated() where rect.contains(point) {
            category = categories[index]
            presetIndex = 0
            hoverIndex = nil
            if let first = currentPresets.first { apply(first) }
            needsLayout = true
            return
        }
        if moreRect.contains(point) {
            category = "免费模板"
            presetIndex = 0
            if let first = currentPresets.first { apply(first) }
            needsLayout = true
            return
        }
        for (index, rect) in presetRects.enumerated() where rect.contains(point) && index < currentPresets.count {
            presetIndex = index
            apply(currentPresets[index])
            return
        }
        if saveRect.contains(point) {
            saveCurrent()
            return
        }
        if unitRect.contains(point) {
            switch unit {
            case .mm: unit = .pt
            case .pt: unit = .px
            case .px: unit = .inch
            case .inch: unit = .mm
            }
            needsDisplay = true
            return
        }
        if portraitRect.contains(point) { choosePortrait(true); return }
        if landscapeRect.contains(point) { choosePortrait(false); return }
        if linkRect.contains(point) {
            bleedLinked.toggle()
            if bleedLinked { syncBleeds(from: bleedTop) }
            needsDisplay = true
            return
        }
        if advancedRect.contains(point) {
            advancedOpen.toggle()
            needsLayout = true
            return
        }
        if modeRect.contains(point) {
            mode = mode == .cmyk ? .rgb : .cmyk
            needsDisplay = true
            return
        }
        if rasterRect.contains(point) {
            if raster < 100 { raster = 150 }
            else if raster < 200 { raster = 300 }
            else { raster = 72 }
            needsDisplay = true
            return
        }
        if previewRect.contains(point) {
            switch preview {
            case "默认值": preview = "像素"
            case "像素": preview = "叠印"
            default: preview = "默认值"
            }
            needsDisplay = true
            return
        }
        if moreSettingsRect.contains(point) {
            moreOpen.toggle()
            needsLayout = true
        }
    }

    private func choosePortrait(_ flag: Bool) {
        guard flag != portrait else { return }
        let width = widthField.stringValue
        widthField.stringValue = heightField.stringValue
        heightField.stringValue = width
        portrait = flag
        needsDisplay = true
    }

    private func apply(_ preset: DocPreset) {
        widthField.stringValue = formatNumber(preset.width)
        heightField.stringValue = formatNumber(preset.height)
        unit = preset.unit
        mode = preset.mode
        raster = preset.raster
        portrait = preset.width <= preset.height
        bleedTop.stringValue = "0"
        bleedBottom.stringValue = "0"
        bleedLeft.stringValue = "0"
        bleedRight.stringValue = "0"
        needsDisplay = true
    }

    private func saveCurrent() {
        let spec = currentSpec()
        let preset = DocPreset(
            name: spec.name.isEmpty ? "未标题-1" : spec.name,
            detail: "\(formatNumber(spec.width)) × \(formatNumber(spec.height)) \(unitTitle)",
            width: spec.width,
            height: spec.height,
            unit: spec.unit,
            mode: spec.colorMode,
            raster: spec.raster
        )
        saved.insert(preset, at: 0)
        category = "已保存"
        presetIndex = 0
        needsLayout = true
    }

    private func syncBleeds(from source: DialogField?) {
        guard bleedLinked, let source else { return }
        let value = source.stringValue
        for field in [bleedTop, bleedBottom, bleedLeft, bleedRight] where field !== source {
            field.stringValue = value
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private var unitTitle: String {
        switch unit {
        case .mm: return "毫米"
        case .pt: return "点"
        case .px: return "像素"
        case .inch: return "英寸"
        }
    }

    private func currentSpec() -> NewDocSpec {
        let top = Double(bleedTop.stringValue) ?? 0
        let bottom = Double(bleedBottom.stringValue) ?? 0
        let left = Double(bleedLeft.stringValue) ?? 0
        let right = Double(bleedRight.stringValue) ?? 0
        return NewDocSpec(
            name: nameField.stringValue,
            width: Double(widthField.stringValue) ?? 210,
            height: Double(heightField.stringValue) ?? 297,
            unit: unit,
            colorMode: mode,
            artboards: max(1, Int(countField.stringValue) ?? 1),
            bleed: top,
            raster: raster,
            portrait: portrait,
            bleedTop: top,
            bleedBottom: bleedLinked ? top : bottom,
            bleedLeft: bleedLinked ? top : left,
            bleedRight: bleedLinked ? top : right,
            preview: preview
        )
    }
}
