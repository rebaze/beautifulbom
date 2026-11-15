import AppKit
import BOMCore
import SwiftUI

/// The faithful, read-only source: the original text, coloured, with line
/// numbers and the system find bar. Selecting text selects the node there;
/// a selection from elsewhere selects and reveals the node's exact range.
struct SourceTextView: NSViewRepresentable {
    let model: DocumentModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeView() }

    func updateNSView(_ view: NSScrollView, context: Context) {
        // Read observed properties here so SwiftUI calls us when they change.
        context.coordinator.update(serial: model.selectionSerial, textSize: model.textSize)
        context.coordinator.updateMarker(model.absentMarker)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: DocumentModel
        private var textView: NSTextView!
        private var scrollView: NSScrollView!
        private var ruler: LineNumberRuler!
        private var highlighter: Highlighter?
        private var appliedSerial = -1
        private var appliedTextSize: CGFloat = 0
        private var applyingSelection = false
        private var marker: Absent?
        private let markerView = AbsentMarkerView()

        init(model: DocumentModel) { self.model = model }

        func makeView() -> NSScrollView {
            guard let display = model.display, let tree = model.tree else { return NSScrollView() }
            let textView = SourceNSTextView(usingTextLayoutManager: true)
            textView.display = display
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.importsGraphics = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.allowsUndo = false
            textView.drawsBackground = true
            textView.backgroundColor = .textBackgroundColor
            textView.textContainerInset = NSSize(width: 10, height: 14)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.lineFragmentPadding = 4
            textView.setAccessibilityLabel("Source")

            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = true
            scrollView.backgroundColor = .textBackgroundColor
            scrollView.documentView = textView
            scrollView.contentView.postsBoundsChangedNotifications = true

            let ruler = LineNumberRuler(textView: textView, display: display)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            scrollView.tile()

            self.textView = textView
            self.scrollView = scrollView
            self.ruler = ruler

            textView.textStorage?.setAttributedString(NSAttributedString(string: display.string, attributes: baseAttributes()))
            appliedTextSize = model.textSize
            textView.delegate = self  // after the text is in: setting it changes the selection
            if let tlm = textView.textLayoutManager {
                let highlighter = Highlighter(display: display, tree: tree, textLayoutManager: tlm)
                highlighter.indentLines = { [weak self] range in self?.applyHangingIndents(in: range) }
                self.highlighter = highlighter
            }
            ruler.font = Self.rulerFont(model.textSize)
            markerView.isHidden = true
            textView.addSubview(markerView)

            NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged),
                                                   name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged),
                                                   name: NSView.frameDidChangeNotification, object: textView)
            DispatchQueue.main.async { [weak self] in
                self?.viewportChanged()
                self?.model.reportFirstLayout()
            }
            return scrollView
        }

        static func rulerFont(_ textSize: CGFloat) -> NSFont {
            .monospacedDigitSystemFont(ofSize: max(10, textSize * 0.82), weight: .regular)
        }

        /// Wrapped lines continue at their own indentation (plus two columns), so deep
        /// JSON stays readable at presentation size. Only for lines starting in `range`.
        private func applyHangingIndents(in range: Range<ByteOffset>) {
            guard let display = model.display, let storage = textView.textStorage else { return }
            let source = display.source
            let bytes = source.bytes
            let advance = (" " as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: model.textSize, weight: .regular)]).width
            let maxIndent = max(0, (textView.textContainer?.size.width ?? 600) * 0.5)
            var line = source.line(containing: range.lowerBound)
            if source.lineStart(line) < range.lowerBound.value { line += 1 }
            storage.beginEditing()
            while line < source.lineCount, source.lineStart(line) < range.upperBound.value {
                let start = source.lineStart(line)
                var i = start, columns = 0
                while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x09 {
                    columns += bytes[i] == 0x09 ? 4 : 1
                    i += 1
                }
                if columns > 0 {
                    let end = line + 1 < source.lineCount ? source.lineStart(line + 1) : bytes.count
                    let style = NSMutableParagraphStyle()
                    style.lineHeightMultiple = 1.15
                    // Capped, so a narrow pane at presentation size keeps room for text.
                    style.headIndent = min(CGFloat(columns + 2) * advance, maxIndent)
                    storage.addAttribute(.paragraphStyle, value: style,
                                         range: display.displayRange(ByteOffset(value: start)..<ByteOffset(value: end)))
                }
                line += 1
            }
            storage.endEditing()
        }

        private func baseAttributes() -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.15
            return [
                .font: NSFont.monospacedSystemFont(ofSize: model.textSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        }

        func update(serial: Int, textSize: CGFloat) {
            guard textView != nil else { return }
            if textSize != appliedTextSize {
                appliedTextSize = textSize
                let keep = textView.selectedRange()
                applyingSelection = true
                if let storage = textView.textStorage {
                    storage.beginEditing()
                    storage.setAttributes(baseAttributes(), range: NSRange(location: 0, length: storage.length))
                    storage.endEditing()
                }
                textView.setSelectedRange(keep)
                applyingSelection = false
                ruler.font = Self.rulerFont(textSize)
                highlighter?.reset()
                applyNodeHighlight()
                textView.scrollRangeToVisible(keep)
                viewportChanged()
            }
            if serial != appliedSerial {
                appliedSerial = serial
                applyNodeHighlight()
                if model.selectionOrigin != .source { revealWhenReady() }
            }
        }

        private func selectedNodeRange() -> NSRange? {
            guard let id = model.selection, let tree = model.tree, let display = model.display else { return nil }
            return display.displayRange(tree.fullRange(id))
        }

        /// An absent key shows only its marker, not the whole parent object.
        private func applyNodeHighlight() { highlighter?.highlightNode(model.absentMarker == nil ? selectedNodeRange() : nil) }

        /// The view may not be in a window or sized yet (first selection at launch).
        private func revealWhenReady(attempts: Int = 20) {
            if textView.window != nil, scrollView.contentView.bounds.height > 0 {
                revealSelection()
            } else if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.revealWhenReady(attempts: attempts - 1)
                }
            }
        }

        private func revealSelection() {
            let focus = model.focusRange.flatMap { r in model.display.map { $0.displayRange(r) } }
            guard let range = focus ?? selectedNodeRange() else { return }
            applyingSelection = true
            textView.setSelectedRange(range)
            applyingSelection = false
            scrollToCentre(range)
            textView.showFindIndicator(for: NSRange(location: range.location, length: min(range.length, 2_000)))
        }

        private func scrollToCentre(_ range: NSRange) {
            guard let tlm = textView.textLayoutManager, let textRange = tlm.textRange(NSRange(location: range.location, length: 0)) else {
                textView.scrollRangeToVisible(range)
                return
            }
            tlm.ensureLayout(for: textRange)
            var target: CGRect?
            tlm.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
                target = frame
                return false
            }
            guard let frame = target else {
                textView.scrollRangeToVisible(range)
                return
            }
            let clip = scrollView.contentView
            // Keep x: the ruler is a content inset, so x = 0 would slide text under it.
            var visible = clip.bounds
            visible.origin.y = frame.midY + textView.textContainerInset.height - clip.bounds.height / 2
            clip.scroll(to: clip.constrainBoundsRect(visible).origin)
            scrollView.reflectScrolledClipView(clip)
            viewportChanged()
        }

        @objc private func viewportChanged() {
            guard let tlm = textView?.textLayoutManager,
                  let viewport = tlm.textViewportLayoutController.viewportRange else { return }
            highlighter?.colour(visible: tlm.nsRange(viewport))
            ruler.needsDisplay = true
            positionMarker()
        }

        func updateMarker(_ absent: Absent?) {
            guard textView != nil, absent != marker else { return }
            marker = absent
            positionMarker()
        }

        /// Draws "⟵ "key" would be here: absent" after the end of the line that
        /// holds the insertion point. A decoration: the text is never changed.
        private func positionMarker() {
            guard let absent = marker, let display = model.display, let tlm = textView.textLayoutManager else {
                markerView.isHidden = true
                return
            }
            // After the end of the display line when that is on the insertion's visual
            // line (pretty JSON); otherwise, as in a wrapped minified line, right-aligned
            // on the visual line that holds the insertion point.
            let at = display.displayOffset(display.source.utf16Offset(of: absent.insertion))
            let endAt = display.displayLineEnd(containing: absent.insertion)
            guard let here = caretRect(tlm, at), let end = caretRect(tlm, endAt) else { markerView.isHidden = true; return }
            let origin = textView.textContainerOrigin
            let font = NSFont.monospacedSystemFont(ofSize: model.textSize, weight: .regular)
            markerView.text = "  ⟵ " + L("\"%@\" would be here: absent", absent.key)
            markerView.font = font
            let height = max(here.height, font.boundingRectForFont.height)
            if abs(end.minY - here.minY) < 1 {
                markerView.rightAligned = false
                markerView.frame = CGRect(x: end.minX + origin.x, y: end.minY + origin.y,
                                          width: max(0, textView.bounds.width - (end.minX + origin.x)), height: height)
            } else {
                markerView.rightAligned = true
                markerView.frame = CGRect(x: origin.x, y: here.minY + origin.y,
                                          width: max(0, textView.bounds.width - origin.x * 2), height: height)
            }
            markerView.isHidden = false
            markerView.needsDisplay = true
        }

        private func caretRect(_ tlm: NSTextLayoutManager, _ location: Int) -> CGRect? {
            guard let range = tlm.textRange(NSRange(location: location, length: 0)) else { return nil }
            tlm.ensureLayout(for: range)
            var caret: CGRect?
            tlm.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
                caret = frame
                return false
            }
            return caret
        }

        // MARK: NSTextViewDelegate

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !applyingSelection, let tree = model.tree, let display = model.display else { return }
            let location = textView.selectedRange().location
            guard location != NSNotFound else { return }
            let id = tree.node(at: display.source.byteOffset(of: display.sourceOffset(location)))
            if id != model.selection { model.select(id, origin: .source) }
        }
    }
}

/// The red note for an absent key; lets clicks through.
final class AbsentMarkerView: NSView {
    var text = ""
    var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    /// On a wrapped line the note sits at the right edge, over the line's tail, on an opaque label.
    var rightAligned = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.systemRed]
        if rightAligned {
            let size = (text as NSString).size(withAttributes: attributes)
            let label = NSRect(x: max(0, bounds.width - size.width - 8), y: 0, width: min(bounds.width, size.width + 8), height: bounds.height)
            NSColor.textBackgroundColor.setFill()
            label.fill()
            NSColor.systemRed.withAlphaComponent(0.12).setFill()
            label.fill()
            (text as NSString).draw(at: NSPoint(x: label.minX + 4, y: 0), withAttributes: attributes)
        } else {
            NSColor.systemRed.withAlphaComponent(0.08).setFill()
            bounds.fill()
            (text as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: attributes)
        }
    }
}

/// Copies the original bytes of the selection, never the displayed text, which
/// may contain line breaks added for layout (see `DisplayText`).
final class SourceNSTextView: NSTextView {
    var display: DisplayText?

    override func copy(_ sender: Any?) {
        guard let display, selectedRange().length > 0 else { return super.copy(sender) }
        let text = display.source.slice(display.byteRange(selectedRange()))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
