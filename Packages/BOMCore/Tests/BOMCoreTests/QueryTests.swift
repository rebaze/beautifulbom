import Testing
@testable import BOMCore

@Test func pointersEscapeAndMarkDuplicates() {
    let t = tree(#"{"a/b":{"m~n":[0,{"k":1}]},"d":1,"d":2}"#)
    let k = t.children(t.children(t.children(t.children(t.root!)[0])[0])[1])[0]
    #expect(t.pointer(k).description == "/a~1b/m~0n/1/k")
    let d2 = t.children(t.root!)[2]
    #expect(t.pointer(d2).description == "/d")
    #expect(t.pointer(d2).displayString == "/d (duplicate 2 of 2)")
    #expect(t.pointer(t.children(t.root!)[1]).occurrence == 1)
    #expect(t.pointer(t.children(t.root!)[0]).occurrence == nil)
    #expect(t.pointer(t.root!).description == "")
}

@Test func unicodeEscapedKeysDecode() {
    let t = tree(#"{"ä😀":"\n\"x"}"#)
    let n = t.children(t.root!)[0]
    #expect(t.key(n) == "ä😀")
    #expect(t.decodedValue(n) == "\n\"x")
    #expect(t.pointer(n).description == "/ä😀")
}

@Test func decodedValuesByKind() {
    let t = tree(#"[-1.5e3, true, null, {"a": 1}, tru]"#)
    #expect(t.children(t.root!).map { t.decodedValue($0) } == ["-1.5e3", "true", "null", #"{"a": 1}"#, "tru"])
    #expect(t.key(t.children(t.root!)[0]) == nil)
}

@Test func nodeAtOffsetPicksDeepest() {
    let s = #"{"a": [10, 20]}"#
    let t = tree(s)
    let twenty = s.utf8.firstIndex(of: UInt8(ascii: "2"))!
    let n = t.node(at: ByteOffset(value: s.utf8.distance(from: s.utf8.startIndex, to: twenty)))!
    #expect(t.decodedValue(n) == "20")
    #expect(t.ancestors(n).count == 2)
    #expect(t.ancestors(n).first == t.root)
    #expect(t.node(at: ByteOffset(value: 2)) == t.children(t.root!)[0])  // on the key -> member node
    #expect(t.node(at: ByteOffset(value: 9)) == t.children(t.root!)[0])  // between elements -> the array
    #expect(t.node(at: ByteOffset(value: 100)) == nil)
}

@Test func lexStartIsNearOffsetInMinifiedInput() {
    let s = "[" + Array(repeating: #"{"name":"x","v":1}"#, count: 50_000).joined(separator: ",") + "]"
    let t = tree(s)
    let probe = ByteOffset(value: s.utf8.count / 2)
    let start = t.lexStart(atOrBefore: probe)
    #expect(start <= probe && probe.value - start.value < 32)
}

@Test func resolvePointerFindsFirstOccurrence() {
    let t = tree(#"{"a/b":{"m~n":[0,{"k":1}]},"d":1,"d":2}"#)
    let k = t.resolve(pointer: "/a~1b/m~0n/1/k")
    #expect(k != nil && t.decodedValue(k!) == "1" && t.key(k!) == "k")
    #expect(t.resolve(pointer: "/d") == t.children(t.root!)[1])
    #expect(t.resolve(pointer: "") == t.root)
    #expect(t.resolve(pointer: "/nope") == nil)
    #expect(t.resolve(pointer: "/a~1b/m~0n/9") == nil)
}
