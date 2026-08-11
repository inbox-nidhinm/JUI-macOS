# JUI

A single-window macOS writing pad. A cream sheet, Courier, and no chrome — built
to feel like a page rather than an app.

It was written as a gift, so it optimises for how it *feels* to write in rather
than for feature count. Three Swift files and a shell script: no Xcode project,
no package manager, no dependencies.

## What it does

- **A page, not a document window.** Hidden title bar, wide margins, justified
  paragraphs, and traffic lights covered by flat cream dots that only reveal
  themselves under the pointer.
- **Silent autosave.** Notes are RTF files in a folder you choose, named by UUID
  — readable in Finder, portable, no database.
- **Folders**, one level deep, that are real subdirectories on disk.
- **Sticky notes** anchored to a range of text rather than to pixels:
  postage-stamp margin annotations that survive edits and reflow, and can be
  dragged out to pin anywhere on the page.
- **⌘K search** across every note, with snippets, folder prefixes, and a command
  row or two.
- **Six themes** — cream, mint, sky, coral, lilac, orchid — applied instantly.
  Each one holds the original's lightness and saturation and rotates only hue,
  so contrast and hierarchy survive the change.
- **Writing conveniences**: markdown-style bullets, `---` for a full-width rule,
  ⌘I for italics, typewriter-style input that never rewrites your dashes or
  quotes, and a caret that glides rather than jumps.

## Build

```bash
./build.sh
```

Produces a universal `JUI.app` (Apple Silicon + Intel, macOS 13 and later),
ad-hoc signs and verifies it, stamps a fresh build number, and packages
`JUI.zip`. Needs the Swift toolchain from Xcode or the Command Line Tools.

## Installing a build

The app is only **ad-hoc signed** — notarisation needs a paid Apple Developer
account — so macOS treats every new build as an unknown app. After unzipping,
before the first launch:

```bash
xattr -cr JUI.app
```

Then move it to `/Applications` before opening it. A quarantined app launched
from `Downloads` gets translocated to a read-only mount, which produces its own
confusing failures.

## Layout

| File | What's in it |
|---|---|
| `main.swift` | Colour tokens, store, text engine, stickies, panel, search, settings |
| `Theme.swift` | The six palettes and the theme picker |
| `Onboarding.swift` | First-run envelope flow |
| `build.sh` | Build, sign, verify, package, push |
| `CLAUDE.md` | Architecture notes, and the invariants worth not breaking |
| `CHANGELOG.md` | What was built, in order, and why |

Requires macOS 13 or later.
