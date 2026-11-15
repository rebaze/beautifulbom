import BOMCore
import Foundation
import Observation

enum SelectionOrigin { case source, structure, breadcrumb, history, reveal, launch }

/// State of one open document window. Views read the selection and react to
/// `selectionSerial`; every pane addresses the source through BOMCore ranges.
@MainActor @Observable
final class DocumentModel {
    private(set) var source: SourceDocument?
    private(set) var tree: JSONTree?
    private(set) var selection: NodeID?
    private(set) var selectionOrigin: SelectionOrigin = .launch
    /// Increments on every selection, so panes react even when the same node is chosen again.
    private(set) var selectionSerial = 0
    var textSize: CGFloat = DocumentModel.defaultTextSize
    var showDiagnostics = false

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
    }

    var isLoaded: Bool { tree != nil }

    func load() async {
        guard tree == nil else { return }
        let bytes = self.bytes
        let (source, tree) = await Task.detached(priority: .userInitiated) {
            let source = SourceDocument(bytes: bytes)
            return (source, parseJSON(source))
        }.value
        self.source = source
        self.tree = tree
        if LaunchOptions.timing { print(String(format: "open→parsed %.0f ms", -openedAt.timeIntervalSinceNow * 1000)) }
        if let pointer = LaunchOptions.selectPointer, let id = tree.resolve(pointer: pointer) {
            select(id, origin: .launch)
        }
    }

    func reportFirstLayout() {
        guard !firstLayoutReported else { return }
        firstLayoutReported = true
        if LaunchOptions.timing { print(String(format: "open→first layout %.0f ms", -openedAt.timeIntervalSinceNow * 1000)) }
    }

    func select(_ id: NodeID?, origin: SelectionOrigin) {
        if origin != .history, let current = selection, current != id {
            back.append(current)
            forward.removeAll()
        }
        selection = id
        selectionOrigin = origin
        selectionSerial += 1
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

    // MARK: Text size

    func biggerText() { textSize = min(textSize + 2, Self.textSizeRange.upperBound) }
    func smallerText() { textSize = max(textSize - 2, Self.textSizeRange.lowerBound) }
    func actualSizeText() { textSize = Self.defaultTextSize }
    func togglePresentationSize() {
        textSize = textSize == Self.presentationTextSize ? Self.defaultTextSize : Self.presentationTextSize
    }
}
