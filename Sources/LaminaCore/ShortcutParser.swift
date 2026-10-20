import Foundation

public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)

    public var menuMaskDescription: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}

public enum KeyID: Hashable, Sendable {
    case character(Character)
    case function(Int)
    case space, escape, tab, delete, `return`
    case left, right, up, down
    case plus, minus, equal
    case semicolon, comma, period, slash, backslash
    case quote, backtick
    case leftBracket, rightBracket
    case lessThan, greaterThan
    case tilde
    case leftBrace, rightBrace

    public var display: String {
        switch self {
        case .character(let c): return String(c).uppercased()
        case .function(let n): return "F\(n)"
        case .space: return "空格"
        case .escape: return "Esc"
        case .tab: return "Tab"
        case .delete: return "⌫"
        case .return: return "↩"
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        case .plus: return "+"
        case .minus: return "-"
        case .equal: return "="
        case .semicolon: return ";"
        case .comma: return ","
        case .period: return "."
        case .slash: return "/"
        case .backslash: return "\\"
        case .quote: return "'"
        case .backtick: return "`"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .lessThan: return "<"
        case .greaterThan: return ">"
        case .tilde: return "~"
        case .leftBrace: return "{"
        case .rightBrace: return "}"
        }
    }
}

public struct KeyChord: Hashable, Sendable {
    public var modifiers: KeyModifiers
    public var key: KeyID

    public init(modifiers: KeyModifiers = [], key: KeyID) {
        self.modifiers = modifiers
        self.key = key
    }

    public var display: String { modifiers.menuMaskDescription + key.display }

    /// Command, Control, or a function key can be shown as an AppKit menu key equivalent.
    public var menuEligible: Bool {
        if modifiers.contains(.command) || modifiers.contains(.control) { return true }
        if case .function = key { return true }
        return false
    }
}

public struct ShortcutEntry: Equatable, Sendable {
    public var index: Int
    public var category: String
    public var title: String
    public var windowsRaw: String
    public var macRaw: String
    public var chords: [KeyChord]

    public var action: String { title }
}

