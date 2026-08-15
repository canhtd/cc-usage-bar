import Foundation
import Testing

@testable import CCUsageBar

/// R1: the decoder must survive a chunk boundary anywhere inside a multi-byte sequence.
@Suite("UTF-8 stream decoder")
struct UTF8StreamDecoderTests {
    /// Every glyph the usage panel actually prints, plus a 4-byte scalar for good measure.
    static let sample = "█▉▊▋▌▍▎▏░▒▓ · — ❯ é 🎉 中文"

    @Test("Splitting at every byte offset reproduces the input exactly")
    func splitAtEveryOffset() {
        let bytes = Array(Self.sample.utf8)
        for split in 0...bytes.count {
            let decoder = UTF8StreamDecoder()
            var output = decoder.decode(Data(bytes[0..<split]))
            output += decoder.decode(Data(bytes[split...]))
            output += decoder.flush()
            #expect(output == Self.sample, "failed at split \(split)")
        }
    }

    @Test("Byte-at-a-time delivery reproduces the input exactly")
    func oneByteAtATime() {
        let decoder = UTF8StreamDecoder()
        var output = ""
        for byte in Array(Self.sample.utf8) {
            output += decoder.decode(Data([byte]))
        }
        output += decoder.flush()
        #expect(output == Self.sample)
    }

    @Test("Three-way splits of a four-byte scalar reproduce it exactly")
    func threeWaySplits() {
        let source = "a🎉b"
        let bytes = Array(source.utf8)
        for first in 0...bytes.count {
            for second in first...bytes.count {
                let decoder = UTF8StreamDecoder()
                var output = decoder.decode(Data(bytes[0..<first]))
                output += decoder.decode(Data(bytes[first..<second]))
                output += decoder.decode(Data(bytes[second...]))
                output += decoder.flush()
                #expect(output == source, "failed at \(first)/\(second)")
            }
        }
    }

    @Test("A truncated sequence is held back rather than emitted as mojibake")
    func holdsBackIncompleteSequence() {
        let decoder = UTF8StreamDecoder()
        // First two bytes of U+2588 FULL BLOCK.
        #expect(decoder.decode(Data([0xE2, 0x96])) == "")
        #expect(decoder.decode(Data([0x88])) == "█")
    }

    @Test("Invalid bytes become U+FFFD, never Latin-1")
    func invalidBytesBecomeReplacement() {
        let decoder = UTF8StreamDecoder()
        let output = decoder.decode(Data([0x41, 0xE2, 0x28, 0xA1, 0x42])) + decoder.flush()
        #expect(output.contains("A"))
        #expect(output.contains("B"))
        #expect(output.contains("\u{FFFD}"))
        // 0xE2 as Latin-1 would be "â"; that is the bug this decoder exists to prevent.
        #expect(!output.contains("â"))
    }

    @Test("The prefix scan never buffers more than three bytes")
    func boundaryNeverBuffersWholeChunk() {
        let bytes: [UInt8] = [0x80, 0x80, 0x80, 0x80, 0x80]
        #expect(UTF8StreamDecoder.completePrefixLength(of: bytes) == bytes.count)
        #expect(UTF8StreamDecoder.completePrefixLength(of: [0xF0, 0x9F, 0x8E]) == 0)
        #expect(UTF8StreamDecoder.completePrefixLength(of: [0x41, 0xF0, 0x9F, 0x8E, 0x89]) == 5)
    }
}
