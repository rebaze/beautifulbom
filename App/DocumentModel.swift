import AppKit
import BOMCore
import Foundation
import Observation

enum SelectionOrigin { case source, structure, breadcrumb, history, reveal, launch }

enum CopyKind { case pointer, value, source }

/// State of one open document window. Views read the selection and react to
/// `selectionSerial`; every pane addresses the source through BOMCore ranges.
@MainActor @Observable
final class DocumentModel {
    private(set) var source: SourceDocument?
    private(set) var tree: JSONTree?
    private(set) var display: DisplayText?
    private(set) var selection: NodeID?
    private(set) var selectionOrigin: SelectionOrigin = .launch
    /// Increments on every selection, so panes react even when the same node is chosen again.
    private(set) var selectionSerial = 0
    var textSize: CGFloat = DocumentModel.defaultTextSize
    var showDiagnostics = false
    /// A byte range to reveal instead of the selected node's range (a diagnostic).
    private(set) var focusRange: Range<ByteOffset>?

    static let defaultTextSize: CGFloat = 13
    static let presentationTextSize: CGFloat = 24
    static let textSizeRange: ClosedRange<CGFloat> = 9...48

    private var back: [NodeID] = []
    private var forward: [NodeID] = []
    private let bytes: [UInt8]
    let openedAt = Date()
    private var firstLayoutReported = false

    init(bytes: [UInt8]) {
        self.bytes = bytes
        if let size = LaunchOptions.textSize { textSize = min(max(size, Self.textSizeRange.lowerBound), Self.textSizeRange.upperBound) }
    }

    var isLoaded: Bool { tree != nil }

    func load() async {
        guard tree == nil else { return }
        let bytes = self.bytes
        let (source, tree, display) = await Task.detached(priority: .userInitiated) {
            let source = SourceDocument(bytes: bytes)
            return (source, parseJSON(source), DisplayText(source: source))
        }.value
        self.source = source
        self.display = display
        self.tree = tree
        timing("open→parsed")
        showDiagnostics = tree.diagnostics.contains { $0.severity == .error }
        if let pointer = LaunchOptions.selectPointer, let id = tree.resolve(pointer: pointer) {
            select(id, origin: .launch)
            if let kind = LaunchOptions.copyKind { copy(kind) }
        }
    }

    func reportFirstLayout() {
        guard !firstLayoutReported else { return }
        firstLayoutReported = true
        timing("open→first layout")
    }

    private func timing(_ label: String) {
        guard LaunchOptions.timing else { return }
        print(String(format: "%@ %.0f ms", label, -openedAt.timeIntervalSinceNow * 1000))
        fflush(stdout)
    }

    func select(_ id: NodeID?, origin: SelectionOrigin) {
        if origin != .history, let current = selection, current != id {
            back.append(current)
            forward.removeAll()
        }
        selection = id
        selectionOrigin = origin
        focusRange = nil
        selectionSerial += 1
    }

    /// Selects the node where a diagnostic starts and reveals the diagnostic's own range.
    func reveal(_ diagnostic: Diagnostic) {
        guard let tree else { return }
        select(tree.node(at: diagnostic.range.lowerBound) ?? tree.root, origin: .reveal)
        focusRange = diagnostic.range.isEmpty
            ? diagnostic.range.lowerBound..<ByteOffset(value: min(diagnostic.range.lowerBound.value + 1, tree.source.bytes.count))
            : diagnostic.range
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    func goBack() {
        guard let previous = back.popLast() else { return }
        if let current = selection { forward.append(current) }
        select(previous, origin: .history)
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        if let current = selection { back.append(current) }
        select(next, origin: .history)
    }

    // MARK: Copy

    /// The text a copy command puts on the pasteboard for `node` (default: the selection).
    func copyText(_ kind: CopyKind, node: NodeID? = nil) -> String? {
        guard let id = node ?? selection, let tree else { return nil }
        switch kind {
        case .pointer: return tree.pointer(id).description
        case .value: return tree.decodedValue(id)
        case .source: return tree.source.slice(tree.fullRange(id))
        }
    }

    func copy(_ kind: CopyKind, node: NodeID? = nil) {
        guard let text = copyText(kind, node: node) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Text size

    func biggerText() { textSize = min(textSize + 2, Self.textSizeRange.upperBound) }
    func smallerText() { textSize = max(textSize - 2, Self.textSizeRange.lowerBound) }
    func actualSizeText() { textSize = Self.defaultTextSize }
    func togglePresentationSize() {
        textSize = textSize == Self.presentationTextSize ? Self.defaultTextSize : Self.presentationTextSize
    }
}
