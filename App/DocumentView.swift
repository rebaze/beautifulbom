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
            if model.isLoaded {
                SourceTextView(model: model)
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
