# Art drop

Where source art goes. Drop files in, tell me what they are, and I'll wire
them up.

```
Art/
  Textures/    grain and paper — shipped into the bundle as-is
  Vectors/     SVG sources — converted to Swift paths, never shipped
  Reference/   Figma exports, screen recordings, anything to look at
```

Only `Textures/` is copied into `JUI.app`. `Vectors/` and `Reference/` are
inputs to the build, not part of it.

---

## Textures

**Tileable swatches, not full-frame overlays.** A 512×512 tile that repeats
costs a few hundred KB and stays crisp at any window size. A full-frame export
has to be stretched to fit, which softens the grain into mush at exactly the
scale where grain is the whole point — and it's the same picture at every size,
so resizing the window visibly rescales the paper.

If a texture genuinely can't tile (a vignette, a deckled edge, anything that
belongs to one specific edge or corner), say so and send it full-frame — those
are the cases where stretching is correct.

| | |
|---|---|
| Format | PNG |
| Size | 512×512 or 1024×1024, power of two |
| Scale | export at 2× — it's drawn at half size on Retina |
| Colour | **greyscale**, not tinted |
| Alpha | none needed; the blend mode does the work |
| Seams | must tile — offset it by half and check the middle |

### Greyscale is load-bearing

The texture must carry no colour of its own. Under `multiply` the surface's
themed colour comes through the texture; under `plusDarker` it's darkened by the
texture's own value. Either way the **colour comes from the theme underneath and
the tone comes from the texture** — which is exactly what makes one texture work
across all six palettes instead of needing six.

A texture with a cream cast baked in will look right in cream and wrong in the
other five, and it'll be wrong in a way that's hard to name — slightly muddy,
slightly off-temperature, no single pixel obviously broken.

### What I need alongside each file

The three numbers Figma already knows:

1. **Which surface** — sheet, panel, folder card, sticky, envelope, letter…
2. **Blend mode** — `multiply` or `plus darker`
3. **Layer opacity** — the percentage from Figma

Naming them like this is enough, and means you can drop several at once without
a covering note:

```
sheet-grain@2x.png
sticky-fibre@2x.png
panel-tooth@2x.png
```

### Two things to expect

**Multiply darkens.** Ink-on-sheet contrast currently clears 4.5:1 in all six
themes, and darkening the sheet only widens that, so legibility is safe. The
risk runs the other way: a heavy grain can make a pastel sheet look dingy rather
than textured. Lilac and orchid are the ones to watch — they carry the least
headroom.

**`plusDarker` is harsher than it looks in Figma.** It's a linear burn — it
clips to black rather than easing into it — so a value that reads as a whisper
over cream can go blotchy over a darker panel. Send both blend modes if you're
unsure and I'll show you the pair side by side in the running app.

---

## Vectors

SVG sources for anything that should animate. They don't ship — I convert the
path data into Swift `CGPath` builders and commit the generated code, so there's
no SVG parser in the app and no runtime cost.

**How the file is structured decides what the motion can do**, so this matters
more than the export settings:

- **One merged path** → I can only move the whole thing. Fade, drift, scale,
  rotate, sway. Nothing internal.
- **One path per element**, ideally grouped and named (`petal-1`, `stem`,
  `leaf-3`) → per-element staggers, a stem that draws itself on, petals that
  open in sequence, a flourish that assembles rather than fades in.

So: **expand strokes, don't merge shapes, keep the layer names**. If the flourish
is currently one flattened outline, splitting it is the single highest-leverage
thing you can do for the motion.

Also useful, if it's no trouble: a consistent `viewBox` per asset and the origin
at the natural anchor (the base of the stem for the flourish, rather than the
bounding-box centre) — it saves guessing where a sway should pivot from.
