"""Twelve September 30 JR West train pages pin passenger calls and platforms."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka45-52-thunderbird47-50-20260930"
DAY = "2026-09-30"
# Each clock is arrival/departure/platform; '-' means the printed cell is empty.
EXPECTED = {
    ('haruka', 45): ('257091', '京都:-/17:00/30 新大阪:17:27/17:28/3 大阪:17:32/17:33/21 天王寺:17:48/17:50/15 和泉府中:18:06/18:07/- 日根野:18:18/18:18/- 関西空港:18:26/-/-'),
    ('haruka', 46): ('1151', '関西空港:-/18:16/- 天王寺:18:48/18:49/18 大阪:19:01/19:02/24 新大阪:19:06/19:07/1 高槻:19:19/19:20/- 京都:19:34/-/30'),
    ('haruka', 47): ('1171', '京都:-/17:30/30 新大阪:17:57/17:58/3 大阪:18:02/18:03/21 天王寺:18:18/18:20/15 和泉府中:18:37/18:37/- 日根野:18:46/18:47/- 関西空港:18:59/-/-'),
    ('haruka', 48): ('257341', '関西空港:-/18:46/- 天王寺:19:18/19:19/18 大阪:19:31/19:32/24 新大阪:19:36/19:37/1 高槻:19:49/19:50/- 京都:20:04/-/30'),
    ('haruka', 49): ('257111', '京都:-/18:00/30 新大阪:18:27/18:28/3 大阪:18:32/18:33/21 天王寺:18:48/18:50/15 和泉府中:19:07/19:07/- 日根野:19:16/19:17/- 関西空港:19:25/-/-'),
    ('haruka', 50): ('192721', '関西空港:-/19:16/- 天王寺:19:48/19:49/18 大阪:20:01/20:02/24 新大阪:20:06/20:07/1 高槻:20:19/20:19/- 京都:20:32/20:34/0 山科:20:39/20:39/- 大津:20:43/20:44/- 石山:20:48/20:48/- 南草津:20:52/20:53/- 草津:20:56/20:56/- 守山:21:00/21:01/- 野洲:21:04/-/-'),
    ('haruka', 51): ('129391', '京都:-/18:30/30 新大阪:18:57/18:58/3 大阪:19:02/19:03/21 天王寺:19:18/19:20/15 和泉府中:19:37/19:38/- 日根野:19:47/19:47/- 関西空港:19:59/-/-'),
    ('haruka', 52): ('257361', '関西空港:-/19:46/- 天王寺:20:18/20:19/18 大阪:20:31/20:32/24 新大阪:20:36/20:37/1 高槻:20:49/20:49/- 京都:21:03/-/30'),
    ('thunderbird', 47): ('257911', '大阪:-/20:07/11 新大阪:20:11/20:12/4 京都:20:36/20:38/0 堅田:20:52/20:53/- 近江今津:21:11/21:11/- 敦賀:21:33/-/31'),
    ('thunderbird', 48): ('258251', '敦賀:-/21:08/33 京都:22:02/22:03/7 高槻:22:16/22:16/- 新大阪:22:26/22:27/9 大阪:22:31/-/3'),
    ('thunderbird', 49): ('257921', '大阪:-/20:54/11 新大阪:20:57/20:58/4 京都:21:20/21:21/0 堅田:21:36/21:37/- 敦賀:22:16/-/32'),
    ('thunderbird', 50): ('258261', '敦賀:-/22:05/33 京都:22:59/23:01/7 高槻:23:14/23:14/- 新大阪:23:24/23:25/9 大阪:23:29/-/4'),
}
WEEKDAY_ONLY = {('haruka', 48), ('haruka', 47), ('haruka', 50), ('haruka', 46), ('haruka', 49), ('haruka', 52), ('haruka', 45), ('haruka', 51)}


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


class WestSeptember30BatchTests(unittest.TestCase):
    def test_date_selected_sources_and_every_printed_call(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        sources = {row["source_id"]: row for row in rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        formations = {row["trip_id"]: row for row in rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")}
        self.assertEqual(candidate["service_date"], DAY)
        self.assertEqual(len(candidate["trips"]), 12)
        self.assertEqual(len(sources), 12)
        self.assertEqual(len(stops), 80)
        for entry in candidate["trips"]:
            service, public = entry["service_id"], int(entry["public_number"])
            key = (service, public)
            page, expected = EXPECTED[key]
            tid = entry["trip_id"]
            with self.subTest(trip=tid):
                self.assertEqual(entry["source_url"],
                                 f"https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930")
                self.assertEqual((sources[entry["source_id"]]["url_or_locator"],
                                  sources[entry["source_id"]]["effective_date"]),
                                 (entry["source_url"], DAY))
                self.assertEqual(entry["operation_label"],
                                 "土曜・休日運休" if key in WEEKDAY_ONLY else "毎日運転")
                self.assertEqual((trips[tid]["train_number"], trips[tid]["public_number"]),
                                 (f"{1000 + public if service == 'haruka' else 4000 + public}M",
                                  str(public)))
                expected_calls = printed_calls(expected)
                self.assertEqual([(stop["name"], stop["arrival"], stop["departure"], stop["platform"])
                                  for stop in entry["stops"]], expected_calls)
                actual = sorted((stop for stop in stops if stop["trip_id"] == tid),
                                key=lambda stop: stop["stop_sequence"])
                self.assertEqual([(stop["arrival_time"], stop["departure_time"], stop["platform"])
                                  for stop in actual], [call[1:] for call in expected_calls])
                formation = formations[tid]
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["car_count"], formation["green_car_available"]),
                                 (DAY, "planned", 9, True))
                self.assertEqual(formation["all_reserved"], service == "thunderbird")
                self.assertEqual(formation.get("reserved_seat_capacity"),
                                 546 if service == "thunderbird" else None)
                self.assertNotIn("vehicle_series", formation)
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}").exists())

    def test_only_selected_day_materializes(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        selected = {trip["trip_id"]: trip for trip in timetable.materialize(data, DAY)}
        previous = {trip["trip_id"] for trip in timetable.materialize(data, "2026-09-29")}
        for service, number in EXPECTED:
            tid = f"jr-west.{service}.{number}.{DAY}"
            with self.subTest(trip=tid):
                self.assertEqual(len(selected[tid]["stop_times"]),
                                 len(printed_calls(EXPECTED[(service, number)][1])))
                self.assertNotIn(tid, previous)


if __name__ == "__main__":
    unittest.main()
