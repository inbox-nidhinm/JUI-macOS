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
    main.swift Onboarding.swift -o "/tmp/jui-$arch"
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
# the bundle it's named after. ditto is Apple's archiver: unlike `zip` it
# preserves the signature and the executable bit exactly.
rm -f JUI.zip
ditto -c -k --keepParent "$APP" JUI.zip

echo "Built $APP build $BUILD_NUMBER ($(lipo -archs "$APP/Contents/MacOS/JUI"), macOS $DEPLOY_TARGET+, signature verified)"
echo "Packaged JUI.zip ($(du -h JUI.zip | cut -f1)) — on the receiving Mac: xattr -cr JUI.app"
