# Beautiful Bill of Materials: workshop views (design)

Status: draft for Toni's approval, 2026-11-15. Builds on `design.md` (the JSON reader, done) and replaces its optional "phase 2" with a larger scope.

## Intent

The JSON reader is a better text editor, not a reason to leave the text editor (Toni, 2026-11-15). The app must show what an SBOM *means*, visually, while the original source stays the evidence for every statement. "Beautiful Bill of Materials" has to earn its name.

**Primary situation (decided):** a client workshop. Toni presents an SBOM of the client's product on a projector to a mixed room (management and developers). The room's questions: *What is in our product? Is this SBOM good enough?* Desk use by a practitioner is secondary; teaching comes later.

## Goals

1. Four views, in this order, as tabs (decided: all four, Overview first):
   - **Overview**: the title page. Product name, version, type, what it is built on; four big numbers (components; chosen directly → pulled in; ecosystems; licenses); who made the SBOM (tool, version) and when; one verdict sentence derived from Completeness, linking there. The verdict names the reference and the largest gaps, e.g. "Not ready for TR-03183-2: format version 1.4, and no hashes, manufacturer or timestamp." It never says "compliant"; a fully covered SBOM reads "All TR-03183-2 fields present in the required form."
   - **Composition**: components by vendor (one horizontal bar, largest vendors named, the rest as "n others"); licenses (one bar, with the exceptions to the majority named); dependency depth (histogram of steps from the product).
   - **Completeness**: a checklist of required fields with coverage per row (e.g. "Hash of the component 0/62"); a row opens the list of affected components; each has evidence.
   - **Components**: a searchable list filterable by license, by gap and by depth ("everything not MIT", "everything without a hash"); each opens a **component page**: identity (purl decoded), description, author/supplier, license, integrity (hashes), external references, gaps, and **"Why is it here?"**, the shortest path from the product to the component, plus "used by".
2. **Evidence drawer underneath (decided: option B).** Views use the full width. Clicking any statement opens a drawer below with the source at the exact range (the existing source view, same highlighting). Esc closes it; ⌥⌘E pins it open for desk use.
3. **Gaps are evidence too.** A missing field (no timestamp, no hash) shows in the drawer as a marked line where the field would be in its parent object ("⟵ "timestamp" would be here: absent").
4. **Presentation-first typography.** Readable from the back of a room at 1440×900 and full-screen 1920×1080; presentation size (⌥⌘P) scales views, not only the source.
5. The JSON reader stays: a **Source** tab gives the current structure + source view, and any non-CycloneDX file opens there directly.

Mockups with real data: `docs/mockups/workshop-lenses.html`, `docs/mockups/overview-layout.html` (option B).

## Non-goals

SPDX and AIBOM views (next format after this works); vulnerability data from the network (offline principle; a `vulnerabilities` section inside the SBOM may be shown later); editing; comparing two SBOMs; iPad/iPhone; distribution and signing.

## Anti-goals

- Any claim of conformity ("CRA-compliant", "TR-03183-2 compliant"). Completeness reports **presence and form of fields only**, worded as such.
- Hiding or smoothing gaps; a dashboard look with invented scores or percentages that the SBOM does not support.
- A rule set that is not verified against its official text.
- Network access, uploads, accounts.
- Customer SBOMs in the repository, even as fixtures.

## Constraints

As in `design.md`: Swift 6, SwiftUI with AppKit where needed, macOS 15, BOMCore without dependencies and shared with iOS, everything addressed by byte ranges, self-contained in `apps/beautiful-bom/`. Charts with Swift Charts (system framework). Public (CC0) or synthetic fixtures.

## Approaches considered

