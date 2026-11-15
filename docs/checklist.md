# Manual interaction checklist

Run with `make app`, then open `build/Build/Products/Debug/BeautifulBOM.app`. Fixtures: `Fixtures/public/`, `Fixtures/edge/`, `Fixtures/generated/` (`make fixtures`).
Status: ✅ verified · ⏳ to check by hand (needs a person at the Mac) · ❌ failed. Agents verify what the `--snapshot` option can show; the rest stays ⏳ until checked.

## Opening (Task 5)

- ✅ `--open` opens a file through the document system; the title bar shows the name (snapshot).
- ✅ A malformed file opens and reports its issues instead of failing (snapshot of `Fixtures/edge/malformed.json`).
- ⏳ File › Open shows the standard panel and opens a `.json` file.
- ⏳ File › Open Recent lists the file afterwards.
- ⏳ Dropping a `.json` file onto the Dock icon opens it.
- ⏳ Save and Duplicate are unavailable or refuse cleanly (read-only viewer).

## Source pane (Task 6)

- ✅ Coloured source with line numbers; a wrapped line is numbered once (snapshots of laravel, 10 MB, 50 MB).
- ✅ Minified 10 MB and 50 MB files display and wrap; reveal lands on the exact range deep inside the single line (snapshot `SELECT=/components/1200/licenses/0/license/id`).
- ✅ Reveal from launch selects the node's full range and centres it (10 MB pretty, line 32 435).
- ⏳ ⌘F opens the find bar, typing finds incrementally, ⌘G steps to the next match.
- ⏳ Scrolling through the 50 MB file stays smooth; colour appears as regions scroll in.
- ⏳ ⌘+ / ⌘− / ⌘0 change the text size and keep the selection visible; ⌥⌘P toggles presentation size (24 pt).
- ⏳ ⌘C in the source of a minified file copies the original text, without line breaks added for layout.
- ⏳ VoiceOver reads the source text.

## Structure, sync, breadcrumbs (Task 7)

- ✅ A launch selection expands the outline to the node, selects and centres it, and reveals the same range in the source (10 MB, `/components/2000/hashes/0/content`).
- ✅ Duplicate keys show a warning badge; the breadcrumb pointer reads `/name (duplicate 1 of 2)` (`Fixtures/edge/duplicates.json`).
- ✅ Object rows show a readable hint (name, else id/bom-ref, plus version), e.g. `[2001] {9} guava-2001 7.15.44`.
- ⏳ Clicking in the source selects the matching outline row; arrow keys in the outline move the source highlight.
- ⏳ Breadcrumb segments select their node.
- ⏳ ⌘[ and ⌘] (Go › Back/Forward) return to earlier selections.
- ⏳ ⌥-click on a disclosure triangle expands a small subtree fully but only one level of a large one (> 2 000 nodes).
- ⏳ Keyboard only: open a file, move through the outline, copy a pointer, without the mouse.

## Copy and diagnostics (Task 8)

- ✅ Copy Value / Copy Source / Copy JSON Pointer put the decoded value, the original fragment and the RFC 6901 pointer on the pasteboard (`--copy` with `pbpaste`, `Fixtures/edge/escapes.json`: `x"y`, `"x\"y": "x\"y"`, `/path~1with~0tilde`).
- ✅ A broken file shows a banner with errors and warnings by line:column, while the rest stays navigable (`Fixtures/edge/workshop-broken.json`).
- ⏳ Edit menu: Copy JSON Pointer ⌥⌘C, Copy Value ⇧⌘C, Copy Source ⌥⇧⌘C; ⌘C in the outline copies the source; the outline's context menu offers all three.
- ⏳ Clicking a diagnostic reveals its exact range in the source.

## Appearance and accessibility (Task 9)

- ✅ Dark appearance: semantic colours throughout, selection and highlights readable (`--appearance dark`).
- ✅ Presentation size starts at 24 pt in both panes (`--text-size 24`); see the open point on narrow windows in findings.md.
- ⏳ Presentation size full-screen on a 1920×1080 display: source readable from the back of a room, no one-word lines.
- ⏳ VoiceOver: outline rows read "key, value"; the source reads as text; breadcrumb buttons are named; the diagnostics banner announces its summary.
- ⏳ Increase Contrast and Reduce Transparency: nothing disappears.
