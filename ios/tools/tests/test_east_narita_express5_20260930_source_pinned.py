"""Exact-date Narita Express 5 clocks and Tokyo coupling stay source-pinned."""

import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-east-narita-express5-20260930.json"
SOURCE = "jr-east-narita-express5-20260930"


class NaritaExpress5Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reviewed = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}
        cls.trips = {row["trip_id"]: row for row in timetable.materialize(cls.data, "2026-09-30")}

    def test_official_date_and_complete_2005m_column(self):
        reviewed = self.reviewed["trips"][0]
        actual = self.trips[reviewed["trip_id"]]
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        self.assertEqual(sources[SOURCE]["url_or_locator"], self.reviewed["source_url"])
        self.assertEqual(actual["train_number"], "2005M")
        self.assertEqual(len(actual["stop_times"]), 9)
        self.assertEqual(
            [(self.names[row["station_id"]], row["arrival_time"], row["departure_time"], row["platform"])
             for row in actual["stop_times"]],
            [("空港第2ビル" if name == "空港第２ビル" else name, arrival, departure, platform)
             for name, arrival, departure, platform, _ in reviewed["stops"]],
        )

    def test_2205m_unprinted_cells_and_coupling(self):
        ofuna, shinjuku = self.reviewed["trips"]
        actual = self.trips[shinjuku["trip_id"]]
        stops = actual["stop_times"]
        self.assertEqual(actual["train_number"], "2205M")
        self.assertEqual([(row["arrival_time"], row["departure_time"]) for row in stops[:4]],
                         [(None, "07:07"), ("07:12", "07:13"), (None, None), ("07:29", None)])
        self.assertEqual(stops[2]["call_type"], "pass")
        self.assertTrue(all(row["arrival_time"] is None and row["departure_time"] is None
                            and row["platform"] is None for row in stops[4:]))
        relations = {(row["trip_id"], row["related_trip_id"], row["from_sequence"], row["to_sequence"])
                     for row in self.data["trip_relations"] if row["source_id"] == SOURCE}
        self.assertEqual(relations, {
            (ofuna["trip_id"], shinjuku["trip_id"], 6, 9),
            (shinjuku["trip_id"], ofuna["trip_id"], 4, 7),
        })
        completeness = {(row["entity_id"], row["dimension"]): row["status"]
                        for row in self.data["fact_completeness"] if row["entity_id"] in
                        {ofuna["trip_id"], shinjuku["trip_id"]}}
        self.assertEqual(completeness[(ofuna["trip_id"], "times")], "verified")
        self.assertEqual(completeness[(shinjuku["trip_id"], "times")], "partial")

    def test_single_day_scope_and_no_invented_route(self):
        ids = {trip["trip_id"] for trip in self.reviewed["trips"]}
        for day in ("2026-09-29", "2026-10-01"):
            self.assertFalse(ids & {trip["trip_id"] for trip in timetable.materialize(self.data, day)})
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_operator_segments"]))


if __name__ == "__main__":
    unittest.main()
