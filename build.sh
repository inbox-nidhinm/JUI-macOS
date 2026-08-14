#!/bin/zsh
# Builds JUI.app next to this script.
#
# Universal (Apple Silicon + Intel) with a macOS 13 floor, so the zip opens on
# any reasonably recent Mac. An arm64-only or macOS-14-only build fails to
# launch elsewhere with a bare "the file cannot be opened", which looks like a
# signing problem but isn't.
set -e
cd "$(dirname "$0")"

# --- identity ----------------------------------------------------------------
# Everything that makes this a distinct app from the shipping JUI lives in these
# three lines, and nowhere else. The re-JUI branch is a look rebuild: it has to
# be installable and runnable *beside* the real app without touching its notes,
# its settings or its Dock tile, so it gets its own name, its own bundle id
# (hence its own UserDefaults domain and — via CFBundleName — its own vault),
# and its own build counter so the two branches never fight over one number.
#
# Merging this branch back into main means restoring these three values. That is
# the whole revert, which is why they are hoisted here rather than committed
# into Info.plist.
NAME="re-JUI"
BUNDLE_ID="com.nidhin.jui.re"
COUNTER="build-number-re"
ICON="AppIconRe.icns" # copied in as AppIcon.icns; main ships plain AppIcon.icns

APP="$NAME.app"
ZIP="$NAME.zip"
DEPLOY_TARGET="13"

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
# folder from it, so this is also what keeps this build's notes out of JUI's.
for key in CFBundleName CFBundleDisplayName CFBundleExecutable; do
  /usr/libexec/PlistBuddy -c "Set :$key $NAME" "$APP/Contents/Info.plist" > /dev/null
done
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" \
  "$APP/Contents/Info.plist" > /dev/null
for asset in Flourish.png StickyFlower.png FolderSprig.png OnboardingLogo.png; do
  [ -f "$asset" ] && cp "$asset" "$APP/Contents/Resources/$asset"
done

# The icon is copied separately because this branch ships a different one. It
# still lands as AppIcon.icns, which is what CFBundleIconFile in Info.plist
# names — so the source plist stays describing the real app here too.
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# Textures ship as a directory rather than by name. The rebuild adds and drops
# these constantly, and the old per-asset loop above fails silently when someone
# adds a file and forgets to list it — the app just draws nothing, on a branch
# where drawing nothing and drawing a very subtle grain look identical.
#
# Art/Vectors and Art/Reference are deliberately not copied: SVG sources are
# compiled to Swift paths ahead of time, and reference material is for us.
if [ -d Art/Textures ] && [ -n "$(ls -A Art/Textures 2>/dev/null)" ]; then
  mkdir -p "$APP/Contents/Resources/Textures"
  cp Art/Textures/*.png "$APP/Contents/Resources/Textures/" 2>/dev/null
  echo "Textures: shipped $(ls -1 Art/Textures/*.png 2>/dev/null | wc -l | tr -d ' ')"
fi

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 \
    -target "$arch-apple-macos$DEPLOY_TARGET" \
    main.swift Theme.swift Onboarding.swift -o "/tmp/jui-$arch"
done
lipo -create /tmp/jui-arm64 /tmp/jui-x86_64 -output "$APP/Contents/MacOS/$NAME"
rm -f /tmp/jui-arm64 /tmp/jui-x86_64

# Extended attributes from downloaded/rendered assets make codesign fail; clear
# them first, and let a signing failure stop the build rather than shipping an
# unsigned bundle.
xattr -cr "$APP"
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
