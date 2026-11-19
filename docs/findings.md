# Findings

Observations, not promised limits. Machine: Apple Silicon Mac, macOS 27.2.1, Xcode 27.2 (Swift 6.4.2).

## Engine (`make bench`, release build, 2026-11-15)

| File | Size | Nodes | SourceDocument | Parse | `node(at:)` | Lex 64 KiB | Peak RSS |
|---|---:|---:|---:|---:|---:|---:|---:|
| cern-lhc-vdm-editor (CDX 1.2) | 40 KB | 1 109 | 0.1 ms | 0.3 ms | 0.1 µs | 47 µs | 6 MB |
| laravel-7.12.0 (CDX 1.4) | 140 KB | 2 732 | 0.3 ms | 0.7 ms | 0.1 µs | 265 µs | 7 MB |
| synthetic, pretty | 1 MB | 29 279 | 2.0 ms | 5.8 ms | 0.1 µs | 168 µs | 11 MB |
| synthetic, minified | 1 MB | 46 569 | 2.0 ms | 8.8 ms | 0.2 µs | 158 µs | 11 MB |
| synthetic, pretty | 10 MB | 291 004 | 21 ms | 57 ms | 0.5 µs | 164 µs | 51 MB |
| synthetic, minified | 10 MB | 461 054 | 18 ms | 91 ms | 0.7 µs | 163 µs | 63 MB |
| synthetic, pretty | 50 MB | 1 449 510 | 103 ms | 307 ms | 1.1 µs | 143 µs | 241 MB |
| synthetic, minified | 50 MB | 2 293 053 | 91 ms | 445 ms | 2.7 µs | 158 µs | 301 MB |

- Peak memory is about 5–6× the file size: file bytes, the decoded `String`, the `Data` read buffer and the node arena (11 `Int32` columns plus the kind, about 45 bytes per node). Well inside the plan's 10× threshold, so the arena layout stays.
- Lexing a 64 KiB window costs the same in the middle of a 50 MB single-line file as in a 1 MB one: highlighting is bounded by the visible range, not by the line.
- Minified files have about 1.6× the nodes per byte, because there is no whitespace.

## App (Release build, `BBOM_TIMING=1`, 2026-11-15)

Whole app with structure pane, source pane, breadcrumbs and a launch reveal of `/components/1200/licenses/0/license/id`. "First layout" is when the source first shows; peak RSS is the whole process (`/usr/bin/time -l`).

| File | Open → parsed | Open → first layout | Peak RSS |
|---|---:|---:|---:|
| laravel-7.12.0 (CDX 1.4, 140 KB) | 39 ms | 154 ms | 149 MB |
| synthetic 1 MB, pretty | 41 ms | 209 ms | 165 MB |
| synthetic 1 MB, minified | 43 ms | 90 ms | 178 MB |
| synthetic 10 MB, pretty | 108 ms | 180 ms | 220 MB |
| synthetic 10 MB, minified | 159 ms | 348 ms | 259 MB |
| synthetic 50 MB, pretty | 505 ms | 863 ms | 501 MB |
| synthetic 50 MB, minified | 724 ms | 1 128 ms | 668 MB |

The app's baseline is about 140 MB (SwiftUI, AppKit, text system); a document adds about 7–10× its size at 50 MB.

## Lessons

- **Minified files and TextKit 2.** TextKit 2 lays out whole paragraphs. A 10 MB one-line file (one paragraph) did not display within 30 s and grew to 2.4 GB. `DisplayText` now gives very long lines invisible paragraph breaks after a comma outside a string, about every 4 KB. Wrapped on screen they look like soft wraps. All offsets pass through the mapping, and Copy takes the original bytes. Limitation: a find whose match spans such a break (e.g. `,"name"` exactly there) misses that one occurrence.
- **Debug builds are about 7× slower in the engine** (50 MB parse 3.4 s vs 0.5 s). Measure with `make app CONFIG=Release`.
- **Colour** is TextKit 2 rendering attributes over 64 KiB windows, applied when they scroll into view; token offsets are converted in one forward walk (`utf16Offsets(ofSorted:)`).
- **Hanging indents.** Wrapped lines continue at their own indentation (capped at half the pane width), applied per window as they scroll in. Clearly more readable at normal size.
- **Scroll views and rulers.** In current AppKit the line-number ruler is a content inset of a full-width clip view; scrolling to an absolute `x = 0` slides text under the ruler. Always scroll via `constrainBoundsRect` and keep `x`.
- **Launch-time reveal** must wait until the views are in a window and sized; selections made before that silently do nothing.
- **Setting the text fires a selection change**; attach the text view's delegate after the text is in, or the first "user" selection overwrites the launch selection.
- **Self-snapshots** (`--snapshot`) render everything except vibrancy materials: the source-list selection draws black. The outline uses the inset style instead.
- **Build checks** must use the exit status: filtering `xcodebuild | xcbeautify` output for "error" missed its `❌` lines, and several snapshots showed a stale binary.

