#!/bin/sh
# Build Cybermove and assemble a real macOS app bundle: build/Cybermove.app
#
#   scripts/make-app.sh            release build, universal (arm64 and x86_64)
#   scripts/make-app.sh debug      debug build
#   scripts/make-app.sh --native   only for this Mac's CPU (faster to build)
#   scripts/make-app.sh --open     also launch it afterwards
#
# The bundle gets a stable identifier (so the stored settings have a fixed
# home), the icon, and an ad-hoc signature. It is meant for running on this
# Mac. Distributing it to others would need a Developer ID signature and
# notarization.

set -eu
cd "$(dirname "$0")/.."

configuration=release
open_after=no
architectures="--arch arm64 --arch x86_64"
for argument in "$@"; do
    case "$argument" in
        debug) configuration=debug ;;
        release) configuration=release ;;
        --native) architectures="" ;;
        --open) open_after=yes ;;
        *) echo "usage: $0 [debug|release] [--native] [--open]" >&2; exit 2 ;;
    esac
done

identifier="io.github.zrhbert.Cybermove"
version="0.2.0"
app="build/Cybermove.app"

# shellcheck disable=SC2086   # $architectures is deliberately word-split
swift build -c "$configuration" $architectures --product Cybermove
binary="$(swift build -c "$configuration" $architectures --show-bin-path)/Cybermove"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Cybermove"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Cybermove</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$identifier</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Cybermove</string>
    <key>CFBundleDisplayName</key><string>Cybermove</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$app/Contents/Info.plist" >/dev/null
codesign --force --sign - "$app" >/dev/null 2>&1
codesign --verify --strict "$app"

echo "built $app ($configuration, $identifier, $(lipo -archs "$app/Contents/MacOS/Cybermove"))"
if [ "$open_after" = yes ]; then open "$app"; fi
