"""Apple footprint response fixtures; never launch a device or external tool."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "measure-release-route-memory.py"
SPEC = importlib.util.spec_from_file_location("measure_release_route_memory", SCRIPT)
sampler = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sampler)
PID = 88715
CURRENT = 1576391216
PEAK = 2205766504


def process(pid=PID, current=CURRENT, peak=PEAK):
    return {"pid": pid, "auxiliary": {
        "phys_footprint": current, "phys_footprint_peak": peak}}


class FootprintSnapshotTests(unittest.TestCase):
    def sample(self, payload, *, returncode=0, write=True):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "footprint.json"
            # A failed command must not consume an earlier positive sample.
            path.write_text(json.dumps({"processes": [process()]}))

            def response(args, **kwargs):
                self.assertFalse(path.exists())
                if write:
                    path.write_text(json.dumps(payload))
                return SimpleNamespace(returncode=returncode)

            with mock.patch.object(sampler.subprocess, "run", side_effect=response):
                return sampler.footprint(PID, path)

    def test_real_positive_current_and_peak_are_preserved_including_over_budget(self):
        sample = self.sample({"processes": [process()]})
        self.assertEqual(sample["pid"], PID)
        self.assertEqual(sample["current_bytes"], CURRENT)
        self.assertEqual(sample["peak_bytes"], PEAK)
        self.assertGreater(sample["peak_bytes"], sampler.BUDGET)
        self.assertGreater(sample["time"], 0)

    def test_process_exit_null_entries_are_unavailable_not_zero_samples(self):
        for entries in [[None], [None, None]]:
            with self.subTest(entries=entries):
                self.assertIsNone(self.sample({"processes": entries}))

    def test_null_entry_does_not_hide_a_valid_owned_process(self):
        sample = self.sample({"processes": [None, process()]})
        self.assertEqual(sample["current_bytes"], CURRENT)
        self.assertEqual(sample["peak_bytes"], PEAK)

    def test_owned_process_with_null_auxiliary_is_unavailable(self):
        self.assertIsNone(self.sample({"processes": [{"pid": PID, "auxiliary": None}]}))

    def test_wrong_pid_still_rejected_even_with_exit_nulls(self):
        for entries in [[process(PID + 1)], [None, process(PID + 1)],
                        [{"pid": PID + 1, "auxiliary": None}], []]:
            with self.subTest(entries=entries):
                with self.assertRaisesRegex(ValueError, "owned app PID"):
                    self.sample({"processes": entries})

    def test_duplicate_owned_pid_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "owned app PID"):
            self.sample({"processes": [None, process(), process()]})

    def test_missing_or_malformed_metrics_are_rejected(self):
        invalid = [None, "123", True, False, 0, -1, float("nan"),
                   float("inf"), float("-inf")]
        for field in ["current", "peak"]:
            for value in invalid:
                with self.subTest(field=field, value=value):
                    with self.assertRaisesRegex(ValueError, "physical footprint"):
                        self.sample({"processes": [process(**{field: value})]})
        for auxiliary in [{}, [], "unavailable"]:
            with self.subTest(auxiliary=auxiliary):
                with self.assertRaisesRegex(ValueError, "physical footprint"):
                    self.sample({"processes": [{"pid": PID, "auxiliary": auxiliary}]})

    def test_peak_below_current_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "physical footprint"):
            self.sample({"processes": [process(current=100, peak=99)]})

    def test_failed_or_missing_output_cannot_reuse_stale_positive_sample(self):
        self.assertIsNone(self.sample({"processes": [process()]}, returncode=1))
        self.assertIsNone(self.sample(None, write=False))


if __name__ == "__main__":
    unittest.main()
