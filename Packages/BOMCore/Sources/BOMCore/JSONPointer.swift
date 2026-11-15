/// An RFC 6901 JSON Pointer for display and copying. Not an identity: a pointer
/// can match several nodes when an object repeats a key, which `occurrence`
/// and `occurrences` make explicit. Code addresses nodes by `NodeID`.
public struct JSONPointer: Sendable, Hashable, CustomStringConvertible {
    public let tokens: [String]
    /// 1-based occurrence of this node's key among equal keys in its object; nil if unique.
    public let occurrence: Int?
    public let occurrences: Int?

    public init(tokens: [String], occurrence: Int? = nil, occurrences: Int? = nil) {
        self.tokens = tokens
        self.occurrence = occurrence
        self.occurrences = occurrences
    }

    /// The RFC 6901 string: `~` → `~0`, `/` → `~1`; the root is "".
    public var description: String {
        tokens.map { "/" + $0.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }.joined()
    }

    public var displayString: String {
        guard let occurrence, let occurrences else { return description }
        return "\(description) (duplicate \(occurrence) of \(occurrences))"
    }
}

extension JSONTree {
    /// The decoded member key; nil for array elements and the root.
    public func key(_ n: NodeID) -> String? {
        let s = keyStarts[n.index]
        guard s >= 0 else { return nil }
        return decodeJSONString(source.bytes, Int(s)..<Int(keyEnds[n.index]))
    }

    /// Ancestors from the root down to the parent; excludes `n`.
    public func ancestors(_ n: NodeID) -> [NodeID] {
        var out: [NodeID] = []
        var p = parents[n.index]
        while p >= 0 {
            out.append(NodeID(rawValue: p))
            p = parents[Int(p)]
        }
        return out.reversed()
    }

    public func pointer(_ n: NodeID) -> JSONPointer {
        var tokens: [String] = []
        var c = n
        while let p = parent(c) {
            tokens.append(kind(p) == .object ? (key(c) ?? "") : String(indexInParent(c)))
            c = p
        }
        tokens.reverse()
        guard duplicateKeyNodes.contains(n.rawValue), let p = parent(n), let k = key(n) else {
            return JSONPointer(tokens: tokens)
        }
        let same = children(p).filter { duplicateKeyNodes.contains($0.rawValue) && key($0) == k }
        return JSONPointer(tokens: tokens, occurrence: (same.firstIndex(of: n) ?? 0) + 1, occurrences: same.count)
    }

    /// Strings unescaped; numbers, booleans and null as written; containers and
    /// invalid values as their original source text.
    public func decodedValue(_ n: NodeID) -> String {
        let r = valueRange(n)
        if kind(n) == .string { return decodeJSONString(source.bytes, r.lowerBound.value..<r.upperBound.value) }
        return source.slice(r)
    }

    /// The deepest node whose `fullRange` contains `offset`, or nil.
    public func node(at offset: ByteOffset) -> NodeID? {
        guard let i = lastNode(startingAtOrBefore: offset.value) else { return nil }
        var c: Int32 = Int32(i)
        while c >= 0 {
            let id = NodeID(rawValue: c)
            if fullRange(id).contains(offset) { return id }
            c = parents[Int(c)]
        }
        return nil
    }

    /// A byte offset at or before `offset` where lexing can safely start
    /// (never inside a string): the start of the last node starting there or earlier.
    public func lexStart(atOrBefore offset: ByteOffset) -> ByteOffset {
        guard let i = lastNode(startingAtOrBefore: offset.value) else { return ByteOffset(value: 0) }
        return ByteOffset(value: start(i))
    }

    /// Binary search over node starts, which ascend in pre-order.
    func lastNode(startingAtOrBefore offset: Int) -> Int? {
        guard nodeCount > 0, start(0) <= offset else { return nil }
        var lo = 0, hi = nodeCount - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if start(mid) <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}

extension JSONTree {
    /// The node an RFC 6901 pointer string names; with duplicate keys, the first
    /// occurrence. For launch arguments and links, never as a node identity.
    public func resolve(pointer: String) -> NodeID? {
        guard var current = root else { return nil }
        if pointer.isEmpty { return current }
        guard pointer.hasPrefix("/") else { return nil }
        for raw in pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            let token = raw.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            let kids = children(current)
            switch kind(current) {
            case .object:
                guard let next = kids.first(where: { key($0) == token }) else { return nil }
                current = next
            case .array:
                guard let i = Int(token), kids.indices.contains(i) else { return nil }
                current = kids[i]
            default:
                return nil
            }
        }
        return current
    }
}
