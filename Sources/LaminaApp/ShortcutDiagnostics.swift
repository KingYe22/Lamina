import AppKit

/// Live log of keys the app actually received, and what they did.
/// Opened from 帮助 › 快捷键诊断.
final class ShortcutDiagnostics {
    static let shared = ShortcutDiagnostics()
    private var window: NSWindow?
    private let text = NSTextView()
    private var lines: [String] = []

    func show() {
        if window == nil { build() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func append(_ line: String) {
        let stamp = Self.clock.string(from: Date())
        lines.append("\(stamp)  \(line)")
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        let value = lines.joined(separator: "\n")
        if Thread.isMainThread {
            text.string = value
            text.scrollToEndOfDocument(nil)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.text.string = value
                self?.text.scrollToEndOfDocument(nil)
            }
        }
    }

    private func build() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "快捷键诊断"
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        text.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        text.string = "在这里按键。每一行是实际收到的 keyCode、输入法和触发的动作。\n拼音模式下字母键如果被输入法吃掉，这里不会出现新行。\n"
        text.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = text
        window.contentView = scroll
        window.center()
        self.window = window
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

enum ShortcutLog {
    static func record(_ event: NSEvent, route: String, action: String) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: [String] = []
        if flags.contains(.control) { mods.append("ctrl") }
        if flags.contains(.option) { mods.append("opt") }
        if flags.contains(.shift) { mods.append("shift") }
        if flags.contains(.command) { mods.append("cmd") }
        let responder = (event.window ?? NSApp.keyWindow)?.firstResponder
        let who = responder.map { String(describing: type(of: $0)) } ?? "无"
        let line = "keyCode=\(event.keyCode) 修饰=\(mods.joined(separator: "+")) 输入法=\(InputSourceName.current) 响应者=\(who) 路径=\(route) 动作=\(action)"
        ShortcutDiagnostics.shared.append(line)
    }
}

enum InputSourceName {
    static var current: String {
        let identifier = NSTextInputContext.current?.selectedKeyboardInputSource ?? "未知"
        if identifier.contains("SCIM") || identifier.contains("Pinyin") || identifier.contains("TCIM") || identifier.localizedCaseInsensitiveContains("pinyin") {
            return "拼音 \(identifier)"
        }
        if identifier.contains("ABC") || identifier.contains("US") || identifier.contains("Roman") {
            return "英文 \(identifier)"
        }
        return identifier
    }
}