## Final review fixes (2026-11-15)

A fresh whole-branch review measured triggers the plan's tests missed. Fixed, each with a regression test:

| Input | Before | After |
|---|---|---|
| 200 000 diagnostics (a comment on every line) | SwiftUI crash; 5 000 already froze for 6 s | opens in 0.19 s; first 1 000 listed, total stated |
| 10 MB base64 string (CycloneDX attachment) | 12 s main-thread stall, 1.65 GB | first layout 0.13 s, 191 MB |
| 50 MB minified with one stray `}` | colouring lexed from byte 782 for every window (≈150 ms, 200 MB each) | lexing starts within 4 KB of the window |
| `{"a": [{x]}, "b": 1}` | phantom node, bracket lost | bracket re-handled, no phantom |
| `{"a":,"b":1}` | `a` took `"b"` as its value | `a` is an empty invalid value, `b` is kept |
| Latin-1 bytes in a string | silent `�` | warning with the byte range |

## Find from every tab (2026-11-16)

Edit › Find is the app's own menu (replacing the text-editing group), so ⌘F works on every tab: it switches to Source, gives the text view the keyboard and opens AppKit's find bar, which searches incrementally. Find Next and Previous leave the keyboard in the search field. No Replace: the file is read-only.

Typing measured with `--find` (Release, real key events through the window, 90 ms between keys): no key cost more than 38 ms on the main thread, and the main thread was never busy for more than 10 ms between keys, on both 50 MB files; AppKit counts and highlights in the background (5 397 matches for "left-pad-2" in the minified file). After a find-bar jump the viewport range can still start below the top of the visible area; the line-number ruler now starts at the fragment at the top of the visible rect instead.

## Workshop views (2026-11-15)

Analysis = CycloneDX model, dependency graph, TR-03183-2 checks, composition and completeness report, after the parse (`make bench`, `bbom-bench analyse`, Release, Apple Silicon). Generated files now carry a dependency tree (six children per node) and one composition.

| File | Components | Offenders | Parse | Analysis |
|---|---:|---:|---:|---:|
| Laravel (public) | 62 | 507 | 0.9 ms | 1.5 ms |
| 10 MB pretty | 15 315 | 107 213 | 96 ms | 139 ms |
| 10 MB minified | 24 265 | 169 863 | 133 ms | 224 ms |
| 50 MB pretty | 76 289 | 534 031 | 494 ms | 711 ms |
| 50 MB minified | 120 686 | 844 810 | 650 ms | 1 178 ms |

Peak memory of `bbom-bench analyse` on the 63 MB minified file: about 1.1 GB (tree, model and 845 000 findings).

App, Release, `BBOM_TIMING=1`: 50 MB pretty open→parsed 1 222 ms, first layout 1 503 ms; 50 MB minified 1 812 ms and 2 131 ms. The display text is built while the tree is parsed and analysed.

The first version took 2 056 ms for the minified 50 MB file. What it cost, and the fix:

- Every field lookup scanned the component's members again (about 25 scans per component): one pass now.
- The checks re-read properties and references from the tree for each rule: they read the component model, except creator and licences, which keep rio's raw-JSON semantics.
- `Level.fields` built a new `Set` on every rule check (about a million allocations): bit masks.
- Package URLs were parsed with Foundation string functions (≈ 270 ms): a byte-level parser.

