#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
swift build -c release
mkdir -p dist/MyGit.app/Contents/MacOS
cp .build/release/MyGit dist/MyGit.app/Contents/MacOS/MyGit
cp Resources/Info.plist dist/MyGit.app/Contents/Info.plist
codesign --force --sign - dist/MyGit.app
echo "Built: $PWD/dist/MyGit.app"
