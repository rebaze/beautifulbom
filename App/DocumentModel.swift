import AppKit
import BOMCore
import Foundation
import Observation

enum SelectionOrigin { case source, structure, breadcrumb, history, reveal, evidence, launch }

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

    // MARK: Workshop state
    /// The CycloneDX analysis; nil for any other JSON (Source only).
    private(set) var analysis: WorkshopAnalysis?
    private(set) var tab: WorkshopTab = .source
    /// The component page open on the Components tab (index into `bom.components`).
    private(set) var componentPage: Int?
    /// What the drawer shows; nil when nothing was asked for yet.
    private(set) var evidence: Evidence?
    private(set) var drawerOpen = false
    var drawerPinned = false
    /// The absent key the source view marks after the parent's opening line.
    private(set) var absentMarker: Absent?
    /// The filter the Components list starts with when another view opens it.
    var componentFilter = ComponentFilter()
    private var history = History<Place>()

    static let defaultTextSize: CGFloat = 13
    static let presentationTextSize: CGFloat = 24
    static let textSizeRange: ClosedRange<CGFloat> = 9...48

    private let bytes: [UInt8]
    let openedAt = Date()
    private var firstLayoutReported = false

    let fileName: String?

    init(bytes: [UInt8], fileName: String? = nil) {
        self.bytes = bytes
        self.fileName = fileName
        if let size = LaunchOptions.textSize { textSize = min(max(size, Self.textSizeRange.lowerBound), Self.textSizeRange.upperBound) }
    }

    var isLoaded: Bool { tree != nil }

    func load() async {
        guard tree == nil else { return }
        let bytes = self.bytes
        let (source, tree, display, analysis) = await Task.detached(priority: .userInitiated) {
            let source = SourceDocument(bytes: bytes)
            // The display text needs only the source; it is built while the tree is parsed and analysed.
            async let display = DisplayText(source: source)
            let tree = parseJSON(source)
            let analysis = WorkshopAnalysis.analyse(tree)
            return (source, tree, await display, analysis)
        }.value
        self.source = source
        self.display = display
        self.analysis = analysis
        self.tree = tree
        timing("open→parsed")
        showDiagnostics = tree.diagnostics.contains { $0.severity == .error }
        tab = analysis == nil ? .source : analysis?.ai != nil ? .model : .overview
        history.visit(.tab(tab))
        applyLaunchOptions(tree)
    }

    private func applyLaunchOptions(_ tree: JSONTree) {
        if let pointer = LaunchOptions.selectPointer, let id = tree.resolve(pointer: pointer) {
            if LaunchOptions.view == nil { show(tab: .source) }
            select(id, origin: .launch)
            if let kind = LaunchOptions.copyKind { copy(kind) }
        }
        if let name = LaunchOptions.view, let t = WorkshopTab(rawValue: name), tabs.contains(t) { show(tab: t) }
        if let ref = LaunchOptions.component, let i = analysis?.componentIndex(bomRef: ref) {
            openComponent(i)
        }
        if let rule = LaunchOptions.evidence.flatMap(RuleID.init), let first = analysis?.profile.offenders(rule).first {
            show(first.evidence)
        }
        if let query = LaunchOptions.find { typeIntoFindBar(query) }
    }

    /// `--find`: opens the find bar from the current tab and types `query` into it
    /// key by key, as a person would; with BBOM_TIMING=1 it prints each key's cost.
    private func typeIntoFindBar(_ query: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.activate(ignoringOtherApps: true)
            sourceTextView?.window?.makeKeyAndOrderFront(nil)
            find(.showFindInterface)
            try? await Task.sleep(for: .milliseconds(150))
            for ch in query {
                guard let window = sourceTextView?.window,
                      let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, characters: String(ch),
                                                  charactersIgnoringModifiers: String(ch), isARepeat: false, keyCode: 0) else { return }
                let start = Date()
                window.sendEvent(down)
                await Task.yield()
                let key = -start.timeIntervalSinceNow * 1000
                let pause = Date()
                try? await Task.sleep(for: .milliseconds(90))
                // Anything over 90 ms is time the main thread was busy with the search.
                if LaunchOptions.timing {
                    print(String(format: "find key %@ %.0f ms, blocked after %.0f ms", String(ch), key, -pause.timeIntervalSinceNow * 1000 - 90))
                    fflush(stdout)
                }
            }
        }
    }

    // MARK: Places

    /// The tabs this document has: the workshop views for an SBOM, the model for an AIBOM, Source always.
    var tabs: [WorkshopTab] {
        guard let analysis else { return [.source] }
        return analysis.ai != nil ? [.model, .source] : [.overview, .composition, .completeness, .components, .source]
    }

    func show(tab t: WorkshopTab) {
        guard tabs.contains(t) else { return }
        tab = t
        componentPage = nil
        history.visit(.tab(t))
    }

    func openComponent(_ index: Int) {
        tab = .components
        componentPage = index
        history.visit(.component(index))
    }

    /// Opens Components with `filter` applied.
    func showComponents(_ filter: ComponentFilter) {
        componentFilter = filter
        show(tab: .components)
    }

    private func apply(_ place: Place) {
        switch place {
        case .tab(let t):
            tab = t
            componentPage = nil
        case .component(let i):
            tab = .components
            componentPage = i
        case .node(let id):
            tab = .source
            select(id, origin: .history)
        }
    }

    // MARK: Evidence

    /// Shows the source behind a statement in the drawer (or in the Source tab).
    func show(_ e: Evidence) {
        guard let tree else { return }
        evidence = e
        if tab != .source { drawerOpen = true }
        switch e {
        case .located(let id):
            absentMarker = nil
            select(id, origin: .evidence)
        case .absent(let a):
            absentMarker = a
            select(a.parent, origin: .evidence)
            // Reveal the parent's opening line ("metadata": {), not the whole object.
            let start = tree.fullRange(a.parent).lowerBound
            focusRange = start..<a.insertion
        }
    }

    func closeDrawer() {
        guard !drawerPinned else { return }
        drawerOpen = false
    }

    func toggleDrawerPinned() {
        drawerPinned.toggle()
        if drawerPinned { drawerOpen = true }
    }

    var scale: CGFloat { textSize / Self.defaultTextSize }

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
        if tab == .source, origin != .history, origin != .evidence, let id, id != selection {
            history.visit(.node(id))
        }
        if origin != .evidence { absentMarker = nil }
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

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    func goBack() {
        if let p = history.back() { apply(p) }
    }

    func goForward() {
        if let p = history.forward() { apply(p) }
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

    // MARK: Find

    /// The source text view, set when it is made; the target of every find command.
    @ObservationIgnored weak var sourceTextView: NSTextView?

    /// Runs a find-bar action from any tab: switches to Source, gives the text the
    /// keyboard and hands the action to its find bar, which searches while typing.
    func find(_ action: NSTextFinder.Action) {
        guard sourceTextView != nil else { return }
        if tab != .source { show(tab: .source) }
        // After SwiftUI has laid the source out at full size, so the bar opens above it.
        DispatchQueue.main.async { [weak self] in
            guard let textView = self?.sourceTextView, let window = textView.window else { return }
            // Keep the keyboard where it is when it is already in the text or its find bar (⌘G while typing).
            let focus = window.firstResponder as? NSView
            if let pane = textView.enclosingScrollView, focus?.isDescendant(of: pane) != true {
                window.makeFirstResponder(textView)
            }
            let item = NSMenuItem()
            item.tag = action.rawValue
            textView.performTextFinderAction(item)
        }
    }

    // MARK: Text size

    func biggerText() { textSize = min(textSize + 2, Self.textSizeRange.upperBound) }
    func smallerText() { textSize = max(textSize - 2, Self.textSizeRange.lowerBound) }
    func actualSizeText() { textSize = Self.defaultTextSize }
    func togglePresentationSize() {
        textSize = textSize == Self.presentationTextSize ? Self.defaultTextSize : Self.presentationTextSize
    }
}
