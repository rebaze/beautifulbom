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

## Open points

- **Presentation size in a narrow window.** At 24 pt in a 450 pt source pane, deep JSON wraps heavily even with capped indents, and the outline's disclosure triangles sit low in the taller rows. Untested full-screen (the workshop case); a presentation layout that hides the structure pane may be the better answer.
- **Lone CR line endings** (classic Mac) break paragraphs in the text view but not in the line index, so line numbers drift. Not seen in BOMs.
- **Source folding** (plan Task 11) not attempted.
