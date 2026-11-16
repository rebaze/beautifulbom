import Foundation

/// rio's field checks (`internal/gate/profile_fields.go`) over the tree. A value
/// of the wrong shape reads as absent; duplicate keys resolve to the last one.
struct FieldChecks {
    let tree: JSONTree

    func string(_ object: NodeID?, _ key: String) -> String? {
        guard let object else { return nil }
        return tree.memberString(object, key)
    }

    /// A manufacturer object with a contact email that has text on both sides
    /// of an "@", or an absolute http(s) URL with a host.
    func validCreator(_ v: NodeID?) -> Bool {
        guard let v, tree.kind(v) == .object else { return false }
        for c in tree.objectElements(tree.member(v, "contact")) {
            if let raw = tree.memberString(c, "email") {
                let email = Array(TR031832.trim(raw).utf8)
                if let at = email.firstIndex(of: UInt8(ascii: "@")), at > 0, at < email.count - 1 { return true }
            }
        }
        return tree.elements(tree.member(v, "url")).contains { tree.string($0).map(Self.absoluteHTTP) ?? false }
    }

    static func absoluteHTTP(_ s: String) -> Bool {
        guard let u = URLComponents(string: TR031832.trim(s)), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return !(u.host ?? "").isEmpty
    }

    /// The values of every property called `name` (nil for a property without a value).
    func properties(_ obj: NodeID, _ name: String) -> [NodeID?] {
        tree.objectElements(tree.member(obj, "properties"))
            .filter { tree.memberString($0, "name") == name }
            .map { tree.member($0, "value") }
    }

    func validFilename(_ obj: NodeID) -> Bool {
        let values = properties(obj, "bsi:component:filename")
        guard values.count == 1, let s = tree.string(values[0]) else { return false }
        return !TR031832.blank(s) && !s.contains("/") && !s.contains("\\")
    }

    func oneProperty(_ obj: NodeID, _ name: String, _ allowed: [String]) -> Bool {
        let values = properties(obj, name)
        guard values.count == 1, let s = tree.string(values[0]) else { return false }
        return allowed.contains(s)
    }

    /// Any SHA-512 of 128 hex characters on a distribution reference.
    func validDeployableHash(_ obj: NodeID) -> Bool {
        for ref in tree.objectElements(tree.member(obj, "externalReferences")) where tree.memberString(ref, "type") == "distribution" {
            for h in tree.objectElements(tree.member(ref, "hashes")) {
                if tree.memberString(h, "alg") == "SHA-512", let c = tree.memberString(h, "content"), Self.validHex(c, 128) { return true }
            }
        }
        return false
    }

    /// A concluded licence in SPDX form; a name or text alone never counts (§6.1).
    func validLicences(_ obj: NodeID) -> Bool {
        for e in tree.objectElements(tree.member(obj, "licenses")) {
            if let expr = tree.memberString(e, "expression"), tree.memberString(e, "acknowledgement") == "concluded",
               SPDX.isValidExpression(expr) { return true }
            if let l = tree.member(e, "license"), tree.kind(l) == .object, tree.memberString(l, "acknowledgement") == "concluded",
               let id = tree.memberString(l, "id"), SPDX.isLicence(id) { return true }
        }
        return false
    }

    static func validHex(_ s: String, _ n: Int) -> Bool {
        s.utf8.count == n && s.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) || ($0 >= 65 && $0 <= 70) }
    }

    /// RFC 3339 as Go's `time.Parse(time.RFC3339, s)` accepts it: four-digit
    /// year, two-digit month and day (calendar-valid), `T`, a one- or two-digit
    /// hour, two-digit minute and second, an optional `.` or `,` fraction, then
    /// `Z` or a ±hh:mm offset (hour ≤ 24, minute ≤ 60).
    static func validTimestamp(_ s: String) -> Bool {
        let b = Array(s.utf8)
        var i = 0
        func digits(_ n: Int) -> Int? {
            guard i + n <= b.count else { return nil }
            var v = 0
            for k in 0..<n {
                let c = b[i + k]
                guard c >= 48 && c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            i += n
            return v
        }
        func expect(_ c: Character) -> Bool {
            guard i < b.count, b[i] == c.asciiValue! else { return false }
            i += 1
            return true
        }
        func isDigit(_ k: Int) -> Bool { k < b.count && b[k] >= 48 && b[k] <= 57 }
        guard let year = digits(4), expect("-"), let month = digits(2), expect("-"), let day = digits(2), expect("T") else { return false }
        guard (1...12).contains(month), day >= 1, day <= daysIn(month, year) else { return false }
        let hourDigits = isDigit(i + 1) ? 2 : 1
        guard let hour = digits(hourDigits), hour < 24, expect(":"), let minute = digits(2), minute < 60,
              expect(":"), let second = digits(2), second < 60 else { return false }
        if i < b.count, b[i] == UInt8(ascii: ".") || b[i] == UInt8(ascii: ",") {
            guard isDigit(i + 1) else { return false }
            i += 1
            while isDigit(i) { i += 1 }
        }
        if i < b.count, b[i] == UInt8(ascii: "Z") { return i + 1 == b.count }
        guard i < b.count, b[i] == UInt8(ascii: "+") || b[i] == UInt8(ascii: "-") else { return false }
        i += 1
        guard let oh = digits(2), oh <= 24, expect(":"), let om = digits(2), om <= 60 else { return false }
        return i == b.count
    }

    static func daysIn(_ month: Int, _ year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}
