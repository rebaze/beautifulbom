import AppKit
import SwiftUI

/// Launch options for agents and measurements:
///   --open <path>        open a file at launch
///   --select <pointer>   select the node an RFC 6901 pointer names, once parsed
///   --copy pointer|value|source  copy the selected node, after --select
///   --appearance dark|light  force an appearance (checks without changing system settings)
///   --text-size <pt>     start with this text size (24 = presentation size)
///   --window-size <WxH>  resize the document window (points), e.g. for screenshots
///   --view <tab>         open a tab: overview, composition, completeness, components, source
///   --component <ref>    open the component page for a bom-ref
///   --evidence <rule>    show the first offender of a rule (e.g. sbom.timestamp) in the drawer
///   --language de|en     show the workshop views in this language (not saved)
///   --point <bom-ref>    on the map, show a part as if the pointer were on it
///   --find <text>        open the find bar from the current tab and type <text> into it
///   --show welcome|about show the welcome window (the default without --open) or About
///   --snapshot <png>     render the front window into a PNG, then quit
///   BBOM_TIMING=1        print open→parsed and open→first layout times
enum LaunchOptions {
    static let arguments = CommandLine.arguments

    static func value(_ flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static let openPath = value("--open")
    static let selectPointer = value("--select")
    static let snapshotPath = value("--snapshot")
    static let copyKind: CopyKind? = switch value("--copy") {
    case "pointer": .pointer
    case "value": .value
    case "source": .source
    default: nil
    }
    static let textSize = value("--text-size").flatMap(Double.init).map { CGFloat($0) }
    static let windowSize: NSSize? = value("--window-size").flatMap { spec in
        let parts = spec.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? NSSize(width: parts[0], height: parts[1]) : nil
    }
    static let view = value("--view")
    static let component = value("--component")
    static let evidence = value("--evidence")
    static let find = value("--find")
    static let point = value("--point")
    // A value, not a bare switch: AppKit reads options as pairs and would open a lone path as a file.
    static let welcome = value("--show") == "welcome"
    static let about = value("--show") == "about"
    static let timing = ProcessInfo.processInfo.environment["BBOM_TIMING"] == "1"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The welcome window replaces the Open panel a document app shows at launch.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
        switch LaunchOptions.value("--appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if LaunchOptions.about {
            About.show()
            if let path = LaunchOptions.snapshotPath { Snapshot.take(to: path) }
            return
        }
        guard let path = LaunchOptions.openPath else {
            // A plain launch, not one to open a file from Finder or the Dock.
            let plain = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
            if plain || LaunchOptions.welcome {
                Welcome.show()
                if let path = LaunchOptions.snapshotPath { Snapshot.take(to: path) }
            }
            return
        }
        let url = URL(fileURLWithPath: path)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                FileHandle.standardError.write(Data("open failed: \(error.localizedDescription)\n".utf8))
                if LaunchOptions.snapshotPath != nil { exit(3) }
            }
        }
    }

    /// The Dock icon clicked with no window open: the welcome window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        // A minimised document comes back first, as in every document app; the welcome window otherwise.
        if let minimised = NSApp.windows.first(where: { $0.isMiniaturized }) {
            minimised.deminiaturize(nil)
        } else {
            Welcome.show()
        }
        return false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}

@MainActor
enum Snapshot {
    /// The front document window; not the find bar's overlay, which is a window of its own.
    static var documentWindow: NSWindow? {
        // orderedWindows leaves out panels such as About.
        (NSApp.orderedWindows + NSApp.windows).first { $0.isVisible && $0.contentView != nil && $0.styleMask.contains(.titled) && $0.parent == nil }
    }

    /// Renders the front document window into `path` and quits. Needs no
    /// Screen Recording permission, so agents can check visuals.
    static func take(to path: String, after delay: Duration = .milliseconds(1200)) {
        Task { @MainActor in
            if let size = LaunchOptions.windowSize,
               let window = documentWindow {
                window.setContentSize(size)
            }
            try? await Task.sleep(for: delay)
            guard let window = documentWindow,
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(4) }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(5) }
            do {
                try png.write(to: URL(fileURLWithPath: path))
                exit(0)
            } catch {
                exit(6)
            }
        }
    }
}
