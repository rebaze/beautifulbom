/// A parsed JSON document: a flat arena of nodes with byte ranges into `source`.
/// Nothing in the tree is a copy of the source; every text comes from a range.
public struct JSONTree: Sendable {
    public let source: SourceDocument
    public internal(set) var root: NodeID?
    public internal(set) var diagnostics: [Diagnostic] = []

    // Struct-of-arrays storage, indexed by NodeID.rawValue. -1 means none.
    var kinds: [NodeKind] = []
    var parents: [Int32] = []
    var firstChildren: [Int32] = []
    var nextSiblings: [Int32] = []
    var childCounts: [Int32] = []
    var depths: [Int32] = []
    var indexes: [Int32] = []
    var keyStarts: [Int32] = []
    var keyEnds: [Int32] = []
    var valueStarts: [Int32] = []
    var valueEnds: [Int32] = []
    /// Members whose key occurs more than once in the same object (all occurrences).
    var duplicateKeyNodes: Set<Int32> = []

    init(source: SourceDocument) { self.source = source }

    public var nodeCount: Int { kinds.count }

    public func kind(_ n: NodeID) -> NodeKind { kinds[n.index] }

    public func parent(_ n: NodeID) -> NodeID? {
        let p = parents[n.index]
        return p < 0 ? nil : NodeID(rawValue: p)
    }

    public func childCount(_ n: NodeID) -> Int { Int(childCounts[n.index]) }

    public func children(_ n: NodeID) -> [NodeID] {
        var out: [NodeID] = []
        out.reserveCapacity(childCount(n))
        var c = firstChildren[n.index]
        while c >= 0 {
            out.append(NodeID(rawValue: c))
            c = nextSiblings[Int(c)]
        }
        return out
    }

    public func depth(_ n: NodeID) -> Int { Int(depths[n.index]) }

    /// Position among the parent's children (array index for array elements).
    public func indexInParent(_ n: NodeID) -> Int { Int(indexes[n.index]) }

    /// The member key including its quotes; nil for array elements and the root.
    public func keyRange(_ n: NodeID) -> Range<ByteOffset>? {
        let s = keyStarts[n.index]
        return s < 0 ? nil : ByteOffset(value: Int(s))..<ByteOffset(value: Int(keyEnds[n.index]))
    }

    public func valueRange(_ n: NodeID) -> Range<ByteOffset> {
        ByteOffset(value: Int(valueStarts[n.index]))..<ByteOffset(value: Int(valueEnds[n.index]))
    }

    /// From the key (if any) to the end of the value.
    public func fullRange(_ n: NodeID) -> Range<ByteOffset> {
        let k = keyStarts[n.index]
        let start = k >= 0 ? Int(k) : Int(valueStarts[n.index])
        return ByteOffset(value: start)..<ByteOffset(value: Int(valueEnds[n.index]))
    }

    func start(_ i: Int) -> Int {
        let k = keyStarts[i]
        return k >= 0 ? Int(k) : Int(valueStarts[i])
    }
}
