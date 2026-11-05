#!/bin/sh
# Invoked only after explicit confirmation and signature verification by Grove.
set -eu
parent_pid=$1
source_app=$2
target_app=$3
update_root=$4
log_dir=$5
mkdir -p "$log_dir"
exec >>"$log_dir/update.log" 2>&1
staging="${target_app}.update-$$"
backup="${target_app}.previous-$$"
swapped=0
finish() {
    result=$?
    if [ "$result" -ne 0 ]; then
        echo failure >"$log_dir/update-result"
        echo "Update failed ($result); restoring previous application."
        restored=0
        if [ "$swapped" -eq 1 ] && [ -d "$backup" ]; then
            rm -rf "$target_app"
            mv "$backup" "$target_app"
            restored=1
        elif [ ! -e "$target_app" ] && [ -d "$backup" ]; then
            mv "$backup" "$target_app"
            restored=1
        fi
        if [ "$restored" -eq 1 ]; then /usr/bin/open "$target_app" || true; fi
    fi
    rm -rf "$staging" "$update_root"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM
echo "$(date): Preparing update for $target_app"
# Never replace a running app. If quitting is cancelled, abandon after one minute.
count=0
while kill -0 "$parent_pid" 2>/dev/null; do
    count=$((count + 1))
    if [ "$count" -gt 60 ]; then echo "Application did not exit; update cancelled."; exit 1; fi
    sleep 1
done
/usr/bin/ditto "$source_app" "$staging"
/usr/bin/codesign --verify --deep --strict "$staging"
mv "$target_app" "$backup"
mv "$staging" "$target_app"
swapped=1
/usr/bin/open "$target_app"
rm -rf "$backup"
echo success >"$log_dir/update-result"
echo "$(date): Update installed successfully."
