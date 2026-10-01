"""Selected official JR Hokkaido columns supply only their exact-date clocks."""

import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-dated-stop-clocks-202609.json"


class HokkaidoDatedStopClocksTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.station_names = {r["station_id"]: r["name_snapshot"] for r in cls.data["station_identities"]}

    def test_all_printed_clocks_and_sides_match_each_selected_column(self):
        for reviewed in self.candidate["trips"]:
            with self.subTest(trip=reviewed["trip_id"]):
                occurrence = next(
                    trip for trip in timetable.materialize(self.data, reviewed["service_date"])
                    if trip["trip_id"] == reviewed["trip_id"]
                )
                self.assertEqual(occurrence["train_number"], reviewed["train_number"])
                actual = [
                    [self.station_names[s["station_id"]], s["arrival_time"], s["departure_time"]]
                    for s in occurrence["stop_times"]
                ]
                self.assertEqual(actual, reviewed["stops"])

    def test_overrides_are_restricted_to_four_dates_and_registered_sources(self):
        reviewed = {r["trip_id"]: r for r in self.candidate["trips"]}
        overrides = [r for r in self.data["trip_stop_time_overrides"] if r["trip_id"] in reviewed]
        self.assertEqual(len(overrides), 53)
        sources = {r["source_id"]: r for r in self.data["source_documents"]}
        for row in overrides:
            selected = reviewed[row["trip_id"]]
            self.assertEqual(row["service_date"], selected["service_date"])
            self.assertEqual(row["source_id"], selected["source_id"])
            self.assertEqual(sources[row["source_id"]]["url_or_locator"], selected["source_url"])
            self.assertEqual(sources[row["source_id"]]["effective_date"], selected["service_date"])

    def test_unprinted_sides_and_other_dates_remain_unknown(self):
        dated_id = "jr-hokkaido.niseko.sapporo-to-hakodate-dated-20260923.2026-09-23"
        dated = next(t for t in timetable.materialize(self.data, "2026-09-23") if t["trip_id"] == dated_id)
        self.assertIsNone(dated["stop_times"][1]["arrival_time"])
        self.assertEqual(dated["stop_times"][1]["departure_time"], "08:10")
        self.assertFalse(any(t["trip_id"] == dated_id for t in timetable.materialize(self.data, "2026-09-22")))
        general = next(t for t in timetable.materialize(self.data, "2026-09-21")
                       if t["trip_id"] == "jr-hokkaido.niseko.sapporo-to-hakodate.2026-09-05")
        self.assertIsNone(general["stop_times"][1]["departure_time"])

    def test_partial_time_status_explains_unprinted_arrivals(self):
        reviewed_ids = {r["trip_id"] for r in self.candidate["trips"]}
        statuses = [r for r in self.data["fact_completeness"]
                    if r["entity_id"] in reviewed_ids and r["dimension"] == "times"]
        self.assertEqual(len(statuses), 4)
        for row in statuses:
            self.assertEqual(row["status"], "partial")
            self.assertIn("unprinted arrival", row["notes"])
        queue = [r for r in self.data["research_queue"]
                 if r["entity_id"] in reviewed_ids and r["missing_dimension"] == "times"]
        self.assertEqual(len(queue), 4)
        self.assertTrue(all("unprinted arrival/departure" in r["notes"] for r in queue))


if __name__ == "__main__":
    unittest.main()
