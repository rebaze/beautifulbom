/// Parses `source` into a `JSONTree`. Never fails: malformed input yields
/// diagnostics and every node that could be recovered. Iterative, so nesting
/// depth is limited by memory, not by the call stack. Safe to call off the main thread.
public func parseJSON(_ source: SourceDocument) -> JSONTree {
    var parser = Parser(source: source)
    parser.run()
    return parser.tree
}

private struct Token {
    enum Kind { case beginObject, endObject, beginArray, endArray, colon, comma, string, word, eof }
    var kind: Kind
    var start: Int
    var end: Int
}

private struct Frame {
    let node: Int32
    let isObject: Bool
    let openOffset: Int
    var lastChild: Int32 = -1
    var count: Int32 = 0
    var keys: [String: Int] = [:]  // decoded key -> byte offset of first occurrence
}

private enum Expect {
    case value          // root, after ':' , after ',' in an array
    case valueOrEnd     // after '['
    case keyOrEnd       // after '{'
    case key            // after ',' in an object
    case colon
    case commaOrEnd
}

private struct Parser {
    let source: SourceDocument
    let bytes: [UInt8]
    var tree: JSONTree
    var pos = 0
    var stack: [Frame] = []
    var expect = Expect.value
    var afterComma = false
    var pendingKey: (start: Int, end: Int)?
    var rootDone = false

    init(source: SourceDocument) {
        self.source = source
        self.bytes = source.bytes
        self.tree = JSONTree(source: source)
    }

