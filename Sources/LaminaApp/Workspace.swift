import AppKit
import LaminaCore
import PDFKit
import UniformTypeIdentifiers

final class EditorSession: Identifiable {
    let id = UUID()
    let model: EditorModel
    init(model: EditorModel = EditorModel()) { self.model = model }
    var title: String {
        let name = model.document.title.isEmpty ? "未标题" : model.document.title
        return model.isDirty ? "\(name) •" : name
    }
}

final class Workspace: ObservableObject {
    @Published var sessions: [EditorSession] = []
    @Published var activeIndex = 0
    @Published var revision = 0
    var onChange: (() -> Void)?
    var onNewDocument: (() -> Void)?
    var onDismissDialog: (() -> Bool)?
    var onAcceptDialog: (() -> Bool)?
    var onRevealEditor: (() -> Void)?
    var onShortcutDiagnostics: (() -> Void)?
    var editorIsKey = false
    /// When set, open/save panels record the request instead of running a modal dialog.
    var suppressPanels = false
    var panelRequest = ""

    var active: EditorSession {
        if sessions.isEmpty { addDocument(fit: false) }
        return sessions[min(activeIndex, sessions.count - 1)]
    }

    init() {
        addDocument(fit: false)
    }

    func touch() {
        revision += 1
        objectWillChange.send()
        onChange?()
        if let request = active.model.pendingDialog {
            presentDialog(request)
        }
    }

    func addDocument(size: Vec2 = Vec2(800, 600), title: String = "未标题-1", fit: Bool = true) {
        let session = EditorSession()
        session.model.newDocument(size: size, title: uniqueTitle(title))
        bind(session)
        sessions.append(session)
        activeIndex = sessions.count - 1
        if fit { session.model.fitArtboard() }
        touch()
    }

    func closeActive() {
        guard !sessions.isEmpty else { return }
        if !confirmClose(active) { return }
        sessions.remove(at: activeIndex)
        if sessions.isEmpty { addDocument() }
        activeIndex = min(activeIndex, sessions.count - 1)
        touch()
    }

    func select(index: Int) {
        guard sessions.indices.contains(index) else { return }
        activeIndex = index
        touch()
    }

    @discardableResult
    func confirmClose(_ session: EditorSession) -> Bool {
        guard session.model.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "存储对“\(session.model.document.title)”的更改？"
        alert.informativeText = "未存储的更改会丢失。"
        alert.addButton(withTitle: "存储")
        alert.addButton(withTitle: "不存储")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return save(session, copy: false, forceDialog: session.model.fileURL == nil)
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func handle(_ action: String, session: EditorSession) -> Bool {
        if action == "快捷键诊断" {
            onShortcutDiagnostics?()
            return true
        }
        if let tool = Keymap.toolForTitle[action] {
            session.model.tool = tool
            session.model.status = tool.title
            return true
        }
        switch action {
        case "在不打开“新建文档”对话框的情况下创建文档":
            addDocument()
            return true
        case "创建文档":
            if session.model.dialogValues.isEmpty {
                if let onNewDocument {
                    onNewDocument()
                    return true
                }
            }
            let values = session.model.dialogValues
            let width = Double(values["width"] ?? "") ?? 800
            let height = Double(values["height"] ?? "") ?? 600
            addDocument(size: Vec2(max(1, width), max(1, height)))
            if (values["mode"] ?? "").lowercased().contains("cmyk") {
                active.model.document.colorMode = .cmyk
            }
            return true
        case "从模板创建文档":
            addDocument(size: Vec2(595, 842), title: "模板-A4")
            return true
        case "打开文档":
            if suppressPanels { panelRequest = "open"; return true }
            openPanel()
            return true
        case "关闭文档窗口":
            closeActive()
            return true
        case "存储对文档所做的更改":
            if suppressPanels { panelRequest = "save"; return true }
            _ = save(session, copy: false, forceDialog: false)
            return true
        case "打开“存储为”对话框":
            _ = save(session, copy: false, forceDialog: true)
            return true
        case "存储文档的副本":
            _ = save(session, copy: true, forceDialog: true)
            return true
        case "恢复":
            revert(session)
            return true
        case "将文件置入文档":
            openPanel(place: true)
            return true
        case "导出为", "打开“导出为多种屏幕所用格式”对话框", "打开“存储为 Web 所用格式”对话框":
            export(session)
            return true
        case "打印":
            printDocument(session)
            return true
        case "打包文档":
            pack(session)
            return true
        case "退出应用程序":
            NSApp.terminate(nil)
            return true
        case "关于墨线":
            inform("墨线", "个人使用的 macOS 矢量编辑器。界面文字与默认快捷键来自 Adobe Illustrator 的公开帮助文档，程序没有反编译 Illustrator。")
            return true
        case "关于快捷键来源":
            inform("快捷键来源", "默认快捷键表是 Adobe Illustrator 帮助中心公开页面的中文 Mac 快捷键。也可以导入 Illustrator 导出的 .kys 或文本快捷键集。")
            return true
        case "打开“键盘快捷键”对话框", "键盘快捷键说明":
            importShortcuts()
            return true
        case "清除最近的文件":
            UserDefaults.standard.removeObject(forKey: Self.recentKey)
            return true
        default:
            return false
        }
    }

    func openPanel(place: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.readableTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url, place: place)
    }

