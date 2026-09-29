#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
signing_identity="${MYGIT_SIGNING_IDENTITY:-MyGit Local Code Signing}"

if ! security find-identity -v -p codesigning | grep -Fq "\"$signing_identity\""; then
    echo "No valid code signing identity named '$signing_identity' was found in Keychain." >&2
    echo "Set MYGIT_SIGNING_IDENTITY to an installed code signing certificate name." >&2
    exit 1
fi

swift build -c release
mkdir -p dist/MyGit.app/Contents/MacOS
mkdir -p dist/MyGit.app/Contents/Resources
cp .build/release/MyGit dist/MyGit.app/Contents/MacOS/MyGit
cp Resources/Info.plist dist/MyGit.app/Contents/Info.plist
cp Resources/MyGitIcon.icns dist/MyGit.app/Contents/Resources/MyGitIcon.icns
codesign --force --sign "$signing_identity" dist/MyGit.app
echo "Built: $PWD/dist/MyGit.app"
