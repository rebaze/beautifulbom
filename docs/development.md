# Developing Beautiful BOM

Updated: 2026-11-17. For contributors and agents; users start at the [README](../README.md).
Working rules: [AGENTS.md](../AGENTS.md). Releasing: [release.md](release.md).

## Build and run

`make install` builds the Release app and copies it to `~/Applications`, so Spotlight, Launchpad
and the Dock find it. `make dmg` writes `build/BeautifulBOM-<version>.dmg` (the app and a link to
Applications), signed ad hoc: another Mac asks once, under System Settings › Privacy & Security ›
Open Anyway. Releases are signed with rebaze's Developer ID and notarized by the release workflow
(`docs/release.md`). The icon is the rebaze mark; `scripts/icon/make-icon.sh` renders it from
`scripts/icon/icon.svg` (needs `rsvg-convert`). Design: `docs/design-branding.md`.

Requirements: macOS 15 or later, Xcode 27.2 (Swift 6.4), [XcodeGen](https://github.com/yonaskolb/XcodeGen), [xcbeautify](https://github.com/cpisciotta/xcbeautify).

```sh
make test                      # string catalog check and BOMCore engine tests (Swift Testing)
make app                       # Debug build: build/Build/Products/Debug/BeautifulBOM.app
make app CONFIG=Release        # for measurements
make fixtures && make bench    # synthetic 1/10/50 MB fixtures and engine timings
make snapshot CONFIG=Release FILE=Fixtures/public/laravel-7.12.0.cdx-1.4.json OUT=build/shot.png SELECT=/components/3
```

Launch options for checks and agents: `--window-size <WxH>`, `--open <file>`, `--select <json-pointer>`, `--copy pointer|value|source`, `--view overview|composition|completeness|components|source`, `--component <bom-ref>`, `--evidence <rule id>` (e.g. `sbom.timestamp`), `--language de|en`, `--show welcome|about`, `--point <bom-ref>` (on the map, show a part as if pointed at), `--find <text>` (opens the find bar from the current tab and types the text key by key; with `BBOM_TIMING=1` it prints each key's cost), `--snapshot <png>` (renders the window and quits; needs no Screen Recording permission), `--text-size <pt>`, `--appearance dark|light`, and `BBOM_TIMING=1`. `make screenshots` renders every workshop view into `build/screenshots/`.

The TR-03183-2 checks are a port of rio's profile. `make test` compares them with rio's results committed in `Fixtures/parity/`; `make parity-refresh` regenerates those with the `rio` on your PATH.

Tested on macOS 27.2.1 (Apple Silicon) with Xcode 27.2.

## Layout

- `Packages/BOMCore`: the engine, no dependencies, macOS and iOS. Source bytes and offsets (`SourceDocument`), error-tolerant parser into a node arena (`parseJSON`, `JSONTree`), JSON Pointers, lexer, `DisplayText`. `CycloneDX/`: the SBOM model, dependency graph and composition, every value with the node it came from (`Evidence`). `Checks/`: TR-03183-2 2.1.0 (port of rio) and SPDX. `Workshop/`: the completeness report, verdict, filters and history the views show. Everything is addressed by byte ranges into the original file.
- `App`: SwiftUI document app hosting AppKit views (TextKit 2 `NSTextView`, `NSOutlineView`); `App/Workshop/` holds the four views, the evidence drawer and the German/English string catalog (`App/Localizable.xcstrings`).
- `Fixtures`: public CycloneDX examples (CC0), rio's two profile fixtures (Apache-2.0), hand-written edge cases and synthetic SBOMs, rio's results for the parity test, generated large files (git-ignored).

## Design and records

- Design: [design.md](design.md) (source reader), [design-workshop-views.md](design-workshop-views.md),
  [design-branding.md](design-branding.md), [design-beautiful-views.md](design-beautiful-views.md),
  [spike-aibom.md](spike-aibom.md) (AIBOM view)
- Plans: [plan.md](plan.md), [plan-workshop-views.md](plan-workshop-views.md)
- Measurements and reviews: [findings.md](findings.md) · What is verified: [checklist.md](checklist.md)
  · By hand: [hand-check.md](hand-check.md) · Next: [roadmap.md](roadmap.md)

## README screenshots

`scripts/readme-screenshots.sh` renders the pictures in `docs/images/` from the public samples with
the Release app (`make app CONFIG=Release` first).
