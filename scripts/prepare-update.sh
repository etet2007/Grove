#!/bin/zsh
# Prepare files only. Review and push the destination repository yourself.
set -euo pipefail
cd "${0:A:h:h}"
if (( $# < 2 || $# > 4 )); then
    echo 'Usage: zsh scripts/prepare-update.sh VERSION BUILD [OUTPUT_DIRECTORY] [RELEASE_NOTES]'
    exit 1
fi
export GROVE_VERSION="$1"
export GROVE_BUILD="$2"
if [[ ! "$GROVE_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$GROVE_BUILD" =~ '^[1-9][0-9]*$' ]]; then
    echo 'VERSION must be x.y.z; BUILD must be a positive, increasing integer.'
    exit 1
fi
update_output="${3:-$PWD/dist/update}"
export GROVE_RELEASE_NOTES="${4:-}"
zsh scripts/build-app.sh
mkdir -p "$update_output"
update_output="${update_output:A}"
# Grove currently has no embedded frameworks; reject symlinks in this simple format.
if [[ -n "$(find dist/Grove.app -type l -print -quit)" ]]; then
    echo 'Update packages must not contain symlinks.'
    exit 1
fi
rm -f "$update_output/Grove.zip"
/usr/bin/ditto -c -k --keepParent dist/Grove.app "$update_output/Grove.zip"
python3 - "$update_output" <<'PY'
import hashlib, json, os, pathlib, sys
root = pathlib.Path(sys.argv[1])
manifest = dict(version=os.environ['GROVE_VERSION'], build=int(os.environ['GROVE_BUILD']),
                sha256=hashlib.sha256((root/'Grove.zip').read_bytes()).hexdigest(),
                notes=os.environ['GROVE_RELEASE_NOTES'])
(root/'latest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
PY
codesign --verify --strict dist/Grove.app
echo "Ready: $update_output/latest.json and $update_output/Grove.zip"
echo 'Commit and push both files together to your update repository. No Git changes were made by this script.'
