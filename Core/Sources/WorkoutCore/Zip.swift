import Foundation
import Compression

/*
 * The zip an .xlsx is: read, and written back surgically.
 *
 * A port of js/zip.js. Reading trusts the central directory for sizes and CRC
 * (a local header may leave them zero) but the local header for where the data
 * starts, since its extra field can differ from the central one.
 *
 * Writing is the half that matters. An entry nobody changed is copied across
 * still compressed, with its original CRC — never decoded, so nothing Excel put
 * there can be lost in a round trip. Only the parts an edit touched are
 * compressed again. Every header is laid out exactly as js/zip.js lays it out
 * (version 20, UTF-8 flag, the fixed 1996-01-01 date, no extra fields), so the
 * native and web writers produce archives that differ in one place only: the
 * deflate stream of a changed part, because Apple's compressor and the
 * browser's choose different encodings of the same bytes. tools/write-parity
 * unpacks those and compares the text.
 */
public struct ZipArchive {
    public struct Entry {
        public let name: String
        public let method: UInt16
        public let crc: UInt32
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let dataStart: Int
    }

    public enum ZipError: Error, LocalizedError {
        case notAZip
        case truncated(String)
        case unsupported(String)
        case inflateFailed(String)
        case deflateFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notAZip: return "This file is not a workbook — it is not a zip archive."
            case .truncated(let name): return "The workbook is cut short (\(name))."
            case .unsupported(let what): return "The workbook uses something this app cannot unpack (\(what))."
            case .inflateFailed(let name): return "Part of the workbook could not be unpacked (\(name))."
            case .deflateFailed(let name): return "Part of the workbook could not be packed again (\(name))."
            }
        }
    }

    public let data: Data
    public let entries: [Entry]
    private let byName: [String: Entry]

    public init(data: Data) throws {
        self.data = data
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notAZip }

        var eocd = -1
        var i = bytes.count - 22
        let floor = max(0, bytes.count - 66_000)
        while i >= floor {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4b, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let count = Int(Self.u16(bytes, eocd + 10))
        var offset = Int(Self.u32(bytes, eocd + 16))
        if offset == 0xFFFF_FFFF || count == 0xFFFF { throw ZipError.unsupported("zip64") }

        var list: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, Self.u32(bytes, offset) == 0x0201_4b50 else { break }
            let method = Self.u16(bytes, offset + 10)
            let crc = Self.u32(bytes, offset + 16)
            let compressed = Self.u32(bytes, offset + 20)
            let uncompressed = Self.u32(bytes, offset + 24)
            let nameLength = Int(Self.u16(bytes, offset + 28))
            let extraLength = Int(Self.u16(bytes, offset + 30))
            let commentLength = Int(Self.u16(bytes, offset + 32))
            let local = Int(Self.u32(bytes, offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { throw ZipError.truncated("central directory") }
            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || local == 0xFFFF_FFFF {
                throw ZipError.unsupported("zip64")
            }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            guard local + 30 <= bytes.count else { throw ZipError.truncated(name) }
            let localName = Int(Self.u16(bytes, local + 26))
            let localExtra = Int(Self.u16(bytes, local + 28))
            list.append(Entry(name: name, method: method, crc: crc, compressedSize: Int(compressed),
                              uncompressedSize: Int(uncompressed), dataStart: local + 30 + localName + localExtra))
            offset += 46 + nameLength + extraLength + commentLength
        }

        entries = list
        var map: [String: Entry] = [:]
        for entry in list { map[entry.name] = entry }
        byName = map
    }

    public func entry(_ name: String) -> Entry? { byName[name] }
    public func has(_ name: String) -> Bool { byName[name] != nil }

    public func raw(_ entry: Entry) throws -> Data {
        guard entry.dataStart + entry.compressedSize <= data.count else { throw ZipError.truncated(entry.name) }
        return data.subdata(in: entry.dataStart..<(entry.dataStart + entry.compressedSize))
    }

    public func bytes(_ name: String) throws -> Data? {
        guard let entry = byName[name] else { return nil }
        let raw = try raw(entry)
        switch entry.method {
        case 0: return raw
        case 8: return try Self.inflate(raw, size: entry.uncompressedSize, name: name)
        default: throw ZipError.unsupported("compression method \(entry.method)")
        }
    }

    public func text(_ name: String) throws -> String? {
        try bytes(name).map(decodeUTF8)
    }

    static func inflate(_ raw: Data, size: Int, name: String) throws -> Data {
        if size == 0 { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            raw.withUnsafeBytes { src in
                // COMPRESSION_ZLIB is raw DEFLATE, which is what zip stores.
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.inflateFailed(name) }
        return out
    }

    static func deflate(_ plain: Data, name: String) throws -> Data {
        // Deflate can in principle grow incompressible input slightly.
        let capacity = plain.count + plain.count / 10 + 1024
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst in
            plain.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, plain.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw ZipError.deflateFailed(name) }
        out.count = written
        return out
    }

    fileprivate static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    fileprivate static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}

/* TextDecoder('utf-8') drops a leading byte-order mark; so must this, or a
   part that carried one would come back out one character longer. */
func decodeUTF8(_ data: Data) -> String {
    var s = String(decoding: data, as: UTF8.self)
    if s.unicodeScalars.first == "\u{FEFF}" { s.unicodeScalars.removeFirst() }
    return s
}

private let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
    var c = UInt32(i)
    for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
    return c
}

public func crc32(_ data: Data) -> UInt32 {
    var c: UInt32 = 0xFFFF_FFFF
    for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
    return c ^ 0xFFFF_FFFF
}

