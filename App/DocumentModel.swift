import AppKit
import BOMCore
import Foundation
import Observation
import UniformTypeIdentifiers

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
        let compareURL = LaunchOptions.compare.map { URL(fileURLWithPath: $0) }
        let (source, tree, display, analysis, comparison) = await Task.detached(priority: .userInitiated) {
            let source = SourceDocument(bytes: bytes)
            // The display text needs only the source; it is built while the tree is parsed and analysed.
            async let display = DisplayText(source: source)
            let tree = parseJSON(source)
            let analysis = WorkshopAnalysis.analyse(tree)
            // --compare: built here, so a snapshot waits for it.
            let comparison = analysis.flatMap { a in compareURL.flatMap { Self.comparison(a.bom, $0) } }
            return (source, tree, await display, analysis, comparison)
        }.value
        self.comparison = comparison
        self.comparedFileName = comparison == nil ? nil : compareURL?.lastPathComponent
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
        if let rule = LaunchOptions.evidence.flatMap(RuleID.init), let first = analysis?.profile?.offenders(rule).first {
            show(first.evidence)
        }
        if let query = LaunchOptions.find { typeIntoFindBar(query) }
        if let dir = LaunchOptions.exportGaps, analysis?.profile != nil {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            writeGaps(.csv, to: folder.appendingPathComponent(exportBaseName + ".csv"))
            writeGaps(.pdf, to: folder.appendingPathComponent(exportBaseName + ".pdf"))
        }
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
        let compare: [WorkshopTab] = comparison == nil ? [] : [.compare]
        return analysis.ai != nil ? [.model] + compare + [.source]
            : [.overview, .composition, .completeness, .components] + compare + [.source]
    }

    // MARK: The gap list for the client

    /// SHA-256 of the file's bytes: the handout names exactly what was read.
    var fileSHA256: String { GapExport.sha256(bytes) }

    private var exportBaseName: String {
        let base = (fileName as NSString?)?.deletingPathExtension ?? "sbom"
        return base + "-gaps"
    }

    /// File › Export Gap List as PDF… / as CSV….
    func exportGaps(_ kind: GapExport.Kind) {
        guard analysis?.profile != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind == .pdf ? .pdf : .commaSeparatedText]
        panel.nameFieldStringValue = exportBaseName + (kind == .pdf ? ".pdf" : ".csv")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeGaps(kind, to: url)
    }

    @discardableResult
    func writeGaps(_ kind: GapExport.Kind, to url: URL) -> Bool {
        guard let analysis else { return false }
        switch kind {
        case .csv: return (try? GapExport.csv(analysis).write(to: url, options: .atomic)) != nil
        case .pdf: return GapExport.pdf(analysis, fileName: fileName, sha256: fileSHA256, to: url)
        }
    }

    // MARK: Comparing with a second file

    /// This file (A) against a second one (B); nil until File › Compare With….
    private(set) var comparison: BOMComparison?
    private(set) var comparedFileName: String?

    /// File › Compare With…: pick a second SBOM, pair it with this one, show the Compare tab.
    func chooseComparison() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = L("Choose an SBOM to compare with this one.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await compare(with: url) }
    }

    func compare(with url: URL) async {
        guard let a = analysis?.bom else { return }
        let result = await Task.detached(priority: .userInitiated) { Self.comparison(a, url) }.value
        guard let result else {
            let alert = NSAlert()
            alert.messageText = L("%@ is not a CycloneDX or SPDX SBOM.", url.lastPathComponent)
            alert.informativeText = L("Beautiful BOM compares CycloneDX 1.2 or later and SPDX 2.3 or 3.0 in JSON.")
            alert.runModal()
            return
        }
        comparison = result
        comparedFileName = url.lastPathComponent
        show(tab: .compare)
    }

    nonisolated static func comparison(_ a: BOMCore.BOMDocument, _ url: URL) -> BOMComparison? {
        guard let data = try? Data(contentsOf: url),
              let b = BOMCore.BOMDocument.recognize(parseJSON(SourceDocument(bytes: Array(data)))) else { return nil }
        return BOMComparison(a, b)
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
