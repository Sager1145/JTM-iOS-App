"""Hitachi 26 September 30 page pins stops, platforms and planned seat classes."""

import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
TRIP = "jr-east.hitachi.26.2026-09-18"
SOURCE = "jr-east-hitachi26-202609"
URL = "https://timetables.jreast.co.jp/2610/train/095/098731.html"
PRINTED = [
    ("いわき", None, "18:17", None), ("湯本", "18:23", "18:23", None),
    ("泉", "18:28", "18:28", None), ("勿来", "18:36", "18:37", None),
    ("高萩", "18:49", "18:50", None), ("日立", "19:00", "19:00", None),
    ("常陸多賀", "19:04", "19:05", None), ("大甕", "19:08", "19:09", None),
    ("東海", "19:13", "19:14", None), ("勝田", "19:20", "19:21", None),
    ("水戸", "19:26", "19:27", "７"), ("上野", "20:36", "20:37", "８"),
    ("東京", "20:42", "20:44", "９"), ("品川", "20:53", None, "９"),
]


class EastHitachi26SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_exact_day_printed_stops_and_platforms(self):
        day = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        trip = day[TRIP]
        self.assertEqual((trip["public_number"], trip["train_number"]), ("26", "26M"))
        self.assertEqual(
            [(self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"], stop["platform"])
             for stop in trip["stop_times"]], PRINTED,
        )
        source = next(row for row in self.data["source_documents"] if row["source_id"] == SOURCE)
        self.assertEqual(source["url_or_locator"], URL)

    def test_exact_day_planned_equipment(self):
        candidate = json.loads((BASE / "candidates/jr-east-hitachi26-equipment-20260930.json").read_text())
        self.assertEqual(candidate["printed_equipment"],
                         ["座席未指定券", "グリーン車指定席", "普通車全車指定席"])
        formations = [row for row in self.data["trip_formations"]
                      if row["trip_id"] == TRIP and row["service_date"] == "2026-09-30"]
        self.assertEqual(len(formations), 1)
        formation = formations[0]
        self.assertEqual((formation["source_id"], formation["evidence_kind"]), (SOURCE, "planned"))
        self.assertIs(formation["all_reserved"], True)
        self.assertIs(formation["green_car_available"], True)
        for field in ("car_count", "vehicle_series", "formation_label", "reserved_seat_capacity"):
            self.assertIsNone(formation.get(field))


if __name__ == "__main__":
    unittest.main()
