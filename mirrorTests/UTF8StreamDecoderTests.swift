import Testing
import SwiftLlama

// Vendored SwiftLlama patch #6: characters split across tokens must survive decoding.
struct UTF8StreamDecoderTests {
    @Test func multiByteCharacterSplitAcrossTokensIsKept() {
        var decoder = UTF8StreamDecoder()
        let bytes = Array("はじめて".utf8)          // 4 characters × 3 bytes
        var out = ""
        for byte in bytes { out += decoder.append([byte]) }   // worst case: one byte per token
        #expect(out == "はじめて")
    }

    @Test func mixedChunksEmitOnlyCompleteCharacters() {
        var decoder = UTF8StreamDecoder()
        let bytes = Array("今週é😀ok".utf8)
        #expect(decoder.append(Array(bytes[0..<4])) == "今")        // 今 + first byte of 週
        #expect(decoder.append(Array(bytes[4..<7])) == "週")        // rest of 週 + first byte of é
        #expect(decoder.append(Array(bytes[7..<10])) == "é")        // rest of é + 2 bytes of 😀
        #expect(decoder.append(Array(bytes[10...])) == "😀ok")
    }

    @Test func invalidBytesAreFlushedInsteadOfHeldForever() {
        var decoder = UTF8StreamDecoder()
        _ = decoder.append([0x80, 0x80, 0x80])
        #expect(!decoder.append([0x80, 0x80]).isEmpty)
        #expect(decoder.append(Array("a".utf8)) == "a")
    }
}
