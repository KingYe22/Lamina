import AppKit
import LaminaCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let workspace = Workspace()
    private var shell: EditorShell!
    private var keyMonitor: Any?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MacGlyphs.install()
        shell = EditorShell(workspace: workspace)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lamina"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.chrome
        window.contentView = shell
        window.minSize = NSSize(width: 960, height: 640)
        window.setFrameAutosaveName("LaminaMain")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        MenuBar.install(workspace: workspace)
        workspace.onChange = { [weak self] in
            self?.shell.sync()
            if let workspace = self?.workspace {
                MenuBar.refreshEnabled(workspace: workspace)
                let title = workspace.active.model.document.title
                self?.window.title = title.isEmpty ? "Lamina" : "Lamina — \(title)"
            }
        }
        shell.layoutSubtreeIfNeeded()
        workspace.active.model.viewportSize = Vec2(Double(shell.canvas.bounds.width), Double(shell.canvas.bounds.height))
        workspace.active.model.fitArtboard()
        shell.sync()
        window.makeFirstResponder(shell.canvas.drawing)
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
}
