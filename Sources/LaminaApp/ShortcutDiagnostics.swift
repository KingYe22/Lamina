import AppKit

/// Live log of keys the app actually received, and what they did.
/// Opened from 帮助 › 快捷键诊断.
final class ShortcutDiagnostics {
    static let shared = ShortcutDiagnostics()
    private var window: NSWindow?
    private let text = NSTextView()
    private let header = NSTextField(labelWithString: "")
    private var lines: [String] = []
    private var timer: Timer?

    func show() {
        if window == nil { build() }
        refreshHeader()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self = self, self.window?.isVisible == true else {
                timer.invalidate()
                return
            }
            self.refreshHeader()
        }
    }

    func append(_ line: String) {
        let stamp = Self.clock.string(from: Date())
        lines.append("\(stamp)  \(line)")
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        let value = lines.joined(separator: "\n")
        if Thread.isMainThread {
            text.string = value
            text.scrollToEndOfDocument(nil)
            refreshHeader()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.text.string = value
                self?.text.scrollToEndOfDocument(nil)
                self?.refreshHeader()
            }
        }
    }

    private func refreshHeader() {
        let lamina = NSApp.windows.first { $0 is LaminaWindow }
        let name = lamina?.firstResponder.map { String(describing: type(of: $0)) } ?? "无"
        header.stringValue = "当前 first responder：\(name)"
    }

    private func build() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "快捷键诊断"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 460))
        header.frame = NSRect(x: 0, y: 428, width: 720, height: 32)
        header.autoresizingMask = [.width, .minYMargin]
        header.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        header.textColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        header.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 1)
        header.drawsBackground = true
        header.isBezeled = false
        header.isEditable = false
        header.isSelectable = true
        header.refusesFirstResponder = true
        header.alignment = .left
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 428))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        text.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        text.string = "在这里按键。顶部是主窗口当前 first responder 的类名。\n每一行还有 keyCode、输入法、响应者类名和触发的动作。\n面板里的数值框只有点击后才会变成 first responder。\n"
        text.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = text
        content.addSubview(scroll)
        content.addSubview(header)
        window.contentView = content
        window.center()
        self.window = window
        refreshHeader()
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
