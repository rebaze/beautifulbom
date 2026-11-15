import Foundation
import Testing
@testable import BOMCore

// Final review findings, each pinned by the input that triggered it.

@Test func diagnosticsAreCappedWithASummary() {
    let s = "[\n" + String(repeating: "// c\n", count: 5000) + "1]"
    let t = tree(s)
    #expect(t.diagnostics.count == JSONTree.maxDiagnostics + 1)
    #expect(t.diagnostics.last!.message.contains("4000 more"))
    #expect(t.unlistedDiagnostics == 4000)
}

@Test func recoveryRehandlesTheBracketItStoppedAt() {
    let t = tree(#"{"a": [{x]}, "b": 1}"#)
    let a = t.children(t.root!)[0]
    #expect(t.kind(a) == .array && t.childCount(a) == 1)
    let object = t.children(a)[0]
    #expect(t.kind(object) == .object && t.childCount(object) == 0)
    #expect(src(t, t.valueRange(object)) == "{x")
    #expect(t.nodeCount == 3)  // no phantom node for x
}

@Test func missingValueDoesNotSwallowTheNextKey() {
    let t = tree(#"{"a":,"b":1}"#)
    let kids = t.children(t.root!)
    #expect(kids.count == 2)
    #expect(t.kind(kids[0]) == .invalid && t.valueRange(kids[0]).isEmpty)
    #expect(t.key(kids[1]) == "b" && t.decodedValue(kids[1]) == "1")
    let arr = tree("[1,,2]")
    #expect(arr.children(arr.root!).map { arr.kind($0) } == [.number, .invalid, .number])
}

@Test func longStringsAndCommaFreeRunsGetDisplayBreaks() {
    for s in [#"{"data":""# + String(repeating: "A", count: 30_000) + #""}"#,
              #"[""# + String(repeating: "日", count: 10_000) + #""]"#,
              String(repeating: #"{"a":"#, count: 5_000) + "1" + String(repeating: "}", count: 5_000)] {
        let dt = DisplayText(source: SourceDocument(bytes: Array(s.utf8)), maxLineBytes: 1000)
        #expect(!dt.breaks.isEmpty)
        #expect(dt.string.replacingOccurrences(of: "\n", with: "") == s)
        #expect(dt.string.split(separator: "\n").allSatisfy { $0.utf8.count <= 2000 + 4 })
    }
}

@Test func lexStartStaysNearAfterUnparsedContent() {
    let s = "[1]]" + Array(repeating: #"{"name":"x","v":1}"#, count: 50_000).joined(separator: ",")
    let d = SourceDocument(bytes: Array(s.utf8))
    let dt = DisplayText(source: d)
    let probe = ByteOffset(value: s.utf8.count - 100)
    #expect(parseJSON(d).lexStart(atOrBefore: probe).value < 10)  // the tree stops after the root
    let start = dt.lexStart(atOrBefore: probe)
    #expect(start <= probe && probe.value - start.value < 2 * 4096)
    let kinds = lex(d, from: start, to: probe).map(\.kind)
    #expect(!kinds.contains(.invalid))  // starts outside a string
}

@Test func invalidUTF8IsReported() {
    let bytes = Array(#"{"n":"M"#.utf8) + [0xFC] + Array(#"ller", "m":"x"#.utf8) + [0xC3] + Array(#""}"#.utf8)
    let t = parseJSON(SourceDocument(bytes: bytes))
    let w = t.diagnostics.filter { $0.message.contains("UTF-8") }
    #expect(w.count == 2 && w.allSatisfy { $0.severity == .warning })
    #expect(w[0].range == ByteOffset(value: 7)..<ByteOffset(value: 8))
}
