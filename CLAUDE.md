# JUI

A single-window macOS writing pad — a cream sheet, Courier, no chrome. Built as a
gift for Juilee. Design-led: how it *feels* matters more than feature count, and
almost every oddity in the code is a deliberate fix for something that felt wrong.

**Read `CHANGELOG.md` for *what* was built and why, in order.** This file is the
map of *where things are* and *what will break if you touch them*.

## Shape of the project

No Xcode project. Five Swift files compiled directly by `swiftc`:

| File | Lines | Contents |
|---|---|---|
| `main.swift` | ~4200 | Everything: tokens, store, text engine, stickies, panel, search, settings |
| `Crumple.swift` | ~560 | The crumpled-ball sticky: the SceneKit sheet, its creases, `CrumpleDirector` |
| `Theme.swift` | ~290 | The six palettes, the `AppIcon` recolour, the mood-dot `ThemePicker` |
| `Texture.swift` | ~240 | The paper: which stock each surface takes, at what grain and strength |
| `Onboarding.swift` | ~510 | First-run envelope flow only |
| `build.sh` | | Universal build + ad-hoc sign + verify |
| `Info.plist` | | `com.nidhin.jui`, `LSMinimumSystemVersion 26.0` |

**Adding a `.swift` file means adding it to the `swiftc` line in `build.sh`** —
grep for `for arch in`.

**Art ships as directories, not as a list of filenames.** `Contents/Resources`
gets `AppIcon.icns`, `Textures/` (three greyscale JPEGs, derived from
`Art/Textures`) and `FlourishFrames/{corner,folder,sticky}/` (the stop-motion
frames, derived from `Art/Vectors`). Both are copied wholesale, which is
deliberate: the per-asset loop that used to sit here did nothing when someone
added a file and forgot to name it, and on this branch drawing nothing and
drawing a very subtle grain look identical. There are no loose PNGs at the repo
root any more — the six that were there outlived what drew them and were still
shipping in every bundle.

### Landmarks in `main.swift`

Keyed on what to grep for rather than on a line number. Every number in the
table this replaced had drifted by 250–800 lines, which made the whole thing
worse than nothing: wrong enough to send you to the wrong place, confident
enough to be believed.

| Region | Grep for | What |
|---|---|---|
| Colour tokens | `var sheetColor` | Computed vars reading `Style.theme` — never literals |
| Type token | `func houseFont` | The one font every SwiftUI call site goes through |
| `Style` | `enum Style` | Theme global, fonts, margins, paragraph styles, the ruled grid |
| Models | `struct NoteMeta` | `NoteMeta` / `SearchHit` / `Sticky` |
| `NotesStore` | `final class NotesStore` | The single source of truth for everything |
| Document loading | `MARK: Getting a document` | `load` / `loadBlank` — every route into the editor |
| `SmoothCaret` | `final class SmoothCaret` | Shared caret glide (note editor *and* stickies) |
| `StickyView` | `final class StickyView` | The open sticky's card: postage stamp, drawn by hand |
| `StickyBallView` | `final class StickyBallView` | A sticky put away: the crumpled ball after its words |
| `StickyCloseDot` | `final class StickyCloseDot` | The ring in the card's top-right corner that puts it away |
| Ball's room in the line | `func applyStickySlots` | The editor-only spacing a ball sits in |
| Sticky out/away | `func openSticky` | `openSticky` / `putAwaySticky` / `syncStickies` on `PlainTextView` |
| `PlainTextView` | `final class PlainTextView` | The `NSTextView` subclass — bullets, ruling, cursors, paste, `applyTheme` |
| `HouseField` | `struct HouseField` | The app's only text field |
| `RichTextEditor` | `struct RichTextEditor` | `NSViewRepresentable` bridge + `Coordinator` |
| Traffic lights | `final class TrafficDotsOverlay` | The flat dots over the real buttons |
| `SearchPalette` | `struct SearchPalette` | ⌘K — results *and* commands |
| `ContentView` | `struct ContentView` | Layout, notes/folders panel, settings block |
| `@main` | `struct PlainEditorApp` | Name is legacy — the app was renamed, the type wasn't |

### ⌘K holds commands as well as matches

Below the results the palette can show **command rows**, and results plus commands
share **one selection space** (`selected` indexes across both), so the arrows walk
the whole list and Return fires whatever is highlighted. A command row carries the
same highlight box as a result so it reads as selectable.

- **`onboard again`** — properly hidden: needs three characters and a real prefix
  of "onboard", so it can't surface while searching notes. Calls
  `NotesStore.replayOnboarding()`, which deliberately leaves `onboardingCompleted`
  alone — the only way out of onboarding is to finish it (Escape is dead by
  design), so abandoning a replay by quitting must not re-trigger it on next
  launch.

Onboarding seeds the name and vault from the store on appear, so replaying it and
clicking straight through changes nothing. Before that, a replay blanked the name
and offered to move the vault back to its default.

## Architecture

`NotesStore: ObservableObject` owns all state. There is no other model layer, no
view models, no dependency injection — every view takes `store` directly.

**Persistence is plain files in a user-chosen vault folder**, deliberately
readable in Finder:

```
<vault>/
  <uuid>.rtf                 a note (RTF so italics survive)
  <uuid>.stickies.json       its sticky annotations, if any
  <folder name>/             a real subdirectory — one level only, never nested
    <uuid>.rtf
```

