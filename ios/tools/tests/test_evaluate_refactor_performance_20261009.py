"""Synthetic evidence exercises evaluator semantics; no product measurements."""
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1] / "evaluate-refactor-performance-20261009.py"
SPEC = importlib.util.spec_from_file_location("performance_acceptance", TOOL)
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)


class PairedEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="jtm-acceptance-selftest-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.epoch = datetime(2026, 10, 9, tzinfo=timezone.utc)
        self.raw = self.write("synthetic-not-product-evidence.log", "SYNTHETIC evaluator test only")
        self.proof = self.write("proof.json", {"regions": tool.REGIONS, "ride_ids": tool.RIDES,
                           "routes_generated": True, "stats_ready": True})
        self.quiet = self.write("quiet.json", {"started_at": self.stamp(0), "ended_at": self.stamp(10000),
                           "cpu_heavy_pids": [], "exclusive_device": True, "thermal_state": "nominal",
                           "raw": [self.raw]})
        builds = {}
        for role in ["baseline", "candidate"]:
            source_file = self.write(role + ".swift", role)
            source = self.write(role + "-manifest.json", {"scope": "synthetic test only", "files": [source_file]})
            builds[role] = self.write(role + "-build.json", {"source": source,
                "binary": self.write(role + ".bin", role), "debug_binary": self.write(role + "-debug.bin", role),
                "configuration": "Release", "toolchain": {"xcode": "test", "swift": "test", "sdk": "test", "architecture": "test"}})
        fixture = TOOL.parent / "fixtures/release-route-memory-five-real-regions.json"
        self.protocol = {"schema_version": 1, "frozen_at": self.stamp(0),
            "scope": "combined-five-real-regions", "regions": tool.REGIONS, "ride_ids": tool.RIDES,
            "fixture": {"path": str(fixture), "sha256": tool.digest(fixture)}, "builds": builds,
            "baseline_lineage": {"kind": "later-phase", "description": "synthetic evaluator test only",
                                 "evidence": self.write("provenance.json", {"test_only": True})},
            "inputs": self.write("inputs.json", {"scope": "synthetic test input", "files": [self.raw]}),
            "device": {"id": "synthetic", "model": "synthetic", "os": "synthetic", "kind": "simulator"},
            "host": {"id": "synthetic", "os": "synthetic", "architecture": "synthetic"},
            "groups": [], "samples": []}
        for metric in sorted(tool.METRICS):
            self.protocol["groups"].append({"id": metric, "metric": metric, "cache": "frozen warm test state",
                "method": "synthetic test observation", "collector": self.raw,
                "edit_patch": self.raw,
                "window_ms": 5000, "settle_after_ms": 5000})
            count = 20 if metric in ["launch_ms", "firstmap_ms"] else 3
            for pair in range(count):
                roles = ["baseline", "candidate"] if pair % 2 == 0 else ["candidate", "baseline"]
                for role in roles:
                    self.protocol["samples"].append({"id": f"{metric}-{pair}-{role}",
                        "group": metric, "pair": str(pair), "role": role})
        self.protocol_path = self.root / "protocol.json"
        self.write("protocol.json", self.protocol)
        protocol_sha = tool.digest(self.protocol_path)
        self.runs = []
        for i, entry in enumerate(self.protocol["samples"]):
            candidate = entry["role"] == "candidate"
            metric = entry["group"]
            if metric == "footprint_bytes":
                value = 900 if candidate else 1000
                observations = {"pid": 123, "ready_elapsed_ms": 1000, "samples": [
                    {"pid": 123, "elapsed_ms": 6000 + j * 1000, "current_bytes": value, "peak_bytes": 1200}
                    for j in range(5)]}
            elif metric == "stalls_ms":
                observations = {"window_ms": 5000, "stalls_ms": [600 if candidate else 1000]}
            else:
                observations = {"duration_ms": 700 if candidate else 1000}
            run = dict(entry, protocol_sha256=protocol_sha,
                build_sha256=builds[entry["role"]]["sha256"], inputs_sha256=self.protocol["inputs"]["sha256"],
                fixture_sha256=tool.FIXTURE_SHA, device=self.protocol["device"], host=self.protocol["host"],
                cache="frozen warm test state", started_at=self.stamp(1 + i * 20), ended_at=self.stamp(20 + i * 20),
                configuration="Debug" if metric == "incremental_debug_ms" else "Release",
                argv=["synthetic"], exit_code=0, budget_stopped=False, raw=[self.raw], quiet=self.quiet,
                proof=self.proof, observations=observations)
            if metric == "incremental_debug_ms":
                run.update(edit_sha256=self.raw["sha256"], warmup_raw=[self.raw])
            self.runs.append(run)
        self.index_path = self.root / "index.json"

    def stamp(self, seconds):
        return (self.epoch + timedelta(seconds=seconds)).isoformat()

    def write(self, name, data):
        path = self.root / name
        path.write_text(json.dumps(data) if not isinstance(data, str) else data)
        return {"path": str(path), "sha256": tool.digest(path)}

    def report(self):
        references = [self.write(run["id"] + ".json", run) for run in self.runs]
        self.write("index.json", {"protocol_sha256": tool.digest(self.protocol_path), "runs": references})
        return tool.evaluate(self.protocol_path, self.index_path)

    def run_for(self, metric, role="candidate"):
        return next(run for run in self.runs if run["group"] == metric and run["role"] == role)

    def test_complete_synthetic_evidence_passes_scoped_gates(self):
        report = self.report()
        self.assertEqual(report["status"], "PASS", report)
        self.assertEqual(len(report["runs"]), 98)
        self.assertIn("leaks", report["unassessed"])
        self.assertFalse(report["original_start_performance_gate_pass"])

    def test_incremental_build_does_not_require_runtime_ui_or_device_proof(self):
        for run in self.runs:
            if run["group"] == "incremental_debug_ms":
                for field in ["proof", "device", "fixture_sha256"]:
                    run.pop(field)
                run["quiet"] = self.write("host-only.json", {"started_at": self.stamp(0),
                    "ended_at": self.stamp(10000), "cpu_heavy_pids": [], "raw": [self.raw]})
        self.assertEqual(self.report()["status"], "PASS")

    def test_nearest_rank_p95_keeps_tail_not_median(self):
        self.assertEqual(tool.p95(list(range(1, 21))), 19)
        for run in self.runs:
            if run["group"] == "launch_ms" and run["role"] == "candidate":
                run["observations"]["duration_ms"] = 900 if int(run["pair"]) >= 18 else 700
        report = self.report()
        self.assertEqual(report["status"], "FAIL")
        row = next(row for row in report["groups"] if row["metric"] == "launch_ms")
        self.assertEqual(row["ratio"], .9)

    def test_failed_attempt_is_retained_and_not_excluded(self):
        run = self.run_for("stalls_ms")
        run["exit_code"] = 65
        report = self.report()
        self.assertEqual(report["status"], "INVALID_EVIDENCE")
        self.assertEqual(len(report["runs"]), 98)
        self.assertTrue(any("exit=65" in error for error in report["errors"]))

    def test_missing_pair_cannot_pass(self):
        self.runs.pop()
        report = self.report()
        self.assertFalse(report["gate_pass"])
        self.assertIn("missing or unplanned", report["errors"][0])

    def test_changed_artifact_cannot_pass_even_if_summaries_good(self):
        Path(self.raw["path"]).write_text("changed")
        self.assertEqual(self.report()["status"], "INVALID_EVIDENCE")

    def test_contaminated_or_uncovered_quiet_audit_cannot_pass(self):
        for update in [{"cpu_heavy_pids": [123]}, {"exclusive_device": False},
                       {"thermal_state": "serious"}, {"ended_at": self.stamp(3)}]:
            with self.subTest(update=update):
                quiet = json.loads(Path(self.quiet["path"]).read_text())
                quiet.update(update)
                reference = self.write("bad-quiet.json", quiet)
                run = self.runs[0]
                old = run["quiet"]
                run["quiet"] = reference
                self.assertFalse(self.report()["gate_pass"])
                run["quiet"] = old

    def test_identities_cache_and_overlap_cannot_be_pooled(self):
        for field, value in [("cache", "cold"), ("device", {"id": "other"}),
                             ("inputs_sha256", "0" * 64), ("started_at", self.stamp(1))]:
            with self.subTest(field=field):
                run = self.runs[1]
                old = run[field]
                run[field] = value
                self.assertFalse(self.report()["gate_pass"])
                run[field] = old

    def test_equal_memory_does_not_meet_strict_smaller(self):
        for run in self.runs:
            if run["group"] == "footprint_bytes" and run["role"] == "candidate":
                for sample in run["observations"]["samples"]:
                    sample["current_bytes"] = 1000
        self.assertEqual(self.report()["status"], "FAIL")

    def test_peak_budget_breach_preserved_despite_lower_medians(self):
        run = self.run_for("footprint_bytes")
        run["observations"]["samples"][-1]["peak_bytes"] = tool.BUDGET + 1
        report = self.report()
        self.assertEqual(report["status"], "FAIL")
        row = next(row for row in report["groups"] if row["metric"] == "footprint_bytes")
        self.assertEqual(row["maximum_observed_peak"], tool.BUDGET + 1)

    def test_zero_stall_baseline_has_no_invented_percentage(self):
        for run in self.runs:
            if run["group"] == "stalls_ms":
                run["observations"]["stalls_ms"] = []
        report = self.report()
        self.assertEqual(report["status"], "FAIL")
        row = next(row for row in report["groups"] if row["metric"] == "stalls_ms")
        self.assertIsNone(row["ratio"])

    def test_threshold_boundaries(self):
        for run in self.runs:
            if run["role"] == "candidate":
                metric = run["group"]
                if metric in ["launch_ms", "firstmap_ms", "incremental_debug_ms"]:
                    run["observations"]["duration_ms"] = 1000 * tool.LIMITS[metric]
                elif metric == "stalls_ms":
                    run["observations"]["stalls_ms"] = [700]
        self.assertEqual(self.report()["status"], "PASS")

    def test_invalid_numeric_and_unsettled_footprint_are_rejected(self):
        run = self.run_for("footprint_bytes")
        run["observations"]["samples"][0]["elapsed_ms"] = 5999
        self.assertEqual(self.report()["status"], "INVALID_EVIDENCE")
        run["observations"]["samples"][0]["elapsed_ms"] = 6000
        run["observations"]["samples"][0]["peak_bytes"] = float("nan")
        self.assertEqual(self.report()["status"], "INVALID_EVIDENCE")

    def test_footprint_cannot_mix_processes_or_reset_process_peak(self):
        run = self.run_for("footprint_bytes")
        run["observations"]["samples"][1]["pid"] = 124
        self.assertEqual(self.report()["status"], "INVALID_EVIDENCE")
        run["observations"]["samples"][1]["pid"] = 123
        run["observations"]["samples"][0]["peak_bytes"] = 1300
        self.assertEqual(self.report()["status"], "INVALID_EVIDENCE")

    def test_peak_regression_cannot_be_offset_by_settled_reduction(self):
        for run in self.runs:
            if run["group"] == "footprint_bytes" and run["role"] == "candidate":
                for sample in run["observations"]["samples"]:
                    sample["peak_bytes"] = 1300
        self.assertEqual(self.report()["status"], "FAIL")

    def test_incomplete_original_dirty_start_provenance_cannot_pass(self):
        self.protocol["baseline_lineage"]["kind"] = "original-frozen-dirty-start"
        self.write("protocol.json", self.protocol)
        self.assertEqual(self.report()["status"], "INVALID_EVIDENCE")

    def test_insufficient_p95_samples_cannot_pass(self):
        self.protocol["samples"] = [entry for entry in self.protocol["samples"]
            if not (entry["group"] == "launch_ms" and entry["pair"] == "19")]
        self.write("protocol.json", self.protocol)
        self.assertEqual(self.report()["status"], "INVALID_EVIDENCE")

    def test_stall_observation_window_must_fit_entire_audited_interval(self):
        run = self.run_for("stalls_ms")
        run["ended_at"] = (datetime.fromisoformat(run["started_at"]) + timedelta(seconds=2)).isoformat()
        report = self.report()
        self.assertEqual(report["status"], "INVALID_EVIDENCE")
        self.assertTrue(any("stall window exceeds" in error for error in report["errors"]))

    def test_footprint_elapsed_observations_must_fit_audited_interval(self):
        run = self.run_for("footprint_bytes")
        run["ended_at"] = (datetime.fromisoformat(run["started_at"]) + timedelta(seconds=1)).isoformat()
        report = self.report()
        self.assertEqual(report["status"], "INVALID_EVIDENCE")
        self.assertTrue(any("samples extend beyond" in error for error in report["errors"]))


if __name__ == "__main__":
    unittest.main()
