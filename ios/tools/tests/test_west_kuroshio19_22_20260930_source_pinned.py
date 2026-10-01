"""Exact-date Kuroshio 19–22 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio19-22-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {
    19: ('18841', '2069M', '新大阪:-/16:13/2 大阪:16:17/16:18/21 天王寺:16:31/16:32/15 日根野:16:57/16:58/- 和泉砂川:17:02/17:03/- 和歌山:17:18/17:20/4 海南:17:28/17:29/- 箕島:17:40/17:41/- 藤並:17:47/17:47/- 湯浅:17:51/17:51/- 御坊:18:04/18:05/- 南部:18:28/18:28/- 紀伊田辺:18:35/18:36/- 白浜:18:47/-/-'),
    20: ('183811', '2070M', '白浜:-/12:20/- 紀伊田辺:12:30/12:32/- 南部:12:38/12:38/- 御坊:13:02/13:03/- 湯浅:13:16/13:16/- 藤並:13:20/13:20/- 箕島:13:27/13:27/- 海南:13:39/13:39/- 和歌山:13:48/13:50/1 日根野:14:08/14:08/- 天王寺:14:33/14:35/18 大阪:14:46/14:47/24 新大阪:14:51/-/2'),
    21: ('50631', '71M', '新大阪:-/17:13/2 大阪:17:17/17:18/21 天王寺:17:33/17:35/15 和泉府中:17:52/17:52/- 日根野:18:02/18:02/- 和泉砂川:18:07/18:07/- 和歌山:18:22/18:25/4 海南:18:33/18:34/- 箕島:18:45/18:46/- 藤並:18:52/18:53/- 湯浅:18:56/18:56/- 御坊:19:10/19:10/- 南部:19:33/19:33/- 紀伊田辺:19:40/19:42/- 白浜:19:54/19:56/- 周参見:20:17/20:17/- 串本:20:50/20:50/- 古座:20:59/20:59/- 太地:21:16/21:16/- 紀伊勝浦:21:23/21:23/- 新宮:21:41/-/-'),
    22: ('183821', '72M', '新宮:-/11:27/- 紀伊勝浦:11:49/11:49/- 太地:11:56/11:56/- 古座:12:14/12:14/- 串本:12:22/12:23/- 周参見:12:58/12:58/- 白浜:13:19/13:26/- 紀伊田辺:13:36/13:37/- 御坊:14:06/14:07/- 海南:14:39/14:39/- 和歌山:14:48/14:50/1 日根野:15:08/15:08/- 天王寺:15:33/15:35/18 大阪:15:46/15:47/24 新大阪:15:51/-/2'),
}
PRINTED_EQUIPMENT = ["女性専用席があります", "グリーン車指定席", "普通車全車指定席"]


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


class KuroshioSeptember30BatchTests(unittest.TestCase):
    def test_official_pages_and_every_printed_call(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        sources = {row["source_id"]: row for row in rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        formations = {row["trip_id"]: row for row in rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")}
        self.assertEqual((candidate["service_date"], len(candidate["trips"]), len(sources), len(stops)),
                         (DAY, 4, 4, 63))
        for entry in candidate["trips"]:
            public = int(entry["public_number"])
            page, train_number, expected = EXPECTED[public]
            tid = entry["trip_id"]
            with self.subTest(trip=tid):
                self.assertEqual((entry["train_number"], entry["source_url"]),
                                 (train_number, f"https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930"))
                self.assertEqual((sources[entry["source_id"]]["url_or_locator"],
                                  sources[entry["source_id"]]["effective_date"]),
                                 (entry["source_url"], DAY))
                self.assertEqual(entry["operation_label"],
                                 "土曜・休日運休" if public == 21 else "毎日運転")
                self.assertEqual(entry["printed_equipment"], PRINTED_EQUIPMENT)
                self.assertEqual((trips[tid]["train_number"], trips[tid]["public_number"]),
                                 (train_number, str(public)))
                expected_calls = printed_calls(expected)
                self.assertEqual([(stop["name"], stop["arrival"], stop["departure"], stop["platform"])
                                  for stop in entry["stops"]], expected_calls)
                actual = sorted((stop for stop in stops if stop["trip_id"] == tid),
                                key=lambda stop: stop["stop_sequence"])
                self.assertEqual([(stop["arrival_time"], stop["departure_time"], stop["platform"])
                                  for stop in actual], [call[1:] for call in expected_calls])
                formation = formations[tid]
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["all_reserved"], formation["green_car_available"]),
                                 (DAY, "planned", True, True))
                for field in ("formation_label", "car_count", "reserved_seat_capacity", "vehicle_series"):
                    self.assertNotIn(field, formation)
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}").exists())

    def test_only_selected_date_materializes(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        selected = {trip["trip_id"]: trip for trip in timetable.materialize(data, DAY)}
        previous = {trip["trip_id"] for trip in timetable.materialize(data, "2026-09-29")}
        for number, (_, _, calls) in EXPECTED.items():
            tid = f"jr-west.kuroshio.{number}.{DAY}"
            self.assertEqual(len(selected[tid]["stop_times"]), len(printed_calls(calls)))
            self.assertNotIn(tid, previous)


if __name__ == "__main__":
    unittest.main()
