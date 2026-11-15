import Foundation

/// The original bytes of a document, authoritative and never rewritten, with the
/// indexes needed to address them from the text system.
///
/// `text` is `String(decoding: bytes, as: UTF8.self)`: every maximal invalid UTF-8
/// subpart becomes one U+FFFD, exactly as shown by a text view. All offset
/// conversions follow the same decoding, so bytes and displayed text map one to one.
public final class SourceDocument: Sendable {
    public let bytes: [UInt8]
    public let text: String
    /// Byte offset of the first byte of each line. Lines break after `\n` only.
    let lineStarts: [Int]
    /// Checkpoints at scalar starts, roughly every `checkpointStride` bytes.
    let checkpoints: [Checkpoint]

    static let checkpointStride = 4096
    static let maxInvalidUTF8Ranges = 100

    /// Runs of invalid UTF-8 (each shown as U+FFFD per maximal subpart); the first 100.
    public let invalidUTF8: [Range<ByteOffset>]
    /// Number of invalid runs in the whole file.
    public let invalidUTF8Count: Int

    struct Checkpoint: Sendable {
        let byte: Int
        let utf16: Int
        let scalars: Int
    }

    public init(bytes: [UInt8]) {
        self.bytes = bytes
        self.text = String(decoding: bytes, as: UTF8.self)

        var starts = [0]
        var cps = [Checkpoint(byte: 0, utf16: 0, scalars: 0)]
        var next = Self.checkpointStride
        var i = 0, u16 = 0, scalars = 0
        var invalid: [Range<ByteOffset>] = []
        var invalidCount = 0
        var runEnd = -1
        bytes.withUnsafeBufferPointer { buf in
            while i < buf.count {
                if i >= next {
                    cps.append(Checkpoint(byte: i, utf16: u16, scalars: scalars))
                    next = i + Self.checkpointStride
                }
                let b = buf[i]
                if b < 0x80 {
                    if b == 0x0A { starts.append(i + 1) }
                    i += 1; u16 += 1
                } else {
                    let (n, u) = Self.scalarLength(buf, at: i)
                    if n != Self.expectedLength(b) {
                        if i == runEnd, let last = invalid.last, last.upperBound.value == i {
                            invalid[invalid.count - 1] = last.lowerBound..<ByteOffset(value: i + n)
                        } else if i != runEnd {
                            invalidCount += 1
                            if invalid.count < Self.maxInvalidUTF8Ranges {
                                invalid.append(ByteOffset(value: i)..<ByteOffset(value: i + n))
                            }
                        }
                        runEnd = i + n
                    }
                    i += n; u16 += u
                }
                scalars += 1
            }
        }
        self.lineStarts = starts
        self.checkpoints = cps
        self.invalidUTF8 = invalid
        self.invalidUTF8Count = invalidCount
    }

    public var lineCount: Int { lineStarts.count }

    /// Byte offset of the first byte of a 0-based line.
    public func lineStart(_ line: Int) -> Int { lineStarts[line] }

    /// 0-based line index of the line containing `offset`.
    public func line(containing offset: ByteOffset) -> Int {
        Self.lastIndex(in: lineStarts, notAfter: offset.value)
    }

    /// 1-based line and column; the column counts Unicode scalars (an invalid
    /// UTF-8 subpart counts as one, like the U+FFFD that replaces it).
    public func lineColumn(of offset: ByteOffset) -> (line: Int, column: Int) {
        let l = line(containing: offset)
        let start = position(ofByte: lineStarts[l]).scalars
        return (l + 1, position(ofByte: offset.value).scalars - start + 1)
    }

    public func utf16Offset(of offset: ByteOffset) -> UTF16Offset {
        UTF16Offset(value: position(ofByte: offset.value).utf16)
    }

