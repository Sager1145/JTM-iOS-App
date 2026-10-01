"""Eight September 30 JR West train pages pin passenger calls and platforms."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka53-60-20260930"
DAY = "2026-09-30"
# Each clock is arrival/departure/platform; '-' means the printed cell is empty.
EXPECTED = {
    ('haruka', 53): ('257131', '京都:-/19:00/30 新大阪:19:27/19:28/3 大阪:19:32/19:33/21 天王寺:19:49/19:50/15 和泉府中:20:06/20:07/- 日根野:20:16/20:17/- 関西空港:20:25/-/-'),
    ('haruka', 54): ('192741', '関西空港:-/20:16/- 天王寺:20:48/20:49/18 大阪:21:01/21:02/24 新大阪:21:06/21:07/1 高槻:21:19/21:19/- 京都:21:32/21:34/0 山科:21:39/21:39/- 大津:21:43/21:44/- 石山:21:48/21:48/- 南草津:21:52/21:53/- 草津:21:56/21:56/- 守山:22:00/22:00/- 野洲:22:04/-/-'),
    ('haruka', 55): ('129411', '京都:-/19:30/30 新大阪:19:57/19:58/3 大阪:20:02/20:03/21 天王寺:20:18/20:20/15 和泉府中:20:37/20:37/- 日根野:20:46/20:47/- 関西空港:20:59/-/-'),
    ('haruka', 56): ('257381', '関西空港:-/20:46/- 天王寺:21:18/21:19/18 大阪:21:31/21:32/24 新大阪:21:36/21:37/1 高槻:21:49/21:49/- 京都:22:03/-/0'),
    ('haruka', 57): ('257151', '京都:-/20:00/30 新大阪:20:27/20:28/3 大阪:20:32/20:33/21 天王寺:20:48/20:50/15 和泉府中:21:07/21:07/- 日根野:21:16/21:17/- 関西空港:21:27/-/-'),
    ('haruka', 58): ('129471', '関西空港:-/21:25/- 天王寺:21:57/21:59/18 大阪:22:10/22:11/24 新大阪:22:15/22:17/1 京都:22:42/-/30'),
    ('haruka', 59): ('129431', '京都:-/20:30/30 新大阪:20:57/20:58/3 大阪:21:02/21:03/21 天王寺:21:18/21:21/15 和泉府中:21:37/21:38/- 日根野:21:47/21:49/- 関西空港:21:59/-/-'),
    ('haruka', 60): ('129481', '関西空港:-/22:16/- 天王寺:22:49/22:50/18 大阪:23:03/23:04/24 新大阪:23:08/23:09/1 京都:23:32/-/30'),
}
WEEKDAY_ONLY = {('haruka', 54), ('haruka', 57), ('haruka', 53), ('haruka', 56), ('haruka', 59), ('haruka', 55)}


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
        self.assertEqual(len(candidate["trips"]), 8)
        self.assertEqual(len(sources), 8)
        self.assertEqual(len(stops), 57)
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
                                 len(printed_calls(EXPECTED[(service, number)][1])))
                self.assertNotIn(tid, previous)


if __name__ == "__main__":
    unittest.main()
