import Foundation
import Compression

/*
 * Reading the zip an .xlsx is.
 *
 * Read-only on purpose. The web app's writer copies every untouched part of
 * the archive across byte for byte, and that is a property to be proven again
 * in Swift before anything here is allowed to write — so this file does not
 * pretend to be half of that yet.
 *
 * The central directory is the authority, not the local headers: a local
 * header may leave its sizes zero and put them in a data descriptor after the
 * data, and Excel does write files that way.
 */
public struct ZipArchive {
    public struct Entry {
        public let name: String
        public let method: UInt16
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let localHeaderOffset: Int
    }

    public enum ZipError: Error, LocalizedError {
        case notAZip
        case truncated(String)
        case unsupported(String)
        case inflateFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notAZip: return "This file is not a workbook — it is not a zip archive."
            case .truncated(let name): return "The workbook is cut short (\(name))."
            case .unsupported(let what): return "The workbook uses something this app cannot unpack (\(what))."
            case .inflateFailed(let name): return "Part of the workbook could not be unpacked (\(name))."
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

        // End of central directory: the last 22 bytes, or further back if the
        // archive carries a comment.
        var eocd = -1
        var i = bytes.count - 22
        let floor = max(0, bytes.count - 22 - 65_535)
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
        if offset == 0xFFFF_FFFF { throw ZipError.unsupported("zip64") }

        var list: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count,
                  Self.u32(bytes, offset) == 0x0201_4b50 else { throw ZipError.truncated("central directory") }
            let method = Self.u16(bytes, offset + 10)
            let compressed = Int(Self.u32(bytes, offset + 20))
            let uncompressed = Int(Self.u32(bytes, offset + 24))
            let nameLength = Int(Self.u16(bytes, offset + 28))
            let extraLength = Int(Self.u16(bytes, offset + 30))
            let commentLength = Int(Self.u16(bytes, offset + 32))
            let local = Int(Self.u32(bytes, offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { throw ZipError.truncated("central directory") }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            list.append(Entry(name: name, method: method, compressedSize: compressed,
                              uncompressedSize: uncompressed, localHeaderOffset: local))
            offset += 46 + nameLength + extraLength + commentLength
        }

        entries = list
        var map: [String: Entry] = [:]
        for entry in list { map[entry.name] = entry }
        byName = map
    }

    public func has(_ name: String) -> Bool { byName[name] != nil }

    public func bytes(_ name: String) throws -> Data? {
        guard let entry = byName[name] else { return nil }
        let start = entry.localHeaderOffset
        guard start + 30 <= data.count else { throw ZipError.truncated(name) }

        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data in
            let base = raw.bindMemory(to: UInt8.self)
            guard Self.u32(base, start) == 0x0403_4b50 else { throw ZipError.truncated(name) }
            let nameLength = Int(Self.u16(base, start + 26))
            let extraLength = Int(Self.u16(base, start + 28))
            let dataStart = start + 30 + nameLength + extraLength
            guard dataStart + entry.compressedSize <= base.count else { throw ZipError.truncated(name) }

            switch entry.method {
            case 0:
                return Data(base[dataStart..<(dataStart + entry.compressedSize)])
            case 8:
                if entry.uncompressedSize == 0 { return Data() }
                var out = Data(count: entry.uncompressedSize)
                let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                    // COMPRESSION_ZLIB is raw DEFLATE, which is what zip stores.
                    compression_decode_buffer(
                        dst.bindMemory(to: UInt8.self).baseAddress!, entry.uncompressedSize,
                        base.baseAddress! + dataStart, entry.compressedSize,
                        nil, COMPRESSION_ZLIB)
                }
                guard written == entry.uncompressedSize else { throw ZipError.inflateFailed(name) }
                return out
            default:
                throw ZipError.unsupported("compression method \(entry.method)")
            }
        }
    }

    public func text(_ name: String) throws -> String? {
        guard let bytes = try bytes(name) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func u16<C: RandomAccessCollection>(_ b: C, _ i: Int) -> UInt16 where C.Element == UInt8, C.Index == Int {
        UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    private static func u32<C: RandomAccessCollection>(_ b: C, _ i: Int) -> UInt32 where C.Element == UInt8, C.Index == Int {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}
