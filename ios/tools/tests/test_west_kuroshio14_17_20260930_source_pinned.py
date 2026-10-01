"""September 30 Kuroshio 14, 16, 17 pages pin each timed call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio14-17-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' denotes an unprinted cell.
EXPECTED = {
    14: ("144531", "2064M", "白浜:-/09:20/- 紀伊田辺:09:30/09:32/- 南部:09:38/09:38/- 御坊:10:02/10:03/- 湯浅:10:16/10:16/- 藤並:10:20/10:20/- 箕島:10:27/10:27/- 海南:10:39/10:39/- 和歌山:10:48/10:50/1 日根野:11:08/11:08/- 天王寺:11:33/11:35/18 大阪:11:46/11:47/24 新大阪:11:51/-/2"),
    16: ("144541", "66M", "新宮:-/08:32/- 紀伊勝浦:08:49/08:49/- 太地:08:56/08:56/- 古座:09:14/09:14/- 串本:09:22/09:23/- 周参見:09:54/09:55/- 白浜:10:19/10:26/- 紀伊田辺:10:36/10:37/- 御坊:11:06/11:07/- 海南:11:39/11:39/- 和歌山:11:48/11:50/1 日根野:12:08/12:08/- 天王寺:12:33/12:35/18 大阪:12:46/12:47/24 新大阪:12:51/-/2"),
    17: ("86211", "67M", "新大阪:-/15:13/2 大阪:15:17/15:18/21 天王寺:15:30/15:32/15 日根野:15:57/15:57/- 和歌山:16:15/16:18/4 海南:16:27/16:27/- 御坊:17:00/17:00/- 紀伊田辺:17:29/17:31/- 白浜:17:41/17:43/- 周参見:18:04/18:04/- 串本:18:37/18:38/- 古座:18:46/18:46/- 太地:19:03/19:04/- 紀伊勝浦:19:10/19:11/- 新宮:19:28/-/-"),
}
REGULAR = ["女性専用席があります", "グリーン車指定席", "普通車全車指定席"]
OCEAN = ["オーシャンアロー車両で運転", "女性専用車両があります",
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
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        self.assertEqual((candidate["service_date"], len(candidate["trips"]), len(sources), len(stops)),
                         (DAY, 3, 3, 43))
        self.assertEqual({int(row["public_number"]) for row in candidate["trips"]}, set(EXPECTED))
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
                self.assertEqual(entry["operation_label"], "毎日運転")
                self.assertEqual(entry["printed_equipment"], OCEAN if public == 14 else REGULAR)
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
                                  "オーシャンアロー車両" if public == 14 else None))
                self.assertIn("formation.women_only_car_available" if public == 14
                              else "formation.women_only_seat_available",
                              {row["field_name"] for row in facts if row["entity_id"] == tid})
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
        self.assertNotIn(f"jr-west.kuroshio.15.{DAY}", selected)


if __name__ == "__main__":
    unittest.main()
