# Hand check: a workshop rehearsal in 20 minutes

Everything the snapshots cannot show, in the order of a workshop. Tick what works; note what does
not (step number and what you saw), and the agent turns each note into a fix or a ✅ in
`checklist.md`. Files: the samples on the welcome window, and `Fixtures/generated/50mb-min.json`
(`make fixtures` if missing).

## 1. Start and open (3 min)

1. [ ] Quit Beautiful BOM, start it from Spotlight. **Expect:** the welcome window, no Open panel.
2. [ ] Close the welcome window, click the Dock icon. **Expect:** the welcome window again.
3. [ ] Drop `laravel-7.12.0.cdx-1.4.json` from Finder onto the welcome window's dashed area.
   **Expect:** "Drop to open" while hovering, then the file in its own window; the welcome window
   closes.
4. [ ] Drop the same file onto the open window. **Expect:** the existing window comes to the front,
   no second window. Drop `cern-lhc-vdm-editor.cdx.json` onto it: a second window.
5. [ ] Drop a JSON file onto the Dock icon; use File › Open (⌘O) and File › Open Recent.
   **Expect:** each opens the file; Open Recent lists it.
6. [ ] File menu: Save and Duplicate. **Expect:** unavailable, or a clean refusal (read-only).

## 2. The workshop views (6 min, Laravel)

7. [ ] Switch tabs with ⌘1 to ⌘5. **Expect:** bars grow in from the left, the map opens from its
   centre; calm, not showy.
8. [ ] Overview: click "See the map →", a vendor segment, the "permissive 62" chip.
   **Expect:** Composition; Components filtered to the vendor; Components filtered to the family,
   the licence menu reads "permissive", "Clear" resets it.
9. [ ] Composition: point at slices of the map. **Expect:** everything but the path fades, the card
   follows smoothly. Click doctrine/lexer: its component page. Back (⌘[) and Forward (⌘]).
10. [ ] Click "Why is it here?" chips on a component page, then Back twice. **Expect:** the pages
    in reverse order, then the tab.
11. [ ] Click any statement with evidence (e.g. "no timestamp" on the Overview). **Expect:** the
    drawer with the source; Esc closes it; ⌥⌘E keeps it open, then Esc does nothing.
12. [ ] Drag the line above the drawer. **Expect:** the drawer resizes.
13. [ ] Click the wordmark at the top right. **Expect:** About; its rebaze.de link opens the browser.

## 3. Source and find (4 min)

14. [ ] From the Overview press ⌘F and type "lexer". **Expect:** Source, the find bar, matches
    while typing; ⌘G / ⇧⌘G step through them; Return selects; Esc closes the bar.
15. [ ] Click in the source; use the arrow keys in the outline; click breadcrumb segments.
    **Expect:** source, outline and breadcrumb stay in step.
16. [ ] Copy with ⌥⌘C (pointer), ⇧⌘C (value), ⌥⇧⌘C (source); right-click an outline row.
    **Expect:** the three copies on the pasteboard; the context menu offers all three.
17. [ ] ⌘+, ⌘−, ⌘0, then ⌥⌘P. **Expect:** text size changes, the selection stays visible;
    presentation size on and off.
18. [ ] Back on the Overview (drawer closed) press ⌘C. **Expect:** nothing from the hidden source.

## 4. Large file (3 min, 50mb-min.json)

19. [ ] Open it. **Expect:** the Overview within a few seconds; the window stays responsive.
20. [ ] Composition: point across the map. **Expect:** no stutter.
21. [ ] Components: type in the search field. **Expect:** no lag per key.
22. [ ] Source: scroll fast; ⌘F "left-pad-2". **Expect:** smooth scrolling; colour appears as
    regions scroll in; matches while typing.

## 5. AIBOM (2 min)

23. [ ] Welcome window (⇧⌘1): open both zephyr-7b-beta samples. **Expect:** the Model tab; the
    reference shows the full family tree, the generated one the red base-model box and five gaps.
24. [ ] Click a card and a gap. **Expect:** the drawer opens at that place in the file.

## 6. Room conditions (2 min)

25. [ ] Full screen on the projector or a 1920 × 1080 display, ⌥⌘P. **Expect:** Overview,
    Completeness and the AIBOM readable from the back of the room; no one-word lines.
26. [ ] View › Language › Deutsch; restart. **Expect:** all views in German, still after restart.
27. [ ] System Settings › Accessibility › Display › Reduce motion on; switch tabs. **Expect:**
    nothing moves. Turn it off again.

## Optional: accessibility (10 min)

28. [ ] Increase contrast and Reduce transparency: nothing disappears.
29. [ ] VoiceOver (⌘F5): tabs, stat cards, rows, evidence buttons and the map are named; the
    source reads as text; outline rows read "key, value"; the diagnostics banner (open
    `Fixtures/edge/malformed.json`) announces its summary.
30. [ ] Keyboard only: open a file, move through the outline, copy a pointer.

## 7. After the first release (5 min, once)

31. [ ] On a Mac (or a new user account) that never had Beautiful BOM: download
    `BeautifulBOM-<version>.dmg` from the GitHub release with Safari, open it, drag the app to
    Applications, start it. **Expect:** one "downloaded from the Internet" question naming rebaze
    GmbH, no "Open Anyway", no warning about an unidentified developer; the welcome window.
32. [ ] About: the version matches the release.

## 8. Comparing two SBOMs (3 min)

33. [ ] Open `Fixtures/tools/partner-portal.maven.cdx.json`, File › Compare With… (⌥⌘K), choose
    `Fixtures/tools/partner-portal.syft.cdx.json`. **Expect:** the Compare tab: "3 packages in
    both. 3 only in cyclonedx-maven-plugin, 2 only in syft."
34. [ ] Click `log4j-api` under "Only in cyclonedx-maven-plugin". **Expect:** its component page;
    Back (⌘[) returns to Compare.
35. [ ] Compare With… a file that is not an SBOM (e.g. `Fixtures/edge/malformed.json`).
    **Expect:** an alert naming the file; the window unchanged.

## 9. The gap list (3 min)

36. [ ] Laravel, Completeness › Export gap list › As PDF handout…, save. **Expect:** a PDF with
    the file name and page numbers on each page; first page: product, SHA-256, the
    presence-and-form sentence, the summary; nothing claims conformity.
37. [ ] File › Export Gap List as CSV…, open it in Numbers and in Excel. **Expect:** one row per
    gap, columns readable, umlauts intact in German (View › Language › Deutsch first).
38. [ ] Open an SPDX file. **Expect:** both menu items unavailable; no export button.