/*
 * An opened archive with changes pending: the js/zip.js Archive class.
 * `order` keeps the original entry order, so a workbook that goes through
 * without edits comes out laid out as it went in.
 */
public final class Archive {
    public let zip: ZipArchive
    private(set) var order: [String]
    private var overrides: [String: Data] = [:]
    private var removed = Set<String>()
    private var plainCache: [String: Data] = [:]

    public init(data: Data) throws {
        zip = try ZipArchive(data: data)
        order = zip.entries.map(\.name)
    }

    public func has(_ name: String) -> Bool {
        (zip.has(name) || overrides[name] != nil) && !removed.contains(name)
    }

    public var names: [String] { order.filter { !removed.contains($0) } }

    public func file(_ name: String) throws -> Data? {
        if removed.contains(name) { return nil }
        if let override = overrides[name] { return override }
        if let cached = plainCache[name] { return cached }
        guard let plain = try zip.bytes(name) else { return nil }
        plainCache[name] = plain
        return plain
    }

    public func text(_ name: String) throws -> String? { try file(name).map(decodeUTF8) }

    public func set(_ name: String, _ text: String) {
        overrides[name] = Data(text.utf8)
        removed.remove(name)
        if !order.contains(name) { order.append(name) }
    }

    public func remove(_ name: String) { removed.insert(name) }

    public func save() throws -> Data {
        var out = Data()
        struct Central { let name: Data; let method: UInt16; let crc: UInt32; let comp: Int; let uncomp: Int; let offset: Int }
        var central: [Central] = []

        for name in order where !removed.contains(name) {
            let method: UInt16
            let crc: UInt32
            let uncomp: Int
            let payload: Data

            if let plain = overrides[name] {
                crc = crc32(plain)
                uncomp = plain.count
                if plain.count > 0 {
                    payload = try ZipArchive.deflate(plain, name: name)
                    method = 8
                } else {
                    payload = plain
                    method = 0
                }
            } else {
                guard let entry = zip.entry(name) else { continue }
                method = entry.method
                crc = entry.crc
                uncomp = entry.uncompressedSize
                payload = try zip.raw(entry)
            }

            let nameBytes = Data(name.utf8)
            let offset = out.count
            out.append(le32(0x0403_4b50))
            out.append(le16(20))
            out.append(le16(0x0800))
            out.append(le16(method))
            out.append(le16(0))
            out.append(le16(0x21))
            out.append(le32(crc))
            out.append(le32(UInt32(payload.count)))
            out.append(le32(UInt32(uncomp)))
            out.append(le16(UInt16(nameBytes.count)))
            out.append(le16(0))
            out.append(nameBytes)
            out.append(payload)
            central.append(Central(name: nameBytes, method: method, crc: crc, comp: payload.count, uncomp: uncomp, offset: offset))
        }

        let centralStart = out.count
        for item in central {
            out.append(le32(0x0201_4b50))
            out.append(le16(20))
            out.append(le16(20))
            out.append(le16(0x0800))
            out.append(le16(item.method))
            out.append(le16(0))
            out.append(le16(0x21))
            out.append(le32(item.crc))
            out.append(le32(UInt32(item.comp)))
            out.append(le32(UInt32(item.uncomp)))
            out.append(le16(UInt16(item.name.count)))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le32(0))
            out.append(le32(UInt32(item.offset)))
            out.append(item.name)
        }

        let centralSize = out.count - centralStart
        out.append(le32(0x0605_4b50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(central.count)))
        out.append(le16(UInt16(central.count)))
        out.append(le32(UInt32(centralSize)))
        out.append(le32(UInt32(centralStart)))
        out.append(le16(0))
        return out
    }
}

private func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8)]) }
private func le32(_ v: UInt32) -> Data {
    Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)])
}

/*
 * A zip built from nothing, for saving photographs out of the app — the
 * web app's AmsZip.build. Stored rather than deflated, deliberately: a JPEG
 * is already compressed, so deflating it spends time to make it a fraction
 * of a percent smaller, and store-only keeps this to the one thing it has to
 * get right, which is the offsets. The header fields are the ones save()
 * writes.
 */
public enum ZipBuilder {
    public static func build(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        struct Central { let name: Data; let crc: UInt32; let size: Int; let offset: Int }
        var central: [Central] = []

        for file in files {
            let nameBytes = Data(file.name.utf8)
            let crc = crc32(file.data)
            let offset = out.count
            out.append(le32(0x0403_4b50))
            out.append(le16(20))
            out.append(le16(0x0800))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le16(0x21))
            out.append(le32(crc))
            out.append(le32(UInt32(file.data.count)))
            out.append(le32(UInt32(file.data.count)))
            out.append(le16(UInt16(nameBytes.count)))
            out.append(le16(0))
            out.append(nameBytes)
            out.append(file.data)
            central.append(Central(name: nameBytes, crc: crc, size: file.data.count, offset: offset))
        }

        let centralStart = out.count
        for item in central {
            out.append(le32(0x0201_4b50))
            out.append(le16(20))
            out.append(le16(20))
            out.append(le16(0x0800))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le16(0x21))
            out.append(le32(item.crc))
            out.append(le32(UInt32(item.size)))
            out.append(le32(UInt32(item.size)))
            out.append(le16(UInt16(item.name.count)))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le32(0))
            out.append(le32(UInt32(item.offset)))
            out.append(item.name)
        }
        let centralSize = out.count - centralStart
        out.append(le32(0x0605_4b50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(central.count)))
        out.append(le16(UInt16(central.count)))
        out.append(le32(UInt32(centralSize)))
        out.append(le32(UInt32(centralStart)))
        out.append(le16(0))
        return out
    }
}
