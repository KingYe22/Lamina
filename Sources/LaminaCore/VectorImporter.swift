import Foundation

public enum EditableFile {
    public static func open(data: Data, title: String) throws -> LaminaDocument {
        if let native = try? AIFile.document(from: data) { return native }
        if let imported = VectorImporter.importDocument(data, title: title), imported.objectCount > 0 {
            return imported
        }
        throw AIFileError.missingDocument
    }
}

/// Editable geometry from a PDF content stream or a legacy PostScript `.ai` file.
/// Offsets follow the PDF Reference (user space, then y-down). Illustrator private data is not required.
public enum VectorImporter {
    public static func importDocument(_ data: Data, title: String) -> LaminaDocument? {
        if let pdf = PDFImporter.read(data, title: title), pdf.objectCount > 0 { return pdf }
        if let ai = LegacyAIImporter.read(data, title: title), ai.objectCount > 0 { return ai }
        return nil
    }
}

private enum PDFObj {
    case null
    case bool(Bool)
    case number(Double)
    case name(String)
    case string(String)
    case array([PDFObj])
    case dict([String: PDFObj])
    case ref(Int)
    case stream([String: PDFObj], Data)
}

private final class PDFFile {
    let bytes: [UInt8]
    var xref: [Int: Int] = [:]
    var compressed: [Int: (stream: Int, index: Int)] = [:]
    var cache: [Int: PDFObj] = [:]
    var root = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    func load() -> Bool {
        guard let start = lastStartXRef() else { return false }
        var cursor: Int? = start
        var seen = Set<Int>()
        while let at = cursor, seen.insert(at).inserted {
            if at + 4 < bytes.count, String(decoding: bytes[at..<min(at + 4, bytes.count)], as: UTF8.self) == "xref" {
                cursor = parseClassic(at)
            } else if let prev = parseXRefStream(at) {
                cursor = prev
            } else {
                break
            }
        }
        return root != 0
    }

    func resolve(_ obj: PDFObj) -> PDFObj {
        if case .ref(let id) = obj { return object(id) ?? .null }
        return obj
    }

    func object(_ id: Int) -> PDFObj? {
        if let cached = cache[id] { return cached }
        if let hit = compressed[id] {
            guard case .stream(let dict, let data)? = object(hit.stream) else { return nil }
            guard let built = objectsInStream(dict: dict, data: data), built.indices.contains(hit.index) else { return nil }
            let value = built[hit.index].1
            cache[id] = value
            return value
        }
        guard let offset = xref[id], offset >= 0, offset < bytes.count else { return nil }
        var parser = PDFCursor(bytes: bytes, index: offset)
        _ = parser.number()
        _ = parser.number()
        _ = parser.keyword()
        guard let value = parser.value() else { return nil }
        if parser.consume("stream") {
            guard case .dict(let dict) = value else { return nil }
            if parser.index < bytes.count, bytes[parser.index] == 13 { parser.index += 1 }
            if parser.index < bytes.count, bytes[parser.index] == 10 { parser.index += 1 }
            let length = streamLength(dict)
            let end = min(bytes.count, parser.index + length)
            let raw = Data(bytes[parser.index..<end])
            let decoded = PDFFilters.decode(raw, dict: dict, file: self)
            let stream = PDFObj.stream(dict, decoded)
            cache[id] = stream
            return stream
        }
        cache[id] = value
        return value
    }

    private func streamLength(_ dict: [String: PDFObj]) -> Int {
        guard let length = dict["Length"] else { return 0 }
        switch resolve(length) {
        case .number(let n): return max(0, Int(n))
        default: return 0
        }
    }

    private func objectsInStream(dict: [String: PDFObj], data: Data) -> [(Int, PDFObj)]? {
        guard case .number(let nRaw) = resolve(dict["N"] ?? .null),
              case .number(let firstRaw) = resolve(dict["First"] ?? .null) else { return nil }
        let n = Int(nRaw)
        let first = Int(firstRaw)
        let text = [UInt8](data)
        var cursor = PDFCursor(bytes: text, index: 0)
        var pairs: [(Int, Int)] = []
        for _ in 0..<n {
            guard let id = cursor.number(), let rel = cursor.number() else { return nil }
            pairs.append((Int(id), Int(rel)))
        }
        var values: [(Int, PDFObj)] = []
        for (id, rel) in pairs {
            var body = PDFCursor(bytes: text, index: first + rel)
            guard let value = body.value() else { continue }
            values.append((id, value))
            cache[id] = value
        }
        return values
    }

    private func lastStartXRef() -> Int? {
        let token = Array("startxref".utf8)
        guard bytes.count > token.count else { return nil }
        var i = bytes.count - token.count
        while i >= 0 {
            if Array(bytes[i..<(i + token.count)]) == token {
                var cursor = PDFCursor(bytes: bytes, index: i + token.count)
                if let n = cursor.number() { return Int(n) }
            }
            i -= 1
            if bytes.count - i > 4096 { break }
        }
        return nil
    }

    private func parseClassic(_ at: Int) -> Int? {
        var cursor = PDFCursor(bytes: bytes, index: at)
        _ = cursor.keyword()
        while true {
            cursor.skip()
            guard cursor.index < bytes.count, bytes[cursor.index].isASCIIDigit else { break }
            guard let start = cursor.number(), let count = cursor.number() else { break }
            for offsetIndex in 0..<Int(count) {
                guard let pos = cursor.number(), let _ = cursor.number(), let flag = cursor.keyword() else { break }
                let id = Int(start) + offsetIndex
                if flag == "n", xref[id] == nil { xref[id] = Int(pos) }
            }
        }
        guard cursor.consume("trailer"), let trailer = cursor.dict() else { return nil }
        applyTrailer(trailer)
        if case .number(let prev) = resolve(trailer["Prev"] ?? .null) { return Int(prev) }
        return nil
    }

    private func parseXRefStream(_ at: Int) -> Int? {
        guard let obj = readStreamObject(at: at), case .stream(let dict, let data) = obj else { return nil }
        if case .ref(let id) = dict["Root"] ?? .null { root = id }
        else if case .dict = resolve(dict["Root"] ?? .null) {
            // root stored as inline dict is unusual; ignore
        }
        if case .number(let size) = resolve(dict["Size"] ?? .null) {
            _ = size
        }
        var widths = [1, 2, 1]
        if case .array(let arr) = resolve(dict["W"] ?? .null) {
            widths = arr.compactMap { if case .number(let n) = $0 { return Int(n) } else { return nil } }
        }
        guard widths.count == 3 else { return nil }
        var indexPairs: [(Int, Int)] = [(0, Int(number(dict["Size"])))]
        if case .array(let arr) = resolve(dict["Index"] ?? .null) {
            var pairs: [(Int, Int)] = []
            var i = 0
            let nums = arr.compactMap { if case .number(let n) = $0 { return Int(n) } else { return nil } }
            while i + 1 < nums.count {
                pairs.append((nums[i], nums[i + 1]))
                i += 2
            }
            if !pairs.isEmpty { indexPairs = pairs }
        }
        let raw = [UInt8](data)
        var cursor = 0
        func field(_ w: Int) -> Int {
            var v = 0
            for _ in 0..<w {
                if cursor < raw.count { v = (v << 8) | Int(raw[cursor]); cursor += 1 }
            }
            return w == 0 ? 0 : v
        }
        for (start, count) in indexPairs {
            for n in 0..<count {
                let kind = widths[0] == 0 ? 1 : field(widths[0])
                let b = field(widths[1])
                let c = field(widths[2])
                let id = start + n
                if kind == 1, xref[id] == nil { xref[id] = b }
                if kind == 2, compressed[id] == nil { compressed[id] = (b, c) }
            }
        }
        if case .number(let prev) = resolve(dict["Prev"] ?? .null) { return Int(prev) }
        return nil
    }

