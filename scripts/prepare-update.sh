#!/bin/zsh
# Prepare files only. Review and push the destination repository yourself.
set -euo pipefail
cd "${0:A:h:h}"
if (( $# < 2 || $# > 4 )); then
    echo 'Usage: zsh scripts/prepare-update.sh VERSION BUILD [OUTPUT_DIRECTORY] [RELEASE_NOTES]'
    exit 1
fi
export MYGIT_VERSION="$1"
export MYGIT_BUILD="$2"
if [[ ! "$MYGIT_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$MYGIT_BUILD" =~ '^[1-9][0-9]*$' ]]; then
    echo 'VERSION must be x.y.z; BUILD must be a positive, increasing integer.'
    exit 1
fi
update_output="${3:-$PWD/dist/update}"
export MYGIT_RELEASE_NOTES="${4:-}"
zsh scripts/build-app.sh
mkdir -p "$update_output"
update_output="${update_output:A}"
# MyGit currently has no embedded frameworks; reject symlinks in this simple format.
if [[ -n "$(find dist/MyGit.app -type l -print -quit)" ]]; then
    echo 'Update packages must not contain symlinks.'
    exit 1
fi
rm -f "$update_output/MyGit.zip"
/usr/bin/ditto -c -k --keepParent dist/MyGit.app "$update_output/MyGit.zip"
python3 - "$update_output" <<'PY'
import hashlib, json, os, pathlib, sys
root = pathlib.Path(sys.argv[1])
manifest = dict(version=os.environ['MYGIT_VERSION'], build=int(os.environ['MYGIT_BUILD']),
                sha256=hashlib.sha256((root/'MyGit.zip').read_bytes()).hexdigest(),
                notes=os.environ['MYGIT_RELEASE_NOTES'])
(root/'latest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
PY
codesign --verify --strict dist/MyGit.app
echo "Ready: $update_output/latest.json and $update_output/MyGit.zip"
echo 'Commit and push both files together to your update repository. No Git changes were made by this script.'
