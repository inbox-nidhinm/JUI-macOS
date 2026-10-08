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

12. **Colour themes** (`Theme.swift`) — six moods: the original cream plus mint,
    sky, coral, lilac and orchid, chosen from a row of dots in a new
    "pick your mood" onboarding step (between name and vault) and from the
    hidden settings page under the dedication. Clicking one applies it
    immediately — no confirm, no relaunch — and it persists in `themeID`.
    The five alternates were derived from the cream palette in Figma rather
    than picked by hand: each holds the original's lightness and saturation
    exactly and rotates every hue into an 11° band anchored on its sticky-note
    colour, so only temperature moves and the value relationships the app
    leans on for hierarchy survive intact. Ink on sheet stays past 4.5:1 in all
    six (cream 6.2, coral 9.0, lilac 11.4). Structurally this turned every
    colour token into a computed read through `Style.theme`, which also
    collapsed the last `Color`/`NSColor` twins into single values. The AppKit
    half — caret, selection, sticky bodies, traffic lights, and the ink baked
    into the text storage — is pushed by `PlainTextView.applyTheme()`, done as
    an attribute-only edit so a mid-sentence theme change keeps the caret,
    scroll position and undo stack. All four bundled sprigs are now
    template-tinted rather than drawn raw, so they follow the theme too.

13. **Audit pass on the rebuild** — the look rebuild left a trail behind it, and
    this is the sweep. Nothing here changes what the app does; several things
    change what it costs.

    *Removed, because nothing drew them any more.* All six root PNGs
    (`Flourish`, `StickyFlower`, `FolderSprig`, `OnboardingLogo`,
    `StickyFlourish`, `FolderFlourish`) — the stop-motion frames replaced every
    static mark, and these were still being copied into every bundle with
    nothing left in the app that read them. With them went the globals that
    loaded them, the per-asset copy loop in `build.sh`, three `Theme` tokens
    whose subjects no longer exist (`divider`, `rule`, `flourishHover` — all
    three became *tones* rather than colours), the `dividerColor` and
    `flourishHoverColor` reads, two unused onboarding design constants, and the
    word count's filter for a box-drawing rule that nothing writes.

    *Memory.* The sticky's tinted flourish frames were cached by theme **and**
    frame, so changing mood added a set of thirty decoded bitmaps rather than
    replacing one — six moods and one animated sticky reached roughly 106MB,
    none of it reachable again. The cache now holds the current theme only.
    ⌘K's full-text cache is dropped a beat after the palette closes instead of
    being held for the life of the process.

    *Speed.* `saveNow` ends in `refreshList`, and saves are debounced on typing
    — so every 300ms pause re-read and re-parsed the RTF of *every note in the
    vault* to re-derive titles. Titles are now cached against the modification
    date they were read at, so a save re-parses the one file it just wrote.

    *Fixed — the selection.* It drew as a band hanging in the air above the
    words, clipping the tops of the letters, but only ever on the last line of a
    note, which made it look intermittent rather than wrong. The fill sized
    itself with `min(fragment.height, lineHeight + padding * 2)` while lifting
    the box by `padding` — a clamp that holds only while the rect is taller than
    the clamp. Measured, the rect AppKit hands over is not one height: 19pt on
    the last line of the document, 48 on a line with another under it, 96 on a
    line that ends a paragraph. On the last line the clamp did nothing and the
    lift remained. Both the selection and `SmoothCaret` — which carried the same
    construct, and changed height by 4pt between lines because of it — now take
    their vertical extent from `Style.inkOffset`/`inkHeight`, the ink box, and
    are one size on every line. The air around the words came down from 8pt to 5,
    which is what the original app's whole-fragment highlight worked out to.

    Fixing that exposed a second one underneath it: AppKit coalesces the
    full-width interior of a multi-line selection into a single tall rect, so
    selecting three lines from the start hands the first two over as *one* rect
    three bands tall. Drawing one fixed-height band per rect highlighted its
    first line and missed the others — the middle line of a three-line selection
    had no highlight at all. The fill now asks the layout manager which line
    fragments each rect covers and draws a band per line, rather than stepping by
    a pitch that does not exist (48 inside a paragraph, 96 at the end of one).

    *Fixed — the band's position.* It is centred between the two rules now
    rather than on the ink, which are not the same place: the ruling centres the
    font's line height, and Courier's 19pt line height carries its 16pt ink box
    2.94 down from the top, so an ink-centred band sat 12.44pt from the rule
    above and 9.56 from the one below. Centring on the computed midpoint was
    still a point out, because `drawRuling` snaps each rule to the pixel grid and
    the snap moves it; both now share `Style.ruleY`. Measured on a render, the
    band centre and the rule midpoint agree to 0.00pt.

    *Fixed.* A folder could not be recapitalised: the vault is
    case-insensitive, so renaming "notes" to "Notes" found "Notes" already
    present — itself — and settled on "Notes 2". `Style.applyFont` wrote
    attributes from inside its own `enumerateAttribute` walk, which can merge
    the runs being enumerated. And `applyTheme` ran `didChangeText` straight
    through to a `@Published` write while inside a SwiftUI update pass.

    *Changed on purpose.* Deleting a folder now deletes the notes in it, rather
    than sliding them back to unfiled — the same deal `delete(_:)` already
    offers for one note, with no trash and no undo. Folder names are shown as
    typed instead of forced to uppercase, which is what made recapitalising
    them worth fixing.

    *Consistency.* `houseFont` replaced `.font(.custom("Courier", size:))` at
    every call site, so the family chosen in settings reaches the chrome and
    the stickies and not only the page — it used to restyle the note and leave
    the panel, the palette, the folder names and onboarding in Courier. The
    three settings cards take the notes panel's paper; they were the last flat
    raised surfaces in the app. Three hand-drawn placeholder texts became
    `HouseField`'s own. Four copies of the load-a-document sequence became one,
    the vault picker exists once instead of twice, and the settings rows are one
    builder instead of three near-identical blocks.