    private func readStreamObject(at: Int) -> PDFObj? {
        var parser = PDFCursor(bytes: bytes, index: at)
        let id = Int(parser.number() ?? -1)
        _ = parser.number()
        _ = parser.keyword()
        guard let value = parser.value(), case .dict(let dict) = value, parser.consume("stream") else { return nil }
        if parser.index < bytes.count, bytes[parser.index] == 13 { parser.index += 1 }
        if parser.index < bytes.count, bytes[parser.index] == 10 { parser.index += 1 }
        let length = streamLength(dict)
        let end = min(bytes.count, parser.index + length)
        let decoded = PDFFilters.decode(Data(bytes[parser.index..<end]), dict: dict, file: self)
        let stream = PDFObj.stream(dict, decoded)
        if id >= 0 { cache[id] = stream }
        if case .ref(let rootID) = dict["Root"] ?? .null { root = rootID }
        return stream
    }

    private func applyTrailer(_ trailer: [String: PDFObj]) {
        if case .ref(let id) = trailer["Root"] ?? .null, root == 0 { root = id }
    }

    private func number(_ obj: PDFObj?) -> Double {
        guard let obj else { return 0 }
        if case .number(let n) = resolve(obj) { return n }
        return 0
    }
}

private struct PDFCursor {
    var bytes: [UInt8]
    var index: Int

    mutating func skip() {
        while index < bytes.count {
            let b = bytes[index]
            if b == 37 {
                while index < bytes.count, bytes[index] != 10, bytes[index] != 13 { index += 1 }
                continue
            }
            if b == 0 || b == 9 || b == 10 || b == 12 || b == 13 || b == 32 { index += 1; continue }
            break
        }
    }

    mutating func keyword() -> String? {
        skip()
        let start = index
        while index < bytes.count {
            let b = bytes[index]
            if b <= 32 || b == 47 || b == 60 || b == 62 || b == 91 || b == 93 || b == 40 || b == 41 || b == 123 { break }
            if b == 37 { break }
            index += 1
        }
        if index == start { return nil }
        return String(bytes: bytes[start..<index], encoding: .isoLatin1)
    }

    mutating func number() -> Double? {
        skip()
        let start = index
        if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
        var saw = false
        while index < bytes.count, bytes[index].isASCIIDigit { saw = true; index += 1 }
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            while index < bytes.count, bytes[index].isASCIIDigit { saw = true; index += 1 }
        }
        guard saw, let value = Double(String(bytes: bytes[start..<index], encoding: .isoLatin1) ?? "") else {
            index = start
            return nil
        }
        return value
    }

    mutating func consume(_ word: String) -> Bool {
        let save = index
        if keyword() == word { return true }
        index = save
        return false
    }

    mutating func value() -> PDFObj? {
        skip()
        guard index < bytes.count else { return nil }
        let b = bytes[index]
        if b == 40 { return .string(literalString()) }
        if b == 60 {
            if index + 1 < bytes.count, bytes[index + 1] == 60 { return .dict(dict() ?? [:]) }
            return .string(hexString())
        }
        if b == 91 { return .array(array() ?? []) }
        if b == 47 { return .name(name()) }
        if let word = keyword() {
            if word == "true" { return .bool(true) }
            if word == "false" { return .bool(false) }
            if word == "null" { return .null }
            if let n = Double(word) {
                let save = index
                if let gen = number() {
                    let after = index
                    if keyword() == "R" { return .ref(Int(n)) }
                    index = after
                    _ = gen
                }
                index = save
                return .number(n)
            }
            return nil
        }
        return nil
    }

    mutating func dict() -> [String: PDFObj]? {
        skip()
        guard index + 1 < bytes.count, bytes[index] == 60, bytes[index + 1] == 60 else { return nil }
        index += 2
        var map: [String: PDFObj] = [:]
        while index < bytes.count {
            skip()
            if index + 1 < bytes.count, bytes[index] == 62, bytes[index + 1] == 62 {
                index += 2
                break
            }
            guard bytes[index] == 47 else { break }
            let key = name()
            guard let val = value() else { break }
            map[key] = val
        }
        return map
    }

    mutating func array() -> [PDFObj]? {
        skip()
        guard index < bytes.count, bytes[index] == 91 else { return nil }
        index += 1
        var items: [PDFObj] = []
        while index < bytes.count {
            skip()
            if index < bytes.count, bytes[index] == 93 { index += 1; break }
            guard let item = value() else { break }
            items.append(item)
        }
        return items
    }

    mutating func name() -> String {
        skip()
        guard index < bytes.count, bytes[index] == 47 else { return "" }
        index += 1
        var out = ""
        while index < bytes.count {
            let b = bytes[index]
            if b <= 32 || b == 47 || b == 60 || b == 62 || b == 91 || b == 93 || b == 40 || b == 41 || b == 37 { break }
            if b == 35, index + 2 < bytes.count, let v = Int(String(bytes: bytes[(index + 1)..<(index + 3)], encoding: .ascii) ?? "", radix: 16) {
                out.append(Character(UnicodeScalar(v) ?? " "))
                index += 3
                continue
            }
            out.append(Character(UnicodeScalar(b)))
            index += 1
        }
        return out
    }

    mutating func literalString() -> String {
        guard index < bytes.count, bytes[index] == 40 else { return "" }
        index += 1
        var depth = 1
        var out: [UInt8] = []
        while index < bytes.count, depth > 0 {
            let b = bytes[index]
            index += 1
            if b == 92 {
                guard index < bytes.count else { break }
                let e = bytes[index]
                index += 1
                switch e {
                case 110: out.append(10)
                case 114: out.append(13)
                case 116: out.append(9)
                case 98: out.append(8)
                case 102: out.append(12)
                case 40, 41, 92: out.append(e)
                case 13, 10:
                    if e == 13, index < bytes.count, bytes[index] == 10 { index += 1 }
                default:
                    if e.isASCIIDigit {
                        var oct = Int(e - 48)
                        for _ in 0..<2 {
                            if index < bytes.count, bytes[index].isASCIIDigit {
                                oct = oct * 8 + Int(bytes[index] - 48)
                                index += 1
                            }
                        }
                        out.append(UInt8(oct & 0xFF))
                    }
                }
                continue
            }
            if b == 40 { depth += 1; out.append(b); continue }
            if b == 41 { depth -= 1; if depth > 0 { out.append(b) }; continue }
            out.append(b)
        }
        return String(bytes: out, encoding: .utf8) ?? String(bytes: out, encoding: .isoLatin1) ?? ""
    }

    mutating func hexString() -> String {
        guard index < bytes.count, bytes[index] == 60 else { return "" }
        index += 1
        var hex = ""
        while index < bytes.count, bytes[index] != 62 {
            let b = bytes[index]
            index += 1
            if b > 32 { hex.append(Character(UnicodeScalar(b))) }
        }
        if index < bytes.count, bytes[index] == 62 { index += 1 }
        if hex.count % 2 == 1 { hex.append("0") }
        var bytesOut: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            if let v = UInt8(hex[i..<j], radix: 16) { bytesOut.append(v) }
            i = j
        }
        return String(bytes: bytesOut, encoding: .utf8) ?? String(bytes: bytesOut, encoding: .isoLatin1) ?? ""
    }
}

