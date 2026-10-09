#!/bin/zsh
# Builds JUI.app next to this script.
#
# Universal (Apple Silicon + Intel) with a macOS 26 floor. The floor was 13
# until the sticky rework, which leans on SceneKit and AppKit API that 13 lacks;
# 26 is also the last macOS that runs on Intel, so the x86_64 slice still earns
# its place. An arm64-only build fails to launch on an Intel Mac with a bare
# "the file cannot be opened", which looks like a signing problem but isn't.
set -e
cd "$(dirname "$0")"

# --- identity ----------------------------------------------------------------
# The app's name, bundle id and build counter, stamped into the bundle below.
# Until build 69 this branch was re-JUI, a look rebuild that ran *beside* the
# shipping JUI under its own name (re-JUI), id (com.nidhin.jui.re) and counter
# (build-number-re), so it never touched the real app's notes or settings. It
# replaced JUI outright on 2026-10-10 and these went back to the real app's
# values; the counter carries on from re-JUI's 69, so builds keep climbing.
NAME="JUI"
BUNDLE_ID="com.nidhin.jui"
COUNTER="build-number"
# (There was a fourth, ICON, for a fixed black icon that told the rebuild apart
# in the Dock. The icon follows the mood now, as on the phone — see below.)

APP="$NAME.app"
ZIP="$NAME.zip"
DEPLOY_TARGET="26"

rm -rf "$APP" # start clean so no stale resource breaks the signature seal
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

# Every build gets its own CFBundleVersion, so two builds are never
# indistinguishable when one works and the other doesn't. The user-facing
# CFBundleShortVersionString in Info.plist is left alone. Stamped before signing:
# editing Info.plist afterwards would break the signature seal.
BUILD_NUMBER=$(( $(cat "$COUNTER" 2>/dev/null || echo 0) + 1 ))
echo "$BUILD_NUMBER" > "$COUNTER"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
  "$APP/Contents/Info.plist" > /dev/null

# The identity above is stamped in here rather than kept in the source
# Info.plist, so that file stays the canonical description of the real app.
# CFBundleName is load-bearing beyond the menu bar: NotesStore derives the vault
# folder from it, so a build under another name keeps its own notes.
for key in CFBundleName CFBundleDisplayName CFBundleExecutable; do
  /usr/libexec/PlistBuddy -c "Set :$key $NAME" "$APP/Contents/Info.plist" > /dev/null
done
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" \
  "$APP/Contents/Info.plist" > /dev/null
# There is no loop of individual PNGs here any more, and no PNGs at the repo
# root to feed one. The rebuild replaced every static mark with the stop-motion
# flourish below, so Flourish, StickyFlower, FolderSprig, OnboardingLogo,
# StickyFlourish and FolderFlourish were all still being copied into every
# bundle with nothing left in the app that drew them. The two remaining kinds of
# art ship as *directories* — Textures and FlourishFrames — which is also what
# stops this failing silently: a per-asset list does nothing when someone adds a
# file and forgets to name it, and on this branch drawing nothing and drawing a
# very subtle grain look identical.

# The icon follows the mood: six icons from the Figma system (node 331:539), the
# same artwork as the iPhone app, in Art/AppIcons. Art/render-icons.swift sets
# each on the macOS icon grid (an 824 tile on a clear 1024 canvas, with the
# shadow macOS icons carry) through WebKit; all six ship in AppIcons/ for the
# app to switch between (`AppIcon` in Theme.swift), and cream becomes the
# bundle's own AppIcon.icns — what CFBundleIconFile names, and what Finder shows
# before the app has ever run. Cached on the sources' modification time.
ICONS="Art/AppIcons"
mkdir -p .iconcache
if [ ! -f .iconcache/AppIcon.icns ] \
   || [ -n "$(find "$ICONS" -newer .iconcache/AppIcon.icns -name '*.svg')" ] \
   || [ Art/render-icons.swift -nt .iconcache/AppIcon.icns ]; then
  swift Art/render-icons.swift "$ICONS" .iconcache > /dev/null
  rm -rf .iconcache/AppIcon.iconset && mkdir -p .iconcache/AppIcon.iconset
  for size in 16 32 128 256 512; do
    sips -z $size $size .iconcache/cream.png \
      --out ".iconcache/AppIcon.iconset/icon_${size}x${size}.png" > /dev/null
    double=$(( size * 2 ))
    sips -z $double $double .iconcache/cream.png \
      --out ".iconcache/AppIcon.iconset/icon_${size}x${size}@2x.png" > /dev/null
  done
  iconutil -c icns .iconcache/AppIcon.iconset -o .iconcache/AppIcon.icns
  echo "Icons: rebuilt 6 moods + AppIcon.icns"
