import BOMCore
import SwiftUI

struct DocumentView: View {
    @State private var model: DocumentModel
    let fileURL: URL?
    @State private var outlineWidth: CGFloat = 340
    @State private var drawerFraction: CGFloat = 0.38
    @State private var dropTargeted = false

    init(document: BOMDocument, fileURL: URL?) {
        _model = State(initialValue: DocumentModel(bytes: document.bytes, fileName: fileURL?.lastPathComponent))
        self.fileURL = fileURL
    }

    var body: some View {
        Group {
            if model.isLoaded {
                content
            } else {
                ProgressView("Reading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .dropDestination(for: URL.self) { urls, _ in
            DropToOpen.open(urls)
        } isTargeted: { dropTargeted = $0 }
        .overlay { if dropTargeted { DropToOpen.Highlight() } }
        .environment(model)
        .focusedSceneValue(\.documentModel, model)
        .onChange(of: model.tab == .source || model.drawerOpen) { _, sourceVisible in
            // The source view stays alive when hidden; it must not keep the keyboard (⌘C, ⌘F).
            if !sourceVisible, let w = NSApp.keyWindow, w.firstResponder is NSTextView { w.makeFirstResponder(nil) }
        }
        .onAppear { Welcome.close() }
        .task {
            await model.load()
            if let path = LaunchOptions.snapshotPath { Snapshot.take(to: path, after: .milliseconds(LaunchOptions.find == nil ? 1200 : 3000)) }
        }
    }

    /// One layout for every tab, so the source view (expensive for large files)
    /// stays alive: on the Source tab it fills the window beside the outline; on
    /// the workshop tabs it is the evidence drawer under the view.
    private var content: some View {
        let isSource = model.tab == .source
        return VStack(spacing: 0) {
            if model.analysis != nil {
                TabBar(model: model)
                Divider()
            }
            if isSource {
                BreadcrumbBar(model: model)
                Divider()
                if let tree = model.tree, !tree.diagnostics.isEmpty {
                    DiagnosticsBanner(model: model, diagnostics: tree.diagnostics)
                    Divider()
                }
            }
            GeometryReader { geo in
                let drawerHeight = isSource ? geo.size.height : (model.drawerOpen ? max(160, geo.size.height * drawerFraction) : 0)
                VStack(spacing: 0) {
                    if !isSource, let analysis = model.analysis {
                        WorkshopContent(model: model, analysis: analysis)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if model.drawerOpen {
                            DragHandle(axis: .vertical) { delta in
                                drawerFraction = min(0.8, max(0.15, drawerFraction - delta / geo.size.height))
                            }
                            EvidenceHeader(model: model)
                            Divider()
                        }
                    }
                    HStack(spacing: 0) {
                        if isSource {
                            StructureOutlineView(model: model)
                                .frame(width: min(outlineWidth, geo.size.width - 360))
                            DragHandle(axis: .horizontal) { delta in
                                outlineWidth = min(640, max(240, outlineWidth + delta))
                            }
                        }
                        SourceTextView(model: model)
                            .frame(minWidth: 360)
                    }
                    .frame(height: max(0, drawerHeight))
                    .clipped()
                    .opacity(isSource || model.drawerOpen ? 1 : 0)
                    .accessibilityHidden(!(isSource || model.drawerOpen))
                }
            }
        }
    }
}

/// A thin divider that resizes its neighbours when dragged.
struct DragHandle: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    let changed: (CGFloat) -> Void
    @State private var last: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
            .padding(axis == .horizontal ? .horizontal : .vertical, 2)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    let now = axis == .horizontal ? v.translation.width : v.translation.height
                    changed(now - last)
                    last = now
                }
                .onEnded { _ in last = 0 })
    }
}

/// Files dropped on a window open in windows of their own, as in Preview; a
/// file that is already open comes to the front.
enum DropToOpen {
    @MainActor
    static func open(_ urls: [URL]) -> Bool {
        let files = urls.filter(\.isFileURL)
        for url in files {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        return !files.isEmpty
    }

    struct Highlight: View {
        var body: some View {
            // The window recedes, so the message reads on any view underneath.
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.94)
                Color.accentColor.opacity(0.06)
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(10)
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 48, weight: .light))
                    Text(L("Drop to open")).font(.title.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .allowsHitTesting(false)
        }
    }
}
