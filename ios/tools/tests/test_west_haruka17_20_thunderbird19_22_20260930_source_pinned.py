"""The September 30 West batch stays tied to four selected official train pages."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka17-20-thunderbird19-22-20260930"
DAY = "2026-09-30"
EXPECTED = {
    "jr-west.haruka.17.2026-09-30": (
        "256921", "1017M", "17", False,
        [("京都", None, "10:00", "30"), ("新大阪", "10:27", "10:28", "3"),
         ("大阪", "10:32", "10:33", "21"), ("天王寺", "10:45", "10:47", "15"),
         ("関西空港", "11:24", None, None)]),
    "jr-west.haruka.18.2026-09-30": (
        "257191", "1018M", "18", False,
        [("関西空港", None, "11:14", None), ("天王寺", "11:48", "11:50", "18"),
         ("大阪", "12:01", "12:02", "24"), ("新大阪", "12:06", "12:07", "1"),
         ("京都", "12:34", None, "30")]),
    "jr-west.haruka.19.2026-09-30": (
        "256941", "1019M", "19", False,
        [("京都", None, "10:30", "30"), ("新大阪", "10:57", "10:58", "3"),
         ("大阪", "11:02", "11:03", "21"), ("天王寺", "11:15", "11:17", "15"),
         ("関西空港", "11:50", None, None)]),
    "jr-west.haruka.20.2026-09-30": (
        "257201", "1020M", "20", False,
        [("関西空港", None, "11:44", None), ("天王寺", "12:18", "12:20", "18"),
         ("大阪", "12:31", "12:32", "24"), ("新大阪", "12:36", "12:37", "1"),
         ("京都", "13:04", None, "30")]),
    "jr-west.thunderbird.19.2026-09-30": (
        "257771", "4019M", "19", True,
        [("大阪", None, "11:12", "11"), ("新大阪", "11:15", "11:16", "4"),
         ("京都", "11:39", "11:40", "0"), ("敦賀", "12:33", None, "32")]),
    "jr-west.thunderbird.20.2026-09-30": (
        "258071", "4020M", "20", True,
        [("敦賀", None, "12:14", "33"), ("京都", "13:09", "13:10", "7"),
         ("新大阪", "13:32", "13:32", "9"), ("大阪", "13:36", None, "3")]),
    "jr-west.thunderbird.21.2026-09-30": (
        "257781", "4021M", "21", True,
        [("大阪", None, "12:12", "11"), ("新大阪", "12:15", "12:16", "4"),
         ("京都", "12:39", "12:40", "0"), ("敦賀", "13:33", None, "32")]),
    "jr-west.thunderbird.22.2026-09-30": (
        "258081", "4022M", "22", True,
        [("敦賀", None, "13:14", "33"), ("京都", "14:09", "14:10", "7"),
         ("新大阪", "14:32", "14:32", "9"), ("大阪", "14:36", None, "3")]),
}
LABELS = {
    ("haruka", 17): "土曜・休日運休", ("haruka", 18): "毎日運転",
    ("haruka", 19): "毎日運転", ("haruka", 20): "毎日運転",
    ("thunderbird", 19): "毎日運転", ("thunderbird", 20): "毎日運転",
    ("thunderbird", 21): "毎日運転", ("thunderbird", 22): "毎日運転",
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
        self.assertEqual(len(stops), 36)
        self.assertEqual(len(sources), 8)
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
                self.assertEqual(entry["operation_label"], LABELS[(entry["service_id"], int(public))])
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
                self.assertIn("full route line IDs", entry["route_evidence"])
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
