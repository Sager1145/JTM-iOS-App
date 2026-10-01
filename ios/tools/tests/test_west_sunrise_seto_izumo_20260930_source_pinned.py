"""Pin the September 30 official Sunrise page's two overnight columns."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-sunrise-seto-izumo-20260930"
DAY = "2026-09-30"
URL = "https://timetable.jr-odekake.net/train-timetable/38492?date=20260930"
SETO = "jr-west.sunrise-seto.5031m.2026-09-30"
IZUMO = "jr-west.sunrise-izumo.5031m-4031m.2026-09-30"
# The two strings independently pin printed arrival/departure/platform cells.
PRINTED = {
    SETO: "東京:-/21:26/9 横浜:21:51/21:52/6 熱海:22:55/22:57/2 沼津:23:15/23:16/- 富士:23:31/23:32/- 静岡:23:57/23:59/4 浜松:00:53/00:54/4 姫路:05:25/05:26/8 岡山:06:27/06:31/8 児島:06:52/06:53/- 坂出:07:09/07:10/- 高松:07:27/-/6",
    IZUMO: "東京:-/21:26/9 横浜:21:51/21:52/6 熱海:22:55/22:57/2 沼津:23:15/23:16/- 富士:23:31/23:32/- 静岡:23:57/23:59/4 浜松:00:53/00:54/4 姫路:05:25/05:26/8 岡山:06:27/06:34/8 倉敷:06:46/06:47/- 備中高梁:07:14/07:14/- 新見:07:43/07:44/- 米子:09:05/09:08/2 安来:09:16/09:17/- 松江:09:33/09:34/- 宍道:09:47/09:48/- 出雲市:10:00/-/-",
}
EQUIPMENT = ["シングルデラックス（Ａ寝台１人個室）", "ソロ（Ｂ寝台１人個室）",
             "シングルツイン（Ｂ寝台１人個室）", "シングル（Ｂ寝台１人個室）",
             "サンライズツイン（Ｂ寝台２人個室）", "普通車全車指定席（ノビノビ座席）"]


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def calls(value):
    result = []
    for index, token in enumerate(value.split()):
        name, clocks = token.split(":", 1)
        a, d, p = clocks.split("/")
        result.append((name, None if a == "-" else a, None if d == "-" else d,
                       None if p == "-" else p, int(index >= 6)))
    return result


class SunriseSeptember30Tests(unittest.TestCase):
    def test_official_columns_and_normalized_calls(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        segments = rows(BASE / f"normalized/trip-number-segments/{SUFFIX}/seeds.jsonl")
        relations = rows(BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl")
        formations = rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")
        self.assertEqual((candidate["selected_service_date"], len(candidate["trips"]), len(stops)),
                         (DAY, 2, 29))
        self.assertEqual((source[0]["url_or_locator"], source[0]["effective_date"]), (URL, DAY))
        self.assertEqual({row["trip_id"] for row in candidate["trips"]}, {SETO, IZUMO})
        for entry in candidate["trips"]:
            tid = entry["trip_id"]
            with self.subTest(trip=tid):
                self.assertEqual((entry["train_number"], entry["operation_label"], entry["printed_equipment"]),
                                 ("5031M", "毎日運転", EQUIPMENT))
                expected = calls(PRINTED[tid])
                self.assertEqual([(s["name"], s["arrival"], s["departure"], s["platform"], s["day_offset"])
                                  for s in entry["stops"]], expected)
                actual = sorted((s for s in stops if s["trip_id"] == tid), key=lambda s: s["stop_sequence"])
                self.assertEqual([(s["arrival_time"], s["departure_time"], s["platform"], s["day_offset"])
                                  for s in actual], [c[1:] for c in expected])
                self.assertEqual((trips[tid]["origin_station_id"], trips[tid]["train_number"]),
                                 ("jp.n02.003766", "5031M"))
        self.assertEqual([(r["from_sequence"], r["to_sequence"], r["train_number"])
                          for r in segments if r["trip_id"] == IZUMO],
                         [(1, 9, "5031M"), (9, 17, "4031M")])
        self.assertEqual({(r["trip_id"], r["related_trip_id"], r["from_sequence"], r["to_sequence"])
                          for r in relations}, {(SETO, IZUMO, 1, 9), (IZUMO, SETO, 1, 9)})
        self.assertEqual({r["trip_id"] for r in formations}, {SETO, IZUMO})
        for formation in formations:
            self.assertEqual((formation["service_date"], formation["evidence_kind"],
                              formation["all_reserved"], formation["green_car_available"]),
                             (DAY, "planned", True, False))
            for field in ("car_count", "reserved_seat_capacity", "vehicle_series"):
                self.assertNotIn(field, formation)

    def test_departure_date_and_next_day_calls(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable

        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        selected = {trip["trip_id"]: trip for trip in timetable.materialize(data, DAY)}
        previous = {trip["trip_id"] for trip in timetable.materialize(data, "2026-09-29")}
        for tid in (SETO, IZUMO):
            self.assertEqual(len(selected[tid]["stop_times"]), len(calls(PRINTED[tid])))
            self.assertNotIn(tid, previous)
        self.assertEqual(selected[SETO]["stop_times"][0]["day_offset"], 0)
        self.assertEqual(selected[SETO]["stop_times"][6]["day_offset"], 1)
        self.assertEqual(selected[IZUMO]["stop_times"][8]["arrival_time"], "06:27")
        self.assertEqual(selected[IZUMO]["stop_times"][8]["departure_time"], "06:34")


if __name__ == "__main__":
    unittest.main()
