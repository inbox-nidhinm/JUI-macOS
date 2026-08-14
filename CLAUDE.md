# JUI

A single-window macOS writing pad — a cream sheet, Courier, no chrome. Built as a
gift for Juilee. Design-led: how it *feels* matters more than feature count, and
almost every oddity in the code is a deliberate fix for something that felt wrong.

**Read `CHANGELOG.md` for *what* was built and why, in order.** This file is the
map of *where things are* and *what will break if you touch them*.

## Shape of the project

No Xcode project. Two Swift files compiled directly by `swiftc`:

| File | Lines | Contents |
|---|---|---|
| `main.swift` | ~2600 | Everything: tokens, store, text engine, stickies, panel, search, settings |
| `Theme.swift` | ~150 | The six palettes, and the mood-dot `ThemePicker` |
| `Onboarding.swift` | ~490 | First-run envelope flow only |
| `build.sh` | | Universal build + ad-hoc sign + verify |
| `Info.plist` | | `com.nidhin.jui`, `LSMinimumSystemVersion 13.0` |

**Adding a `.swift` file means adding it to the `swiftc` line in `build.sh:24`.**

Assets live at the repo root and are copied into `Contents/Resources` by
`build.sh`: `AppIcon.icns`, `Flourish.png` (corner flourish), `StickyFlower.png`,
`FolderSprig.png`, `OnboardingLogo.png`. **Adding an asset means adding it to the
loop in `build.sh:17`** or it silently won't ship.

### Landmarks in `main.swift`

