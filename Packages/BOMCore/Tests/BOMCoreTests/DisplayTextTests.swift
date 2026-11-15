import Foundation
import Testing
@testable import BOMCore

@Test func displayTextBreaksLongLinesAfterCommasOutsideStrings() {
    let s = "[" + Array(repeating: #""a,b""#, count: 2000).joined(separator: ",") + "]"  // one ~12 KB line
    let d = SourceDocument(bytes: Array(s.utf8))
    let dt = DisplayText(source: d, maxLineBytes: 1000)
    #expect(!dt.breaks.isEmpty)
    #expect(dt.string.replacingOccurrences(of: "\n", with: "") == s)
    let u = Array(s.utf16)
    for b in dt.breaks {
        #expect(u[b.value - 1] == UInt16(UInt8(ascii: ",")))
        #expect(u[b.value] == UInt16(UInt8(ascii: "\"")))  // the comma between elements, not inside "a,b"
    }
    #expect(dt.string.split(separator: "\n").allSatisfy { $0.utf8.count <= 1000 + 8 })
}

@Test func displayOffsetsRoundTripAndRangesKeepSourceText() {
    let s = "[" + Array(repeating: #""é😀""#, count: 3000).joined(separator: ",") + "]"
    let d = SourceDocument(bytes: Array(s.utf8))
    let dt = DisplayText(source: d, maxLineBytes: 500)
    for u in stride(from: 0, to: s.utf16.count, by: 37) {
        #expect(dt.sourceOffset(dt.displayOffset(UTF16Offset(value: u))) == UTF16Offset(value: u))
    }
    let r = ByteOffset(value: 478)..<ByteOffset(value: 1297)  // element starts (1 + 9k): scalar-aligned
    let nr = dt.displayRange(r)
    #expect((dt.string as NSString).substring(with: nr).replacingOccurrences(of: "\n", with: "") == d.slice(r))
    #expect(dt.byteRange(nr) == r)
}

@Test func displayTextLeavesOrdinaryFilesUntouched() {
    let s = "{\n  \"a\": [1, 2]\n}"
    let d = SourceDocument(bytes: Array(s.utf8))
    let dt = DisplayText(source: d, maxLineBytes: 1000)
    #expect(dt.breaks.isEmpty && dt.string == s)
    #expect(dt.displayRange(ByteOffset(value: 4)..<ByteOffset(value: 7)) == NSRange(location: 4, length: 3))
}
