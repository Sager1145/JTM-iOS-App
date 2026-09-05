#!/bin/sh
# Capture every reviewed railway-error hotspot from a built RailMap app.
# Usage: capture-railway-hotspots.sh <RailMap.app> <output-dir> [simulator-udid]
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
app=${1:?usage: capture-railway-hotspots.sh <RailMap.app> <output-dir> [simulator-udid]}
output=${2:?usage: capture-railway-hotspots.sh <RailMap.app> <output-dir> [simulator-udid]}
device=${3:-}
hotspots="$repo/app/public/rail/audit-hotspots.json"
tmp_root=${TMPDIR:-/tmp}
devices_json=$(mktemp "${tmp_root%/}/railmap-hotspot-devices.XXXXXX")
rows=$(mktemp "${tmp_root%/}/railmap-hotspot-rows.XXXXXX")
trap 'rm -f "$devices_json" "$rows"' EXIT

if [ ! -d "$app" ] || [ ! -f "$app/Info.plist" ]; then
    echo "FAIL: RailMap app bundle not found: $app" >&2
    exit 1
fi
if [ ! -f "$hotspots" ]; then
    echo "FAIL: hotspot registry not found: $hotspots" >&2
    exit 1
fi

xcrun simctl list devices available --json >"$devices_json"
if [ -z "$device" ]; then
    device=$(/usr/bin/python3 - "$devices_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    runtimes = json.load(source)["devices"]
devices = [
    device
    for runtime in runtimes.values()
    for device in runtime
    if device.get("isAvailable", False)
    and device.get("name", "").startswith("iPhone")
]
booted = [device for device in devices if device.get("state") == "Booted"]
candidates = booted or devices
candidates.sort(key=lambda device: (device.get("name") != "iPhone 17", device["name"]))
if candidates:
    print(candidates[0]["udid"])
PY
    )
fi
if [ -z "$device" ]; then
    echo "FAIL: no available iPhone simulator" >&2
    exit 1
fi

state=$(/usr/bin/python3 - "$devices_json" "$device" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    runtimes = json.load(source)["devices"]
for runtime in runtimes.values():
    for device in runtime:
        if device.get("udid") == sys.argv[2]:
            print(device.get("state", ""))
            raise SystemExit
PY
)
if [ "$state" != "Booted" ]; then
    xcrun simctl boot "$device"
    xcrun simctl bootstatus "$device" -b
fi

/usr/bin/python3 - "$hotspots" >"$rows" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    payload = json.load(source)
if payload.get("format") != "jtm-railway-audit-hotspots-v1":
    raise SystemExit("unsupported railway hotspot registry")
for row in payload.get("hotspots") or []:
    slug = str(row.get("id") or "")
    camera = row.get("camera") or []
    if not re.fullmatch(r"[a-z0-9-]+", slug) or len(camera) != 3:
        raise SystemExit(f"invalid railway hotspot: {row!r}")
    print(slug, ",".join(str(value) for value in camera), sep="\t")
PY

mkdir -p "$output"
cp "$hotspots" "$output/audit-hotspots.json"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
xcrun simctl install "$device" "$app"

expected=0
captured=0
minimum_bytes=${RAILMAP_SCREENSHOT_MINIMUM_BYTES:-300000}
while IFS="	" read -r slug camera; do
    [ -n "$slug" ] || continue
    expected=$((expected + 1))
    screenshot="$output/$slug.png"
    attempt=1
    screenshot_bytes=0
    while [ "$attempt" -le 2 ]; do
        # Keep the audit target visible. The medium sheet covers the camera
        # centre on phones, which can make a valid capture look empty.
        SIMCTL_CHILD_RAILMAP_UI_TEST_TAB=all \
        SIMCTL_CHILD_RAILMAP_UI_TEST_STAGE=compact \
        SIMCTL_CHILD_RAILMAP_UI_TEST_LAYERS=network \
        SIMCTL_CHILD_RAILMAP_UI_TEST_CAMERA="$camera" \
            xcrun simctl launch --terminate-running-process "$device" "$bundle_id" >/dev/null
        # A cold bundle first indexes seven regional packages and then loads
        # the z10 tiles intersecting the requested camera. On current iPhone
        # simulators that can take about 45 seconds; an 18-second capture
        # recorded the empty MapKit grid before the rail overlays arrived.
        sleep "${RAILMAP_SCREENSHOT_WAIT_SECONDS:-55}"
        xcrun simctl io "$device" screenshot "$screenshot"
        sips --resampleHeightWidthMax 1800 "$screenshot" >/dev/null
        screenshot_bytes=$(wc -c <"$screenshot" | tr -d ' ')
        if [ "$screenshot_bytes" -ge "$minimum_bytes" ]; then
            break
        fi
        echo "retrying $slug: screenshot has only $screenshot_bytes bytes" >&2
        attempt=$((attempt + 1))
    done
    if [ "$screenshot_bytes" -lt "$minimum_bytes" ]; then
        echo "FAIL: low-information screenshot for $slug ($screenshot_bytes bytes)" >&2
        exit 1
    fi
    captured=$((captured + 1))
    echo "captured $slug ($screenshot_bytes bytes)"
done <"$rows"

if [ "$captured" -ne "$expected" ] || [ "$captured" -eq 0 ]; then
    echo "FAIL: captured $captured of $expected railway hotspots" >&2
    exit 1
fi
echo "captured $captured railway audit hotspots in $output"