| Region | Line | What |
|---|---|---|
| Colour tokens | 7–35 | Computed vars reading `Style.theme` — never literals |
| `Style` | 38 | Theme global, fonts, margins, paragraph styles, hr/bullet constants |
| `NoteMeta` / `SearchHit` / `Sticky` | 99–125 | Models |
| `NotesStore` | 127 | The single source of truth for everything |
| `SmoothCaret` | 717 | Shared caret glide (note editor *and* stickies) |
| `StickyView` | 843 | Postage-stamp margin annotation, drawn by hand |
| `PlainTextView` | 1107 | The `NSTextView` subclass — bullets, rules, cursors, paste, `applyTheme` |
| `RichTextEditor` | 1571 | `NSViewRepresentable` bridge + `Coordinator` |
| `TrafficDotsOverlay` / `WindowConfigurator` | 1750–1792 | The flat dots over the traffic lights |
| `SearchPalette` | 1892 | ⌘K — results *and* commands |
| `ContentView` | 2098 | Layout, notes/folders panel, settings block |
| `PlainEditorApp` | 2681 | `@main` (name is legacy — app was renamed, type wasn't) |

These line numbers drift with every edit. If one is off by more than a few, grep
the declaration rather than trusting the table.

### ⌘K holds commands as well as matches

Below the results the palette can show **command rows**, and results plus commands
share **one selection space** (`selected` indexes across both), so the arrows walk
the whole list and Return fires whatever is highlighted. A command row carries the
same highlight box as a result so it reads as selectable.

- **`hide/show sticky notes`** — appears on an empty query or one about stickies.
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

- Note **title** is derived, never stored: first non-empty line, 42 chars (`NotesStore.title`, :532).
- Note **order** is `contentModificationDate` descending.
- `refreshList()` (:486) rescans the vault from disk; it is the only thing that
  populates `notes`/`folders`. Call it after any file operation.
- Saves are debounced 300ms (`scheduleSave`, :637) and also fire on
  `willTerminate` and before any note switch. An empty never-typed note is
  never written to disk (:651).

`UserDefaults` keys — the complete set: `vaultPath`, `fontFamily`, `displayName`,
`onboardingCompleted`.

### `docVersion` is the load signal

`store.docVersion` increments **only when a different document is loaded into the
editor — never on typing**. `RichTextEditor.Coordinator.loadedVersion` compares
against it (:1528) to decide whether to blow away the text view's contents.

If you add a path that changes `attr` wholesale, bump `docVersion`. If you bump
it on keystrokes, you'll wipe the undo stack and fight the caret on every letter.

### Overlay states

Three mutually-aware overlays, all flags on the store:

- `hiddenShown` — the flourish page: dedication + settings (name, vault, font)
- `searchShown` — ⌘K palette
- `onboardingShown` — first run; **cannot be escaped** (`onExitCommand {}`)

`editorBlocked` (`hiddenShown || onboardingShown`, :160) freezes the text view.
`RichTextEditor.updateNSView` (:1510) is what actually flips
`isEditable`/`isSelectable` and moves first responder.

## Invariants — break these and something visibly regresses

**TextKit 1, assembled by hand.** `makeNSView` (:1463) builds
`NSTextStorage` → `SelectionColorLayoutManager` → `NSTextContainer` explicitly,
and `tv.retainedStorage` keeps the storage alive. This is *not* legacy drift —
`SelectionColorLayoutManager` (:1002) is the only reliable way to stop selections
turning system-gray when focus moves into a sticky. Do not migrate to TextKit 2.

**Cursor handling lives in exactly two places.** `resetCursorRects` (:1404) is the
mechanism AppKit actually honours for the dead margins; `ArrowZones.hoverCount`
(:1016) lets SwiftUI controls drawn *on top of* the text view claim the arrow via
`.arrowCursorZone()`. Earlier attempts elsewhere (`mouseMoved`, `cursorUpdate`)
are kept as belt-and-braces but are not sufficient alone. Don't add a third way.

**The native caret is fully suppressed, three ways at once** — `insertionPointColor
= .clear`, an empty `drawInsertionPoint` override, and hiding
`NSTextInsertionIndicator` on macOS 14+ (:698). All three are needed. `SmoothCaret`
draws it as a `CALayer`. Any new text field in the app should use it too.

**Horizontal rules are a single no-break space** (`Style.hrMarker`) alone in a
paragraph, with the line *drawn* in `drawBackground` (:1358). Not a character run —
that's how they re-fit on resize. `loadAttr` migrates old `"───…"` notes (:553).

**Bullets are literal `"• "` text** plus `Style.bulletParagraph` (hanging indent).
`normalizeFonts` (:1587) identifies them by `headIndent > 0` — if you change how
bullets indent, update that check or bullet paragraphs get restyled as prose.

**Typewriter input.** Smart dashes, quotes, and text replacement are off
everywhere. Smart dashes silently broke `---` rules once already.

**Sticky anchors are character ranges, remapped on every edit** via
`textView(_:shouldChangeTextIn:)` → `store.remapStickies` (:272). Anchors inside a
deleted range collapse to the edit point rather than dying. `syncStickies` (:1078)
rebuilds positions on every layout pass. A sticky measures its own height, and
must be width-set *before* measuring (:946) or long notes load at default size.

**`normalizeFonts` is a safety net, not the styling path.** It forces family/size,
paragraph style, and ink color, and strips underline/strike/link/shadow/etc. from
anything that arrives styled (drops, services). Paste is already handled
separately and always plain (:1218).

## macOS 13 floor — the hard compatibility rule

The app must keep launching on macOS 13, universal (arm64 + x86_64). An
arm64-only or 14-only build fails on other Macs with a bare
*"The application can't be opened"*, which reads like a signing problem and isn't.

Two consequences for any new SwiftUI you write:

1. **`onChange(of:)` must use the single-parameter closure** — `{ new in … }`.
   The two-parameter `{ old, new in … }` form is macOS 14+. Every existing call
   site uses the old form on purpose.
2. **Anything 14+ needs `if #available`.** There is now exactly **one** gated
   site: `NSTextInsertionIndicator`, in `SmoothCaret`. ⌘K's arrow navigation used
   to be the second, via `onKeyPress`; `HouseField` handles arrows through
   AppKit's `doCommandBy` instead, which works on 13, so that gate is gone.

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

**`HouseField.Bed` is the non-obvious part.** The selection has to be one step
away from whatever the field is sitting on. The editor selects panel-on-sheet,
but the ⌘K palette's own background *is* the panel colour, so reusing that made
the selection invisible — same colour on same colour. A field declared
`bed: .panel` selects in sheet instead, which is also what the palette's result
rows already highlight with. Get this wrong and the selection silently vanishes
rather than looking wrong.

## Build & ship

```bash
./build.sh
```

One command does everything: universal build, macOS 13 floor, per-build
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
unzip -Z1 JUI.zip   # must show 12 entries, no ._ files, no __MACOSX
```

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
   fans out to `SmoothCaret`, `SelectionIconView`, every `StickyView`, and the
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

**Bundled art must be tinted, not drawn raw.** All four PNGs are single-colour
silhouettes with clean alpha. In SwiftUI use `.renderingMode(.template)` plus a
`foregroundStyle` (that's how `Flourish`, `FolderSprig` and `OnboardingLogo`
follow the theme). `StickyFlower` is drawn by hand in `StickyView.draw`, so it
gets a tinted copy cached per theme — `sourceAtop` straight over the original
would catch the sticky's own opaque background. Their baked tones map to
`flourish`, `divider`, `flourish` and `sheet` respectively, which is why the
cream theme looks unchanged.

### Palette (cream — the other five are the same structure, hue-rotated)

- sheet `#FDF0D9` · panel/selection `#ECDBBE` · ink `#71390D` · divider
  `#E6D4B5` · open-note dot `#A88D34` · folder card `#F3E4CA` · rule `#AD9E84`
  · sticky `#F7C82D` · flourish `#F2E3C9`/`#F2DEBA` · envelope `#EBCEA3` ·
  letter `#FFFAF3`
- **There is one ink, `brownInk` (`#71390D`), at four fixed steps** —
  `brownInk` (1.0) / `inkStrong` (0.85) / `inkMuted` (0.55) / `inkFaint` (0.4),
  declared at the top of `main.swift`. Write `.foregroundStyle(inkMuted)`, never
  `.opacity(0.5)`: a fresh opacity is a fifth colour nobody chose. The app used
  to carry a second near-black ink and ten ad-hoc alpha steps; that's been
  collapsed, so don't reintroduce either.
- **The caret is `Style.ink`, deliberately.** It was `NSColor.controlAccentColor`
  and rendered in the user's system accent — pink on the author's Mac. The one
  element on the page that never stops moving has to be in palette.
- Type scale is 10 / 11 / 12 / 13 / 14 / 16, Courier throughout. **16 is the
  largest text in the app** — including onboarding titles, which is why the
  Figma frames' 34/24 were deliberately not used (`Onboarding.swift:60`).
- Motion: 0.15s ease-out for hovers and panel fades, 0.2–0.25s for page
  transitions, 0.7–0.75s for the onboarding letter. Reduced-motion collapses
  onboarding to a straight cut.
- Exactly one highlight exists in the notes panel at a time (`PanelHighlight`,
  :1938). Notes slide a shared box via `matchedGeometryEffect`; folder cards
  cross-fade instead, because morphing between tall half-width cards and short
  full-width rows arced visibly.