14. **Stickies from the phone** — the iPhone port reworked the sticky over an
    evening of use, and this brings every part of it that means anything on a
    Mac back to the Mac, so a sticky looks and behaves the same in both places
    (they share one vault now, in iCloud Drive).

    *Put away, a sticky is a crumpled ball* in its margin, beside the line it
    is about — the margin used to hold the whole card, open, all the time.
    Clicked, the ball lifts and opens out flat into the card, in the margin
    where it sat; clicked away from, or done, it crushes back. Deleted or never
    written in, it crumples to nothing. The fold is the phone's
    (`Crumple.swift`), taken across nearly line for line: a SceneKit sheet
    printed with a picture of the card, crease depth 0.8, 1.15s out and 0.95s
    back. The real card is shown only once the sheet lies flat, which is also
    why its flourish now draws itself on *every* time it is opened, after the
    unfold and never during it. Reduce Motion skips the fold.

    *The words a sticky is about carry a wash* of its colour — a highlighter
    run over them — so the ball says that there is a note and the wash says
    which words. Painted with the page under the text, the size and shape of a
    selection, never stored in the RTF.

    *The card reads more easily.* 14pt at 140% leading, up from 13 on the
    system's default, and a smaller flourish (0.30 of the stamp, from 0.40)
    with clearer air above it; at the old size its blooms reached into the
    last lines.

    *Delete and done are marks under the card* while it is being written in —
    the Figma system's hand-drawn bin and tick (node 330:433), in the ink's
    muted step on a faint tile — rather than only living in the right-click
    menu. The vectors are scatter-brush strokes, so they are rasterised through
    WebKit at build time like the flourish frames (`Art/render-marks.swift`).

    *Gone.* Dragging a sticky out to pin it on the page — a ball has no line to
    go back to from there; old pin positions stay in the file, unread. And the
    "hide sticky notes" command in ⌘K, which a page of small balls has no need
    for.

    *The floor moves from macOS 13 to 26*, still universal. Nothing needed the
    old systems any more; the one availability gate went, and every
    `onChange` takes the current two-parameter form.

## Minor updates & polish

- **New folder without the context menu**: the folder grid ends with a `+`
  tile — same card as a folder, plus glyph at the size the new-note button
  uses — so folders are made the same way notes are. It flows with the grid
  rather than taking a row of its own, and takes the panel's single
  highlight on hover like any other tile.
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
