import Foundation

/// Incremental UTF-8 decoder for a byte stream that arrives in arbitrary chunks.
///
/// A PTY hands us whatever bytes happen to be in the kernel buffer, so a multi-byte
/// character such as `█` (E2 96 88) is routinely split across two `read()` calls.
/// Decoding each chunk independently corrupts it; falling back to Latin-1 -- the bug
/// this app exists to fix -- turns it into mojibake such as `â`.
///
/// This decoder keeps any incomplete trailing sequence in `pending` and prepends it to
/// the next chunk. Bytes that are genuinely invalid UTF-8 become U+FFFD; the stream is
/// never reinterpreted in another encoding.
nonisolated final class UTF8StreamDecoder {
    /// Bytes of a multi-byte sequence seen so far but not yet complete (at most 3).
    private var pending: [UInt8] = []

    init() {}

    /// Decodes as much of `data` as forms complete scalars, carrying the remainder over.
    func decode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var bytes = pending
        bytes.append(contentsOf: data)

        let boundary = Self.completePrefixLength(of: bytes)
        pending = boundary < bytes.count ? Array(bytes[boundary...]) : []
        guard boundary > 0 else { return "" }
        return String(decoding: bytes[..<boundary], as: UTF8.self)
    }

    /// Flushes buffered bytes at end of stream, emitting U+FFFD for a truncated tail.
    func flush() -> String {
        guard !pending.isEmpty else { return "" }
        let tail = pending
        pending = []
        return String(decoding: tail, as: UTF8.self)
    }

    /// Number of leading bytes in `bytes` that form whole UTF-8 sequences.
    ///
    /// Scans backwards over at most three continuation bytes to find the lead byte of the
    /// trailing sequence; if that sequence is short, the boundary sits before its lead byte.
    /// Because at most three continuations are skipped, the carried-over tail is <= 3 bytes.
    static func completePrefixLength(of bytes: [UInt8]) -> Int {
        let count = bytes.count
        guard count > 0 else { return 0 }
        var index = count - 1
        var continuations = 0
        while index >= 0, isContinuation(bytes[index]), continuations < 3 {
            index -= 1
            continuations += 1
        }
        guard index >= 0 else { return count }  // nothing but continuations: emit U+FFFD now
        let expected = sequenceLength(of: bytes[index])
        guard expected > 0 else { return count }  // invalid lead byte: emit U+FFFD now
        return count - index < expected ? index : count
    }

    private static func isContinuation(_ byte: UInt8) -> Bool { byte & 0b1100_0000 == 0b1000_0000 }

    /// Expected total length of the sequence starting with `byte`, or 0 if it cannot start one.
    private static func sequenceLength(of byte: UInt8) -> Int {
        switch byte {
        case 0x00...0x7F: return 1
        case 0xC2...0xDF: return 2
        case 0xE0...0xEF: return 3
        case 0xF0...0xF4: return 4
        default: return 0
        }
    }
}
