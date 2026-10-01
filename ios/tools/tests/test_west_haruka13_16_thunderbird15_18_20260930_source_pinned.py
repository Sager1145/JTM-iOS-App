"""The September 30 West batch stays tied to four selected official train pages."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka13-16-thunderbird15-18-20260930"
DAY = "2026-09-30"
EXPECTED = {
    "jr-west.haruka.13.2026-09-30": (
        "192701", "1013M", "13", False,
        [("京都", None, "08:45", "30"), ("新大阪", "09:13", "09:13", "3"),
         ("大阪", "09:18", "09:19", "21"), ("天王寺", "09:31", "09:32", "15"),
         ("関西空港", "10:05", None, None)]),
    "jr-west.haruka.14.2026-09-30": (
        "257171", "1014M", "14", False,
        [("関西空港", None, "10:16", None), ("天王寺", "10:48", "10:50", "18"),
         ("大阪", "11:01", "11:02", "24"), ("新大阪", "11:06", "11:07", "1"),
         ("京都", "11:34", None, "30")]),
    "jr-west.haruka.15.2026-09-30": (
        "661", "1015M", "15", False,
        [("京都", None, "09:30", "30"), ("新大阪", "09:57", "09:58", "3"),
         ("大阪", "10:02", "10:03", "21"), ("天王寺", "10:15", "10:17", "15"),
         ("関西空港", "10:54", None, None)]),
    "jr-west.haruka.16.2026-09-30": (
        "257181", "1016M", "16", False,
        [("関西空港", None, "10:44", None), ("天王寺", "11:18", "11:20", "18"),
         ("大阪", "11:31", "11:32", "24"), ("新大阪", "11:36", "11:37", "1"),
         ("京都", "12:04", None, "30")]),
    "jr-west.thunderbird.15.2026-09-30": (
        "257751", "4015M", "15", True,
        [("大阪", None, "10:09", "11"), ("新大阪", "10:12", "10:13", "4"),
         ("京都", "10:36", "10:37", "0"), ("敦賀", "11:30", None, "32")]),
    "jr-west.thunderbird.16.2026-09-30": (
        "258051", "4016M", "16", True,
        [("敦賀", None, "10:44", "33"), ("京都", "11:39", "11:40", "7"),
         ("新大阪", "12:02", "12:02", "9"), ("大阪", "12:06", None, "3")]),
    "jr-west.thunderbird.17.2026-09-30": (
        "257761", "4017M", "17", True,
        [("大阪", None, "10:42", "11"), ("新大阪", "10:45", "10:46", "4"),
         ("京都", "11:09", "11:10", "0"), ("敦賀", "12:03", None, "31")]),
    "jr-west.thunderbird.18.2026-09-30": (
        "258061", "4018M", "18", True,
        [("敦賀", None, "11:14", "33"), ("京都", "12:09", "12:10", "7"),
         ("新大阪", "12:32", "12:32", "9"), ("大阪", "12:36", None, "3")]),
}
LABELS = {
    ("haruka", 13): "土曜・休日運休", ("haruka", 14): "毎日運転",
    ("haruka", 15): "土曜・休日運休", ("haruka", 16): "毎日運転",
    ("thunderbird", 15): "毎日運転", ("thunderbird", 16): "毎日運転",
    ("thunderbird", 17): "毎日運転", ("thunderbird", 18): "毎日運転",
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
