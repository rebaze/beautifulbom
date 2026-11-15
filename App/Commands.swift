import SwiftUI

extension FocusedValues {
    @Entry var documentModel: DocumentModel?
}

struct BBOMCommands: Commands {
    @FocusedValue(\.documentModel) private var model

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Bigger") { model?.biggerText() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(model == nil)
            Button("Smaller") { model?.smallerText() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model == nil)
            Button("Actual Size") { model?.actualSizeText() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(model == nil)
            Button("Presentation Size") { model?.togglePresentationSize() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(model == nil)
            Divider()
        }
    }
}
