"""Exact-date Yakumo 9–12 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo9-12-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {9: ('76271', '1009M', '岡山:-/11:13/2 倉敷:11:24/11:24/- 備中高梁:11:47/11:48/- 新見:12:15/12:16/- 生山:12:48/12:49/- 米子:13:25/13:26/2 安来:13:33/13:34/- 松江:13:48/13:49/- 玉造温泉:13:55/13:56/- 宍道:14:08/14:08/- 出雲市:14:19/-/-'), 10: ('76321', '1010M', '出雲市:-/08:34/- 宍道:08:47/08:48/- 玉造温泉:08:56/08:56/- 松江:09:05/09:06/- 安来:09:26/09:26/- 米子:09:34/09:35/1 伯耆大山:09:39/09:40/- 生山:10:13/10:14/- 新見:10:44/10:45/- 備中高梁:11:13/11:14/- 倉敷:11:35/11:36/- 岡山:11:47/-/3'), 11: ('541', '1011M', '岡山:-/12:13/2 倉敷:12:24/12:24/- 総社:12:32/12:33/- 備中高梁:12:49/12:49/- 新見:13:20/13:21/- 根雨:14:03/14:03/- 米子:14:26/14:28/2 安来:14:34/14:35/- 松江:14:54/14:55/- 玉造温泉:15:01/15:01/- 宍道:15:09/15:09/- 出雲市:15:20/-/-'), 12: ('278901', '1012M', '出雲市:-/09:40/- 宍道:09:55/09:56/- 玉造温泉:10:04/10:04/- 松江:10:10/10:11/- 安来:10:26/10:27/- 米子:10:34/10:36/1 根雨:10:59/11:02/- 新見:11:44/11:44/- 備中高梁:12:13/12:14/- 倉敷:12:35/12:36/- 岡山:12:47/-/3')}

PRINTED_EQUIPMENT = ["グリーン車指定席", "普通車全車指定席"]

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


class YakumoNineToTwelveSeptember30Tests(unittest.TestCase):
    def test_official_pages_and_every_printed_call(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        sources = {row["source_id"]: row for row in rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        formations = {row["trip_id"]: row for row in rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")}
        self.assertEqual((candidate["service_date"], len(candidate["trips"]), len(sources), len(stops)),
                         (DAY, 4, 4, 46))
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
                                 "毎日運転")
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
                self.assertEqual(formation.get("formation_label"), None)
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
            tid = f"jr-west.yakumo.{number}.{DAY}"
            self.assertEqual(len(selected[tid]["stop_times"]), len(printed_calls(calls)))
            self.assertNotIn(tid, previous)

    def test_twelve_is_distinct_from_september_27_occurrence(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        old = "jr-west.yakumo.12.2026-09-27"
        current = "jr-west.yakumo.12.2026-09-30"
        on_old = {trip["trip_id"] for trip in timetable.materialize(data, "2026-09-27")}
        on_current = {trip["trip_id"] for trip in timetable.materialize(data, DAY)}
        self.assertIn(old, on_old)
        self.assertNotIn(current, on_old)
        self.assertIn(current, on_current)
        self.assertNotIn(old, on_current)
        prior = rows(BASE / "sources/source-registry-west-yakumo12-20260927.jsonl")[0]
        self.assertEqual(prior["url_or_locator"],
                         "https://timetable.jr-odekake.net/train-timetable/278901?date=20260927")


if __name__ == "__main__":
    unittest.main()
