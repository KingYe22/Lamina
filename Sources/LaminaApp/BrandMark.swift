import AppKit
import LaminaCore
import SwiftUI

/// Draws a vendor SVG from the app bundle. Personal non-commercial identification only.
struct BrandSVGView: View {
    var name: String

    var body: some View {
        Canvas { context, size in
            guard let mark = BrandSVG.mark(named: name), mark.box.width > 0, mark.box.height > 0 else { return }
            let scale = min(size.width / mark.box.width, size.height / mark.box.height)
            let dx = (size.width - mark.box.width * scale) / 2 - mark.box.minX * scale
            let dy = (size.height - mark.box.height * scale) / 2 - mark.box.minY * scale
            for shape in mark.shapes {
                var transform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
                guard let cg = shape.path.copy(using: &transform) else { continue }
                let path = Path(cg)
                if shape.stops.count >= 2 {
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: shape.stops.map { Color(nsColor: $0) }),
                        startPoint: CGPoint(x: 0, y: size.height),
                        endPoint: CGPoint(x: size.width, y: 0)
                    ))
                } else {
                    context.fill(path, with: .color(Color(nsColor: shape.color)))
                }
            }
        }
    }
}

enum BrandSVG {
    struct Shape {
        var path: CGPath
        var color: NSColor
        var stops: [NSColor]
    }

    struct Mark {
        var box: CGRect
        var shapes: [Shape]
    }

    private static var cache: [String: Mark] = [:]

    static func mark(named name: String) -> Mark? {
        if let cached = cache[name] { return cached }
        guard let text = load(name) else { return nil }
        let parsed = parse(text)
        cache[name] = parsed
        return parsed
    }

    private static func load(_ name: String) -> String? {
        let bundle = Bundle.main
        let candidates = [
            bundle.url(forResource: name, withExtension: "svg", subdirectory: "Brands"),
            bundle.url(forResource: name, withExtension: "svg")
        ]
        for url in candidates.compactMap({ $0 }) {
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        }
        return nil
    }

    static func parse(_ text: String) -> Mark {
        let box = viewBox(text) ?? CGRect(x: 0, y: 0, width: 24, height: 24)
        let classes = styleFills(text)
        let gradients = gradientStops(text)
        var shapes: [Shape] = []
        for tag in tags("path", in: text) {
            guard let d = attribute("d", in: tag) else { continue }
            let path = pathFrom(d)
            let fill = attribute("fill", in: tag)
            let klass = attribute("class", in: tag)
            var color = NSColor.white
            var stops: [NSColor] = []
            if let fill, fill.hasPrefix("url(") {
                let id = fill.replacingOccurrences(of: "url(#", with: "").replacingOccurrences(of: ")", with: "")
                stops = gradients[id] ?? []
                color = stops.first ?? .white
            } else if let fill, fill != "none" {
                color = colorValue(fill)
            } else if let klass, let painted = classes[klass] {
                color = painted
            } else if let painted = classes.values.first, fill == nil {
                color = painted
            }
            shapes.append(Shape(path: path, color: color, stops: stops))
        }
        return Mark(box: box, shapes: shapes)
    }

    private static func viewBox(_ text: String) -> CGRect? {
        guard let raw = attribute("viewBox", in: text) else { return nil }
        let nums = raw.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard nums.count >= 4 else { return nil }
        return CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
    }

    private static func styleFills(_ text: String) -> [String: NSColor] {
        guard let start = text.range(of: "<style"), let end = text.range(of: "</style>") else { return [:] }
        let css = String(text[start.upperBound..<end.lowerBound])
        var map: [String: NSColor] = [:]
        var rest = css
        while let dot = rest.firstIndex(of: "."), let brace = rest[dot...].firstIndex(of: "{"), let close = rest[brace...].firstIndex(of: "}") {
            let name = rest[rest.index(after: dot)..<brace].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(rest[rest.index(after: brace)..<close])
            if let range = body.range(of: "fill:") {
                let value = body[range.upperBound...].prefix { $0 != ";" }.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { map[name] = colorValue(value) }
            }
            rest = String(rest[rest.index(after: close)...])
        }
        return map
    }

    private static func gradientStops(_ text: String) -> [String: [NSColor]] {
        var map: [String: [NSColor]] = [:]
        var rest = text
        while let start = rest.range(of: "<radialGradient"), let close = rest.range(of: "</radialGradient>") {
            let block = String(rest[start.lowerBound..<close.upperBound])
            let id = attribute("id", in: block) ?? ""
            var stops: [NSColor] = []
            for tag in tags("stop", in: block) {
                if let color = attribute("stop-color", in: tag) { stops.append(colorValue(color)) }
            }
            if !id.isEmpty { map[id] = stops }
            rest = String(rest[close.upperBound...])
        }
        return map
    }

