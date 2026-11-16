# Beautiful BOM workshop views: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the JSON reader into a workshop tool: Overview, Composition, Completeness and Components views over a CycloneDX SBOM, each statement backed by evidence in a source drawer, with BSI TR-03183-2 2.1.0 checks that give rio's results.

**Architecture:** A CycloneDX layer in BOMCore reads the existing `JSONTree` (no second parse): model, dependency graph, aggregates, a port of rio's TR-03183-2 profile and a presentation model (rows, verdict, filters) with no UI types. The app adds a tab bar, SwiftUI views with Swift Charts and an evidence drawer that reuses `SourceTextView`. Everything a view says carries an `Evidence` value (a node, or an absent key with its insertion offset).

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing, SwiftUI + Swift Charts, AppKit/TextKit 2 (existing source view), xcodegen, String Catalog. rio 0.10.2 (Homebrew) only to regenerate parity expectations.

**Spec:** `apps/beautiful-bom/docs/design-workshop-views.md` (approved by Toni, 2026-11-15). Background: `docs/design.md` (JSON reader), `docs/findings.md`.

## Global Constraints

- Self-contained in `apps/beautiful-bom/`: no code, script or test reads a path outside this folder. rio is the port source and a tool for `make parity-refresh` only; the committed parity expectations make `make test` independent of it.
- BOMCore: no dependencies, platforms `.macOS(.v15), .iOS(.v18)`, no AppKit/SwiftUI imports. Presentation logic (verdict, rows, filters) lives in BOMCore so it is tested; the app only lays it out and localises it.
- The original bytes stay authoritative: every statement is backed by `Evidence` (`.located(NodeID)` or `.absent(Absent)`); nothing is inferred from text the parser did not read.
- Recognised: root object, `bomFormat` == "CycloneDX", `specVersion` dotted decimal ≥ 1.2 (1.7 and later included). Anything else opens the Source tab only.
- Completeness is TR-03183-2 2.1.0 always, counted exactly as rio's `bsi-tr-03183-2@2.1.0` counts (with `gate.require: [name, version]`), except `sbom.specVersion`, which the app judges on the file as it is.
- Wording: presence and form only. Never "compliant", "conformant", "certified" in any string (a test greps the String Catalog). Industry terms in English in German copy (SBOM, Finding, Dependency, Hash, Supplier).
- Version-gap line (English source, verbatim): "This SBOM is CycloneDX {found}. TR-03183-2 requires 1.6 or later. A conversion to 1.6 fixes the version; it adds none of the missing fields."
- Field note (verbatim): "field introduced in CycloneDX {version}". Versions from the CycloneDX schemas: `creator` 1.6, `distributionLicences` 1.6, `dependencies` 1.3, `filename`/`executable`/`archive`/`structured` 1.3, `deployableHash` 1.3; all others none.
- Verdict when everything passes (verbatim): "All TR-03183-2 fields present in the required form."
- No network, no file writes outside the user's explicit save, no customer SBOMs in `Fixtures/`.
- Build checks use make's exit status, never a grep of xcbeautify output. Measurements in `CONFIG=Release`.
- Commits: no `Co-Authored-By`, no AI attribution. If 1Password signing fails, commit with `--no-gpg-sign`.

## Review Focus

1. **Duplicate keys** (`"manufacturer"` twice on one component): rio's Go decoder keeps the last occurrence; the app's checks must too, and the evidence must point at that last occurrence. Pinned in Task 1 and in the parity edge fixture (Task 8).
2. **A file with parse errors that is still CycloneDX** (`Fixtures/edge/cyclonedx-broken.json`, Task 9): rio would refuse it; the app shows the views for what it could read and Completeness says so above the rows ("The file has N errors; results cover what could be read"). Pinned in Task 9.
3. **Values of the wrong type** (`"version": 1.2` as a number, `"licenses": {}` as an object, a non-object entry in `components`): read as absent, never a crash; a non-object component entry still counts as a component with every field missing, as in rio. Pinned in Tasks 3 and 7.
4. **Large SBOMs** (the 50 MB generated file with a dependency graph): the CycloneDX layer, graph and checks add at most about one second over the parse (Release), off the main thread; the Components list stays lazy. Pinned in Task 16.
5. **Edge forms rio accepts differently from a naive port**: timestamps with fractional seconds or `+01:00` offsets (pass) versus `2020-13-01T00:00:00Z` or a missing `T` (fail); manufacturer URL `https://` without host (fail); SPDX expressions in lower-case operators (`mit or apache-2.0`, pass), `WITH` exceptions, `LicenseRef-`, trailing `+`. Pinned in Tasks 6 and 7 and in the parity edge fixture.

---

### Task 1: Tree access helpers

**Files:**
- Create: `Packages/BOMCore/Sources/BOMCore/CycloneDX/TreeAccess.swift`
- Test: `Packages/BOMCore/Tests/BOMCoreTests/TreeAccessTests.swift`

**Interfaces:**
- Consumes: `JSONTree.kind/children/key(_:)/decodedValue(_:)/valueRange(_:)`.
- Produces (all `public`, in `extension JSONTree`):
  - `func member(_ object: NodeID, _ key: String) -> NodeID?` — the **last** member with that key (Go `encoding/json` semantics); nil if `object` is not an object.
  - `func string(_ n: NodeID?) -> String?` — decoded value when the node is a string, else nil.
  - `func memberString(_ object: NodeID, _ key: String) -> String?`
  - `func elements(_ n: NodeID?) -> [NodeID]` — children of an array, else `[]`.
  - `func objectElements(_ n: NodeID?) -> [NodeID]` — the object children of an array, else `[]`.
  - `func keys(_ object: NodeID) -> [String]` — member keys in document order, duplicates kept.

