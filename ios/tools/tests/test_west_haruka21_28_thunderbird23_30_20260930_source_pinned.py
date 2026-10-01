"""Sixteen September 30 JR West train pages pin passenger calls and platforms."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka21-28-thunderbird23-30-20260930"
DAY = "2026-09-30"
# Each clock is arrival/departure/platform; '-' means the printed cell is empty.
EXPECTED = {
    ("haruka", 21): ("256951", "京都:-/11:00/30 新大阪:11:27/11:28/3 大阪:11:32/11:33/21 天王寺:11:45/11:47/15 関西空港:12:20/-/-"),
    ("haruka", 22): ("257211", "関西空港:-/12:14/- 天王寺:12:48/12:50/18 大阪:13:01/13:02/24 新大阪:13:06/13:07/1 京都:13:34/-/30"),
    ("haruka", 23): ("256961", "京都:-/11:30/30 新大阪:11:57/11:58/3 大阪:12:02/12:03/21 天王寺:12:15/12:17/15 関西空港:12:50/-/-"),
    ("haruka", 24): ("257221", "関西空港:-/12:44/- 天王寺:13:18/13:20/18 大阪:13:31/13:32/24 新大阪:13:36/13:37/1 京都:14:04/-/30"),
    ("haruka", 25): ("256971", "京都:-/12:00/30 新大阪:12:27/12:28/3 大阪:12:32/12:33/21 天王寺:12:45/12:47/15 関西空港:13:20/-/-"),
    ("haruka", 26): ("257231", "関西空港:-/13:14/- 天王寺:13:48/13:50/18 大阪:14:01/14:02/24 新大阪:14:06/14:07/1 京都:14:34/-/30"),
    ("haruka", 27): ("256981", "京都:-/12:30/30 新大阪:12:57/12:58/3 大阪:13:02/13:03/21 天王寺:13:15/13:17/15 関西空港:13:50/-/-"),
    ("haruka", 28): ("257241", "関西空港:-/13:44/- 天王寺:14:18/14:20/18 大阪:14:31/14:32/24 新大阪:14:36/14:37/1 京都:15:04/-/30"),
    ("thunderbird", 23): ("257791", "大阪:-/12:42/11 新大阪:12:45/12:46/4 京都:13:09/13:10/0 敦賀:14:03/-/32"),
    ("thunderbird", 24): ("258091", "敦賀:-/14:14/33 京都:15:09/15:10/7 新大阪:15:32/15:32/9 大阪:15:36/-/3"),
    ("thunderbird", 25): ("257801", "大阪:-/13:12/11 新大阪:13:15/13:16/4 京都:13:39/13:40/0 敦賀:14:33/-/31"),
    ("thunderbird", 26): ("258101", "敦賀:-/15:14/33 京都:16:09/16:10/7 新大阪:16:32/16:32/9 大阪:16:36/-/3"),
    ("thunderbird", 27): ("257811", "大阪:-/14:12/11 新大阪:14:15/14:16/4 京都:14:39/14:40/0 敦賀:15:33/-/31"),
    ("thunderbird", 28): ("258111", "敦賀:-/15:44/33 京都:16:39/16:40/7 新大阪:17:02/17:02/9 大阪:17:06/-/3"),
    ("thunderbird", 29): ("257821", "大阪:-/15:09/11 新大阪:15:13/15:13/4 京都:15:36/15:37/0 敦賀:16:31/-/31"),
    ("thunderbird", 30): ("258121", "敦賀:-/16:13/33 京都:17:09/17:10/7 新大阪:17:32/17:32/9 大阪:17:36/-/3"),
}


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
        self.assertEqual(len(stops), 72)
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
                self.assertEqual(entry["operation_label"], "毎日運転")
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
                self.assertEqual(len(selected[tid]["stop_times"]), 5 if service == "haruka" else 4)
                self.assertNotIn(tid, previous)


if __name__ == "__main__":
    unittest.main()
