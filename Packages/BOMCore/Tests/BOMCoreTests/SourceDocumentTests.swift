import Foundation
import Testing
@testable import BOMCore

@Test func asciiAndLines() {
    let d = SourceDocument(bytes: Array("{\n  \"a\": 1\n}".utf8))
    #expect(d.lineCount == 3)
    #expect(d.line(containing: ByteOffset(value: 4)) == 1)
    #expect(d.lineColumn(of: ByteOffset(value: 4)) == (2, 3))
    #expect(d.utf16Offset(of: ByteOffset(value: 4)).value == 4)
}

@Test func surrogatePairsMap() {
    let s = "{\"k😀\": \"ä\"}"  // 😀 = 4 UTF-8 bytes, 2 UTF-16 units
    let d = SourceDocument(bytes: Array(s.utf8))
    let afterEmoji = ByteOffset(value: 2 + 1 + 4)  // '{' '"' 'k' 😀
    #expect(d.utf16Offset(of: afterEmoji).value == 5)
    #expect(d.byteOffset(of: UTF16Offset(value: 5)) == afterEmoji)
    #expect(d.byteOffset(of: UTF16Offset(value: 4)).value == 3)  // inside the pair rounds down
    let r = ByteOffset(value: 1)..<afterEmoji
    #expect((d.text as NSString).substring(with: d.nsRange(r)) == "\"k😀")
    #expect(d.byteRange(d.nsRange(r)) == r)
}

@Test func bomCRLFAndInvalidUTF8Map() {
    let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("[1,\r\n".utf8) + [0xFF] + Array(",2]".utf8)
    let d = SourceDocument(bytes: bytes)
    #expect(d.lineCount == 2)
    let two = ByteOffset(value: bytes.count - 2)
    let ns = d.text as NSString
    #expect(ns.substring(with: NSRange(location: d.utf16Offset(of: two).value, length: 1)) == "2")
    #expect(d.lineColumn(of: two) == (2, 3))  // U+FFFD counts as one column
}

@Test func checkpointsHoldOnOneHugeLine() {
    let line = String(repeating: "\"é\",", count: 200_000)  // ~1 MB, no newline
    let d = SourceDocument(bytes: Array("[\(line)0]".utf8))
    let probe = ByteOffset(value: 1 + 5 * 150_000)
    #expect(d.utf16Offset(of: probe).value == 1 + 4 * 150_000)
}

@Test func sliceReturnsOriginalText() {
    let d = SourceDocument(bytes: Array("[\"ä\"]".utf8))
    #expect(d.slice(ByteOffset(value: 1)..<ByteOffset(value: 5)) == "\"ä\"")
}

@Test func batchUTF16OffsetsMatchSingleConversions() {
    let s = "[" + Array(repeating: "\"é😀\\\"\"", count: 3000).joined(separator: ",\n") + "]"
    let d = SourceDocument(bytes: Array(s.utf8))
    let probes = stride(from: 0, to: s.utf8.count, by: 7).map { ByteOffset(value: $0) }
    #expect(d.utf16Offsets(ofSorted: probes) == probes.map { d.utf16Offset(of: $0) })
}

@Test func lineStartsAreByteOffsets() {
    let d = SourceDocument(bytes: Array("ä\n  b\r\n".utf8))
    #expect((0..<d.lineCount).map { d.lineStart($0) } == [0, 3, 8])  // "ä" is 2 bytes; the last \n is byte 7
}
