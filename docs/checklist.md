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
