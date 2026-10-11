import Compression
import Foundation

enum ZlibError: Error { case notGzip, corrupt, tooLarge }

/// Apple's `Compression` speaks only raw DEFLATE, so framing and checksums are done here.
enum Zlib {
    static let defaultMaxOutput = 64 * 1024 * 1024

    static func gunzip(_ data: Data, maxOutput: Int = defaultMaxOutput) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else {
            throw ZlibError.notGzip
        }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {
            guard index + 2 <= bytes.count else { throw ZlibError.corrupt }
            index += 2 + (Int(bytes[index]) | Int(bytes[index + 1]) << 8)
        }
        if flags & 0x08 != 0 { index = try skipCString(bytes, from: index) }
        if flags & 0x10 != 0 { index = try skipCString(bytes, from: index) }
        if flags & 0x02 != 0 { index += 2 }
        guard index < bytes.count - 8 else { throw ZlibError.corrupt }
        return try inflateRaw(Data(bytes[index..<(bytes.count - 8)]), maxOutput: maxOutput)
    }

    static func gzip(_ data: Data) throws -> Data {
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
        out.append(try deflateRaw(data))
        out.append(littleEndian(crc32(data)))
        out.append(littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return out
    }

    static func inflateRaw(_ data: Data, maxOutput: Int = defaultMaxOutput) throws -> Data {
        try stream(data, operation: COMPRESSION_STREAM_DECODE, maxOutput: maxOutput)
    }

    static func deflateRaw(_ data: Data) throws -> Data {
        try stream(data, operation: COMPRESSION_STREAM_ENCODE, maxOutput: Int.max)
    }

    private static func skipCString(_ bytes: [UInt8], from start: Int) throws -> Int {
        var i = start
        while i < bytes.count {
            if bytes[i] == 0 { return i + 1 }
            i += 1
        }
        throw ZlibError.corrupt
    }

    private static func stream(
        _ input: Data, operation: compression_stream_operation, maxOutput: Int
    ) throws -> Data {
        let bufferSize = 256 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        // The C struct has no zero-arg init; the placeholders are overwritten before use.
        var handle = compression_stream(
            dst_ptr: dst, dst_size: bufferSize, src_ptr: dst, src_size: 0, state: nil)
        guard compression_stream_init(&handle, operation, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR
        else { throw ZlibError.corrupt }
        defer { compression_stream_destroy(&handle) }

        enum Outcome { case done(Data), overflow, failed }
        let outcome: Outcome = input.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return .done(Data()) }
            handle.src_ptr = base
            handle.src_size = raw.count
            var out = Data()
            while true {
                handle.dst_ptr = dst
                handle.dst_size = bufferSize
                let status = compression_stream_process(
                    &handle, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    out.append(dst, count: bufferSize - handle.dst_size)
                    if out.count > maxOutput { return .overflow }
                    if status == COMPRESSION_STATUS_END { return .done(out) }
                default:
                    return .failed
                }
            }
        }
        switch outcome {
        case .done(let data): return data
        case .overflow: throw ZlibError.tooLarge
        case .failed: throw ZlibError.corrupt
        }
    }

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8(value >> 24)
        ])
    }
}
