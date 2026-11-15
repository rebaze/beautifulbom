/// Identity of a node: its index in the tree's arena. Nodes are stored in
/// pre-order, so ascending IDs have ascending start offsets.
public struct NodeID: Hashable, Comparable, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static func < (a: NodeID, b: NodeID) -> Bool { a.rawValue < b.rawValue }
    var index: Int { Int(rawValue) }
}

public enum NodeKind: UInt8, Sendable {
    case object, array, string, number, bool, null, invalid
}

public struct Diagnostic: Sendable, Hashable {
    public enum Severity: Sendable, Hashable { case error, warning }
    public let severity: Severity
    public let range: Range<ByteOffset>
    public let message: String

    public init(severity: Severity, range: Range<ByteOffset>, message: String) {
        self.severity = severity
        self.range = range
        self.message = message
    }
}
