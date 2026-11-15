import Testing
@testable import BOMCore

@Test func lexerKinds() {
    let s = #"{"k": "v", "n": -1.5e3, "t": true, "z": null}"#
    let d = SourceDocument(bytes: Array(s.utf8))
    let kinds = lex(d, from: ByteOffset(value: 0), to: ByteOffset(value: s.utf8.count)).map(\.kind)
    #expect(kinds == [.punctuation, .key, .punctuation, .string, .punctuation,
                      .key, .punctuation, .number, .punctuation,
                      .key, .punctuation, .literal, .punctuation,
                      .key, .punctuation, .literal, .punctuation])
}

@Test func lexerStopsAtEndAndMarksInvalidAndComments() {
    let s = "[tru, // c\n \"a\\\"b\", 1]"
    let d = SourceDocument(bytes: Array(s.utf8))
    let toks = lex(d, from: ByteOffset(value: 0), to: ByteOffset(value: 13))
    #expect(toks.map(\.kind) == [.punctuation, .invalid, .punctuation, .comment, .string])
    #expect(d.slice(toks[4].range) == #""a\"b""#)
}
