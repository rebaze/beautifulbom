import BOMCore
import SwiftUI

/// Looks a workshop string up in the current language (English source text is the key).
/// Placeholders follow String(format:): %@ for text, %d for numbers.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.lookup(key)
    return args.isEmpty ? format : String(format: format, locale: L10n.locale, arguments: args)
}

enum L10n {
    static func lookup(_ key: String) -> String { key }
    static var locale: Locale { .current }
}

/// Type and spacing for the workshop views, scaled by presentation size.
struct Typo {
    let s: CGFloat
    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size * s, weight: weight) }
    func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size * s, weight: weight, design: .monospaced) }
    func pad(_ v: CGFloat) -> CGFloat { v * s }
}

/// A small coloured label: a gap in red, a present field in green.
struct Pill: View {
    enum Kind { case gap, ok, neutral }
    let text: String
    let kind: Kind
    let t: Typo

    var body: some View {
        Text(text)
            .font(t.font(12, .medium))
            .padding(.horizontal, t.pad(8))
            .padding(.vertical, t.pad(2))
            .foregroundStyle(colour)
            .background(Capsule().fill(colour.opacity(0.12)))
    }

    private var colour: Color {
        switch kind {
        case .gap: .red
        case .ok: .green
        case .neutral: .secondary
        }
    }
}

/// An eyebrow: small, spaced capitals above a title.
struct Eyebrow: View {
    let text: String
    let t: Typo
    var body: some View {
        Text(text.uppercased())
            .font(t.font(11, .medium))
            .tracking(0.8 * t.s)
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// The quiet panel behind stats and sections.
    func panel(_ t: Typo, tint: Color? = nil) -> some View {
        padding(t.pad(14))
            .background(RoundedRectangle(cornerRadius: 12 * t.s, style: .continuous)
                .fill(tint.map { $0.opacity(0.10) } ?? Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12 * t.s, style: .continuous)
                .strokeBorder(tint.map { $0.opacity(0.35) } ?? .clear, lineWidth: 1))
    }
}

extension Verdict {
    /// The one sentence about Completeness, e.g. "Not ready for TR-03183-2. Gaps: format version 1.4, timestamp, manufacturer, +4 more."
    var headline: String {
        ready ? L("All TR-03183-2 fields present in the required form.") : L("Not ready for TR-03183-2.")
    }

    var gapList: String? {
        guard !ready else { return nil }
        var parts: [String] = []
        if let v = versionGap { parts.append(L("format version %@", v)) }
        parts += gaps.map(\.label)
        let shown = parts.prefix(4)
        let more = parts.count - shown.count
        var text = L("Gaps: %@", shown.joined(separator: ", "))
        if more > 0 { text += ", " + L("+%d more", more) }
        return text + "."
    }
}

extension GapTopic {
    var label: String {
        switch self {
        case .timestamp: L("timestamp")
        case .manufacturer: L("manufacturer")
        case .hashes: L("SHA-512 hashes")
        case .licences: L("concluded licences")
        case .dependencies: L("dependency coverage")
        case .fileProperties: L("file properties")
        case .identity: L("names and versions")
        case .vulnerabilities: L("vulnerabilities listed in the SBOM")
        }
    }
}

/// A horizontal separator line, whatever the surrounding stack.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1).frame(maxWidth: .infinity)
    }
}
