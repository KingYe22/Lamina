import Foundation

public struct RasterBuffer: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]

    public func png() -> Data { PNGCodec.encode(PNGImage(width: width, height: height, rgba: rgba)) }
}

public enum EffectEngine {
    public static func rasterize(points: [Vec2], fill: RGBA, ppi: Double, padding: Int = 8) -> RasterBuffer {
        let box = Rect2.enclosing(points).expanded(Double(padding))
        let scale = max(1, ppi / 72)
        let width = max(1, Int((box.width * scale).rounded()) + 1)
        let height = max(1, Int((box.height * scale).rounded()) + 1)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard points.count >= 3 else { return RasterBuffer(width: width, height: height, rgba: rgba) }
        let pixels = points.map { Vec2(($0.x - box.x) * scale, ($0.y - box.y) * scale) }
        for y in 0..<height {
            var hits: [Double] = []
            let py = Double(y) + 0.5
            for i in 0..<pixels.count {
                let a = pixels[i]
                let b = pixels[(i + 1) % pixels.count]
                if (a.y > py) == (b.y > py) { continue }
                let x = a.x + (b.x - a.x) * (py - a.y) / (b.y - a.y)
                hits.append(x)
            }
            hits.sort()
            var i = 0
            while i + 1 < hits.count {
                let x0 = max(0, Int(hits[i]))
                let x1 = min(width - 1, Int(hits[i + 1]))
                if x1 >= x0 {
                    for x in x0...x1 {
                        let o = (y * width + x) * 4
                        rgba[o] = UInt8((fill.r * 255).rounded())
                        rgba[o + 1] = UInt8((fill.g * 255).rounded())
                        rgba[o + 2] = UInt8((fill.b * 255).rounded())
                        rgba[o + 3] = UInt8((fill.a * 255).rounded())
                    }
                }
                i += 2
            }
        }
        return RasterBuffer(width: width, height: height, rgba: rgba)
    }

    public static func blur(_ buffer: RasterBuffer, radius: Int) -> RasterBuffer {
        let r = max(0, radius)
        if r == 0 { return buffer }
        var horizontal = buffer.rgba
        let w = buffer.width, h = buffer.height
        func index(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
        for y in 0..<h {
            for x in 0..<w {
                var acc = [0, 0, 0, 0]
                var count = 0
                for k in -r...r {
                    let sx = min(w - 1, max(0, x + k))
                    let o = index(sx, y)
                    for c in 0..<4 { acc[c] += Int(buffer.rgba[o + c]) }
                    count += 1
                }
                let o = index(x, y)
                for c in 0..<4 { horizontal[o + c] = UInt8(acc[c] / count) }
            }
        }
        var vertical = horizontal
        for y in 0..<h {
            for x in 0..<w {
                var acc = [0, 0, 0, 0]
                var count = 0
                for k in -r...r {
                    let sy = min(h - 1, max(0, y + k))
                    let o = index(x, sy)
                    for c in 0..<4 { acc[c] += Int(horizontal[o + c]) }
                    count += 1
                }
                let o = index(x, y)
                for c in 0..<4 { vertical[o + c] = UInt8(acc[c] / count) }
            }
        }
        return RasterBuffer(width: w, height: h, rgba: vertical)
    }

    public static func dropShadow(points: [Vec2], dx: Double, dy: Double, blur blurRadius: Double, color: RGBA, ppi: Double) -> (buffer: RasterBuffer, origin: Vec2) {
        let shifted = points.map { $0 + Vec2(dx, dy) }
        let sharp = rasterize(points: shifted, fill: color, ppi: ppi, padding: Int(blurRadius) + 4)
        let soft = blur(sharp, radius: max(1, Int(blurRadius)))
        let box = Rect2.enclosing(shifted).expanded(Double(Int(blurRadius) + 4))
        return (soft, box.origin)
    }

    public static func placedShadow(points: [Vec2], dx: Double, dy: Double, blur: Double, color: RGBA, ppi: Double) -> PlacedObject? {
        let result = dropShadow(points: points, dx: dx, dy: dy, blur: blur, color: color, ppi: ppi)
        guard result.buffer.width > 1 else { return nil }
        let scale = 72 / max(1, ppi)
        return PlacedObject(
            name: "投影",
            kind: "image",
            frame: Rect2(x: result.origin.x, y: result.origin.y, width: Double(result.buffer.width) * scale, height: Double(result.buffer.height) * scale),
            dataBase64: result.buffer.png().base64EncodedString()
        )
    }
}
