#!/bin/sh
# Simulator gates for the workspace's two materially different layouts.
#
# The default keeps the focused wide-iPad smoke used by CI. Passing `iphone`
# runs the phone workspace regression: editing, Search, list-detail return,
# map-layer controls, and the one-test console surface sweep. Both paths use
# one selected device and retain an xcresult plus the complete xcodebuild log.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
ios_root=$(cd "$here/.." && pwd)
tmp_root=${TMPDIR:-/tmp}
mode=${1:-ipad}

case "$mode" in
    ipad)
        device_family=iPad
        result_name=LayoutSmoke
        success_message="adaptive layout UI smoke test passed"
        set -- \
            -only-testing:RailMapUITests/RailMapUITests/testWideIPadDocksThePhoneMenu
        ;;
    iphone)
        device_family=iPhone
        result_name=WorkspaceRegression
        success_message="iPhone workspace UI regression passed"
        # ConsoleSweepTests is one phone-only walk and shares this invocation's
        # build, so its additional cost is small beside the map-layer suite.
        set -- \
            -only-testing:RailMapUITests/WorkspaceEditingTests \
            -only-testing:RailMapUITests/RailMapUITests/testSearchDestinationAlwaysExposesAField \
            -only-testing:RailMapUITests/RailMapUITests/testAllJourneyRowsOpenTheirMatchingJourney \
            -only-testing:RailMapUITests/RailMapUITests/testPhoneMenuHeaderDragsInBothDirectionsRepeatedly \
            -only-testing:RailMapUITests/RailMapUITests/testLandscapeUsesReachableSidebarChrome \
            -only-testing:RailMapUITests/MapLayerToggleTests \
            -only-testing:RailMapUITests/ConsoleSweepTests
        ;;
    *)
        echo "usage: $0 [ipad|iphone]" >&2
        exit 2
        ;;
esac

scratch=${SCRATCH:-${tmp_root%/}/railmap-${mode}-ui-smoke-$$}
devices_json=$(mktemp "${tmp_root%/}/railmap-layout-devices.XXXXXX")
trap 'rm -f "$devices_json"' EXIT

xcrun simctl list devices available --json >"$devices_json"
device_id=$(/usr/bin/python3 - "$devices_json" "$device_family" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    runtimes = json.load(source)["devices"]

family = sys.argv[2]
devices = [
    device
    for runtime in runtimes.values()
    for device in runtime
    if device.get("isAvailable", False) and device.get("name", "").startswith(family)
]
if family == "iPad":
    devices.sort(key=lambda device: ("13-inch" not in device["name"], device["name"]))
else:
    devices.sort(key=lambda device: (
        not device["name"].endswith(" Pro"),
        "Max" in device["name"],
        device["name"],
    ))
if devices:
    print(devices[0]["udid"])
PY
)

if [ -z "$device_id" ]; then
    echo "FAIL: no available $device_family simulator" >&2
    exit 1
fi

mkdir -p "$scratch"
cd "$ios_root"
result_bundle="$scratch/$result_name-$$.xcresult"
log="$scratch/$result_name-$$.log"
if ! xcodebuild \
        -project RailMap.xcodeproj \
        -scheme RailMap \
        -destination "platform=iOS Simulator,id=$device_id" \
        -derivedDataPath "$scratch/DerivedData" \
        -resultBundlePath "$result_bundle" \
        -parallel-testing-enabled NO \
        "$@" \
        test >"$log" 2>&1
then
    tail -120 "$log"
    echo "FAIL: $mode workspace UI test (result: $result_bundle)" >&2
    exit 1
fi

echo "$success_message"
