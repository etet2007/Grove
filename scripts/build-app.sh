#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
# Preserve existing local signing setups after the product rename.
signing_identity="${GROVE_SIGNING_IDENTITY:-${MYGIT_SIGNING_IDENTITY:-MyGit Local Code Signing}}"
grove_version="${GROVE_VERSION:-${MYGIT_VERSION:-}}"
grove_build="${GROVE_BUILD:-${MYGIT_BUILD:-}}"

if ! security find-identity -v -p codesigning | grep -Fq "\"$signing_identity\""; then
    echo "No valid code signing identity named '$signing_identity' was found in Keychain." >&2
    echo "Set GROVE_SIGNING_IDENTITY to an installed code signing certificate name." >&2
    exit 1
fi

swift build -c release
mkdir -p dist/Grove.app/Contents/MacOS
mkdir -p dist/Grove.app/Contents/Resources
cp .build/release/Grove dist/Grove.app/Contents/MacOS/Grove
cp Resources/Info.plist dist/Grove.app/Contents/Info.plist
if [[ -n "$grove_version" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $grove_version" dist/Grove.app/Contents/Info.plist
fi
if [[ -n "$grove_build" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $grove_build" dist/Grove.app/Contents/Info.plist
fi
cp scripts/install-update.sh dist/Grove.app/Contents/Resources/install-update.sh
cp Resources/GroveIcon.icns dist/Grove.app/Contents/Resources/GroveIcon.icns
cp Resources/ThirdPartyNotices.txt dist/Grove.app/Contents/Resources/ThirdPartyNotices.txt
rm -rf dist/Grove.app/Contents/Resources/Grove_Grove.bundle
cp -R .build/release/Grove_Grove.bundle dist/Grove.app/Contents/Resources/
swift scripts/render-system-app-icons.swift dist/Grove.app/Contents/Resources/Grove_Grove.bundle
swift scripts/verify-app-icons.swift dist/Grove.app
cp -R Resources/en.lproj Resources/zh-Hans.lproj dist/Grove.app/Contents/Resources/
# Sign nested code before the enclosing application. The Dock loads this plug-in
# to retain the selected icon after Grove quits.
plugin="dist/Grove.app/Contents/PlugIns/GroveDockTile.docktileplugin"
mkdir -p "$plugin/Contents/MacOS"
xcrun clang -bundle -fobjc-arc -mmacosx-version-min=14.0 -framework AppKit \
    Sources/GroveDockTile/GroveDockTilePlugin.m -o "$plugin/Contents/MacOS/GroveDockTile"
cp Resources/GroveDockTile-Info.plist "$plugin/Contents/Info.plist"
codesign --force --sign "$signing_identity" "$plugin"
codesign --force --sign "$signing_identity" dist/Grove.app
codesign --verify --deep --strict dist/Grove.app
echo "Built: $PWD/dist/Grove.app"
