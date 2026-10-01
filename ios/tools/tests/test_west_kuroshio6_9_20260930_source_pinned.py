"""Exact-date Kuroshio 6–9 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio6-9-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {
    6: ("144471", "2056M", "海南:-/06:39/- 和歌山:06:48/06:50/1 和泉砂川:07:04/07:05/- 日根野:07:10/07:11/- 和泉府中:07:20/07:20/- 天王寺:07:44/07:45/18 大阪:08:01/08:03/24 新大阪:08:07/-/2"),
    7: ("126971", "2057M", "新大阪:-/10:13/2 大阪:10:17/10:18/21 天王寺:10:30/10:32/15 日根野:10:57/10:57/- 和歌山:11:15/11:18/4 海南:11:27/11:27/- 箕島:11:39/11:39/- 藤並:11:46/11:46/- 湯浅:11:49/11:50/- 御坊:12:03/12:04/- 南部:12:27/12:27/- 紀伊田辺:12:34/12:35/- 白浜:12:46/-/-"),
    8: ("126991", "2058M", "白浜:-/06:39/- 紀伊田辺:06:49/06:51/- 南部:06:57/06:57/- 御坊:07:21/07:22/- 湯浅:07:35/07:35/- 藤並:07:39/07:39/- 箕島:07:46/07:46/- 海南:07:58/07:58/- 和歌山:08:07/08:09/1 和泉砂川:08:24/08:24/- 日根野:08:29/08:30/- 和泉府中:08:39/08:40/- 天王寺:08:59/09:01/18 大阪:09:14/09:15/24 新大阪:09:19/-/1"),
    9: ("144331", "2059M", "新大阪:-/11:13/2 大阪:11:17/11:18/21 天王寺:11:30/11:32/15 日根野:11:57/11:57/- 和歌山:12:15/12:18/4 海南:12:27/12:27/- 箕島:12:39/12:40/- 藤並:12:46/12:47/- 湯浅:12:50/12:50/- 御坊:13:04/13:04/- 南部:13:27/13:28/- 紀伊田辺:13:35/13:36/- 白浜:13:47/-/-"),
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
                         (DAY, 4, 4, 49))
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
                                 "毎日運転" if public == 9 else "土曜・休日運休")
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
