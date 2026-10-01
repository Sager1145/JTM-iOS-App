"""Exact-date Kuroshio 27–30 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio27-30-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {27: ('144381', '77M', '新大阪:-/19:13/2 大阪:19:17/19:18/21 天王寺:19:33/19:35/15 和泉府中:19:52/19:52/- 日根野:20:01/20:02/- 和泉砂川:20:07/20:07/- 和歌山:20:23/20:26/4 海南:20:34/20:35/- 箕島:20:46/20:47/- 藤並:20:53/20:54/- 湯浅:20:57/20:57/- 御坊:21:11/21:11/- 南部:21:34/21:35/- 紀伊田辺:21:42/21:43/- 白浜:21:54/21:56/- 周参見:22:17/22:17/- 串本:22:54/22:55/- 古座:23:03/23:04/- 太地:23:22/23:23/- 紀伊勝浦:23:29/23:30/- 新宮:23:49/-/-'), 28: ('127011', '2078M', '白浜:-/16:20/- 紀伊田辺:16:30/16:32/- 南部:16:38/16:38/- 御坊:17:02/17:03/- 湯浅:17:16/17:16/- 藤並:17:20/17:20/- 箕島:17:27/17:27/- 海南:17:39/17:39/- 和歌山:17:48/17:50/1 日根野:18:08/18:08/- 天王寺:18:32/18:34/18 大阪:18:46/18:47/24 新大阪:18:51/-/2'), 29: ('144401', '2079M', '新大阪:-/20:13/2 大阪:20:17/20:18/21 天王寺:20:33/20:35/15 和泉府中:20:52/20:52/- 日根野:21:01/21:02/- 和泉砂川:21:07/21:07/- 和歌山:21:22/21:26/4 海南:21:34/21:35/- 箕島:21:46/21:47/- 藤並:21:53/21:54/- 湯浅:21:57/21:57/- 御坊:22:11/22:11/- 南部:22:34/22:35/- 紀伊田辺:22:41/22:43/- 白浜:22:54/-/-'), 30: ('198532', '6080M', '新宮:-/15:04/- 紀伊勝浦:15:21/15:21/- 太地:15:28/15:28/- 古座:15:47/15:49/- 串本:15:57/15:57/- 周参見:16:29/16:29/- 白浜:16:50/16:56/- 紀伊田辺:17:06/17:08/- 御坊:17:37/17:37/- 海南:18:09/18:09/- 和歌山:18:18/18:20/1 日根野:18:37/18:38/- 天王寺:19:02/19:04/18 大阪:19:16/19:17/24 新大阪:19:21/-/2')}

PRINTED_EQUIPMENT = ["女性専用席があります", "グリーン車指定席", "普通車全車指定席"]
OCEAN_ARROW_EQUIPMENT = ["オーシャンアロー車両で運転", "女性専用席があります", "グリーン車指定席（パノラマ型グリーン車）", "普通車全車指定席"]
SPECIAL_OPERATION = "９月１８・２４・２５・２８～３０日・１０月１・２・５～９・１３～１６・１９～２３・２６～３０日・１１月２・４～６・９～１３・１６～２０・２４～２７・３０日運転"


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
                         (DAY, 4, 4, 64))
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
                                 SPECIAL_OPERATION if public == 30 else "土曜・休日運休")
                self.assertEqual(entry["printed_equipment"], OCEAN_ARROW_EQUIPMENT if public in (29, 30) else PRINTED_EQUIPMENT)
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
                self.assertEqual(formation.get("formation_label"), "オーシャンアロー車両" if public in (29, 30) else None)
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
