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
            if event.keyCode == 49 {
                self?.workspace.active.model.spaceHeld = false
                return nil
            }
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
            runKeyTest()
        }
        if let dir = ProcessInfo.processInfo.environment["LAMINA_SHOTS"] {
            captureShots(in: dir)
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
        let report = KeyReport(path: path)
        workspace.suppressPanels = true
        root.layoutSubtreeIfNeeded()
        root.showEditor()
        window.makeFirstResponder(root.editor.canvas.drawing)
        func focus() {
            root.dialog.isHidden = true
            window.makeFirstResponder(root.editor.canvas.drawing)
        }
        func expectTool(_ name: String, _ tool: Tool, code: CGKeyCode, flags: CGEventFlags = []) {
            focus()
            inject(code, flags: flags)
            let ok = workspace.active.model.tool == tool
            report.line("\(ok ? "PASS" : "FAIL") \(name) tool=\(workspace.active.model.tool.rawValue)")
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
        focus()
        let before = workspace.active.model.zoom
        inject(24, flags: .maskCommand)
        let zoomedIn = workspace.active.model.zoom > before + 0.001
        report.line("\(zoomedIn ? "PASS" : "FAIL") Cmd+plus zoom=\(workspace.active.model.zoom)")
        let mid = workspace.active.model.zoom
        inject(27, flags: .maskCommand)
        let zoomedOut = workspace.active.model.zoom < mid - 0.001
        report.line("\(zoomedOut ? "PASS" : "FAIL") Cmd+minus zoom=\(workspace.active.model.zoom)")
        focus()
        inject(49, flags: [], keyUp: false)
        let held = workspace.active.model.spaceHeld
        report.line("\(held ? "PASS" : "FAIL") space spaceHeld=\(workspace.active.model.spaceHeld)")
        let canvas = root.editor.canvas.drawing
        let panBefore = workspace.active.model.pan
        if let down = mouse(.leftMouseDown, at: NSPoint(x: 80, y: 80), in: canvas),
           let drag = mouse(.leftMouseDragged, at: NSPoint(x: 180, y: 140), in: canvas),
           let up = mouse(.leftMouseUp, at: NSPoint(x: 180, y: 140), in: canvas) {
            canvas.mouseDown(with: down)
            canvas.mouseDragged(with: drag)
            canvas.mouseUp(with: up)
        }
        let panned = hypot(workspace.active.model.pan.x - panBefore.x, workspace.active.model.pan.y - panBefore.y) > 1
        report.line("\(held && panned ? "PASS" : "FAIL") space-drag pan=\(workspace.active.model.pan.x),\(workspace.active.model.pan.y)")
        inject(49, flags: [], keyDown: false)
        let released = !workspace.active.model.spaceHeld
        report.line("\(released ? "PASS" : "FAIL") space-up spaceHeld=\(workspace.active.model.spaceHeld)")
        workspace.active.model.spaceHeld = false
        focus()
        inject(45, flags: .maskCommand)
        report.line("\(root.dialog.isHidden ? "FAIL" : "PASS") Cmd+N dialog")
        focus()
        workspace.panelRequest = ""
        inject(31, flags: .maskCommand)
        report.line("\(workspace.panelRequest == "open" ? "PASS" : "FAIL") Cmd+O panel=\(workspace.panelRequest)")
        workspace.panelRequest = ""
        inject(1, flags: .maskCommand)
        report.line("\(workspace.panelRequest == "save" ? "PASS" : "FAIL") Cmd+S panel=\(workspace.panelRequest)")
        let model = workspace.active.model
        model.tool = .rectangle
        model.pointerDown(at: Vec2(40, 40), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(140, 120), shift: false, option: false, command: false)
        let drawn = itemCount()
        inject(6, flags: .maskCommand)
        let undone = model.status.contains("还原") && itemCount() < drawn
        report.line("\(undone ? "PASS" : "FAIL") Cmd+Z status=\(model.status) items=\(itemCount())")
        model.tool = .rectangle
        model.pointerDown(at: Vec2(40, 40), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(140, 120), shift: false, option: false, command: false)
        let copiedFrom = itemCount()
        inject(8, flags: .maskCommand)
        report.line("\(model.status.contains("已复制") ? "PASS" : "FAIL") Cmd+C status=\(model.status)")
        inject(9, flags: .maskCommand)
        let pasted = itemCount() > copiedFrom && model.tool == .rectangle
        report.line("\(pasted ? "PASS" : "FAIL") Cmd+V tool=\(model.tool.rawValue) items=\(itemCount())")
        inject(5, flags: .maskCommand)
        report.line("\(model.status.contains("请选择多个对象") || model.status.contains("组") ? "PASS" : "FAIL") Cmd+G status=\(model.status)")
        report.finish()
    }

    /// Build a real CGEvent and hand that same event to AppKit. Posting it
    /// through the HID tap needs Accessibility and, on the CI runner, blocks
    /// the main thread before any result can be written.
    private func inject(_ code: CGKeyCode, flags: CGEventFlags, keyDown: Bool = true, keyUp: Bool = true) {
        if keyDown { deliver(code, flags: flags, isDown: true) }
        if keyUp { deliver(code, flags: flags, isDown: false) }
    }

    private func deliver(_ code: CGKeyCode, flags: CGEventFlags, isDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { return }
        event.flags = flags
        if let text = glyph(for: code, shift: flags.contains(.maskShift)) {
            let units = Array(text.utf16)
            units.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            }
        }
        if let nsEvent = NSEvent(cgEvent: event) {
            NSApp.sendEvent(nsEvent)
            return
        }
        let kind: NSEvent.EventType = isDown ? .keyDown : .keyUp
        let text = glyph(for: code, shift: flags.contains(.maskShift)) ?? ""
        guard let fallback = NSEvent.keyEvent(
            with: kind,
            location: .zero,
            modifierFlags: nsFlags(flags),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: text,
            charactersIgnoringModifiers: text.lowercased(),
            isARepeat: false,
            keyCode: code
        ) else { return }
        NSApp.sendEvent(fallback)
    }

    private func mouse(_ type: NSEvent.EventType, at viewPoint: NSPoint, in view: NSView) -> NSEvent? {
        let location = view.convert(viewPoint, to: nil)
        return NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
    }

    private func itemCount() -> Int {
        workspace.active.model.document.layers.reduce(0) { $0 + $1.items.count }
    }

    private func glyph(for code: CGKeyCode, shift: Bool) -> String? {
        switch code {
        case 49: return " "
        case 24: return shift ? "+" : "="
        case 27: return "-"
        default: break
        }
        let map: [CGKeyCode: String] = [
            0: "a", 1: "s", 5: "g", 6: "z", 8: "c", 9: "v", 11: "b", 14: "e", 15: "r",
            17: "t", 31: "o", 35: "p", 37: "l", 45: "n", 46: "m"
        ]
        guard let letter = map[code] else { return nil }
        return shift ? letter.uppercased() : letter
    }

    private func nsFlags(_ flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        return result
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

private final class KeyReport {
    private let handle: FileHandle
    private var failed = false

    init(path: String) {
        FileManager.default.createFile(atPath: path, contents: Data())
        handle = FileHandle(forWritingAtPath: path) ?? FileHandle.standardError
    }

    func line(_ text: String) {
        if text.hasPrefix("FAIL") { failed = true }
        let data = Data((text + "\n").utf8)
        try? handle.write(contentsOf: data)
        try? handle.synchronize()
        try? FileHandle.standardError.write(contentsOf: data)
    }

    func finish() {
        line(failed ? "FAIL" : "OK")
        exit(failed ? 1 : 0)
    }
}
