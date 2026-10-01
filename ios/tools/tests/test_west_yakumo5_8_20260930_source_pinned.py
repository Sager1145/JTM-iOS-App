"""Exact-date Yakumo 5–8 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo5-8-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {5: ('76251', '1005M', '岡山:-/09:13/2 倉敷:09:24/09:24/- 総社:09:32/09:33/- 備中高梁:09:49/09:49/- 新見:10:18/10:18/- 生山:10:48/10:49/- 米子:11:25/11:26/2 安来:11:33/11:33/- 松江:11:48/11:49/- 宍道:12:06/12:06/- 出雲市:12:17/-/-'), 6: ('76291', '1006M', '出雲市:-/06:30/- 宍道:06:45/06:46/- 玉造温泉:06:54/06:55/- 松江:07:02/07:03/- 安来:07:18/07:19/- 米子:07:27/07:30/1 伯耆大山:07:35/07:35/- 生山:08:08/08:08/- 新見:08:38/08:39/- 備中高梁:09:13/09:14/- 倉敷:09:35/09:36/- 岡山:09:47/-/3'), 7: ('76261', '1007M', '岡山:-/10:13/2 倉敷:10:24/10:24/- 備中高梁:10:47/10:48/- 新見:11:15/11:16/- 根雨:12:01/12:02/- 米子:12:25/12:27/2 安来:12:33/12:34/- 松江:12:49/12:50/- 玉造温泉:12:55/12:56/- 宍道:13:03/13:04/- 出雲市:13:15/-/-'), 8: ('76301', '1008M', '出雲市:-/07:30/- 宍道:07:41/07:42/- 玉造温泉:07:49/07:50/- 松江:07:56/07:57/- 安来:08:16/08:17/- 米子:08:25/08:29/1 伯耆大山:08:33/08:34/- 根雨:08:57/08:58/- 新見:09:40/09:41/- 備中高梁:10:08/10:08/- 倉敷:10:30/10:31/- 岡山:10:43/-/3')}

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


class YakumoSeptember30BatchTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
