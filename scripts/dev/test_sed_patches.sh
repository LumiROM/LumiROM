#!/bin/bash
#
# Applies every sed patch shipped in LumiROM/Mods to a synthetic target.
#
# The patch files put a sed instruction on the first line (`/x/i`, `/x/a`,
# `/x/c`) and the text on the rest. A malformed expression only fails when the
# build reaches that mod, so this catches format regressions in the Lint
# workflow instead of 40 minutes into a ROM build.

set -eo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source scripts/features/AppPatches.sh

TARGET_SEED='<root>
<application>
<TopLevelAdvancedFeatures/>
</root>
'

count=0
failed=0

while IFS= read -r -d '' patch; do
    instruction="$(head -n 1 "$patch")"
    case "$instruction" in
        */i|*/a|*/c) ;;
        *) continue ;;
    esac

    target="$(mktemp)"
    printf '%s' "$TARGET_SEED" > "$target"

    if ! apps_apply_sed_patch "$patch" "$target" 2>/dev/null; then
        echo "FAIL: $patch"
        failed=1
    fi
    rm -f "$target"
    count=$((count + 1))
done < <(find LumiROM/Mods -name '*.xml' -type f -print0)

if [ "$count" -eq 0 ]; then
    echo "FAIL: no sed patches found (did the format change?)" >&2
    exit 1
fi

[ "$failed" -eq 0 ] || exit 1
echo "OK: $count sed patches apply cleanly"
