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
