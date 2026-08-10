# JUI — Changelog

A plain writing pad for Juilee. Built July 16–17, 2026.

## Major builds

1. **The editor itself** — native macOS app (Swift, single `main.swift`): a plain
   `#FDF0D9` sheet, Courier-only, hidden title bar, 200pt side margins, justified
   paragraphs, brown `#71390D` ink, silent auto-save on every keystroke.
2. **Notes & history** — notes stored as portable RTF files in a vault folder;
   history popover (bottom-right) with titles, hover-following `#FDF0D9`
   highlight, 6px `#A88D34` dot marking the open note, right-click delete.
3. **Rich text engine** — migrated from plain text to a rich NSTextView:
   ⌘I italics (Courier-Oblique), `#ECDBBE` selection, paste always stripped to
   plain text, foreign fonts/styles normalized away.
4. **Writing conveniences** — Return = paragraph with 24pt gap, Shift+Return =
   line break; markdown-style `- ` bullets (hanging indent, auto-continue,
   double-Return exit); `---` + Return full-width rule in `#AD9E84` that
   re-fits on window resize.
5. **⌘K search** — centered palette, full-text across all notes, snippets,
   arrow/Enter navigation, opens the note and flashes the match; scrim
   (background color at 80%) plus 3pt blur behind it.
6. **The secret flourish page** — clicking the corner flower fades to
   "Juilee's personal writing pad <3", read-only and centered, toggling back to
   the exact writing spot. Later grew into the settings room: vault relocation
   (folder picker, notes migrate along) and a font-family selector, both
   persisted.
7. **Sticky notes** — selection-triggered icon → margin annotations anchored to
   character ranges (remapped through every edit, orphans survive), persisted
   in sidecar JSON per note, drag-to-pin anywhere with a one-time ±2° tilt,
   Return-to-Margin, postage-stamp perforated styling with a flower motif,
   left *and* right margins chosen by selection position, and a contextual
   hide/show row in ⌘K.
8. **Identity & distribution** — named JUI, custom SVG app icon (system
   squircle), Apple Silicon build, AirDrop-ready `JUI.zip`, notes vault outside
   the app. Requires macOS 14+.

9. **Folders** — flat, one level, managed entirely inside the history popover.
   Folders are real vault subdirectories (Finder mirrors the app); each note
   lives in one folder or unfiled, its sticky sidecar traveling with it.
   Drill-in navigation (`poems ›` rows, `‹ poems` back row), panel opens at
   the open note's location, dot propagates to the folder row at root.
   Right-click: New Folder (panel), Rename / Delete Folder (folder rows,
   deletion unfiles the notes), Move to (note rows) — plus drag a note onto a
   folder row to file it, onto the back row to unfile. ⌘N lands in the folder
   you're standing in. ⌘K stays global with a muted `folder/` prefix on filed
   results. Vault relocation moves the whole tree.

10. **Folder grid & unified panel highlight** — folders sit two-per-row at the
    top of the panel, separated from the notes list by a hairline divider, so
    the two regions read as distinct. The panel now has exactly one highlight
    at any moment (`PanelHighlight`): hovering a folder takes the selection
    outright instead of letting it snap back to the open note, and the single
    box glides between folders, notes, and the back row. At rest it sits on
    the open note — or, at root when that note is filed, on the folder
    holding it. Folder boxes then grew to twice a note row (68pt), each
    carrying a 32pt botanical sprig up top with the name along the bottom
    (space-between), chevron dropped and names set in uppercase — including
    the `‹ FOLDER` back row. Folder cards carry their own `#F3E4CA` tint that
    lightens to `#FDF0D9` when hovered or open; they cross-fade instead of
    sharing the notes' sliding highlight, since morphing a shared box between
    tall half-width cards and short full-width rows produced an arcing,
    resizing animation.

