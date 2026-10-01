"""Sixteen September 30 JR West train pages pin passenger calls and platforms."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka37-44-thunderbird39-46-20260930"
DAY = "2026-09-30"
# Each clock is arrival/departure/platform; '-' means the printed cell is empty.
EXPECTED = {
    ('haruka', 37): ('257031', '京都:-/15:00/30 新大阪:15:27/15:28/3 大阪:15:32/15:33/21 天王寺:15:45/15:47/15 関西空港:16:20/-/-'),
    ('haruka', 38): ('257291', '関西空港:-/16:14/- 天王寺:16:48/16:50/18 大阪:17:01/17:02/24 新大阪:17:06/17:07/1 高槻:17:19/17:20/- 京都:17:34/-/30'),
    ('haruka', 39): ('257041', '京都:-/15:30/30 新大阪:15:57/15:58/3 大阪:16:02/16:03/21 天王寺:16:15/16:17/15 関西空港:16:50/-/-'),
    ('haruka', 40): ('257301', '関西空港:-/16:43/- 天王寺:17:17/17:20/18 大阪:17:31/17:32/24 新大阪:17:36/17:37/1 高槻:17:49/17:50/- 京都:18:04/-/30'),
    ('haruka', 41): ('257051', '京都:-/16:00/30 新大阪:16:27/16:28/3 大阪:16:32/16:33/21 天王寺:16:46/16:47/15 関西空港:17:23/-/-'),
    ('haruka', 42): ('129451', '関西空港:-/17:16/- 天王寺:17:48/17:50/18 大阪:18:01/18:02/24 新大阪:18:06/18:07/1 高槻:18:19/18:20/- 京都:18:34/-/30'),
    ('haruka', 43): ('257071', '京都:-/16:30/30 新大阪:16:57/16:58/3 大阪:17:02/17:03/21 天王寺:17:17/17:20/15 和泉府中:17:36/17:37/- 日根野:17:47/17:48/- 関西空港:17:56/-/-'),
    ('haruka', 44): ('257321', '関西空港:-/17:46/- 天王寺:18:18/18:20/18 大阪:18:31/18:32/24 新大阪:18:36/18:37/1 高槻:18:49/18:50/- 京都:19:04/-/30'),
    ('thunderbird', 39): ('257871', '大阪:-/17:40/11 新大阪:17:43/17:44/4 京都:18:06/18:07/0 敦賀:19:00/-/32'),
    ('thunderbird', 40): ('258201', '敦賀:-/18:44/33 京都:19:38/19:40/7 新大阪:20:03/20:04/9 大阪:20:09/-/5'),
    ('thunderbird', 41): ('257881', '大阪:-/18:10/11 新大阪:18:13/18:14/4 京都:18:37/18:38/0 敦賀:19:31/-/31'),
    ('thunderbird', 42): ('258221', '敦賀:-/19:14/33 京都:20:09/20:11/7 高槻:20:23/20:24/- 新大阪:20:34/20:34/9 大阪:20:38/-/3'),
    ('thunderbird', 43): ('257891', '大阪:-/18:42/11 新大阪:18:45/18:46/4 京都:19:09/19:10/0 近江今津:19:44/19:45/- 敦賀:20:07/-/32'),
    ('thunderbird', 44): ('258231', '敦賀:-/19:44/33 京都:20:38/20:40/7 高槻:20:52/20:53/- 新大阪:21:03/21:04/9 大阪:21:09/-/3'),
    ('thunderbird', 45): ('257901', '大阪:-/19:10/11 新大阪:19:13/19:14/4 京都:19:36/19:38/0 堅田:19:52/19:53/- 近江今津:20:11/20:11/- 敦賀:20:33/-/31'),
    ('thunderbird', 46): ('258241', '敦賀:-/20:11/33 京都:21:05/21:06/7 高槻:21:19/21:19/- 新大阪:21:29/21:30/9 大阪:21:34/-/3'),
}
WEEKDAY_ONLY = {('haruka', 40), ('haruka', 43), ('haruka', 42), ('thunderbird', 40), ('haruka', 41), ('haruka', 44)}


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
        self.assertEqual(len(candidate["trips"]), 16)
        self.assertEqual(len(sources), 16)
        self.assertEqual(len(stops), 84)
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
