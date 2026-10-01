"""Exact-date Kuroshio 23–26 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio23-26-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {
    23: ('100371', '2073M', '京都:-/17:47/7 新大阪:18:12/18:13/2 大阪:18:17/18:18/21 天王寺:18:33/18:35/15 和泉府中:18:52/18:52/- 日根野:19:02/19:03/- 和泉砂川:19:08/19:08/- 和歌山:19:23/19:26/4 海南:19:35/19:36/- 箕島:19:47/19:48/- 藤並:19:54/19:55/- 湯浅:19:58/19:59/- 御坊:20:12/20:13/- 南部:20:36/20:36/- 紀伊田辺:20:43/20:44/- 白浜:20:55/-/-'),
    24: ('183851', '2074M', '白浜:-/14:20/- 紀伊田辺:14:30/14:32/- 南部:14:38/14:38/- 御坊:15:02/15:03/- 湯浅:15:16/15:16/- 藤並:15:20/15:20/- 箕島:15:27/15:27/- 海南:15:39/15:39/- 和歌山:15:48/15:50/1 日根野:16:08/16:08/- 天王寺:16:33/16:35/18 大阪:16:46/16:47/24 新大阪:16:51/-/2'),
    25: ('144361', '2075M', '新大阪:-/18:43/2 大阪:18:47/18:48/21 天王寺:19:03/19:05/15 和泉府中:19:22/19:22/- 日根野:19:31/19:32/- 和泉砂川:19:37/19:38/- 和歌山:19:53/-/4'),
    26: ('183831', '76M', '新宮:-/13:29/- 紀伊勝浦:13:45/13:46/- 太地:13:52/13:53/- 古座:14:11/14:11/- 串本:14:19/14:20/- 周参見:14:52/14:53/- 白浜:15:18/15:26/- 紀伊田辺:15:36/15:37/- 御坊:16:06/16:07/- 海南:16:39/16:39/- 和歌山:16:48/16:50/1 日根野:17:07/17:08/- 天王寺:17:33/17:35/18 大阪:17:46/17:47/24 新大阪:17:51/-/2'),
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
                         (DAY, 4, 4, 51))
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
                                 "土曜・休日運休" if public in (23, 25, 26) else "毎日運転")
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
