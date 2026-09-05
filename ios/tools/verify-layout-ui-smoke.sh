#!/bin/sh
# Focused simulator gate for the docked-card workspace on a wide iPad window.
# This intentionally runs one iPad path rather than the full UI suite; fast
# breakpoint coverage lives in RailPresentationTests and is already part of
# `verify.sh --core`.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
ios_root=$(cd "$here/.." && pwd)
tmp_root=${TMPDIR:-/tmp}
scratch=${SCRATCH:-${tmp_root%/}/railmap-layout-ui-smoke-$$}
devices_json=$(mktemp "${tmp_root%/}/railmap-layout-devices.XXXXXX")
trap 'rm -f "$devices_json"' EXIT

xcrun simctl list devices available --json >"$devices_json"
device_id=$(/usr/bin/python3 - "$devices_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    runtimes = json.load(source)["devices"]

devices = [
    device
    for runtime in runtimes.values()
    for device in runtime
    if device.get("isAvailable", False) and device.get("name", "").startswith("iPad")
]
devices.sort(key=lambda device: ("13-inch" not in device["name"], device["name"]))
if devices:
    print(devices[0]["udid"])
PY
)

if [ -z "$device_id" ]; then
    echo "FAIL: no available iPad simulator" >&2
    exit 1
fi

mkdir -p "$scratch"
cd "$ios_root"
result_bundle="$scratch/LayoutSmoke-$$.xcresult"
log="$scratch/LayoutSmoke-$$.log"
if ! xcodebuild \
        -project RailMap.xcodeproj \
        -scheme RailMap \
        -destination "platform=iOS Simulator,id=$device_id" \
        -derivedDataPath "$scratch/DerivedData" \
        -resultBundlePath "$result_bundle" \
        -only-testing:RailMapUITests/RailMapUITests/testWideIPadDocksThePhoneMenu \
        test >"$log" 2>&1
then
    tail -120 "$log"
    echo "FAIL: adaptive layout UI smoke test (result: $result_bundle)" >&2
    exit 1
fi

echo "adaptive layout UI smoke test passed"
