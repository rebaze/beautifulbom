import BOMCore
import SwiftUI

struct DocumentView: View {
    @State private var model: DocumentModel
    let fileURL: URL?

    init(document: BOMDocument, fileURL: URL?) {
        _model = State(initialValue: DocumentModel(bytes: document.bytes))
        self.fileURL = fileURL
    }

    var body: some View {
        Group {
            if let tree = model.tree {
                VStack(spacing: 0) {
                    Text("\(tree.nodeCount) nodes, \(tree.diagnostics.count) issues")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView("Reading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .focusedSceneValue(\.documentModel, model)
        .task {
            await model.load()
            if let path = LaunchOptions.snapshotPath { Snapshot.take(to: path) }
        }
    }
}
