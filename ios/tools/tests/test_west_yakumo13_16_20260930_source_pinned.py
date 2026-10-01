"""Source-pin the four September 30 Yakumo pages, including existing 15."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo13-16-20260930"
DAY = "2026-09-30"
EXPECTED = {
    13: ("278871", "1013M", "岡山:-/13:13/2 倉敷:13:24/13:24/- 備中高梁:13:47/13:48/- 新見:14:15/14:16/- 生山:14:50/14:51/- 米子:15:28/15:29/2 安来:15:36/15:36/- 松江:15:51/15:52/- 玉造温泉:15:57/15:58/- 出雲市:16:19/-/-"),
    14: ("631", "1014M", "出雲市:-/10:38/- 玉造温泉:10:57/10:58/- 松江:11:04/11:07/- 安来:11:22/11:23/- 米子:11:31/11:35/1 生山:12:15/12:15/- 新見:12:43/12:44/- 備中高梁:13:09/13:10/- 総社:13:25/13:26/- 倉敷:13:33/13:34/- 岡山:13:46/-/3"),
    15: ("681", "1015M", "岡山:-/14:13/2 倉敷:14:24/14:24/- 備中高梁:14:47/14:48/- 新見:15:15/15:16/- 根雨:16:03/16:04/- 米子:16:27/16:28/2 安来:16:35/16:35/- 松江:16:51/16:54/- 玉造温泉:17:02/17:02/- 宍道:17:10/17:10/- 出雲市:17:23/-/-"),
    16: ("278911", "1016M", "出雲市:-/11:44/- 宍道:11:54/11:55/- 玉造温泉:12:03/12:04/- 松江:12:10/12:11/- 安来:12:26/12:27/- 米子:12:34/12:35/1 根雨:12:59/13:03/- 新見:13:45/13:46/- 備中高梁:14:13/14:14/- 倉敷:14:35/14:36/- 岡山:14:47/-/3"),
}
EQUIPMENT = ["グリーン車指定席", "普通車全車指定席"]


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def printed_calls(value):
    result = []
    for token in value.split():
        name, clocks = token.split(":", 1)
        a, d, p = clocks.split("/")
        result.append((name, None if a == "-" else a,
                       None if d == "-" else d, None if p == "-" else p))
    return result


class YakumoThirteenToSixteenTests(unittest.TestCase):
    def test_four_pages_and_three_new_trips(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        sources = {row["source_id"]: row for row in rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        formations = {row["trip_id"]: row for row in rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")}
        self.assertEqual((candidate["service_date"], len(candidate["trips"]), len(sources), len(stops)),
                         (DAY, 4, 3, 32))
        self.assertEqual({int(row["public_number"]) for row in candidate["trips"]}, set(EXPECTED))
        self.assertEqual(set(trips), {f"jr-west.yakumo.{number}.{DAY}" for number in (13, 14, 16)})
        for entry in candidate["trips"]:
            public = int(entry["public_number"])
            page, number, clocks = EXPECTED[public]
            tid = entry["trip_id"]
            expected = printed_calls(clocks)
            with self.subTest(public=public):
                self.assertEqual((entry["train_number"], entry["source_url"], entry["operation_label"]),
                                 (number, f"https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930", "毎日運転"))
                self.assertEqual(entry["printed_equipment"], EQUIPMENT)
                self.assertEqual([(s["name"], s["arrival"], s["departure"], s["platform"])
                                  for s in entry["stops"]], expected)
                if public == 15:
                    self.assertNotIn(entry["source_id"], sources)
                    self.assertNotIn(tid, trips)
                    continue
                self.assertEqual((sources[entry["source_id"]]["url_or_locator"],
                                  sources[entry["source_id"]]["effective_date"]),
                                 (entry["source_url"], DAY))
                self.assertEqual((trips[tid]["train_number"], trips[tid]["public_number"]),
                                 (number, str(public)))
                actual = sorted((s for s in stops if s["trip_id"] == tid),
                                key=lambda s: s["stop_sequence"])
                self.assertEqual([(s["arrival_time"], s["departure_time"], s["platform"])
                                  for s in actual], [call[1:] for call in expected])
                formation = formations[tid]
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["all_reserved"], formation["green_car_available"]),
                                 (DAY, "planned", True, True))
                for field in ("car_count", "vehicle_series", "reserved_seat_capacity"):
                    self.assertNotIn(field, formation)

    def test_existing_fifteen_and_platform_supplement(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable

        source = [row for row in rows(BASE / "sources/source-registry-discovery-west-2026.jsonl")
                  if row["source_id"] == "jr-west-odekake-yakumo15-1015m-20260930"]
        self.assertEqual(len(source), 1)
        self.assertEqual(source[0]["url_or_locator"],
                         "https://timetable.jr-odekake.net/train-timetable/681?date=20260930")
        overrides = rows(BASE / f"normalized/trip-stop-time-overrides/{SUFFIX}/seeds.jsonl")
        self.assertEqual([(row["stop_sequence"], row["platform_override"]) for row in overrides],
                         [(1, "2"), (6, "2")])
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        selected = {trip["trip_id"]: trip for trip in timetable.materialize(data, DAY)}
        previous = {trip["trip_id"] for trip in timetable.materialize(data, "2026-09-29")}
        for public, (_, _, clocks) in EXPECTED.items():
            tid = f"jr-west.yakumo.{public}.{DAY}"
            self.assertEqual(len(selected[tid]["stop_times"]), len(printed_calls(clocks)))
            self.assertNotIn(tid, previous)
        fifteen = selected[f"jr-west.yakumo.15.{DAY}"]["stop_times"]
        self.assertEqual((fifteen[0]["platform"], fifteen[5]["platform"]), ("2", "2"))


if __name__ == "__main__":
    unittest.main()