- [ ] **Step 1: Write the failing tests** (`tree(_ json: String) -> JSONTree` helper as in ParserTests):
  - `memberReturnsLastDuplicate`: `{"a":1,"a":"x"}` → `string(member(root,"a"))` == "x".
  - `memberOnArrayIsNil`: `[1]` → `member(root,"a")` == nil.
  - `stringOfNumberIsNil`: `{"version":1.2}` → `memberString(root,"version")` == nil.
  - `objectElementsSkipsNonObjects`: `{"c":[{"n":1},"s",2,{"n":2}]}` → count 2.
  - `elementsOfObjectIsEmpty`: `{"licenses":{}}` → `elements(member(root,"licenses"))` == [].
  - `decodesEscapes`: `{"n":"aé\"b"}` → "aé\"b".
- [ ] **Step 2: Run** `make test` — Expected: FAIL, `member` not found.
- [ ] **Step 3: Implement** the extension. `member` scans `children(object)` and keeps the last match by `key(_:)`.
- [ ] **Step 4: Run** `make test` — Expected: all tests pass (35 existing + 6 new).
- [ ] **Step 5: Commit** `git add Packages/BOMCore && git commit -m "Add key lookup helpers to the JSON tree"`

### Task 2: Evidence and package URLs

**Files:**
- Create: `Packages/BOMCore/Sources/BOMCore/CycloneDX/Evidence.swift`, `Packages/BOMCore/Sources/BOMCore/CycloneDX/PackageURL.swift`
- Test: `Packages/BOMCore/Tests/BOMCoreTests/EvidenceTests.swift`

**Interfaces:**
- Produces:
  - `public struct Located<Value: Sendable & Hashable>: Sendable, Hashable { public let value: Value; public let node: NodeID }`
  - `public struct Absent: Sendable, Hashable { public let parent: NodeID; public let key: String; public let insertion: ByteOffset }` with `public init(parent: NodeID, key: String, in tree: JSONTree)`; `insertion` = `tree.valueRange(parent).lowerBound + 1` (just after `{`).
  - `public enum Evidence: Sendable, Hashable { case located(NodeID); case absent(Absent) }`
  - `extension JSONTree { public func evidence(_ object: NodeID, _ key: String) -> Evidence }` — `.located(member)` if present, else `.absent(Absent(parent: object, key: key, in: self))`.
  - `public struct PackageURL: Sendable, Hashable { type, namespace: String?, name, version: String?, qualifiers: [String: String], subpath: String? }` with `public static func parse(_ s: String) -> PackageURL?` (purl spec: `pkg:` scheme, type lower-cased, percent-decoding of every component, `@` version split from the right of the name segment).

- [ ] **Step 1: Write the failing tests:**
  - `absentTimestampSitsOnMetadataLine`: Laravel fixture; `Absent(parent: member(root,"metadata")!, key: "timestamp", in:)`; `source.lineColumn(of: insertion).line` == 6.
  - `evidenceLocatedWhenPresent`: CERN; `evidence(metadata,"timestamp")` == `.located(...)` and its string is "2020-08-03T01:28:52.765Z".
  - `purlComposer`: "pkg:composer/doctrine/lexer@1.2.3" → type "composer", namespace "doctrine", name "lexer", version "1.2.3".
  - `purlScopedNpm`: "pkg:npm/%40angular/core@16.0.0?arch=x64#src" → namespace "@angular", name "core", qualifiers ["arch": "x64"], subpath "src".
  - `purlRejectsNonPkg`: "https://x" → nil; "pkg:" → nil.
- [ ] **Step 2: Run** `make test` — Expected: FAIL, types missing.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run** `make test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Add evidence values and package URL parsing"`

### Task 3: CycloneDX recognition and model

**Files:**
- Create: `Packages/BOMCore/Sources/BOMCore/CycloneDX/CycloneDXDocument.swift`, `.../CycloneDX/Component.swift`
- Create: `Fixtures/synthetic/nested-1.6.cdx.json` (written by hand: specVersion "1.6", `metadata.tools` in the 1.5+ object form with one `components` entry, `metadata.manufacturer`, a subject with one nested component, a top-level component with two nested components, one entry in `components` that is the string `"oops"`, one component with `"version": 1.2`, one with `"licenses": {}`, one with `licenses` holding `{"expression":"MIT OR Apache-2.0","acknowledgement":"concluded"}`)
- Test: `Packages/BOMCore/Tests/BOMCoreTests/CycloneDXModelTests.swift`