fi
cp .iconcache/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/AppIcons"
cp .iconcache/{cream,mint,sky,coral,lilac,orchid}.png "$APP/Contents/Resources/AppIcons/"

# Textures ship as a directory rather than by name. The rebuild adds and drops
# these constantly, and the old per-asset loop above fails silently when someone
# adds a file and forgets to list it — the app just draws nothing, on a branch
# where drawing nothing and drawing a very subtle grain look identical.
#
# Art/Vectors and Art/Reference are deliberately not copied: SVG sources are
# compiled to Swift paths ahead of time, and reference material is for us.
#
# The sources are 4096px colour PNGs at ~10MB each — 31MB against an app that
# was under 1MB. What ships is derived: downsampled, greyscale, JPEG.
#
# Greyscale because the textures are neutral by design and the colour channels
# carry nothing. JPEG because photographic grain is precisely what PNG is worst
# at, and because the loss it adds is far below the loss the downsample already
# costs — measured at 0.88 levels of error against 0.81 for lossless at the same
# size, on a surface multiplied at 50%. A fifth of the size for no visible
# difference.
#
# Cached on modification time: converting three 4096px photographs takes long
# enough to be irritating on every rebuild, and these change rarely.
if [ -d Art/Textures ] && [ -n "$(ls -A Art/Textures/*.png 2>/dev/null)" ]; then
  mkdir -p .texcache "$APP/Contents/Resources/Textures"
  for src in Art/Textures/*.png; do
    base=$(basename "$src" .png)
    out=".texcache/$base.jpg"
    if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
      # Only the sticky gets a native-resolution *crop*. It is ~170pt across, so
      # squeezing a whole 2048px sheet into it shrinks the grain twelvefold and
      # the paper reads as flat colour — which is exactly what it did. A crop
      # keeps the pixels at their own size, so the stamp shows a window onto the
      # stock rather than a miniature of it.
      #
      # Everything else takes the whole photograph, downsampled, because it is
      # drawn to cover. The panels went the other way first and came out
      # blotchy: a crop carries the photograph's large-scale mottling at full
      # size, and dropping that into a 260pt panel puts a visible streak across
      # it. Scaling the whole sheet down averages that away and leaves even
      # tooth — measured, it is the difference between a grain spread of 0.122
      # and 0.086, against 0.085 in the system.
      case "$base" in
        sticky) sips -c 1367 2048 -s format jpeg -s formatOptions 80 \
                  --matchTo '/System/Library/ColorSync/Profiles/Generic Gray Profile.icc' \
                  "$src" --out "$out" > /dev/null 2>&1 ;;
        *)      sips -Z 2048 -s format jpeg -s formatOptions 80 \
                  --matchTo '/System/Library/ColorSync/Profiles/Generic Gray Profile.icc' \
                  "$src" --out "$out" > /dev/null 2>&1 ;;
      esac
      echo "Textures: rebuilt $base.jpg"
    fi
    cp "$out" "$APP/Contents/Resources/Textures/$base.jpg"
  done
  echo "Textures: shipped $(ls -1 "$APP/Contents/Resources/Textures" | wc -l | tr -d ' ') ($(du -sh "$APP/Contents/Resources/Textures" | cut -f1))"
fi

# Flourish animation: 30 frames of a stop-motion draw-on, split out of one
# animated SVG and rasterised here.
#
# The export stacks all 30 frames in a single file and reveals them in turn with
# CSS @keyframes on opacity. Nothing in AppKit runs that — no SMIL, no CSS
# animation, no clock — so rendering the file as it stands draws every frame at
# once. Each frame is lifted into its own document first, then drawn.
#
# Raster, unusually for this branch. The artwork is a single tone, so a template
# image tinted at draw time still follows the theme, which is the property that
# made vectors worth the trouble elsewhere. What vectors would cost here is
# reimplementing SVG mask semantics — the later frames are drawn by masking a
# full-bleed rect, so the mask carries the shape — and letting the renderer
# resolve that is exact rather than nearly right. 30 frames come to under 300KB.
#
# Cached on the source's modification time; splitting and rendering 30 frames is
# slow enough to notice on every build.
ANIM="Art/Vectors/FlourishAnimation.svg"
if [ -f "$ANIM" ]; then
  if [ ! -f .animcache/corner/frame-30.png ] || [ "$ANIM" -nt .animcache/corner/frame-30.png ]; then
    rm -rf .animcache && mkdir -p .animcache/svg .animcache/corner .animcache/sticky
    python3 Art/split-frames.py "$ANIM" .animcache/svg > /dev/null
    # Two sets from one source. The corner mark is upright; the sticky carries
    # the same drawing rotated, at the angle its static artwork was baked with —
    # so animating it changes nothing about how it looks, it only lets it draw
    # itself on. (There was a third, for folder tiles, rotated 134.07°; the
    # tiles carry no flourish now.)
    swift Art/render-frames.swift .animcache/svg .animcache/corner 405 0
    swift Art/render-frames.swift .animcache/svg .animcache/sticky 405 147.88
  fi
  for set in corner sticky; do
    mkdir -p "$APP/Contents/Resources/FlourishFrames/$set"
    cp .animcache/$set/frame-*.png "$APP/Contents/Resources/FlourishFrames/$set/"
  done
  echo "Flourish: shipped 2 x $(ls -1 .animcache/corner/frame-*.png | wc -l | tr -d ' ') frames ($(du -sh "$APP/Contents/Resources/FlourishFrames" | cut -f1))"
fi

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 \
    -target "$arch-apple-macos$DEPLOY_TARGET" \
    main.swift Theme.swift Texture.swift Onboarding.swift Crumple.swift -o "/tmp/jui-$arch"
done
lipo -create /tmp/jui-arm64 /tmp/jui-x86_64 -output "$APP/Contents/MacOS/$NAME"
rm -f /tmp/jui-arm64 /tmp/jui-x86_64

# The Dock tile plug-in (DockTile.swift): draws the mood's icon in the Dock
# while the app isn't running, so a pinned tile keeps up with the mood without
# the Dock being restarted. A loadable bundle, not a dylib — hence
# `-Xlinker -bundle` — named by NSDockTilePlugIn in Info.plist.
PLUGIN="$APP/Contents/PlugIns/JUIDockTile.docktileplugin"
mkdir -p "$PLUGIN/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 \
    -target "$arch-apple-macos$DEPLOY_TARGET" -module-name JUIDockTile \
    -emit-library -Xlinker -bundle DockTile.swift -o "/tmp/jui-docktile-$arch"
done
lipo -create /tmp/jui-docktile-arm64 /tmp/jui-docktile-x86_64 \
  -output "$PLUGIN/Contents/MacOS/JUIDockTile"
rm -f /tmp/jui-docktile-arm64 /tmp/jui-docktile-x86_64
cat > "$PLUGIN/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>JUIDockTile</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID.docktile</string>
	<key>CFBundleName</key><string>JUIDockTile</string>
	<key>CFBundlePackageType</key><string>BNDL</string>
	<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
	<key>NSPrincipalClass</key><string>JUIDockTilePlugIn</string>
</dict>
</plist>
PLIST

# Extended attributes from downloaded/rendered assets make codesign fail; clear
# them first, and let a signing failure stop the build rather than shipping an
# unsigned bundle. Nested code is signed first, then the app around it.
xattr -cr "$APP"
codesign --force --sign - "$PLUGIN"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Ship the zip from here rather than by hand, so it can never go stale against
# the bundle it's named after.
#
# --norsrc --noextattr are load-bearing. The assets carry a com.apple.macl
# xattr that `xattr -cr` above cannot remove (the kernel owns it), and a plain
# `ditto -c -k` would archive an AppleDouble "._" companion for every such
# file. Extracted with anything other than Finder those land *inside* the
# bundle as real files that aren't in the code seal, and the app then dies with
# "a sealed resource is missing or invalid" — a launch failure that looks
# nothing like its cause. Stripping them keeps the archive byte-clean.
rm -f "$ZIP"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ZIP"

echo "Built $APP build $BUILD_NUMBER ($(lipo -archs "$APP/Contents/MacOS/$NAME"), macOS $DEPLOY_TARGET+, signature verified)"
echo "Packaged $ZIP ($(du -h "$ZIP" | cut -f1)) — on the receiving Mac: xattr -cr $APP"

# --- stage a copy outside ~/Documents ----------------------------------------
# Run the staged copy, not the one that was just built here.
#
# This repo lives inside ~/Documents, which macOS protects with TCC, and the
# bundle's own resources — every texture and PNG — are therefore files in a
# protected folder. Launching the app reads them, so macOS asks permission.
#
# Normally that is a one-time question: macOS exempts an app for its own bundle
# and remembers the answer. Both depend on a stable code-signing identity, and
# an ad-hoc signature has none — `codesign --sign -` leaves Signature=adhoc with
# TeamIdentifier not set, and this script re-signs from scratch on every build,
# so the identity differs each time. The approval has nothing durable to attach
# to, and the prompt comes back on every single launch.
#
# Notarised distribution would fix it properly. Until then the cheap fix is to
# not run it from a protected folder: verified, the same bundle launched from
# here never asks. The zip and the bundle in the repo are untouched, so what
# ships is unchanged.
STAGE="$HOME/Library/Application Support/$NAME-dev"
rm -rf "$STAGE/$APP"
mkdir -p "$STAGE"
ditto --norsrc --noextattr "$APP" "$STAGE/$APP"
codesign --verify --deep --strict "$STAGE/$APP"
echo "Staged $STAGE/$APP"
echo "  run that one: open \"$STAGE/$APP\""

# --- back up to GitHub -------------------------------------------------------
# Records every build and pushes it, so the source is never only on this Mac.
#
# Nothing here may fail the build: `set -e` is off for this block deliberately.
# A build with no network, or before `gh auth login` has been run, still
# succeeds — it just says so and leaves the work committed locally, ready to go
# up next time. Build products are gitignored, so only source is pushed.
set +e
if git rev-parse --git-dir > /dev/null 2>&1; then
  if [ -z "$(git remote get-url origin 2>/dev/null)" ]; then
    echo "GitHub: no remote set up yet — skipping."
  else
    if [ -n "$(git status --porcelain)" ]; then
      git add -A
      CHANGED=$(git diff --cached --name-only | sed 's/^/  /')
      git commit -q -m "Build $BUILD_NUMBER" -m "Files changed:
$CHANGED"
      echo "GitHub: committed build $BUILD_NUMBER."
    fi
    if [ -n "$(git log origin/$(git branch --show-current)..HEAD 2>/dev/null)" ] \
       || ! git rev-parse --verify --quiet "origin/$(git branch --show-current)" > /dev/null; then
      if git push -q -u origin "$(git branch --show-current)" 2>/dev/null; then
        echo "GitHub: pushed to $(git remote get-url origin)"
      else
        echo "GitHub: push failed — offline, or sign in first with: gh auth login"
        echo "        Your work is committed locally and will go up on the next build."
      fi
    else
      echo "GitHub: already up to date."
    fi
  fi
fi
set -e
