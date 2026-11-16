# Beautiful Bill of Materials: design

Status: approved for the macOS proof of concept (Toni, 2026-11-15). Working title.

## Intent

Opening a bill of materials should feel like reading a document, not like
reading JSON in a text editor. Beautiful Bill of Materials (BBOM) is a native
Apple reader for BOMs: readable where abstraction helps, and always one step
away from the exact bytes in the original file that support what is shown.

Audience: practitioners inspecting BOMs, customer workshops (projector, large
type), teaching. Monetization is not the driver. Inspiration: Marked, a
focused, careful document reader; take the care, not the interface.

## Goals of the proof of concept

1. An excellent read-only macOS JSON reader: faithful source with syntax
   colour, line numbers, search, adjustable text size; a structure pane in
   sync with the source; breadcrumbs / JSON Pointer; copy path, value and
   original source fragment; malformed files stay readable with diagnostics.
2. Exact structure-to-source mapping for nested objects, arrays, repeated
   values, escaped strings, Unicode (including characters outside the BMP)
   and duplicate keys.
3. Measured responsiveness and memory at about 1, 10 and 50 MB.
4. Optional, once 1 to 3 feel convincing: recognise CycloneDX, show a small
   overview and readable component details, each with "Reveal in Source".

## Non-goals

Editing, network access of any kind, accounts, a document library or server,
SPDX/AIBOM views, iPad/iPhone apps, Quick Look, distribution. These stay in
the later exploration list of the proposal (GitHub issue).

## Anti-goals

- Locating source by reserializing parsed JSON or by searching for values.
- Dropping unknown fields or hiding that a field is missing.
- Eagerly building UI for every node of a large document.
- Anything that needs an upload or a connection to read a local file.

## Constraints

- Swift 6 (strict concurrency), SwiftUI, AppKit where SwiftUI lacks control.
- Xcode 27.2, macOS 27 SDK; deployment target macOS 15, iOS 18 for the
  shared package so the iPad step needs no engine changes.
- No third-party dependencies in the engine.
- Fixtures are public (CycloneDX bom-examples, Apache-2.0) or synthetic.
  Never customer data, not even git-ignored inside this folder.
- Self-contained in `apps/beautiful-bom/`: no paths outside it, so it can be
  split into its own repository with history (see Extraction).

## Approaches considered

| Approach | Trade-off | Verdict |
|---|---|---|
| Own byte-level parser with source ranges (chosen) | More code to own; exact ranges, error recovery, duplicate keys, no dependencies | Chosen: the defining interaction depends on it |
| Foundation `JSONSerialization`/`JSONDecoder` plus value search | Little code; no positions, loses duplicates and number text, fails on malformed input | Rejected: the proposal rules it out and it cannot be exact |
| Web view (CodeMirror, Monaco) inside a native shell | Folding and highlighting for free; not native text, weaker accessibility and typography, two runtimes | Rejected: the goal is a native document app |

## Architecture

### `BOMCore` (Swift package, macOS + iOS)

- `SourceDocument`: the original bytes, authoritative and never rewritten.
  A line index (byte offset of each line start) and a UTF-8 to UTF-16
  mapping with a checkpoint per line, because AppKit/UIKit text uses UTF-16
  offsets. Conversions are explicit types (`ByteOffset`, `UTF16Offset`).
- `JSONParser`: error-tolerant, iterative (explicit stack, so deep nesting
  cannot overflow the call stack), runs off the main thread. Produces a flat
  node arena: per node its kind, parent, first child, next sibling, key byte
  range, value byte range, depth. `NodeID` is the arena index and the only
  identity.
- Diagnostics: byte range, message, what recovery did. A malformed document
  still yields every node parsed before and, where recovery allows, after the
  error.
- Duplicate keys: each member is its own node. Its JSON Pointer is displayed
  with an occurrence marker and a warning; code never looks nodes up by
  pointer.
- JSON Pointer (RFC 6901) from decoded keys; raw source text from ranges.
- Lookup "node at byte offset" for source-to-structure sync.
- Highlighting tokens are lexed per line on demand. JSON strings cannot
  contain raw newlines, so each line lexes on its own, without the tree.

### `BeautifulBOM` app (macOS)

- `DocumentGroup(viewing:)`: the standard open panel, recent documents,
  drag onto the Dock icon; plus drop onto the window.
- Window: structure pane (NSOutlineView: lazy, native keyboard navigation
  and accessibility) | source pane (read-only NSTextView with TextKit 2,
  colour applied as rendering attributes for the visible range only, line
  number gutter, the system find bar) | footer with breadcrumbs.
- Selecting in either pane selects and reveals in the other, without losing
  the scroll position or selection of the pane you came from.
- Copy: JSON Pointer, decoded value, original source fragment (menu and
  context menu, with keyboard shortcuts).
- Text size: Cmd-plus / Cmd-minus, and a presentation size for workshops.
- Diagnostics: a banner with the count; the list jumps to each location.
- `--snapshot <png> <file>` renders the window into a PNG and quits, for
  visual checks by agents without Screen Recording permission.

## Decided in the spike (2026-11-15)

Swift package tests (Swift Testing), xcodegen project generation, xcodebuild,
and a SwiftUI window hosting NSTextView with highlighting placed by byte
range all work on this machine. Screenshots from the shell need Screen
Recording permission; hence the self-snapshot option.

## Left to the builder

- Folding in the source pane. Folding in the structure pane is required;
  folding in the source is a stretch goal, evaluated with TextKit 2 (hiding
  paragraphs through the content storage delegate) and dropped if it
  compromises faithful text.
- Arena layout and checkpoint density, chosen from the 50 MB measurement.
- Exact visual styling: system fonts, a calm light and dark appearance.

## Verification

- Swift Testing suites for the source mapping: nested, arrays, repeated
  values, escapes, Unicode incl. surrogate pairs, duplicates, empty
  containers, malformed input, deep nesting.
- A fixture generator for synthetic CycloneDX-like files at 1/10/50 MB;
  timings and peak memory recorded in `docs/findings.md`.
- A manual interaction checklist (keyboard only, VoiceOver, presentation
  size) in `docs/checklist.md`.
- `make test`, `make app`, `make snapshot` documented in the README.

## Extraction

When the proof of concept is done: `git filter-repo --subdirectory-filter
apps/beautiful-bom` (or `git subtree split`) into a new `rebaze/` repository,
keeping history. Commits for this app touch only this folder plus one line
in `AGENTS.md`, so the split is clean.

Signing comes with the move (Toni, 2026-11-16): a release workflow in the new repository signs
the app with rebaze's Developer ID ("Developer ID Application: rebaze GmbH (32Z95ATB2T)"),
notarizes and staples the DMG from `make dmg`, and publishes it as a GitHub release, reusing rio's
setup (`MACOS_SIGN_P12`, `MACOS_SIGN_PASSWORD`, `MACOS_NOTARY_KEY`, `MACOS_NOTARY_KEY_ID`,
`MACOS_NOTARY_ISSUER_ID` in a protected environment). Until then the DMG is signed ad hoc.
