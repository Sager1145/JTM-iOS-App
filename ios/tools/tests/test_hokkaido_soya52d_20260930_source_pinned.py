"""Official exact-date 52D / 宗谷 column remains scoped and side accurate."""

import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-soya52d-20260930.json"


class HokkaidoSoya52DTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reviewed = json.loads(CANDIDATE.read_text(encoding="utf-8"))["trip"]
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_printed_calls_and_source(self):
        reviewed = self.reviewed
        actual = next(trip for trip in timetable.materialize(self.data, "2026-09-30")
                      if trip["trip_id"] == reviewed["trip_id"])
        self.assertEqual(actual["train_number"], "52D")
        self.assertIsNone(actual["public_number"])
        self.assertEqual(
            [[self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"]]
             for stop in actual["stop_times"]], reviewed["stops"]
        )
        source = next(row for row in self.data["source_documents"] if row["source_id"] == reviewed["source_id"])
        self.assertEqual(source["url_or_locator"], reviewed["source_url"])
        self.assertNotIn("比布", [row[0] for row in reviewed["stops"]])
        self.assertNotIn("剣淵", [row[0] for row in reviewed["stops"]])
        self.assertNotIn("砂川", [row[0] for row in reviewed["stops"]])
        self.assertNotIn("美唄", [row[0] for row in reviewed["stops"]])

    def test_scope_partial_current_route_and_unknown_operator(self):
        trip_id = self.reviewed["trip_id"]
        for other in ("2026-09-29", "2026-10-01"):
            self.assertFalse(any(trip["trip_id"] == trip_id for trip in timetable.materialize(self.data, other)))
        segments = sorted(
            (row for row in self.data["trip_line_segments"] if row["trip_id"] == trip_id),
            key=lambda row: row["sequence"],
        )
        self.assertEqual(len(segments), 14)
        self.assertEqual([row["current_n02_line_id"] for row in segments],
                         ["jp-北海道旅客鉄道-宗谷線"] * 10
                         + ["jp-北海道旅客鉄道-函館線"] * 4)
        self.assertTrue(all(row["reference_kind"] == "current_n02" for row in segments))
        self.assertTrue(all(row["source_id"] == "jr-hokkaido-line-inventory-priority-route-batch-a"
                            for row in segments))
        self.assertFalse(any(row["trip_id"] == trip_id for row in self.data["trip_operator_segments"]))
        statuses = {row["dimension"]: row["status"] for row in self.data["fact_completeness"]
                    if row["entity_id"] == trip_id}
        self.assertEqual(statuses["times"], "partial")
        self.assertEqual(statuses["route_lines"], "partial")
        self.assertEqual(statuses["operator"], "unknown")


if __name__ == "__main__":
    unittest.main()
