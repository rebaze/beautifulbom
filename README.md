# Beautiful Bill of Materials

A native macOS reader for bills of materials: pleasant to read, and always one step from the exact bytes in the original file. Proof of concept (issue #151), working title. This version is an excellent read-only JSON reader; BOM-specific views come next.

- Design: [docs/design.md](docs/design.md) · Plan: [docs/plan.md](docs/plan.md)
- Findings and measurements: [docs/findings.md](docs/findings.md) · Manual checklist: [docs/checklist.md](docs/checklist.md)

## What it does

- Opens local JSON files (File › Open, recent documents, Dock drop). No network, no account, no upload.
- Shows the original source with syntax colour, line numbers, the system find bar and adjustable text size (⌘+ ⌘− ⌘0, presentation size ⌥⌘P).
- A structure outline in sync with the source: select in either and the other follows to the exact range. Objects show a readable hint (name, version).
- Breadcrumbs and the JSON Pointer of the selection; duplicate keys are marked (`/name (duplicate 2 of 2)`).
- Copy JSON Pointer (⌥⌘C), Copy Value (⇧⌘C), Copy Source (⌥⇧⌘C, or ⌘C in the outline). Go › Back/Forward (⌘[ ⌘]).
- Malformed files stay readable: a banner lists each problem with line and column, and everything that could be parsed stays navigable.
- Large files: 50 MB shows in about a second; minified files are wrapped for display without changing what is copied.

## Build and run

Requirements: macOS 15 or later, Xcode 27.2 (Swift 6.4), [XcodeGen](https://github.com/yonaskolb/XcodeGen), [xcbeautify](https://github.com/cpisciotta/xcbeautify).

```sh
make test                      # BOMCore engine tests (Swift Testing)
make app                       # Debug build: build/Build/Products/Debug/BeautifulBOM.app
make app CONFIG=Release        # for measurements
make fixtures && make bench    # synthetic 1/10/50 MB fixtures and engine timings
make snapshot CONFIG=Release FILE=Fixtures/public/laravel-7.12.0.cdx-1.4.json OUT=build/shot.png SELECT=/components/3
```

Launch options for checks and agents: `--window-size <WxH>`, `--open <file>`, `--select <json-pointer>`, `--copy pointer|value|source`, `--snapshot <png>` (renders the window and quits; needs no Screen Recording permission), `--text-size <pt>`, `--appearance dark|light`, and `BBOM_TIMING=1`.

Tested on macOS 27.2.1 (Apple Silicon) with Xcode 27.2.

## Layout

- `Packages/BOMCore`: the engine, no dependencies, macOS and iOS. Source bytes and offsets (`SourceDocument`), error-tolerant parser into a node arena (`parseJSON`, `JSONTree`), JSON Pointers, lexer, `DisplayText`. Everything is addressed by byte ranges into the original file.
- `App`: SwiftUI document app hosting AppKit views (TextKit 2 `NSTextView`, `NSOutlineView`).
- `Fixtures`: public CycloneDX examples (CC0), hand-written edge cases, generated large files (git-ignored).

## Limitations

Read-only. JSON only; no CycloneDX/SPDX views yet. No folding in the source pane. Find misses a match that spans a display break in a minified line. Ad-hoc signed: on another Mac, open it with right-click › Open.

## Moving out

Everything lives in this folder and references nothing outside it. To split it into its own repository with history: `git filter-repo --subdirectory-filter apps/beautiful-bom` on a fresh clone.
