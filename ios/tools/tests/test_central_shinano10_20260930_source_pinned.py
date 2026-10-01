"""Source-pinned single-day checks for JR Central Shinano 10."""

import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable

SCRIPT = ROOT / "ios/tools/normalize-reviewed-central-shinano10-20260930.py"
spec = importlib.util.spec_from_file_location("shinano10_normalizer", SCRIPT)
normalizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(normalizer)


class Shinano10SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / "candidates/jr-central-shinano10-20260930.json").read_text())
        cls.manifest = timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.data, cls.origins = timetable.load_dataset(timetable.DEFAULT_CANONICAL, cls.manifest)

    def test_candidate_is_pinned_to_selected_official_date_variant(self):
        normalizer.validate(self.candidate)
        source = self.candidate["trip"]["source"]
        self.assertEqual(source["url_or_locator"], normalizer.URL)
        self.assertEqual(source["effective_date"], "2026-09-30")
        self.assertFalse(source["automated_extraction_allowed"])
        self.assertEqual(
            [(r["name_snapshot"], r["arrival_time"], r["departure_time"])
             for r in self.candidate["trip"]["stop_times"]],
            [(n, arrival, departure) for n, _, arrival, departure, _, _ in normalizer.EXPECTED],
        )

    def test_normalized_rows_validate_and_materialize_only_on_selected_date(self):
        self.assertEqual(timetable.validate_dataset(self.data, self.origins, self.manifest), [])
        for day, expected in (("2026-09-29", 0), ("2026-09-30", 1)):
            matched = [trip for trip in timetable.materialize(self.data, day)
                       if trip["trip_id"] == normalizer.TRIP]
            self.assertEqual(len(matched), expected)
            if matched:
                self.assertEqual(len(matched[0]["stop_times"]), 10)
                self.assertEqual(matched[0]["train_number"], "1010M")
                self.assertIsNone(matched[0]["stop_times"][0]["arrival_time"])
                self.assertIsNone(matched[0]["stop_times"][-1]["departure_time"])

    def test_route_is_current_partial_and_operator_remains_unverified(self):
        facts = [r for r in self.data["fact_completeness"] if r["entity_id"] == normalizer.TRIP]
        self.assertEqual({r["dimension"]: r["status"] for r in facts}["route_lines"], "partial")
        self.assertEqual({r["dimension"]: r["status"] for r in facts}["operator"], "unknown")
        segments = sorted(
            (r for r in self.data["trip_line_segments"] if r["trip_id"] == normalizer.TRIP),
            key=lambda r: r["sequence"],
        )
        self.assertEqual(len(segments), 9)
        self.assertEqual([r["current_n02_line_id"] for r in segments],
                         ["jp-東日本旅客鉄道-信越線-3"]
                         + ["jp-東日本旅客鉄道-篠ノ井線"] * 2
                         + ["jp-東海旅客鉄道-中央線"] * 6)
        self.assertEqual([r["operator_id"] for r in segments],
                         ["jr-east"] * 3 + ["jr-central"] * 6)
        self.assertEqual([r["source_id"] for r in segments],
                         ["jr-east-shinano-boundaries-priority-route-batch-a"] * 3
                         + ["jr-central-shinano-route-priority-route-batch-a"] * 6)
        self.assertTrue(all(r["reference_kind"] == "current_n02" for r in segments))
        self.assertTrue(all(r.get("rail_history_id") is None for r in segments))
        self.assertFalse([r for r in self.data["trip_operator_segments"] if r["trip_id"] == normalizer.TRIP])


if __name__ == "__main__":
    unittest.main()
