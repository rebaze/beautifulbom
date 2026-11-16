import AppKit
import SwiftUI

/// The app's name as it is set wherever it appears in a window.
enum AppName {
    static let text = "Beautiful BOM"
    static func font(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    /// The icon from the bundle's own file: the system's copy arrives asynchronously, a placeholder first.
    @MainActor static var icon: NSImage { Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
}

/// The rebaze mark and the app's name, quiet, at the right of the tab bar. Opens About.
struct Wordmark: View {
    let scale: CGFloat

    var body: some View {
        Button { About.show() } label: {
            HStack(spacing: 6 * scale) {
                Image("RebazeMark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 14 * scale)
                Text(AppName.text).font(AppName.font(14 * scale))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("About Beautiful BOM"))
        .accessibilityLabel(L("About Beautiful BOM"))
    }
}

/// The standard About panel: icon, name, version, by rebaze, and the licences of the samples.
@MainActor
enum About {
    static var credits: NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centered]
        let text = NSMutableAttributedString(string: L("A reader for bills of materials, software and AI, by rebaze.") + "\n", attributes: base)
        var link = base
        link[.link] = URL(string: "https://rebaze.de")!
        text.append(NSAttributedString(string: "rebaze.de", attributes: link))
        text.append(NSAttributedString(string: "\n\n" + L("Samples: Laravel and CERN from CycloneDX bom-examples (CC0 1.0); cart-api from rio (Apache License 2.0); zephyr-7b-beta AIBOMs from public Hugging Face metadata, one written by the OWASP AIBOM Generator (Apache License 2.0), one by rebaze."), attributes: base))
        return text
    }

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppName.text, .applicationIcon: AppName.icon, .credits: credits])
    }
}

// MARK: Welcome

/// A file the welcome window offers: a recent file or a bundled sample.
struct WelcomeItem: Identifiable {
    let url: URL
    let title: String
    let detail: String
    var id: URL { url }
}

/// The window shown when the app starts without a file, or when the Dock icon is
/// clicked with no window open; it replaces the bare Open panel.
@MainActor
enum Welcome {
    private static var window: NSWindow?

    static func show() {
        if let w = window {
            // Rebuilt on every show, so the recent files are current.
            w.contentView = NSHostingView(rootView: WelcomeView())
        } else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 480),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.title = L("Welcome to Beautiful BOM")
            w.contentView = NSHostingView(rootView: WelcomeView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func close() { window?.orderOut(nil) }

    static func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    static var samples: [WelcomeItem] {
        [("laravel-7.12.0.cdx-1.4", "json", "Laravel 7.12", L("62 components · CycloneDX 1.4")),
         ("cern-lhc-vdm-editor.cdx", "json", "CERN LHC VdM Editor", "CycloneDX 1.2"),
         ("bsi-pass.cdx", "json", "cart-api", L("CycloneDX 1.6 · every TR-03183-2 field present")),
         ("zephyr-7b-beta.reference.aibom", "json", "zephyr-7b-beta", L("AIBOM · hand-made reference, the standard used fully")),
         ("zephyr-7b-beta.generated.aibom", "json", "zephyr-7b-beta", L("AIBOM · as the OWASP AIBOM Generator writes it"))]
            .compactMap { name, ext, title, detail in
                Bundle.main.url(forResource: name, withExtension: ext).map { WelcomeItem(url: $0, title: title, detail: detail) }
            }
    }

    /// Recent files that still exist, without the bundled samples.
    static var recents: [WelcomeItem] {
        let samplePaths = Set(samples.map(\.url.standardizedFileURL.path))
        return NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) && !samplePaths.contains($0.standardizedFileURL.path) }
            .prefix(5)
            .map { WelcomeItem(url: $0, title: $0.lastPathComponent,
                               detail: ($0.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath) }
    }
}

struct WelcomeView: View {
    @State private var targeted = false
    private let recents = Welcome.recents
    private let samples = Welcome.samples

    var body: some View {
        HStack(spacing: 0) {
            intro
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            files
                .frame(width: 320)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.background.secondary)
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var intro: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            Image(nsImage: AppName.icon)
                .resizable()
                .frame(width: 128, height: 128)
            Text(AppName.text)
                .font(AppName.font(36))
                .padding(.top, 6)
            Text(L("A reader for bills of materials: software and AI."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text(L("Version %@", AppName.version))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            dropArea
                .padding(.top, 28)
            Spacer(minLength: 20)
            HStack(spacing: 5) {
                Image("RebazeMark").resizable().scaledToFit().frame(height: 11)
                Text(L("by rebaze"))
            }
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 40)
    }

    /// „Open an SBOM…“ inside an area that also takes a dropped file.
    private var dropArea: some View {
        VStack(spacing: 10) {
            Button { NSDocumentController.shared.openDocument(nil) } label: {
                Label(L("Open an SBOM…"), systemImage: "doc.badge.plus")
                    .padding(.horizontal, 6)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            Text(targeted ? L("Drop to open") : L("or drop a CycloneDX JSON file here"))
                .font(.callout)
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
        }
        .frame(maxWidth: 360)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(targeted ? Color.accentColor : Color(nsColor: .separatorColor),
                              style: StrokeStyle(lineWidth: targeted ? 2.5 : 1.5, dash: [7, 5]))
                .background(RoundedRectangle(cornerRadius: 14).fill(targeted ? Color.accentColor.opacity(0.06) : .clear))
        }
        .dropDestination(for: URL.self) { urls, _ in DropToOpen.open(urls) } isTargeted: { targeted = $0 }
    }

    private var files: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if !recents.isEmpty {
                    section(L("Recent"), recents)
                }
                section(L("Samples"), samples)
            }
            .padding(.horizontal, 10)
            .padding(.top, 36)
            .padding(.bottom, 16)
        }
    }

    private func section(_ title: String, _ items: [WelcomeItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(items) { WelcomeRow(item: $0) }
        }
    }
}

private struct WelcomeRow: View {
    let item: WelcomeItem
    @State private var hovered = false

    var body: some View {
        Button { Welcome.open(item.url) } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovered ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(item.url.path)
    }
}
