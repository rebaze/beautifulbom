import Foundation

/// SPDX licence identifiers and expressions, as rio checks them
/// (rio `internal/sbom/enrichment.go`, `internal/gate/spdxexpr.go`).
public enum SPDX {
    struct Lists: Sendable {
        var licences: Set<String> = []
        var exceptions: Set<String> = []
        /// Lowercased ID → listed spelling; "" when the lowercase form is ambiguous.
        var folded: [String: String] = [:]
    }

    /// The CycloneDX SPDX enum lists licences in case-insensitive order, then
    /// exceptions in the same order. Split where that order breaks, exactly
    /// once; any other layout leaves both lists empty (everything unknown).
    static let lists: Lists = {
        guard let url = Bundle.module.url(forResource: "spdx.schema", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ids = object["enum"] as? [String]
        else { return Lists() }
        var split = -1
        for i in 1..<ids.count where Array(ids[i].lowercased().utf8).lexicographicallyPrecedes(Array(ids[i - 1].lowercased().utf8)) {
            if split >= 0 { return Lists() }
            split = i
        }
        guard split >= 0 else { return Lists() }
        var lists = Lists()
        for (i, v) in ids.enumerated() {
            if i < split { lists.licences.insert(v) } else { lists.exceptions.insert(v) }
            let lower = v.lowercased()
            lists.folded[lower] = lists.folded[lower] == nil ? v : ""
        }
        return lists
    }()

    public static func isLicence(_ id: String) -> Bool { lists.licences.contains(id) }

    /// Exact spelling, or the listed spelling matched without regard to case.
    public static func isLicenceAnyCase(_ id: String) -> Bool {
        isLicence(id) || isLicence(spelling(id))
    }

    public static func isExceptionAnyCase(_ id: String) -> Bool {
        lists.exceptions.contains(id) || lists.exceptions.contains(spelling(id))
    }

    static func spelling(_ id: String) -> String { lists.folded[id.lowercased()] ?? "" }

    static let maxExpressionLength = 4096
    static let maxExpressionDepth = 64

    /// A valid SPDX licence expression with known identifiers.
    public static func isValidExpression(_ s: String) -> Bool {
        guard s.utf8.count <= maxExpressionLength else { return false }
        var parser = ExpressionParser(tokens: tokens(s))
        guard !parser.tokens.isEmpty else { return false }
        return parser.expr() && parser.pos == parser.tokens.count
    }

    static func tokens(_ s: String) -> [String] {
        var out: [String] = [], word = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "(", ")":
                if !word.isEmpty { out.append(word); word = "" }
                out.append(String(ch))
            case " ", "\t", "\n", "\r":
                if !word.isEmpty { out.append(word); word = "" }
            default:
                word.unicodeScalars.append(ch)
            }
        }
        if !word.isEmpty { out.append(word) }
        return out
    }

    struct ExpressionParser {
        let tokens: [String]
        var pos = 0
        var depth = 0

        var peek: String { pos < tokens.count ? tokens[pos] : "" }

        mutating func op(_ name: String) -> Bool {
            if peek == name || peek == name.lowercased() { pos += 1; return true }
            return false
        }

        mutating func expr() -> Bool {
            guard and() else { return false }
            while op("OR") { guard and() else { return false } }
            return true
        }

        mutating func and() -> Bool {
            guard with() else { return false }
            while op("AND") { guard with() else { return false } }
            return true
        }

        mutating func with() -> Bool {
            let t = peek
            if t == "(" {
                pos += 1
                depth += 1
                guard depth <= SPDX.maxExpressionDepth, expr(), peek == ")" else { return false }
                depth -= 1
                pos += 1
                return true
            }
            guard t != "", t != ")", !SPDX.isOperator(t), SPDX.validLicenceID(t) else { return false }
            pos += 1
            if op("WITH") {
                let e = peek
                guard e != "", !SPDX.isOperator(e), SPDX.validIDChars(e), SPDX.isExceptionAnyCase(e) else { return false }
                pos += 1
            }
            return true
        }
    }

    static func isOperator(_ t: String) -> Bool {
        ["AND", "OR", "WITH", "and", "or", "with"].contains(t)
    }

    static func validLicenceID(_ t: String) -> Bool {
        if validLicenseRef(t) { return true }
        if let colon = t.firstIndex(of: ":"), t.hasPrefix("DocumentRef-") {
            let doc = t[t.index(t.startIndex, offsetBy: 12)..<colon]
            return validIDChars(String(doc)) && validLicenseRef(String(t[t.index(after: colon)...]))
        }
        let id = t.hasSuffix("+") ? String(t.dropLast()) : t
        return validIDChars(id) && isLicenceAnyCase(id)
    }

    static func validLicenseRef(_ t: String) -> Bool {
        t.hasPrefix("LicenseRef-") && validIDChars(String(t.dropFirst(11)))
    }

    /// A nonempty run of [A-Za-z0-9.-].
    static func validIDChars(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { c in
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 46 || c == 45
        }
    }
}
