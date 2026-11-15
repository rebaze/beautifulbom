import AppKit
import SwiftUI

/// Launch options for agents and measurements:
///   --open <path>        open a file at launch
///   --select <pointer>   select the node an RFC 6901 pointer names, once parsed
///   --copy pointer|value|source  copy the selected node, after --select
///   --appearance dark|light  force an appearance (checks without changing system settings)
///   --text-size <pt>     start with this text size (24 = presentation size)
///   --window-size <WxH>  resize the document window (points), e.g. for screenshots
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
    static let timing = ProcessInfo.processInfo.environment["BBOM_TIMING"] == "1"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        switch LaunchOptions.value("--appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

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
            if let size = LaunchOptions.windowSize,
               let window = NSApp.orderedWindows.first(where: { $0.isVisible && $0.contentView != nil }) {
                window.setContentSize(size)
            }
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
