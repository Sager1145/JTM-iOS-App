"""Exact-date Yakumo 1–4 pages pin every timed passenger call."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo1-4-20260930"
DAY = "2026-09-30"
# name:arrival/departure/platform; '-' means the official cell is blank.
EXPECTED = {1: ('76231', '1001M', '岡山:-/07:05/2 倉敷:07:16/07:16/- 備中高梁:07:40/07:40/- 新見:08:10/08:11/- 生山:08:43/08:44/- 米子:09:21/09:23/2 安来:09:30/09:30/- 松江:09:49/09:50/- 玉造温泉:09:56/09:56/- 宍道:10:06/10:07/- 出雲市:10:18/-/-'), 2: ('76332', '1002M', '出雲市:-/04:42/- 宍道:04:52/04:53/- 松江:05:06/05:07/- 安来:05:22/05:23/- 米子:05:30/05:32/1 伯耆大山:05:36/05:36/- 生山:06:09/06:10/- 新見:06:39/06:40/- 備中高梁:07:06/07:06/- 倉敷:07:28/07:29/- 岡山:07:41/-/3'), 3: ('76241', '1003M', '岡山:-/08:13/2 倉敷:08:24/08:24/- 備中高梁:08:47/08:48/- 新見:09:14/09:15/- 根雨:10:00/10:00/- 米子:10:23/10:25/2 安来:10:32/10:32/- 松江:10:47/10:48/- 宍道:11:01/11:01/- 出雲市:11:12/-/-'), 4: ('76281', '1004M', '出雲市:-/05:27/- 宍道:05:37/05:38/- 松江:05:51/05:52/- 安来:06:07/06:08/- 米子:06:15/06:23/1 伯耆大山:06:27/06:27/- 根雨:06:47/06:48/- 新見:07:29/07:29/- 備中高梁:07:59/08:00/- 総社:08:15/08:15/- 倉敷:08:23/08:24/- 岡山:08:35/-/3')}

PRINTED_EQUIPMENT = ["グリーン車指定席", "普通車全車指定席"]
YAKUMO_2_OPERATION = "９月１８日・１０月１４～１６・２０～２３・２７～３０日・１１月５・６・１０～１３・１７～２０日は出雲市－米子間運休"

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
                         (DAY, 4, 4, 44))
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
                                 YAKUMO_2_OPERATION if public == 2 else "毎日運転")
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
