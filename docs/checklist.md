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

## Workshop views (plan-workshop-views.md, Tasks 10–16)

- ✅ A CycloneDX file opens on the Overview with tabs; any other JSON opens in the source reader without tabs (snapshots `w-overview-laravel`, `w-source-only`).
- ✅ Overview at 1440×900 and at 24 pt, light and dark, English and German: nothing clips (`make screenshots`).
- ✅ Evidence drawer: a located statement selects its exact range; an absent field shows the red "would be here" marker after the parent's opening line, or right-aligned on that visual line when a minified line wraps (`--evidence sbom.timestamp` on pretty and minified Laravel).
- ✅ A CycloneDX file with parse errors never gets the all-present verdict (`Fixtures/edge/bsi-pass-broken.cdx.json`: "The file has 2 errors; the checks cover what could be read.").
- ✅ Composition: Laravel vendors (symfony 27 first), licences (MIT 57), depth histogram 1/5/30/21/4/1; CERN says "no dependency data".
- ✅ Completeness: Laravel shows the version gap and "field introduced in CycloneDX 1.6" on manufacturer and concluded licence; rio's bsi-pass shows every row present and the all-present sentence.
- ✅ Component page for doctrine/lexer: path product → laravel/laravel → laravel/framework → egulias/email-validator → doctrine/lexer; used by egulias/email-validator.
- ✅ 50 MB minified (120 686 components) opens on Components with a lazy list (Release: open→parsed 1.8 s).
- ⏳ Clicking a statement opens the drawer; Esc closes it; ⌥⌘E (View › Keep Evidence Open) keeps it open and Esc then does nothing.
- ⏳ Back/Forward (⌘[ ⌘]) walk tab → component page → another component page (via "Why is it here?") → tab, and back.
- ⏳ ⌘1–⌘5 switch tabs; clicking a bar segment or histogram bar opens Components with that filter; Clear resets it.
- ⏳ After leaving the Source tab (drawer closed), ⌘F and ⌘C do nothing in the hidden source view.
- ⏳ Dragging the line above the drawer resizes it; dragging the line beside the outline resizes the outline.
- ⏳ View › Language switches all workshop views at once; the choice survives a restart.
- ⏳ Typing in the Components search with the 50 MB file stays responsive.
- ⏳ Full-screen 1920×1080 at presentation size (⌥⌘P): the room can read the Overview and Completeness from the back.
- ⏳ VoiceOver: tab buttons, stat cards, rows and evidence buttons are named.
