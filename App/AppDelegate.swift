import AppKit
import SwiftUI

/// Launch options for agents and measurements:
///   --open <path>        open a file at launch
///   --select <pointer>   select the node an RFC 6901 pointer names, once parsed
///   --copy pointer|value|source  copy the selected node, after --select
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
    static let timing = ProcessInfo.processInfo.environment["BBOM_TIMING"] == "1"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = LaunchOptions.openPath else { return }
        let url = URL(fileURLWithPath: path)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                FileHandle.standardError.write(Data("open failed: \(error.localizedDescription)\n".utf8))
                if LaunchOptions.snapshotPath != nil { exit(3) }
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}

@MainActor
enum Snapshot {
    /// Renders the front document window into `path` and quits. Needs no
    /// Screen Recording permission, so agents can check visuals.
    static func take(to path: String, after delay: Duration = .milliseconds(1200)) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard let window = NSApp.orderedWindows.first(where: { $0.isVisible && $0.contentView != nil }),
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