**Interfaces:**
- Consumes: Task 1 helpers, Task 2 types.
- Produces:
  - `public struct CycloneDXDocument: Sendable { public let tree: JSONTree; public let root: NodeID; public let specVersion: Located<String>; public let metadata: NodeID?; public let timestamp: Located<String>?; public let tools: [Tool]; public let subject: Component?; public let components: [Component]; public static func recognize(_ tree: JSONTree) -> CycloneDXDocument? }`. `components` holds every component except the subject, in rio's `ProfileComponents` order: the subject's nested components (recursive, pre-order), then `components` (recursive, pre-order).
  - `public static func compareVersions(_ a: String, _ b: String) -> Int` (rio's `compareSpecVersions`: dotted, a non-numeric segment sorts after every number) and `public static func isDottedDecimal(_ v: String) -> Bool`.
  - `public struct Tool: Sendable, Hashable { vendor: String?, name: String?, version: String?, node: NodeID }` — from the ≤1.4 array form, and from the 1.5+ object form (`components` and `services`).
  - `public struct Component: Sendable, Hashable { node: NodeID?; path: String; isSubject: Bool; bomRef, type, group, name, version, purl, description, author: String?; packageURL: PackageURL?; licenses: [License]; hashes: [Hash]; externalReferences: [ExternalReference]; properties: [Property]; supplierName, manufacturerName: String?; unknownKeys: [String] }`. `node` is nil only for a non-object entry. `path` uses rio's form (`metadata.component`, `components[3].components[0]`, `metadata.component.components[0]`). String fields come from `memberString` (wrong type → nil).
  - `public struct License: Sendable, Hashable { enum Kind { case id(String), name(String), expression(String) }; kind: Kind; acknowledgement: String?; node: NodeID }`
  - `public struct Hash: Sendable, Hashable { alg: String?, content: String?, node: NodeID }`
  - `public struct ExternalReference: Sendable, Hashable { type: String?, url: String?, hashes: [Hash], node: NodeID }`
  - `public struct Property: Sendable, Hashable { name: String?, value: String?, node: NodeID }`
  - `public var displayName: String` on Component: `group/name` when both, else name, else the path.
  - Known keys for `unknownKeys`: the CycloneDX 1.6 component properties (`type, mime-type, bom-ref, supplier, manufacturer, authors, author, publisher, group, name, version, description, scope, hashes, licenses, copyright, cpe, purl, omniborId, swhid, swid, modified, pedigree, externalReferences, properties, components, evidence, releaseNotes, modelCard, data, cryptoProperties, tags, signature`).

- [ ] **Step 1: Write the failing tests:**
  - `laravelRecognised`: specVersion "1.4"; subject name "cyclonedx-php-composer-demo", version "dev-master", type "application"; 62 components; tools == [cyclonedx/cyclonedx-php-composer/in-dev]; timestamp nil.
  - `laravelLexer`: the component with name "lexer" has group "doctrine", purl type "composer", licenses [.id("MIT")], 3 external references, path "components[\(i)]" for its index.
  - `cernRecognised`: specVersion "1.2"; 43 components; each has one hash with alg "SHA-512"; timestamp "2020-08-03T01:28:52.765Z".
  - `nestedOrderMatchesRio`: synthetic file; paths in order: subject's nested first ("metadata.component.components[0]"), then "components[0]", "components[0].components[0]", "components[0].components[1]", …; the `"oops"` entry is present with `node == nil`.
  - `wrongTypesReadAsAbsent`: `"version": 1.2` → version nil; `"licenses": {}` → licenses [].
  - `toolsObjectForm`: synthetic file → one tool from `tools.components`.
  - `notCycloneDX`: `Fixtures/edge/duplicates.json` → nil; `{"bomFormat":"SPDX","specVersion":"2.3"}` → nil; `{"bomFormat":"CycloneDX","specVersion":"1.1"}` → nil; `"1.7"` → recognised; `"1.x"` → nil.
  - `compareVersionsLikeRio`: ("1.10","1.6") → 1; ("1.6","1.6.0") → 0; ("1.x","1.6") → 1.
- [ ] **Step 2: Run** `make test` — Expected: FAIL, `CycloneDXDocument` missing.
- [ ] **Step 3: Implement.** Recognition rejects a non-dotted-decimal version (opens Source) although `compareVersions` sorts it high, so `1.x` never reaches the checks.
- [ ] **Step 4: Run** `make test` — Expected: PASS.
- [ ] **Step 5: Commit** `git add Packages/BOMCore Fixtures/synthetic && git commit -m "Read CycloneDX documents into a component model"`

### Task 4: Dependency graph

**Files:**
- Create: `Packages/BOMCore/Sources/BOMCore/CycloneDX/DependencyGraph.swift`
- Test: `Packages/BOMCore/Tests/BOMCoreTests/DependencyGraphTests.swift`

**Interfaces:**
- Consumes: `CycloneDXDocument`.
- Produces:
  - `public struct DependencyGraph: Sendable { public init?(_ bom: CycloneDXDocument) }` — nil when the document has no `dependencies` array (a first-class state; never an empty graph).
  - `public var direct: [String]` (subject's `dependsOn`, document order), `public func depth(_ bomRef: String) -> Int?` (BFS steps from the subject; nil = unreachable), `public func path(to bomRef: String) -> [String]?` (shortest, subject first; ties broken by `dependsOn` order), `public func usedBy(_ bomRef: String) -> [String]` (reverse edges, document order), `public var depthHistogram: [Int: Int]` (depth → count of reachable non-subject refs), `public var unreachable: [String]` (component bom-refs not reached), `public func entry(_ bomRef: String) -> NodeID?` (the `dependencies[]` object, for evidence).
  - `CycloneDXDocument.component(bomRef:) -> Component?` (first match).

- [ ] **Step 1: Write the failing tests** (Laravel):
  - `laravelDirect`: direct == ["laravel/laravel-7.12.0.0"].
  - `laravelHistogram`: [1: 1, 2: 5, 3: 30, 4: 21, 5: 4, 6: 1]; unreachable == [].
  - `laravelLexerPath`: path(to: "doctrine/lexer-1.2.3.0") == ["cyclonedx/cyclonedx-php-composer-demo-dev-master", "laravel/laravel-7.12.0.0", "laravel/framework-7.30.6.0", "egulias/email-validator-2.1.25.0", "doctrine/lexer-1.2.3.0"].
  - `laravelLexerUsedBy`: ["egulias/email-validator-2.1.25.0"].
  - `cernHasNoGraph`: `DependencyGraph(cern)` == nil.
  - `cycleTerminates`: inline document where a → b → a; depth(b) == 2 from subject s → a; no hang.
- [ ] **Step 2: Run** `make test` — Expected: FAIL.
- [ ] **Step 3: Implement** with adjacency arrays keyed by bom-ref, one BFS at init.
- [ ] **Step 4: Run** `make test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Build the dependency graph with depth, paths and used-by"`

### Task 5: Composition aggregates

**Files:**
- Create: `Packages/BOMCore/Sources/BOMCore/CycloneDX/Composition.swift`
- Test: `Packages/BOMCore/Tests/BOMCoreTests/CompositionTests.swift`

**Interfaces:**
- Consumes: `CycloneDXDocument`, `DependencyGraph?`.
- Produces: `public struct Composition: Sendable { public init(_ bom: CycloneDXDocument, graph: DependencyGraph?) }` with
  - `public let vendors: [Slice]`, `licenses: [Slice]`, `ecosystems: [Slice]` sorted by count descending, then label ascending; `public struct Slice: Sendable, Hashable { label: String; count: Int; components: [Int] }` (indexes into `bom.components`).
  - `public func top(_ slices: [Slice], keep: Int) -> (named: [Slice], others: Slice?)` — "n others" bucket labelled "".
  - `public let depthHistogram: [Int: Int]?` (nil without a graph).
  - `public let directCount: Int?`, `indirectCount: Int?` (indirect = reachable minus direct).
  - Vendor: `group`, else purl namespace, else "(none)" label `""` + flag `unknown`. License label: SPDX id, expression, or `name`; a component with no licence counts under label "" with `unknown`. A component with two licences counts once per licence.

- [ ] **Step 1: Write the failing tests:**
  - `laravelVendors`: 24 slices; first five: symfony 27, psr 5, then guzzlehttp/laravel/league 3 each in that label order.
  - `laravelLicenses`: MIT 57, BSD-3-Clause 4, Apache-2.0 1.
  - `laravelEcosystems`: [composer 62]; direct 1, indirect 61.
  - `cernVendorsUnknown`: one slice, unknown, 43; ecosystems [npm 43]; depthHistogram nil.
  - `topKeepsOthers`: `top(vendors, keep: 5)` → 5 named, others.count == 62 - 41 == 21.
- [ ] **Step 2: Run** `make test` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `make test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Aggregate components by vendor, licence, ecosystem and depth"`

### Task 6: SPDX identifiers and expressions

**Files:**
- Create: `Packages/BOMCore/Sources/BOMCore/Resources/spdx.schema.json` (copied from CycloneDX's `schema/spdx.schema.json`, `$comment` "v1.1-3.28.0", the same file rio 0.10.2 embeds; copied once from `../rio/internal/sbom/schemas/spdx.schema.json`; `Packages/BOMCore/Sources/BOMCore/Resources/NOTICE.md` names the source and the Apache-2.0 licence)
- Create: `Packages/BOMCore/Sources/BOMCore/Checks/SPDX.swift`
- Modify: `Packages/BOMCore/Package.swift` (`.target(name: "BOMCore", resources: [.copy("Resources/spdx.schema.json")])`)
- Test: `Packages/BOMCore/Tests/BOMCoreTests/SPDXTests.swift`

**Interfaces:**
- Produces: `public enum SPDX { static func isLicence(_ id: String) -> Bool; static func isLicenceAnyCase(_ id: String) -> Bool; static func isExceptionAnyCase(_ id: String) -> Bool; static func isValidExpression(_ s: String) -> Bool }`, a port of rio's `internal/sbom/enrichment.go` (list split where the case-insensitive order breaks, exactly once, else everything unknown) and `internal/gate/spdxexpr.go` (max length 4096, max depth 64, operators upper- or lower-case, `LicenseRef-`, `DocumentRef-x:LicenseRef-y`, trailing `+`, `WITH` exception). Loaded once, lazily, thread-safe (`static let`).

- [ ] **Step 1: Write the failing tests:**
  - `knownLicence`: isLicence("MIT") true; isLicence("mit") false; isLicenceAnyCase("mit") true; isLicence("Classpath-exception-2.0") false.
  - `expressions` (true): "MIT", "MIT OR Apache-2.0", "mit or apache-2.0", "(MIT AND BSD-3-Clause) OR GPL-2.0-only", "GPL-2.0-or-later WITH Classpath-exception-2.0", "LicenseRef-acme", "DocumentRef-x:LicenseRef-y", "Apache-2.0+".
  - `badExpressions` (false): "", "MIT OR", "(MIT", "MIT WITH MIT", "Foo-1.0", "MIT AND (" , a string of 65 nested parentheses around MIT, a 4097-character expression.
- [ ] **Step 2: Run** `make test` — Expected: FAIL.
- [ ] **Step 3: Implement** and add the resource.
- [ ] **Step 4: Run** `make test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Port rio's SPDX licence list and expression check"`

### Task 7: TR-03183-2 2.1.0 checks

**Files:**
- Create: `Packages/BOMCore/Sources/BOMCore/Checks/TR031832.swift` (rule ids, levels, sections), `.../Checks/FieldChecks.swift` (port of rio `internal/gate/profile_fields.go`), `.../Checks/ProfileCheck.swift` (port of `checkProfile`, `runProfile`, `ProfileEvaluationCounts`, `identify`)
- Test: `Packages/BOMCore/Tests/BOMCoreTests/ProfileCheckTests.swift`

**Interfaces:**
- Consumes: `CycloneDXDocument`, `Component`, `SPDX`, Task 1 helpers.
- Produces:
  - `public enum Scope: String, Sendable { case sbom, subject, components }`
  - `public enum Requirement: String, Sendable, CaseIterable { case specVersion, creator, timestamp, vulnerabilities, name, version, level, filename, dependencies, distributionLicences, deployableHash, executable, archive, structured }`
  - `public struct RuleID: Hashable, Sendable { scope: Scope; requirement: Requirement; var description: String /* "components.creator" */ }`
  - `public enum Level: String, Sendable, CaseIterable { case full, logical, assembled, identified, referenced }` (reporting order as listed).
  - `public struct Evaluation: Sendable, Hashable { rule: RuleID; evaluated: Int; failed: Int }` with `outcome` (`pass`, `fail`, `notEvaluated` when evaluated == 0).
  - `public struct Offender: Sendable, Hashable { rule: RuleID; component: Int? /* index into bom.components, nil for sbom/subject */; identity: String /* rio identify() */; evidence: Evidence; detail: String? }`
  - `public struct ProfileResult: Sendable { evaluations: [Evaluation] /* rio's reporting order */; levels: [Level: Int] /* subject included */; offenders: [Offender]; func offenders(_ rule: RuleID) -> [Offender] }`
  - `public func checkTR031832(_ bom: CycloneDXDocument) -> ProfileResult`
  - `public static func section(_ rule: RuleID) -> String?` on `TR031832` (rio's `ProfileSection`: sbom.specVersion "§4"; sbom.creator, sbom.timestamp "§5.2.1"; sbom.vulnerabilities "§3.1"; subject/components distributionLicences "§5.2.2, §6.1"; other subject/components fields "§5.2.2"; level nil).
  - `public static func introducedIn(_ r: Requirement) -> String?` (values in Global Constraints).
  - Evidence per failed rule (object = the component's node, or metadata, or root):

    | Requirement | key on the object |
    |---|---|
    | specVersion, vulnerabilities | root `specVersion`, `vulnerabilities` |
    | creator (sbom) | metadata `manufacturer` (absent `metadata` on root when there is none) |
    | timestamp | metadata `timestamp` |
    | name, version | `name`, `version` |
    | creator (component) | `manufacturer` |
    | level, filename, executable, archive, structured | `properties` |
    | distributionLicences | `licenses` |
    | deployableHash | `externalReferences` |
    | dependencies | `bom-ref` |

    A non-object component entry gets `.located(entry node)`; a component without a node in the tree cannot occur.

- [ ] **Step 1: Write the failing tests** (inline documents via a `bom(_ json:)` helper, plus fixtures):
  - `laravelCounts`: evaluations for components: name 62/62 passed, level 62 evaluated 0 failed, creator/filename/dependencies/distributionLicences/deployableHash/executable/archive/structured each evaluated 62 failed 62; sbom: specVersion failed 1, creator failed 1, timestamp failed 1, vulnerabilities failed 0; levels [.full: 63].
  - `laravelTimestampEvidence`: offenders(sbom.timestamp).first?.evidence is `.absent` with key "timestamp" and parent = metadata.
  - `levelsFromProperty`: components with `rio:tr-03183-2:level` "assembled" → filename not evaluated for it, creator/dependencies/distributionLicences evaluated; "identified" → only creator (plus name/version/level); a `bom` external reference with a nonblank url → `.referenced`, even with a level property; the property twice → `.full` with a `level` failure and detail "the rio:tr-03183-2:level property appears 2 times; it may appear once"; value "bogus" → `.full`, failure, detail names it.
  - `creatorForms`: manufacturer `{contact:[{email:"a@b"}]}` pass; `{contact:[{email:"@b"}]}` fail; `{url:["https://example.com"]}` pass; `{url:["https://"]}` fail; `{url:["ftp://x"]}` fail; duplicate `manufacturer` key, first valid, last `{}` → fail, evidence located on the last.
  - `timestampForms`: pass "2020-08-03T01:28:52.765Z", "2026-11-15T10:00:00+01:00"; fail "2020-13-01T00:00:00Z", "2020-08-03 01:28:52Z", "2020-02-30T00:00:00Z", 20200803.
  - `licences`: expression "MIT OR Apache-2.0" acknowledged "concluded" pass; `license.id` "MIT" concluded pass; `license.id` "MIT" declared fail; `license.name` "MIT" concluded fail; `license.id` "Classpath-exception-2.0" concluded fail.
  - `deployableHash`: SHA-512 of 128 hex on a `distribution` reference pass; same hash on the component's own `hashes` (CERN form) fail; 127 hex fail; alg "SHA-256" fail.
  - `dependenciesNeedComposition`: bom-ref with a dependencies entry but no composition fail; with composition `aggregate` "complete" listing it in `assemblies` pass; `aggregate` "not_specified" fail.
  - `fileProperties`: `bsi:component:executable` "executable" pass, "yes" fail, twice fail; filename "app.jar" pass, "lib/app.jar" fail, "  " fail.
  - `vulnerabilities`: non-empty `vulnerabilities` array → sbom.vulnerabilities failed 1.
  - `nonObjectEntry`: synthetic file's `"oops"` entry counts in components evaluations and fails name, version and every full-level field; identity is its path ("components[\(i)]").
  - `identityLikeRio`: purl when present; else "group:name@version"; else path + "@version".
  - `subjectWithoutObject`: no `metadata.component` → subject profile fields evaluated 0; subject.name and subject.version failed 1.
- [ ] **Step 2: Run** `make test` — Expected: FAIL.
- [ ] **Step 3: Implement** the port. Evaluation order and counts follow rio's `ProfileEvaluationCounts`; `subject.securityContact`, `subject.digest` and `components.purl` are not part of the rule set. `sbom.specVersion` fails when the file's version is not dotted decimal ≥ 1.6 (rio's `validSpecVersion`). Timestamp: RFC 3339 as Go's `time.Parse(time.RFC3339)` accepts it (upper-case `T` and `Z`, optional fraction, numeric offset, calendar-valid date); URL: scheme http/https case-insensitive and a non-empty host after trimming.
- [ ] **Step 4: Run** `make test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Port rio's TR-03183-2 2.1.0 profile checks"`

### Task 8: Parity with rio

**Files:**
- Create: `scripts/rio-parity.py` (stdlib only, run with `python3 -I`), `Fixtures/parity/*.rio.json` (generated, committed), `Fixtures/synthetic/tr-edge-1.6.cdx.json`, `Fixtures/rio/bsi-pass.cdx.json`, `Fixtures/rio/bsi-fail.cdx.json` (copied from rio's `testdata/profile/`, Apache-2.0; `Fixtures/rio/NOTICE.md` names the source and licence)
- Modify: `Makefile` (target `parity-refresh`)
- Test: `Packages/BOMCore/Tests/BOMCoreTests/ParityTests.swift`

**Interfaces:**
- Consumes: `checkTR031832`, `ProfileResult`.
- Produces: `make parity-refresh` (requires `rio` on PATH; fails with "rio not found" otherwise). For each of `Fixtures/public/*.json`, `Fixtures/rio/*.json`, `Fixtures/synthetic/tr-edge-1.6.cdx.json`, it writes a manifest under `build/parity/` (`version: 1`, one artifact, `gate: {mode: warn, require: [name, version], profile: bsi-tr-03183-2@2.1.0}`), runs `rio normalize --manifest … --out build/parity/out --quiet`, and writes `Fixtures/parity/<file name>.rio.json`:
  `{"rio": "<rio version line>", "input": "<file>", "specVersionInput": "1.4", "evaluations": [{"scope","requirement","evaluated","failed"}], "profileLevels": {...}, "findings": [{"scope": "sbom|subject|components", "component": "<identity or null>", "missing": [...]}]}` taken from `index.json` (`checks.evaluations`, `checks.profileLevels`, `gateFindings`).
- `tr-edge-1.6.cdx.json` is schema-valid CycloneDX 1.6 (rio validates) and covers: each level (property and `bom` reference), a duplicated level property, a duplicated `manufacturer` key (first valid, last invalid), a manufacturer URL without host, a timestamp with `+01:00`, a lower-case expression, a `WITH` expression, a `LicenseRef-`, a SHA-512 on a distribution reference, a 127-hex hash, a composition `not_specified`, nested components under the subject, a component without purl and group.

- [ ] **Step 1: Write the edge fixture, copy rio's two fixtures, write the script and run** `make parity-refresh` — Expected: six `.rio.json` files; `git diff --stat` shows them; rio exits 0 for each (warn mode).
- [ ] **Step 2: Write the failing test** `matchesRio` (parameterised over the parity files): same evaluations list in the same order for every rule but `sbom.specVersion`; for `sbom.specVersion`, app failed == 1 exactly when `specVersionInput` < 1.6; same `profileLevels`; same findings as (scope, component, missing) in the same order, after removing `specVersion` from the app's sbom finding when rio uplifted.
- [ ] **Step 3: Run** `make test` — Expected: FAIL where the port differs (or PASS if Task 7 is exact; then break one check on purpose, watch it fail, restore).
- [ ] **Step 4: Fix differences in the port, never in the expectations.** A difference that is a rio bug is a ruling to ledger and report to Toni, not a silent deviation.
- [ ] **Step 5: Run** `make test` — Expected: PASS.
- [ ] **Step 6: Commit** `git add scripts Fixtures Makefile Packages && git commit -m "Check the TR-03183-2 port against rio's results"`

### Task 9: Completeness report, verdict and component filters

**Files:**
- Create: `Packages/BOMCore/Sources/BOMCore/Workshop/WorkshopReport.swift`, `.../Workshop/ComponentFilter.swift`, `.../Workshop/History.swift`
- Test: `Packages/BOMCore/Tests/BOMCoreTests/WorkshopReportTests.swift`, `HistoryTests.swift`

**Interfaces:**
- Consumes: Tasks 3–7.
- Produces:
  - `public struct WorkshopAnalysis: Sendable { bom: CycloneDXDocument; graph: DependencyGraph?; composition: Composition; profile: ProfileResult; report: CompletenessReport; public static func analyse(_ tree: JSONTree) -> WorkshopAnalysis? }` (nil when not CycloneDX). The one entry point the app calls off the main thread.
  - `public struct CompletenessReport: Sendable { versionGap: VersionGap?; parseErrors: Int; sections: [Section] }`, `VersionGap { found: String; required: "1.6"; evidence: Evidence }`, `Section { scope: Scope; rows: [Row] }`, `Row { rule: RuleID; covered: Int; total: Int; outcome; section: String?; introducedIn: String? /* only when newer than the file */; offenders: [Offender] }`. Rows in rio's reporting order; `sbom.specVersion` is not a row (it is the version gap).
  - `public struct Verdict: Sendable, Equatable { ready: Bool; versionGap: String?; gaps: [GapTopic] /* failing topics in priority order */ }`, `public enum GapTopic: CaseIterable { timestamp, manufacturer, hashes, licences, dependencies, fileProperties, identity, vulnerabilities }` (priority = case order; identity = name/version/level; manufacturer = any creator rule; fileProperties = filename/executable/archive/structured). `ready` only when no rule fails and there is no version gap. The app names the first three topics and "+N more".
  - `public struct ComponentFilter: Sendable, Equatable { text: String; licence: LicenceFilter?; missing: RuleID?; depth: Int? }`, `LicenceFilter { case is(String), isNot(String), unknown }`, `public func apply(_ analysis: WorkshopAnalysis) -> [Int]` (indexes, document order; text matches name, group, purl case-insensitively).
  - `public struct History<Place: Hashable & Sendable>: Sendable { mutating func visit(_ p: Place); mutating func back() -> Place?; mutating func forward() -> Place?; var current: Place?; var canGoBack, canGoForward: Bool }` (visit of the current place is a no-op; visit clears forward).

- [ ] **Step 1: Write the failing tests:**
  - `laravelVersionGap`: versionGap.found "1.4", evidence located on `specVersion`.
  - `laravelNotes`: row components.creator introducedIn "1.6"; components.filename introducedIn nil (1.4 ≥ 1.3); for CERN (1.2) components.filename introducedIn "1.3".
  - `laravelVerdict`: ready false, versionGap "1.4", gaps == [.timestamp, .manufacturer, .hashes, .licences, .dependencies, .fileProperties].
  - `rioPassVerdict`: `Fixtures/rio/bsi-pass.cdx.json` → ready true, gaps [].
  - `brokenFileStillReported`: a new `Fixtures/edge/cyclonedx-broken.json` (CycloneDX 1.6 with two components and one missing comma between them; `workshop-broken.json` has no `specVersion`, so it stays a Source-only file) → analysis non-nil, parseErrors ≥ 1.
  - `filters`: Laravel `licence: .isNot("MIT")` → 5 components; `missing: components.deployableHash` → 62; `depth: 6` → 1 (lexer's chain end); text "symfony" → 27.
  - History: visit a,b,c; back → b; back → a; forward → b; visit d → canGoForward false; visit d again → back returns b.
- [ ] **Step 2: Run** `make test` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `make test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Add the completeness report, verdict and component filters"`

### Task 10: App shell: tabs, analysis, evidence drawer

**Files:**
- Modify: `App/DocumentModel.swift`, `App/DocumentView.swift`, `App/Commands.swift`, `App/AppDelegate.swift` (launch options), `App/Source/SourceTextView.swift` (absent marker), `Makefile` (`snapshot` gains `VIEW=`, `COMPONENT=`, `EVIDENCE=`, `LANG=`)
- Create: `App/Workshop/WorkshopTabs.swift`, `App/Workshop/EvidenceDrawer.swift`, `App/Workshop/EvidenceButton.swift`

**Interfaces:**
- Consumes: `WorkshopAnalysis.analyse`, `Evidence`, `Absent`, `History`.
- Produces (app-internal):
  - `enum WorkshopTab: String, CaseIterable { overview, composition, completeness, components, source }`.
  - `enum Place: Hashable, Sendable { case tab(WorkshopTab); case component(Int); case node(NodeID) }`; `DocumentModel.history: History<Place>` replaces `back`/`forward`; `goBack()`/`goForward()` keep their menu items (⌘[ ⌘]).
  - `DocumentModel`: `analysis: WorkshopAnalysis?` (computed in the same detached task as the parse); `tab: WorkshopTab` (`.overview` when `analysis != nil`, else `.source`); `componentPage: Int?`; `evidence: Evidence?`; `drawerPinned: Bool`; `absentMarker: Absent?`; `func show(_ e: Evidence)` (selects `.located` node with origin `.reveal`, or the absent's parent with `absentMarker` set, and opens the drawer); `func closeDrawer()` (no-op when pinned); `var scale: CGFloat { textSize / Self.defaultTextSize }`.
  - `EvidenceButton(evidence:label:)`: any statement in a view; click → `model.show`.
  - Drawer: bottom panel under the tab content, resizable (VSplitView), default height 38% of the window; header "Evidence · line N · <pointer or "\"key\" is absent">" and "Esc to close"; Esc closes, ⌥⌘E toggles pinned (Commands, View menu "Keep Evidence Open"). Hidden on the Source tab.
  - Absent marker: drawn by the text view (never inserted into the text), after the end of the line containing `insertion`, in the system red: `⟵ "<key>" would be here: absent`. Uses `display.displayOffset` for the line.
  - Launch options: `--view <tab>`, `--component <bom-ref>`, `--evidence <rule id>` (shows the first offender's evidence), `--language de|en`.

- [ ] **Step 1: Build check before changes:** `make app` — Expected: exit 0.
- [ ] **Step 2: Implement** the model changes, tabs (placeholder text per view tab for now), drawer, marker, commands and options.
- [ ] **Step 3: Run** `make test && make app` — Expected: both exit 0.
- [ ] **Step 4: Verify by snapshot:** `make snapshot FILE=Fixtures/public/laravel-7.12.0.cdx-1.4.json OUT=build/screenshots/w-drawer.png VIEW=overview EVIDENCE=sbom.timestamp` — Expected: PNG shows the tab bar and the drawer with line 6 selected and the red marker after `"metadata": {`. `make snapshot FILE=Fixtures/edge/duplicates.json OUT=build/screenshots/w-source-only.png` — Expected: Source view only, no tab bar entries besides Source.
- [ ] **Step 5: Commit** `git commit -m "Add workshop tabs and the evidence drawer"`

### Task 11: Overview

**Files:**
- Create: `App/Workshop/OverviewView.swift`

**Interfaces:**
- Consumes: `analysis.bom`, `composition`, `report`, `Verdict`, `EvidenceButton`.
- Produces: the Overview as in `docs/mockups/overview-layout.html` option B: eyebrow "Software bill of materials · CycloneDX <version>"; title (subject name, else file name); line "type · version · built on <first direct dependency's displayName and version>" (omitted parts drop out); four stats: components; "direct → indirect" (or "no dependency data"); ecosystems (named when one); licences; fields Made by (tools), Made when (timestamp or a red "no timestamp" pill), Supplier/Manufacturer of the SBOM; the verdict box linking to Completeness. Every value is an `EvidenceButton`. Fonts scale with `model.scale`.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run** `make app` — Expected: exit 0.
- [ ] **Step 3: Snapshots** at `--window-size 1440x900` and `--text-size 24` for Laravel and CERN, light and dark: `build/screenshots/w-overview-*.png`. Expected: Laravel reads "62 · 1 → 61 · 1 (Composer) · 3"; verdict starts "Not ready for TR-03183-2: format version 1.4"; CERN shows "no dependency data" and its timestamp; nothing clips at 24 pt.
- [ ] **Step 4: Commit** `git commit -m "Add the Overview"`

### Task 12: Composition

**Files:**
- Create: `App/Workshop/CompositionView.swift`

**Interfaces:**
- Consumes: `Composition`, `top(_:keep:)`.
- Produces: three sections. Vendors: one horizontal stacked bar (Swift Charts `BarMark`), the largest five named, the rest "n others"; licences: one stacked bar with the exceptions to the majority named in text below ("5 not MIT: …"); dependency depth: histogram (`BarMark` per depth) or the sentence "This SBOM has no dependency data." Clicking a segment opens Components with the matching filter; each count is an `EvidenceButton` to the first component's node. Semantic system colours, one accent; unknown slices in grey.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run** `make app` — Expected: exit 0.
- [ ] **Step 3: Snapshots** Laravel and CERN at 1440×900 and 24 pt: `build/screenshots/w-composition-*.png`. Expected: Laravel bar names symfony 27 first; histogram 1/5/30/21/4/1; CERN shows the no-data sentence.
- [ ] **Step 4: Commit** `git commit -m "Add the Composition view"`

### Task 13: Completeness

**Files:**
- Create: `App/Workshop/CompletenessView.swift`

**Interfaces:**
- Consumes: `CompletenessReport`, `TR031832.section`.
- Produces: header "BSI TR-03183-2 2.1.0 · presence and form of fields"; the version-gap line (Global Constraints) when present; the parse-error line when `parseErrors > 0`; sections Document · Product · Components; each row: plain title, "covered / total", a bar, the section reference, the field note; a not-evaluated row is muted ("not checked at this level"); clicking a row expands its offenders (lazy list, identity + detail), each an `EvidenceButton`. Row titles (English source): creator "Manufacturer with contact", timestamp "Creation time (RFC 3339)", vulnerabilities "No vulnerability data in the SBOM", name "Name", version "Version", level "Level property valid", filename "File name", dependencies "Dependencies, covered by a composition", distributionLicences "Concluded licence (SPDX)", deployableHash "SHA-512 hash of the deployable file", executable "Executable property", archive "Archive property", structured "Structured property".

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run** `make app` — Expected: exit 0.
- [ ] **Step 3: Snapshots** Laravel, CERN, `Fixtures/rio/bsi-pass.cdx.json`: `build/screenshots/w-completeness-*.png`, one with a row expanded and the drawer open (`EVIDENCE=components.deployableHash`). Expected: Laravel shows the version-gap line and "field introduced in CycloneDX 1.6" on Manufacturer and Concluded licence; bsi-pass shows every row full and the all-present sentence.
- [ ] **Step 4: Commit** `git commit -m "Add the Completeness view"`

### Task 14: Components and the component page

**Files:**
- Create: `App/Workshop/ComponentsView.swift`, `App/Workshop/ComponentPage.swift`

**Interfaces:**
- Consumes: `ComponentFilter.apply`, `DependencyGraph.path/usedBy/depth`, `ProfileResult.offenders`.
- Produces: a search field and filter menus (licence is / is not / unknown; missing <rule>; depth) over a lazy `List`/`Table` (name, version, licence, depth, gap count); a row opens the component page (`Place.component`). Page: identity (decoded purl fields), description, author/supplier/manufacturer, licences with acknowledgement, integrity (hashes on the component and on references), external references, gaps (its offenders), "Why is it here?" (the path as a chain of buttons, each opening that component; "not reachable from the product" or "no dependency data" otherwise), "Used by". Every value is an `EvidenceButton`.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run** `make app` — Expected: exit 0.
- [ ] **Step 3: Snapshots:** `VIEW=components` with Laravel; `COMPONENT=doctrine/lexer-1.2.3.0` at 1440×900 and 24 pt: `build/screenshots/w-component-lexer*.png`. Expected: path cyclonedx-php-composer-demo → laravel/laravel → laravel/framework → egulias/email-validator → doctrine/lexer; Used by egulias/email-validator.
- [ ] **Step 4: Manual check** (record in `docs/checklist.md`): Back/Forward walks tab → component → component → tab; Esc closes the drawer; ⌥⌘E keeps it.
- [ ] **Step 5: Commit** `git commit -m "Add Components and the component page"`

### Task 15: German and English

**Files:**
- Create: `App/Localizable.xcstrings`, `App/Workshop/L10n.swift`, `scripts/check-strings.py`
- Modify: workshop views (strings through `L10n`), `Commands.swift` (View › Language: System, English, Deutsch), `Makefile` (target `strings-check`, run by `test`)

**Interfaces:**
- Produces: `enum AppLanguage: String { system, en, de }` stored in `UserDefaults` (`bbom.language`); `L10n.text(_ key: String.LocalizationValue, _ lang: AppLanguage) -> String` looks the key up in the `.lproj` bundle of the chosen language (`Bundle.main.path(forResource: "de", ofType: "lproj")`), falling back to English. Views read the language from the environment, so a switch re-renders without restarting. `scripts/check-strings.py` fails when a key lacks an `en` or `de` value or any value contains "compliant", "konform", "conformant" or "zertifiziert".

- [ ] **Step 1: Write** `check-strings.py` and run `make strings-check` on an empty catalog with one key lacking `de` — Expected: FAIL naming the key.
- [ ] **Step 2: Implement** the catalog (all workshop strings, German in the expert register; Toni reviews the wording) and the switch.
- [ ] **Step 3: Run** `make test && make app` — Expected: exit 0.
- [ ] **Step 4: Snapshots** with `LANG=de` for Overview and Completeness (Laravel). Expected: German text, English industry terms, no clipping.
- [ ] **Step 5: Commit** `git commit -m "Add German and English with an in-app switch"`

### Task 16: Large files, documentation, screenshots

**Files:**
- Modify: `Packages/BOMCore/Sources/bbom-bench/main.swift` (generator emits `dependencies` as a tree of depth ≤ 8 and one composition; new subcommand `analyse <path>` printing parse ms and analysis ms), `Makefile` (`bench` also runs `analyse`; target `screenshots`), `docs/findings.md`, `docs/checklist.md`, `README.md`
- Test: `Packages/BOMCore/Tests/BOMCoreTests/WorkshopScaleTests.swift`

**Interfaces:**
- Consumes: `WorkshopAnalysis.analyse`.

- [ ] **Step 1: Write the failing test** `analysesGeneratedMegabyte`: a 1 MB document from the generator's function (moved into BOMCore as `SyntheticSBOM.generate(sizeMB:minified:)` so tests can call it) has a graph and every component reachable.
- [ ] **Step 2: Run** `make test` — Expected: FAIL. **Step 3: Implement**, **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Measure:** `make fixtures bench CONFIG=Release` — Expected: for the 50 MB files, analysis ≤ about 1000 ms over the parse. Record the table in `docs/findings.md`; if over, profile and fix before continuing.
- [ ] **Step 6: Screenshots:** `make screenshots` regenerates every `w-*.png` in `build/screenshots/` (served by the LAN gallery). Check each against the mockups.
- [ ] **Step 7: Docs:** README (the views, launch options, `make parity-refresh`), checklist (workshop flow, presentation size, language switch, drawer), findings (timings, rulings, open points).
- [ ] **Step 8: Commit** `git commit -m "Measure the workshop views on large SBOMs and document them"`
