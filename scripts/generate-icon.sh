#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
swift scripts/generate-icon.swift Resources/MyGitIcon.png
iconset=$(mktemp -d "${TMPDIR:-/tmp/}MyGitIcon.XXXXXX.iconset")
trap 'rm -rf "$iconset"' EXIT
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" Resources/MyGitIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -s format png -z "$doubled" "$doubled" Resources/MyGitIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/MyGitIcon.icns
