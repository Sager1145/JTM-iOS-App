#!/usr/bin/env python3
"""Audit zoom-dependent straight chords in every shipped railway region.

The extractor calls production rail-network.js. The compiled Swift probe calls
production ContinuousStroke.buildStroke and Geometry.douglasPeuckerIndices.
Findings are review candidates: the detector measures visible skipped bends;
it does not assert that every chord is geographically wrong.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


REGIONS = ("jp", "tw", "hk", "mo", "kr", "us", "ca")
DEFAULT_ZOOMS = (10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0)


def run(command: list[str], *, cwd: Path, env: dict[str, str], stdout=None) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, env=env, stdout=stdout, check=True, text=stdout is None)


def compile_probe(repo: Path, output: Path, env: dict[str, str]) -> None:
    core = repo / "ios/RailKit/Sources/RailCore"
    run([
        "xcrun", "swiftc", "-O",
        str(core / "JSNumber.swift"),
        str(core / "Coordinates.swift"),
        str(core / "Geometry.swift"),
        str(core / "LaneLOD.swift"),
        str(core / "ContinuousStroke.swift"),
        str(repo / "ios/tools/audit-zoom-chords.swift"),
        "-o", str(output),
    ], cwd=repo, env=env)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regions", default=",".join(REGIONS), help="comma-separated shipped region codes")
    parser.add_argument("--zooms", default=",".join(str(int(z)) for z in DEFAULT_ZOOMS),
                        help="native/app zooms; projection uses the equivalent MapLibre zoom minus one")
    parser.add_argument("--json", type=Path, help="write the complete machine-readable report")
    parser.add_argument("--limit", type=int, default=30, help="maximum candidate locations printed")
    parser.add_argument("--legacy", action="store_true", help="use legacy non-strict ContinuousStroke mode")
    parser.add_argument("--check-orange", action="store_true",
                        help="fail if the Highland Avenue–Orange regression is present")
    parser.add_argument("--fail-on-candidates", action="store_true",
                        help="fail after reporting when any visible skipped-bend candidate remains")
    parser.add_argument("--fail-on-crossings", action="store_true",
                        help="also fail on warning-only newly introduced self-intersections")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    regions = tuple(value.strip() for value in args.regions.split(",") if value.strip())
    unknown = sorted(set(regions) - set(REGIONS))
    if unknown:
        raise SystemExit(f"unknown region(s): {', '.join(unknown)}")
    zooms = tuple(float(value) for value in args.zooms.split(",") if value.strip())
    if not zooms:
        raise SystemExit("--zooms must contain at least one value")
    if args.check_orange and "us" not in regions:
        raise SystemExit("--check-orange requires --regions to include us")

    env = dict(os.environ)
    developer = env.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    env["DEVELOPER_DIR"] = developer
    supplied_sdk = env.get("SDKROOT")
    if not supplied_sdk or not Path(supplied_sdk).exists() or (
        "CommandLineTools" in supplied_sdk and developer not in supplied_sdk
    ):
        lookup_env = dict(env)
        lookup_env.pop("SDKROOT", None)
        env["SDKROOT"] = subprocess.check_output(
            ["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=lookup_env, text=True
        ).strip()
    with tempfile.TemporaryDirectory(prefix="jtm-zoom-chords-") as held:
        scratch = Path(held)
        env["CLANG_MODULE_CACHE_PATH"] = str(scratch / "module-cache")
        env["SWIFT_MODULECACHE_PATH"] = str(scratch / "module-cache")
        probe = scratch / "audit-zoom-chords"
        compile_probe(repo, probe, env)
        reports = []
        orange_fine = None
        for region in regions:
            source = scratch / f"{region}-stroke-model.json"
            with source.open("w") as output:
                run(["node", str(repo / "ios/tools/audit-zoom-chords.mjs"), region],
                    cwd=repo, env=env, stdout=output)
            command = [str(probe), str(source), *(f"{zoom:g}" for zoom in zooms)]
            if args.legacy:
                command.append("--legacy")
            completed = subprocess.run(command, cwd=repo, env=env, check=True,
                                       stdout=subprocess.PIPE, text=True)
            reports.append(json.loads(completed.stdout))
            if args.check_orange and region == "us":
                fine_zooms = tuple(12 + step / 8 for step in range(33))
                fine_command = [str(probe), str(source), *(f"{zoom:g}" for zoom in fine_zooms),
                                "--line=new-jersey-transit-nj-transi-mneg"]
                if args.legacy:
                    fine_command.append("--legacy")
                fine = subprocess.run(fine_command, cwd=repo, env=env, check=True,
                                      stdout=subprocess.PIPE, text=True)
                orange_fine = json.loads(fine.stdout)

    candidates = [candidate for report in reports for candidate in report["candidates"]]
    candidates.sort(key=lambda row: (-row["excessPx"], row["region"], row["lineId"], row["appZoom"]))
    crossing_candidates = [candidate for held in reports for candidate in held["crossingCandidates"]]
    for row in crossing_candidates:
        if ("source_simplify" in row["stage"] or "noncontinuous_final" in row["stage"]) \
                and row["sourceSeparationPx"] <= 0.125:
            row["classification"] = "existing_source_touch_or_grade_separation"
        elif row["loopDiameterPx"] < 1:
            row["classification"] = "subpixel_footprint"
        else:
            row["classification"] = "visible_crossing_review"
    crossing_candidates.sort(key=lambda row: (row["region"], row["lineId"], row["appZoom"], row["firstMeasure"]))
    report = {
        "format": "jtm-zoom-chord-audit-v1",
        "mode": "legacy" if args.legacy else "production",
        "regions": reports,
        "candidateCount": len(candidates),
        "candidates": candidates,
        "crossingCandidateCount": len(crossing_candidates),
        "crossingCandidates": crossing_candidates,
        "orangeFineSweep": orange_fine,
        "interpretation": "Chord and newly introduced self-intersection candidates are review locations, not source-data verdicts.",
        "laneLOD": "Each zoom is a cold build (previousBucket=nil); camera-history hysteresis is not enumerated.",
    }
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    print("Zoom-chord audit (candidate threshold: edge ratio >= 2.5, excess > 1 px)")
    print("region version lines station-memberships continuous-parts plain-parts chords crossings")
    for held in reports:
        print(held["region"], held["version"], held["packageLineCount"],
              held["packageStationMembershipCount"], held["continuousPartCount"],
              held["plainPartCount"], len(held["candidates"]), len(held["crossingCandidates"]))
    print("\nregion zoom chords crossings")
    for held in reports:
        for zoom in held["zooms"]:
            count = sum(1 for row in held["candidates"] if row["appZoom"] == zoom)
            crossing_count = sum(1 for row in held["crossingCandidates"] if row["appZoom"] == zoom)
            print(held["region"], f"{zoom:g}", count, crossing_count)
    print("\nnonzero stage breakdown")
    counts: dict[tuple[str, float, str], int] = {}
    for row in candidates:
        key = (row["region"], row["appZoom"], row["stage"])
        counts[key] = counts.get(key, 0) + 1
    for key in sorted(counts):
        print(key[0], f"{key[1]:g}", key[2], counts[key])
    print(f"\nTop {min(args.limit, len(candidates))} of {len(candidates)} review candidates")
    for row in candidates[:args.limit]:
        print(
            f'{row["region"]} z{row["appZoom"]:g} {row["stage"]} '
            f'{row["lineId"]}#{row["partIndex"]} '
            f'm={row["fromMeasure"]:.1f}..{row["toMeasure"]:.1f} '
            f'excess={row["excessPx"]:.2f}px ratio={row["edgeRatio"]:.1f} '
            f'@ {row["latitude"]:.6f},{row["longitude"]:.6f}'
        )
    print(f"\nTop {min(args.limit, len(crossing_candidates))} of "
          f"{len(crossing_candidates)} new self-intersection candidates")
    for row in crossing_candidates[:args.limit]:
        print(
            f'{row["region"]} z{row["appZoom"]:g} {row["stage"]} '
            f'{row["lineId"]}#{row["partIndex"]} '
            f'm={row["firstMeasure"]:.1f}×{row["secondMeasure"]:.1f} '
            f'loop={row["loopDiameterPx"]:.2f}px source-gap={row["sourceSeparationPx"]:.2f}px '
            f'angle={row["intersectionAngleDegrees"]:.1f}° '
            f'class={row["classification"]} '
            f'@ {row["latitude"]:.6f},{row["longitude"]:.6f}'
        )

    if args.check_orange:
        if orange_fine is None or orange_fine["continuousBuilds"] == 0:
            print("ERROR Highland Avenue–Orange target line was not audited", file=sys.stderr)
            return 1
        orange = [row for row in orange_fine["candidates"]
                  if row["lineId"] == "new-jersey-transit-nj-transi-mneg"
                  and row["stage"] == "lane_offset_or_fold"
                  and row["fromMeasure"] < 19_000 < row["toMeasure"]]
        orange_crossings = orange_fine["crossingCandidates"]
        if orange or orange_crossings:
            print(f"ERROR Highland Avenue–Orange regression present: {len(orange)} chord(s), "
                  f"{len(orange_crossings)} new crossing(s)", file=sys.stderr)
            return 1
        print("PASS Highland Avenue–Orange focused regression "
              "(app z12..16 in 0.125 increments; 33 cold-build zooms)")
    if args.fail_on_candidates and candidates:
        print(f"ERROR {len(candidates)} zoom-chord candidate(s) remain", file=sys.stderr)
        return 1
    if args.fail_on_crossings and crossing_candidates:
        print(f"ERROR {len(crossing_candidates)} warning-only new self-intersection "
              "candidate(s) remain", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
