#!/bin/sh
# Full seven-region structural scan plus required high-error map screenshots.
# Usage: audit-with-hotspots.sh <RailMap.app> <output-dir> [simulator-udid]
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
app=${1:?usage: audit-with-hotspots.sh <RailMap.app> <output-dir> [simulator-udid]}
output=${2:?usage: audit-with-hotspots.sh <RailMap.app> <output-dir> [simulator-udid]}
device=${3:-}

mkdir -p "$output"
audit_status=0
python3 "$repo/.claude/skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py" \
    --repo "$repo" \
    --countries jp,tw,hk,mo,kr,us,ca \
    --json "$output/audit.json" \
    --limit 250 \
    >"$output/audit.txt" 2>&1 || audit_status=$?

if [ -n "$device" ]; then
    "$repo/ios/tools/capture-railway-hotspots.sh" \
        "$app" "$output/screenshots" "$device"
else
    "$repo/ios/tools/capture-railway-hotspots.sh" \
        "$app" "$output/screenshots"
fi

echo "railway audit and hotspot screenshots written to $output"
if [ "$audit_status" -ne 0 ]; then
    echo "railway structural audit reported findings (exit $audit_status); screenshots were still captured" >&2
    exit "$audit_status"
fi
