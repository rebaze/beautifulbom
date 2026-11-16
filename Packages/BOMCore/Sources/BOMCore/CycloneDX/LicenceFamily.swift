/// The family a licence belongs to, derived from its SPDX identifier. The SBOM does not
/// state it; the app classifies known identifiers and says "not classified" for the rest.
public enum LicenceFamily: String, Sendable, Hashable, CaseIterable {
    case permissive, weakCopyleft, strongCopyleft, unclassified
    /// The component states no licence.
    case none

    /// How much a licence asks of the code that uses it; unclassified and none are not ranked.
    private var rank: Int? {
        switch self {
        case .permissive: 0
        case .weakCopyleft: 1
        case .strongCopyleft: 2
        case .unclassified, .none: nil
        }
    }

    static let permissiveIDs: Set<String> = [
        "mit", "mit-0", "x11", "isc", "0bsd", "bsd-1-clause", "bsd-2-clause", "bsd-3-clause", "bsd-3-clause-clear",
        "bsd-2-clause-patent", "apache-1.1", "apache-2.0", "zlib", "unlicense", "cc0-1.0", "bsl-1.0", "psf-2.0",
        "python-2.0", "postgresql", "ncsa", "upl-1.0", "blueoak-1.0.0", "wtfpl", "curl", "openssl", "artistic-2.0",
        "ruby", "php-3.01", "unicode-dfs-2016", "unicode-3.0", "cc-by-4.0", "ofl-1.1", "mpl-2.0-no-copyleft-exception",
    ]
    static let weakIDs: Set<String> = [
        "lgpl-2.0", "lgpl-2.1", "lgpl-3.0", "mpl-1.1", "mpl-2.0", "epl-1.0", "epl-2.0", "cddl-1.0", "cddl-1.1",
        "cpl-1.0", "ms-rl", "lgpllr",
    ]
    static let strongIDs: Set<String> = [
        "gpl-1.0", "gpl-2.0", "gpl-3.0", "agpl-1.0", "agpl-3.0", "eupl-1.1", "eupl-1.2", "osl-3.0", "sspl-1.0",
        "cc-by-sa-4.0",
    ]
    /// Exceptions that let code link to a strong-copyleft library without taking its terms.
    static let linkingExceptions: Set<String> = [
        "classpath-exception-2.0", "gcc-exception-3.1", "llvm-exception", "openjdk-assembly-exception-1.0",
    ]

    /// The family of one identifier, ignoring case and the "-only", "-or-later" and "+" suffixes.
    static func ofIdentifier(_ id: String) -> LicenceFamily {
        var key = id.lowercased()
        for suffix in ["-only", "-or-later", "+"] where key.hasSuffix(suffix) { key.removeLast(suffix.count) }
        if permissiveIDs.contains(key) { return .permissive }
        if weakIDs.contains(key) { return .weakCopyleft }
        if strongIDs.contains(key) { return .strongCopyleft }
        return .unclassified
    }

    /// The family of a licence identifier or SPDX expression. OR takes the least demanding
    /// classified choice; AND the most demanding one (unclassified if one part is unknown and
    /// nothing is strong); WITH a linking exception lowers strong copyleft to weak.
    public static func of(_ label: String) -> LicenceFamily {
        var p = Parser(tokens: SPDX.tokens(label))
        guard let f = p.or(), p.pos == p.tokens.count else { return .unclassified }
        return f
    }

    /// A component's licences together (several entries apply together, as AND); none when it states none.
    public static func of(_ c: Component) -> LicenceFamily {
        guard !c.licenses.isEmpty else { return .none }
        return and(c.licenses.map { of($0.label) })
    }

    static func and(_ fs: [LicenceFamily]) -> LicenceFamily {
        if fs.contains(.strongCopyleft) { return .strongCopyleft }
        if fs.contains(where: { $0.rank == nil }) { return .unclassified }
        return fs.max { $0.rank! < $1.rank! } ?? .unclassified
    }

    static func or(_ fs: [LicenceFamily]) -> LicenceFamily {
        fs.filter { $0.rank != nil }.min { $0.rank! < $1.rank! } ?? .unclassified
    }

    private struct Parser {
        let tokens: [String]
        var pos = 0
        mutating func peek(_ word: String) -> Bool {
            pos < tokens.count && tokens[pos].uppercased() == word
        }
        mutating func or() -> LicenceFamily? {
            guard var parts = and().map({ [$0] }) else { return nil }
            while peek("OR") { pos += 1; guard let f = and() else { return nil }; parts.append(f) }
            return LicenceFamily.or(parts)
        }
        mutating func and() -> LicenceFamily? {
            guard var parts = with().map({ [$0] }) else { return nil }
            while peek("AND") { pos += 1; guard let f = with() else { return nil }; parts.append(f) }
            return LicenceFamily.and(parts)
        }
        mutating func with() -> LicenceFamily? {
            guard let base = atom() else { return nil }
            guard peek("WITH") else { return base }
            pos += 1
            guard pos < tokens.count else { return nil }
            let exception = tokens[pos].lowercased(); pos += 1
            return base == .strongCopyleft && LicenceFamily.linkingExceptions.contains(exception) ? .weakCopyleft : base
        }
        mutating func atom() -> LicenceFamily? {
            guard pos < tokens.count else { return nil }
            if tokens[pos] == "(" {
                pos += 1
                guard let f = or(), pos < tokens.count, tokens[pos] == ")" else { return nil }
                pos += 1
                return f
            }
            guard tokens[pos] != ")" else { return nil }
            defer { pos += 1 }
            // Free text with spaces ("Some proprietary terms") is several words: one unknown licence.
            let word = tokens[pos]
            if pos + 1 < tokens.count, !["AND", "OR", "WITH", ")"].contains(tokens[pos + 1].uppercased()) {
                pos = tokens.count - 1
                return .unclassified
            }
            return LicenceFamily.ofIdentifier(word)
        }
    }
}
