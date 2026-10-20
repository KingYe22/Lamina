import AppKit
import LaminaCore

@_silgen_name("LaminaCurrentInputSource")
func laminaCurrentInputSource() -> UnsafePointer<CChar>

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: LaminaWindow!
    private let workspace = Workspace()
    var keyWorkspace: Workspace { workspace }
    private var root: AppRoot!
    private var pendingURLs: [URL] = []
    private var keyLog: FileHandle?
    private var keyRevision = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MacGlyphs.install()
        root = AppRoot(workspace: workspace)
        window = LaminaWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 1011),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.workspace = workspace
        window.title = "Lamina"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.window
        window.contentView = root
        window.delegate = self
        window.initialFirstResponder = root.editor.canvas.drawing
        window.autorecalculatesKeyViewLoop = false
        window.minSize = NSSize(width: 1100, height: 720)
        window.setFrameAutosaveName("LaminaMain")
        window.center()
        // Only the title-bar strip calls performWindowDrag. A pen (or any tool)
        // drag on the canvas must not move the window.
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        MenuBar.install(workspace: workspace)
        reportShortcutTableFailure()
        workspace.onNewDocument = { [weak self] in self?.root.showDialog() }
        workspace.onRevealEditor = { [weak self] in self?.root.showEditor() }
        workspace.onShortcutDiagnostics = { ShortcutDiagnostics.shared.show() }
        workspace.onChange = { [weak self] in
            self?.root.editor.sync()
            if let workspace = self?.workspace {
                MenuBar.refreshEnabled(workspace: workspace)
            }
            self?.window.title = "Lamina"
        }
        root.layoutSubtreeIfNeeded()
        workspace.active.model.viewportSize = Vec2(Double(root.editor.canvas.bounds.width), Double(root.editor.canvas.bounds.height))
        let queued = pendingURLs
        pendingURLs = []
        for url in queued { workspace.open(url: url, place: false) }
        if queued.isEmpty { root.showHome() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.environment["LAMINA_SMOKE"] == "1" {
            let path = ProcessInfo.processInfo.environment["LAMINA_SMOKE_FILE"]
                ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("lamina-started")
            try? "started\n".write(toFile: path, atomically: true, encoding: .utf8)
            exit(0)
        }
        if ProcessInfo.processInfo.environment["LAMINA_KEYTEST"] == "1" {
            armExternalKeyTest()
        }
        if let dir = ProcessInfo.processInfo.environment["LAMINA_SHOTS"] {
            captureShots(in: dir)
        }
    }

    /// The shortcut table is compiled into the binary. A miss used to return ""
    /// and every tool key did nothing, including on a machine where the file
    /// was never copied into the app.
    private func reportShortcutTableFailure() {
        _ = Keymap.entries
        guard let failure = ShortcutSource.failure else { return }
        let line = "Lamina: 快捷键表加载失败：\(failure)\n"
        try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
        workspace.active.model.status = "快捷键表加载失败"
        let testing = ProcessInfo.processInfo.environment["LAMINA_SMOKE"] == "1"
            || ProcessInfo.processInfo.environment["LAMINA_KEYTEST"] == "1"
            || ProcessInfo.processInfo.environment["LAMINA_SHOTS"] != nil
        if testing { exit(1) }
        let alert = NSAlert()
        alert.messageText = "快捷键表没有载入"
        alert.informativeText = "\(failure)。工具快捷键不会生效。"
        alert.alertStyle = .critical
        alert.runModal()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        focusCanvasIfIdle()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusCanvasIfIdle()
    }

    private func focusCanvasIfIdle() {
        guard root?.showingEditor == true, let window else { return }
        if PanelField.anyArmed(in: window) { return }
        CanvasFocus.restore(in: window)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard window != nil else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        for url in urls { workspace.open(url: url, place: false) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for session in workspace.sessions where !workspace.confirmClose(session) {
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Stay on the home screen and publish hit targets. A second process posts
    /// CGEvent HID events, including under Pinyin, so this thread never blocks
    /// inside CGEventPost.
    private func armExternalKeyTest() {
        let path = ProcessInfo.processInfo.environment["LAMINA_KEYTEST_FILE"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("lamina-keys.txt")
        FileManager.default.createFile(atPath: path, contents: nil)
        keyLog = FileHandle(forWritingAtPath: path)
        workspace.suppressPanels = true
        KeyProbe.onChange = { [weak self] _ in self?.writeKeyState() }
        root.layoutSubtreeIfNeeded()
        writeKeyState()
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !PanelField.anyArmed(in: self.window) {
                NSApp.activate(ignoringOtherApps: true)
                self.window.makeKey()
            }
            self.writeKeyState()
        }
    }

    private func writeKeyState() {
        guard let keyLog else { return }
        root.layoutSubtreeIfNeeded()
        root.editor.layoutSubtreeIfNeeded()
        keyRevision += 1
        let model = workspace.active.model
        let phase = root.showingEditor ? "editor" : (root.dialog.isHidden ? "home" : "dialog")
        let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
        let items = model.document.layers.reduce(0) { $0 + $1.items.count }
        let status = model.status
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
        let canvas = root.editor.canvas.drawing
        let mid = NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
        let line = [
            "rev=\(keyRevision)",
            "phase=\(phase)",
            "tool=\(model.tool.rawValue)",
            "zoom=\(Self.plain(model.zoom, digits: 4))",
            "space=\(model.spaceHeld ? 1 : 0)",
            "dialog=\(root.dialog.isHidden ? 0 : 1)",
            "ime=\(Self.currentInputSourceID())",
            "panel=\(workspace.panelRequest)",
            "items=\(items)",
            "responder=\(responder)",
            "status=\(status)",
            "pan=\(Self.plain(model.pan.x, digits: 2)),\(Self.plain(model.pan.y, digits: 2))",
            "frame=\(Self.frameToken(window.frame))",
            "nodes=\(model.penNodes.count)",
            "new=\(Self.cg(root.home, root.home.newButtonCenter()))",
            "create=\(Self.cg(root.dialog, root.dialog.createButtonCenter()))",
            "field=\(Self.cg(root.editor.dock, root.editor.dock.nudgeFieldCenter()))",
            "down=\(Self.cg(canvas, NSPoint(x: mid.x + 260, y: mid.y - 400)))",
            "pen=\(Self.cg(canvas, NSPoint(x: mid.x + 300, y: mid.y - 360)))",
            "drag=\(Self.cg(canvas, NSPoint(x: mid.x + 400, y: mid.y - 320)))",
            "penA=\(Self.cg(canvas, NSPoint(x: mid.x + 180, y: mid.y - 420)))",
            "penB=\(Self.cg(canvas, NSPoint(x: mid.x + 220, y: mid.y - 340)))",
            "penC=\(Self.cg(canvas, NSPoint(x: mid.x + 160, y: mid.y - 260)))"
        ].joined(separator: " ")
        let data = Data((line + "\n").utf8)
        try? keyLog.seekToEnd()
        try? keyLog.write(contentsOf: data)
        try? keyLog.synchronize()
    }

    private static func currentInputSourceID() -> String {
        let raw = String(cString: laminaCurrentInputSource())
        return raw.isEmpty ? "none" : raw
    }

    private static func frameToken(_ frame: NSRect) -> String {
        [
            plain(Double(frame.origin.x), digits: 2),
            plain(Double(frame.origin.y), digits: 2),
            plain(Double(frame.size.width), digits: 2),
            plain(Double(frame.size.height), digits: 2)
        ].joined(separator: ",")
    }

    private static func plain(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func cg(_ view: NSView, _ point: NSPoint) -> String {
        guard let window = view.window else { return "0,0" }
        let inWindow = view.convert(point, to: nil)
        let cocoa = window.convertToScreen(NSRect(origin: inWindow, size: .zero)).origin
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first else { return "0,0" }
        let cgY = primary.frame.height - cocoa.y
        return "\(plain(Double(cocoa.x), digits: 2)),\(plain(Double(cgY), digits: 2))"
    }

    private func captureShots(in directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        root.showHome()
        window.displayIfNeeded()
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        writePNG(root, to: dir.appendingPathComponent("home.png"))
        root.showDialog()
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        writePNG(root, to: dir.appendingPathComponent("new-document.png"))
        root.create(NewDocSpec(name: "未标题-1", width: 210, height: 297, unit: .mm, colorMode: .cmyk, artboards: 1, bleed: 0, raster: 72, portrait: true))
        root.layoutSubtreeIfNeeded()
        root.editor.sync()
        root.displayIfNeeded()
        writePNG(root, to: dir.appendingPathComponent("workspace.png"))
        let model = workspace.active.model
        let board = model.document.currentArtboard.rect
        let start = Vec2(board.midX - 90, board.midY - 60)
        let end = Vec2(board.midX + 70, board.midY + 50)
        model.tool = .rectangle
        model.pointerDown(at: start, shift: false, option: false, command: false)
        model.pointerDrag(to: end, shift: false, option: false, command: false)
        root.editor.canvas.drawing.needsDisplay = true
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        writePNG(root, to: dir.appendingPathComponent("drag-preview.png"))
        model.pointerUp(at: end, shift: false, option: false, command: false)
        let anchor = Vec2(board.midX - 150, board.midY - 30)
        let handle = Vec2(board.midX - 30, board.midY + 150)
        let next = Vec2(board.midX + 160, board.midY + 20)
        let nextHandle = Vec2(board.midX + 230, board.midY - 120)
        model.tool = .pen
        model.pointerDown(at: anchor, shift: false, option: false, command: false)
        model.pointerDrag(to: handle, shift: false, option: false, command: false)
        model.pointerUp(at: handle, shift: false, option: false, command: false)
        model.pointerDown(at: next, shift: false, option: false, command: false)
        model.pointerDrag(to: nextHandle, shift: false, option: false, command: false)
        root.editor.canvas.drawing.needsDisplay = true
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        writePNG(root, to: dir.appendingPathComponent("pen-drawing.png"))
        model.pointerUp(at: nextHandle, shift: false, option: false, command: false)
        root.editor.toolbar.revealTooltipForShot()
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        writePNG(root, to: dir.appendingPathComponent("tooltip.png"))
        root.editor.toolbar.revealFlyoutForShot()
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        writePNG(root, to: dir.appendingPathComponent("tool-flyout.png"))
        exit(0)
    }

    private func writePNG(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
