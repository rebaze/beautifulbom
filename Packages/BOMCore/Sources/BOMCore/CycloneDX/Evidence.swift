/// A value and the node it was read from.
public struct Located<Value: Sendable & Hashable>: Sendable, Hashable {
    public let value: Value
    public let node: NodeID
    public init(_ value: Value, node: NodeID) {
        self.value = value
        self.node = node
    }
}

/// A key an object does not have, and where it would go: just after the
/// object's opening brace. The evidence drawer marks that place.
public struct Absent: Sendable, Hashable {
    public let parent: NodeID
    public let key: String
    public let insertion: ByteOffset

    public init(parent: NodeID, key: String, in tree: JSONTree) {
        self.parent = parent
        self.key = key
        insertion = ByteOffset(value: min(tree.valueRange(parent).lowerBound.value + 1, tree.source.bytes.count))
    }
}

/// What backs a statement in a view: a node in the source, or an absent key.
public enum Evidence: Sendable, Hashable {
    case located(NodeID)
    case absent(Absent)
}

extension JSONTree {
    /// The member `key` of `object` as evidence, or its absence.
    public func evidence(_ object: NodeID, _ key: String) -> Evidence {
        if let m = member(object, key) { return .located(m) }
        return .absent(Absent(parent: object, key: key, in: self))
    }
}
