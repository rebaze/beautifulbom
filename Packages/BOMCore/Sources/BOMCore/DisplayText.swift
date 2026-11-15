import Foundation

/// The text a source view displays. Identical to `SourceDocument.text`, except
/// that very long lines (minified JSON) get invisible paragraph breaks after a
/// comma outside a string, about every `maxLineBytes`; where no such comma comes
/// (a long string, a run without commas), at any scalar boundary after twice that. Text layout works per
/// paragraph, and a single 10 MB paragraph is beyond it; wrapped on screen the
/// breaks look like ordinary soft wrapping.
///
/// The source stays authoritative: every offset passes through this mapping,
/// and copying must use `SourceDocument.slice(byteRange(_:))`, never the
/// displayed string.
public struct DisplayText: Sendable {
    public let string: String
    /// Source UTF-16 offsets before which a "\n" is inserted (each right after a comma), ascending.
    public let breaks: [UTF16Offset]
    public let source: SourceDocument
    /// For each `safeStride` bytes of the source: the last offset at or before the
    /// stride's start that lies outside a string, where lexing can safely begin.
    let safeLexStarts: [Int]
    static let safeStride = 4096

    public static let defaultMaxLineBytes = 4096

    public init(source: SourceDocument, maxLineBytes: Int = DisplayText.defaultMaxLineBytes) {
        self.source = source
        var breakBytes: [ByteOffset] = []
        var safe: [Int] = []
        source.bytes.withUnsafeBufferPointer { b in
            var lineBytes = 0, inString = false, i = 0
            var lastOutside = 0
            while i < b.count {
                while safe.count * Self.safeStride <= i { safe.append(lastOutside) }
                if !inString { lastOutside = i }
                let c = b[i]
                lineBytes += 1
                if c == 0x0A || c == 0x0D {
                    lineBytes = 0
                    inString = false
                } else if inString {
                    if c == UInt8(ascii: "\\") { i += 1; lineBytes += 1 } else if c == UInt8(ascii: "\"") { inString = false }
                } else if c == UInt8(ascii: "\"") {
                    inString = true
                } else if c == UInt8(ascii: ","), lineBytes >= maxLineBytes, i + 1 < b.count {
                    breakBytes.append(ByteOffset(value: i + 1))
                    lineBytes = 0
                }
                i += 1
                // Hard break: before any byte that starts a scalar (not 0x80...0xBF), which
                // also keeps UTF-8 repair of invalid sequences unchanged.
                if lineBytes >= 2 * maxLineBytes, i < b.count, !(0x80...0xBF).contains(b[i]),
                   b[i] != 0x0A, b[i] != 0x0D, breakBytes.last?.value != i {
                    breakBytes.append(ByteOffset(value: i))
                    lineBytes = 0
                }
            }
        }
        safeLexStarts = safe
        if breakBytes.isEmpty {
            string = source.text
            breaks = []
            return
        }
        var display: [UInt8] = []
        display.reserveCapacity(source.bytes.count + breakBytes.count)
        var last = 0
        for b in breakBytes {
            display.append(contentsOf: source.bytes[last..<b.value])
            display.append(0x0A)
            last = b.value
        }
        display.append(contentsOf: source.bytes[last...])
        // Breaks sit before a scalar's first byte, so UTF-8 repair decodes exactly as in `source.text`.
        string = String(decoding: display, as: UTF8.self)
        breaks = source.utf16Offsets(ofSorted: breakBytes)
    }

    /// A position at or before `offset`, outside any string, within about
    /// `safeStride` bytes (plus the length of a string spanning it). Independent of
    /// the parse tree, so it stays near after content the parser could not read.
    public func lexStart(atOrBefore offset: ByteOffset) -> ByteOffset {
        guard !safeLexStarts.isEmpty, offset.value >= 0 else { return ByteOffset(value: 0) }
        let k = min(offset.value / Self.safeStride, safeLexStarts.count - 1)
        return ByteOffset(value: min(safeLexStarts[k], offset.value))
    }

    /// Display UTF-16 offset of a source UTF-16 offset.
    public func displayOffset(_ s: UTF16Offset) -> Int {
        s.value + Self.count(breaks.count) { breaks[$0].value < s.value }
    }

    /// Source UTF-16 offset of a display offset; an inserted break maps to the
    /// position right after its comma.
    public func sourceOffset(_ d: Int) -> UTF16Offset {
        // The break with index j is displayed at breaks[j] + j.
        UTF16Offset(value: d - Self.count(breaks.count) { breaks[$0].value + $0 < d })
    }

    public func displayRange(_ r: Range<ByteOffset>) -> NSRange {
        let lo = displayOffset(source.utf16Offset(of: r.lowerBound))
        return NSRange(location: lo, length: displayOffset(source.utf16Offset(of: r.upperBound)) - lo)
    }

    public func byteRange(_ r: NSRange) -> Range<ByteOffset> {
        source.byteOffset(of: sourceOffset(r.location))..<source.byteOffset(of: sourceOffset(NSMaxRange(r)))
    }

    /// Number of leading indices in 0..<n for which `pred` holds (pred is monotone: true, then false).
    static func count(_ n: Int, _ pred: (Int) -> Bool) -> Int {
        var lo = 0, hi = n
        while lo < hi {
            let mid = (lo + hi) / 2
            if pred(mid) { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
