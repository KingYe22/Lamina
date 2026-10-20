import AppKit
import LaminaCore

enum ChordAppKit {
    static func chord(from event: NSEvent) -> KeyChord? {
        var mods = KeyModifiers()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }

        let code = event.keyCode
        switch code {
        case 36: return KeyChord(modifiers: mods, key: .return)
        case 48: return KeyChord(modifiers: mods, key: .tab)
        case 49: return KeyChord(modifiers: mods, key: .space)
        case 51, 117: return KeyChord(modifiers: mods, key: .delete)
        case 53: return KeyChord(modifiers: mods, key: .escape)
        case 123: return KeyChord(modifiers: mods, key: .left)
        case 124: return KeyChord(modifiers: mods, key: .right)
        case 125: return KeyChord(modifiers: mods, key: .down)
        case 126: return KeyChord(modifiers: mods, key: .up)
        case 122: return KeyChord(modifiers: mods, key: .function(1))
        case 120: return KeyChord(modifiers: mods, key: .function(2))
        case 99: return KeyChord(modifiers: mods, key: .function(3))
        case 118: return KeyChord(modifiers: mods, key: .function(4))
        case 96: return KeyChord(modifiers: mods, key: .function(5))
        case 97: return KeyChord(modifiers: mods, key: .function(6))
        case 98: return KeyChord(modifiers: mods, key: .function(7))
        case 100: return KeyChord(modifiers: mods, key: .function(8))
        case 101: return KeyChord(modifiers: mods, key: .function(9))
        case 109: return KeyChord(modifiers: mods, key: .function(10))
        case 103: return KeyChord(modifiers: mods, key: .function(11))
        case 111: return KeyChord(modifiers: mods, key: .function(12))
        case 24:
            if mods == .shift { return KeyChord(modifiers: [], key: .plus) }
            return KeyChord(modifiers: mods, key: .equal)
        case 27:
            return KeyChord(modifiers: mods, key: .minus)
        case 44:
            return KeyChord(modifiers: mods, key: .slash)
        case 42:
            return KeyChord(modifiers: mods, key: .backslash)
        case 33:
            return KeyChord(modifiers: mods, key: .leftBracket)
        case 30:
            return KeyChord(modifiers: mods, key: .rightBracket)
        case 41:
            return KeyChord(modifiers: mods, key: .semicolon)
        case 39:
            return KeyChord(modifiers: mods, key: .quote)
        case 50:
            return KeyChord(modifiers: mods, key: mods.contains(.shift) ? .tilde : .backtick)
        case 43:
            if mods.contains(.shift), !mods.contains(.command), !mods.contains(.option), !mods.contains(.control) {
                return KeyChord(modifiers: [], key: .lessThan)
            }
            return KeyChord(modifiers: mods, key: .comma)
        case 47:
            if mods.contains(.shift), !mods.contains(.command), !mods.contains(.option), !mods.contains(.control) {
                return KeyChord(modifiers: [], key: .greaterThan)
            }
            return KeyChord(modifiers: mods, key: .period)
        default:
            break
        }
        if let letter = letter(for: code) ?? number(for: code) {
            return KeyChord(modifiers: mods, key: .character(letter))
        }
        return nil
    }

    static func menuEquivalent(_ chord: KeyChord) -> (String, NSEvent.ModifierFlags)? {
        guard chord.menuEligible else { return nil }
        var flags: NSEvent.ModifierFlags = []
        if chord.modifiers.contains(.command) { flags.insert(.command) }
        if chord.modifiers.contains(.shift) { flags.insert(.shift) }
        if chord.modifiers.contains(.option) { flags.insert(.option) }
        if chord.modifiers.contains(.control) { flags.insert(.control) }
        let key: String
        switch chord.key {
        case .character(let c): key = String(c).lowercased()
        case .function(let n):
            guard let scalar = UnicodeScalar(0xF704 + n - 1) else { return nil }
            key = String(Character(scalar))
        case .equal: key = "="
        case .minus: key = "-"
        case .plus: key = "+"
        case .space: key = " "
        case .delete: key = String(Character(UnicodeScalar(127)!))
        case .return: key = "\r"
        case .tab: key = "\t"
        case .escape: key = String(Character(UnicodeScalar(27)!))
        case .left: key = String(Character(UnicodeScalar(0xF702)!))
        case .right: key = String(Character(UnicodeScalar(0xF703)!))
        case .up: key = String(Character(UnicodeScalar(0xF700)!))
        case .down: key = String(Character(UnicodeScalar(0xF701)!))
        case .leftBracket: key = "["
        case .rightBracket: key = "]"
        case .comma: key = ","
        case .period: key = "."
        case .slash: key = "/"
        case .backslash: key = "\\"
        case .semicolon: key = ";"
        case .quote: key = "'"
        case .backtick: key = "`"
        case .lessThan: key = "<"
        case .greaterThan: key = ">"
        case .tilde: key = "~"
        default: return nil
        }
        return (key, flags)
    }

    private static func letter(for code: UInt16) -> Character? {
        let map: [UInt16: Character] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
            31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m"
        ]
        return map[code]
    }

    private static func number(for code: UInt16) -> Character? {
        let map: [UInt16: Character] = [
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0"
        ]
        return map[code]
    }
}