- Note **title** is derived, never stored: first non-empty line, 42 chars (`NotesStore.title`).
- Note **order** is `contentModificationDate` descending.
- `refreshList()` rescans the vault from disk; it is the only thing that
  populates `notes`/`folders`. Call it after any file operation.
- Saves are debounced 300ms (`scheduleSave`) and also fire on
  `willTerminate` and before any note switch. An empty never-typed note is
  never written to disk.

`UserDefaults` keys — the complete set: `vaultPath`, `fontFamily`, `themeID`,
`displayName`, `onboardingCompleted`.

**Titles are cached against modification date** (`titleCache`). Deriving one
means opening the file and parsing the RTF, and `saveNow` ends in
`refreshList` — so without the cache every 300ms pause in typing re-parsed
every note in the vault. If you add a way for a note's first line to change
without its file being rewritten, that cache is what will show it stale.

**Deleting a folder deletes the notes in it.** It used to slide them back to
unfiled. There is no trash and no undo, which is the same deal `delete(_:)`
offers for a single note. The whole directory goes rather than a filtered sweep
of it: a leftover file of some other kind would make `removeItem` fail and leave
a folder in the panel that nothing could get rid of. If the open note is one of
the casualties, its pending save is cancelled first — a debounce firing
afterwards writes the file straight back into a directory that no longer exists.

**Folder names are shown as typed**, not uppercased, and a rename that only
changes case has to skip the uniquing loop: the vault is case-insensitive, so
`fileExists` for "Notes" is true while the folder is still called "notes" — the
folder answers for the name it is being renamed *to*, the loop reads that as a
collision, and recapitalising a folder produced "Notes 2".

### `docVersion` is the load signal

`store.docVersion` increments **only when a different document is loaded into the
editor — never on typing**. `RichTextEditor.Coordinator.loadedVersion` compares
against it to decide whether to blow away the text view's contents.

If you add a path that changes `attr` wholesale, bump `docVersion`. If you bump
it on keystrokes, you'll wipe the undo stack and fight the caret on every letter.

### Overlay states

Three mutually-aware overlays, all flags on the store:

- `hiddenShown` — the flourish page: dedication + settings (name, vault, font)
- `searchShown` — ⌘K palette
- `onboardingShown` — first run; **cannot be escaped** (`onExitCommand {}`)

`editorBlocked` (`hiddenShown || onboardingShown`) freezes the text view.
`RichTextEditor.updateNSView` is what actually flips
`isEditable`/`isSelectable` and moves first responder.

## Invariants — break these and something visibly regresses

**TextKit 1, assembled by hand.** `makeNSView` builds
`NSTextStorage` → `SelectionColorLayoutManager` → `NSTextContainer` explicitly,
and `tv.retainedStorage` keeps the storage alive. This is *not* legacy drift —
`SelectionColorLayoutManager` is the only reliable way to stop selections
turning system-gray when focus moves into a sticky. Do not migrate to TextKit 2.

**Cursor handling lives in exactly two places.** `resetCursorRects` is the
mechanism AppKit actually honours for the dead margins; `ArrowZones.hoverCount`
 lets SwiftUI controls drawn *on top of* the text view claim the arrow via
`.arrowCursorZone()`. Earlier attempts elsewhere (`mouseMoved`, `cursorUpdate`)
are kept as belt-and-braces but are not sufficient alone. Don't add a third way.

**The native caret is fully suppressed, three ways at once** — `insertionPointColor
= .clear`, an empty `drawInsertionPoint` override, and hiding
`NSTextInsertionIndicator` on macOS 14+. All three are needed. `SmoothCaret`
draws it as a `CALayer`. Any new text field in the app should use it too.

**Horizontal rules are gone** on this branch. `---` + Return no longer becomes
one, and none is drawn. A page that is already ruled cannot use one more line to
mean "a break" — the two read as the same mark. `Style.hrMarker` survives, and
so does the `loadAttr` migration from old `"───…"` runs, only so that a note
which already contains a rule opens as a blank line instead of a stray
box-drawing run. Nothing creates a new one.

**Paragraph styles are rebuilt on load, never trusted from the file**
(`loadAttr`). On a ruled page a stale `paragraphSpacing` doesn't merely look
different — any gap that isn't a whole number of pitches walks the type off the
ruling, a little further with every paragraph, and every note written before the
grid existed carries the old value. Classification is by the line's own text
(does it start with `Style.bulletPrefix`), not by `headIndent`, which is the
attribute being rebuilt. `normalizeFonts` still reads `headIndent` at runtime,
where the attribute is trustworthy.

**Bullets are literal `"• "` text** plus `Style.bulletParagraph` (hanging indent).
`normalizeFonts` identifies them by `headIndent > 0` — if you change how
bullets indent, update that check or bullet paragraphs get restyled as prose.

**Typewriter input.** Smart dashes, quotes, and text replacement are off
everywhere. Smart dashes silently broke `---` rules once already.

**Sticky anchors are character ranges, remapped on every edit** via
`textView(_:shouldChangeTextIn:)` → `store.remapStickies`. Anchors inside a
deleted range collapse to the edit point rather than dying. `syncStickies`
rebuilds positions on every layout pass. A card measures its own height, and
must be width-set *before* measuring or long notes load at default size.

