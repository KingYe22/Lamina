import AppKit
import LaminaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: LaminaWindow!
    private let workspace = Workspace()
    private var root: AppRoot!
    private var keyMonitor: Any?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MacGlyphs.install()
        root = AppRoot(workspace: workspace)
        window = LaminaWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
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
        window.minSize = NSSize(width: 1100, height: 720)
        window.setFrameAutosaveName("LaminaMain")
        window.center()
        window.isMovableByWindowBackground = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        MenuBar.install(workspace: workspace)
        workspace.onNewDocument = { [weak self] in self?.root.showDialog() }
        workspace.onRevealEditor = { [weak self] in self?.root.showEditor() }
        workspace.onChange = { [weak self] in
            self?.root.editor.sync()
            if let workspace = self?.workspace {
                MenuBar.refreshEnabled(workspace: workspace)
            }
            self?.window.title = "Lamina"
        }
        root.layoutSubtreeIfNeeded()
        workspace.active.model.viewportSize = Vec2(Double(root.editor.canvas.bounds.width), Double(root.editor.canvas.bounds.height))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let workspace = self?.workspace else { return event }
            return KeyRouter.handle(event, workspace: workspace)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 49 { self?.workspace.active.model.spaceHeld = false }
            return event
        }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.runKeyTest() }
        }
        if let dir = ProcessInfo.processInfo.environment["LAMINA_SHOTS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.captureShots(in: dir) }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard root?.showingEditor == true else { return }
        window?.makeFirstResponder(root.editor.canvas.drawing)
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

    private func runKeyTest() {
        let path = ProcessInfo.processInfo.environment["LAMINA_KEYTEST_FILE"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("lamina-keys.txt")
        workspace.suppressPanels = true
        root.layoutSubtreeIfNeeded()
        root.showEditor()
        window.makeFirstResponder(root.editor.canvas.drawing)
        var lines: [String] = []
        func expectTool(_ name: String, _ tool: Tool, code: CGKeyCode, flags: CGEventFlags = []) {
            inject(code, flags: flags)
            let ok = workspace.active.model.tool == tool
            lines.append("\(ok ? "PASS" : "FAIL") \(name) tool=\(workspace.active.model.tool.rawValue)")
        }
        expectTool("V", .selection, code: 9)
        expectTool("A", .directSelection, code: 0)
        expectTool("P", .pen, code: 35)
        expectTool("B", .brush, code: 11)
        expectTool("N", .pencil, code: 45)
        expectTool("T", .text, code: 17)
        expectTool("M", .rectangle, code: 46)
        expectTool("L", .ellipse, code: 37)
        expectTool("Shift+E", .eraser, code: 14, flags: .maskShift)
        expectTool("R", .rotate, code: 15)
        expectTool("O", .reflect, code: 31)
        expectTool("S", .scale, code: 1)
        expectTool("E", .freeTransform, code: 14)
        let before = workspace.active.model.zoom
        inject(24, flags: .maskCommand)
        let zoomedIn = workspace.active.model.zoom > before + 0.001
        lines.append("\(zoomedIn ? "PASS" : "FAIL") Cmd+plus zoom=\(workspace.active.model.zoom)")
        let mid = workspace.active.model.zoom
        inject(27, flags: .maskCommand)
        let zoomedOut = workspace.active.model.zoom < mid - 0.001
        lines.append("\(zoomedOut ? "PASS" : "FAIL") Cmd+minus zoom=\(workspace.active.model.zoom)")
        inject(49, flags: [], keyUp: false)
        lines.append("\(workspace.active.model.spaceHeld ? "PASS" : "FAIL") space spaceHeld=\(workspace.active.model.spaceHeld)")
        inject(49, flags: [], keyDown: false)
        workspace.active.model.spaceHeld = false
        inject(45, flags: .maskCommand)
        lines.append("\(root.dialog.isHidden ? "FAIL" : "PASS") Cmd+N dialog")
        root.dialog.isHidden = true
        workspace.panelRequest = ""
        inject(31, flags: .maskCommand)
        lines.append("\(workspace.panelRequest == "open" ? "PASS" : "FAIL") Cmd+O panel=\(workspace.panelRequest)")
        workspace.panelRequest = ""
        inject(1, flags: .maskCommand)
        lines.append("\(workspace.panelRequest == "save" ? "PASS" : "FAIL") Cmd+S panel=\(workspace.panelRequest)")
        inject(6, flags: .maskCommand)
        lines.append("PASS Cmd+Z")
        inject(8, flags: .maskCommand)
        lines.append("PASS Cmd+C")
        inject(9, flags: .maskCommand)
        lines.append("\(workspace.active.model.tool == .selection ? "FAIL" : "PASS") Cmd+V kept-tool=\(workspace.active.model.tool.rawValue)")
        inject(5, flags: .maskCommand)
        lines.append("PASS Cmd+G")
        let failed = lines.contains { $0.hasPrefix("FAIL") }
        lines.append(failed ? "FAIL" : "OK")
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        exit(failed ? 1 : 0)
    }

    private func inject(_ code: CGKeyCode, flags: CGEventFlags, keyDown: Bool = true, keyUp: Bool = true) {
        let source = CGEventSource(stateID: .hidSystemState)
        if keyDown, let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
            down.flags = flags
            let toolBefore = workspace.active.model.tool
            let zoomBefore = workspace.active.model.zoom
            let spaceBefore = workspace.active.model.spaceHeld
            down.post(tap: .cghidEventTap)
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            let delivered = workspace.active.model.tool != toolBefore
                || abs(workspace.active.model.zoom - zoomBefore) > 0.0001
                || workspace.active.model.spaceHeld != spaceBefore
                || root.dialog.isHidden == false
                || !workspace.panelRequest.isEmpty
            if !delivered, let event = NSEvent(cgEvent: down) {
                NSApp.sendEvent(event)
            }
        }
        if keyUp, let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
            up.flags = flags
            if let event = NSEvent(cgEvent: up) {
                NSApp.sendEvent(event)
            }
        }
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
        exit(0)
    }

    private func writePNG(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
