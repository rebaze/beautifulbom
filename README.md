# Beautiful Bill of Materials

A native macOS reader for bills of materials: pleasant to read, and always one step from the exact bytes in the original file. Proof of concept (issue #151), working title. A CycloneDX SBOM opens as a workshop presentation (Overview, Composition, Completeness, Components); any other JSON opens in the source reader.

- Design: [docs/design.md](docs/design.md) (JSON reader), [docs/design-workshop-views.md](docs/design-workshop-views.md) (workshop views)
- Plans: [docs/plan.md](docs/plan.md), [docs/plan-workshop-views.md](docs/plan-workshop-views.md)
- Findings and measurements: [docs/findings.md](docs/findings.md) · Manual checklist: [docs/checklist.md](docs/checklist.md)

## Workshop views (CycloneDX 1.2 and later)

- **Overview**: product, version, what it is built on; components, chosen directly → pulled in, ecosystems, licences; vendor and licence bars; who made the SBOM and when; one verdict sentence on BSI TR-03183-2.
- **Composition**: components by vendor and by licence (click a segment for those components), and a histogram of how many steps each component is from the product.
- **Completeness**: BSI TR-03183-2 2.1.0, presence and form of fields only, counted exactly as rio's `bsi-tr-03183-2@2.1.0` profile counts. An SBOM older than CycloneDX 1.6 gets the version gap stated once, and rules whose field is newer than the file say so.
- **Components**: search and filter (licence is / is not, missing field, depth); each opens a component page with identity, licence, hashes, references, gaps, and "Why is it here?" (the path from the product, and who uses it).
- **Evidence**: every statement is a button. It opens the source in a drawer underneath at the exact range; a missing field shows a red marker where it would be. Esc closes the drawer, ⌥⌘E keeps it open. Back/Forward (⌘[ ⌘]) walk through tabs and component pages; ⌘1–⌘5 switch tabs.
- **Language**: View › Language switches the workshop views between English and German at once.

## Source reader

- Opens local JSON files (File › Open, recent documents, Dock drop). No network, no account, no upload.
- Shows the original source with syntax colour, line numbers, the system find bar and adjustable text size. Edit › Find (⌘F, ⌘G, ⇧⌘G, ⌘E) works from every tab: it switches to Source and searches the whole file while you type (⌘+ ⌘− ⌘0, presentation size ⌥⌘P).
- A structure outline in sync with the source: select in either and the other follows to the exact range. Objects show a readable hint (name, version).
- Breadcrumbs and the JSON Pointer of the selection; duplicate keys are marked (`/name (duplicate 2 of 2)`).
- Copy JSON Pointer (⌥⌘C), Copy Value (⇧⌘C), Copy Source (⌥⇧⌘C, or ⌘C in the outline). Go › Back/Forward (⌘[ ⌘]).
- Malformed files stay readable: a banner lists each problem with line and column, and everything that could be parsed stays navigable.
- Large files: 50 MB shows in about a second; minified files are wrapped for display without changing what is copied.

## Build and run

`make install` builds the Release app and copies it to `~/Applications`, so Spotlight, Launchpad and the Dock find it. Open an SBOM with ⌘O, by dropping it on a window or on the Dock icon, or with Finder › Open With. Started without a file, it shows a welcome window with recent files and three bundled samples (Window › Welcome to Beautiful BOM, ⇧⌘1). The icon is the rebaze mark; `scripts/icon/make-icon.sh` renders it from `scripts/icon/icon.svg` (needs `rsvg-convert`). Design: `docs/design-branding.md`.

Requirements: macOS 15 or later, Xcode 27.2 (Swift 6.4), [XcodeGen](https://github.com/yonaskolb/XcodeGen), [xcbeautify](https://github.com/cpisciotta/xcbeautify).

```sh
make test                      # string catalog check and BOMCore engine tests (Swift Testing)
make app                       # Debug build: build/Build/Products/Debug/BeautifulBOM.app
make app CONFIG=Release        # for measurements
make fixtures && make bench    # synthetic 1/10/50 MB fixtures and engine timings
make snapshot CONFIG=Release FILE=Fixtures/public/laravel-7.12.0.cdx-1.4.json OUT=build/shot.png SELECT=/components/3
```

Launch options for checks and agents: `--window-size <WxH>`, `--open <file>`, `--select <json-pointer>`, `--copy pointer|value|source`, `--view overview|composition|completeness|components|source`, `--component <bom-ref>`, `--evidence <rule id>` (e.g. `sbom.timestamp`), `--language de|en`, `--show welcome|about`, `--find <text>` (opens the find bar from the current tab and types the text key by key; with `BBOM_TIMING=1` it prints each key's cost), `--snapshot <png>` (renders the window and quits; needs no Screen Recording permission), `--text-size <pt>`, `--appearance dark|light`, and `BBOM_TIMING=1`. `make screenshots` renders every workshop view into `build/screenshots/`.

The TR-03183-2 checks are a port of rio's profile. `make test` compares them with rio's results committed in `Fixtures/parity/`; `make parity-refresh` regenerates those with the `rio` on your PATH.

Tested on macOS 27.2.1 (Apple Silicon) with Xcode 27.2.

## Layout

- `Packages/BOMCore`: the engine, no dependencies, macOS and iOS. Source bytes and offsets (`SourceDocument`), error-tolerant parser into a node arena (`parseJSON`, `JSONTree`), JSON Pointers, lexer, `DisplayText`. `CycloneDX/`: the SBOM model, dependency graph and composition, every value with the node it came from (`Evidence`). `Checks/`: TR-03183-2 2.1.0 (port of rio) and SPDX. `Workshop/`: the completeness report, verdict, filters and history the views show. Everything is addressed by byte ranges into the original file.
- `App`: SwiftUI document app hosting AppKit views (TextKit 2 `NSTextView`, `NSOutlineView`); `App/Workshop/` holds the four views, the evidence drawer and the German/English string catalog (`App/Localizable.xcstrings`).
- `Fixtures`: public CycloneDX examples (CC0), rio's two profile fixtures (Apache-2.0), hand-written edge cases and synthetic SBOMs, rio's results for the parity test, generated large files (git-ignored).

## Limitations

Read-only. JSON only; workshop views for CycloneDX, not yet SPDX or AIBOM. Completeness reports presence and form of fields, never conformity. No folding in the source pane. Find misses a match that spans a display break in a minified line. Ad-hoc signed: on another Mac, open it with right-click › Open.

## Moving out

Everything lives in this folder and references nothing outside it. To split it into its own repository with history: `git filter-repo --subdirectory-filter apps/beautiful-bom` on a fresh clone.
