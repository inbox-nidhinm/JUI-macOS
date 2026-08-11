#!/bin/zsh
# Builds JUI.app next to this script.
#
# Universal (Apple Silicon + Intel) with a macOS 13 floor, so the zip opens on
# any reasonably recent Mac. An arm64-only or macOS-14-only build fails to
# launch elsewhere with a bare "the file cannot be opened", which looks like a
# signing problem but isn't.
set -e
cd "$(dirname "$0")"

APP="JUI.app"
DEPLOY_TARGET="13"

rm -rf "$APP" # start clean so no stale resource breaks the signature seal
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

# Every build gets its own CFBundleVersion, so two builds are never
# indistinguishable when one works and the other doesn't. The user-facing
# CFBundleShortVersionString in Info.plist is left alone. Stamped before signing:
# editing Info.plist afterwards would break the signature seal.
BUILD_NUMBER=$(( $(cat build-number 2>/dev/null || echo 0) + 1 ))
echo "$BUILD_NUMBER" > build-number
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
  "$APP/Contents/Info.plist" > /dev/null
for asset in AppIcon.icns Flourish.png StickyFlower.png FolderSprig.png OnboardingLogo.png; do
  [ -f "$asset" ] && cp "$asset" "$APP/Contents/Resources/$asset"
done

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 \
    -target "$arch-apple-macos$DEPLOY_TARGET" \
    main.swift Theme.swift Onboarding.swift -o "/tmp/jui-$arch"
done
lipo -create /tmp/jui-arm64 /tmp/jui-x86_64 -output "$APP/Contents/MacOS/JUI"
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
rm -f JUI.zip
ditto -c -k --keepParent --norsrc --noextattr "$APP" JUI.zip

echo "Built $APP build $BUILD_NUMBER ($(lipo -archs "$APP/Contents/MacOS/JUI"), macOS $DEPLOY_TARGET+, signature verified)"
echo "Packaged JUI.zip ($(du -h JUI.zip | cut -f1)) — on the receiving Mac: xattr -cr JUI.app"

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
