"""Exact-date Kuroshio 2–5 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio2-5-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {
    2: ("100391", "2052M", "和歌山:-/05:14/1 和泉砂川:05:28/05:29/- 日根野:05:33/05:34/- 和泉府中:05:43/05:44/- 天王寺:06:00/06:02/18 大阪:06:15/06:16/24 新大阪:06:21/-/3"),
    3: ("144311", "2053M", "新大阪:-/08:58/2 大阪:09:03/09:04/21 天王寺:09:18/09:20/15 日根野:09:46/09:46/- 和歌山:10:05/10:06/4 海南:10:15/10:15/- 箕島:10:27/10:27/- 藤並:10:34/10:34/- 湯浅:10:37/10:38/- 御坊:10:51/10:51/- 南部:11:14/11:15/- 紀伊田辺:11:21/11:23/- 白浜:11:37/-/-"),
    4: ("144451", "2054M", "和歌山:-/06:00/1 和泉砂川:06:15/06:15/- 日根野:06:20/06:21/- 和泉府中:06:33/06:34/- 天王寺:06:56/06:59/18 大阪:07:13/07:14/24 新大阪:07:19/-/2"),
    5: ("198471", "6055M", "新大阪:-/09:28/2 大阪:09:32/09:33/21 天王寺:09:45/09:47/15 日根野:10:14/10:15/- 和歌山:10:34/10:35/4 海南:10:44/10:44/- 御坊:11:16/11:17/- 紀伊田辺:11:46/11:47/- 白浜:11:58/12:01/- 周参見:12:21/12:22/- 串本:12:55/12:56/- 古座:13:04/13:05/- 太地:13:22/13:23/- 紀伊勝浦:13:29/13:30/- 新宮:13:53/-/-"),
}
WEEKDAY_ONLY = {3, 4}
OCEAN_ARROW = {2, 5}


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
                                 "土曜・休日運休" if public in WEEKDAY_ONLY else
                                 "毎日運転" if public == 2 else
                                 "９月１８・２４・２５・２８～３０日・１０月１・２・５～９・１３～１６・１９～２３・２６～３０日・１１月２・４～６・９～１３・１６～２０・２４～２７・３０日運転")
                self.assertEqual((trips[tid]["train_number"], trips[tid]["public_number"]),
                                 (train_number, str(public)))
                expected_calls = printed_calls(expected)
                self.assertEqual([(stop["name"], stop["arrival"], stop["departure"], stop["platform"])
                                  for stop in entry["stops"]], expected_calls)
                actual = sorted((stop for stop in stops if stop["trip_id"] == tid),
                                key=lambda stop: stop["stop_sequence"])
                self.assertEqual([(stop["arrival_time"], stop["departure_time"], stop["platform"])
                                  for stop in actual], [call[1:] for call in expected_calls])
                equipment = entry["printed_equipment"]
                self.assertEqual("オーシャンアロー車両で運転" in equipment,
                                 public in OCEAN_ARROW)
                self.assertIn("女性専用席があります", equipment)
                self.assertIn("普通車全車指定席", equipment)
                self.assertIn("グリーン車指定席（パノラマ型グリーン車）" if public in OCEAN_ARROW
                              else "グリーン車指定席", equipment)
                formation = formations[tid]
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["all_reserved"], formation["green_car_available"]),
                                 (DAY, "planned", True, True))
                self.assertNotIn("car_count", formation)
                self.assertNotIn("reserved_seat_capacity", formation)
                self.assertNotIn("vehicle_series", formation)
                self.assertEqual(formation.get("formation_label"),
                                 "オーシャンアロー車両" if public in OCEAN_ARROW else None)
                self.assertIn("Ocean Arrow" if public in OCEAN_ARROW else "seat categories",
                              formation["notes"])
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
