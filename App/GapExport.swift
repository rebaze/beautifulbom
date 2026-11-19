import AppKit
import BOMCore
import CryptoKit

/// The TR-03183-2 gap list for the client: a CSV with every gap and a PDF handout that a team can
/// work through. Made locally from the open file; presence and form only, and both say so.
@MainActor
enum GapExport {
    enum Kind { case pdf, csv }

    static func sha256(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: CSV

    /// The localised words of the CSV, looked up once: a large SBOM has half a million gaps.
    struct Labels: Sendable {
        let header: [String]
        let parts: [Scope: String]
        let titles: [Requirement: String]
    }

    static func labels() -> Labels {
        Labels(header: [L("Part"), L("Component"), L("Version"), L("Package URL"), "bom-ref", L("Field"),
                        L("TR section"), L("Rule"), L("JSON Pointer")],
               parts: Dictionary(uniqueKeysWithValues: Scope.allCases.map { ($0, CompletenessView.sectionTitle($0)) }),
               titles: Dictionary(uniqueKeysWithValues: Requirement.allCases.map { ($0, CompletenessView.title($0)) }))
    }

    /// UTF-8 with a byte order mark, so spreadsheet apps read the umlauts. Off the main thread.
    nonisolated static func csv(_ list: GapList, _ labels: Labels) -> Data {
        let text = list.csv(header: labels.header, part: { labels.parts[$0] ?? $0.rawValue },
                            title: { labels.titles[$0.requirement] ?? $0.description })
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    // MARK: PDF

    /// Names of components listed per rule in the handout; the CSV has all of them.
    static let namesPerRule = 50

    static func pdf(_ a: WorkshopAnalysis, _ list: GapList, fileName: String?, sha256: String, to url: URL) -> Bool {
        let text = handout(a, list, fileName: fileName, sha256: sha256)
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595.28, height: 841.89) // A4
        info.topMargin = 56; info.bottomMargin = 56; info.leftMargin = 56; info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        // The system's header and footer: the title on each page, page numbers below.
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = true

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(text)
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let height = view.layoutManager?.usedRect(for: view.textContainer!).height ?? 100
        view.frame.size.height = ceil(height) + 8

        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = L("Gaps in the SBOM") + (fileName.map { " · \($0)" } ?? "")
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        return op.run()
    }

    private static func handout(_ a: WorkshopAnalysis, _ list: GapList, fileName: String?, sha256: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let serif = { (size: CGFloat) -> NSFont in
            let base = NSFont.systemFont(ofSize: size, weight: .semibold)
            return NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size) ?? base
        }
        func add(_ s: String, _ font: NSFont, _ colour: NSColor = .black, before: CGFloat = 0, after: CGFloat = 4) {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            p.lineHeightMultiple = 1.12
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: font, .foregroundColor: colour, .paragraphStyle: p]))
        }
        let body = NSFont.systemFont(ofSize: 10.5)
        let small = NSFont.systemFont(ofSize: 9)
        let mono = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .regular)
        let grey = NSColor(white: 0.38, alpha: 1)

        add(L("BSI TR-03183-2 2.1.0 · presence and form of fields").uppercased(), NSFont.systemFont(ofSize: 8.5, weight: .medium), grey, after: 6)
        add(L("Gaps in the SBOM"), serif(26), after: 6)
        let product = a.bom.subject.map { [ProductTitle($0.name).title, $0.version].compactMap { $0 }.joined(separator: " ") }
        add([product, fileName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), serif(14), after: 2)
        var made: [String] = []
        if let tool = a.bom.tools.first { made.append(L("made by %@", [tool.name, tool.version].compactMap { $0 }.joined(separator: " "))) }
        made.append("\(a.bom.format == .spdx ? "SPDX" : "CycloneDX") \(a.bom.specVersion.value)")
        made.append(L("listed on %@", Date().formatted(Date.FormatStyle(date: .long, time: .omitted, locale: L10n.locale))))
        add(made.joined(separator: " · "), body, grey, after: 2)
        add("SHA-256 " + sha256, mono, grey, after: 14)

        add(L("This list reports the presence and form of fields only. It does not check that values are true, and it is not a statement of conformity. Every gap names the place in the file where the field is or would be (JSON Pointer)."),
            body, after: 12)

        guard list.checked, let report = a.report, let verdict = a.verdict else {
            add(L("Not checked: this SBOM is SPDX."), serif(16), before: 4)
            return out
        }
        add(verdict.headline, serif(16), before: 4, after: 6)
        for section in report.sections where section.evaluated > 0 {
            add("\(CompletenessView.sectionTitle(section.scope)): " + L("%d of %d fields present", section.present, section.evaluated), body, after: 2)
        }
        if let gap = report.versionGap {
            add(L("This SBOM is CycloneDX %@. TR-03183-2 requires %@ or later. A conversion to %@ fixes the version; it adds none of the missing fields.",
                  gap.found, gap.required, gap.required), body, grey, before: 4)
        }

        for group in list.byRule {
            let row = report.sections.flatMap(\.rows).first { $0.rule == group.rule }
            let title = CompletenessView.title(group.rule.requirement)
            let scope = CompletenessView.sectionTitle(group.rule.scope)
            add("\(title)", serif(14), before: 14, after: 1)
            var line = [scope, group.entries.first?.section].compactMap { $0 }.joined(separator: " · ")
            if let row, group.rule.scope == .components {
                line += " · " + L("%d of %d components lack it", row.total - row.covered, row.total)
            }
            add(line, small, grey, after: 4)
            if group.rule.scope == .components {
                let names = group.entries.prefix(namesPerRule).map { [$0.name, $0.version].compactMap { $0 }.joined(separator: " ") }
                var text = names.joined(separator: ", ")
                if group.entries.count > namesPerRule {
                    text += " " + L("and %d more; the CSV lists all of them.", group.entries.count - namesPerRule)
                }
                add(text, body)
            } else {
                for e in group.entries { add(e.pointer, mono, grey) }
            }
        }
        add("Beautiful BOM \(AppName.version)", small, grey, before: 18)
        return out
    }
}
