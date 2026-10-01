"""Exact 72D and 3592D columns preserve printed call, platform and date boundaries."""

import json
from pathlib import Path
import sys
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable

BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-okhotsk2-taisetsu3592d-20260930.json"


class HokkaidoOkhotskTaisetsuTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reviewed = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_printed_calls_platform_and_source(self):
        materialized = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        self.assertEqual(sum(len(trip["stops"]) for trip in self.reviewed["trips"]), 26)
        for reviewed in self.reviewed["trips"]:
            with self.subTest(train=reviewed["train_number"]):
                actual = materialized[reviewed["trip_id"]]
                self.assertEqual((actual["train_number"], actual["public_number"]),
                                 (reviewed["train_number"], reviewed["public_number"]))
                self.assertEqual(
                    [[self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"]]
                     for stop in actual["stop_times"]], reviewed["stops"]
                )
                self.assertEqual(
                    {self.names[stop["station_id"]]: stop["platform"]
                     for stop in actual["stop_times"] if stop["platform"] is not None},
                    reviewed["printed_platforms"],
                )
                source = next(row for row in self.data["source_documents"]
                              if row["source_id"] == reviewed["source_id"])
                self.assertEqual(source["url_or_locator"], reviewed["source_url"])

    def test_exact_date_and_unresolved_route(self):
        today = timetable.materialize(self.data, "2026-09-30")
        for reviewed in self.reviewed["trips"]:
            with self.subTest(train=reviewed["train_number"]):
                trip_id = reviewed["trip_id"]
                same_number = [trip for trip in today if trip["service_id"] == reviewed["service_id"]
                               and trip["train_number"] == reviewed["train_number"]]
                self.assertEqual([trip["trip_id"] for trip in same_number], [trip_id])
                for other in ("2026-09-29", "2026-10-01"):
                    self.assertFalse(any(trip["trip_id"] == trip_id for trip in timetable.materialize(self.data, other)))
                self.assertFalse(any(row["trip_id"] == trip_id for row in self.data["trip_line_segments"]))
                self.assertFalse(any(row["trip_id"] == trip_id for row in self.data["trip_operator_segments"]))
                statuses = {row["dimension"]: row["status"] for row in self.data["fact_completeness"]
                            if row["entity_id"] == trip_id}
                self.assertEqual(statuses["times"], "partial")
                self.assertEqual(statuses["route_lines"], "unknown")
                self.assertEqual(statuses["operator"], "unknown")

    def test_taisetsu_public_number_is_not_invented(self):
        train = next(trip for trip in self.reviewed["trips"] if trip["train_number"] == "3592D")
        self.assertIsNone(train["public_number"])
        self.assertEqual(train["service_class"], "special_rapid")
        self.assertEqual(train["stops"][-1], ["旭川", "11:51", None])


if __name__ == "__main__":
    unittest.main()
