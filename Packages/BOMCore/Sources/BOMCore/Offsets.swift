/// A position in the original file, counted in UTF-8 bytes. The engine's native unit.
public struct ByteOffset: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var value: Int
    public init(value: Int) { self.value = value }
    public static func < (a: ByteOffset, b: ByteOffset) -> Bool { a.value < b.value }
    public var description: String { "byte \(value)" }
}

/// A position in the decoded text, counted in UTF-16 code units, as AppKit/UIKit text uses.
public struct UTF16Offset: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var value: Int
    public init(value: Int) { self.value = value }
    public static func < (a: UTF16Offset, b: UTF16Offset) -> Bool { a.value < b.value }
    public var description: String { "utf16 \(value)" }
}
