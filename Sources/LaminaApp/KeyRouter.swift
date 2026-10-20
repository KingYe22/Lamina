import AppKit
import LaminaCore

/// ANSI virtual key codes. Routing uses these, never `characters`.
enum VirtualKey {
    static let ansiA: UInt16 = 0
    static let ansiS: UInt16 = 1
    static let ansiD: UInt16 = 2
    static let ansiF: UInt16 = 3
    static let ansiH: UInt16 = 4
    static let ansiG: UInt16 = 5
    static let ansiZ: UInt16 = 6
    static let ansiX: UInt16 = 7
    static let ansiC: UInt16 = 8
    static let ansiV: UInt16 = 9
    static let ansiB: UInt16 = 11
    static let ansiQ: UInt16 = 12
    static let ansiW: UInt16 = 13
    static let ansiE: UInt16 = 14
    static let ansiR: UInt16 = 15
    static let ansiY: UInt16 = 16
    static let ansiT: UInt16 = 17
    static let ansiEqual: UInt16 = 24
    static let ansiMinus: UInt16 = 27
    static let ansiO: UInt16 = 31
    static let ansiU: UInt16 = 32
    static let ansiI: UInt16 = 34
    static let ansiP: UInt16 = 35
    static let ansiL: UInt16 = 37
    static let ansiJ: UInt16 = 38
    static let ansiK: UInt16 = 40
    static let ansiN: UInt16 = 45
    static let ansiM: UInt16 = 46
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let escape: UInt16 = 53
    static let up: UInt16 = 126
    static let down: UInt16 = 125
}

enum KeyProbe {
    static var onChange: ((Workspace) -> Void)?
    static func bump(_ workspace: Workspace?) {
        guard let workspace else { return }
        onChange?(workspace)
    }
}

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
        case VirtualKey.returnKey: return KeyChord(modifiers: mods, key: .return)
        case VirtualKey.tab: return KeyChord(modifiers: mods, key: .tab)
        case VirtualKey.space: return KeyChord(modifiers: mods, key: .space)
        case VirtualKey.delete, VirtualKey.forwardDelete: return KeyChord(modifiers: mods, key: .delete)
        case VirtualKey.escape: return KeyChord(modifiers: mods, key: .escape)
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
        case VirtualKey.ansiEqual:
            if mods == .shift { return KeyChord(modifiers: [], key: .plus) }
            return KeyChord(modifiers: mods, key: .equal)
        case VirtualKey.ansiMinus:
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
            VirtualKey.ansiA: "a", VirtualKey.ansiS: "s", VirtualKey.ansiD: "d", VirtualKey.ansiF: "f",
            VirtualKey.ansiH: "h", VirtualKey.ansiG: "g", VirtualKey.ansiZ: "z", VirtualKey.ansiX: "x",
            VirtualKey.ansiC: "c", VirtualKey.ansiV: "v", VirtualKey.ansiB: "b", VirtualKey.ansiQ: "q",
            VirtualKey.ansiW: "w", VirtualKey.ansiE: "e", VirtualKey.ansiR: "r", VirtualKey.ansiY: "y",
            VirtualKey.ansiT: "t", VirtualKey.ansiO: "o", VirtualKey.ansiU: "u", VirtualKey.ansiI: "i",
            VirtualKey.ansiP: "p", VirtualKey.ansiL: "l", VirtualKey.ansiJ: "j", VirtualKey.ansiK: "k",
            VirtualKey.ansiN: "n", VirtualKey.ansiM: "m"
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
    private static var lastConsumed = false

    /// True only while a visible field editor is actually editing.
    /// A panel field that has not been clicked does not count.
    /// The decision uses keyCode, never charactersIgnoringModifiers.
    static func isActivelyEditing(_ event: NSEvent) -> Bool {
        let window = event.window ?? NSApp.keyWindow
        let responder = window?.firstResponder
        let editing: Bool
        if let text = responder as? NSTextView {
            editing = text.isEditable && !text.isHiddenOrHasHiddenAncestor
        } else if let field = responder as? NSTextField {
            editing = field.isEditable && !field.refusesFirstResponder && !field.isHiddenOrHasHiddenAncestor
        } else {
            editing = false
        }
        if !editing { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandish = flags.contains(.command) || flags.contains(.control)
        if !commandish { return true }
        let editingChords: Set<UInt16> = [
            VirtualKey.ansiA, VirtualKey.ansiC, VirtualKey.ansiV, VirtualKey.ansiX, VirtualKey.ansiZ
        ]
        if flags.contains(.command), !flags.contains(.option), !flags.contains(.control), editingChords.contains(event.keyCode) {
            return true
        }
        return false
    }

    static func handle(_ event: NSEvent, workspace: Workspace) -> NSEvent? {
        if event.type != .keyDown { return event }
        if event.timestamp == lastStamp, event.keyCode == lastCode {
            return lastConsumed ? nil : event
        }
        let result = route(event, workspace: workspace)
        lastStamp = event.timestamp
        lastCode = event.keyCode
        lastConsumed = result == nil
        KeyProbe.bump(workspace)
        return result
    }

    private static func route(_ event: NSEvent, workspace: Workspace) -> NSEvent? {
        let model = workspace.active.model
        if isActivelyEditing(event), model.editingText == nil {
            ShortcutLog.record(event, route: "交给正在编辑的文本框", action: "—")
            return event
        }
        func consume(_ route: String, _ action: String) -> NSEvent? {
            ShortcutLog.record(event, route: route, action: action)
            return nil
        }
        if event.keyCode == VirtualKey.escape, model.editingText == nil, !isActivelyEditing(event),
           workspace.onDismissDialog?() == true {
            return consume("Esc", "关闭对话框")
        }
        if event.keyCode == VirtualKey.space {
            model.spaceHeld = true
            return consume("空格", "临时抓手")
        }
        if event.keyCode == VirtualKey.up || event.keyCode == VirtualKey.down, model.adjustLiveSides(up: event.keyCode == VirtualKey.up) {
            workspace.touch()
            return consume("绘制中", model.status)
        }
        if event.keyCode == VirtualKey.returnKey, model.editingText == nil {
            model.requestToolOptions()
            workspace.touch()
            return consume("keyCode", "工具选项")
        }
        if model.editingText != nil,
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control) {
            if event.keyCode == VirtualKey.escape {
                model.editingText = nil
                workspace.touch()
                return consume("文字", "结束编辑")
            }
            if event.keyCode == VirtualKey.delete || event.keyCode == VirtualKey.forwardDelete {
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
