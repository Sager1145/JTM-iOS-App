#!/usr/bin/env python3
"""Offline acceptance of a predeclared paired five-real-region experiment.

Reads evidence only; never builds, launches, modifies a device, or fills missing
baseline samples. See --schema for the collection contract. Exit 0 means these
performance gates passed for the declared source/device/cache/workload only;
leaks, M, full-map stress, and overall refactor completion remain separate.
"""
import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import statistics

REGIONS = ["hk", "jp", "kr", "mo", "tw"]
RIDES = sorted(["20260722_06_sonic44",
                "20260802_01_taoyuan_airport_mrt_express_t2_taipei",
                "HK-SAMPLE-EAL-LOW", "MO-SAMPLE-MLM-TAIPA", "KR-SAMPLE-GYEONGBUKSEON"])
FIXTURE_SHA = "ccfcdb2a60eeed675648dedf01f2472d1f00d9dbcae2485737c87a083a801961"
BUDGET = 2 * 1024**3
METRICS = {"launch_ms", "firstmap_ms", "stalls_ms", "incremental_debug_ms", "footprint_bytes"}
LIMITS = {"launch_ms": 0.85, "firstmap_ms": 0.80, "stalls_ms": 0.70,
          "incremental_debug_ms": 1.10, "footprint_bytes": 1.0}

