import SwiftUI

@main
struct BeautifulBOMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: BOMDocument.self) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
        }
        .commands { BBOMCommands() }
    }
}