11. **First-run onboarding** (`Onboarding.swift`) — shown once, gated on an
    `onboardingCompleted` flag in `UserDefaults` alongside the existing
    vault/font settings. Rebuilt from the Figma frames (node 243:120, Screens
    One–Four) as **an envelope**: a letter sits tucked inside with the title
    showing through the flap's V, then after a beat the letter is drawn up out
    of the envelope (ease-in-out, 750ms) to reveal the controls, and the
    remaining steps swap the letter's contents — name, then vault. The
    envelope drifts down as the letter rises so the composition stays centred,
    exactly as the frames do. Geometry is transcribed in the design's own
    pixel units and multiplied by a single scale factor, so the drawn aspect
    ratio survives at any window size; the flap is a computed `Shape` (rect
    minus a triangular notch) rather than an exported asset. Colours defer to
    existing tokens wherever the design was within a shade — only the envelope
    (`#EBCEA3`) and letter (`#FFFAF3`) are new. Sits on the ⌘K palette's dim +
    3pt blur backdrop; the vault pill opens the native `NSOpenPanel` and
    writes the same `vaultPath` the app reads at startup. Enter advances when
    valid, Escape can't dismiss, back works from the name step onward, and the
    whole sequence collapses to a straight cut when
    `accessibilityDisplayShouldReduceMotion` is set. The scene arrives from
    below at half size and grows into place, and leaves the same way in
    reverse — letter back into the envelope, then the envelope sinks, shrinks
    and fades. Type is held at the app's own scale (16 title / 13 controls /
    12 back, 30pt pills) rather than the mock's 34/24, which had been drawn
    for a 1600px canvas and shouted next to the editor.
    The name is a new shared setting: onboarding writes it, a new Settings
    card edits it, and the hidden page reads it (falling back to the original
    dedication when empty).

## Minor updates & polish

- **Chrome**: cream traffic lights (true-size circles, hover reveals real
  colors); bottom-right icons with hover boxes and persistent active state;
  arrow cursor over all controls; click-anywhere panel dismissal; fade-only
  panel transition; word counter (10px, number only); corner flourish at 80%
  of half size in `#F2E3C9` with `#F2DEBA` hover.
- **Caret**: MS Word 2013-style smooth glide (100ms ease-out), solid while
  typing, blinking when idle.
- **Search palette styling**: `#71390D` titles, 60% snippets and "search"
  placeholder, divider, toggle-row alignment and padding.
- **Settings styling**: card layout matching the popovers, values in light
  pills, clickable vault path.
- **Sticky fine-tuning**: 13pt text, square-by-default size, 6pt perforation
  corner gap, 20pt flower with reserved bottom band, window-wall clamping for
  pinned notes, tilt applied mid-drag and rolled only once, icon border
  (2pt `#FDF0D9`), empty stickies self-delete on click-away.

## Distribution

- Universal again (Apple Silicon + Intel) with a macOS 13 floor: the two
  macOS 14-only APIs in use are now version-gated (`onKeyPress` degrades to
  Enter/mouse on 13) and the five `onChange` calls use the form available on
  both. Widest compatibility for a hand-shared app.
- `build.sh` cleans the bundle before building, strips extended attributes
  (they make `codesign` fail), and no longer swallows signing errors — it
  verifies the signature and stops the build if anything is wrong, rather than
  shipping a bundle that looks fine locally and refuses to launch elsewhere.
- The app is only **ad-hoc signed** (notarization needs a paid Apple Developer
  account). Every rebuild therefore gets a fresh signature, so a Mac that
  previously approved JUI treats each new build as a stranger: after
  unzipping, clear quarantine with `xattr -cr JUI.app` before first launch.

## Notable fixes along the way

- Smart-dash substitution silently breaking `---` rules → typewriter input
  mode (no smart dashes/quotes/replacement).
- A paste regression (nothing pasted) → robust plain-text paste with
  rich-clipboard fallback.
- Inactive selection turning system gray → custom layout manager owns all
  selection drawing.
- Margin clicks yanking the caret → margins are caret-dead space that only
  end sticky editing.
- The pointer stayed an I-beam over the margins even though they're dead space
  for the caret. Earlier attempts only forced the arrow over registered
  controls (`ArrowZones`); NSTextView still claimed its whole bounds for the
  I-beam. Fixed at the mechanism AppKit actually honours — an explicit
  `resetCursorRects` that hands the margins to `.arrow` and only the text
  column to `.iBeam`, re-registered whenever the view resizes.
- Old-name migration (PlainEditor → JUI) for the app support folder and note
  formats (.txt → .rtf).
- Stickies with long content rendered at default size (text overflowing) when
  opening a past note → inner text view is now sized synchronously before its
  height is measured, so notes load at their true size.
- The smooth caret glide had only ever been wired into the main note editor;
  sticky notes silently used the plain default caret. Extracted the glide
  logic into a shared `SmoothCaret` helper (verified by sampling the
  CALayer's live presentation-layer position, not just screenshots) and
  wired it into sticky editors too, so every text field in the app now
  glides the same way.
