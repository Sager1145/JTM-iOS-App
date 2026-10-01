"""Exact-date Kuroshio 32, 33, 35, and 36 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio32-33-35-36-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {32: ('100421', '2082M', '白浜:-/17:20/- 紀伊田辺:17:30/17:32/- 南部:17:38/17:38/- 御坊:18:02/18:03/- 湯浅:18:16/18:16/- 藤並:18:20/18:20/- 箕島:18:27/18:27/- 海南:18:39/18:39/- 和歌山:18:48/18:50/1 日根野:19:08/19:09/- 天王寺:19:33/19:35/18 大阪:19:46/19:47/24 新大阪:19:51/-/2'), 33: ('144421', '2083M', '新大阪:-/21:44/2 大阪:21:49/21:50/21 天王寺:22:04/22:06/15 和泉府中:22:24/22:24/- 日根野:22:34/22:35/- 和泉砂川:22:39/22:40/- 和歌山:22:55/-/5'), 35: ('144441', '2085M', '新大阪:-/22:47/2 大阪:22:51/22:52/21 天王寺:23:09/23:10/15 和泉府中:23:27/23:27/- 日根野:23:37/23:38/- 和泉砂川:23:42/23:43/- 和歌山:23:58/-/1'), 36: ('144551', '86M', '新宮:-/17:46/- 紀伊勝浦:18:03/18:04/- 太地:18:10/18:11/- 古座:18:28/18:29/- 串本:18:37/18:38/- 周参見:19:09/19:10/- 白浜:19:30/19:37/- 紀伊田辺:19:48/19:50/- 御坊:20:19/20:19/- 海南:20:51/20:52/- 和歌山:21:01/21:02/1 日根野:21:22/21:23/- 天王寺:21:47/21:49/18 大阪:22:02/22:03/24 新大阪:22:08/-/2')}

PRINTED_EQUIPMENT = ["女性専用席があります", "グリーン車指定席", "普通車全車指定席"]
OCEAN_ARROW_EQUIPMENT = ["オーシャンアロー車両で運転", "女性専用席があります", "グリーン車指定席（パノラマ型グリーン車）", "普通車全車指定席"]


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
                         (DAY, 4, 4, 42))
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
                                 "毎日運転" if public in (32, 35) else "土曜・休日運休")
                self.assertEqual(entry["printed_equipment"], OCEAN_ARROW_EQUIPMENT if public in (35, 36) else PRINTED_EQUIPMENT)
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
                self.assertEqual(formation.get("formation_label"), "オーシャンアロー車両" if public in (35, 36) else None)
                for field in ("car_count", "reserved_seat_capacity", "vehicle_series"):
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
