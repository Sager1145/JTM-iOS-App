"""Exact-date Nanki 1 source and normalized trip checks."""

import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable

SCRIPT = ROOT / "ios/tools/normalize-reviewed-central-nanki1-20260930.py"
spec = importlib.util.spec_from_file_location("nanki1_normalizer", SCRIPT)
normalizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(normalizer)


class Nanki1SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / "candidates/jr-central-nanki1-20260930.json").read_text())
        cls.source = json.loads((BASE / "sources/source-registry-central-nanki1-20260930.jsonl").read_text())
        cls.manifest = timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.data, cls.origins = timetable.load_dataset(timetable.DEFAULT_CANONICAL, cls.manifest)

    def test_selected_page_and_all_timed_calls_are_pinned(self):
        normalizer.validate(self.candidate, self.source)
        self.assertEqual(self.source["url_or_locator"], normalizer.URL)
        self.assertFalse(self.source["automated_extraction_allowed"])
        self.assertEqual(
            [(r["name_snapshot"], r["arrival_time"], r["departure_time"])
             for r in self.candidate["trip"]["stop_times"]],
            [(n, arrival, departure) for n, _, arrival, departure, _, _ in normalizer.STOPS],
        )
        self.assertEqual(len(self.candidate["trip"]["stop_times"]), 13)

    def test_one_date_materializes_with_partial_current_route(self):
        self.assertEqual(timetable.validate_dataset(self.data, self.origins, self.manifest), [])
        self.assertFalse([t for t in timetable.materialize(self.data, "2026-09-29")
                          if t["trip_id"] == normalizer.TRIP])
        trips = [t for t in timetable.materialize(self.data, "2026-09-30")
                 if t["trip_id"] == normalizer.TRIP]
        self.assertEqual(len(trips), 1)
        self.assertEqual(trips[0]["train_number"], "3001D")
        self.assertEqual(len(trips[0]["stop_times"]), 13)
        self.assertIsNone(trips[0]["stop_times"][0]["arrival_time"])
        self.assertIsNone(trips[0]["stop_times"][-1]["departure_time"])
        facts = {r["dimension"]: r["status"] for r in self.data["fact_completeness"]
                 if r["entity_id"] == normalizer.TRIP}
        self.assertEqual(facts["route_lines"], "partial")
        self.assertEqual(facts["operator"], "unknown")
        segments = [r for r in self.data["trip_line_segments"]
                    if r["trip_id"] == normalizer.TRIP]
        self.assertEqual(len(segments), 13)
        self.assertTrue(all(r["reference_kind"] == "current_n02" for r in segments))
        self.assertNotIn("jp.n02.006285", {r["station_id"] for r in trips[0]["stop_times"]})


if __name__ == "__main__":
    unittest.main()
