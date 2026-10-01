"""Four selected JR Hokkaido columns retain exact printed calls and date scope."""

import json
from pathlib import Path
import sys
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable

BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-hokuto1-2-suzuran2-5-20260930.json"


class HokkaidoHokutoSuzuranTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reviewed = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_each_printed_column_and_source(self):
        materialized = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        self.assertEqual(sum(len(trip["stops"]) for trip in self.reviewed["trips"]), 47)
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

    def test_date_scope_pass_through_and_unknowns(self):
        today = timetable.materialize(self.data, "2026-09-30")
        for reviewed in self.reviewed["trips"]:
            with self.subTest(train=reviewed["train_number"]):
                trip_id = reviewed["trip_id"]
                matching = [trip for trip in today if trip["service_id"] == reviewed["service_id"]
                            and trip["public_number"] == reviewed["public_number"]]
                self.assertEqual([trip["trip_id"] for trip in matching], [trip_id])
                for other in ("2026-09-29", "2026-10-01"):
                    self.assertFalse(any(trip["trip_id"] == trip_id for trip in timetable.materialize(self.data, other)))
                calls = {stop[0] for stop in reviewed["stops"]}
                self.assertTrue(calls.isdisjoint(self.reviewed["pass_through_notes"][reviewed["train_number"]]))
                self.assertFalse(any(row["trip_id"] == trip_id for row in self.data["trip_line_segments"]))
                self.assertFalse(any(row["trip_id"] == trip_id for row in self.data["trip_operator_segments"]))
                statuses = {row["dimension"]: row["status"] for row in self.data["fact_completeness"]
                            if row["entity_id"] == trip_id}
                self.assertEqual(statuses["times"], "partial")
                self.assertEqual(statuses["route_lines"], "unknown")
                self.assertEqual(statuses["operator"], "unknown")

    def test_suzuran_two_terminates_at_higashi_muroran(self):
        reviewed = next(trip for trip in self.reviewed["trips"] if trip["train_number"] == "1002M")
        self.assertEqual(reviewed["destination"], "東室蘭")
        self.assertEqual(reviewed["stops"][-1], ["東室蘭", "08:58", None])
        self.assertNotIn("室蘭", [stop[0] for stop in reviewed["stops"]])

    def test_printed_symbols_preserve_branch_rows_and_order(self):
        expected = {
            "1": [(3, 0, "大沼公園", "レ"),
                  (8, 0, "室蘭", "||"), (8, 1, "母恋", "||"),
                  (8, 2, "御崎", "||"), (8, 3, "輪西", "||"),
                  (9, 0, "鷲別", "レ"), (9, 1, "幌別", "レ"),
                  (12, 0, "沼ノ端", "レ"), (13, 0, "千歳", "レ")],
            "2": [(2, 0, "千歳", "レ"), (3, 0, "沼ノ端", "レ"),
                  (4, 0, "白老", "レ"), (4, 1, "登別", "レ"),
                  (4, 2, "幌別", "レ"), (4, 3, "鷲別", "レ"),
                  (5, 0, "輪西", "||"), (5, 1, "御崎", "||"),
                  (5, 2, "母恋", "||"), (5, 3, "室蘭", "||"),
                  (5, 4, "伊達紋別", "レ"), (5, 5, "洞爺", "レ"),
                  (8, 0, "大沼公園", "レ"), (9, 0, "五稜郭", "レ")],
        }
        for number, printed in expected.items():
            trip_id = f"jr-hokkaido.hokuto.{number}.exact-2026-09-30"
            symbols = sorted((row for row in self.data["trip_timetable_symbols"]
                              if row["trip_id"] == trip_id),
                             key=lambda row: (row["after_stop_sequence"], row["position"]))
            self.assertEqual([(row["after_stop_sequence"], row["position"],
                               row["station_name"], row["symbol"]) for row in symbols], printed)
            reviewed = next(trip for trip in self.reviewed["trips"] if trip["trip_id"] == trip_id)
            self.assertEqual({row["source_id"] for row in symbols}, {reviewed["source_id"]})
            passenger_names = {stop[0] for stop in reviewed["stops"]}
            self.assertTrue(passenger_names.isdisjoint(row["station_name"] for row in symbols))


if __name__ == "__main__":
    unittest.main()
