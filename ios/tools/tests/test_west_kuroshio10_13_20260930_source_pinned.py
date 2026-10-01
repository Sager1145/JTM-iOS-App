"""Exact-date Kuroshio 10–13 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio10-13-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {
    10: ("144491", "2060M", "白浜:-/07:10/- 紀伊田辺:07:20/07:22/- 南部:07:28/07:28/- 御坊:07:52/07:53/- 湯浅:08:06/08:07/- 藤並:08:10/08:11/- 箕島:08:17/08:18/- 海南:08:29/08:30/- 和歌山:08:39/08:41/1 和泉砂川:08:58/08:58/- 日根野:09:03/09:04/- 天王寺:09:34/09:35/18 大阪:09:46/09:47/24 新大阪:09:52/-/2"),
    11: ("144341", "61M", "新大阪:-/12:13/2 大阪:12:17/12:18/21 天王寺:12:30/12:32/15 日根野:12:57/12:57/- 和歌山:13:15/13:18/4 海南:13:27/13:27/- 御坊:14:00/14:00/- 紀伊田辺:14:29/14:31/- 白浜:14:41/14:43/- 周参見:15:07/15:08/- 串本:15:40/15:40/- 古座:15:49/15:50/- 太地:16:08/16:09/- 紀伊勝浦:16:16/16:17/- 新宮:16:40/-/-"),
    12: ("144511", "62M", "新宮:-/06:27/- 紀伊勝浦:06:44/06:45/- 太地:06:51/06:52/- 古座:07:10/07:10/- 串本:07:18/07:19/- 周参見:07:50/07:51/- 白浜:08:13/08:20/- 紀伊田辺:08:30/08:32/- 南部:08:37/08:38/- 御坊:09:02/09:03/- 湯浅:09:16/09:16/- 藤並:09:19/09:20/- 箕島:09:26/09:27/- 海南:09:38/09:39/- 和歌山:09:48/09:50/1 日根野:10:08/10:09/- 天王寺:10:33/10:35/18 大阪:10:46/10:47/24 新大阪:10:51/10:52/1 京都:11:17/-/0"),
    13: ("144351", "2063M", "新大阪:-/13:13/2 大阪:13:17/13:18/21 天王寺:13:30/13:32/15 日根野:13:57/13:57/- 和歌山:14:15/14:18/4 海南:14:27/14:27/- 箕島:14:39/14:40/- 藤並:14:46/14:47/- 湯浅:14:50/14:50/- 御坊:15:04/15:04/- 南部:15:27/15:28/- 紀伊田辺:15:35/15:36/- 白浜:15:47/-/-"),
}
REGULAR = ["女性専用席があります", "グリーン車指定席", "普通車全車指定席"]
OCEAN = ["オーシャンアロー車両で運転", "女性専用席があります",
         "グリーン車指定席（パノラマ型グリーン車）", "普通車全車指定席"]


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
                         (DAY, 4, 4, 62))
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
                                 "土曜・休日運休" if public in (10, 12) else "毎日運転")
                self.assertEqual(entry["printed_equipment"], OCEAN if public == 11 else REGULAR)
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
                                  formation["all_reserved"], formation["green_car_available"],
                                  formation.get("formation_label")),
                                 (DAY, "planned", True, True,
                                  "オーシャンアロー車両" if public == 11 else None))
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
