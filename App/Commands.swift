import AppKit
import SwiftUI

extension FocusedValues {
    @Entry var documentModel: DocumentModel?
}

struct BBOMCommands: Commands {
    @FocusedValue(\.documentModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Beautiful BOM") { About.show() }
        }
        CommandGroup(after: .windowArrangement) {
            Button("Welcome to Beautiful BOM") { Welcome.show() }
                .keyboardShortcut("1", modifiers: [.command, .shift])
        }
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
            Button(model?.drawerPinned == true ? "Let Evidence Close" : "Keep Evidence Open") { model?.toggleDrawerPinned() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(model?.analysis == nil)
            Divider()
        }
        CommandGroup(after: .sidebar) {
            Picker("Language", selection: Binding(get: { LanguageSettings.shared.language },
                                                  set: { LanguageSettings.shared.language = $0 })) {
                Text("System").tag(AppLanguage.system)
                Text("English").tag(AppLanguage.en)
                Text("Deutsch").tag(AppLanguage.de)
            }
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy JSON Pointer") { model?.copy(.pointer) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model?.selection == nil)
            Button("Copy Value") { model?.copy(.value) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model?.selection == nil)
            Button("Copy Source") { model?.copy(.source) }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(model?.selection == nil)
        }
        // Edit › Find, as in every Mac app, but reachable from every tab: each item
        // switches to Source and works on its find bar (a read-only file: no Replace).
        CommandGroup(replacing: .textEditing) {
            Menu("Find") {
                findButton("Find…", .showFindInterface, "f")
                findButton("Find Next", .nextMatch, "g")
                findButton("Find Previous", .previousMatch, "g", [.command, .shift])
                findButton("Use Selection for Find", .setSearchString, "e")
            }
        }
        CommandMenu("Go") {
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(model?.canGoBack ?? false))
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(model?.canGoForward ?? false))
        }
    }

    private func findButton(_ title: String, _ action: NSTextFinder.Action, _ key: KeyEquivalent,
                            _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { model?.find(action) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(model?.isLoaded != true)
    }
}