**A sticky is a crumpled ball until it is opened** — the fold is the iPhone
port's (`~/Documents/Claude Code/JUI-iOS`), from the same code. The ball has a
place of its own *in the line*, right after the sticky's words, and the
sentence carries on after it — 24pt, centred on the line like the words, as in
the prototype the design came from (`JUI-iOS/prototypes/crumpled-sticky`). Two
on the same words sit side by side. (The phone keeps its ball in the margin.)
Clicking the ball runs the fold in `Crumple.swift`: a SceneKit sheet printed
with a picture of the card (`StickyView.picture()`), lifting out of the ball
and opening flat right there, over the page — or wherever the card was last
dragged to. **The real card is hidden until that sheet lies flat**, then shown, given the
caret, and its flourish draws itself on — every opening, not only the first.
Losing focus (a click anywhere else, or the dot in the card's top-right corner)
puts it away the same way round. The card's words wrap around the dot — an
exclusion path on its text container — so nothing runs under it. There are no
delete or done buttons: delete is on the right-click menu of the card and of
the ball. A sticky that is deleted or was never written in crumples to nothing
and is removed. One is out at a time — taking out another puts the first
straight back without a fold.
Reduce Motion skips the fold. The card is made fresh per opening and the page
holds only that one; everything else on the page is a ball.

Rules that keep it working:
- **`openID` is the sticky that is out; `card` may outlive it** while its sheet
  is on the way back, and is dropped once the sheet takes over (`cardLeft`).
- **The stage is drawn above everything** — cards and balls are added *below*
  `crumple.view`, never with a bare `addSubview`.
- **The fold's coordinates are the page's**, y down: the director takes the
  card's frame, the ball's centre and a stage rect around both, all in page
  points, and converts.
- **The ball's room in the line is spacing, laid on in the editor only.**
  `applyStickySlots` puts `.kern` (marked `.stickySlot`) on the last inked
  letter of each sticky's words — enough for the ball and its air — and takes
  it off wherever it no longer belongs. `NotesStore.textChanged` strips both
  on the way back from the editor, which is the only way text reaches the
  store, so the spacing never reaches the RTF or the phone. It is applied a
  turn of the loop after `syncStickies` (which runs from layout, where the
  storage can't be edited) and only when it differs from what is there, so it
  can't loop. `typingAttributes` drops it, or typing after a sticky's words
  would carry the gap along. The wash ends at the letter, not the gap.
- **A card can be dragged anywhere on the page** — by its paper (the
  perforated edge and the flourish band, open-hand cursor), never its words,
  which take clicks as words. It then opens there from now on: `pinX`/`pinY`,
  in document points. "Return to Its Words" on its menu forgets the spot.
  `syncStickies` leaves a card alone while `isDragging`.

**The words a sticky is about carry a wash** of the sticky colour at 26%,
painted in `drawBackground` after the ruling — so beneath the text — sized and
placed as the selection's bands are. Never a storage attribute: it would be
written into the RTF. `syncStickies` asks for a redraw when any anchor range
changes.

**`normalizeFonts` is a safety net, not the styling path.** It forces family/size,
paragraph style, and ink color, and strips underline/strike/link/shadow/etc. from
anything that arrives styled (drops, services). Paste is already handled
separately and always plain.

**A selection or a caret is sized off the ink box, never off the rect AppKit
hands it.** `Style.inkOffset` and `Style.inkHeight` are that box: the baseline
sits `defaultBaselineOffset` down from a line fragment's top, and the ink runs
from there up by the ascender and down by the descender. Everything else in the
fragment is leading, which on a 48pt band is most of it.

The rect's *origin* is dependable — it is the fragment's top. Its *height* is
not, and this is the trap: for the same 16pt type it arrives **19pt** on the last
line of the document, **48** on a line with another line under it (the line plus
`lineSpacing`), and **96** on a line that ends a paragraph (plus
`paragraphSpacing`). Measured, all three.

`fillBackgroundRectArray` used to read `min(fragment.height, lineHeight + padding
* 2)` while still lifting the box by `padding` — a clamp that only holds while
the rect is taller than the clamp. On the last line it isn't, so the clamp did
nothing, the lift stayed, and the highlight drew 19pt starting 8pt *above* the
words: a band hanging in the air over the line, clipping the tops of the letters.
Only ever the last line, which is what made it look intermittent rather than
wrong. `SmoothCaret` carried the same construct and changed height by 4pt between
lines because of it. Both now compute `inkOffset`/`inkHeight` and are one size
everywhere.

**And one rect is not one line.** AppKit coalesces the full-width interior of a
multi-line selection into a single tall block — select three lines from the very
start and the first two arrive as *one* rect three bands tall. A fixed-height
band drawn per rect therefore highlighted the block's first line and silently
missed the rest, which is a separate bug from the one above and was hidden by it.

**And it is centred in the ruled band, not on the ink.** The two are not the
same place: the ruling centres the font's *line height* in the pitch, and a line
height is not symmetric around the ink it carries — Courier 16 is 19pt around a
16pt ink box and puts 2.94 of the difference above the glyphs, 0.06 below. A band
centred on the ink therefore sat 12.44pt from the rule above and 9.56 from the
one below, which reads as the selection crowding the line beneath it.

Measure against the rules **as drawn**, not as computed. `drawRuling` snaps each
one with `.rounded() + 0.5` so a hairline doesn't smear across two device pixels,
and that snap moves it — a full point, when the computed y lands on a half, which
is exactly what Courier's 29pt `lineSpacing` produces. Centring on the computed
midpoint left the band 1pt high, visible at 2x. Both the ruling and the selection
now go through `Style.ruleY` / `Style.ruledCentre`, so they cannot disagree.
Verified on a render: rule centres at 197.0 and 293.0 device px, band centre
245.0, midpoint 245.0.

So `fillBackgroundRectArray` asks the layout manager which line fragments each
rect covers (`enumerateLineFragments` over the selection's glyph range, offset by
`textContainerOrigin`) and draws one band per line. It does **not** step down the
rect by a fixed pitch: there is no single pitch to step by, since a line inside a
paragraph is 48 from the next and a line that ends one is 96. Horizontal extent
still comes from the rect, so AppKit keeps deciding how far a continuing
selection runs past the last word on a line.

**Never write attributes from inside `enumerateAttribute`.** Adding an attribute
can merge a run with its neighbour, which reshapes the ranges being walked.
`normalizeFonts` collects closures and applies them after; `Style.applyFont`
collects `(font, range)` pairs and applies them inside `beginEditing`/
`endEditing`; `toggleItalics` brackets its whole walk the same way. There is no
fourth pattern, and the one that used to write in place was the odd one out.

**`applyTheme` defers `didChangeText` by one hop.** It is called from
`updateNSView` — so from inside a SwiftUI update pass — and `didChangeText` runs
the delegate straight through to `store.textChanged` → `updateWordCount`, which
writes a `@Published`. Publishing from inside an update pass is not allowed. The
`DispatchQueue.main.async` around it is what moves that write after the pass;
don't unwrap it because it looks redundant.

## macOS 26 floor

The app launches on macOS 26 and later, universal (arm64 + x86_64). It was 13
until the sticky rework (October 2026), when the floor was raised on purpose:
nothing needs to run on older systems, and it removed the gates rather than
adding more. `onChange(of:)` takes the two-parameter closure everywhere now,
`SmoothCaret` hides `NSTextInsertionIndicator` without an `#available`, and the
fold is driven by `NSView.displayLink`.

Keep the build universal: 26 is the last macOS on Intel, and an arm64-only
build fails there with a bare *"The application can't be opened"*, which reads
like a signing problem and isn't.

### Text fields are `HouseField`, not SwiftUI's `TextField`

SwiftUI gives no way to set a text field's selection colour — selections follow
the view's `tint`, and the app tints to house ink for the caret, which painted
selections in near-black and made selected text unreadable. Configuring the
window's shared field editor doesn't hold either: AppKit re-runs
`setUpFieldEditorAttributes` whenever a field takes focus and overwrites it
(measured). That method *is* the hook it honours, so `HouseField` wraps an
`NSTextField` whose cell overrides it.

All five fields go through it — onboarding name, settings name, ⌘K query, folder
rename, new folder. It also carries submit / cancel / arrow callbacks, the
placeholder, and the ink-ladder step for the text.

**Use its `placeholder`, not a `Text` behind it.** Three of the five drew their
own prompt in a `ZStack` under a comment about macOS ignoring `prompt` styling —
true of SwiftUI's `TextField`, and irrelevant here, because
`placeholderAttributedString` takes whatever attributes it is given. The
hand-drawn ones also went on using Courier after the field itself started
following the font picker, so ⌘K showed two families on one line.
`placeholderAlpha` exists because ⌘K's prompt is `inkMuted` where the others are
`inkFaint`; it defaults to faint.

**`HouseField.Bed` is the non-obvious part.** The selection has to be one step
away from whatever the field is sitting on. The editor selects panel-on-sheet,
but the ⌘K palette's own background *is* the panel colour, so reusing that made
the selection invisible — same colour on same colour. A field declared
`bed: .panel` selects in sheet instead, which is also what the palette's result
rows already highlight with. Get this wrong and the selection silently vanishes
rather than looking wrong.

## The `re-JUI` branch — a parallel app, not just a branch

`re-JUI` is a ground-up rework of the app's *look*. It is built to install and
run **beside** the shipping JUI, so the two can be compared side by side and a
half-finished redesign never costs anyone their notes.

Three values at the top of `build.sh` are the entire divergence:

| | main | re-JUI |
|---|---|---|
| `NAME` (app, executable, zip) | `JUI` | `re-JUI` |
| `BUNDLE_ID` | `com.nidhin.jui` | `com.nidhin.jui.re` |
| `COUNTER` | `build-number` | `build-number-re` |
| `ICON` | `AppIcon.icns` | `AppIconRe.icns` |

They are stamped into the bundle at build time with `PlistBuddy`, alongside the
`CFBundleVersion` stamp that was already there. **The source `Info.plist` is
left describing the real app** — so merging this branch back is a matter of
restoring those three lines, and nothing else.

What each one buys:

- **A separate bundle id is a separate `UserDefaults` domain.** Theme, name,
  font, vault path and `onboardingCompleted` are all independent, which is why a
  fresh `re-JUI` build opens on onboarding in cream while the real app stays on
  whatever it was set to.
- **A separate `CFBundleName` is a separate vault.** `NotesStore.appFolderName`
  reads it and the vault becomes `~/Library/Application Support/<name>/Notes`,
  so this build writes to `re-JUI/Notes`. That replaced a hardcoded `"JUI/Notes"`
  in two places; on main it resolves to exactly what it always did. The fallback
  is `"JUI"`, for the case where there is no bundle to read.
- **A separate counter** keeps the two branches from conflicting on a one-line
  file every time either of them builds.

`.gitignore` matches build products as `*.app/` and `*.zip` rather than by name,
so neither branch's bundle can be committed by the other's build.

### The flourish animation, and two traps in rasterising it

The corner flourish draws itself once at launch, from frames split out of one
animated SVG by `Art/split-frames.py` and rasterised by `Art/render-frames.swift`,
both run from `build.sh`. Currently 30 of them, and **nothing in the app says
30**: `AnimatedFlourish.frames` counts what shipped by enumerating the bundle
directory, and the aspect ratio, the sequence's duration and the onboarding beat
that waits for it are all derived from that array. The loader used to hardcode
`1...30`, which made those derivations a fiction — a re-export of a different
length would have been rasterised and shipped in full, then played thirty frames
of and stopped. Frames are sorted by the number in the name rather than by the
string, so a hundred-frame export doesn't order 100 before 11.

**Render through WebKit, never AppKit.** `NSImage` loads SVG and silently drops
`<mask>`. The later frames of this animation are drawn by masking a full-bleed
rect — the mask *is* the shape — so an AppKit render loses every masked element
and returns a sparse sprig with its blooms missing. Nothing errors, which is the
trap: it looks like an animation that ends early rather than a renderer that
failed, and it was diagnosed as exactly that at first.

**Write premultiplied alpha.** `NSBitmapImageRep` stores premultiplied by
default, so a white silhouette at partial coverage is `(a, a, a, a)` and not
`(255, 255, 255, a)`. Writing the latter is not valid premultiplied data and
reads back fully opaque — every frame came out a solid rectangle.

Frames are cropped to the **last** frame's bounds, not their own, or the drawing
re-centres on every tick and the flourish swims while drawing itself. They ship
as white silhouettes and are tinted at draw time, so one sequence serves all six
themes. Playback is a repeating timer stepping an index, not an animation:
stop-motion is discrete, and interpolating between frames would remove the point
of it.

**The sticky's tinted copies are cached for the current theme only.** SwiftUI
tints with `.renderingMode(.template)`, but `StickyView` draws by hand, so each
frame needs a tinted copy built through `lockFocus` — a whole decoded bitmap, not
a reference to the source. Thirty frames of a ~366×405 stamp is about 18MB. The
cache used to be keyed by theme **and** frame, so changing mood added a set
rather than replacing one, and six moods with one animated sticky reached roughly
106MB that nothing could ever ask for again. `flowerCacheTheme` now wipes the lot
on a change. Nothing visible moves: the same image is rebuilt the same way from
the same frame, and the only tint ever requested is the one in force.

### The ruled grid, and the Figma system it comes from

The source of truth is the **Design System** page of the JUI — Colour Palette
file (`2XErpBfGuIGNU0DkL58Ute`, node `31:3555`). Read it with the Figma MCP
rather than measuring exports: a 1px rule at 2× exports antialiased across two
device pixels, which made the ruling look like 4.7% black when the system says
10%, and that wrong number shipped once already.

**The whole system scales by 16/22.** Its type is Courier Prime 22 on a 66pt
line; the app's is 16. Everything else follows and cross-checks:

| | Figma | × 16/22 | app |
|---|---|---|---|
| type | 22 | 16 | `Style.baseFont` |
| line / ruling pitch | 66 (= 3 × type) | 48 | `Style.linePitch` |
| side margin | 279 | 203 | `sideMargin` 200 — already matched |
| rule overhang past text | 36 | 26 | `Style.ruleOverhang` |
| paragraph gap | 64 (≈ 1 pitch) | — | `paragraphSpacing = linePitch` |
| rule | black 10% | — | `Style.ruleTone`, multiplied |

That the margins independently came out at 203 against the 200 already in the
app is the check that the 16/22 factor is real rather than fitted.

**Pitch is the constant and leading is derived from it** — not the other way
round. Settings lets the reader change font family, and a fixed leading would
give every family its own pitch and its own ruling. Fixing the pitch means a
family with a different natural line height gets different leading and still
lands on the same rules.

**Type is centred in its band, and the ruling moves rather than the text.**
AppKit puts leading below the glyphs, so a fragment is `[glyphs][leading]` and
its bottom edge is a whole leading from the words; ruling on that edge leaves
every line hugging the rule above it, worse the more leading there is. The band
is `linePitch` and the glyphs are the font's line height, so centring is half a
leading of shift — applied to the ruling, so no baseline moves and selection,
the caret and sticky anchors all stay where the layout manager put them.

**Where the system and the ink ladder disagree, the ladder wins.** The system
draws the past-notes glyph at `#967654`, which solves to roughly 0.68 of the ink
over its background — between `inkMuted` (0.55) and `inkStrong` (0.85), on no
rung. It is drawn `inkMuted`, which keeps the relationship the system is
actually expressing (that glyph darker than the new-note plus, which is
`#c6a78a` and *is* `inkFaint` to within a point per channel) without adding a
fifth alpha step to a ladder that was deliberately collapsed to four.

**Any gap that isn't a whole number of pitches walks the type off the grid.**
That is why `paragraphSpacing` is exactly one pitch (a break skips one rule) and
the bullet gap is exactly zero (list items take consecutive rules).

### The icon here is fixed, and that switches a whole mechanism off

`AppIconRe.icns` is the cream flourish (`#F2E3C9`) on pure black — full-bleed
1024², the same single-image structure the original `.icns` uses, and it is
copied in *as* `AppIcon.icns` so `CFBundleIconFile` needs no change.

It deliberately **does not follow the theme**. Two reasons: the two builds have
to be told apart at a glance in the Dock, ⌘-Tab and Finder whatever mood either
is set to; and a dark icon is not something the recolour could produce anyway,
since it maps the artwork's two tones onto two *theme* colours and is therefore
light by construction.

So `AppIcon.followsTheme` (`Theme.swift`) is `false` here, and `apply` and
`refreshDockTile` return immediately. Everything the main branch's write-up
describes — the persisted `Icon\r` override, the broken strict code seal, the
Dock restart on quit — **does not happen on this branch**, and the strict
verification `build.sh` runs stays passing on an installed copy. `prepare()`
still runs, harmlessly: it clears any override a previous run left behind.

The call sites in `main.swift` are untouched, so re-enabling is one line.

**That leaves `recoloured`, `persist`, `image(for:)`, the cache and `pristine`
unreachable on this branch, and they are kept deliberately.** They are live code
on `main`, and this branch is meant to merge *forward* into it — deleting them
here would make the merge quietly drop the themed Dock icon, which is a feature
rather than drift. It is the one region of unreachable code in the repo that is
supposed to be there; everything else the audit found has been removed.

The scratch vault at `~/Library/Application Support/re-JUI/Notes` was seeded
with a **copy** of the real notes, so the redesign is judged against real prose
— real line lengths, real folders, a real sticky — rather than lorem ipsum.
It is a copy: edits made in `re-JUI` never reach the real vault, and are also
never carried back to it.

## Build & ship

```bash
./build.sh
```

**Run the staged copy, not the one in the repo.** `build.sh` finishes by
copying the bundle to `~/Library/Application Support/re-JUI-dev/` and prints the
path.

This repo is inside `~/Documents`, which macOS protects with TCC, so the
bundle's own resources are files in a protected folder and launching it reads
them. That would normally be a one-time prompt — macOS exempts an app for its
own bundle and remembers the answer — but both of those hang on a stable
code-signing identity, and an ad-hoc signature has none. `codesign --sign -`
leaves `Signature=adhoc` with `TeamIdentifier=not set`, and this script re-signs
from scratch every build, so the identity is different each time. The approval
has nothing durable to attach to, and the prompt returns on *every launch*.

Verified both ways: the same bundle asks every time from the repo and never asks
from the staging directory. Notarisation would fix it properly; until then, do
not run the dev build out of `~/Documents`. The zip and the bundle in the repo
are untouched, so what ships is unaffected.

One command does everything: universal build, macOS 26 floor, per-build
`CFBundleVersion` stamp, ad-hoc sign, signature verify, and `JUI.zip`. It stops
rather than shipping a broken bundle. Then to see it:

```bash
./build.sh && open JUI.app
```

There are no tests. Verification is running the app and looking at it. When
changing anything visual, actually launch it.

`build-number` is a tracked counter file — it increments on every build and is
stamped into the bundle's `CFBundleVersion`, so two builds are never
indistinguishable. `CFBundleShortVersionString` (the user-facing `1.0`) is left
alone, as is the source `Info.plist`.

**Never repackage the zip by hand, and never with Finder's Compress.** The
assets carry a `com.apple.macl` xattr that `xattr -cr` *cannot* remove — the
kernel owns it. Any archiver that preserves xattrs writes an AppleDouble `._`
companion per file; extracted with anything but Finder, those land inside the
bundle as files that aren't in the code seal, and the app dies with *"a sealed
resource is missing or invalid"* — a launch failure that looks nothing like its
cause. `build.sh` passes `--norsrc --noextattr` to `ditto` for exactly this
reason. To check an archive before sending it:

```bash
unzip -Z1 JUI.zip | grep -c '^\._\|__MACOSX'   # must be 0
```

What matters is that count, not the number of entries. This used to read "must
show 13 entries", from before the app shipped a directory of textures and three
directories of animation frames — it is a little over a hundred now, and a
hardcoded total is a check that fails for the wrong reason every time the art
changes.

**Distribution caveat.** The app is only ad-hoc signed — notarization needs a paid
Apple Developer account. Every rebuild gets a fresh signature, so a Mac that
already approved an earlier JUI treats the new one as a stranger. On the
receiving Mac, after unzipping and before first launch:

```bash
xattr -cr JUI.app
```

Then move it to `/Applications` before opening (a quarantined app launched from
`Downloads` gets translocated to a read-only mount).

## Design language

Reuse the existing tokens; don't introduce new colors unless the design genuinely
has no near neighbour (the envelope `#EBCEA3` and letter `#FFFAF3` are the only
two that earned it).

### Every raised surface takes paper

`Texture.swift` holds the list: `page`, `sticky`, `folderPanel`, `folderTile`,
`palette`, `button`, `envelope`, `letter`. Each names a stock, a strength and a
fit, all three recovered from the design rather than guessed — read the comments
there before changing a number.

**A new raised surface goes on the list.** In SwiftUI the shape is
`colour.papered(.surface).clipShape(…)` — colour, then paper, then clip, in that
order, or the grain squares off behind the corner radius. The settings cards were
the last three flat ones in the app and now take `.folderPanel`, since they are
the same thing the notes panel is: a panel-toned pane raised off the page. Their
inner wells stay flat, because a well is a hole in the card rather than another
surface on top of it — the same call the ⌘K result rows make.

The AppKit half is `Surface.draw(in:)`, and it has to be drawn into the same
context as the colour it is texturing: a multiply can only see what is already in
its own context, so paper drawn over a background living *behind* the view finds
nothing to darken and paints flat instead.

### Theming — read this before touching any colour

The app ships **six themes** (cream, mint, sky, coral, lilac, orchid), picked in
onboarding and in settings. `Style.theme` is the single global they hang off;
every colour token in `main.swift` is a **computed var** reading through it, so
a theme change repaints the app without any call site knowing about it.

**Never write a colour literal outside `Theme.swift`.** A hardcoded value won't
follow the theme, and the bug only shows up in five of the six. Add the token to
`Theme` and give all six palettes a value.

Two halves have to be kept in step:

1. **SwiftUI** re-renders on its own — `NotesStore.themeID` is `@Published`, so
   `ContentView` and everything under it re-reads the computed tokens.
2. **AppKit does not.** Colours captured at init (layer backgrounds, caret,
   `selectedTextAttributes`) and colours baked into the text storage's
   attributes have to be pushed. That's what `PlainTextView.applyTheme()` is
   for — `RichTextEditor.updateNSView` calls it when `themeID` changes, and it
   fans out to `SmoothCaret`, `SelectionIconView`, the open `StickyView`, every
   `StickyBallView`, and the
   traffic-light overlay in the title bar. **Any new AppKit view that holds a
   colour needs an `applyTheme()` and a call added to that fan-out.**

`setTheme` deliberately does **not** bump `docVersion` the way `setFont` does.
A theme change happens mid-sentence from the settings page, so the ink is
rewritten as an attribute-only edit on the existing storage — selection, scroll
position and undo all survive. Bumping `docVersion` would reload the document
and throw the caret to the end of the note.

**The Dock icon follows the theme, but only while running.** `AppIcon` in
`Theme.swift` maps the icon's two tones — a gold field, a cream motif — onto
`sticky` and `sheet`, applied via `NSApplication.applicationIconImage` in
`PlainEditorApp.init()` and on every `setTheme`, cached per theme.

Two things about it are load-bearing, and both were bugs first:

1. **It recolours `NSWorkspace.icon(forFile: bundlePath)`, not `AppIcon.icns`.**
   The raw asset is a full-bleed opaque square; macOS insets it to the
   824-in-1024 grid and masks it to the system squircle before Finder ever shows
   it. But `applicationIconImage` is drawn exactly as handed over — so
   recolouring the raw file gave a Dock tile that was hard-cornered and visibly
   larger than its neighbours. Starting from the composed icon inherits the right
   geometry for whatever macOS is running, with no shape maths here to go stale.
2. **The two endpoint tones are measured off the bitmap, not hardcoded.** The
   `.icns` is colour-converted on its way into a `deviceRGB` bitmap, so the gold
   arrives as `#F7C82D`, not the `#F9D039` the file contains. Constants taken
   from the file left the motif a few percent short of `sheet`.

Premultiplication matters too: undo it before reading a pixel's tone and redo it
after, or the soft squircle edge reads as near-gold and picks up a bright fringe.

**And it persists past quit**, via `NSWorkspace.setIcon(_:forFile:)` on the
bundle — the same thing pasting into a Get Info window does, and the mechanism
Granola's write-up settled on. `applicationIconImage` alone dies with the
process, so Finder (and a pinned Dock tile) reverted to the gold default.

Three things hold this together:

- **`prepare()` must run before any themed icon is applied, exactly once.** It
  clears the previous run's override and captures the pristine artwork. Without
  it the recolour would read its own output as the source and compound —
  catastrophically, not subtly, since lilac's field and motif differ by 2 in blue
  where the original gold and cream differ by 172.
- **Cream removes the override rather than writing a copy of the default.** That
  leaves no stale file, and restores the code seal exactly.
- **The seal really does break for the other five.** `codesign --verify --deep
  --strict` fails with "resource fork, Finder information, or similar detritus
  not allowed" once the `Icon\r` exists. Verified that the app still launches
  through LaunchServices, that plain `codesign --verify` still passes, and that
  switching back to cream restores strict verification. The build output and the
  shipped zip are never affected — `build.sh` rebuilds the bundle from scratch,
  so only an installed copy that has been run carries the file.

**A pinned Dock tile needs the Dock restarted.** `setIcon` updates Finder
immediately, but the Dock keeps its own cache of a pinned tile's icon. Measured:
`touch`ing the bundle and `lsregister -f` both leave the stale tile in place;
only relaunching the Dock clears it (`AppIcon.refreshDockTile()`, which
terminates `com.apple.dock` and lets launchd bring it back).

That fires **on quit, and only if the theme changed during the session** —
`NotesStore.themeChangedThisSession`. While the app is running the tile draws
`applicationIconImage` and is already correct, so the stale cache is invisible
until the app is gone; doing it at quit means the Dock never flashes mid-use, and
an ordinary quit leaves the Dock alone entirely. Don't move this to `setTheme`.

Granola reached for a private Dock API for the same problem. Restarting the Dock
is public, and at this app's scale the difference doesn't justify the fragility.

If JUI is ever notarised, this needs revisiting: notarisation would reject a
bundle carrying that file, though the artifact you submit is built fresh and so
would be clean.

**Bundled art must be tinted, not drawn raw.** The flourish frames are
single-colour silhouettes with clean alpha, which is what lets one sequence serve
all six themes. In SwiftUI use `.renderingMode(.template)` plus a
`foregroundStyle` — that is what `AnimatedFlourish` does. `StickyView` draws by
hand instead, so it bakes a tinted copy: `sourceAtop` straight over the original
would catch the sticky's own opaque background.

The four static PNGs this paragraph used to describe — `Flourish`,
`StickyFlower`, `FolderSprig`, `OnboardingLogo`, plus the later `StickyFlourish`
and `FolderFlourish` — are gone. The animation replaced every one of them and
nothing had read them for some time; they were still being copied into every
bundle. The one thing they left behind is `folderMarkWidth`/`Height`/`Gap` in
`main.swift`, which hold the air above a folder's name — the mark moved to the
tile's background, so those are the sprig's old metrics keeping its space, and
the tile height is computed from them.

### Palette (cream — the other five are the same structure, hue-rotated)

- sheet `#FDF0D9` · panel/selection `#ECDBBE` · ink `#71390D` · open-note dot
  `#A88D34` · folder card `#F3E4CA` · sticky `#F7C82D` · flourish `#F2E3C9` ·
  envelope `#EBCEA3` · letter `#FFFAF3`
- **Three tokens that used to be here are now tones, not colours**, and were
  removed from `Theme` rather than left unused: `divider` (`#E6D4B5`) became
  `panelDividerColor`, black at 12%, because a fixed hairline *inverted* once the
  panels took their paper and read as a pale scratch across the card; `rule`
  (`#AD9E84`) became `Style.ruleTone` when horizontal rules gave way to the ruled
  page; `flourishHover` (`#F2DEBA`) became `flourishHovered`, panel taken a step
  toward the ink, because hovering has to *deepen* the mark now rather than lift
  it. All three follow the same principle — a tone is one value that is right in
  all six themes and over paper, where a colour has to be picked six times and
  can still invert.
- **There is one ink, `brownInk` (`#71390D`), at four fixed steps** —
  `brownInk` (1.0) / `inkStrong` (0.85) / `inkMuted` (0.55) / `inkFaint` (0.4),
  declared at the top of `main.swift`. Write `.foregroundStyle(inkMuted)`, never
  `.opacity(0.5)`: a fresh opacity is a fifth colour nobody chose. The app used
  to carry a second near-black ink and ten ad-hoc alpha steps; that's been
  collapsed, so don't reintroduce either.
- **The caret is `Style.ink`, deliberately.** It was `NSColor.controlAccentColor`
  and rendered in the user's system accent — pink on the author's Mac. The one
  element on the page that never stops moving has to be in palette.
- Type scale is 10 / 11 / 12 / 13 / 14 / 16. **16 is the largest text in the
  app** — including onboarding titles, which is why the Figma frames' 34/24 were
  deliberately not used (see the `T` enum in `Onboarding.swift`).
- **Write `.font(houseFont(13))`, never `.font(.custom("Courier", size: 13))`.**
  Type goes through one function for the same reason colour goes through one
  token: settings lets the reader change family, and a literal doesn't follow it.
  Every call site was a literal, so the picker restyled the page and left the
  panel rows, search results, folder names, stickies and onboarding in Courier —
  and inside the ⌘K field the typed text followed the choice while the
  placeholder drawn behind it did not, which put two families on one line.
  `Style.font(_:)` is the AppKit half, resolved through `NSFontManager` because
  `fontFamily` is a *family* name: `NSFont(name:)` wants a font's own name, and
  the two coincide for Courier and not for most of what the picker offers.
- **AppKit views holding a font need pushing, like colours do.** A sticky's
  editor is one, so `RichTextEditor.updateNSView` watches `store.fontFamily` and
  calls `tv.applyFont()` — the same shape as the `themeID` fan-out beside it. The
  note's own text arrives via `docVersion` instead, since `setFont` restyles the
  storage in the store and bumps it.
- Motion: 0.15s ease-out for hovers and panel fades, 0.2–0.25s for page
  transitions, 0.7–0.75s for the onboarding letter. Reduced-motion collapses
  onboarding to a straight cut.
- Exactly one highlight exists in the notes panel at a time
  (`PanelHighlight`). Notes slide a shared box via `matchedGeometryEffect`; folder cards
  cross-fade instead, because morphing between tall half-width cards and short
  full-width rows arced visibly.