    func open(url: URL, place: Bool) {
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()
            if place {
                try placeFile(url: url, data: data, into: active)
            } else if ext == "svg" {
                let document = try SVGCodec.read(String(decoding: data, as: UTF8.self))
                install(document, url: url)
            } else if let document = try? EditableFile.open(data: data, title: url.deletingPathExtension().lastPathComponent) {
                install(document, url: url)
            } else if ext == "pdf" || ext == "ai" {
                install(try pdfDocument(data, title: url.deletingPathExtension().lastPathComponent), url: url)
            } else {
                try placeFile(url: url, data: data, into: active)
            }
            remember(url)
            onRevealEditor?()
        } catch {
            inform("无法打开", error.localizedDescription)
        }
    }

    @discardableResult
    func save(_ session: EditorSession, copy: Bool, forceDialog: Bool) -> Bool {
        let url: URL
        if let existing = session.model.fileURL, !forceDialog, !copy {
            url = URL(fileURLWithPath: existing)
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [Self.aiType]
            panel.nameFieldStringValue = session.model.document.title + ".ai"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let picked = panel.url else { return false }
            url = picked
        }
        do {
            let data = try AIFile.data(from: session.model.document)
            try data.write(to: url)
            if !copy {
                session.model.fileURL = url.path
                session.model.document.title = url.deletingPathExtension().lastPathComponent
                session.model.markSaved()
            }
            remember(url)
            session.model.status = copy ? "已存储副本" : "已存储"
            touch()
            return true
        } catch {
            inform("无法存储", error.localizedDescription)
            return false
        }
    }

    func export(_ session: EditorSession) {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        popup.addItems(withTitles: ["PDF", "PNG", "SVG"])
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf, .png, Self.svgType]
        panel.nameFieldStringValue = session.model.document.title
        panel.accessoryView = popup
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let format = popup.indexOfSelectedItem
        do {
            switch format {
            case 1:
                guard let png = CanvasDrawing.renderPNG(session.model.document, scale: 2) else { return }
                try png.write(to: url.pathExtension.lowercased() == "png" ? url : url.appendingPathExtension("png"))
            case 2:
                let svg = SVGCodec.write(session.model.document)
                let target = url.pathExtension.lowercased() == "svg" ? url : url.appendingPathExtension("svg")
                try svg.data(using: .utf8)?.write(to: target)
            default:
                let data = try AIFile.data(from: session.model.document)
                let target = url.pathExtension.lowercased() == "pdf" ? url : url.appendingPathExtension("pdf")
                try data.write(to: target)
            }
            session.model.status = "已导出"
            touch()
        } catch {
            inform("无法导出", error.localizedDescription)
        }
    }

    func printDocument(_ session: EditorSession) {
        guard let data = try? AIFile.data(from: session.model.document), let pdf = PDFDocument(data: data) else { return }
        pdf.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)?.run()
    }

    func pack(_ session: EditorSession) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "打包到这里"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let name = session.model.document.title
        let destination = folder.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let ai = try AIFile.data(from: session.model.document)
            try ai.write(to: destination.appendingPathComponent(name + ".ai"))
            try SVGCodec.write(session.model.document).data(using: .utf8)?.write(to: destination.appendingPathComponent(name + ".svg"))
            if let png = CanvasDrawing.renderPNG(session.model.document, scale: 2) {
                try png.write(to: destination.appendingPathComponent(name + ".png"))
            }
            session.model.status = "已打包"
            touch()
        } catch {
            inform("无法打包", error.localizedDescription)
        }
    }

    func importShortcuts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .data]
        panel.message = "选择 Illustrator 导出的 .kys 或文本快捷键集"
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let set = ShortcutSetImporter.parse(text)
        for session in sessions { session.model.keymap.apply(set) }
        active.model.status = "已导入快捷键集 \(set.name)（\(set.overrides.count) 条）"
        touch()
    }

    func replaceEditingText(_ body: (inout String) -> Void) {
        let model = active.model
        guard let id = model.editingText else { return }
        model.beginChange()
        _ = model.document.updateItem(id) { item in
            if case .text(var text) = item {
                body(&text.string)
                item = .text(text)
            }
        }
        touch()
    }

    func applyFillHex(_ hex: String) {
        active.model.applyFill(.solid(RGBA(hex: hex)))
        touch()
    }

    func applyStrokeHex(_ hex: String) {
        var stroke = active.model.currentStroke ?? StrokeStyle()
        stroke.paint = .solid(RGBA(hex: hex))
        active.model.applyStroke(stroke)
        touch()
    }

    func setStrokeWidth(_ width: Double) {
        var stroke = active.model.currentStroke ?? StrokeStyle()
        stroke.width = width
        active.model.applyStroke(stroke)
        touch()
    }

    func setOpacity(_ value: Double) {
        let model = active.model
        model.beginChange()
        for id in model.selection {
            _ = model.document.updateItem(id) { item in
                switch item {
                case .path(var object):
                    object.appearance.opacity = value
                    item = .path(object)
                case .text(var object):
                    object.appearance.opacity = value
                    item = .text(object)
                case .compound(var object):
                    object.appearance.opacity = value
                    item = .compound(object)
                case .group(var object):
                    object.opacity = value
                    item = .group(object)
                default:
                    break
                }
            }
        }
        touch()
    }

    func toggleLayerVisible(_ index: Int) {
        guard active.model.document.layers.indices.contains(index) else { return }
        active.model.beginChange()
        active.model.document.layers[index].visible.toggle()
        touch()
    }

    func toggleLayerLocked(_ index: Int) {
        guard active.model.document.layers.indices.contains(index) else { return }
        active.model.beginChange()
        active.model.document.layers[index].locked.toggle()
        touch()
    }

    func selectLayer(_ index: Int) {
        guard active.model.document.layers.indices.contains(index) else { return }
        active.model.document.activeLayer = index
        let items = active.model.document.layers[index].items.map(\.id)
        active.model.selection = items
        touch()
    }

    func moveLayer(_ index: Int, by delta: Int) {
        let model = active.model
        let next = index + delta
        guard model.document.layers.indices.contains(index), model.document.layers.indices.contains(next) else { return }
        model.beginChange()
        model.document.layers.swapAt(index, next)
        model.document.activeLayer = next
        touch()
    }

    func renameLayer(_ index: Int, name: String) {
        guard active.model.document.layers.indices.contains(index) else { return }
        active.model.document.layers[index].name = name
        touch()
    }

    func stepArtboard(_ delta: Int) {
        let model = active.model
        guard !model.document.artboards.isEmpty else { return }
        let count = model.document.artboards.count
        model.document.activeArtboard = (model.document.activeArtboard + delta + count) % count
        model.fitArtboard()
        touch()
    }

    func presentGenerative() {
        active.model.presentGenerative()
        touch()
    }

    func perform(_ action: String) {
        if action == "创建文档" {
            onNewDocument?()
            return
        }
        _ = active.model.perform(action)
        if let request = active.model.pendingDialog {
            presentDialog(request)
        }
        touch()
    }

    private func presentDialog(_ request: DialogRequest) {
        if suppressPanels {
            panelRequest = "dialog:" + request.action
            active.model.cancelDialog()
            return
        }
        let alert = NSAlert()
        alert.messageText = request.title
        alert.informativeText = request.action
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let height = CGFloat(max(request.fields.count, 1)) * 28
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: height))
        var inputs: [(String, NSTextField)] = []
        for (index, field) in request.fields.enumerated() {
            let y = height - CGFloat(index + 1) * 28 + 4
            let label = NSTextField(labelWithString: field.label)
            label.frame = NSRect(x: 0, y: y, width: 148, height: 20)
            let input = NSTextField(frame: NSRect(x: 154, y: y, width: 180, height: 22))
            input.stringValue = field.value
            holder.addSubview(label)
            holder.addSubview(input)
            inputs.append((field.key, input))
        }
        alert.accessoryView = holder
        if alert.runModal() == .alertFirstButtonReturn {
            var values: [String: String] = [:]
            for (key, field) in inputs { values[key] = field.stringValue }
            active.model.commitDialog(values)
        } else {
            active.model.cancelDialog()
        }
    }

    private func bind(_ session: EditorSession) {
        session.model.dialogsEnabled = true
        session.model.actionHandler = { [weak self, weak session] action in
            guard let self, let session else { return false }
            return self.handle(action, session: session)
        }
    }

    private func install(_ document: LaminaDocument, url: URL) {
        let session = EditorSession()
        var copy = document
        if copy.title == "未标题-1" || copy.title.isEmpty {
            copy.title = url.deletingPathExtension().lastPathComponent
        }
        session.model.replaceDocument(copy)
        session.model.fileURL = url.path
        session.model.markSaved()
        bind(session)
        sessions.append(session)
        activeIndex = sessions.count - 1
        session.model.fitArtboard()
        touch()
    }

    private func placeFile(url: URL, data: Data, into session: EditorSession) throws {
        let ext = url.pathExtension.lowercased()
        if ext == "svg" {
            try session.model.insertSVG(String(decoding: data, as: UTF8.self))
            touch()
            return
        }
        if ext == "ai" || ext == "pdf", let document = try? EditableFile.open(data: data, title: url.deletingPathExtension().lastPathComponent) {
            session.model.beginChange()
            for item in document.layers.flatMap(\.items) {
                session.model.document.layers[session.model.document.activeLayer].items.append(item)
            }
            session.model.selection = document.layers.flatMap { $0.items.map(\.id) }
            touch()
            return
        }
        if ext == "pdf" || ext == "ai" {
            let placed = try pdfDocument(data, title: url.lastPathComponent)
            session.model.beginChange()
            session.model.document.layers[session.model.document.activeLayer].items.append(contentsOf: placed.layers.flatMap(\.items))
            touch()
            return
        }
        let image = NSImage(data: data)
        let size = image?.size ?? NSSize(width: 200, height: 200)
        let placed = PlacedObject(
            name: url.lastPathComponent,
            kind: "image",
            frame: Rect2(x: 40, y: 40, width: Double(size.width), height: Double(size.height)),
            dataBase64: data.base64EncodedString()
        )
        session.model.beginChange()
        session.model.document.layers[session.model.document.activeLayer].items.append(.placed(placed))
        session.model.selection = [placed.id]
        touch()
    }

    private func pdfDocument(_ data: Data, title: String) throws -> LaminaDocument {
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var document = LaminaDocument.blank(title: title, size: Vec2(800, 600))
        document.artboards = []
        document.layers[0].items = []
        var x: Double = 0
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let box = page.bounds(for: .mediaBox)
            let rect = Rect2(x: x, y: 0, width: Double(box.width), height: Double(box.height))
            document.artboards.append(Artboard(name: "页面 \(index + 1)", rect: rect))
            let placed = PlacedObject(
                name: "页面 \(index + 1)",
                kind: "pdf:\(index)",
                frame: rect,
                dataBase64: data.base64EncodedString()
            )
            document.layers[0].items.append(.placed(placed))
            x += Double(box.width) + 40
        }
        if document.artboards.isEmpty { document.artboards = [Artboard(name: "画板 1", rect: Rect2(x: 0, y: 0, width: 800, height: 600))] }
        return document
    }

    private func revert(_ session: EditorSession) {
        guard let path = session.model.fileURL else {
            session.model.status = "没有可恢复的文件"
            touch()
            return
        }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return }
        if let document = try? EditableFile.open(data: data, title: url.deletingPathExtension().lastPathComponent) {
            session.model.replaceDocument(document)
            session.model.fileURL = path
            session.model.markSaved()
        } else if url.pathExtension.lowercased() == "svg", let document = try? SVGCodec.read(String(decoding: data, as: UTF8.self)) {
            session.model.replaceDocument(document)
            session.model.fileURL = path
            session.model.markSaved()
        }
        session.model.status = "已恢复"
        touch()
    }

    private func uniqueTitle(_ title: String) -> String {
        let existing = Set(sessions.map { $0.model.document.title })
        if !existing.contains(title) { return title }
        var index = 2
        while existing.contains("未标题-\(index)") { index += 1 }
        return "未标题-\(index)"
    }

    private func remember(_ url: URL) {
        var recent = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        recent.removeAll { $0 == url.path }
        recent.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(8)), forKey: Self.recentKey)
    }

    private func inform(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.runModal()
    }

    static let recentKey = "lamina.recent"
    static let aiType = UTType(filenameExtension: "ai") ?? .pdf
    static let svgType = UTType(filenameExtension: "svg") ?? .xml
    static var readableTypes: [UTType] {
        [aiType, svgType, .pdf, .png, .jpeg, .tiff]
    }
}