private enum PDFFilters {
    static func decode(_ data: Data, dict: [String: PDFObj], file: PDFFile) -> Data {
        var current = data
        var filters: [String] = []
        if case .name(let one) = file.resolve(dict["Filter"] ?? .null) { filters = [one] }
        if case .array(let many) = file.resolve(dict["Filter"] ?? .null) {
            filters = many.compactMap { item in
                if case .name(let filterName) = item { return filterName }
                return nil
            }
        }
        var parms: [PDFObj] = []
        if let raw = dict["DecodeParms"] ?? dict["DP"] {
            switch file.resolve(raw) {
            case .array(let items): parms = items
            case .dict: parms = [raw]
            default: break
            }
        }
        for (index, filter) in filters.enumerated() {
            switch filter {
            case "FlateDecode", "Fl":
                current = Inflate.zlib(current) ?? current
                if parms.indices.contains(index), case .dict(let p) = file.resolve(parms[index]) {
                    current = unpredict(current, parms: p, file: file)
                }
            case "ASCIIHexDecode", "AHx":
                current = asciiHex(current)
            case "ASCII85Decode", "A85":
                current = ascii85(current)
            default:
                break
            }
        }
        return current
    }

    private static func unpredict(_ data: Data, parms: [String: PDFObj], file: PDFFile) -> Data {
        guard case .number(let predictor) = file.resolve(parms["Predictor"] ?? .null) else { return data }
        let pred = Int(predictor)
        guard pred >= 10 else { return data }
        let columns = Int(fileNumber(parms["Columns"], file: file, fallback: 1))
        let colors = max(1, Int(fileNumber(parms["Colors"], file: file, fallback: 1)))
        let bpc = max(1, Int(fileNumber(parms["BitsPerComponent"], file: file, fallback: 8)))
        let row = max(1, ((columns * colors * bpc) + 7) / 8)
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        var prev = [UInt8](repeating: 0, count: row)
        var i = 0
        while i + row < bytes.count || (i < bytes.count && bytes.count - i >= row + 1) {
            if i >= bytes.count { break }
            let filter = bytes[i]
            i += 1
            guard i + row <= bytes.count else { break }
            var rowBytes = Array(bytes[i..<(i + row)])
            i += row
            let bpp = max(1, (colors * bpc + 7) / 8)
            for x in 0..<row {
                let left: UInt8 = x >= bpp ? rowBytes[x - bpp] : 0
                let up = prev[x]
                let ul: UInt8 = x >= bpp ? prev[x - bpp] : 0
                switch filter {
                case 0: break
                case 1: rowBytes[x] = rowBytes[x] &+ left
                case 2: rowBytes[x] = rowBytes[x] &+ up
                case 3: rowBytes[x] = rowBytes[x] &+ UInt8((Int(left) + Int(up)) / 2)
                case 4:
                    let p = Int(left) + Int(up) - Int(ul)
                    let pa = abs(p - Int(left)), pb = abs(p - Int(up)), pc = abs(p - Int(ul))
                    let pick: UInt8 = pa <= pb && pa <= pc ? left : (pb <= pc ? up : ul)
                    rowBytes[x] = rowBytes[x] &+ pick
                default: break
                }
            }
            output.append(contentsOf: rowBytes)
            prev = rowBytes
        }
        return Data(output)
    }

    private static func fileNumber(_ obj: PDFObj?, file: PDFFile, fallback: Double) -> Double {
        guard let obj else { return fallback }
        if case .number(let n) = file.resolve(obj) { return n }
        return fallback
    }

