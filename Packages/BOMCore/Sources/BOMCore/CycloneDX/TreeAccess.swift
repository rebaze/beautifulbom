/// Reading values out of the tree. A value of the wrong shape reads as absent,
/// as in rio's field checks, so a malformed document gives findings, not traps.
extension JSONTree {
    /// The last member of `object` called `key` (Go's encoding/json keeps the
    /// last of duplicate keys, and the checks must agree with rio). Nil when
    /// `object` is not an object or has no such member.
    public func member(_ object: NodeID, _ key: String) -> NodeID? {
        guard kind(object) == .object else { return nil }
        let want = Array(key.utf8)
        var found: NodeID?
        var c = firstChildren[object.index]
        while c >= 0 {
            if keyEquals(Int(c), want) { found = NodeID(rawValue: c) }
            c = nextSiblings[Int(c)]
        }
        return found
    }

    /// Compares a member's key with `want`; raw bytes unless the key has escapes.
    private func keyEquals(_ i: Int, _ want: [UInt8]) -> Bool {
        let s = Int(keyStarts[i]), e = Int(keyEnds[i])
        guard s >= 0 else { return false }
        let bytes = source.bytes
        // Key range includes the quotes; an unterminated key has no closing quote.
        let lo = s + 1
        let hi = e > lo && bytes[e - 1] == UInt8(ascii: "\"") ? e - 1 : e
        var escaped = false
        if hi - lo == want.count {
            var equal = true
            for k in 0..<want.count {
                let b = bytes[lo + k]
                if b == UInt8(ascii: "\\") { escaped = true; break }
                if b != want[k] { equal = false; break }
            }
            if equal && !escaped { return true }
            if !escaped { return false }
        } else {
            escaped = bytes[lo..<hi].contains(UInt8(ascii: "\\"))
            if !escaped { return false }
        }
        return decodeJSONString(bytes, s..<e) == String(decoding: want, as: UTF8.self)
    }

    /// The decoded value of a string node; nil for any other node.
    public func string(_ n: NodeID?) -> String? {
        guard let n, kind(n) == .string else { return nil }
        return decodedValue(n)
    }

    public func memberString(_ object: NodeID, _ key: String) -> String? {
        string(member(object, key))
    }

    /// The elements of an array; empty for anything else.
    public func elements(_ n: NodeID?) -> [NodeID] {
        guard let n, kind(n) == .array else { return [] }
        return children(n)
    }

    /// The object elements of an array, skipping anything else.
    public func objectElements(_ n: NodeID?) -> [NodeID] {
        elements(n).filter { kind($0) == .object }
    }

    /// Member keys in document order, duplicates kept.
    public func keys(_ object: NodeID) -> [String] {
        guard kind(object) == .object else { return [] }
        return children(object).compactMap { key($0) }
    }
}
