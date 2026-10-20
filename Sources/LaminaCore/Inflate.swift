import Foundation

/// zlib/deflate (RFC 1950 / 1951) for PDF FlateDecode and PNG.
/// Stored, fixed, and dynamic Huffman blocks are decoded. There is no compressor
/// except `store`, which wraps bytes in a zlib stream of non-compressed blocks.
public enum Inflate {
    public static func zlib(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let cmf = Int(bytes[0])
        let flg = Int(bytes[1])
        guard cmf & 0x0F == 8, (cmf * 256 + flg) % 31 == 0 else { return nil }
        var start = 2
        if flg & 0x20 != 0 {
            guard bytes.count >= 6 else { return nil }
            start = 6
        }
        guard let raw = inflate(Array(bytes[start...]), rawDeflate: true) else { return nil }
        return Data(raw)
    }

    public static func raw(_ data: Data) -> Data? {
        guard let raw = inflate([UInt8](data), rawDeflate: true) else { return nil }
        return Data(raw)
    }

    /// zlib wrapper around stored (uncompressed) deflate blocks. Used by the PNG writer and tests.
    public static func store(_ data: Data) -> Data {
        var out: [UInt8] = [0x78, 0x01]
        let bytes = [UInt8](data)
        var offset = 0
        if bytes.isEmpty {
            out.append(0x01)
            out.append(contentsOf: [0, 0, 0xFF, 0xFF])
        }
        while offset < bytes.count {
            let n = min(65535, bytes.count - offset)
            let final = offset + n >= bytes.count
            out.append(final ? 1 : 0)
            out.append(UInt8(n & 0xFF))
            out.append(UInt8((n >> 8) & 0xFF))
            let nlen = n ^ 0xFFFF
            out.append(UInt8(nlen & 0xFF))
            out.append(UInt8((nlen >> 8) & 0xFF))
            out.append(contentsOf: bytes[offset..<(offset + n)])
            offset += n
        }
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let sum = (b << 16) | a
        out.append(UInt8((sum >> 24) & 0xFF))
        out.append(UInt8((sum >> 16) & 0xFF))
        out.append(UInt8((sum >> 8) & 0xFF))
        out.append(UInt8(sum & 0xFF))
        return Data(out)
    }

