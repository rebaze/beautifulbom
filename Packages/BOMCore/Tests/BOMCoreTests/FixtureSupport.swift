import Foundation
@testable import BOMCore

/// `Fixtures` at the repository root, found from this file's path.
let fixturesDirectory: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

func fixtureTree(_ relative: String) -> JSONTree {
    let data = try! Data(contentsOf: fixturesDirectory.appendingPathComponent(relative))
    return parseJSON(SourceDocument(bytes: Array(data)))
}

let laravelPath = "public/laravel-7.12.0.cdx-1.4.json"
let cernPath = "public/cern-lhc-vdm-editor.cdx.json"
