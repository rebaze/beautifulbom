# Beautiful Bill of Materials: proof of concept implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A read-only macOS app that opens a local JSON file and makes it pleasant and exact to read: faithful highlighted source, a synced structure pane, pointers and copy, diagnostics for malformed input; optionally a first CycloneDX view.

**Architecture:** A dependency-free Swift package `BOMCore` parses the original bytes once, off the main thread, into a flat node arena with byte ranges, and maps bytes to UTF-16 for the text system. A SwiftUI document app hosts AppKit views (NSTextView with TextKit 2, NSOutlineView) that only ever address the source through `BOMCore` ranges.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, SwiftUI + AppKit, xcodegen, xcodebuild + xcbeautify, Make.

**Spec:** `apps/beautiful-bom/docs/design.md` (issue #151).

## Global Constraints

- Everything lives in `apps/beautiful-bom/`; no file references outside it (the folder becomes its own repository).
- Deployment targets: macOS 15.0 for the app; `.macOS(.v15), .iOS(.v18)` for `BOMCore`.
- `BOMCore` has no third-party dependencies and imports only Foundation.
- Original bytes are authoritative; source locations come only from parser ranges, never from reserializing or searching values.
- No network access anywhere in the app or package.
- Fixtures are public (CycloneDX bom-examples, Apache-2.0, with notice) or synthetic; never customer data.
- Commit messages: plain, imperative, no `Co-Authored-By` lines, no AI attribution. Work on branch `beautiful-bom-poc`.
- Paths below are relative to `apps/beautiful-bom/` unless they start with the repository root.

## Review Focus

1. **Minified BOMs (one line, 10–50 MB).** Common in practice. Lexing, highlighting and node lookup must stay bounded by the visible range, never by the line. Pinned in Task 3 (`lexStartIsNearOffsetInMinifiedInput`) and Task 4 (bench `--minified`).
2. **Byte order mark, CRLF, invalid UTF-8.** Offsets must still map one to one with what the text view shows. Pinned in Task 1 (`bomCRLFAndInvalidUTF8Map`).
3. **Characters outside the BMP** (emoji, CJK extension) in keys and values. Each one is two UTF-16 units in AppKit. Pinned in Task 1 (`surrogatePairsMap`).
4. **Empty, whitespace-only or non-JSON files** (a PDF renamed `.json`): a diagnostic, never a crash or a blank window. Pinned in Task 2 (`degenerateInputsYieldDiagnostics`).
5. **Very deep nesting (100 000 levels):** no stack overflow in the parser, pointer or outline. Pinned in Task 2 (`deepNestingDoesNotOverflow`).

---

## File structure

```
apps/beautiful-bom/
  README.md                 build, run, tested platform, limitations, findings link
  Makefile                  test, bench, project, app, snapshot, clean
  .gitignore                build/, *.xcodeproj, Fixtures/generated/
  project.yml               xcodegen spec for the app
  docs/design.md, plan.md, findings.md, checklist.md
  Fixtures/public/          CycloneDX examples + NOTICE (Apache-2.0)
  Fixtures/edge/            hand-written edge cases (duplicates, malformed, unicode)
  Packages/BOMCore/
    Package.swift
    Sources/BOMCore/
      Offsets.swift         ByteOffset, UTF16Offset
      SourceDocument.swift  bytes, line index, UTF-8 <-> UTF-16 checkpoints
      Node.swift            NodeID, NodeKind, Diagnostic
      JSONParser.swift      error-tolerant iterative parser -> JSONTree
      JSONTree.swift        arena + navigation queries
      JSONPointer.swift     RFC 6901 pointer with duplicate occurrence
      Lexer.swift           tokens for highlighting
      CycloneDX.swift       (Task 10) recognition, overview, component detail
    Sources/bbom-bench/main.swift   fixture generator + parse benchmark
    Tests/BOMCoreTests/     one file per source file
  App/
    BeautifulBOMApp.swift   @main, DocumentGroup(viewing:), commands
    AppDelegate.swift       --open, --snapshot, --select, BBOM_TIMING
    BOMDocument.swift       FileDocument holding bytes
    DocumentModel.swift     @Observable: tree, selection, history, text size
    DocumentView.swift      split layout, banner, breadcrumbs
    Source/SourceTextView.swift, Highlighter.swift, LineNumberRuler.swift
    Structure/StructureOutlineView.swift
    Commands.swift          copy commands, text size, back/forward
    CycloneDX/OverviewView.swift, ComponentDetailView.swift  (Task 10)
```

---

### Task 1: Package scaffold and SourceDocument offsets

**Files:**
- Create: `Packages/BOMCore/Package.swift`, `Sources/BOMCore/Offsets.swift`, `Sources/BOMCore/SourceDocument.swift`, `Tests/BOMCoreTests/SourceDocumentTests.swift`, `Makefile`, `.gitignore`, `README.md` (stub: one-paragraph purpose, `make test`)
- Modify (repository root, already done): `AGENTS.md` row for `apps/beautiful-bom/`

**Interfaces:**
- Produces:
  - `public struct ByteOffset: Hashable, Comparable, Sendable { public var value: Int }`
  - `public struct UTF16Offset: Hashable, Comparable, Sendable { public var value: Int }`
  - `public final class SourceDocument: Sendable`
    - `init(bytes: [UInt8])`
    - `let bytes: [UInt8]`
    - `let text: String` — `String(decoding: bytes, as: UTF8.self)` (invalid sequences become U+FFFD; this is exactly what the text view shows)
    - `var lineCount: Int`
    - `func line(containing: ByteOffset) -> Int` (0-based)
    - `func lineColumn(of: ByteOffset) -> (line: Int, column: Int)` (1-based; column counts Unicode scalars)
    - `func utf16Offset(of: ByteOffset) -> UTF16Offset`
    - `func byteOffset(of: UTF16Offset) -> ByteOffset` (rounds down to a scalar start)
    - `func nsRange(_: Range<ByteOffset>) -> NSRange`
    - `func byteRange(_: NSRange) -> Range<ByteOffset>`
    - `func slice(_: Range<ByteOffset>) -> String`

- [ ] **Step 1: Create branch and scaffold**

```bash
git switch -c beautiful-bom-poc
```
`Package.swift`: tools 6.0, products library `BOMCore`, executable `bbom-bench` (empty `main.swift` printing usage), test target. `Makefile` target `test: cd Packages/BOMCore && swift test`. `.gitignore`: `build/`, `*.xcodeproj/`, `Fixtures/generated/`, `.build/`.

- [ ] **Step 2: Write failing tests** in `SourceDocumentTests.swift`

```swift
@Test func asciiAndLines() {
  let d = SourceDocument(bytes: Array("{\n  \"a\": 1\n}".utf8))
  #expect(d.lineCount == 3)
  #expect(d.line(containing: ByteOffset(value: 4)) == 1)
  #expect(d.lineColumn(of: ByteOffset(value: 4)) == (2, 3))
  #expect(d.utf16Offset(of: ByteOffset(value: 4)).value == 4)
}
@Test func surrogatePairsMap() {
  let s = "{\"k😀\": \"ä\"}"           // 😀 = 4 UTF-8 bytes, 2 UTF-16 units
  let d = SourceDocument(bytes: Array(s.utf8))
  let afterEmoji = ByteOffset(value: 2 + 1 + 4)  // '{' '"' 'k' 😀
  #expect(d.utf16Offset(of: afterEmoji).value == 5)
  #expect(d.byteOffset(of: UTF16Offset(value: 5)) == afterEmoji)
  #expect(d.byteOffset(of: UTF16Offset(value: 4)).value == 3)   // inside the pair rounds down
  let r = ByteOffset(value: 1)..<afterEmoji
  #expect((d.text as NSString).substring(with: d.nsRange(r)) == "\"k😀")
  #expect(d.byteRange(d.nsRange(r)) == r)
}
@Test func bomCRLFAndInvalidUTF8Map() {
  let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("[1,\r\n".utf8) + [0xFF] + Array(",2]".utf8)
  let d = SourceDocument(bytes: bytes)
  #expect(d.lineCount == 2)
  let two = ByteOffset(value: bytes.count - 2)
  let ns = d.text as NSString
  #expect(ns.substring(with: NSRange(location: d.utf16Offset(of: two).value, length: 1)) == "2")
  #expect(d.lineColumn(of: two) == (2, 3))   // U+FFFD counts as one column
}
@Test func checkpointsHoldOnOneHugeLine() {
  let line = String(repeating: "\"é\",", count: 200_000)   // ~1 MB, no newline
  let d = SourceDocument(bytes: Array("[\(line)0]".utf8))
  let probe = ByteOffset(value: 1 + 5 * 150_000)
  #expect(d.utf16Offset(of: probe).value == 1 + 4 * 150_000)
}
```

- [ ] **Step 3: Run** `make test` — Expected: FAIL (types not defined).

- [ ] **Step 4: Implement** `Offsets.swift` and `SourceDocument.swift`. Line starts: byte offsets after each `\n` (CR is part of the line ending, not a line break of its own). UTF-16 mapping: checkpoint array every 4096 bytes, each checkpoint aligned to the next scalar start and storing `(byteOffset, utf16Offset)`, built in one pass with `Unicode.UTF8` decoding that repairs invalid sequences the same way `String(decoding:)` does (one U+FFFD per maximal invalid subpart, one UTF-16 unit). Conversions binary-search the checkpoints and walk at most 4 KiB.

- [ ] **Step 5: Run** `make test` — Expected: 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/beautiful-bom AGENTS.md
git commit -m "Add BOMCore package with source offset mapping"
```

---

### Task 2: Error-tolerant parser into a node arena

**Files:**
- Create: `Sources/BOMCore/Node.swift`, `Sources/BOMCore/JSONParser.swift`, `Sources/BOMCore/JSONTree.swift` (storage + basic accessors), `Tests/BOMCoreTests/ParserTests.swift`, `Fixtures/edge/*.json` (the inputs below as files too, for manual testing)

**Interfaces:**
- Consumes: `SourceDocument`, `ByteOffset`
- Produces:
  - `public struct NodeID: Hashable, Comparable, Sendable { public let rawValue: Int32 }` — arena index; pre-order, so ascending `NodeID` means ascending start offset
  - `public enum NodeKind: UInt8, Sendable { case object, array, string, number, bool, null, invalid }`
  - `public struct Diagnostic: Sendable, Hashable { enum Severity { case error, warning }; let severity; let range: Range<ByteOffset>; let message: String }`
  - `public func parseJSON(_ source: SourceDocument) -> JSONTree`
  - `public struct JSONTree: Sendable` with `source`, `root: NodeID?`, `nodeCount: Int`, `diagnostics: [Diagnostic]`, and per node: `kind(_:)`, `parent(_:) -> NodeID?`, `children(_:) -> [NodeID]`, `childCount(_:) -> Int`, `depth(_:) -> Int`, `keyRange(_:) -> Range<ByteOffset>?` (includes quotes), `valueRange(_:) -> Range<ByteOffset>`, `fullRange(_:) -> Range<ByteOffset>` (key start, else value start, to value end), `indexInParent(_:) -> Int`

- [ ] **Step 1: Write failing tests**

```swift
func tree(_ s: String) -> JSONTree { parseJSON(SourceDocument(bytes: Array(s.utf8))) }
func src(_ t: JSONTree, _ r: Range<ByteOffset>) -> String { t.source.slice(r) }

@Test func rangesAreExact() {
  let t = tree(#"{ "a" : [1, {"b": "x\"y"}], "c": null }"#)
  let root = t.root!
  #expect(t.kind(root) == .object && t.childCount(root) == 2)
  let a = t.children(root)[0]
  #expect(src(t, t.keyRange(a)!) == #""a""#)
  #expect(src(t, t.valueRange(a)) == #"[1, {"b": "x\"y"}]"#)
  let b = t.children(t.children(a)[1])[0]
  #expect(src(t, t.valueRange(b)) == #""x\"y""#)
  #expect(t.depth(b) == 3 && t.indexInParent(b) == 0)
  #expect(t.diagnostics.isEmpty)
}
@Test func repeatedValuesAreDistinctNodes() {
  let t = tree(#"["x","x","x"]"#)
  let ranges = t.children(t.root!).map { t.valueRange($0).lowerBound.value }
  #expect(ranges == [1, 5, 9])
}
@Test func duplicateKeysKeptAndWarned() {
  let t = tree(#"{"name":"a","name":"b"}"#)
  #expect(t.childCount(t.root!) == 2)
  #expect(t.diagnostics.map(\.severity) == [.warning])
  #expect(t.diagnostics[0].message.contains("Duplicate key \"name\""))
}
@Test func malformedKeepsWhatParsed() {
  let t = tree("{\"a\": 1, \"b\": tru, \"c\": [2, 3}")
  #expect(t.childCount(t.root!) == 3)
  #expect(t.kind(t.children(t.root!)[1]) == .invalid)
  #expect(t.diagnostics.filter { $0.severity == .error }.count >= 2)   // bad literal, mismatched bracket
  #expect(t.diagnostics.allSatisfy { !$0.message.isEmpty })
}
@Test func unclosedContainersEndAtEOF() {
  let s = "{\"a\": [1, 2"
  let t = tree(s)
  #expect(t.valueRange(t.root!).upperBound.value == s.utf8.count)
  #expect(t.diagnostics.contains { $0.message.contains("Unclosed array") && $0.message.contains("line 1") })
}
@Test func degenerateInputsYieldDiagnostics() {
  for input in ["", "   \n", "%PDF-1.7\n\u{1}\u{2}"] {
    let t = tree(input)
    #expect(t.diagnostics.contains { $0.severity == .error })
  }
  #expect(tree("").root == nil)
}
@Test func bomAndTrailingContent() {
  var bytes: [UInt8] = [0xEF, 0xBB, 0xBF]; bytes += Array("[1] [2]".utf8)
  let t = parseJSON(SourceDocument(bytes: bytes))
  #expect(t.valueRange(t.root!).lowerBound.value == 3)
  #expect(t.diagnostics.map(\.severity) == [.warning, .error])   // byte order mark; content after root
}
@Test func deepNestingDoesNotOverflow() {
  let n = 100_000
  let t = tree(String(repeating: "[", count: n) + String(repeating: "]", count: n))
  #expect(t.nodeCount == n && t.diagnostics.isEmpty)
  #expect(t.depth(NodeID(rawValue: Int32(n - 1))) == n - 1)
}
```

- [ ] **Step 2: Run** `make test` — Expected: FAIL (`parseJSON` not defined).

- [ ] **Step 3: Implement** the parser as a loop over bytes with an explicit container stack (no recursion). Grammar per RFC 8259. Recovery rules, each recorded as a `Diagnostic` with a message naming what was expected and `line N, column M`:
  - unexpected token inside a container → error; skip to the next `,` or closing bracket at the same depth (strings skipped correctly);
  - mismatched closing bracket (e.g. `}` inside an array) → error; the innermost container ends before the bracket, and the bracket is then matched against the next container out (in `malformedKeepsWhatParsed` it closes the root object, so there is no extra "unclosed" error);
  - EOF with open containers → one error per container ("Unclosed array opened at line N, column M"); value ranges end at EOF;
  - invalid literal or number → `.invalid` node covering the bad token, error;
  - unterminated string → string ends at the line end (JSON strings cannot contain raw newlines), error; raw control characters in a string → error, string continues;
  - leading U+FEFF → warning, skipped; content after the root value → error, not parsed;
  - empty or whitespace-only → error "The file contains no JSON value";
  - `//` and `/* */` comments, trailing commas → error, skipped (so JSONC files stay navigable);
  - duplicate key in one object → warning on the later key.
  Arena storage layout (struct of arrays, `Int32` offsets) is the builder's choice, measured in Task 4.

- [ ] **Step 4: Run** `make test` — Expected: all PASS.

- [ ] **Step 5: Commit** `git commit -m "Parse JSON into a ranged node arena with recovery"`

---

### Task 3: Pointers, lookup by offset, decoded values, lexer

**Files:**
- Create: `Sources/BOMCore/JSONPointer.swift`, `Sources/BOMCore/Lexer.swift`, `Tests/BOMCoreTests/QueryTests.swift`, `Tests/BOMCoreTests/LexerTests.swift`
- Modify: `Sources/BOMCore/JSONTree.swift`

**Interfaces:**
- Consumes: `JSONTree`, `NodeID`, `SourceDocument`
- Produces:
  - `public struct JSONPointer: Sendable, Hashable, CustomStringConvertible { let tokens: [String]; let occurrence: Int?; let occurrences: Int? }` — `description` is the RFC 6901 string (`~` → `~0`, `/` → `~1`); `displayString` appends ` (duplicate 2 of 2)` when `occurrence != nil`
  - `JSONTree.key(_:) -> String?` (unescaped), `pointer(_:) -> JSONPointer`, `ancestors(_:) -> [NodeID]` (root first, excludes self), `node(at: ByteOffset) -> NodeID?` (deepest node whose `fullRange` contains the offset), `decodedValue(_:) -> String` (string unescaped; number, bool, null raw text; container and invalid → source slice), `lexStart(atOrBefore: ByteOffset) -> ByteOffset` (start of the last node starting at or before the offset; `0` if none)
  - `public enum TokenKind: Sendable { case key, string, number, literal, punctuation, comment, invalid }`
  - `public struct Token: Sendable, Hashable { let kind: TokenKind; let range: Range<ByteOffset> }`
  - `public func lex(_ source: SourceDocument, from: ByteOffset, to: ByteOffset) -> [Token]` — `from` must be outside a string; returns tokens starting before `to`

- [ ] **Step 1: Write failing tests**

```swift
@Test func pointersEscapeAndMarkDuplicates() {
  let t = tree(#"{"a/b":{"m~n":[0,{"k":1}]},"d":1,"d":2}"#)
  let k = t.children(t.children(t.children(t.children(t.root!)[0])[0])[1])[0]
  #expect(t.pointer(k).description == "/a~1b/m~0n/1/k")
  let d2 = t.children(t.root!)[2]
  #expect(t.pointer(d2).description == "/d")
  #expect(t.pointer(d2).displayString == "/d (duplicate 2 of 2)")
  #expect(t.pointer(t.root!).description == "")
}
@Test func unicodeEscapedKeysDecode() {
  let t = tree(#"{"ä😀":"\n\"x"}"#)
  let n = t.children(t.root!)[0]
  #expect(t.key(n) == "ä😀")
  #expect(t.decodedValue(n) == "\n\"x")
  #expect(t.pointer(n).description == "/ä😀")
}
@Test func nodeAtOffsetPicksDeepest() {
  let s = #"{"a": [10, 20]}"#
  let t = tree(s)
  let twenty = s.utf8.firstIndex(of: UInt8(ascii: "2"))!
  let n = t.node(at: ByteOffset(value: s.utf8.distance(from: s.utf8.startIndex, to: twenty)))!
  #expect(t.decodedValue(n) == "20")
  #expect(t.ancestors(n).count == 2)
  #expect(t.node(at: ByteOffset(value: 2)) == t.children(t.root!)[0])   // on the key -> member node
}
@Test func lexStartIsNearOffsetInMinifiedInput() {
  let s = "[" + Array(repeating: #"{"name":"x","v":1}"#, count: 50_000).joined(separator: ",") + "]"
  let t = tree(s)
  let probe = ByteOffset(value: s.utf8.count / 2)
  let start = t.lexStart(atOrBefore: probe)
  #expect(probe.value - start.value < 32)
}
@Test func lexerKinds() {
  let s = #"{"k": "v", "n": -1.5e3, "t": true, "z": null}"#
  let d = SourceDocument(bytes: Array(s.utf8))
  let kinds = lex(d, from: ByteOffset(value: 0), to: ByteOffset(value: s.utf8.count)).map(\.kind)
  #expect(kinds == [.punctuation, .key, .punctuation, .string, .punctuation,
                    .key, .punctuation, .number, .punctuation,
                    .key, .punctuation, .literal, .punctuation,
                    .key, .punctuation, .literal, .punctuation])
}
```

- [ ] **Step 2: Run** `make test` — Expected: FAIL.

- [ ] **Step 3: Implement.** `node(at:)`: binary search the last node whose start ≤ offset, then walk up through `parent` until `fullRange` contains the offset. `lexStart`: the same binary search, return that node's start. Pointer occurrence: count siblings with equal decoded key; set `occurrence`/`occurrences` only when the count > 1. Lexer: key vs string decided by the next non-whitespace byte being `:`.

- [ ] **Step 4: Run** `make test` — Expected: all PASS.

- [ ] **Step 5: Commit** `git commit -m "Add JSON pointers, offset lookup and lexer"`

---

### Task 4: Fixtures and engine benchmark

**Files:**
- Create: `Sources/bbom-bench/main.swift`, `Fixtures/public/` (CycloneDX `bom-examples` files: one 1.3 and one 1.6 example, plus `NOTICE` with source URL and Apache-2.0), `docs/findings.md`
- Modify: `Makefile` (targets `fixtures`, `bench`)

**Interfaces:**
- Consumes: `parseJSON`, `SourceDocument`, `lex`, `JSONTree.node(at:)`
- Produces: `swift run -c release bbom-bench generate --size <MB> [--minified] --out <path>` writes a synthetic CycloneDX 1.6 document (components with name, version, purl, licenses, hashes, properties; deterministic seed); `bbom-bench parse <path>` prints one line `bytes=… nodes=… sourceDocMs=… parseMs=… lookupUs=… lex64KUs=… peakRSSMB=…`

- [ ] **Step 1: Implement generator and parse command.** Peak RSS from `getrusage(RUSAGE_SELF).ru_maxrss` (bytes on macOS). `lookupUs`: mean of 1000 `node(at:)` calls at random offsets. `lex64KUs`: one `lex` over 64 KiB from `lexStart` in the middle of the file.
- [ ] **Step 2: Generate** `make fixtures` → `Fixtures/generated/{1,10,50}mb{,-min}.json`. Expected: six files within ±10 % of target size.
- [ ] **Step 3: Run** `make bench` (release build, parses all six). Expected: six result lines, no crash.
- [ ] **Step 4: Record** the table in `docs/findings.md` (machine, macOS and Xcode version, date; observations, not limits). If 50 MB parse exceeds 2 s or peak RSS exceeds 10× file size, note it and adjust the arena layout before Task 5.
- [ ] **Step 5: Commit** `git commit -m "Add fixtures and engine benchmark with first findings"`

---

### Task 5: App shell: document opening, async parse, snapshot

**Files:**
- Create: `project.yml`, `App/BeautifulBOMApp.swift`, `App/AppDelegate.swift`, `App/BOMDocument.swift`, `App/DocumentModel.swift`, `App/DocumentView.swift` (placeholder panes: "Parsing…" then node count and diagnostics count)
- Modify: `Makefile` (targets `project`, `app`, `snapshot`), `README.md`

**Interfaces:**
- Consumes: `SourceDocument`, `parseJSON`, `JSONTree`
- Produces:
  - `struct BOMDocument: FileDocument` — `readableContentTypes = [.json]`, `let bytes: [UInt8]`; read-only (`fileWrapper` throws `CocoaError(.featureUnsupported)`)
  - `@MainActor @Observable final class DocumentModel` — `let source: SourceDocument`, `private(set) var tree: JSONTree?`, `var selection: NodeID?`, `var textSize: CGFloat` (default 13, presentation 24, range 9–48), `func select(_ id: NodeID?, origin: SelectionOrigin)`, `func goBack()`, `func goForward()`, `var canGoBack/canGoForward: Bool`; `enum SelectionOrigin { case source, structure, breadcrumb, history, reveal }`. Parsing runs in `Task.detached(priority: .userInitiated)`; history records selections except those from `.history`.
  - Launch arguments handled by `AppDelegate`: `--open <path>` (opens through `NSDocumentController.shared.openDocument(withContentsOf:display:)`), `--select <json-pointer>` (selects that node once parsed), `--snapshot <png>` (once parsed and laid out, renders the front window with `cacheDisplay(in:to:)` and calls `exit(0)`), env `BBOM_TIMING=1` prints `open→parsed ms` and `open→first layout ms` to stdout.
- `project.yml`: app target `BeautifulBOM`, bundle id `de.rebaze.beautiful-bom`, macOS 15.0, Swift 6, `GENERATE_INFOPLIST_FILE`, document type `public.json` with role Viewer, ad-hoc signing `CODE_SIGN_IDENTITY: "-"`, local package `Packages/BOMCore`.

- [ ] **Step 1: Write** the files above and the Make targets: `project: xcodegen generate`; `app: project` then `xcodebuild -project BeautifulBOM.xcodeproj -scheme BeautifulBOM -configuration Debug -derivedDataPath build build | xcbeautify`; `snapshot FILE=… OUT=… [SELECT=…]` runs the built binary under `timeout 30` with `--open`, `--snapshot` and `--select`.
- [ ] **Step 2: Build** `make app` — Expected: `Build Succeeded`, no Swift 6 concurrency errors.
- [ ] **Step 3: Verify open + snapshot**

Run: `make snapshot FILE=Fixtures/public/<1.6 example>.json OUT=build/shot-shell.png`
Expected: exit 0, PNG shows the node count and "0 issues". Then with `Fixtures/edge/malformed.json`: count of errors shown, no crash.
- [ ] **Step 4: Verify manually** (record in `docs/checklist.md`, created here): File › Open works, File › Open Recent lists the file, dropping a `.json` onto the Dock icon opens it, saving is unavailable.
- [ ] **Step 5: Commit** `git commit -m "Add macOS document app shell with async parsing and snapshots"`

---

### Task 6: Source pane

**Files:**
- Create: `App/Source/SourceTextView.swift` (`NSViewRepresentable`), `App/Source/Highlighter.swift`, `App/Source/LineNumberRuler.swift`
- Modify: `App/DocumentView.swift`, `App/Commands.swift` (text size)

**Interfaces:**
- Consumes: `DocumentModel` (`source`, `tree`, `selection`, `select`, `textSize`), `lex`, `JSONTree.lexStart`, `node(at:)`, `fullRange`, `SourceDocument.nsRange/byteRange`
- Produces: `SourceTextView(model:)`; on selection from any origin other than `.source`, selects `fullRange` of the node, scrolls it to the visible centre and calls `showFindIndicator(for:)`; a user click or arrow-key selection change calls `model.select(tree.node(at:), origin: .source)`.

- [ ] **Step 1: Implement** a read-only, selectable `NSTextView` using TextKit 2 (`NSTextView(usingTextLayoutManager: true)`), `usesFindBar = true`, `isIncrementalSearchingEnabled = true`, monospaced system font at `model.textSize`, line wrapping on (minified files must stay readable). Highlighter: on viewport changes (clip view bounds notifications), take the viewport's byte range, align to 64 KiB windows, and for each window not yet coloured: `lex` from `tree.lexStart(atOrBefore:)` and apply colours with `NSTextLayoutManager.setRenderingAttributes(_:for:)` (never mutate the text storage). Colours: system semantic colours (key `.systemBlue`, string `.systemGreen`, number `.systemOrange`, literal `.systemPurple`, punctuation `.secondaryLabelColor`, invalid `.systemRed` underline) so dark mode works. Line numbers: `NSRulerView` subclass drawing numbers for visible layout fragments, using `SourceDocument.line(containing:)`; on wrapped lines only the first fragment is numbered.
- [ ] **Step 2: Commands:** View › Bigger (⌘+), Smaller (⌘−), Actual Size (⌘0), Presentation Size (⌥⌘P toggles 24 pt), all through `model.textSize`.
- [ ] **Step 3: Build and snapshot** `make app && make snapshot FILE=Fixtures/public/<1.6>.json OUT=build/shot-source.png` — Expected: coloured source with line numbers. Repeat with `Fixtures/generated/10mb-min.json` and `BBOM_TIMING=1`; record both timings in `docs/findings.md`.
- [ ] **Step 4: Manual checks** (add to `docs/checklist.md`): ⌘F finds text and ⌘G steps; scrolling a 50 MB file stays smooth; text size changes keep the selection visible; VoiceOver reads the text.
- [ ] **Step 5: Commit** `git commit -m "Add highlighted source pane with line numbers, find and text size"`

---

### Task 7: Structure pane, two-way sync, breadcrumbs, history

**Files:**
- Create: `App/Structure/StructureOutlineView.swift`
- Modify: `App/DocumentView.swift` (split view: structure | source; breadcrumb bar below), `App/Commands.swift` (Go › Back ⌘[, Forward ⌘])

**Interfaces:**
- Consumes: `JSONTree.children/childCount/kind/key/decodedValue/ancestors/pointer`, `DocumentModel.select/goBack/goForward`
- Produces: `StructureOutlineView(model:)` and `BreadcrumbBar(model:)`

- [ ] **Step 1: Implement** an `NSOutlineView` data source backed directly by `NodeID` (items boxed in a cache keyed by `NodeID`; children fetched only on expansion). Row: key or `[index]`, a kind glyph, and a one-line value preview (strings truncated to 80 characters; containers show `{n}` / `[n]`). Duplicate members show a warning glyph and the `displayString` in the tooltip. `.invalid` rows show in red with the diagnostic as tooltip. Keyboard: native arrows, ←/→ collapse/expand, ⌥-click expands all children of one node (not recursive beyond 2 000 rows).
- [ ] **Step 2: Sync.** Selection from any origin other than `.structure` expands the ancestors, selects the row and scrolls it to the visible centre. A guard flag prevents echo loops. The source pane keeps its scroll position when the selection comes from the source itself.
- [ ] **Step 3: Breadcrumbs.** `BreadcrumbBar` shows the ancestor chain from `ancestors(_:)`, each segment a button selecting that node (origin `.breadcrumb`); trailing the `pointer(_:).displayString` in a monospaced label.
- [ ] **Step 4: Snapshot with selection** `make snapshot FILE=Fixtures/edge/duplicates.json SELECT=/name OUT=build/shot-sync.png` — Expected: the first `name` member selected in both panes, breadcrumbs show `/name (duplicate 1 of 2)`.
- [ ] **Step 5: Manual checks** (checklist): click in the source selects the row; arrow keys in the outline move the source highlight; ⌘[ / ⌘] restore earlier selections and their scroll positions; keyboard-only navigation from open to copy without the mouse.
- [ ] **Step 6: Commit** `git commit -m "Add structure outline with two-way sync, breadcrumbs and history"`

---

### Task 8: Copy commands and diagnostics

**Files:**
- Modify: `App/Commands.swift`, `App/DocumentView.swift`, `App/Structure/StructureOutlineView.swift` (context menu)

**Interfaces:**
- Consumes: `JSONTree.pointer/decodedValue/fullRange`, `SourceDocument.slice`, `JSONTree.diagnostics`
- Produces: Edit menu items for the selected node: Copy JSON Pointer (⌥⌘C, RFC 6901 `description`), Copy Value (⇧⌘C, `decodedValue`), Copy Source (⌘C when the outline has focus, the exact `slice(fullRange)`); the same three in the outline's context menu.

- [ ] **Step 1: Implement** the commands through `FocusedValue` of the active `DocumentModel`, disabled without a selection.
- [ ] **Step 2: Implement diagnostics UI:** when `diagnostics` is non-empty, a banner above the panes: "2 errors, 1 warning" with a disclosure listing each message with `line:column`; clicking an entry selects the node at the diagnostic's start (origin `.reveal`) and highlights its range in the source in red. The rest of the document remains navigable.
- [ ] **Step 3: Verify** with `Fixtures/edge/escapes.json`: Copy Value on `"x\"y"` puts `x"y` on the pasteboard (`pbpaste`), Copy Source puts `"x\"y"`, Copy JSON Pointer puts the escaped pointer. Snapshot of `Fixtures/edge/malformed.json` shows the banner expanded.
- [ ] **Step 4: Commit** `git commit -m "Add copy commands and a diagnostics banner"`

---

### Task 9: Measurements, checklist, README (phase 1 done)

**Files:**
- Modify: `docs/findings.md`, `docs/checklist.md`, `README.md`

- [ ] **Step 1: Measure** the app with `BBOM_TIMING=1` on `{1,10,50}mb{,-min}.json`: time to parsed, time to first layout, memory from `footprint <pid>` (or Activity Monitor) after scrolling to the end. Add the table to `findings.md` beside the engine numbers, with observations about anything that stuttered.
- [ ] **Step 2: Accessibility pass:** VoiceOver over both panes and the breadcrumbs, Increase Contrast, Dark Mode, presentation size on a 1920×1080 external display (or the scaled equivalent). Record results in the checklist.
- [ ] **Step 3: README:** purpose (two sentences), requirements (macOS 15+, Xcode 27.2), `make test`, `make app`, `make snapshot`, tested platform, known limitations (read-only, JSON only, no source folding unless Task 11 lands), link to findings and checklist, extraction note.
- [ ] **Step 4: Run** `make test && make app` — Expected: all tests PASS, `Build Succeeded`.
- [ ] **Step 5: Commit** `git commit -m "Record findings, checklist and README for the JSON reader"`

---

### Task 10 (optional, phase 2): CycloneDX overview and component details

**Files:**
- Create: `Sources/BOMCore/CycloneDX.swift`, `Tests/BOMCoreTests/CycloneDXTests.swift`, `App/CycloneDX/OverviewView.swift`, `App/CycloneDX/ComponentDetailView.swift`
- Modify: `App/DocumentView.swift` (a "Overview / Structure" switch at the top of the sidebar when recognised)

**Interfaces:**
- Consumes: `JSONTree` queries
- Produces:
  - `public struct Located<Value: Sendable>: Sendable { let value: Value; let node: NodeID }`
  - `public struct CycloneDXDocument: Sendable` — `static func recognize(_ tree: JSONTree) -> CycloneDXDocument?` (root object with `bomFormat` == `"CycloneDX"`), `specVersion: Located<String>?`, `serialNumber: Located<String>?`, `subject: Located<String>?` (`metadata.component.name`), `toolNames: [Located<String>]` (1.4 array and 1.5+ `tools.components` forms), `componentNodes: [NodeID]` (top-level `components` children, nested ones reachable through detail)
  - `public struct ComponentDetail: Sendable` — `init(tree:node:)`; `name, version, group, purl, type: Located<String>?`; `licenses: [Located<String>]` (license `id`, else `name`, else `expression`); `hashes: [Located<String>]` ("alg: content"); `unknownFields: [Located<String>]` (keys not in the above, value preview); `missing: [String]` from the expected set `["name", "version", "purl", "licenses"]`

- [ ] **Step 1: Write failing tests** on the public 1.3 and 1.6 fixtures: `recognize` succeeds and returns the specVersion text; the first component's `licenses[0].node` slices back to exactly the license id's value in source; a hand-written component without `purl` lists `"purl"` in `missing`; an unknown key `x-team` appears in `unknownFields`; a non-CycloneDX document returns `nil`.
- [ ] **Step 2: Run** `make test` — Expected: FAIL. **Step 3: Implement.** **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: UI.** Overview: format, spec version, serial number, subject, tools, component count; a lazily loaded component list (name, version, first license). Component detail: labelled fields; missing fields shown as "Not stated" in secondary text; unknown fields listed under "Other fields". Every field has a "Reveal in Source" button (⌘R for the focused field): `model.select(node, origin: .reveal)`, which highlights the exact range; ⌘[ returns to the detail with its scroll position.
- [ ] **Step 6: Snapshot** detail view and revealed license; add to checklist. **Commit** `git commit -m "Add CycloneDX overview and component details with reveal in source"`

---

### Task 11 (stretch): Folding in the source pane

Only after Task 9. Try TextKit 2 folding by hiding paragraphs through `NSTextContentStorageDelegate` (substituting a placeholder paragraph for folded ranges) with a fold gutter in `LineNumberRuler`. Keep the byte↔UTF-16 mapping untouched (folding is presentation only; selection and find must still address original offsets). If find, selection or copy become unfaithful, drop it and write why in `findings.md`. Commit either the feature or the finding.

---

## Cut-off (after Task 9, or 10/11)

Not a code task. Close issue #151 with a summary, then split `apps/beautiful-bom/` with history into a new `rebaze/` repository (`git filter-repo --subdirectory-filter apps/beautiful-bom` on a fresh clone), and remove the folder and the `AGENTS.md` row here in one commit.
