import Foundation

/// 8-bit gray or RGBA PNG, non-interlaced. Enough for trace input and raster effects.
public struct PNGImage: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public var pixelCount: Int { width * height }
}

public enum PNGCodec {
    public static func encode(_ image: PNGImage) -> Data {
        let width = image.width
        let height = image.height
        var raw = Data()
        raw.reserveCapacity((width * 4 + 1) * height)
        for y in 0..<height {
            raw.append(0)
            let row = y * width * 4
            if image.rgba.count >= row + width * 4 {
                raw.append(contentsOf: image.rgba[row..<(row + width * 4)])
            }
        }
        let compressed = Inflate.store(raw)
        var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        png.append(chunk("IHDR", ihdr(width: width, height: height, color: 6)))
        png.append(chunk("IDAT", compressed))
        png.append(chunk("IEND", Data()))
        return png
    }

    public static func decode(_ data: Data) -> PNGImage? {
        let bytes = [UInt8](data)
        guard bytes.count > 8, bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { return nil }
        var i = 8
        var width = 0
        var height = 0
        var bitDepth = 0
        var colorType = 0
        var idat = Data()
        while i + 8 <= bytes.count {
            let length = int32(bytes, i)
            let type = String(bytes: bytes[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
            let start = i + 8
            let end = start + length
            guard length >= 0, end + 4 <= bytes.count else { return nil }
            let chunk = Data(bytes[start..<end])
            if type == "IHDR", chunk.count >= 13 {
                width = int32([UInt8](chunk), 0)
                height = int32([UInt8](chunk), 4)
                bitDepth = Int(chunk[8])
                colorType = Int(chunk[9])
                if chunk[12] != 0 { return nil }
            } else if type == "IDAT" {
                idat.append(chunk)
            } else if type == "IEND" {
                break
            }
            i = end + 4
        }
        guard width > 0, height > 0, bitDepth == 8, colorType == 0 || colorType == 2 || colorType == 6 else { return nil }
        guard let inflated = Inflate.zlib(idat) else { return nil }
        let channels = colorType == 0 ? 1 : (colorType == 2 ? 3 : 4)
        let stride = width * channels
        let expected = (stride + 1) * height
        let raw = [UInt8](inflated)
        guard raw.count >= expected else { return nil }
        var prev = [UInt8](repeating: 0, count: stride)
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        var cursor = 0
        for y in 0..<height {
            let filter = raw[cursor]
            cursor += 1
            var row = Array(raw[cursor..<(cursor + stride)])
            cursor += stride
            for x in 0..<stride {
                let left: UInt8 = x >= channels ? row[x - channels] : 0
                let up = prev[x]
                let ul: UInt8 = x >= channels ? prev[x - channels] : 0
                switch filter {
                case 0: break
                case 1: row[x] = row[x] &+ left
                case 2: row[x] = row[x] &+ up
                case 3: row[x] = row[x] &+ UInt8((Int(left) + Int(up)) / 2)
                case 4: row[x] = row[x] &+ paeth(left, up, ul)
                default: return nil
                }
            }
            for x in 0..<width {
                let o = y * width * 4 + x * 4
                let s = x * channels
                if channels == 1 {
                    rgba[o] = row[s]; rgba[o + 1] = row[s]; rgba[o + 2] = row[s]; rgba[o + 3] = 255
                } else if channels == 3 {
                    rgba[o] = row[s]; rgba[o + 1] = row[s + 1]; rgba[o + 2] = row[s + 2]; rgba[o + 3] = 255
                } else {
                    rgba[o] = row[s]; rgba[o + 1] = row[s + 1]; rgba[o + 2] = row[s + 2]; rgba[o + 3] = row[s + 3]
                }
            }
            prev = row
        }
        return PNGImage(width: width, height: height, rgba: rgba)
    }

    private static func paeth(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8 {
        let p = Int(a) + Int(b) - Int(c)
        let pa = abs(p - Int(a))
        let pb = abs(p - Int(b))
        let pc = abs(p - Int(c))
        if pa <= pb && pa <= pc { return a }
        if pb <= pc { return b }
        return c
    }

    private static func int32(_ bytes: [UInt8], _ i: Int) -> Int {
        guard i + 3 < bytes.count else { return 0 }
        return (Int(bytes[i]) << 24) | (Int(bytes[i + 1]) << 16) | (Int(bytes[i + 2]) << 8) | Int(bytes[i + 3])
    }

    private static func ihdr(width: Int, height: Int, color: UInt8) -> Data {
        var d = Data()
        func be(_ v: Int) {
            d.append(UInt8((v >> 24) & 0xFF))
            d.append(UInt8((v >> 16) & 0xFF))
            d.append(UInt8((v >> 8) & 0xFF))
            d.append(UInt8(v & 0xFF))
        }
        be(width); be(height)
        d.append(8)
        d.append(color)
        d.append(contentsOf: [0, 0, 0])
        return d
    }

    private static func chunk(_ type: String, _ data: Data) -> Data {
        var out = Data()
        let n = data.count
        out.append(UInt8((n >> 24) & 0xFF))
        out.append(UInt8((n >> 16) & 0xFF))
        out.append(UInt8((n >> 8) & 0xFF))
        out.append(UInt8(n & 0xFF))
        out.append(contentsOf: Data(type.utf8))
        out.append(data)
        let crc = crc32(Data(type.utf8) + data)
        out.append(UInt8((crc >> 24) & 0xFF))
        out.append(UInt8((crc >> 16) & 0xFF))
        out.append(UInt8((crc >> 8) & 0xFF))
        out.append(UInt8(crc & 0xFF))
        return out
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { n -> UInt32 in
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data {
            c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }
}
