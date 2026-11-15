import Testing
@testable import BOMCore

func tree(_ s: String) -> JSONTree { parseJSON(SourceDocument(bytes: Array(s.utf8))) }
func src(_ t: JSONTree, _ r: Range<ByteOffset>) -> String { t.source.slice(r) }

@Test func rangesAreExact() {
    let t = tree(#"{ "a" : [1, {"b": "x\"y"}], "c": null }"#)
    let root = t.root!
    #expect(t.kind(root) == .object && t.childCount(root) == 2)
    let a = t.children(root)[0]
    #expect(src(t, t.keyRange(a)!) == #""a""#)
    #expect(src(t, t.valueRange(a)) == #"[1, {"b": "x\"y"}]"#)
    #expect(src(t, t.fullRange(a)) == #""a" : [1, {"b": "x\"y"}]"#)
    let b = t.children(t.children(a)[1])[0]
    #expect(src(t, t.valueRange(b)) == #""x\"y""#)
    #expect(t.depth(b) == 3 && t.indexInParent(b) == 0)
    #expect(t.parent(b) == t.children(a)[1])
    #expect(t.kind(t.children(root)[1]) == .null)
    #expect(t.diagnostics.isEmpty)
}

@Test func scalarKinds() {
    let t = tree(#"[true, false, -0.5e+2, "s", null, {}, []]"#)
    #expect(t.children(t.root!).map { t.kind($0) } == [.bool, .bool, .number, .string, .null, .object, .array])
    #expect(t.diagnostics.isEmpty)
}

@Test func repeatedValuesAreDistinctNodes() {
    let t = tree(#"["x","x","x"]"#)
    let ranges = t.children(t.root!).map { t.valueRange($0).lowerBound.value }
    #expect(ranges == [1, 5, 9])
}

@Test func duplicateKeysKeptAndWarned() {
    let t = tree(#"{"name":"a","name":"b"}"#)
    #expect(t.childCount(t.root!) == 2)
    #expect(t.diagnostics.map(\.severity) == [.warning])
    #expect(t.diagnostics[0].message.contains("Duplicate key \"name\""))
}

@Test func malformedKeepsWhatParsed() {
    let t = tree("{\"a\": 1, \"b\": tru, \"c\": [2, 3}")
    #expect(t.childCount(t.root!) == 3)
    #expect(t.kind(t.children(t.root!)[1]) == .invalid)
    #expect(t.diagnostics.filter { $0.severity == .error }.count >= 2)  // bad literal, mismatched bracket
    #expect(t.diagnostics.allSatisfy { !$0.message.isEmpty })
}

@Test func unclosedContainersEndAtEOF() {
    let s = "{\"a\": [1, 2"
    let t = tree(s)
    #expect(t.valueRange(t.root!).upperBound.value == s.utf8.count)
    #expect(t.diagnostics.contains { $0.message.contains("Unclosed array") && $0.message.contains("line 1") })
}

@Test func degenerateInputsYieldDiagnostics() {
    for input in ["", "   \n", "%PDF-1.7\n\u{1}\u{2}"] {
        let t = tree(input)
        #expect(t.diagnostics.contains { $0.severity == .error })
    }
    #expect(tree("").root == nil)
}

@Test func bomAndTrailingContent() {
    var bytes: [UInt8] = [0xEF, 0xBB, 0xBF]
    bytes += Array("[1] [2]".utf8)
    let t = parseJSON(SourceDocument(bytes: bytes))
    #expect(t.valueRange(t.root!).lowerBound.value == 3)
    #expect(t.diagnostics.map(\.severity) == [.warning, .error])  // byte order mark; content after root
}

@Test func deepNestingDoesNotOverflow() {
    let n = 100_000
    let t = tree(String(repeating: "[", count: n) + String(repeating: "]", count: n))
    #expect(t.nodeCount == n && t.diagnostics.isEmpty)
    #expect(t.depth(NodeID(rawValue: Int32(n - 1))) == n - 1)
}

@Test func unterminatedStringEndsAtLineEnd() {
    let t = tree("{\"a\": \"open\n, \"b\": 2}")
    #expect(src(t, t.valueRange(t.children(t.root!)[0])) == "\"open")
    #expect(t.diagnostics.contains { $0.message.contains("Unterminated string") })
    #expect(t.childCount(t.root!) == 2)
}

@Test func commentsAndTrailingCommasAreReportedAndSkipped() {
    let t = tree("{\n // note\n \"a\": [1, 2,], /* x */ \"b\": 3,\n}")
    #expect(t.childCount(t.root!) == 2)
    #expect(t.children(t.children(t.root!)[0]).count == 2)
    #expect(t.diagnostics.filter { $0.message.contains("Comment") }.count == 2)
    #expect(t.diagnostics.filter { $0.message.contains("Trailing comma") }.count == 2)
}
