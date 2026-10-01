"""The September 30 West batch stays tied to four selected official train pages."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka11-12-thunderbird13-14-20260930"
DAY = "2026-09-30"
EXPECTED = {
    "jr-west.haruka.11.2026-09-30": (
        "192681", "1011M", "11", False,
        [("野洲", None, "07:51", None), ("守山", "07:54", "07:55", None),
         ("草津", "07:58", "07:59", None), ("南草津", "08:01", "08:02", None),
         ("石山", "08:06", "08:07", None), ("大津", "08:11", "08:11", None),
         ("山科", "08:15", "08:16", None), ("京都", "08:20", "08:22", "7"),
         ("新大阪", "08:46", "08:47", "3"), ("大阪", "08:51", "08:52", "21"),
         ("天王寺", "09:03", "09:04", "15"), ("関西空港", "09:36", None, None)]),
    "jr-west.haruka.12.2026-09-30": (
        "581", "1012M", "12", False,
        [("関西空港", None, "09:42", None), ("日根野", "09:50", "09:51", None),
         ("和泉府中", "10:01", "10:02", None), ("天王寺", "10:18", "10:20", "18"),
         ("大阪", "10:31", "10:32", "24"), ("新大阪", "10:36", "10:37", "1"),
         ("京都", "11:04", None, "30")]),
    "jr-west.thunderbird.13.2026-09-30": (
        "257741", "4013M", "13", True,
        [("大阪", None, "09:41", "11"), ("新大阪", "09:44", "09:45", "4"),
         ("京都", "10:07", "10:09", "0"), ("敦賀", "11:02", None, "31")]),
    "jr-west.thunderbird.14.2026-09-30": (
        "258031", "4014M", "14", True,
        [("敦賀", None, "10:14", "33"), ("京都", "11:09", "11:10", "7"),
         ("新大阪", "11:32", "11:32", "9"), ("大阪", "11:36", None, "3")]),
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class WestSeptember30BatchTests(unittest.TestCase):
    def test_official_sources_and_calls(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        sources = {row["source_id"]: row for row in rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        formations = {row["trip_id"]: row for row in rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")}
        self.assertEqual(candidate["service_date"], DAY)
        self.assertEqual(set(trips), set(EXPECTED))
        self.assertEqual(len(stops), 27)
        self.assertEqual(len(sources), 4)
        for entry in candidate["trips"]:
            tid = entry["trip_id"]
            page, number, public, reserved, expected_calls = EXPECTED[tid]
            with self.subTest(trip=tid):
                source = sources[entry["source_id"]]
                self.assertEqual(source["url_or_locator"],
                                 f"https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930")
                self.assertEqual((source["effective_date"], source["redistribution_status"]),
                                 (DAY, "verification_only"))
                self.assertEqual((trips[tid]["train_number"], trips[tid]["public_number"]),
                                 (number, public))
                calls = sorted((row for row in stops if row["trip_id"] == tid),
                               key=lambda row: row["stop_sequence"])
                self.assertEqual([(stop["name"], stop["arrival"], stop["departure"], stop["platform"])
                                  for stop in entry["stops"]], expected_calls)
                self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                                  for row in calls], [call[1:] for call in expected_calls])
                formation = formations[tid]
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["all_reserved"], formation["green_car_available"]),
                                 (DAY, "planned", reserved, True))
                self.assertEqual(formation.get("car_count"), 9)
                self.assertNotIn("vehicle_series", formation)
                self.assertIn("Full route line IDs", entry["route_evidence"])
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}").exists())

    def test_materializes_selected_day_only(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        selected = {trip["trip_id"]: trip for trip in timetable.materialize(data, DAY)}
        previous = {trip["trip_id"] for trip in timetable.materialize(data, "2026-09-29")}
        for tid, (_, _, _, _, calls) in EXPECTED.items():
            with self.subTest(trip=tid):
                self.assertEqual(len(selected[tid]["stop_times"]), len(calls))
                self.assertNotIn(tid, previous)


if __name__ == "__main__":
    unittest.main()
