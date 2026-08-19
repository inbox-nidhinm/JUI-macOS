#!/usr/bin/env python3
"""Splits a frame-by-frame animated SVG into one still SVG per frame.

The export stacks all 30 frames in one file and shows them in turn with CSS
`@keyframes` on opacity. AppKit ignores CSS entirely, so rendering the file as
it stands draws every frame at once. Each frame is therefore lifted into its
own document, which the renderer can then draw as a still.

Frames are whole pictures, not deltas — frame 1 holds two elements and frame 30
holds thirteen, which is the finished flourish — so the sequence is a drawing
being made rather than parts being added to a canvas.

The background rect is dropped: the app needs the artwork on transparency so it
can be tinted to the theme.
"""
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

svg = src.read_text()

open_tag = re.search(r"<svg[^>]*>", svg).group(0)
defs = re.search(r"<defs>.*?</defs>", svg, re.S)
defs = defs.group(0) if defs else ""

# Each frame is a <g class="fr" ...> ... </g> at the top level. Groups nest
# (masked groups live inside frames), so the closing tag is found by counting
# rather than by matching the first </g>.
frames = []
for m in re.finditer(r'<g class="fr"[^>]*>', svg):
    i = m.end()
    depth = 1
    while depth:
        nxt = re.search(r"<g\b[^>]*>|</g>", svg[i:])
        if not nxt:
            break
        i += nxt.end()
        depth += 1 if nxt.group(0).startswith("<g") else -1
    frames.append(svg[m.end(): i - len("</g>")])

for n, body in enumerate(frames, start=1):
    (out / f"frame-{n:02d}.svg").write_text(
        f"{open_tag}\n{defs}\n<g>{body}</g>\n</svg>\n")

print(f"{len(frames)} frames -> {out}")
