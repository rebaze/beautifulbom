import Testing
@testable import BOMCore

@Suite struct TreeAccessTests {
    @Test func memberReturnsLastDuplicate() {
        let t = tree(#"{"a":1,"a":"x"}"#)
        #expect(t.string(t.member(t.root!, "a")) == "x")
    }

    @Test func memberOnArrayIsNil() {
        let t = tree("[1]")
        #expect(t.member(t.root!, "a") == nil)
    }

    @Test func stringOfNumberIsNil() {
        let t = tree(#"{"version":1.2}"#)
        #expect(t.memberString(t.root!, "version") == nil)
    }

    @Test func objectElementsSkipsNonObjects() {
        let t = tree(#"{"c":[{"n":1},"s",2,{"n":2}]}"#)
        #expect(t.objectElements(t.member(t.root!, "c")).count == 2)
        #expect(t.elements(t.member(t.root!, "c")).count == 4)
    }

    @Test func elementsOfObjectIsEmpty() {
        let t = tree(#"{"licenses":{}}"#)
        #expect(t.elements(t.member(t.root!, "licenses")).isEmpty)
    }

    @Test func decodesEscapes() {
        let t = tree(#"{"n":"aé\"b","key":1}"#)
        #expect(t.memberString(t.root!, "n") == "aé\"b")
        #expect(t.member(t.root!, "key") != nil)
        #expect(t.keys(t.root!) == ["n", "key"])
    }
}