    private struct Bits {
        var bytes: [UInt8]
        var pos = 0
        mutating func pull(_ n: Int) -> Int? {
            guard n >= 0, n <= 24 else { return nil }
            var value = 0
            for i in 0..<n {
                let p = pos + i
                let byte = p >> 3
                if byte >= bytes.count { return nil }
                let bit = (Int(bytes[byte]) >> (p & 7)) & 1
                value |= bit << i
            }
            pos += n
            return value
        }
        mutating func align() { pos = (pos + 7) & ~7 }
        func byteIndex() -> Int { pos >> 3 }
    }

    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []
        static func build(_ lengths: [Int]) -> Huffman? {
            var h = Huffman()
            for len in lengths where len > 0 {
                guard len < 16 else { return nil }
                h.counts[len] += 1
            }
            var offsets = [Int](repeating: 0, count: 16)
            var sum = 0
            for len in 1...15 {
                offsets[len] = sum
                sum += h.counts[len]
            }
            h.symbols = [Int](repeating: 0, count: sum)
            var cursor = offsets
            for (symbol, len) in lengths.enumerated() where len > 0 {
                let at = cursor[len]
                guard at < h.symbols.count else { return nil }
                h.symbols[at] = symbol
                cursor[len] = at + 1
            }
            return h
        }
        func decode(_ bits: inout Bits) -> Int? {
            var code = 0
            var first = 0
            var index = 0
            for len in 1...15 {
                guard let bit = bits.pull(1) else { return nil }
                code = (code << 1) | bit
                let count = counts[len]
                if code - first < count {
                    let at = index + (code - first)
                    guard symbols.indices.contains(at) else { return nil }
                    return symbols[at]
                }
                index += count
                first = (first + count) << 1
            }
            return nil
        }
    }

    private static let lengthBase = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258]
    private static let lengthExtra = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0]
    private static let distBase = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577]
    private static let distExtra = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13]
    private static let codeOrder = [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]

    private static func inflate(_ bytes: [UInt8], rawDeflate: Bool) -> [UInt8]? {
        var bits = Bits(bytes: bytes)
        var output: [UInt8] = []
        var fixedLit: Huffman?
        var fixedDist: Huffman?
        while true {
            guard let bfinal = bits.pull(1), let btype = bits.pull(2) else { return nil }
            if btype == 0 {
                bits.align()
                guard let len = bits.pull(16), let nlen = bits.pull(16), len == (nlen ^ 0xFFFF) else { return nil }
                let start = bits.byteIndex()
                guard start + len <= bytes.count else { return nil }
                output.append(contentsOf: bytes[start..<(start + len)])
                bits.pos = (start + len) * 8
            } else if btype == 1 || btype == 2 {
                let lit: Huffman
                let dist: Huffman
                if btype == 1 {
                    if fixedLit == nil {
                        var lens = [Int](repeating: 8, count: 288)
                        for i in 144..<256 { lens[i] = 9 }
                        for i in 256..<280 { lens[i] = 7 }
                        for i in 280..<288 { lens[i] = 8 }
                        fixedLit = Huffman.build(lens)
                        fixedDist = Huffman.build([Int](repeating: 5, count: 32))
                    }
                    guard let a = fixedLit, let b = fixedDist else { return nil }
                    lit = a
                    dist = b
                } else {
                    guard let hl = dynamic(&bits) else { return nil }
                    lit = hl.0
                    dist = hl.1
                }
                while true {
                    guard let symbol = lit.decode(&bits) else { return nil }
                    if symbol < 256 {
                        output.append(UInt8(symbol))
                    } else if symbol == 256 {
                        break
                    } else {
                        let li = symbol - 257
                        guard li >= 0, li < lengthBase.count else { return nil }
                        let extraL = lengthExtra[li] == 0 ? 0 : (bits.pull(lengthExtra[li]) ?? -1)
                        if extraL < 0 { return nil }
                        let length = lengthBase[li] + extraL
                        guard let ds = dist.decode(&bits) else { return nil }
                        guard ds < distBase.count else { return nil }
                        let extraD = distExtra[ds] == 0 ? 0 : (bits.pull(distExtra[ds]) ?? -1)
                        if extraD < 0 { return nil }
                        let distance = distBase[ds] + extraD
                        guard distance > 0, distance <= output.count else { return nil }
                        for _ in 0..<length {
                            output.append(output[output.count - distance])
                        }
                    }
                }
            } else {
                return nil
            }
            if bfinal == 1 { break }
        }
        _ = rawDeflate
        return output
    }

    private static func dynamic(_ bits: inout Bits) -> (Huffman, Huffman)? {
        guard let hlit = bits.pull(5), let hdist = bits.pull(5), let hclen = bits.pull(4) else { return nil }
        var codeLens = [Int](repeating: 0, count: 19)
        for i in 0..<(hclen + 4) {
            guard let len = bits.pull(3) else { return nil }
            codeLens[codeOrder[i]] = len
        }
        guard let codeTree = Huffman.build(codeLens) else { return nil }
        let total = hlit + 257 + hdist + 1
        var lengths: [Int] = []
        lengths.reserveCapacity(total)
        while lengths.count < total {
            guard let symbol = codeTree.decode(&bits) else { return nil }
            if symbol < 16 {
                lengths.append(symbol)
            } else if symbol == 16 {
                guard let extra = bits.pull(2), let last = lengths.last else { return nil }
                for _ in 0..<(3 + extra) { lengths.append(last) }
            } else if symbol == 17 {
                guard let extra = bits.pull(3) else { return nil }
                for _ in 0..<(3 + extra) { lengths.append(0) }
            } else if symbol == 18 {
                guard let extra = bits.pull(7) else { return nil }
                for _ in 0..<(11 + extra) { lengths.append(0) }
            } else {
                return nil
            }
        }
        if lengths.count > total { return nil }
        let nlit = hlit + 257
        guard let lit = Huffman.build(Array(lengths[0..<nlit])),
              let dist = Huffman.build(Array(lengths[nlit...])) else { return nil }
        return (lit, dist)
    }
}
