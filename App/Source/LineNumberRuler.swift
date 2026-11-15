import AppKit
import BOMCore

/// Line numbers for the visible paragraphs; a wrapped line is numbered once.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    private let display: DisplayText
    private var source: SourceDocument { display.source }
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular) {
        didSet { updateThickness() }
    }

    init(textView: NSTextView, display: DisplayText) {
        self.textView = textView
        self.display = display
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = nil
        updateThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateThickness() {
        let digits = max(3, String(source.lineCount).count)
        let sample = String(repeating: "8", count: digits) as NSString
        ruleThickness = ceil(sample.size(withAttributes: [.font: font]).width) + 20
        scrollView?.tile()
        needsDisplay = true
    }

    override var requiredThickness: CGFloat { ruleThickness }

    override var isOpaque: Bool { true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        guard let textView, let tlm = textView.textLayoutManager, let cm = tlm.textContentManager,
              let viewport = tlm.textViewportLayoutController.viewportRange else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let inset = textView.textContainerInset.height
        let documentStart = cm.documentRange.location
        var lastLine = -1
        tlm.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let origin = self.convert(NSPoint(x: 0, y: frame.minY + inset), from: textView)
            if origin.y > self.bounds.maxY { return false }
            let u16 = cm.offset(from: documentStart, to: fragment.rangeInElement.location)
            let line = self.source.line(containing: self.source.byteOffset(of: self.display.sourceOffset(u16)))
            if line != lastLine {
                lastLine = line
                let label = String(line + 1) as NSString
                let size = label.size(withAttributes: attributes)
                let firstLineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? size.height
                let y = origin.y + (firstLineHeight - size.height) / 2
                label.draw(at: NSPoint(x: self.ruleThickness - size.width - 8, y: y), withAttributes: attributes)
            }
            return true
        }
    }
}