    mutating func run() {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            warn(0, 3, "Byte order mark at the start of the file (ignored)")
            pos = 3
        }
        var tok = nextToken()
        while tok.kind != .eof {
            if rootDone {
                error(tok.start, bytes.count, "Unexpected content after the JSON value (not parsed)")
                break
            }
            if !handle(tok) { tok = nextToken() }
        }
        while let frame = stack.popLast() {
            let (l, c) = source.lineColumn(of: ByteOffset(value: frame.openOffset))
            error(frame.openOffset, frame.openOffset + 1,
                  "Unclosed \(frame.isObject ? "object" : "array") opened at line \(l), column \(c)")
            tree.valueEnds[Int(frame.node)] = Int32(bytes.count)
            tree.childCounts[Int(frame.node)] = frame.count
        }
        if tree.root == nil && tree.diagnostics.allSatisfy({ $0.severity != .error }) {
            error(0, bytes.count, "The file contains no JSON value")
        }
        tree.diagnostics.sort { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Handles one token. Returns true if the same token must be handled again
    /// (after a state change), false if it was consumed.
    mutating func handle(_ tok: Token) -> Bool {
        switch expect {
        case .value, .valueOrEnd:
            if beginValue(tok) { return false }
            if tok.kind == .endArray, let top = stack.last, !top.isObject, expect == .valueOrEnd || afterComma {
                if afterComma { error(tok.start, tok.end, "Trailing comma before ']'") }
                close(at: tok.start, end: tok.end)
                return false
            }
            if tok.kind == .endObject || tok.kind == .endArray, !stack.isEmpty {
                error(tok.start, tok.end, "Expected a value before '\(char(tok))'")
                if pendingKey != nil { addLeaf(.invalid, tok.start, tok.start) }
                expect = .commaOrEnd
                return true
            }
            error(tok.start, tok.end, "Expected a value, found '\(text(tok))'")
            return false
        case .keyOrEnd, .key:
            if tok.kind == .string {
                pendingKey = (tok.start, tok.end)
                expect = .colon
                return false
            }
            if tok.kind == .endObject {
                if expect == .key { error(tok.start, tok.end, "Trailing comma before '}'") }
                close(at: tok.start, end: tok.end)
                return false
            }
            return recover(tok, "Expected a quoted key, found '\(text(tok))'")
        case .colon:
            if tok.kind == .colon { expect = .value; afterComma = false; return false }
            error(tok.start, tok.end, "Expected ':' after the key")
            if isValueStart(tok) { expect = .value; return true }
            pendingKey = nil
            return recover(tok, nil)
        case .commaOrEnd:
            guard let top = stack.last else { return false }
            switch tok.kind {
            case .comma:
                expect = top.isObject ? .key : .value
                afterComma = true
                return false
            case .endObject, .endArray:
                let matches = (tok.kind == .endObject) == top.isObject
                if matches {
                    close(at: tok.start, end: tok.end)
                    return false
                }
                error(tok.start, tok.end,
                      "Expected '\(top.isObject ? "}" : "]")' but found '\(char(tok))'; the \(top.isObject ? "object" : "array") ends here")
                close(at: tok.start, end: tok.start)
                return !stack.isEmpty  // match the bracket against the next container out
            default:
                if top.isObject && tok.kind == .string {
                    error(tok.start, tok.end, "Expected ',' or '}' before the next key")
                    expect = .key
                    return true
                }
                if !top.isObject && isValueStart(tok) {
                    error(tok.start, tok.end, "Expected ',' or ']' before the next value")
                    expect = .value
                    return true
                }
                return recover(tok, "Expected ',' or '\(top.isObject ? "}" : "]")', found '\(text(tok))'")
            }
        }
    }

    /// Skips tokens to the next ',' or closing bracket at this depth.
    mutating func recover(_ tok: Token, _ message: String?) -> Bool {
        if let message { error(tok.start, tok.end, message) }
        var t = tok
        var depth = 0
        while t.kind != .eof {
            switch t.kind {
            case .beginObject, .beginArray: depth += 1
            case .endObject, .endArray:
                if depth == 0 { expect = .commaOrEnd; return handle(t) }
                depth -= 1
            case .comma where depth == 0:
                if let top = stack.last { expect = top.isObject ? .key : .value; afterComma = true }
                return false
            default: break
            }
            t = nextToken()
        }
        expect = .commaOrEnd
        return false
    }

    func isValueStart(_ tok: Token) -> Bool {
        tok.kind == .beginObject || tok.kind == .beginArray || tok.kind == .string || tok.kind == .word
    }

    mutating func beginValue(_ tok: Token) -> Bool {
        switch tok.kind {
        case .beginObject, .beginArray:
            let isObject = tok.kind == .beginObject
            let id = addNode(isObject ? .object : .array, tok.start, tok.end)
            stack.append(Frame(node: id, isObject: isObject, openOffset: tok.start))
            expect = isObject ? .keyOrEnd : .valueOrEnd
            afterComma = false
        case .string:
            addLeaf(.string, tok.start, tok.end)
        case .word:
            addLeaf(classify(tok), tok.start, tok.end)
        default:
            return false
        }
        return true
    }

    mutating func addLeaf(_ kind: NodeKind, _ start: Int, _ end: Int) {
        _ = addNode(kind, start, end)
        afterValue()
    }

    mutating func afterValue() {
        afterComma = false
        if stack.isEmpty { rootDone = true } else { expect = .commaOrEnd }
    }

    mutating func close(at start: Int, end: Int) {
        let frame = stack.removeLast()
        tree.valueEnds[Int(frame.node)] = Int32(end)
        tree.childCounts[Int(frame.node)] = frame.count
        afterValue()
    }

    mutating func addNode(_ kind: NodeKind, _ start: Int, _ end: Int) -> Int32 {
        let id = Int32(tree.kinds.count)
        tree.kinds.append(kind)
        tree.firstChildren.append(-1)
        tree.nextSiblings.append(-1)
        tree.childCounts.append(0)
        tree.valueStarts.append(Int32(start))
        tree.valueEnds.append(Int32(end))
        if stack.isEmpty {
            tree.root = NodeID(rawValue: id)
            tree.parents.append(-1)
            tree.depths.append(0)
            tree.indexes.append(0)
            tree.keyStarts.append(-1)
            tree.keyEnds.append(-1)
        } else {
            var frame = stack.removeLast()
            tree.parents.append(frame.node)
            tree.depths.append(Int32(stack.count + 1))
            tree.indexes.append(frame.count)
            if frame.lastChild >= 0 {
                tree.nextSiblings[Int(frame.lastChild)] = id
            } else {
                tree.firstChildren[Int(frame.node)] = id
            }
            frame.lastChild = id
            frame.count += 1
            if frame.isObject, let key = pendingKey {
                tree.keyStarts.append(Int32(key.start))
                tree.keyEnds.append(Int32(key.end))
                let decoded = decodeJSONString(bytes, key.start..<key.end)
                if let first = frame.keys[decoded] {
                    let (l, c) = source.lineColumn(of: ByteOffset(value: first))
                    warn(key.start, key.end, "Duplicate key \"\(decoded)\" (first at line \(l), column \(c))")
                } else {
                    frame.keys[decoded] = key.start
                }
            } else {
                tree.keyStarts.append(-1)
                tree.keyEnds.append(-1)
            }
            pendingKey = nil
            stack.append(frame)
        }
        return id
    }

    mutating func classify(_ tok: Token) -> NodeKind {
        let w = bytes[tok.start..<tok.end]
        if w.elementsEqual("true".utf8) || w.elementsEqual("false".utf8) { return .bool }
        if w.elementsEqual("null".utf8) { return .null }
        if isValidNumber(w) { return .number }
        let first = w.first!
        if first == UInt8(ascii: "-") || (0x30...0x39).contains(first) {
            error(tok.start, tok.end, "Invalid number '\(text(tok))'")
        } else {
            error(tok.start, tok.end, "Unexpected text '\(text(tok))'; expected a value such as true, false, null, a number or a string")
        }
        return .invalid
    }

    // MARK: Tokenizer

    mutating func nextToken() -> Token {
        while pos < bytes.count {
            let b = bytes[pos]
            switch b {
            case 0x20, 0x09, 0x0A, 0x0D:
                pos += 1
            case UInt8(ascii: "/") where pos + 1 < bytes.count && bytes[pos + 1] == UInt8(ascii: "/"):
                let s = pos
                while pos < bytes.count && bytes[pos] != 0x0A { pos += 1 }
                error(s, pos, "Comments are not allowed in JSON (skipped)")
            case UInt8(ascii: "/") where pos + 1 < bytes.count && bytes[pos + 1] == UInt8(ascii: "*"):
                let s = pos
                pos += 2
                while pos < bytes.count && !(bytes[pos] == UInt8(ascii: "*") && pos + 1 < bytes.count && bytes[pos + 1] == UInt8(ascii: "/")) { pos += 1 }
                pos = min(pos + 2, bytes.count)
                error(s, pos, "Comments are not allowed in JSON (skipped)")
            case UInt8(ascii: "{"): return single(.beginObject)
            case UInt8(ascii: "}"): return single(.endObject)
            case UInt8(ascii: "["): return single(.beginArray)
            case UInt8(ascii: "]"): return single(.endArray)
            case UInt8(ascii: ":"): return single(.colon)
            case UInt8(ascii: ","): return single(.comma)
            case UInt8(ascii: "\""): return string()
            default: return word()
            }
        }
        return Token(kind: .eof, start: bytes.count, end: bytes.count)
    }

    mutating func single(_ kind: Token.Kind) -> Token {
        pos += 1
        return Token(kind: kind, start: pos - 1, end: pos)
    }

    mutating func string() -> Token {
        let s = pos
        pos += 1
        while pos < bytes.count {
            let b = bytes[pos]
            if b == UInt8(ascii: "\"") {
                pos += 1
                return Token(kind: .string, start: s, end: pos)
            }
            if b == 0x0A || b == 0x0D {
                error(s, pos, "Unterminated string (a string must close on the same line)")
                return Token(kind: .string, start: s, end: pos)
            }
            if b == UInt8(ascii: "\\") {
                let e = pos
                pos += 1
                guard pos < bytes.count else { break }
                let c = bytes[pos]
                if c == UInt8(ascii: "u") {
                    let hex = bytes[min(pos + 1, bytes.count)..<min(pos + 5, bytes.count)]
                    if hex.count == 4 && hex.allSatisfy(isHex) {
                        pos += 5
                    } else {
                        error(e, min(pos + 1, bytes.count), "Invalid \\u escape (needs four hex digits)")
                        pos += 1
                    }
                    continue
                }
                if !"\"\\/bfnrt".utf8.contains(c) {
                    error(e, pos + 1, "Invalid escape '\\\(Character(Unicode.Scalar(c)))'")
                }
                pos += 1
                continue
            }
            if b < 0x20 {
                error(pos, pos + 1, "Control character in a string must be escaped")
            }
            pos += 1
        }
        error(s, bytes.count, "Unterminated string at the end of the file")
        return Token(kind: .string, start: s, end: bytes.count)
    }

    mutating func word() -> Token {
        let s = pos
        while pos < bytes.count {
            switch bytes[pos] {
            case 0x20, 0x09, 0x0A, 0x0D, UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["),
                 UInt8(ascii: "]"), UInt8(ascii: ":"), UInt8(ascii: ","), UInt8(ascii: "\""):
                return Token(kind: .word, start: s, end: pos)
            default:
                pos += 1
            }
        }
        return Token(kind: .word, start: s, end: pos)
    }

    // MARK: Diagnostics

    func text(_ tok: Token) -> String {
        if tok.kind == .eof { return "end of file" }
        let t = source.slice(ByteOffset(value: tok.start)..<ByteOffset(value: min(tok.end, tok.start + 40)))
        return tok.end - tok.start > 40 ? t + "…" : t
    }

    func char(_ tok: Token) -> String { text(tok) }

    mutating func error(_ s: Int, _ e: Int, _ message: String) {
        tree.diagnostics.append(Diagnostic(severity: .error, range: ByteOffset(value: s)..<ByteOffset(value: e), message: message))
    }

    mutating func warn(_ s: Int, _ e: Int, _ message: String) {
        tree.diagnostics.append(Diagnostic(severity: .warning, range: ByteOffset(value: s)..<ByteOffset(value: e), message: message))
    }
}

