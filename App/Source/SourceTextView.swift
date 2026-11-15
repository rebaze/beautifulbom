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
                highlighter = Highlighter(display: display, tree: tree, textLayoutManager: tlm)
            }

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
                ruler.font = .monospacedDigitSystemFont(ofSize: max(10, textSize * 0.82), weight: .regular)
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

        private func applyNodeHighlight() { highlighter?.highlightNode(selectedNodeRange()) }

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
