import Foundation

public enum AIResponseParser {
    public static func extractSVG(_ text: String) -> String? {
        if let range = text.range(of: "```svg", options: .caseInsensitive) ?? text.range(of: "```SVG") {
            let rest = text[range.upperBound...]
            if let end = rest.range(of: "```") {
                let body = rest[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if body.contains("<svg") { return body }
            }
        }
        if let range = text.range(of: "```") {
            let rest = text[range.upperBound...]
            if let end = rest.range(of: "```") {
                let body = rest[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if body.contains("<svg") { return String(body) }
            }
        }
        guard let start = text.range(of: "<svg") else { return nil }
        guard let end = text.range(of: "</svg>", options: [], range: start.lowerBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.lowerBound..<end.upperBound])
    }

    public static func extractPalette(_ text: String) -> [(name: String, hex: String)] {
        var source = text
        if let start = text.range(of: "["), let end = text.range(of: "]", options: .backwards), start.lowerBound < end.lowerBound {
            source = String(text[start.lowerBound...end.lowerBound])
        }
        guard let data = source.data(using: .utf8) else { return [] }
        if let rows = try? JSONDecoder().decode([PaletteRow].self, from: data) {
            return rows.compactMap { row in
                let hex = row.hex ?? row.color ?? ""
                guard hex.contains("#") || hex.count == 6 else { return nil }
                let name = row.name ?? "色板"
                return (name, hex.hasPrefix("#") ? hex : "#\(hex)")
            }
        }
        return hexes(in: text).map { ("色板", $0) }
    }

    private struct PaletteRow: Decodable {
        var name: String?
        var hex: String?
        var color: String?
    }

    private static func hexes(in text: String) -> [String] {
        var result: [String] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "#", i + 6 < chars.count {
                let slice = chars[(i + 1)...(i + 6)]
                if slice.allSatisfy({ $0.isHexDigit }) {
                    result.append("#" + String(slice))
                    i += 7
                    continue
                }
            }
            i += 1
        }
        return result
    }
}
