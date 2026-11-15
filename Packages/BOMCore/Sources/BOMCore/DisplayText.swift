import Foundation

/// The text a source view displays. Identical to `SourceDocument.text`, except
/// that very long lines (minified JSON) get invisible paragraph breaks after a
/// comma outside a string, about every `maxLineBytes`. Text layout works per
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

    public static let defaultMaxLineBytes = 4096

    public init(source: SourceDocument, maxLineBytes: Int = DisplayText.defaultMaxLineBytes) {
        self.source = source
        var breakBytes: [ByteOffset] = []
        source.bytes.withUnsafeBufferPointer { b in
            var lineBytes = 0, inString = false, i = 0
            while i < b.count {
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
            }
        }
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
        // Breaks sit between ASCII bytes, so UTF-8 repair decodes exactly as in `source.text`.
        string = String(decoding: display, as: UTF8.self)
        breaks = source.utf16Offsets(ofSorted: breakBytes)
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
