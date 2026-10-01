"""Reviewed whole-line columns retain exact date, clocks, numbers, and platforms."""

import json
from pathlib import Path
import sys
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable

BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-line-columns-20260930.json"
ADDITIONAL = BASE / "candidates/jr-hokkaido-pending-s110-20260930.json"
OZORA_UP = BASE / "candidates/jr-hokkaido-ozora2-20260930.json"
MORE_UP = (BASE / "candidates/jr-hokkaido-tokachi2-4-20260930.json",
           BASE / "candidates/jr-hokkaido-ozora-tokachi-up-rest-20260930.json")
LATER_COLUMNS = (
    BASE / "candidates/jr-hokkaido-hokuto13-15-17-19-20260930.json",
    BASE / "candidates/jr-hokkaido-lilac25-27-20260930.json",
    BASE / "candidates/jr-hokkaido-s111-kamui18-lilac20-22-24-20260930.json",
)


class HokkaidoLineColumnsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reviewed = json.loads(CANDIDATE.read_text(encoding="utf-8"))["trips"]
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.station_names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_all_printed_fields_survive_materialization(self):
        self.assertEqual(len(self.reviewed), 29)
        self.assertEqual(sum(len(trip["stops"]) for trip in self.reviewed), 322)
        actual = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        for reviewed in self.reviewed:
            with self.subTest(train=reviewed["train_number"]):
                trip = actual[reviewed["trip_id"]]
                self.assertEqual((trip["train_number"], trip["public_number"]),
                                 (reviewed["train_number"], reviewed["public_number"]))
                self.assertEqual([[self.station_names[row["station_id"]], row["arrival_time"], row["departure_time"]]
                                  for row in trip["stop_times"]], reviewed["stops"])
                self.assertEqual({self.station_names[row["station_id"]]: row["platform"]
                                  for row in trip["stop_times"] if row["platform"] is not None},
                                 reviewed["printed_platforms"])
                self.assertTrue({row[0] for row in reviewed["stops"]}.isdisjoint(reviewed["pass_through_names"]))
                source = sources[reviewed["source_id"]]
                self.assertEqual(source["url_or_locator"], reviewed["source_url"])
                self.assertEqual(source["effective_date"], "2026-09-30")
                self.assertEqual(source["issue"], "JR時刻表 令和8年10月号")

    def test_exact_day_and_corrected_hokuto_three(self):
        for day in ("2026-09-29", "2026-10-01"):
            listed = {trip["trip_id"] for trip in timetable.materialize(self.data, day)}
            self.assertFalse(listed & {trip["trip_id"] for trip in self.reviewed})
        hokuto = next(trip for trip in self.reviewed if trip["train_number"] == "3D")
        self.assertEqual(hokuto["stops"][9:12],
                         [["登別", None, "10:15"], ["白老", None, "10:27"], ["苫小牧", None, "10:41"]])
        self.assertTrue({"登別", "白老"}.isdisjoint(hokuto["pass_through_names"]))
        self.assertEqual({trip["train_number"] for trip in self.reviewed
                          if trip["source_url"].endswith("s=110")},
                         {"3005M", "3011M", "3013M", "3017M", "2019M"})
        self.assertEqual({trip["train_number"] for trip in self.reviewed
                          if trip["source_url"].endswith("s=111")},
                         {"2006M", "2010M", "3012M", "3014M", "3016M"})

    def test_independently_rechecked_kamui21_and_lilac23(self):
        candidate = json.loads(ADDITIONAL.read_text(encoding="utf-8"))
        self.assertEqual(candidate["candidate_status"], "visually_reviewed")
        self.assertEqual([row["train_number"] for row in candidate["trips"]], ["2021M", "3023M"])
        self.assertEqual([len(row["stops"]) for row in candidate["trips"]], [7, 7])
        actual = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        for reviewed in candidate["trips"]:
            with self.subTest(train=reviewed["train_number"]):
                trip = actual[reviewed["trip_id"]]
                self.assertEqual((trip["train_number"], trip["public_number"]),
                                 (reviewed["train_number"], reviewed["public_number"]))
                self.assertEqual([[self.station_names[stop["station_id"]], stop["arrival_time"], stop["departure_time"]]
                                  for stop in trip["stop_times"]], reviewed["stops"])
                self.assertEqual({self.station_names[stop["station_id"]]: stop["platform"]
                                  for stop in trip["stop_times"] if stop["platform"] is not None},
                                 reviewed["printed_platforms"])
        for day in ("2026-09-29", "2026-10-01"):
            self.assertFalse({row["trip_id"] for row in candidate["trips"]}
                             & {row["trip_id"] for row in timetable.materialize(self.data, day)})

    def test_ozora_two_exact_date_column(self):
        candidate = json.loads(OZORA_UP.read_text(encoding="utf-8"))
        self.assertEqual(candidate["candidate_status"], "visually_reviewed")
        reviewed, = candidate["trips"]
        self.assertEqual((reviewed["train_number"], len(reviewed["stops"])), ("4002D", 15))
        actual = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        trip = actual[reviewed["trip_id"]]
        self.assertEqual((trip["train_number"], trip["public_number"]), ("4002D", "2"))
        self.assertEqual([[self.station_names[stop["station_id"]], stop["arrival_time"], stop["departure_time"]]
                          for stop in trip["stop_times"]], reviewed["stops"])
        self.assertEqual({self.station_names[stop["station_id"]]: stop["platform"]
                          for stop in trip["stop_times"] if stop["platform"] is not None},
                         reviewed["printed_platforms"])
        for day in ("2026-09-29", "2026-10-01"):
            self.assertNotIn(reviewed["trip_id"],
                             {row["trip_id"] for row in timetable.materialize(self.data, day)})

    def test_remaining_up_columns_are_source_pinned(self):
        reviewed = [trip for path in MORE_UP
                    for trip in json.loads(path.read_text(encoding="utf-8"))["trips"]]
        self.assertEqual((len(reviewed), sum(len(trip["stops"]) for trip in reviewed)), (10, 102))
        self.assertEqual(len({trip["train_number"] for trip in reviewed}), 10)
        actual = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        for item in reviewed:
            with self.subTest(train=item["train_number"]):
                trip = actual[item["trip_id"]]
                self.assertEqual((trip["train_number"], trip["public_number"]),
                                 (item["train_number"], item["public_number"]))
                self.assertEqual([[self.station_names[stop["station_id"]], stop["arrival_time"], stop["departure_time"]]
                                  for stop in trip["stop_times"]], item["stops"])
                self.assertEqual({self.station_names[stop["station_id"]]: stop["platform"]
                                  for stop in trip["stop_times"] if stop["platform"] is not None},
                                 item["printed_platforms"])
                self.assertEqual(sources[item["source_id"]]["url_or_locator"], item["source_url"])
                self.assertEqual(sources[item["source_id"]]["effective_date"], "2026-09-30")
        for day in ("2026-09-29", "2026-10-01"):
            listed = {trip["trip_id"] for trip in timetable.materialize(self.data, day)}
            self.assertFalse(listed & {trip["trip_id"] for trip in reviewed})

    def test_later_hokkaido_columns_are_source_pinned(self):
        reviewed = [trip for path in LATER_COLUMNS
                    for trip in json.loads(path.read_text(encoding="utf-8"))["trips"]]
        self.assertEqual((len(reviewed), sum(len(trip["stops"]) for trip in reviewed)), (10, 105))
        actual = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        for item in reviewed:
            with self.subTest(train=item["train_number"]):
                trip = actual[item["trip_id"]]
                self.assertEqual((trip["train_number"], trip["public_number"]),
                                 (item["train_number"], item["public_number"]))
                self.assertEqual([[self.station_names[stop["station_id"]], stop["arrival_time"], stop["departure_time"]]
                                  for stop in trip["stop_times"]], item["stops"])
                self.assertEqual({self.station_names[stop["station_id"]]: stop.get("platform")
                                  for stop in trip["stop_times"] if stop.get("platform") is not None},
                                 item["printed_platforms"])
                self.assertEqual(sources[item["source_id"]]["url_or_locator"], item["source_url"])
        for day in ("2026-09-29", "2026-10-01"):
            listed = {trip["trip_id"] for trip in timetable.materialize(self.data, day)}
            self.assertFalse(listed & {trip["trip_id"] for trip in reviewed})


if __name__ == "__main__":
    unittest.main()
