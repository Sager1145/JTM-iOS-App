"""Sixteen September 30 JR West train pages pin passenger calls and platforms."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka29-36-thunderbird31-38-20260930"
DAY = "2026-09-30"
# Each clock is arrival/departure/platform; '-' means the printed cell is empty.
EXPECTED = {
    ("haruka", 29): ("256991", "京都:-/13:00/30 新大阪:13:27/13:28/3 大阪:13:32/13:33/21 天王寺:13:45/13:47/15 関西空港:14:20/-/-"),
    ("haruka", 30): ("257251", "関西空港:-/14:14/- 天王寺:14:48/14:50/18 大阪:15:01/15:02/24 新大阪:15:06/15:07/1 京都:15:34/-/30"),
    ("haruka", 31): ("257001", "京都:-/13:30/30 新大阪:13:57/13:58/3 大阪:14:02/14:03/21 天王寺:14:15/14:17/15 関西空港:14:50/-/-"),
    ("haruka", 32): ("257261", "関西空港:-/14:44/- 天王寺:15:18/15:20/18 大阪:15:31/15:32/24 新大阪:15:36/15:37/1 京都:16:04/-/30"),
    ("haruka", 33): ("257011", "京都:-/14:00/30 新大阪:14:27/14:28/3 大阪:14:32/14:33/21 天王寺:14:45/14:47/15 関西空港:15:20/-/-"),
    ("haruka", 34): ("257271", "関西空港:-/15:14/- 天王寺:15:48/15:50/18 大阪:16:01/16:02/24 新大阪:16:06/16:07/1 京都:16:34/-/30"),
    ("haruka", 35): ("257021", "京都:-/14:30/30 新大阪:14:57/14:58/3 大阪:15:02/15:03/21 天王寺:15:15/15:17/15 関西空港:15:50/-/-"),
    ("haruka", 36): ("257281", "関西空港:-/15:44/- 天王寺:16:18/16:20/18 大阪:16:31/16:32/24 新大阪:16:36/16:37/1 京都:17:04/-/30"),
    ("thunderbird", 31): ("257831", "大阪:-/15:40/11 新大阪:15:43/15:44/4 京都:16:06/16:08/0 敦賀:17:00/-/32"),
    ("thunderbird", 32): ("258131", "敦賀:-/16:43/33 京都:17:39/17:40/7 新大阪:18:03/18:04/9 大阪:18:09/-/5"),
    ("thunderbird", 33): ("257841", "大阪:-/16:09/11 新大阪:16:12/16:13/4 京都:16:36/16:37/0 敦賀:17:30/-/31"),
    ("thunderbird", 34): ("258151", "敦賀:-/17:14/33 京都:18:09/18:10/7 新大阪:18:33/18:34/9 大阪:18:39/-/5"),
    ("thunderbird", 35): ("257851", "大阪:-/16:40/11 新大阪:16:43/16:44/4 京都:17:06/17:08/0 敦賀:18:00/-/32"),
    ("thunderbird", 36): ("258171", "敦賀:-/17:44/33 京都:18:39/18:40/7 新大阪:19:02/19:03/9 大阪:19:07/-/3"),
    ("thunderbird", 37): ("257861", "大阪:-/17:09/11 新大阪:17:13/17:13/4 京都:17:36/17:37/0 敦賀:18:30/-/31"),
    ("thunderbird", 38): ("258191", "敦賀:-/18:12/33 近江今津:18:35/18:36/- 堅田:18:54/18:55/- 京都:19:09/19:11/7 新大阪:19:32/19:33/9 大阪:19:37/-/3"),
}
WEEKDAY_ONLY = {("thunderbird", 32), ("thunderbird", 34), ("thunderbird", 36)}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def printed_calls(value):
    out = []
    for token in value.split():
        name, clocks = token.split(":", 1)
        arrival, departure, platform = clocks.split("/")
        out.append((name, None if arrival == "-" else arrival,
                    None if departure == "-" else departure,
                    None if platform == "-" else platform))
    return out


class WestSeptember30BatchTests(unittest.TestCase):
    def test_date_selected_sources_and_every_printed_call(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        sources = {row["source_id"]: row for row in rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        formations = {row["trip_id"]: row for row in rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")}
        self.assertEqual(candidate["service_date"], DAY)
        self.assertEqual(len(candidate["trips"]), 16)
        self.assertEqual(len(sources), 16)
        self.assertEqual(len(stops), 74)
        for entry in candidate["trips"]:
            service, public = entry["service_id"], int(entry["public_number"])
            key = (service, public)
            page, expected = EXPECTED[key]
            tid = entry["trip_id"]
            with self.subTest(trip=tid):
                self.assertEqual(entry["source_url"],
                                 f"https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930")
                self.assertEqual((sources[entry["source_id"]]["url_or_locator"],
                                  sources[entry["source_id"]]["effective_date"]),
                                 (entry["source_url"], DAY))
                self.assertEqual(entry["operation_label"],
                                 "土曜・休日運休" if key in WEEKDAY_ONLY else "毎日運転")
                self.assertEqual((trips[tid]["train_number"], trips[tid]["public_number"]),
                                 (f"{1000 + public if service == 'haruka' else 4000 + public}M",
                                  str(public)))
                expected_calls = printed_calls(expected)
                self.assertEqual([(stop["name"], stop["arrival"], stop["departure"], stop["platform"])
                                  for stop in entry["stops"]], expected_calls)
                actual = sorted((stop for stop in stops if stop["trip_id"] == tid),
                                key=lambda stop: stop["stop_sequence"])
                self.assertEqual([(stop["arrival_time"], stop["departure_time"], stop["platform"])
                                  for stop in actual], [call[1:] for call in expected_calls])
                formation = formations[tid]
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["car_count"], formation["green_car_available"]),
                                 (DAY, "planned", 9, True))
                self.assertEqual(formation["all_reserved"], service == "thunderbird")
                self.assertEqual(formation.get("reserved_seat_capacity"),
                                 546 if service == "thunderbird" else None)
                self.assertNotIn("vehicle_series", formation)
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}").exists())

    def test_only_selected_day_materializes(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        selected = {trip["trip_id"]: trip for trip in timetable.materialize(data, DAY)}
        previous = {trip["trip_id"] for trip in timetable.materialize(data, "2026-09-29")}
        for service, number in EXPECTED:
            tid = f"jr-west.{service}.{number}.{DAY}"
            with self.subTest(trip=tid):
                self.assertEqual(len(selected[tid]["stop_times"]),
                                 5 if service == "haruka" else 6 if number == 38 else 4)
                self.assertNotIn(tid, previous)


if __name__ == "__main__":
    unittest.main()