public enum ShortcutSource {
    public static func load() -> String {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "adobe_shortcuts_cn", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           text.contains("Command") {
            return text
        }
        #endif
        if let url = Bundle.main.url(forResource: "adobe_shortcuts_cn", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           text.contains("Command") {
            return text
        }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/adobe_shortcuts_cn.txt")
        if let text = try? String(contentsOf: dev, encoding: .utf8) {
            return text
        }
        return ""
    }
}

public enum ShortcutTableParser {
    public static func parse(_ text: String) -> [ShortcutEntry] {
        let lines = Array(text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        var start = 0
        for (i, line) in lines.enumerated() where line.contains("常用的快捷键") {
            start = i
            break
        }
        let cells = cellsFrom(lines: Array(lines[start...]))
        var entries: [ShortcutEntry] = []
        var category = "常用的快捷键"
        var i = 0
        while i < cells.count {
            if i + 2 < cells.count && cells[i + 1] == "Windows" && cells[i + 2] == "macOS" {
                category = cleanCategory(cells[i])
                i += 3
                continue
            }
            if cells[i] == "Windows" || cells[i] == "macOS" || cells[i] == "快捷键" {
                i += 1
                continue
            }
            if i + 2 >= cells.count { break }
            let name = cells[i]
            let win = cells[i + 1]
            let mac = cells[i + 2]
            if looksLikeShortcut(name) && !containsCJK(name) {
                i += 1
                continue
            }
            entries.append(ShortcutEntry(
                index: entries.count,
                category: category,
                title: name,
                windowsRaw: win,
                macRaw: mac,
                chords: parseMacChords(mac)
            ))
            i += 3
        }
        return entries
    }

    public static func parseMacChords(_ raw: String) -> [KeyChord] {
        var source = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty { return [] }
        source = stripParentheticals(source)
        let bits = source.components(separatedBy: "或").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var result: [KeyChord] = []
        var inherited: KeyModifiers = []
        for (index, bit) in bits.enumerated() {
            let parsed = parseBit(bit)
            if parsed.isEmpty && index == 0 { continue }
            for var chord in parsed {
                if index > 0 && chord.modifiers.isEmpty && !inherited.isEmpty && isLoneKey(bit) {
                    chord = KeyChord(modifiers: inherited, key: chord.key)
                }
                inherited = chord.modifiers.isEmpty ? inherited : chord.modifiers
                result.append(chord)
            }
        }
        if result.isEmpty, let embedded = embeddedChord(in: source) {
            result.append(embedded)
        }
        return result
    }

    private static func cellsFrom(lines: [String]) -> [String] {
        var cells: [String] = []
        var buf: [String] = []
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped == "|" {
                cells.append(buf.joined(separator: " "))
                buf = []
            } else if stripped.hasSuffix("|") {
                var content = stripped
                content.removeLast()
                content = content.trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { buf.append(content) }
                cells.append(buf.joined(separator: " "))
                buf = []
            } else if !stripped.isEmpty {
                buf.append(stripped)
            }
        }
        if !buf.isEmpty { cells.append(buf.joined(separator: " ")) }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func cleanCategory(_ raw: String) -> String {
        var text = raw
        if let range = text.range(of: "快捷键", options: .backwards) {
            text = String(text[..<range.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: "。", options: .backwards) {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if text.isEmpty || text.count > 20 { return "常用的快捷键" }
        return text
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    private static func looksLikeShortcut(_ text: String) -> Bool {
        let prefixes = ["Ctrl", "Alt", "Shift", "Command", "Option", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
        return prefixes.contains { text.hasPrefix($0) }
    }

    private static func stripParentheticals(_ text: String) -> String {
        var result = ""
        var depth = 0
        for ch in text {
            if ch == "(" || ch == "（" { depth += 1; continue }
            if ch == ")" || ch == "）" { depth = max(0, depth - 1); continue }
            if depth == 0 { result.append(ch) }
        }
        return result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func parseBit(_ bit: String) -> [KeyChord] {
        if bit.contains("箭头") {
            let mods = modifiers(in: bit)
            let dirs = arrowKeys(in: bit)
            if !dirs.isEmpty {
                return dirs.map { KeyChord(modifiers: mods, key: $0) }
            }
        }
        if let chord = parseSingle(bit) { return [chord] }
        return []
    }

    private static func arrowKeys(in text: String) -> [KeyID] {
        var keys: [KeyID] = []
        let map: [(String, KeyID)] = [("向左", .left), ("向右", .right), ("向上", .up), ("向下", .down)]
        for (word, key) in map where text.contains(word) && !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    private static func modifiers(in text: String) -> KeyModifiers {
        var mods: KeyModifiers = []
        let lower = text.lowercased()
        if lower.contains("command") || lower.contains("cmd") { mods.insert(.command) }
        if lower.contains("option") || containsToken(text, "alt") { mods.insert(.option) }
        if lower.contains("shift") { mods.insert(.shift) }
        if lower.contains("control") || containsToken(lower, "ctrl") { mods.insert(.control) }
        return mods
    }

    private static func containsToken(_ text: String, _ token: String) -> Bool {
        text.lowercased().contains(token)
    }

    private static func isLoneKey(_ bit: String) -> Bool {
        let trimmed = bit.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("+") { return false }
        return parseKeyToken(trimmed) != nil && modifiers(in: trimmed).isEmpty
    }

    private static func parseSingle(_ text: String) -> KeyChord? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed == "+" || trimmed == "加" { return KeyChord(modifiers: [], key: .plus) }
        let pieces = trimmed.split(separator: "+", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if pieces.isEmpty { return nil }
        var mods: KeyModifiers = []
        var key: KeyID?
        for piece in pieces {
            if let mod = modifierToken(piece) {
                mods.insert(mod)
            } else if key == nil, let parsed = parseKeyToken(piece) {
                key = parsed
            } else {
                return nil
            }
        }
        guard let key else { return nil }
        return KeyChord(modifiers: mods, key: key)
    }

    private static func modifierToken(_ token: String) -> KeyModifiers? {
        switch token.lowercased() {
        case "command", "cmd": return .command
        case "shift": return .shift
        case "option", "alt": return .option
        case "control", "ctrl": return .control
        default: return nil
        }
    }

    private static func parseKeyToken(_ token: String) -> KeyID? {
        let t = token.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        let lower = t.lowercased()
        switch lower {
        case "esc", "escape": return .escape
        case "tab": return .tab
        case "return", "enter": return .return
        case "delete", "删除": return .delete
        case "space", "空格", "空格键": return .space
        case "plus": return .plus
        default: break
        }
        if lower.hasPrefix("f"), let n = Int(lower.dropFirst()), (1...24).contains(n), lower.dropFirst().allSatisfy(\.isNumber) {
            return .function(n)
        }
        if t.count == 1, let ch = t.first {
            return keyFromCharacter(ch)
        }
        // Fullwidth or annotated leftovers such as "。"
        if t == "。" || t == "．" { return .period }
        if t == "，" { return .comma }
        if t == "；" { return .semicolon }
        return nil
    }

    private static func keyFromCharacter(_ ch: Character) -> KeyID? {
        switch ch {
        case "+": return .plus
        case "-": return .minus
        case "=": return .equal
        case ";": return .semicolon
        case "；": return .semicolon
        case ",": return .comma
        case "，": return .comma
        case ".": return .period
        case "。": return .period
        case "/": return .slash
        case "\\": return .backslash
        case "'": return .quote
        case "`": return .backtick
        case "[": return .leftBracket
        case "]": return .rightBracket
        case "<": return .lessThan
        case ">": return .greaterThan
        case "~": return .tilde
        case "{": return .leftBrace
        case "}": return .rightBrace
        case " ": return .space
        default:
            if ch.isLetter || ch.isNumber {
                return .character(Character(ch.lowercased()))
            }
            return nil
        }
    }

    private static func embeddedChord(in text: String) -> KeyChord? {
        // "选择这些路径，然后按 Command+J 组合键"
        guard let range = text.range(of: "Command", options: .caseInsensitive) ?? text.range(of: "Option", options: .caseInsensitive) else {
            return nil
        }
        let tail = String(text[range.lowerBound...])
        var end = tail.endIndex
        for index in tail.indices where tail.distance(from: tail.startIndex, to: index) > 3 && "，,。；; ".contains(tail[index]) {
            end = index
            break
        }
        let candidate = String(tail[..<end])
        return parseSingle(candidate)
    }
}

public enum Tool: String, Codable, CaseIterable, Sendable {
    case selection, directSelection, groupSelection
    case magicWand, lasso
    case pen, addAnchor, deleteAnchor, convertAnchor
    case curvature
    case text, areaText, pathText, verticalText, touchType
    case line, arc, spiral, rectGrid, polarGrid
    case rectangle, roundedRectangle, ellipse, polygon, star, flare
    case brush, blobBrush
    case shaper, pencil, smooth, pathEraser, joinTool
    case eraser, scissors, knife
    case rotate, reflect
    case scale, shear, reshape
    case width, warp
    case freeTransform, puppet
    case shapeBuilder, livePaintBucket, livePaintSelection
    case perspectiveGrid, perspectiveSelection
    case mesh
    case gradient
    case eyedropper, measure
    case blend
    case symbolSprayer
    case columnGraph
    case artboard
    case slice
    case hand, rotateView
    case zoom

    public var title: String {
        switch self {
        case .selection: return "选择"
        case .directSelection: return "直接选择"
        case .groupSelection: return "编组选择"
        case .magicWand: return "魔棒"
        case .lasso: return "套索"
        case .pen: return "钢笔"
        case .addAnchor: return "添加锚点"
        case .deleteAnchor: return "删除锚点"
        case .convertAnchor: return "锚点"
        case .curvature: return "曲率"
        case .text: return "文字"
        case .areaText: return "区域文字"
        case .pathText: return "路径文字"
        case .verticalText: return "直排文字"
        case .touchType: return "修饰文字"
        case .line: return "直线段"
        case .arc: return "弧形"
        case .spiral: return "螺旋线"
        case .rectGrid: return "矩形网格"
        case .polarGrid: return "极坐标网格"
        case .rectangle: return "矩形"
        case .roundedRectangle: return "圆角矩形"
        case .ellipse: return "椭圆"
        case .polygon: return "多边形"
        case .star: return "星形"
        case .flare: return "光晕"
        case .brush: return "画笔"
        case .blobBrush: return "斑点画笔"
        case .shaper: return "Shaper"
        case .pencil: return "铅笔"
        case .smooth: return "平滑"
        case .pathEraser: return "路径橡皮擦"
        case .joinTool: return "连接"
        case .eraser: return "橡皮擦"
        case .scissors: return "剪刀"
        case .knife: return "美工刀"
        case .rotate: return "旋转"
        case .reflect: return "镜像"
        case .scale: return "比例缩放"
        case .shear: return "倾斜"
        case .reshape: return "整形"
        case .width: return "宽度"
        case .warp: return "变形"
        case .freeTransform: return "自由变换"
        case .puppet: return "操控变形"
        case .shapeBuilder: return "形状生成器"
        case .livePaintBucket: return "实时上色"
        case .livePaintSelection: return "实时上色选择"
        case .perspectiveGrid: return "透视网格"
        case .perspectiveSelection: return "透视选区"
        case .mesh: return "网格"
        case .gradient: return "渐变"
        case .eyedropper: return "吸管"
        case .measure: return "度量"
        case .blend: return "混合"
        case .symbolSprayer: return "符号喷枪"
        case .columnGraph: return "柱形图"
        case .artboard: return "画板"
        case .slice: return "切片"
        case .hand: return "抓手"
        case .rotateView: return "旋转视图"
        case .zoom: return "缩放"
        }
    }
}

public enum Keymap {
    public static let entries: [ShortcutEntry] = ShortcutTableParser.parse(ShortcutSource.load())

    public static func entry(title: String) -> ShortcutEntry? {
        entries.first { $0.title == title }
    }

    public static func chords(forTitle title: String) -> [KeyChord] {
        entries.filter { $0.title == title }.flatMap(\.chords)
    }

    public static func entries(matching chord: KeyChord) -> [ShortcutEntry] {
        entries.filter { $0.chords.contains(chord) }
    }

    public static let toolForTitle: [String: Tool] = [
        "画板工具": .artboard,
        "选择工具": .selection,
        "直接选择工具": .directSelection,
        "魔棒工具": .magicWand,
        "套索工具": .lasso,
        "钢笔工具": .pen,
        "曲率工具": .curvature,
        "斑点画笔工具": .blobBrush,
        "添加锚点工具": .addAnchor,
        "删除锚点工具": .deleteAnchor,
        "切换到锚点工具": .convertAnchor,
        "文字工具": .text,
        "修饰文字工具": .touchType,
        "直线段工具": .line,
        "矩形工具": .rectangle,
        "椭圆工具": .ellipse,
        "画笔工具": .brush,
        "铅笔工具": .pencil,
        "Shaper 工具": .shaper,
        "旋转工具": .rotate,
        "镜像工具": .reflect,
        "按比例缩放工具": .scale,
        "变形工具": .warp,
        "宽度工具": .width,
        "自由变换工具": .freeTransform,
        "形状生成器工具": .shapeBuilder,
        "透视网格工具": .perspectiveGrid,
        "透视选区工具": .perspectiveSelection,
        "符号喷枪工具": .symbolSprayer,
        "柱形图工具": .columnGraph,
        "网格工具": .mesh,
        "渐变工具": .gradient,
        "滴管工具": .eyedropper,
        "混合工具": .blend,
        "实时上色油漆桶工具": .livePaintBucket,
        "实时上色选择工具": .livePaintSelection,
        "切片工具": .slice,
        "橡皮擦工具": .eraser,
        "剪刀工具": .scissors,
        "抓手工具": .hand,
        "缩放工具": .zoom,
        "选择形状生成器工具": .shapeBuilder
    ]

    public static let textOnlyTitles: Set<String> = [
        "加粗", "斜体", "下划线", "插入软回车", "创建轮廓",
        "插入字间中点", "插入版权符号", "插入省略号", "插入段落符号", "插入分节符",
        "插入商标符号", "插入注册商标符号", "上标", "下标",
        "插入全角破折号", "插入半角破折号", "插入自由连字符",
        "插入左双引号", "插入右双引号", "插入左单引号", "插入右单引号",
        "插入全角空格", "插入半角空格", "插入窄间隔",
        "左对齐文本", "全部两端对齐", "段落向左对齐、右对齐或居中对齐",
        "增加或减小字体大小", "逐步增加或减小字体大小"
    ]

    /// Prefer a non-text action when the user is not editing text, and the reverse when they are.
    public static func preferredEntry(for chord: KeyChord, editingText: Bool) -> ShortcutEntry? {
        let hits = entries(matching: chord)
        if hits.isEmpty { return nil }
        if editingText, let text = hits.first(where: { textOnlyTitles.contains($0.title) }) {
            return text
        }
        if !editingText, let other = hits.first(where: { !textOnlyTitles.contains($0.title) }) {
            return other
        }
        return hits.first
    }
}