func isHex(_ b: UInt8) -> Bool {
    (0x30...0x39).contains(b) || (0x41...0x46).contains(b) || (0x61...0x66).contains(b)
}

/// RFC 8259 number grammar: -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
func isValidNumber(_ w: ArraySlice<UInt8>) -> Bool {
    var i = w.startIndex
    let end = w.endIndex
    func digit(_ i: Int) -> Bool { i < end && (0x30...0x39).contains(w[i]) }
    if i < end && w[i] == UInt8(ascii: "-") { i += 1 }
    guard digit(i) else { return false }
    if w[i] == 0x30 { i += 1 } else { while digit(i) { i += 1 } }
    if i < end && w[i] == UInt8(ascii: ".") {
        i += 1
        guard digit(i) else { return false }
        while digit(i) { i += 1 }
    }
    if i < end && (w[i] == UInt8(ascii: "e") || w[i] == UInt8(ascii: "E")) {
        i += 1
        if i < end && (w[i] == UInt8(ascii: "+") || w[i] == UInt8(ascii: "-")) { i += 1 }
        guard digit(i) else { return false }
        while digit(i) { i += 1 }
    }
    return i == end
}

/// Decodes a JSON string token (with or without its quotes, possibly
/// unterminated) into its value. Invalid escapes and lone surrogates become U+FFFD.
func decodeJSONString(_ bytes: [UInt8], _ range: Range<Int>) -> String {
    var lo = range.lowerBound, hi = range.upperBound
    if lo < hi && bytes[lo] == UInt8(ascii: "\"") { lo += 1 }
    if hi > lo && bytes[hi - 1] == UInt8(ascii: "\"") && (hi - 2 < lo || bytes[hi - 2] != UInt8(ascii: "\\")) { hi -= 1 }
    let slice = bytes[lo..<hi]
    if !slice.contains(UInt8(ascii: "\\")) { return String(decoding: slice, as: UTF8.self) }

    var out = String.UnicodeScalarView()
    var raw: [UInt8] = []
    func flush() {
        if !raw.isEmpty { out.append(contentsOf: String(decoding: raw, as: UTF8.self).unicodeScalars); raw.removeAll() }
    }
    func hex4(_ i: Int) -> UInt32? {
        guard i + 4 <= hi, bytes[i..<i + 4].allSatisfy(isHex) else { return nil }
        return UInt32(String(decoding: bytes[i..<i + 4], as: UTF8.self), radix: 16)
    }
    var i = lo
    while i < hi {
        let b = bytes[i]
        guard b == UInt8(ascii: "\\"), i + 1 < hi else { raw.append(b); i += 1; continue }
        flush()
        let c = bytes[i + 1]
        i += 2
        switch c {
        case UInt8(ascii: "\""): out.append("\"")
        case UInt8(ascii: "\\"): out.append("\\")
        case UInt8(ascii: "/"): out.append("/")
        case UInt8(ascii: "b"): out.append("\u{08}")
        case UInt8(ascii: "f"): out.append("\u{0C}")
        case UInt8(ascii: "n"): out.append("\n")
        case UInt8(ascii: "r"): out.append("\r")
        case UInt8(ascii: "t"): out.append("\t")
        case UInt8(ascii: "u"):
            guard let u = hex4(i) else { out.append("\u{FFFD}"); continue }
            i += 4
            if (0xD800...0xDBFF).contains(u), i + 6 <= hi, bytes[i] == UInt8(ascii: "\\"),
               bytes[i + 1] == UInt8(ascii: "u"), let low = hex4(i + 2), (0xDC00...0xDFFF).contains(low) {
                i += 6
                out.append(Unicode.Scalar(0x10000 + ((u - 0xD800) << 10) + (low - 0xDC00))!)
            } else {
                out.append(Unicode.Scalar(u) ?? "\u{FFFD}")
            }
        default:
            out.append("\u{FFFD}")
        }
    }
    flush()
    return String(out)
}