Parity with rio: the port agrees with rio 0.10.2 on all five parity files (both public SBOMs, rio's pass and fail fixtures, a synthetic edge file with duplicate keys, every level, a URL without host, lower-case and `WITH` expressions). The one deliberate difference: rio raises a pre-1.6 file to 1.6 before checking, so its receipt passes `sbom.specVersion`; the app judges the file as it is.

## Open points

- **Presentation size in a narrow window.** At 24 pt in a 450 pt source pane, deep JSON wraps heavily even with capped indents, and the outline's disclosure triangles sit low in the taller rows. Untested full-screen (the workshop case); a presentation layout that hides the structure pane may be the better answer.
- **Lone CR line endings** (classic Mac) break paragraphs in the text view but not in the line index, so line numbers drift. Not seen in BOMs.
- **Source folding** (plan Task 11) not attempted.
- **Search on very large SBOMs** recomputes the filter on every keystroke (120 000 components); it may need debouncing.
- **German wording** is the builder's; Toni reviews it (`App/Localizable.xcstrings`). Menu commands follow the system language, not the in-app switch.
- **Drawer selection colour** is the inactive grey when the source view is not focused; the node highlight underneath is light.
- **Plural forms** are not handled ("1 Komponenten" cannot occur with the fixtures, but would with a one-component SBOM).
- **Deferred review minors** (2026-11-16): duplicate `dependsOn` entries can make "pulled in" negative; `pkg:npm/@scope/name` without a version does not parse; two exotic manufacturer URLs pass that Go rejects; the parse-error count includes dropped warnings; Composition counts are not evidence buttons; drag handles have no accessibility role; some dead code in `FieldChecks` and `CompletenessView`.

## Review of 36c875a..facb2fc (2026-11-16)

An independent review of the branch since the last review (Find, drop, branding, map, look, licence
families, AIBOM). No critical findings. Fixed, with `BranchReviewTests` where the engine is involved:

- Licence-family parser had no nesting cap: 3000 nested parentheses crashed the background parse.
  Now capped at SPDX's 64; deeper is "not classified".
- "Up to N steps deep" counted the rings drawn, not the depth (50 MB: said 4, is 7). Now
  `DependencyMap.deepest`; the note counts every part without a slice of its own (`notDrawn`).
- Map hover rebuilt the vendor list per slice (59 ms per redraw at 8000 vendors): computed once.
  The same for Components rows and the Overview picture (colours only when shown).
- A family tree of three or more generations was cut off: it now scrolls sideways, starting at the model.
- "fine-tuned from" claimed more than `pedigree.ancestors` says: now "based on".
- `MPL-2.0-no-copyleft-exception` was permissive: weak copyleft.
- The TR fields bar counted all 11 rules for every component: now the rules of its level
  (`WorkshopAnalysis.ruleCount`, 4 at referenced).
- "1 gaps", "1 others", "1 datasets", "1 steps": singular forms (`Lp`), depth 1 reads "chosen directly".
- Welcome recents were frozen at launch: rebuilt on every show. The Dock icon brings back a
  minimised document before showing the welcome window.
- AIBOM: a dataset `ref` matching no component is its own gap; an unnamed inline dataset counts.
- Parameter counts in German ("7,2 Mrd."), and 999.6 M rounds up to "1.0 B".
- Coverage bars in the Components list no longer grow in again while scrolling.

Deferred: VoiceOver cannot reach the map's slices (it is one element with a summary label); the
bars, legend and Components list carry the same facts.

Left as designed: "n of N fields present" counts rules met by every component; ⌘F in the Components
search goes to Source; a merged slice opens every part at that depth; OR with an unclassified
licence takes the classified side. Not measured: `LineNumberRuler` on 50 MB files after Find.

## SBOMs as the tools write them (2026-11-19)

24 SBOMs from Syft 1.57.2, Trivy 0.76.2, cdxgen 12.9.2 and the CycloneDX Maven plugin 2.9.1 on
four public subjects (`scripts/real-sboms.sh`, a Java service, Juice Shop, rio, `python:3.13-slim`),
each rendered in every view (`scripts/real-sweep.sh`, gallery in `build/screenshots/real/`).

- **CycloneDX 1.7 is the default** of Syft, Trivy and cdxgen; only the Maven plugin writes 1.6.
  The views read 1.7; rio 0.10.2 checks it too.
- **Parity holds on real output**: rio and the app judge all nine committed CycloneDX files alike
  (`Fixtures/tools/`, `Fixtures/parity/`).
- **Fast**: analysis of 2,753 components takes 23 ms; parsing 2.2 MB 19 ms.
- **The same source, different counts**: Juice Shop has 1,108 components by cdxgen, 601 by Syft,
  533 by Trivy. Material for comparing two SBOMs.
- **Fixed in the views**:
  - Syft's product has a bom-ref but no dependency entry starts at it: the Overview said "0 → 0",
    Composition "the product has no bom-ref". Both now say the dependencies do not start at the
    product (`Composition.Reach`).
  - Directory scans name the product "."; the title is now the file name, with "product named "."
    in the SBOM". Image scans put the digest into the name; it moves to the subtitle.
  - Syft lists every file of an image as a component (2,657 of 2,753): files are counted apart and
    kept out of vendors, licences and ecosystems.
  - "built on" named the first of 98 direct dependencies; it now needs exactly one.
  - Labels on the grey and pale red bar segments were white on light grey; now dark.
  - A Debian image states over 100 licence names; the caption lists ten and "n more".
- **SPDX**: Syft and Trivy write SPDX 2.3 JSON, cdxgen SPDX 3.0.1 JSON-LD. Both now get every
  view (`docs/design-spdx.md`). Trivy's SPDX tells the same story as its CycloneDX (533, 1 → 532);
  Syft's SPDX states relationships its CycloneDX lacks (73 → 529 instead of "not from the
  product"); cdxgen's SPDX 3 states no licence in SPDX terms (only in its own extension).
- Numbers followed the Mac's region ("1.108" in English); the workshop views now take the app's
  language for numbers.
- cdxgen writes absolute paths of the checkout (the user name); the script replaces them.