CONTRACT = {
    "schema_version": 1,
    "usage": "--protocol frozen-plan.json --runs run-index.json --output NEW-report.json",
    "references": {"path": "absolute or relative to the referring JSON file", "sha256": "64 hex digits"},
    "protocol": {
        "schema_version": 1, "frozen_at": "ISO8601 timezone required; before any timed run",
        "scope": "combined-five-real-regions", "regions": REGIONS, "ride_ids": RIDES,
        "fixture": "reference to exact committed five-real-region fixture",
        "baseline_lineage": {"kind": "original-frozen-dirty-start / reconstructed-original-commit / later-phase",
                             "description": "exact provenance; a later phase cannot satisfy whole-refactor original-start claims",
                             "evidence": "reference to archived provenance receipt; original kind additionally requires starting_commit, source_manifest_sha256, dirty_inputs_preserved=true"},
        "inputs": "reference to manifest: {scope: description, files: [references]}",
        "builds": {"baseline": "build receipt reference", "candidate": "build receipt reference"},
        "build_receipt": {"source": "source manifest reference (scope/files)",
                          "binary": "app executable reference", "configuration": "Release",
                          "toolchain": "exact Xcode/Swift/SDK/arch identity object",
                          "debug_binary": "Debug app executable reference"},
        "device": "exact nonempty identity object: id, model, os, kind (physical/simulator)",
        "host": "exact nonempty identity object: id, os, architecture",
        "groups": [{"id": "unique measured metric/cache group", "metric": "one of METRICS",
                    "cache": "explicit reset/warmup/cache protocol, identical within pairs",
                    "method": "public instrument, event endpoints, export and sampling definitions",
                    "collector": "reference to exact collector/exporter source",
                    "edit_patch": "incremental_debug_ms only: reference to identical representative edit applied after matched successful warm builds",
                    "window_ms": "positive fixed duration for stalls only",
                    "settle_after_ms": "nonnegative fixed quiet settling duration for footprint only"}],
        "samples": [{"id": "unique id", "pair": "unique within group", "group": "group id",
                     "role": "baseline or candidate"}],
        "sample_notes": "Order in samples is frozen collection order, each pair adjacent; alternate AB/BA. At least 20 pairs for nearest-rank P95, 3 for other metrics. These are reporting evidence requirements, not historical sample claims. Declare any measured cache states; omitted states are not accepted."
    },
    "run_index": {"protocol_sha256": "frozen protocol hash", "runs": ["raw normalized run JSON references, ALL planned attempts including failures"]},
    "run": {
        "id/group/pair/role": "must match plan", "protocol_sha256": "same hash",
        "build_sha256": "role build receipt hash", "inputs_sha256": "inputs manifest hash",
        "fixture_sha256": FIXTURE_SHA, "device": "exact protocol device", "host": "exact protocol host",
        "cache": "exact group cache value", "started_at/ended_at": "ISO8601 with timezone",
        "configuration": "Debug for incremental_debug_ms, Release otherwise",
        "argv": ["exact command arguments"], "exit_code": 0, "budget_stopped": False,
        "raw": ["references to original log/xcresult-export/trace-export, not summaries"],
        "quiet": "reference to timestamped audit JSON described below",
        "proof": "runtime only: public workload proof reference: regions, ride_ids, routes_generated=true, stats_ready=true",
        "edit_sha256": "incremental_debug_ms only: hash of group edit_patch",
        "warmup_raw": "incremental_debug_ms only: nonempty references to successful warm build logs",
        "observations": "latency: {duration_ms: number}; stalls: {window_ms: number, stalls_ms: [all exported stall durations]}, window starts at run.started_at; footprint: {pid: owned App PID, samples: [{pid,elapsed_ms,current_bytes,peak_bytes}], ready_elapsed_ms: number}, all elapsed values relative to run.started_at and within run interval"
    },
    "quiet_audit": {"started_at/ended_at": "must cover complete run",
                    "cpu_heavy_pids": [], "exclusive_device": True, "thermal_state": "nominal",
                    "raw": ["references to timestamped host process/CPU and device ownership/thermal audit artifacts; host-only for incremental Debug"]},
    "limitations": "Hashes bind supplied evidence; they cannot authenticate collector honesty, prove manifest completeness or machine quiet from an unreviewed assertion. Review raw audits/endpoints/closed source inventories. cpu_heavy_pids means competing heavy work, excluding the measured owned build/collector itself. This tool does not collect measurements or infer a historical baseline. Synthetic self-test artifacts establish evaluator behavior only."
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def artifact(reference, base, *, parse=False):
    require(isinstance(reference, dict), "artifact must be a path/hash reference")
    sha = reference.get("sha256", "")
    require(isinstance(sha, str) and len(sha) == 64
            and all(c in "0123456789abcdef" for c in sha), "invalid artifact SHA256")
    path = Path(reference["path"])
    path = path if path.is_absolute() else base / path
    require(path.is_file(), f"missing raw artifact: {path}")
    require(digest(path) == sha, f"artifact changed: {path}")
    return (json.loads(path.read_text()), path.parent) if parse else path


def manifest(reference, base):
    data, location = artifact(reference, base, parse=True)
    require(bool(data.get("scope")) and bool(data.get("files")), "empty/unscoped frozen manifest")
    paths = [str(artifact(ref, location).resolve()) for ref in data["files"]]
    require(len(paths) == len(set(paths)), "duplicate files in frozen manifest")


def instant(text):
    value = datetime.fromisoformat(text.replace("Z", "+00:00"))
    require(value.utcoffset() is not None, "timestamps require timezone")
    return value.timestamp()


def number(value, *, positive=False):
    require(type(value) in (float, int) and math.isfinite(value)
            and (value > 0 if positive else value >= 0), "invalid numeric observation")
    return value


def p95(values):
    return sorted(values)[math.ceil(0.95 * len(values)) - 1]


def distribution(values):
    return {"count": len(values), "p50": statistics.median(values), "p95": p95(values),
            "min": min(values), "max": max(values)}


def check_protocol(protocol, base):
    require(protocol["schema_version"] == 1, "unsupported schema")
    require(protocol["scope"] == "combined-five-real-regions", "scope must be combined five real regions")
    require(sorted(protocol["regions"]) == REGIONS and sorted(protocol["ride_ids"]) == RIDES,
            "real workload regions/rides differ")
    require(protocol["fixture"]["sha256"] == FIXTURE_SHA, "fixture is not reviewed five-real-region fixture")
    fixture, _ = artifact(protocol["fixture"], base, parse=True)
    require(sorted(ride["id"] for ride in fixture["trains"]) == RIDES, "fixture ride mismatch")
    manifest(protocol["inputs"], base)
    frozen = instant(protocol["frozen_at"])
    for identity, fields in [("device", ["id", "model", "os", "kind"]),
                             ("host", ["id", "os", "architecture"])]:
        require(all(protocol[identity].get(field) for field in fields), f"incomplete {identity} identity")
    require(protocol["device"]["kind"] in ["physical", "simulator"], "unknown device kind")
    builds = {}
    for role in ["baseline", "candidate"]:
        build, location = artifact(protocol["builds"][role], base, parse=True)
        require(build["configuration"] == "Release", "runtime products must be Release")
        require(all(build["toolchain"].get(field) for field in ["xcode", "swift", "sdk", "architecture"]),
                "incomplete toolchain identity")
        manifest(build["source"], location)
        artifact(build["binary"], location)
        artifact(build["debug_binary"], location)
        builds[role] = build
    require(builds["baseline"]["toolchain"] == builds["candidate"]["toolchain"], "toolchains differ")
    require(builds["baseline"]["source"]["sha256"] != builds["candidate"]["source"]["sha256"],
            "baseline and candidate source identities identical")
    lineage = protocol["baseline_lineage"]
    require(lineage["kind"] in ["original-frozen-dirty-start", "reconstructed-original-commit", "later-phase"]
            and lineage.get("description"), "baseline lineage missing/unknown")
    provenance, _ = artifact(lineage["evidence"], base, parse=True)
    if lineage["kind"] == "original-frozen-dirty-start":
        require(provenance["starting_commit"] == "14d294653fa11e87b6fbfbe3b4eba43f40b65225"
                and provenance["source_manifest_sha256"] == builds["baseline"]["source"]["sha256"]
                and provenance["dirty_inputs_preserved"] is True, "original dirty-start source provenance incomplete")
    groups = {}
    for group in protocol["groups"]:
        require(group["id"] not in groups, "duplicate metric/cache group")
        require(group["metric"] in METRICS and group.get("cache") and group.get("method"),
                "unscoped metric/cache/method")
        artifact(group["collector"], base)
        if group["metric"] == "stalls_ms":
            number(group["window_ms"], positive=True)
        if group["metric"] == "footprint_bytes":
            number(group["settle_after_ms"])
        if group["metric"] == "incremental_debug_ms":
            artifact(group["edit_patch"], base)
        groups[group["id"]] = group
    require({group["metric"] for group in groups.values()} == METRICS, "required metrics missing")
    samples, ids, pairs = protocol["samples"], set(), {}
    for entry in samples:
        require(entry["id"] not in ids, "duplicate planned sample")
        ids.add(entry["id"])
        require(entry["group"] in groups and entry["role"] in builds, "invalid planned group/role")
        key = (entry["group"], entry["pair"])
        pair = pairs.setdefault(key, [])
        require(entry["role"] not in [x["role"] for x in pair], "duplicate planned pair role")
        pair.append(entry)
    for pair in pairs.values():
        require(len(pair) == 2, "unpaired planned sample")
    for group_id, group in groups.items():
        planned = [entry for entry in samples if entry["group"] == group_id]
        minimum = 20 if group["metric"] in ["launch_ms", "firstmap_ms"] else 3
        require(len(planned) >= minimum * 2, f"{group_id}: insufficient declared samples (minimum {minimum} pairs)")
        for i in range(0, len(planned), 2):
            pair = planned[i:i + 2]
            require(pair[0]["pair"] == pair[1]["pair"], "pairs must be adjacent within each group")
            expected = ["baseline", "candidate"] if (i // 2) % 2 == 0 else ["candidate", "baseline"]
            require([entry["role"] for entry in pair] == expected, "AB/BA order must alternate")
    return frozen, groups


def measure(run, group):
    observations = run["observations"]
    if group["metric"] in ["launch_ms", "firstmap_ms", "incremental_debug_ms"]:
        return number(observations["duration_ms"], positive=True), None
    if group["metric"] == "stalls_ms":
        require(observations["window_ms"] == group["window_ms"], "stall observation windows differ")
        durations = [number(value, positive=True) for value in observations["stalls_ms"]]
        total = sum(durations)
        require(total <= group["window_ms"], "stall duration exceeds observation window")
        return total, None
    samples = observations["samples"]
    require(len(samples) >= 5, "fewer than five valid footprint samples")
    pid = observations["pid"]
    require(type(pid) is int and pid > 0, "owned App PID missing")
    ready = number(observations["ready_elapsed_ms"])
    previous, previous_peak = -1, 0
    for sample in samples:
        require(sample["pid"] == pid, "footprint samples combine different processes")
        elapsed = number(sample["elapsed_ms"])
        require(elapsed > previous, "footprint samples not ordered")
        previous = elapsed
        current = number(sample["current_bytes"], positive=True)
        peak = number(sample["peak_bytes"], positive=True)
        require(peak >= current, "peak is below actual footprint")
        require(peak >= previous_peak, "process peak high-water mark decreased")
        previous_peak = peak
    require(samples[-5]["elapsed_ms"] >= ready + group["settle_after_ms"], "footprint final samples precede settled readiness")
    return statistics.median(s["current_bytes"] for s in samples[-5:]), max(s["peak_bytes"] for s in samples)


def check_run(run, base, expected, protocol, protocol_sha, frozen, group):
    runtime = group["metric"] != "incremental_debug_ms"
    for field in ["id", "group", "pair", "role"]:
        require(run[field] == expected[field], f"planned {field} differs")
    for field, value in [("protocol_sha256", protocol_sha),
                         ("build_sha256", protocol["builds"][run["role"]]["sha256"]),
                         ("inputs_sha256", protocol["inputs"]["sha256"]),
                         ("host", protocol["host"]), ("cache", group["cache"])]:
        require(run[field] == value, f"run {field} identity differs")
    if runtime:
        require(run["fixture_sha256"] == FIXTURE_SHA and run["device"] == protocol["device"],
                "run fixture/device identity differs")
    else:
        require(run["edit_sha256"] == group["edit_patch"]["sha256"], "incremental edit differs")
        require(bool(run["warmup_raw"]), "successful matched warm build evidence missing")
        for reference in run["warmup_raw"]:
            artifact(reference, base)
    start, end = instant(run["started_at"]), instant(run["ended_at"])
    require(frozen < start < end, "run predates freeze or has invalid timing")
    configuration = "Debug" if group["metric"] == "incremental_debug_ms" else "Release"
    require(run["configuration"] == configuration, "wrong run configuration")
    require(type(run["exit_code"]) is int and run["exit_code"] == 0, f"command failed: exit={run['exit_code']}")
    require(run["budget_stopped"] is False, "budget stopped run remains FAIL")
    require(isinstance(run["argv"], list) and run["argv"] and all(isinstance(x, str) for x in run["argv"]), "missing exact command")
    require(bool(run["raw"]), "original raw evidence missing")
    for reference in run["raw"]:
        artifact(reference, base)
    quiet, location = artifact(run["quiet"], base, parse=True)
    require(instant(quiet["started_at"]) <= start and instant(quiet["ended_at"]) >= end, "quiet audit does not cover entire run")
    require(quiet["cpu_heavy_pids"] == [], "contaminated host measurement")
    if runtime:
        require(quiet["exclusive_device"] is True and quiet["thermal_state"] == "nominal",
                "contaminated device measurement")
    require(bool(quiet["raw"]), "raw quiet audit missing")
    for reference in quiet["raw"]:
        artifact(reference, location)
    if runtime:
        proof, _ = artifact(run["proof"], base, parse=True)
        require(sorted(proof["regions"]) == REGIONS and sorted(proof["ride_ids"]) == RIDES
                and proof["routes_generated"] is True and proof["stats_ready"] is True,
                "combined five-real-region public proof incomplete")
    value, peak = measure(run, group)
    interval_ms = (end - start) * 1000
    if group["metric"] == "stalls_ms":
        require(group["window_ms"] <= interval_ms, "declared stall window exceeds audited run interval")
    if group["metric"] == "footprint_bytes":
        require(all(sample["elapsed_ms"] <= interval_ms for sample in run["observations"]["samples"]),
                "footprint samples extend beyond audited run interval")
    require(value <= interval_ms if group["metric"].endswith("_ms") else True,
            "metric exceeds timed run interval")
    return value, peak, start, end


def evaluate(protocol_path, runs_path):
    report = {"schema_version": 1, "gate_pass": False, "status": "INVALID_EVIDENCE",
              "original_start_performance_gate_pass": False, "original_start_scope_eligible": False,
              "scope": "combined-five-real-regions; declared sources/device/cache states only",
              "threshold_ratios": LIMITS, "peak_budget_bytes": BUDGET,
              "groups": [], "runs": [], "errors": [],
              "unassessed": ["leaks", "M pixel/synchronization", "full-map repeated-toggle stress",
                             "platform matrix", "overall refactor acceptance"]}
    try:
        protocol = json.loads(protocol_path.read_text())
        protocol_sha = digest(protocol_path)
        report["protocol_sha256"] = protocol_sha
        frozen, groups = check_protocol(protocol, protocol_path.parent)
        report["baseline_lineage"] = protocol["baseline_lineage"]
        report["original_start_scope_eligible"] = protocol["baseline_lineage"]["kind"] == "original-frozen-dirty-start"
        index = json.loads(runs_path.read_text())
        require(index["protocol_sha256"] == protocol_sha, "run index frozen protocol differs")
        supplied = {}
        for reference in index["runs"]:
            run, location = artifact(reference, runs_path.parent, parse=True)
            require(run["id"] not in supplied, "duplicate observed sample")
            supplied[run["id"]] = (run, location)
        require(set(supplied) == {entry["id"] for entry in protocol["samples"]}, "missing or unplanned attempts; no trial exclusions")
        collected = {group: {"baseline": [], "candidate": [], "peaks": {"baseline": [], "candidate": []}} for group in groups}
        previous_end = frozen
        for expected in protocol["samples"]:
            run, location = supplied[expected["id"]]
            item = {"id": run["id"], "role": run["role"], "pair": run["pair"], "group": run["group"], "valid": False}
            report["runs"].append(item)
            try:
                value, peak, start, end = check_run(run, location, expected, protocol, protocol_sha, frozen, groups[run["group"]])
                require(start >= previous_end, "timed runs overlap or frozen order violated")
                previous_end = end
                item.update(valid=True, value=value, peak_bytes=peak)
                target = collected[run["group"]]
                target[run["role"]].append(value)
                if peak is not None:
                    target["peaks"][run["role"]].append(peak)
            except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
                item["error"] = str(error)
                report["errors"].append(f"{run['id']}: {error}")
        for group_id, data in collected.items():
            group = groups[group_id]
            row = {"group": group_id, "metric": group["metric"], "cache": group["cache"], "gate_pass": False}
            report["groups"].append(row)
            planned = sum(entry["group"] == group_id for entry in protocol["samples"]) // 2
            if len(data["baseline"]) != planned or len(data["candidate"]) != planned:
                row["status"] = "INVALID_EVIDENCE"
                continue
            row.update(baseline=distribution(data["baseline"]), candidate=distribution(data["candidate"]))
            deltas = [after - before for before, after in zip(data["baseline"], data["candidate"])]
            row.update(paired_deltas=distribution(deltas),
                       improved_pairs=sum(delta < 0 for delta in deltas),
                       regressed_pairs=sum(delta > 0 for delta in deltas))
            aggregate = p95 if group["metric"] in ["launch_ms", "firstmap_ms"] else statistics.median
            before, after = aggregate(data["baseline"]), aggregate(data["candidate"])
            ratio = after / before if before > 0 else None
            row.update(aggregate="nearest-rank P95" if aggregate == p95 else "median", ratio=ratio,
                       change_percent=100 * (ratio - 1) if ratio is not None else None,
                       limit_ratio=LIMITS[group["metric"]])
            row["gate_pass"] = ratio is not None and (ratio < 1 if group["metric"] == "footprint_bytes" else ratio <= LIMITS[group["metric"]])
            if group["metric"] == "footprint_bytes":
                bp, cp = statistics.median(data["peaks"]["baseline"]), statistics.median(data["peaks"]["candidate"])
                all_peaks = data["peaks"]["baseline"] + data["peaks"]["candidate"]
                row.update(baseline_median_peak=bp, candidate_median_peak=cp, maximum_observed_peak=max(all_peaks),
                           peak_gate_pass=cp <= bp and max(all_peaks) <= BUDGET)
                row["gate_pass"] = row["gate_pass"] and row["peak_gate_pass"]
            if before == 0:
                row["reason"] = "zero baseline cannot establish requested percentage reduction"
            row["status"] = "PASS" if row["gate_pass"] else "FAIL"
        report["gate_pass"] = not report["errors"] and all(row["gate_pass"] for row in report["groups"])
        report["original_start_performance_gate_pass"] = report["gate_pass"] and report["original_start_scope_eligible"]
        report["status"] = "INVALID_EVIDENCE" if report["errors"] else "PASS" if report["gate_pass"] else "FAIL"
    except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
        report["errors"].append(str(error))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", action="store_true")
    parser.add_argument("--protocol", type=Path)
    parser.add_argument("--runs", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.schema:
        print(json.dumps(CONTRACT, indent=2))
        return 0
    if not all([args.protocol, args.runs, args.output]):
        parser.error("--protocol, --runs and --output are required")
    # Preserve prior acceptance/failure artifacts; use a new output every time.
    with args.output.open("x") as output:
        report = evaluate(args.protocol.resolve(), args.runs.resolve())
        json.dump(report, output, indent=2, allow_nan=False)
        output.write("\n")
    print(json.dumps({"status": report["status"], "gate_pass": report["gate_pass"], "errors": report["errors"]}))
    return 0 if report["gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
