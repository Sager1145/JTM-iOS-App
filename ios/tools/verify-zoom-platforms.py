#!/usr/bin/env python3
"""Run railway zoom regressions serially on explicitly selected iOS simulators.

Example: python3 ios/tools/verify-zoom-platforms.py --device <UDID> --device <UDID>
Use distinct, idle simulators; another task must not launch this app on them.
Device selection is explicit so this does not claim coverage of missing runtimes.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


SMOKE_TESTS = (
    "testAllRailwaysRepeatedZoomAcrossJapanDefersRebuildsUntilSettle",
    "testDenseHobokenNewportParallelBranchesRemainVisibleAcrossZoom",
    "testDenseBundleRemainsVisibleAfterRotation",
    "testOrangeBendRemainsVisibleInLandscape",
    "testTwoFingerMapRotationThenZoomDefersGeometryBuilds",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", action="append", required=True, help="available simulator UDID; repeat for a matrix")
    parser.add_argument("--full", action="store_true", help="run every MapZoomPerformanceTests case")
    parser.add_argument("--skip-build", action="store_true", help="reuse an up-to-date build-for-testing in --derived-data")
    parser.add_argument("--derived-data", type=Path, default=Path(tempfile.gettempdir()) / "jtm-platform-sim")
    parser.add_argument("--output", type=Path, help="new directory for logs, xcresults and summary.json")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    env = dict(os.environ)
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode-beta.app/Contents/Developer")
    inventory = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"], env=env, text=True))
    available = {device["udid"]: {"name": device["name"], "runtime": runtime}
                 for runtime, devices in inventory["devices"].items() for device in devices}
    devices = list(dict.fromkeys(args.device))
    for identifier in devices:
        if identifier not in available:
            parser.error(f"simulator is unavailable: {identifier}")
    if args.skip_build and not any((args.derived_data / "Build/Products").glob("*.xctestrun")):
        parser.error(f"no prepared test build in {args.derived_data}; specify --derived-data or omit --skip-build")
    output = args.output or Path(tempfile.mkdtemp(prefix="jtm-zoom-platforms-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    results = []
    summary = {"startedAt": datetime.now(timezone.utc).isoformat(), "results": results,
               "scope": "Selected simulator runtimes and device sizes; not physical-device frame presentation."}
    for index, identifier in enumerate(devices):
        device = available[identifier]
        print(f"Testing {device['name']} / {device['runtime']}", flush=True)
        log = output / f"{identifier}.log"
        bundle = output / f"{identifier}.xcresult"
        command = [
            "xcodebuild", "-project", str(repo / "ios/RailMap.xcodeproj"),
            "-scheme", "RailMap Debug", "-configuration", "Debug",
            "-destination", f"platform=iOS Simulator,id={identifier}",
            "-derivedDataPath", str(args.derived_data), "-resultBundlePath", str(bundle),
            "-parallel-testing-enabled", "NO",
            # Keep assertion logs/screenshots, but don't let a failed case
            # start a system-wide diagnostic collector during the next pinch.
            "-collect-test-diagnostics", "never",
        ]
        selection = ["RailMapUITests/MapZoomPerformanceTests"] if args.full else [
            f"RailMapUITests/MapZoomPerformanceTests/{name}" for name in SMOKE_TESTS]
        command.extend(f"-only-testing:{name}" for name in selection)
        command.append("test" if index == 0 and not args.skip_build else "test-without-building")
        with log.open("w") as stream:
            completed = subprocess.run(command, cwd=repo, env=env, stdout=stream, stderr=subprocess.STDOUT)
        text = log.read_text(errors="replace")
        results.append({
            "udid": identifier, **device, "passed": completed.returncode == 0,
            "exitCode": completed.returncode, "log": str(log), "xcresult": str(bundle),
            "selectedTests": selection,
            "passedCases": len(re.findall(r"Test Case .* passed \(", text)),
            "settledSnapshots": re.findall(r"^\[[^\n]*05-settled\] (.+)$", text, re.MULTILINE),
        })
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"{'PASS' if completed.returncode == 0 else 'FAIL'} {device['name']}: {log}", flush=True)
    print(f"Results: {output / 'summary.json'}", flush=True)
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