    private static func tags(_ name: String, in text: String) -> [String] {
        var found: [String] = []
        var rest = text
        let open = "<\(name)"
        while let range = rest.range(of: open) {
            let tail = rest[range.lowerBound...]
            if let end = tail.firstIndex(of: ">") {
                found.append(String(tail[...end]))
                rest = String(tail[tail.index(after: end)...])
            } else {
                break
            }
        }
        return found
    }

    private static func attribute(_ key: String, in tag: String) -> String? {
        let patterns = ["\(key)=\"", "\(key)='"]
        for pattern in patterns {
            guard let range = tag.range(of: pattern) else { continue }
            let quote = pattern.last!
            let rest = tag[range.upperBound...]
            guard let end = rest.firstIndex(of: quote) else { continue }
            return String(rest[..<end])
        }
        return nil
    }

    private static func colorValue(_ raw: String) -> NSColor {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "white" { return .white }
        if value == "black" { return .black }
        if value.hasPrefix("#") {
            let rgba = RGBA(hex: value)
            return NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        }
        if value.lowercased().hasPrefix("hsl") {
            let nums = value.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
            if nums.count >= 3 { return hsl(nums[0], nums[1] / 100, nums[2] / 100) }
        }
        return .white
    }

    private static func hsl(_ h: Double, _ s: Double, _ l: Double) -> NSColor {
        let hue = (h.truncatingRemainder(dividingBy: 360)) / 60
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch Int(hue) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return NSColor(srgbRed: r + m, green: g + m, blue: b + m, alpha: 1)
    }

    private static func pathFrom(_ d: String) -> CGPath {
        let path = CGMutablePath()
        let chars = Array(d)
        var i = 0
        var cx = 0.0, cy = 0.0
        var sx = 0.0, sy = 0.0
        var command: Character = "M"

        func skip() {
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "," || c == "\n" || c == "\r" || c == "\t" { i += 1 } else { break }
            }
        }
        func number() -> Double? {
            skip()
            guard i < chars.count else { return nil }
            let start = i
            if chars[i] == "+" || chars[i] == "-" { i += 1 }
            var saw = false
            while i < chars.count, chars[i].isNumber || chars[i] == "." { saw = true; i += 1 }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                i += 1
                if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
                while i < chars.count, chars[i].isNumber { i += 1 }
            }
            guard saw, let value = Double(String(chars[start..<i])) else { i = start; return nil }
            return value
        }
        func take(_ count: Int) -> [Double]? {
            var values: [Double] = []
            for _ in 0..<count {
                guard let value = number() else { return nil }
                values.append(value)
            }
            return values
        }

        while i < chars.count {
            skip()
            if i >= chars.count { break }
            if chars[i].isLetter {
                command = chars[i]
                i += 1
            }
            let relative = command.isLowercase
            switch String(command).lowercased() {
            case "m":
                guard let pair = take(2) else { return path }
                cx = relative ? cx + pair[0] : pair[0]
                cy = relative ? cy + pair[1] : pair[1]
                path.move(to: CGPoint(x: cx, y: cy))
                sx = cx; sy = cy
                command = relative ? "l" : "L"
            case "l":
                guard let pair = take(2) else { return path }
                cx = relative ? cx + pair[0] : pair[0]
                cy = relative ? cy + pair[1] : pair[1]
                path.addLine(to: CGPoint(x: cx, y: cy))
            case "h":
                guard let value = number() else { return path }
                cx = relative ? cx + value : value
                path.addLine(to: CGPoint(x: cx, y: cy))
            case "v":
                guard let value = number() else { return path }
                cy = relative ? cy + value : value
                path.addLine(to: CGPoint(x: cx, y: cy))
            case "c":
                guard let values = take(6) else { return path }
                let x1 = relative ? cx + values[0] : values[0]
                let y1 = relative ? cy + values[1] : values[1]
                let x2 = relative ? cx + values[2] : values[2]
                let y2 = relative ? cy + values[3] : values[3]
                let x = relative ? cx + values[4] : values[4]
                let y = relative ? cy + values[5] : values[5]
                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
                cx = x; cy = y
            case "q":
                guard let values = take(4) else { return path }
                let qx = relative ? cx + values[0] : values[0]
                let qy = relative ? cy + values[1] : values[1]
                let x = relative ? cx + values[2] : values[2]
                let y = relative ? cy + values[3] : values[3]
                let c1 = CGPoint(x: cx + (qx - cx) * 2 / 3, y: cy + (qy - cy) * 2 / 3)
                let c2 = CGPoint(x: x + (qx - x) * 2 / 3, y: y + (qy - y) * 2 / 3)
                path.addCurve(to: CGPoint(x: x, y: y), control1: c1, control2: c2)
                cx = x; cy = y
            case "z":
                path.closeSubpath()
                cx = sx; cy = sy
            default:
                if number() == nil { i += 1 }
            }
        }
        return path
    }
}