    /// The byte offset for a UTF-16 offset; an offset inside a scalar (e.g. between
    /// the halves of a surrogate pair) rounds down to the scalar's start.
    public func byteOffset(of offset: UTF16Offset) -> ByteOffset {
        let target = offset.value
        var lo = 0, hi = checkpoints.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if checkpoints[mid].utf16 <= target { lo = mid } else { hi = mid - 1 }
        }
        var i = checkpoints[lo].byte, u16 = checkpoints[lo].utf16
        bytes.withUnsafeBufferPointer { buf in
            while i < buf.count {
                let (n, u) = buf[i] < 0x80 ? (1, 1) : Self.scalarLength(buf, at: i)
                if u16 + u > target { break }
                i += n; u16 += u
            }
        }
        return ByteOffset(value: i)
    }

    /// UTF-16 offsets for ascending byte offsets in one forward walk, for
    /// converting many token ranges at once (syntax colouring).
    public func utf16Offsets(ofSorted offsets: [ByteOffset]) -> [UTF16Offset] {
        guard let first = offsets.first else { return [] }
        var out: [UTF16Offset] = []
        out.reserveCapacity(offsets.count)
        var i = 0, u16 = 0
        (u16, _) = position(ofByte: first.value)
        i = byteOffset(of: UTF16Offset(value: u16)).value
        bytes.withUnsafeBufferPointer { buf in
            for target in offsets {
                let t = min(target.value, buf.count)
                if t - i > Self.checkpointStride || t < i {
                    let p = position(ofByte: t)
                    u16 = p.utf16
                    i = byteOffset(of: UTF16Offset(value: u16)).value
                }
                while i < t {
                    let (n, u) = buf[i] < 0x80 ? (1, 1) : Self.scalarLength(buf, at: i)
                    if i + n > t { break }
                    i += n; u16 += u
                }
                out.append(UTF16Offset(value: u16))
            }
        }
        return out
    }

    public func nsRange(_ range: Range<ByteOffset>) -> NSRange {
        let lo = utf16Offset(of: range.lowerBound).value
        return NSRange(location: lo, length: utf16Offset(of: range.upperBound).value - lo)
    }

    public func byteRange(_ range: NSRange) -> Range<ByteOffset> {
        byteOffset(of: UTF16Offset(value: range.location))
            ..< byteOffset(of: UTF16Offset(value: NSMaxRange(range)))
    }

    /// The original text of a byte range, decoded the same way as `text`.
    public func slice(_ range: Range<ByteOffset>) -> String {
        let lo = max(0, range.lowerBound.value), hi = min(bytes.count, range.upperBound.value)
        guard lo < hi else { return "" }
        return String(decoding: bytes[lo..<hi], as: UTF8.self)
    }

    // MARK: - Internals

    /// UTF-16 units and scalars before `byte` (rounded down to a scalar start).
    func position(ofByte byte: Int) -> (utf16: Int, scalars: Int) {
        var lo = 0, hi = checkpoints.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if checkpoints[mid].byte <= byte { lo = mid } else { hi = mid - 1 }
        }
        var i = checkpoints[lo].byte, u16 = checkpoints[lo].utf16, scalars = checkpoints[lo].scalars
        bytes.withUnsafeBufferPointer { buf in
            while i < min(byte, buf.count) {
                let (n, u) = buf[i] < 0x80 ? (1, 1) : Self.scalarLength(buf, at: i)
                if i + n > byte { break }
                i += n; u16 += u; scalars += 1
            }
        }
        return (u16, scalars)
    }

    /// Length in bytes and UTF-16 units of the scalar (or maximal invalid subpart,
    /// which decodes to one U+FFFD) starting at `i`, per Unicode table 3-7.
    @inline(__always)
    static func scalarLength(_ buf: UnsafeBufferPointer<UInt8>, at i: Int) -> (bytes: Int, utf16: Int) {
        let b0 = buf[i]
        let tail: [ClosedRange<UInt8>]
        switch b0 {
        case 0x00...0x7F: return (1, 1)
        case 0xC2...0xDF: tail = [0x80...0xBF]
        case 0xE0: tail = [0xA0...0xBF, 0x80...0xBF]
        case 0xE1...0xEC, 0xEE...0xEF: tail = [0x80...0xBF, 0x80...0xBF]
        case 0xED: tail = [0x80...0x9F, 0x80...0xBF]
        case 0xF0: tail = [0x90...0xBF, 0x80...0xBF, 0x80...0xBF]
        case 0xF1...0xF3: tail = [0x80...0xBF, 0x80...0xBF, 0x80...0xBF]
        case 0xF4: tail = [0x80...0x8F, 0x80...0xBF, 0x80...0xBF]
        default: return (1, 1)  // 0x80...0xC1, 0xF5...0xFF: invalid lead byte
        }
        for (k, allowed) in tail.enumerated() {
            let j = i + 1 + k
            if j >= buf.count || !allowed.contains(buf[j]) { return (1 + k, 1) }
        }
        return (1 + tail.count, tail.count == 3 ? 2 : 1)
    }

    /// Length of a well-formed sequence starting with `lead`; 0 for bytes that cannot start one.
    @inline(__always)
    static func expectedLength(_ lead: UInt8) -> Int {
        switch lead {
        case 0x00...0x7F: 1
        case 0xC2...0xDF: 2
        case 0xE0...0xEF: 3
        case 0xF0...0xF4: 4
        default: 0
        }
    }

    static func lastIndex(in sorted: [Int], notAfter value: Int) -> Int {
        var lo = 0, hi = sorted.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if sorted[mid] <= value { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}
