#!/usr/bin/env python3
"""Generate workloads and run the production core stress tests with bounded jobs.

Artifacts and reusable compiler caches stay in the ignored outputs directory.
This runner does not operate a simulator or change application/user data.
"""

import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=10000)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--configuration", choices=("debug", "release"), default="release")
    args = parser.parse_args()
    if args.count < 10000 or args.jobs < 1:
        parser.error("--count must be at least 10000 and --jobs must be positive")

    repository = Path(__file__).resolve().parents[2]
    root = repository / "outputs" / "route-stress-runner"
    root.mkdir(parents=True, exist_ok=True)
    lock = (root / "runner.lock").open("a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error("another route stress run owns this compiler cache")

    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    run = root / "runs" / stamp
    run.mkdir(parents=True)
    package = root / "package"
    (package / "Sources").mkdir(parents=True, exist_ok=True)
    tests = package / "Tests" / "RailCoreTests"
    tests.mkdir(parents=True, exist_ok=True)
    links = {
        package / "Sources" / "RailCore": repository / "ios/RailKit/Sources/RailCore",
        tests / "PortFixtures.swift": repository / "ios/RailKit/Tests/RailCoreTests/PortFixtures.swift",
        tests / "RouteStoreStressTests.swift": repository / "ios/RailKit/Tests/RailCoreTests/RouteStoreStressTests.swift",
    }
    for destination, source in links.items():
        if destination.is_symlink() and destination.resolve() == source:
            continue
        if destination.exists() or destination.is_symlink():
            parser.error(f"unexpected file at runner-owned path: {destination}")
        destination.symlink_to(source, target_is_directory=source.is_dir())
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RouteStress", platforms: [.macOS(.v14)], targets: [
    .target(name: "RailCore", resources: [.process("Resources")], linkerSettings: [.linkedLibrary("sqlite3")]),
    .testTarget(name: "RailCoreTests", dependencies: ["RailCore"])
])
''', encoding="utf-8")

    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(root / "swift-cache")
    environment["PYTHONPYCACHEPREFIX"] = str(root / "python-cache")
    environment["JTM_STRESS_TRAIN_COUNT"] = str(args.count)
    environment["JTM_STRESS_STORE_PATH"] = str(run / "varied/stress-all.json")
    environment["JTM_STRESS_PARTS_DIRECTORY"] = str(run / "varied")
    environment["JTM_STRESS_DENSE_STORE_PATH"] = str(run / "dense-collisions/stress-all.json")
    generator = repository / "ios/tools/generate-route-stress-data.py"
    steps = [
        ("generate-varied", [sys.executable, str(generator), "--count", str(args.count),
                             "--part-size", "2000", "--output-dir", str(run / "varied")]),
        ("generate-dense", [sys.executable, str(generator), "--count", str(args.count),
                            "--scenario", "dense", "--id-mode", "colliding", "--part-size", "2000",
                            "--output-dir", str(run / "dense-collisions")]),
        ("core-tests", ["swift", "test", "--build-system", "native", "--disable-sandbox",
                        "--jobs", str(args.jobs), "--configuration", args.configuration,
                        "--package-path", str(package), "--scratch-path", str(root / "build"),
                        "--cache-path", str(root / "spm-cache"), "--filter", "RouteStoreStressTests"]),
    ]
    report = {"complete": False, "passed": False, "count": args.count,
              "configuration": args.configuration, "simulator_tests": "not run", "steps": []}
    summary = run / "summary.json"
    summary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for name, command in steps:
        log = run / f"{name}.log"
        print(f"{name}: {log}", flush=True)
        started = time.monotonic()
        with log.open("w", encoding="utf-8") as output:
            result = subprocess.run(command, cwd=repository, env=environment,
                                    stdout=output, stderr=subprocess.STDOUT)
        report["steps"].append({"name": name, "command": command, "exit_code": result.returncode,
                                "seconds": time.monotonic() - started, "log": str(log)})
        if result.returncode:
            report["complete"] = True
            summary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
            print(f"FAILED: {summary}", file=sys.stderr)
            return result.returncode
        summary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    report.update(complete=True, passed=True)
    summary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"PASS (core only): {summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
