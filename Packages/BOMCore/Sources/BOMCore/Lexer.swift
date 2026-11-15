public enum TokenKind: Sendable { case key, string, number, literal, punctuation, comment, invalid }

public struct Token: Sendable, Hashable {
    public let kind: TokenKind
    public let range: Range<ByteOffset>
}

/// Tokens for syntax colouring, starting at `from` (which must be outside a
/// string, e.g. `JSONTree.lexStart(atOrBefore:)`) and up to the first token
/// starting at or after `to`. Independent of the tree, so it also colours
/// regions the parser had to skip.
public func lex(_ source: SourceDocument, from: ByteOffset, to: ByteOffset) -> [Token] {
    let b = source.bytes
    var out: [Token] = []
    var i = max(0, from.value)
    let end = min(to.value, b.count)
    func add(_ k: TokenKind, _ s: Int, _ e: Int) {
        out.append(Token(kind: k, range: ByteOffset(value: s)..<ByteOffset(value: e)))
    }
    while i < end {
        let c = b[i]
        switch c {
        case 0x20, 0x09, 0x0A, 0x0D:
            i += 1
        case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: ":"), UInt8(ascii: ","):
            add(.punctuation, i, i + 1)
            i += 1
        case UInt8(ascii: "/") where i + 1 < b.count && (b[i + 1] == UInt8(ascii: "/") || b[i + 1] == UInt8(ascii: "*")):
            let s = i
            if b[i + 1] == UInt8(ascii: "/") {
                while i < b.count && b[i] != 0x0A { i += 1 }
            } else {
                i += 2
                while i < b.count && !(b[i] == UInt8(ascii: "*") && i + 1 < b.count && b[i + 1] == UInt8(ascii: "/")) { i += 1 }
                i = min(i + 2, b.count)
            }
            add(.comment, s, i)
        case UInt8(ascii: "\""):
            let s = i
            i += 1
            while i < b.count && b[i] != UInt8(ascii: "\"") && b[i] != 0x0A && b[i] != 0x0D {
                i += b[i] == UInt8(ascii: "\\") ? 2 : 1
            }
            if i < b.count && b[i] == UInt8(ascii: "\"") { i += 1 }
            i = min(i, b.count)
            var j = i
            while j < b.count && (b[j] == 0x20 || b[j] == 0x09 || b[j] == 0x0A || b[j] == 0x0D) { j += 1 }
            add(j < b.count && b[j] == UInt8(ascii: ":") ? .key : .string, s, i)
        default:
            let s = i
            loop: while i < b.count {
                switch b[i] {
                case 0x20, 0x09, 0x0A, 0x0D, UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["),
                     UInt8(ascii: "]"), UInt8(ascii: ":"), UInt8(ascii: ","), UInt8(ascii: "\""):
                    break loop
                default: i += 1
                }
            }
            let w = b[s..<i]
            if w.elementsEqual("true".utf8) || w.elementsEqual("false".utf8) || w.elementsEqual("null".utf8) {
                add(.literal, s, i)
            } else {
                add(isValidNumber(w) ? .number : .invalid, s, i)
            }
        }
    }
    return out
}