| Approach | Trade-off | Verdict |
|---|---|---|
| Native SwiftUI views over a CycloneDX layer in BOMCore (chosen) | More Swift UI work than HTML; native type, keyboard, VoiceOver; one runtime; evidence links stay exact | Chosen (Claude's call; Toni steers by outcome) |
| Mockup HTML in a web view, native drawer underneath | Fast visual iteration, 1:1 with mockups; two runtimes, weaker accessibility, against "genuinely native" | Rejected |
| Static HTML report generated from the SBOM | Cheapest, shareable; not an app, no live link from view to evidence | Rejected |

## Architecture

### BOMCore: CycloneDX layer (`CycloneDX/`)

- `Located<Value>`: a value plus the `NodeID` it was read from. `Absent`: the parent `NodeID`, the missing key, and the byte offset where it would be inserted (after the parent's opening brace). Every statement a view makes is backed by one of the two.
- `CycloneDXDocument.recognize(_ tree:)` for JSON with `bomFormat == "CycloneDX"` and spec version 1.2 or later, including 1.7 and future versions (unknown fields stay visible); otherwise nil (the app then opens the Source tab).
- Model: metadata (subject component, tools in both the ≤1.4 array form and the 1.5+ `tools.components` form, authors, supplier, manufacturer, timestamp); `compositions`; components flattened from `components` including nested `components`, each with group/name/version/type/purl (decoded: type, namespace, name, version)/licenses (`license.id`, `license.name`, `expression`, and `acknowledgement` declared/concluded)/hashes (also on external references)/supplier/manufacturer/author/externalReferences/properties (including `bsi:component:*`), and unknown fields listed.
- Dependency graph from `dependencies` (`ref` → `dependsOn`): direct dependencies of the subject, depth per component (BFS), shortest path to any component, reverse edges ("used by"). Absent graph is a first-class state ("This SBOM has no dependency data"), never an empty chart.
- Aggregates for Composition: by vendor (`group`, else purl namespace), by license (normalised SPDX id or expression), by ecosystem (purl type), depth histogram.
- Completeness: a rule set as data (`RuleSet` with rules: id, title, section, scope document/component, check = field presence and form). **BSI TR-03183-2 v2.1.0 is a port of rio's profile** (`rio/internal/gate/profile.go`: requirements, component levels, section references), so rio and the app reach the same result on the same SBOM; parity tests run both on shared fixtures. rio's rules were verified against the BSI text when they were written; the port inherits that verification and cites the same sections. Result per rule: covered count, total, offenders (`Absent` or `Located` with the wrong form).
- **SBOMs older than CycloneDX 1.6 (decided):** TR-03183-2 is always the rule set. As in rio, the spec version is one document-level rule and every other rule is evaluated as written, whatever the version; nothing is skipped or graded more kindly. The version gap is stated once, at the top of Completeness: "This SBOM is CycloneDX 1.4. TR-03183-2 requires 1.6 or later." A rule whose field is newer than the file's version carries the note "field introduced in CycloneDX <version>" beside its count, so 0/62 there reads as a version gap, not as sloppy work. From the CycloneDX schemas: creator (`manufacturer`) and distribution licences (`acknowledgement`) came in 1.6; dependencies (`compositions`), filename, executable, archive and structured (`properties`) and the deployable hash (`hashes` on external references) came in 1.3.
- **rio raises older files before it checks.** `rio normalize` uplifts a pre-1.6 SBOM to 1.6 (it rewrites `specVersion` and the shape of identity evidence, nothing else) and then checks the result, so rio's receipt passes `sbom.specVersion` for the Laravel file (verified with rio 0.10.2, 2026-11-15). The app reads the file as it is and fails the rule. Parity therefore covers every rule except `sbom.specVersion`, which is compared against the input version rio records. The version-gap line adds: "A conversion to 1.6 fixes the version; it adds none of the missing fields."
- Parsing stays as is; the CycloneDX layer runs off the main thread after the parse.

### App

- Tab bar: Overview · Composition · Completeness · Components · Source. Non-CycloneDX files show Source only.
- Views are SwiftUI; charts are Swift Charts; every statement is a button that sets an *evidence target* (`Located` or `Absent`) on the document model.
- Evidence drawer: the existing `SourceTextView` in a resizable bottom panel; for `Located` it selects and centres the range; for `Absent` it centres the parent's opening line and draws an "absent" marker line there (a rendering decoration, not text). Esc closes, ⌥⌘E pins.
- Navigation: Back/Forward across views and component pages; component page opens from any list, path node or chart segment.
- Text: String Catalog with English and German; an in-app language switch (View menu, default: system language), so all view strings are looked up with an explicit locale. Copy follows the expert register (industry terms in English, no slogans).
- Agent launch options extend to `--view <name>` and `--component <bom-ref>` for snapshots.

## Verification

- Engine tests on the public fixtures: model extraction (counts, licenses, purl decoding, both tools forms), dependency depth and paths (Laravel: depth histogram 1/5/30/21/4/1; lexer path via laravel/framework and egulias/email-validator), absent markers (offsets), completeness per rule, the version gap on both public fixtures (1.2 and 1.4: version rule fails, notes on the rules whose fields are newer than the file, verdict wording), an SBOM without a dependency graph (CERN fixture), nested components, CycloneDX 1.6 synthetic.
- Snapshots of each view at 1440×900 and in presentation size, compared with the mockups.
- Checklist additions for the workshop flow; findings with timings for 50 MB (the CycloneDX layer must not add more than about a second).

## Decided by Toni

Client workshop as the primary situation; all four views; Overview first; evidence in a drawer underneath (option B). For SBOMs older than CycloneDX 1.6: TR-03183-2 anyway, with the version gap stated once (2026-11-15).

## Decided by Claude after the builder check (Toni may override)

- Port rio's TR-03183-2 2.1.0 profile instead of writing a second rule set; parity tests with rio. *Why:* two rebaze tools must not judge the same client SBOM differently in one workshop.
- Recognise CycloneDX 1.2 and later, including 1.7.
- In-app language switch German/English.
- For pre-1.6 SBOMs, rules are counted exactly as rio counts them (parity wins over "what would carry over to 1.6"); the gap shows as a note on the rules whose field is newer than the file. *Why:* a softer count in the app would contradict rio's receipt for the same file.
- NTIA minimum elements are not part of this scope.

## Left to the builder

Chart styling and colours (semantic system colours; one accent), animation, exact layout of the component page, vendor bar cut-off for "others", the German wording (reviewed by Toni).
