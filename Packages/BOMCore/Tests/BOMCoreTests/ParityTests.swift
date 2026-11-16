import Foundation
import Testing
@testable import BOMCore

/// The app's TR-03183-2 checks against rio's results, regenerated with
/// `make parity-refresh`. Differences are fixed in the port, never here.
@Suite struct ParityTests {
    struct Finding: Equatable, CustomStringConvertible {
        let scope: String
        let component: String?
        let missing: [String]
        var description: String { "\(scope) \(component ?? "-") \(missing)" }
    }

    static let files: [String] = {
        let dir = fixturesDirectory.appendingPathComponent("parity")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".rio.json") }.sorted()
    }()

    @Test func expectationsExist() {
        #expect(Self.files.count == 5)
    }

    @Test(arguments: files)
    func matchesRio(_ file: String) throws {
        let url = fixturesDirectory.appendingPathComponent("parity").appendingPathComponent(file)
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let input = (expected["input"] as! String).replacingOccurrences(of: "Fixtures/", with: "")
        let doc = try #require(CycloneDXDocument.recognize(fixtureTree(input)))
        let result = checkTR031832(doc)
        let inputVersion = expected["specVersionInput"] as! String
        let uplifted = CycloneDXDocument.compareVersions(inputVersion, "1.6") < 0

        // Evaluations: same rules, order and counts; specVersion judged on the file.
        let rio = (expected["evaluations"] as! [[String: Any]]).map {
            "\($0["scope"]!).\($0["requirement"]!) \($0["evaluated"]!)/\($0["failed"]!)"
        }
        let app = result.evaluations.map { e -> String in
            let failed = e.rule == RuleID(.sbom, .specVersion) && uplifted ? 0 : e.failed
            return "\(e.rule) \(e.evaluated)/\(failed)"
        }
        #expect(app == rio)
        #expect(result.evaluation("sbom.specVersion")?.failed == (uplifted ? 1 : 0))

        let levels = expected["profileLevels"] as! [String: Int]
        #expect(Dictionary(uniqueKeysWithValues: result.levels.map { ($0.key.rawValue, $0.value) }) == levels)

        let rioFindings = (expected["findings"] as! [[String: Any]]).map {
            Finding(scope: $0["scope"] as! String, component: $0["component"] as? String, missing: $0["missing"] as! [String])
        }
        #expect(Self.findings(result, droppingSpecVersion: uplifted) == rioFindings)
    }

    /// rio's gateFindings shape: one entry per document, subject and failing component.
    static func findings(_ r: ProfileResult, droppingSpecVersion: Bool) -> [Finding] {
        var out: [Finding] = []
        var key: (Scope, Int?)?
        for o in r.offenders {
            if droppingSpecVersion && o.rule == RuleID(.sbom, .specVersion) { continue }
            let k = (o.rule.scope, o.component)
            if let key, key.0 == k.0, key.1 == k.1 {
                let last = out.removeLast()
                out.append(Finding(scope: last.scope, component: last.component, missing: last.missing + [o.rule.requirement.rawValue]))
            } else {
                out.append(Finding(scope: o.rule.scope.rawValue, component: o.rule.scope == .components ? o.identity : nil,
                                   missing: [o.rule.requirement.rawValue]))
            }
            key = k
        }
        return out
    }
}