    private static func asciiHex(_ data: Data) -> Data {
        var hex = ""
        for byte in data {
            if byte == 62 { break }
            if byte > 32 { hex.append(Character(UnicodeScalar(byte))) }
        }
        if hex.count % 2 == 1 { hex.append("0") }
        var out = Data()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let v = UInt8(hex[i..<j], radix: 16) { out.append(v) }
            i = j
        }
        return out
    }

    private static func ascii85(_ data: Data) -> Data {
        var out = Data()
        var group: [UInt8] = []
        for byte in data {
            if byte == 126 { break }
            if byte <= 32 { continue }
            if byte == 122 {
                out.append(contentsOf: [0, 0, 0, 0])
                continue
            }
            group.append(byte)
            if group.count == 5 {
                out.append(contentsOf: decode85(group))
                group = []
            }
        }
        if !group.isEmpty {
            let pad = 5 - group.count
            var padded = group
            for _ in 0..<pad { padded.append(117) }
            let full = decode85(padded)
            out.append(contentsOf: full.prefix(max(0, 4 - pad)))
        }
        return out
    }

    private static func decode85(_ group: [UInt8]) -> [UInt8] {
        var value: UInt32 = 0
        for byte in group { value = value * 85 + UInt32(byte - 33) }
        return [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}

private enum PDFImporter {
    static func read(_ data: Data, title: String) -> LaminaDocument? {
        guard hasPDF(data) else { return nil }
        let file = PDFFile(data)
        guard file.load() else { return nil }
        guard case .dict(let catalog) = file.object(file.root) ?? .null else { return nil }
        guard case .ref(let pagesID) = catalog["Pages"] ?? .null else { return nil }
        var pages: [(box: Rect2, items: [ArtItem], layers: [(String, [ArtItem])])] = []
        collectPages(id: pagesID, file: file, inherited: [:], into: &pages)
        guard !pages.isEmpty else { return nil }
        var document = LaminaDocument.blank(title: title, size: Vec2(pages[0].box.width, pages[0].box.height))
        document.artboards = []
        document.layers = []
        var x: Double = 0
        var flat: [ArtItem] = []
        var named: [(String, [ArtItem])] = []
        for (index, page) in pages.enumerated() {
            let board = Rect2(x: x, y: 0, width: page.box.width, height: max(page.box.height, 1))
            document.artboards.append(Artboard(name: "页面 \(index + 1)", rect: board))
            let shift = Affine.translation(x, 0)
            func moved(_ item: ArtItem) -> ArtItem {
                var copy = item
                copy.setTransform(shift.concatenated(item.transform))
                return copy
            }
            if page.layers.isEmpty {
                flat.append(contentsOf: page.items.map(moved))
            } else {
                for (name, items) in page.layers {
                    named.append((name, items.map(moved)))
                }
                flat.append(contentsOf: page.items.map(moved))
            }
            x += board.width + 40
        }
        var grouped: [String: [ArtItem]] = [:]
        var order: [String] = []
        for (name, items) in named where !items.isEmpty {
            if grouped[name] == nil { order.append(name) }
            grouped[name, default: []].append(contentsOf: items)
        }
        document.layers = []
        if !flat.isEmpty { document.layers.append(Layer(name: "图层 1", items: flat)) }
        document.layers.append(contentsOf: order.map { Layer(name: $0, items: grouped[$0] ?? []) })
        if document.layers.isEmpty {
            document.layers = [Layer(name: "图层 1", items: flat)]
        }
        if document.artboards.isEmpty {
            document.artboards = [Artboard(name: "画板 1", rect: Rect2(x: 0, y: 0, width: 612, height: 792))]
        }
        return document
    }

    private static func hasPDF(_ data: Data) -> Bool {
        let sample = data.prefix(1024)
        return sample.range(of: Data("%PDF".utf8)) != nil
    }

    private static func collectPages(id: Int, file: PDFFile, inherited: [String: PDFObj], into pages: inout [(box: Rect2, items: [ArtItem], layers: [(String, [ArtItem])])]) {
        guard case .dict(var dict) = file.object(id) ?? .null else { return }
        for (key, value) in inherited where dict[key] == nil { dict[key] = value }
        let type: String
        if case .name(let name) = file.resolve(dict["Type"] ?? .null) { type = name } else { type = "" }
        if type == "Pages" || dict["Kids"] != nil && dict["Contents"] == nil {
            guard case .array(let kids) = file.resolve(dict["Kids"] ?? .null) else { return }
            var next = inherited
            if let box = dict["MediaBox"] { next["MediaBox"] = box }
            if let res = dict["Resources"] { next["Resources"] = res }
            for kid in kids {
                if case .ref(let child) = kid { collectPages(id: child, file: file, inherited: next, into: &pages) }
            }
            return
        }
        let box = rect(file.resolve(dict["MediaBox"] ?? .null)) ?? Rect2(x: 0, y: 0, width: 612, height: 792)
        let resources = resources(dict["Resources"], file: file)
        var streams: [Data] = []
        switch file.resolve(dict["Contents"] ?? .null) {
        case .stream(_, let data):
            streams = [data]
        case .array(let items):
            for item in items {
                if case .stream(_, let data) = file.resolve(item) { streams.append(data) }
            }
        case .ref(let id):
            if case .stream(_, let data) = file.object(id) ?? .null { streams = [data] }
        default:
            break
        }
        let content = streams.reduce(Data(), +)
        let built = ContentInterpreter(file: file, resources: resources, pageHeight: box.height).run(content)
        pages.append((box, built.items, built.layers))
    }

    private static func rect(_ obj: PDFObj) -> Rect2? {
        guard case .array(let items) = obj, items.count >= 4 else { return nil }
        func num(_ o: PDFObj) -> Double { if case .number(let n) = o { return n } else { return 0 } }
        let x0 = num(items[0]), y0 = num(items[1]), x1 = num(items[2]), y1 = num(items[3])
        return Rect2(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
    }

    fileprivate static func resources(_ obj: PDFObj?, file: PDFFile) -> PDFResources {
        guard let obj, case .dict(let dict) = file.resolve(obj) else { return PDFResources() }
        var res = PDFResources()
        if case .dict(let fonts) = file.resolve(dict["Font"] ?? .null) {
            for (key, value) in fonts {
                if case .dict(let font) = file.resolve(value), case .name(let base) = file.resolve(font["BaseFont"] ?? .null) {
                    res.fonts[key] = base
                }
            }
        }
        if case .dict(let xobj) = file.resolve(dict["XObject"] ?? .null) {
            for (key, value) in xobj {
                if case .ref(let id) = value { res.xobjects[key] = id }
            }
        }
        if case .dict(let shades) = file.resolve(dict["Shading"] ?? .null) {
            for (key, value) in shades {
                if case .ref(let id) = value { res.shadings[key] = id }
                if case .dict = file.resolve(value) { res.inlineShading[key] = file.resolve(value) }
            }
        }
        if case .dict(let props) = file.resolve(dict["Properties"] ?? .null) {
            for (key, value) in props {
                if case .dict(let ocg) = file.resolve(value) {
                    if case .string(let name) = file.resolve(ocg["Name"] ?? .null) { res.ocg[key] = name }
                }
            }
        }
        if case .dict(let gs) = file.resolve(dict["ExtGState"] ?? .null) {
            for (key, value) in gs {
                if case .dict(let state) = file.resolve(value) {
                    var fill: Double?
                    var stroke: Double?
                    if case .number(let n) = file.resolve(state["ca"] ?? .null) { fill = n }
                    if case .number(let n) = file.resolve(state["CA"] ?? .null) { stroke = n }
                    res.ext[key] = (fill, stroke)
                }
            }
        }
        return res
    }
}

private struct PDFResources {
    var fonts: [String: String] = [:]
    var xobjects: [String: Int] = [:]
    var shadings: [String: Int] = [:]
    var inlineShading: [String: PDFObj] = [:]
    var ocg: [String: String] = [:]
    var ext: [String: (Double?, Double?)] = [:]
}

fileprivate struct ContentInterpreter {
    var file: PDFFile
    var resources: PDFResources
    var pageHeight: Double
    var items: [ArtItem] = []
    var layers: [(String, [ArtItem])] = []
    var lastName = ""

    init(file: PDFFile, resources: PDFResources, pageHeight: Double) {
        self.file = file
        self.resources = resources
        self.pageHeight = pageHeight
    }

    struct State {
        var ctm = Affine.identity
        var fill = RGBA.black
        var stroke = RGBA.black
        var fillCMYK = false
        var strokeCMYK = false
        var width = 1.0
        var cap = LineCap.butt
        var join = LineJoin.miter
        var miter = 10.0
        var dash: [Double] = []
        var fillSpace = "DeviceGray"
        var strokeSpace = "DeviceGray"
        var clip: PathItem?
        var font = "Helvetica"
        var fontSize = 12.0
        var leading = 0.0
        var charSpacing = 0.0
    }

    struct Subpath {
        var nodes: [PathNode] = []
        var start = Vec2.zero
    }

    func run(_ data: Data) -> (items: [ArtItem], layers: [(String, [ArtItem])]) {
        var machine = self
        machine.execute(data, resources: resources, state: State())
        return (machine.items, machine.layers)
    }

    private mutating func execute(_ data: Data, resources: PDFResources, state: State) {
        self.resources = resources
        var g = state
        var stack: [State] = []
        var path = Subpath()
        var subpaths: [PathItem] = []
        var args: [Double] = []
        var text = false
        var tm = Affine.identity
        var lineMatrix = Affine.identity
        var ocgStack: [String] = []
        var ocgItems: [[ArtItem]] = []
        var pendingText = ""
        let tokens = PDFContent.tokenize(data)
        func emitText() {
            let string = pendingText
            pendingText = ""
            guard !string.isEmpty else { return }
            let origin = g.ctm.apply(tm.apply(Vec2.zero))
            let doc = Vec2(origin.x, pageHeight - origin.y)
            let size = max(1, g.fontSize * max(0.01, hypot(tm.a, tm.b)))
            var object = TextObject(string: string, origin: doc, fontName: g.font, fontSize: size, appearance: Appearance(fill: .solid(g.fill), stroke: nil))
            object.appearance.overprintFill = g.fillCMYK
            emit(.text(object))
        }

        func flushSub() {
            guard path.nodes.count >= 1 else { path = Subpath(); return }
            subpaths.append(PathItem(nodes: path.nodes, closed: false, shape: .free))
            path = Subpath()
        }
        func mapPoint(_ p: Vec2) -> Vec2 {
            let q = g.ctm.apply(p)
            return Vec2(q.x, pageHeight - q.y)
        }
        func mapPath(_ item: PathItem, closed: Bool) -> PathItem {
            var nodes = item.nodes.map { node -> PathNode in
                var copy = node
                copy.anchor = mapPoint(node.anchor)
                if let h = node.inHandle { copy.inHandle = mapPoint(h) }
                if let h = node.outHandle { copy.outHandle = mapPoint(h) }
                return copy
            }
            if closed, nodes.count >= 2, let first = nodes.first?.anchor, let last = nodes.last?.anchor, first.almostEqual(last, eps: 0.05) {
                let closing = nodes.removeLast()
                if let incoming = closing.inHandle { nodes[0].inHandle = incoming }
            }
            return PathItem(nodes: nodes, closed: closed || item.closed, shape: .free)
        }
        func emit(_ item: ArtItem) {
            var art = item
            if let clip = g.clip {
                art = .clip(ClipObject(clipper: .path(PathObject(name: "剪贴", path: clip, appearance: .none)), contents: [item]))
            }
            if ocgItems.isEmpty { items.append(art) }
            else { ocgItems[ocgItems.count - 1].append(art) }
        }
        func paint(fill: Bool, stroke: Bool, evenOdd: Bool, close: Bool) {
            if close, !path.nodes.isEmpty {
                path.nodes[path.nodes.count - 1].anchor = path.start
            }
            flushSub()
            let paths = subpaths
            subpaths = []
            guard !paths.isEmpty else { return }
            var appearance = Appearance.none
            if fill {
                appearance.fill = .solid(g.fill)
                appearance.overprintFill = g.fillCMYK
            }
            if stroke {
                appearance.stroke = StrokeStyle(paint: .solid(g.stroke), width: g.width, cap: g.cap, join: g.join, miterLimit: g.miter, dash: g.dash)
                appearance.overprintStroke = g.strokeCMYK
            }
            let mapped = paths.enumerated().map { index, item -> PathItem in
                let closed = item.closed || (close && index == paths.count - 1) || fill
                return mapPath(item, closed: closed && item.nodes.count >= 2)
            }.filter { !$0.nodes.isEmpty }
            if mapped.count > 1 {
                emit(.compound(CompoundObject(name: "复合路径", paths: mapped, appearance: appearance, fillRule: evenOdd ? .evenOdd : .nonzero)))
            } else if let only = mapped.first {
                emit(.path(PathObject(name: fill ? "路径" : "描边", path: only, appearance: appearance)))
            }
        }

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            switch token {
            case .number(let n):
                args.append(n)
            case .name(let name):
                args.removeAll()
                if text == false {
                    // resource name kept in lastName via a side channel
                }
                lastName = name
            case .string(let s):
                if text { pendingText += s }
            case .array(let inner):
                if text {
                    for piece in inner {
                        if case .string(let s) = piece { pendingText += s }
                    }
                }
            case .op(let op):
                switch op {
                case "q":
                    stack.append(g)
                case "Q":
                    if let previous = stack.popLast() { g = previous }
                case "cm":
                    if args.count >= 6 {
                        let m = Affine(a: args[0], b: args[1], c: args[2], d: args[3], tx: args[4], ty: args[5])
                        g.ctm = m.concatenated(g.ctm)
                    }
                case "w": if let w = args.last { g.width = w }
                case "J": if let v = args.last { g.cap = v < 0.5 ? .butt : (v < 1.5 ? .round : .square) }
                case "j": if let v = args.last { g.join = v < 0.5 ? .miter : (v < 1.5 ? .round : .bevel) }
                case "M": if let v = args.last { g.miter = v }
                case "d": g.dash = args
                case "g":
                    if let gray = args.last {
                        g.fill = RGBA(r: gray, g: gray, b: gray)
                        g.fillCMYK = false
                        g.fillSpace = "DeviceGray"
                    }
                case "G":
                    if let gray = args.last {
                        g.stroke = RGBA(r: gray, g: gray, b: gray)
                        g.strokeCMYK = false
                    }
                case "rg":
                    if args.count >= 3 {
                        g.fill = RGBA(r: args[args.count - 3], g: args[args.count - 2], b: args[args.count - 1])
                        g.fillCMYK = false
                        g.fillSpace = "DeviceRGB"
                    }
                case "RG":
                    if args.count >= 3 {
                        g.stroke = RGBA(r: args[args.count - 3], g: args[args.count - 2], b: args[args.count - 1])
                        g.strokeCMYK = false
                    }
                case "k":
                    if args.count >= 4 {
                        let cmyk = DeviceCMYK(c: args[args.count - 4], m: args[args.count - 3], y: args[args.count - 2], k: args[args.count - 1])
                        g.fill = RGBA(cmyk: cmyk)
                        g.fillCMYK = true
                        g.fillSpace = "DeviceCMYK"
                    }
                case "K":
                    if args.count >= 4 {
                        let cmyk = DeviceCMYK(c: args[args.count - 4], m: args[args.count - 3], y: args[args.count - 2], k: args[args.count - 1])
                        g.stroke = RGBA(cmyk: cmyk)
                        g.strokeCMYK = true
                    }
                case "cs": g.fillSpace = lastName
                case "CS": g.strokeSpace = lastName
                case "sc", "scn":
                    g.fill = color(args, space: g.fillSpace)
                    g.fillCMYK = g.fillSpace == "DeviceCMYK"
                case "SC", "SCN":
                    g.stroke = color(args, space: g.strokeSpace)
                    g.strokeCMYK = g.strokeSpace == "DeviceCMYK"
                case "gs":
                    if let ext = resources.ext[lastName] {
                        if let a = ext.0 { g.fill.a = a }
                        if let a = ext.1 { g.stroke.a = a }
                    }
                case "m":
                    flushSub()
                    if args.count >= 2 {
                        let p = Vec2(args[args.count - 2], args[args.count - 1])
                        path.start = p
                        path.nodes = [PathNode.corner(p)]
                    }
                case "l":
                    if args.count >= 2 { path.nodes.append(.corner(Vec2(args[args.count - 2], args[args.count - 1]))) }
                case "c":
                    if args.count >= 6, !path.nodes.isEmpty {
                        let c1 = Vec2(args[args.count - 6], args[args.count - 5])
                        let c2 = Vec2(args[args.count - 4], args[args.count - 3])
                        let p = Vec2(args[args.count - 2], args[args.count - 1])
                        path.nodes[path.nodes.count - 1].outHandle = c1
                        var node = PathNode.corner(p)
                        node.inHandle = c2
                        node.corner = .smooth
                        path.nodes.append(node)
                    }
                case "v":
                    if args.count >= 4, !path.nodes.isEmpty {
                        let c2 = Vec2(args[args.count - 4], args[args.count - 3])
                        let p = Vec2(args[args.count - 2], args[args.count - 1])
                        path.nodes[path.nodes.count - 1].outHandle = path.nodes[path.nodes.count - 1].anchor
                        var node = PathNode.corner(p)
                        node.inHandle = c2
                        path.nodes.append(node)
                    }
                case "y":
                    if args.count >= 4, !path.nodes.isEmpty {
                        let c1 = Vec2(args[args.count - 4], args[args.count - 3])
                        let p = Vec2(args[args.count - 2], args[args.count - 1])
                        path.nodes[path.nodes.count - 1].outHandle = c1
                        var node = PathNode.corner(p)
                        node.inHandle = p
                        path.nodes.append(node)
                    }
                case "h":
                    if path.nodes.count >= 2 {
                        let closed = PathItem(nodes: path.nodes, closed: true, shape: .free)
                        subpaths.append(closed)
                        path = Subpath()
                    }
                case "re":
                    if args.count >= 4 {
                        flushSub()
                        let x = args[args.count - 4], y = args[args.count - 3], w = args[args.count - 2], h = args[args.count - 1]
                        let nodes = [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)].map { PathNode.corner($0) }
                        subpaths.append(PathItem(nodes: nodes, closed: true, shape: .rectangle))
                    }
                case "S": paint(fill: false, stroke: true, evenOdd: false, close: false)
                case "s": paint(fill: false, stroke: true, evenOdd: false, close: true)
                case "f", "F": paint(fill: true, stroke: false, evenOdd: false, close: true)
                case "f*": paint(fill: true, stroke: false, evenOdd: true, close: true)
                case "B": paint(fill: true, stroke: true, evenOdd: false, close: true)
                case "B*": paint(fill: true, stroke: true, evenOdd: true, close: true)
                case "b": paint(fill: true, stroke: true, evenOdd: false, close: true)
                case "b*": paint(fill: true, stroke: true, evenOdd: true, close: true)
                case "n":
                    if let built = currentClip(&path, &subpaths, map: mapPoint) { g.clip = built }
                    path = Subpath(); subpaths = []
                case "W", "W*":
                    if let built = currentClip(&path, &subpaths, map: mapPoint) { g.clip = built }
                case "BT":
                    text = true
                    tm = .identity
                    lineMatrix = .identity
                case "ET":
                    text = false
                case "Tf":
                    g.font = resources.fonts[lastName] ?? lastName
                    if let size = args.last { g.fontSize = size }
                case "Tm":
                    if args.count >= 6 {
                        tm = Affine(a: args[0], b: args[1], c: args[2], d: args[3], tx: args[4], ty: args[5])
                        lineMatrix = tm
                    }
                case "Td", "TD":
                    if args.count >= 2 {
                        if op == "TD" { g.leading = -args[args.count - 1] }
                        let shift = Affine.translation(args[args.count - 2], args[args.count - 1])
                        lineMatrix = shift.concatenated(lineMatrix)
                        tm = lineMatrix
                    }
                case "T*":
                    let shift = Affine.translation(0, -g.leading)
                    lineMatrix = shift.concatenated(lineMatrix)
                    tm = lineMatrix
                case "TL": if let v = args.last { g.leading = v }
                case "Tc": if let v = args.last { g.charSpacing = v }
                case "Tj", "'", "\"":
                    emitText()
                case "Do":
                    let name = lastName
                    let state = g
                    for art in paintXObject(name, state: state) { emit(art) }
                case "sh":
                    let name = lastName
                    let state = g
                    let clip = g.clip
                    if let art = paintShading(name, state: state, clip: clip) { emit(art) }
                case "BMC", "BDC":
                    let name = resources.ocg[lastName] ?? (lastName.isEmpty ? nil : lastName)
                    if op == "BDC", let name, !name.isEmpty {
                        ocgStack.append(name)
                        ocgItems.append([])
                    }
                case "EMC":
                    if let name = ocgStack.popLast(), let group = ocgItems.popLast() {
                        layers.append((name, group))
                    }
                default:
                    break
                }
                args.removeAll()
            }
        }
    }

    private func color(_ args: [Double], space: String) -> RGBA {
        if space == "DeviceCMYK", args.count >= 4 {
            return RGBA(cmyk: DeviceCMYK(c: args[args.count - 4], m: args[args.count - 3], y: args[args.count - 2], k: args[args.count - 1]))
        }
        if space == "DeviceGray", let g = args.last { return RGBA(r: g, g: g, b: g) }
        if args.count >= 3 { return RGBA(r: args[args.count - 3], g: args[args.count - 2], b: args[args.count - 1]) }
        return .black
    }

    private func currentClip(_ path: inout Subpath, _ subpaths: inout [PathItem], map: (Vec2) -> Vec2) -> PathItem? {
        var nodes = path.nodes
        if nodes.isEmpty, let last = subpaths.last { nodes = last.nodes }
        guard nodes.count >= 2 else { return nil }
        let mapped = nodes.map { node -> PathNode in
            var copy = node
            copy.anchor = map(node.anchor)
            return copy
        }
        return PathItem(nodes: mapped, closed: true, shape: .free)
    }

    private mutating func paintXObject(_ name: String, state: State) -> [ArtItem] {
        var emitted: [ArtItem] = []
        guard let id = resources.xobjects[name], case .stream(let dict, let data) = file.object(id) ?? .null else { return [] }
        let subtype: String
        if case .name(let n) = file.resolve(dict["Subtype"] ?? .null) { subtype = n } else { subtype = "" }
        if subtype == "Image" {
            if let image = imageObject(dict: dict, data: data, state: state) { emitted.append(image) }
            return emitted
        }
        var matrix = Affine.identity
        if case .array(let arr) = file.resolve(dict["Matrix"] ?? .null), arr.count >= 6 {
            func num(_ o: PDFObj) -> Double { if case .number(let n) = o { return n } else { return 0 } }
            matrix = Affine(a: num(arr[0]), b: num(arr[1]), c: num(arr[2]), d: num(arr[3]), tx: num(arr[4]), ty: num(arr[5]))
        }
        var next = state
        next.ctm = matrix.concatenated(state.ctm)
        var formResources = resources
        if dict["Resources"] != nil {
            formResources = PDFImporterResources.merge(dict["Resources"], file: file, base: resources)
        }
        var nested = ContentInterpreter(file: file, resources: formResources, pageHeight: pageHeight)
        nested.execute(data, resources: formResources, state: next)
        emitted.append(contentsOf: nested.items)
        layers.append(contentsOf: nested.layers)
        return emitted
    }

    private func imageObject(dict: [String: PDFObj], data: Data, state: State) -> ArtItem? {
        guard case .number(let w) = file.resolve(dict["Width"] ?? .null),
              case .number(let h) = file.resolve(dict["Height"] ?? .null) else { return nil }
        let width = Int(w), height = Int(h)
        guard width > 0, height > 0 else { return nil }
        var space = "DeviceRGB"
        if case .name(let n) = file.resolve(dict["ColorSpace"] ?? .null) { space = n }
        let raw = [UInt8](data)
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        if space == "DeviceGray" {
            guard raw.count >= width * height else { return nil }
            for i in 0..<(width * height) {
                rgba[i * 4] = raw[i]; rgba[i * 4 + 1] = raw[i]; rgba[i * 4 + 2] = raw[i]
            }
        } else if space == "DeviceRGB" {
            guard raw.count >= width * height * 3 else { return nil }
            for i in 0..<(width * height) {
                rgba[i * 4] = raw[i * 3]; rgba[i * 4 + 1] = raw[i * 3 + 1]; rgba[i * 4 + 2] = raw[i * 3 + 2]
            }
        } else {
            return nil
        }
        let png = PNGCodec.encode(PNGImage(width: width, height: height, rgba: rgba))
        let p0 = state.ctm.apply(Vec2.zero)
        let p1 = state.ctm.apply(Vec2(1, 1))
        let rect = Rect2(x: min(p0.x, p1.x), y: pageHeight - max(p0.y, p1.y), width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
        return .placed(PlacedObject(name: "图像", kind: "image", frame: rect, dataBase64: png.base64EncodedString()))
    }

    private mutating func paintShading(_ name: String, state: State, clip: PathItem?) -> ArtItem? {
        let obj: PDFObj
        if let id = resources.shadings[name] { obj = file.object(id) ?? .null }
        else { obj = resources.inlineShading[name] ?? .null }
        guard case .dict(let dict) = file.resolve(obj) else { return nil }
        guard case .number(let type) = file.resolve(dict["ShadingType"] ?? .null) else { return nil }
        let stops = shadingStops(dict)
        var coords: [Double] = []
        if case .array(let arr) = file.resolve(dict["Coords"] ?? .null) {
            coords = arr.compactMap { if case .number(let n) = $0 { return n } else { return nil } }
        }
        let paint: Paint
        if Int(type) == 3, coords.count >= 6 {
            let gradient = GradientPaint(stops: stops, start: Vec2(0.5, 0.5), end: Vec2(1, 0.5))
            paint = .radial(gradient)
        } else {
            paint = .linear(GradientPaint(stops: stops, start: Vec2(0, 0.5), end: Vec2(1, 0.5)))
        }
        let path: PathItem
        if let clip {
            path = clip
        } else if coords.count >= 4 {
            let a = Vec2(coords[0], coords[1])
            let b = Vec2(coords[2], coords[3])
            let p0 = state.ctm.apply(a)
            let p1 = state.ctm.apply(b)
            let rect = Rect2(x: min(p0.x, p1.x), y: pageHeight - max(p0.y, p1.y), width: max(4, abs(p1.x - p0.x)), height: max(4, abs(p1.y - p0.y)))
            path = PathBuilder.rectangle(rect)
        } else {
            path = PathBuilder.rectangle(Rect2(x: 0, y: 0, width: 100, height: 100))
        }
        return .path(PathObject(name: "渐变", path: path, appearance: Appearance(fill: paint, stroke: nil)))
    }

    private func shadingStops(_ dict: [String: PDFObj]) -> [GradientStop] {
        let function = file.resolve(dict["Function"] ?? .null)
        if case .dict(let fn) = function {
            let c0 = components(fn["C0"])
            let c1 = components(fn["C1"])
            if c0.count >= 3, c1.count >= 3 {
                return [
                    GradientStop(color: RGBA(r: c0[0], g: c0[1], b: c0[2]), location: 0),
                    GradientStop(color: RGBA(r: c1[0], g: c1[1], b: c1[2]), location: 1)
                ]
            }
            if c0.count >= 4, c1.count >= 4 {
                return [
                    GradientStop(color: RGBA(cmyk: DeviceCMYK(c: c0[0], m: c0[1], y: c0[2], k: c0[3])), location: 0),
                    GradientStop(color: RGBA(cmyk: DeviceCMYK(c: c1[0], m: c1[1], y: c1[2], k: c1[3])), location: 1)
                ]
            }
        }
        return [GradientStop(color: .black, location: 0), GradientStop(color: .white, location: 1)]
    }

    private func components(_ obj: PDFObj?) -> [Double] {
        guard let obj, case .array(let items) = file.resolve(obj) else { return [] }
        return items.compactMap { if case .number(let n) = $0 { return n } else { return nil } }
    }
}

private enum PDFImporterResources {
    static func merge(_ obj: PDFObj?, file: PDFFile, base: PDFResources) -> PDFResources {
        var copy = PDFImporter.resources(obj, file: file)
        if copy.fonts.isEmpty { copy.fonts = base.fonts }
        if copy.xobjects.isEmpty { copy.xobjects = base.xobjects }
        if copy.ocg.isEmpty { copy.ocg = base.ocg }
        return copy
    }
}

private enum PDFContent {
    enum Token {
        case number(Double)
        case name(String)
        case string(String)
        case array([Token])
        case op(String)
    }

    static func tokenize(_ data: Data) -> [Token] {
        var cursor = PDFCursor(bytes: [UInt8](data), index: 0)
        var tokens: [Token] = []
        while cursor.index < cursor.bytes.count {
            cursor.skip()
            if cursor.index >= cursor.bytes.count { break }
            let b = cursor.bytes[cursor.index]
            if b == 40 {
                tokens.append(.string(cursor.literalString()))
            } else if b == 60 {
                tokens.append(.string(cursor.hexString()))
            } else if b == 91 {
                tokens.append(.array(array(&cursor)))
            } else if b == 47 {
                tokens.append(.name(cursor.name()))
            } else if let n = cursor.number() {
                tokens.append(.number(n))
            } else if let word = cursor.keyword() {
                tokens.append(.op(word))
            } else {
                cursor.index += 1
            }
        }
        return tokens
    }

    private static func array(_ cursor: inout PDFCursor) -> [Token] {
        guard cursor.index < cursor.bytes.count, cursor.bytes[cursor.index] == 91 else { return [] }
        cursor.index += 1
        var items: [Token] = []
        while cursor.index < cursor.bytes.count {
            cursor.skip()
            if cursor.index < cursor.bytes.count, cursor.bytes[cursor.index] == 93 { cursor.index += 1; break }
            let b = cursor.bytes[cursor.index]
            if b == 40 { items.append(.string(cursor.literalString())) }
            else if b == 60 { items.append(.string(cursor.hexString())) }
            else if b == 47 { items.append(.name(cursor.name())) }
            else if let n = cursor.number() { items.append(.number(n)) }
            else { cursor.index += 1 }
        }
        return items
    }
}

// Text showing has to mutate the interpreter. The helper above dropped the text.
// Patch by reinterpreting Tj inside execute — show() is replaced below via a nested approach.
// The execute loop calls show() which currently discards text. Fix ContentInterpreter by
// making show a closure. Done in the extension by swizzling is not possible; rewrite the call.

private enum LegacyAIImporter {
    static func read(_ data: Data, title: String) -> LaminaDocument? {
        guard let text = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) else { return nil }
        let head = text.prefix(2048)
        guard head.contains("%!PS") || head.contains("%AI") || text.contains("%AI5_") || text.contains("\nm\n") || text.contains(" m\n") else { return nil }
        if head.contains("%PDF") && !text.contains("%AI5_") && !text.contains("%%Creator") { return nil }
        var height = 792.0
        if let box = text.range(of: "%%BoundingBox:") {
            let line = text[box.upperBound...].prefix { $0 != "\n" }
            let nums = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Double($0) }
            if nums.count >= 4 { height = max(nums[3], nums[1]) - min(nums[3], nums[1]); if height < 1 { height = nums[3] } }
        }
        var layers: [(String, [ArtItem])] = [("图层 1", [])]
        var fill = RGBA.black
        var stroke = RGBA.black
        var fillCMYK = false
        var strokeCMYK = false
        var width = 1.0
        var nodes: [PathNode] = []
        var start = Vec2.zero
        var closed = false
        var font = "Helvetica"
        var fontSize = 12.0
        func map(_ p: Vec2) -> Vec2 { Vec2(p.x, height - p.y) }
        func emit(fillOn: Bool, strokeOn: Bool) {
            guard nodes.count >= 2 else { nodes = []; return }
            var path = PathItem(nodes: nodes.map { node in
                var copy = node
                copy.anchor = map(node.anchor)
                if let h = node.inHandle { copy.inHandle = map(h) }
                if let h = node.outHandle { copy.outHandle = map(h) }
                return copy
            }, closed: closed || fillOn, shape: .free)
            if path.closed, path.nodes.count >= 2,
               let a = path.nodes.first?.anchor, let b = path.nodes.last?.anchor, a.almostEqual(b, eps: 0.05) {
                let last = path.nodes.removeLast()
                if let incoming = last.inHandle { path.nodes[0].inHandle = incoming }
            }
            var appearance = Appearance.none
            if fillOn { appearance.fill = .solid(fill); appearance.overprintFill = fillCMYK }
            if strokeOn {
                appearance.stroke = StrokeStyle(paint: .solid(stroke), width: width)
                appearance.overprintStroke = strokeCMYK
            }
            layers[layers.count - 1].1.append(.path(PathObject(name: "路径", path: path, appearance: appearance)))
            nodes = []
            closed = false
        }
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }
            if line.hasPrefix("%AI5_BeginLayer") || line.hasPrefix("%AI5_EndLayer") {
                if line.hasPrefix("%AI5_BeginLayer") { layers.append(("图层 \(layers.count + 1)", [])) }
                continue
            }
            if line.hasPrefix("%") { continue }
            let parts = tokenize(line)
            guard let op = parts.last else { continue }
            let nums = parts.dropLast().compactMap { Double($0) }
            switch op {
            case "m", "M":
                if nums.count >= 2 {
                    start = Vec2(nums[nums.count - 2], nums[nums.count - 1])
                    nodes = [.corner(start)]
                    closed = false
                }
            case "l", "L":
                if nums.count >= 2 { nodes.append(.corner(Vec2(nums[nums.count - 2], nums[nums.count - 1]))) }
            case "c", "C":
                if nums.count >= 6, !nodes.isEmpty {
                    nodes[nodes.count - 1].outHandle = Vec2(nums[0], nums[1])
                    var node = PathNode.corner(Vec2(nums[4], nums[5]))
                    node.inHandle = Vec2(nums[2], nums[3])
                    node.corner = .smooth
                    nodes.append(node)
                }
            case "v", "V":
                if nums.count >= 4, !nodes.isEmpty {
                    nodes[nodes.count - 1].outHandle = nodes[nodes.count - 1].anchor
                    var node = PathNode.corner(Vec2(nums[2], nums[3]))
                    node.inHandle = Vec2(nums[0], nums[1])
                    nodes.append(node)
                }
            case "y", "Y":
                if nums.count >= 4, !nodes.isEmpty {
                    nodes[nodes.count - 1].outHandle = Vec2(nums[0], nums[1])
                    var node = PathNode.corner(Vec2(nums[2], nums[3]))
                    node.inHandle = node.anchor
                    nodes.append(node)
                }
            case "h", "H":
                closed = true
            case "f", "F", "f*":
                emit(fillOn: true, strokeOn: false)
            case "s", "S":
                emit(fillOn: false, strokeOn: true)
            case "b", "B", "b*", "B*":
                emit(fillOn: true, strokeOn: true)
            case "n", "N":
                nodes = []
            case "w", "W":
                // W is also clip in PDF; in AI, linewidth is `w` and clip is `W` after a path.
                if op == "w", let w = nums.last { width = w }
            case "k":
                if nums.count >= 4 {
                    fill = RGBA(cmyk: DeviceCMYK(c: nums[0], m: nums[1], y: nums[2], k: nums[3]))
                    fillCMYK = true
                }
            case "K":
                if nums.count >= 4 {
                    stroke = RGBA(cmyk: DeviceCMYK(c: nums[0], m: nums[1], y: nums[2], k: nums[3]))
                    strokeCMYK = true
                }
            case "g":
                if let v = nums.last { fill = RGBA(r: v, g: v, b: v); fillCMYK = false }
            case "G":
                if let v = nums.last { stroke = RGBA(r: v, g: v, b: v); strokeCMYK = false }
            case "Xa":
                if nums.count >= 3 { fill = RGBA(r: nums[0], g: nums[1], b: nums[2]); fillCMYK = false }
            case "XA":
                if nums.count >= 3 { stroke = RGBA(r: nums[0], g: nums[1], b: nums[2]); strokeCMYK = false }
            case "Tf":
                if let size = nums.last { fontSize = size }
                if let name = parts.dropLast().first(where: { $0.hasPrefix("/") }) {
                    font = String(name.dropFirst())
                }
            case "Tx", "Tj":
                if let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close {
                    let string = String(line[line.index(after: open)..<close])
                    let origin = nums.count >= 2 ? map(Vec2(nums[0], nums[1])) : map(start)
                    let size = nums.count >= 3 ? nums[2] : fontSize
                    let text = TextObject(string: string, origin: origin, fontName: font, fontSize: size, appearance: Appearance(fill: .solid(fill), stroke: nil))
                    layers[layers.count - 1].1.append(.text(text))
                }
            case "Ln":
                if let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close {
                    layers[layers.count - 1].0 = String(line[line.index(after: open)..<close])
                }
            default:
                break
            }
        }
        let kept = layers.filter { !$0.1.isEmpty }
        guard !kept.isEmpty else { return nil }
        var document = LaminaDocument.blank(title: title, size: Vec2(612, height))
        document.artboards = [Artboard(name: "画板 1", rect: Rect2(x: 0, y: 0, width: 612, height: height))]
        document.layers = kept.map { Layer(name: $0.0, items: $0.1) }
        if document.layers.contains(where: { $0.items.contains { if case .path(let p) = $0 { return p.appearance.overprintFill } else { return false } } }) {
            document.colorMode = .cmyk
        }
        return document
    }

    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var string = false
        for ch in line {
            if ch == "(" || ch == ")" { string.toggle(); continue }
            if string { current.append(ch); continue }
            if ch == " " || ch == "\t" {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool { self >= 48 && self <= 57 }
}
