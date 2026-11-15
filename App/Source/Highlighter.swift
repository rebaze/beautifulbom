import AppKit
import BOMCore

/// Colours the visible part of the source, window by window, as TextKit 2
/// rendering attributes. The text storage is never changed for colour.
@MainActor
final class Highlighter {
    static let windowBytes = 64 * 1024

    private let source: SourceDocument
    private let display: DisplayText
    private let tree: JSONTree
    private weak var textLayoutManager: NSTextLayoutManager?
    private var coloured = Set<Int>()
    /// Applies hanging indents (layout attributes) to the lines of a byte window.
    var indentLines: ((Range<ByteOffset>) -> Void)?
    private var nodeHighlight: NSTextRange?

    static let colours: [TokenKind: NSColor] = [
        .key: .systemBlue,
        .string: .systemGreen,
        .number: .systemOrange,
        .literal: .systemPurple,
        .punctuation: .tertiaryLabelColor,
        .comment: .secondaryLabelColor,
        .invalid: .systemRed,
    ]

    init(display: DisplayText, tree: JSONTree, textLayoutManager: NSTextLayoutManager) {
        self.source = display.source
        self.display = display
        self.tree = tree
        self.textLayoutManager = textLayoutManager
    }

    /// Forget what was coloured (after a font change re-creates layout).
    func reset() { coloured.removeAll() }

    /// Colours every not yet coloured window intersecting the visible display range.
    func colour(visible: NSRange) {
        guard let tlm = textLayoutManager, visible.length > 0 else { return }
        let bytes = display.byteRange(visible)
        let first = bytes.lowerBound.value / Self.windowBytes
        let last = max(first, (bytes.upperBound.value - 1) / Self.windowBytes)
        for w in first...last where !coloured.contains(w) {
            coloured.insert(w)
            colourWindow(w, tlm)
            indentLines?(ByteOffset(value: w * Self.windowBytes)..<ByteOffset(value: min((w + 1) * Self.windowBytes, source.bytes.count)))
        }
    }

    private func colourWindow(_ w: Int, _ tlm: NSTextLayoutManager) {
        let windowStart = ByteOffset(value: w * Self.windowBytes)
        let windowEnd = ByteOffset(value: min((w + 1) * Self.windowBytes, source.bytes.count))
        // The nearer of two safe starts: the tree's (exact) and the display scan's (bounded
        // even after content the parser could not read).
        let from = max(tree.lexStart(atOrBefore: windowStart), display.lexStart(atOrBefore: windowStart))
        let tokens = lex(source, from: from, to: windowEnd)
            .filter { $0.range.upperBound > windowStart }
        guard !tokens.isEmpty else { return }
        var bounds: [ByteOffset] = []
        bounds.reserveCapacity(tokens.count * 2)
        for t in tokens {
            bounds.append(t.range.lowerBound)
            bounds.append(t.range.upperBound)
        }
        let u16 = source.utf16Offsets(ofSorted: bounds).map { display.displayOffset($0) }
        guard let cm = tlm.textContentManager,
              let base = cm.location(cm.documentRange.location, offsetBy: u16[0]) else { return }
        let baseOffset = u16[0]
        for (i, t) in tokens.enumerated() {
            guard let colour = Self.colours[t.kind],
                  let s = cm.location(base, offsetBy: u16[2 * i] - baseOffset),
                  let e = cm.location(s, offsetBy: u16[2 * i + 1] - u16[2 * i]),
                  let range = NSTextRange(location: s, end: e) else { continue }
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: colour]
            if t.kind == .invalid {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = NSColor.systemRed
            }
            tlm.setRenderingAttributes(attributes, for: range)
        }
        // setRenderingAttributes replaced the node background on these tokens; restore it.
        if let node = nodeHighlight,
           let windowRange = tlm.textRange(NSRange(location: u16[0], length: u16[u16.count - 1] - u16[0])),
           let overlap = node.intersection(windowRange) {
            tlm.addRenderingAttribute(.backgroundColor, value: Self.nodeBackground, for: overlap)
        }
    }

    static let nodeBackground = NSColor.controlAccentColor.withAlphaComponent(0.12)

    /// A quiet background behind the selected node's full range.
    func highlightNode(_ range: NSRange?) {
        guard let tlm = textLayoutManager else { return }
        if let old = nodeHighlight {
            tlm.removeRenderingAttribute(.backgroundColor, for: old)
            nodeHighlight = nil
        }
        guard let range, let textRange = tlm.textRange(range) else { return }
        tlm.addRenderingAttribute(.backgroundColor, value: Self.nodeBackground, for: textRange)
        nodeHighlight = textRange
    }
}

extension NSTextLayoutManager {
    func textRange(_ range: NSRange) -> NSTextRange? {
        guard let cm = textContentManager,
              let s = cm.location(cm.documentRange.location, offsetBy: range.location),
              let e = cm.location(s, offsetBy: range.length) else { return nil }
        return NSTextRange(location: s, end: e)
    }

    func nsRange(_ range: NSTextRange) -> NSRange {
        guard let cm = textContentManager else { return NSRange(location: NSNotFound, length: 0) }
        let location = cm.offset(from: cm.documentRange.location, to: range.location)
        return NSRange(location: location, length: cm.offset(from: range.location, to: range.endLocation))
    }
}