enum KeyRouter {
    private static var lastStamp: TimeInterval = -1
    private static var lastCode: UInt16 = .max

    /// True only while a visible, editable text view is the field editor.
    /// A bare NSTextField that is not editing, and the canvas, do not count.
    /// The decision uses keyCode, never charactersIgnoringModifiers.
    static func isActivelyEditing(_ event: NSEvent) -> Bool {
        let window = event.window ?? NSApp.keyWindow
        guard let text = window?.firstResponder as? NSTextView else { return false }
        if text.isHiddenOrHasHiddenAncestor { return false }
        if !text.isEditable { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandish = flags.contains(.command) || flags.contains(.control)
        if !commandish { return true }
        // a c v x z — physical codes, so Pinyin cannot rename them.
        let editingChords: Set<UInt16> = [0, 8, 9, 7, 6]
        if flags.contains(.command), !flags.contains(.option), !flags.contains(.control), editingChords.contains(event.keyCode) {
            return true
        }
        return false
    }

    static func handle(_ event: NSEvent, workspace: Workspace) -> NSEvent? {
        if event.type != .keyDown { return event }
        if event.timestamp == lastStamp, event.keyCode == lastCode {
            return nil
        }
        let model = workspace.active.model
        if isActivelyEditing(event), model.editingText == nil {
            ShortcutLog.record(event, route: "交给正在编辑的文本框", action: "—")
            return event
        }
        func consume(_ route: String, _ action: String) -> NSEvent? {
            lastStamp = event.timestamp
            lastCode = event.keyCode
            ShortcutLog.record(event, route: route, action: action)
            return nil
        }
        if event.keyCode == 49 {
            model.spaceHeld = true
            return consume("空格", "临时抓手")
        }
        if event.keyCode == 126 || event.keyCode == 125, model.adjustLiveSides(up: event.keyCode == 126) {
            workspace.touch()
            return consume("绘制中", model.status)
        }
        if event.keyCode == 36, model.editingText == nil {
            model.requestToolOptions()
            workspace.touch()
            return consume("keyCode", "工具选项")
        }
        if model.editingText != nil,
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control) {
            if event.keyCode == 53 {
                model.editingText = nil
                workspace.touch()
                return consume("文字", "结束编辑")
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                workspace.replaceEditingText { text in
                    if !text.isEmpty { text.removeLast() }
                }
                return consume("文字", "删除")
            }
            if let chars = event.characters, !chars.isEmpty {
                workspace.replaceEditingText { text in text += chars }
                return consume("文字", "输入")
            }
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandish = flags.contains(.command) || flags.contains(.control)
        guard let chord = ChordAppKit.chord(from: event) else {
            if commandish { return event }
            focusCanvas(workspace)
            return consume("keyCode 未映射", "吞掉，避免输入法开始组字")
        }
        let before = model.tool
        if model.keyDown(chord: chord) {
            workspace.touch()
            let action = model.tool != before ? model.tool.title : model.status
            focusCanvas(workspace)
            return consume("keyCode", action)
        }
        if commandish {
            ShortcutLog.record(event, route: "keyCode", action: "交给菜单")
            return event
        }
        focusCanvas(workspace)
        return consume("keyCode", "无匹配，已吞掉")
    }

    private static func focusCanvas(_ workspace: Workspace) {
        guard workspace.editorIsKey else { return }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        if window.firstResponder is NSTextView, (window.firstResponder as? NSTextView)?.isEditable == true,
           (window.firstResponder as? NSView)?.isHiddenOrHasHiddenAncestor == false {
            return
        }
        if let canvas = findCanvas(window.contentView), window.firstResponder !== canvas {
            window.makeFirstResponder(canvas)
        }
    }

    private static func findCanvas(_ view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is VectorCanvas { return view }
        for child in view.subviews {
            if let found = findCanvas(child) { return found }
        }
        return nil
    }
}
