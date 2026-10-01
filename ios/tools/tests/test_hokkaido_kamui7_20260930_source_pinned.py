"""Official exact-date 2007M / カムイ 7 column remains scoped and side accurate."""

import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-kamui7-20260930.json"


class HokkaidoKamui7Tests(unittest.TestCase):
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
        self.assertEqual(actual["train_number"], "2007M")
        self.assertEqual(actual["public_number"], "7")
        self.assertEqual(
            [[self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"]]
             for stop in actual["stop_times"]], reviewed["stops"]
        )
        source = next(row for row in self.data["source_documents"] if row["source_id"] == reviewed["source_id"])
        self.assertEqual(source["url_or_locator"], reviewed["source_url"])
        self.assertEqual(len(reviewed["stops"]), 7)

    def test_scope_partial_current_route_and_unknown_operator(self):
        trip_id = self.reviewed["trip_id"]
        same_number = [trip for trip in timetable.materialize(self.data, "2026-09-30")
                       if trip["service_id"] == "kamui" and trip["public_number"] == "7"]
        self.assertEqual([trip["trip_id"] for trip in same_number], [trip_id])
        for other in ("2026-09-29", "2026-10-01"):
            self.assertFalse(any(trip["trip_id"] == trip_id for trip in timetable.materialize(self.data, other)))
        segments = sorted(
            (row for row in self.data["trip_line_segments"] if row["trip_id"] == trip_id),
            key=lambda row: row["sequence"],
        )
        self.assertEqual(len(segments), 6)
        self.assertTrue(all(row["current_n02_line_id"] == "jp-北海道旅客鉄道-函館線"
                            for row in segments))
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
