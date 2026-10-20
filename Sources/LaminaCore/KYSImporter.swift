import Foundation

public struct ShortcutOverride: Equatable, Sendable {
    public var label: String
    public var chord: KeyChord?
    public var raw: String
    public init(label: String, chord: KeyChord?, raw: String) {
        self.label = label
        self.chord = chord
        self.raw = raw
    }
}

public struct ImportedShortcutSet: Equatable, Sendable {
    public var name: String
    public var overrides: [ShortcutOverride]
    public init(name: String, overrides: [ShortcutOverride]) {
        self.name = name
        self.overrides = overrides
    }
}

public enum ShortcutSetImporter {
    /// Reads an Illustrator exported shortcut text file or a text `.kys` set.
    /// Supports tab-separated "label \\t chord" exports and `/command [Name] /shortcut [Command+N]` records.
    public static func parse(_ text: String) -> ImportedShortcutSet {
        if text.contains("/shortcut") || text.contains("/version") || text.contains("/command") {
            return parseKYS(text)
        }
        return parseExportText(text)
    }

    public static func exportText(entries: [ShortcutEntry] = Keymap.entries, name: String = "墨线") -> String {
        var lines = ["墨线键盘快捷键", "集: \(name)", ""]
        var category = ""
        for entry in entries {
            if entry.category != category {
                category = entry.category
                lines.append("")
                lines.append(category)
            }
            let chord = entry.chords.first?.display ?? entry.macRaw
            lines.append("\(entry.title)\t\(chord)")
        }
        return lines.joined(separator: "\n")
    }

    private static func parseExportText(_ text: String) -> ImportedShortcutSet {
        var name = "导入的快捷键"
        var overrides: [ShortcutOverride] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("集:") || line.hasPrefix("Set:") || line.hasPrefix("/name") {
                name = line.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? name
                continue
            }
            let parts: [String]
            if line.contains("\t") {
                parts = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                parts = line.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            guard parts.count >= 2 else { continue }
            let label = parts[0]
            let shortcut = parts[1...].joined(separator: " ")
            guard !label.isEmpty, looksLikeShortcut(shortcut) || shortcut.count <= 3 else { continue }
            let chords = ShortcutTableParser.parseMacChords(normalize(shortcut))
            overrides.append(ShortcutOverride(label: label, chord: chords.first, raw: shortcut))
        }
        return ImportedShortcutSet(name: name, overrides: overrides)
    }

    private static func parseKYS(_ text: String) -> ImportedShortcutSet {
        var name = "导入的快捷键"
        if let range = text.range(of: "/name [") ?? text.range(of: "/name[") {
            let tail = text[range.upperBound...]
            if let end = tail.firstIndex(of: "]") {
                name = String(tail[..<end])
            }
        }
        var overrides: [ShortcutOverride] = []
        let pattern = #"/command\s+\[([^\]]+)\]\s+/shortcut\s+\[([^\]]*)\]"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let label = ns.substring(with: match.range(at: 1))
                let shortcut = ns.substring(with: match.range(at: 2))
                let chords = ShortcutTableParser.parseMacChords(normalize(shortcut))
                overrides.append(ShortcutOverride(label: label, chord: chords.first, raw: shortcut))
            }
        }
        let toolPattern = #"/tool\s+\[([^\]]+)\]\s+/shortcut\s+\[([^\]]*)\]"#
        if let regex = try? NSRegularExpression(pattern: toolPattern) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let label = ns.substring(with: match.range(at: 1))
                let shortcut = ns.substring(with: match.range(at: 2))
                let chords = ShortcutTableParser.parseMacChords(normalize(shortcut))
                overrides.append(ShortcutOverride(label: label, chord: chords.first, raw: shortcut))
            }
        }
        if overrides.isEmpty {
            return parseExportText(text)
        }
        return ImportedShortcutSet(name: name, overrides: overrides)
    }

    private static func normalize(_ shortcut: String) -> String {
        shortcut
            .replacingOccurrences(of: "Cmd", with: "Command")
            .replacingOccurrences(of: "Opt", with: "Option")
            .replacingOccurrences(of: "Ctrl", with: "Control")
            .replacingOccurrences(of: "⌘", with: "Command+")
            .replacingOccurrences(of: "⇧", with: "Shift+")
            .replacingOccurrences(of: "⌥", with: "Option+")
            .replacingOccurrences(of: "⌃", with: "Control+")
    }

    private static func looksLikeShortcut(_ text: String) -> Bool {
        let markers = ["Command", "Cmd", "Shift", "Option", "Alt", "Ctrl", "Control", "⌘", "⇧", "⌥", "+", "F1", "F2", "F5"]
        return markers.contains { text.contains($0) } || text.count == 1
    }
}

public final class UserKeymap {
    public var overrides: [String: KeyChord] = [:]
    public var setName = "默认"

    public init() {}

    public func apply(_ set: ImportedShortcutSet) {
        setName = set.name
        for override in set.overrides {
            if let chord = override.chord {
                overrides[override.label] = chord
            }
        }
    }

    public func reset() {
        overrides = [:]
        setName = "默认"
    }

    public func chord(for title: String) -> KeyChord? {
        if let custom = overrides[title] { return custom }
        return Keymap.chords(forTitle: title).first
    }
}
