# Branding and first impression (2026-11-16)

Approved by Toni on 2026-11-16 ("A, go ahead and build all four parts").

## Intent

Toni shows the app in small workshops on his own Mac. It should look finished and say what it is
from the first screen, with minimal rebaze branding, following Apple's Human Interface Guidelines.
Persona: a workshop participant who sees the app for the first time. First result: they see the
app's name and what it reads before any file is open, then the client's product as the headline.

## Parts

1. **App icon:** the rebaze mark (from the website logo) in `#202020` on a pale squircle in the
   „Blassgrün“ palette (white to `#E3EAE5`). No text in the icon (HIG). Source:
   `scripts/icon/icon.svg`; `scripts/icon/make-icon.sh` renders the asset catalog sizes.
2. **Top bar:** the tabs on the left; on the right a quiet wordmark, the rebaze mark and
   „Beautiful BOM“, in the secondary label colour. Clicking it opens About. The product name stays
   the headline of the Overview.
3. **Welcome window:** shown at launch when no file is opened, and when the Dock icon is clicked
   with no window open; also Window › Welcome to Beautiful BOM (⇧⌘1). Icon, name, one line on what
   the app does, „Open an SBOM…“, a drop area, recent files and three bundled samples. Replaces the
   bare Open panel.
4. **About window:** the standard About panel with the icon, version, „by rebaze“ and the licences
   of the bundled samples.

## Approaches (icon)

| Option | Trade-off | Verdict |
|---|---|---|
| A · the rebaze mark alone | Clear down to 16 px; says „rebaze“, the name says „BOM reader“ | Chosen by Toni |
| B · the mark on a document page | Reads as „a file, read by rebaze“ when large; generic document icon below 32 px | Rejected |
| C · three layers of parts, a line, the green dot | Most „bill of materials“; a grid when small, and borrows the Supply Chain Stack symbol | Rejected |

Renders of all three: `build/screenshots/icons/icon-options.png` (not committed).

## Constraints

- App UI keeps system colours, fonts and controls; brand appears only in the icon, the wordmark,
  the welcome window and About. Electric green `#88EEAD` is not used in the app UI.
- Self-contained: the mark's paths are copied into this folder.
- Bundled samples are the public fixtures already in the repository (CC0, Apache-2.0); never
  customer data. Their licences stand in About.
- Every new string in English and German (`make strings-check`).

## Left to the builder

Layout details of the welcome window, the wordmark's size, and the sample titles.
