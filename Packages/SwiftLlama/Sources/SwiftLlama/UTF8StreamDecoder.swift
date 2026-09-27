//
//  UTF8StreamDecoder.swift
//  mirror patch (see PATCHES.md #6)
//

import Foundation

/// Turns a stream of token byte pieces into text without losing characters that span tokens.
///
/// A token isn't always a whole character: the tokenizer can emit one multi-byte UTF-8 character
/// (common for CJK, especially when a grammar constrains sampling) as several byte-level tokens.
/// Decoding each token's bytes on its own turns those partial sequences into "" or "�", so the
/// character silently disappears. This buffers an incomplete trailing sequence until the bytes
/// that finish it arrive.
public struct UTF8StreamDecoder: Sendable {
    private var pending: [UInt8] = []

    public init() {}

    /// Appends one token's bytes and returns every character they complete.
    public mutating func append(_ bytes: [UInt8]) -> String {
        pending += bytes
        let split = Self.completePrefixLength(pending)
        let complete = Array(pending[..<split])
        pending = Array(pending[split...])
        if pending.count > 4 {
            // Can't be the start of a valid sequence any more — emit it lossily rather than
            // holding output back forever.
            defer { pending = [] }
            return String(decoding: complete + pending, as: UTF8.self)
        }
        return String(decoding: complete, as: UTF8.self)
    }

    /// Length of the longest prefix that doesn't end inside an unfinished multi-byte sequence.
    static func completePrefixLength(_ bytes: [UInt8]) -> Int {
        var index = bytes.count - 1
        var continuationBytes = 0
        while index >= 0, continuationBytes < 3, bytes[index] & 0xC0 == 0x80 {
            continuationBytes += 1
            index -= 1
        }
        guard index >= 0 else { return 0 }
        let lead = bytes[index]
        let expected: Int
        switch lead {
        case 0x00..<0x80: expected = 1
        case 0xC0..<0xE0: expected = 2
        case 0xE0..<0xF0: expected = 3
        case 0xF0..<0xF8: expected = 4
        default: expected = 1
        }
        return bytes.count - index < expected ? index : bytes.count
    }
}
