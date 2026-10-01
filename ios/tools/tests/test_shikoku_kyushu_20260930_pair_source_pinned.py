"""Exact-date source and output checks for the Shikoku and Kyushu batch."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-shikoku-kyushu-20260930-pair"
PRIORITY_ROUTES = "priority-current-n02-route-identities-20260930"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class ShikokuKyushuPairSourcePinnedTests(unittest.TestCase):
    def test_exact_day_and_source_pinning(self):
        kyushu = json.loads((BASE / "candidates/jr-kyushu-kirameki2-20260930.json").read_text())
        kaio = json.loads((BASE / "candidates/jr-kyushu-kaio2-20260930.json").read_text())
        shikoku = json.loads((BASE / "candidates/jr-shikoku-nanpu6-20260930.json").read_text())
        nanpu8 = json.loads((BASE / "candidates/jr-shikoku-nanpu8-20260930.json").read_text())
        self.assertEqual(kyushu["source_url"],
                         "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00086001.html?c=28283&ym=202609&d=30")
        self.assertEqual(kaio["source_url"],
                         "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0019/00192701.html?c=28283&ym=202609&d=30")
        self.assertEqual([source["url_or_locator"] for source in shikoku["sources"]], [
            "https://timetable.jr-odekake.net/train-timetable/162031?date=20260930",
            "https://timetable.jr-odekake.net/line-timetable/2473?day=30&month=9&year=2026",
        ])
        self.assertEqual(nanpu8["sources"][0]["url_or_locator"],
                         "https://timetable.jr-odekake.net/train-timetable/59411?date=20260930")
        self.assertEqual({row["service_date"] for row in rows(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")}, {"2026-09-30"})
        for calendar in rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl"):
            self.assertEqual(sum(calendar[day] for day in (
                "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")), 0)

    def test_calls_are_exact_and_preserve_one_sided_clocks(self):
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        self.assertEqual({row["train_number"] for row in trips.values()}, {"52M", "1092H", "36D", "38D"})
        self.assertEqual(len(stops), 40)
        for candidate_name in ("jr-kyushu-kirameki2-20260930.json",
                               "jr-kyushu-kaio2-20260930.json",
                               "jr-shikoku-nanpu6-20260930.json",
                               "jr-shikoku-nanpu8-20260930.json"):
            candidate = json.loads((BASE / "candidates" / candidate_name).read_text())
            trip = candidate["trip"]
            actual = sorted((row for row in stops if row["trip_id"] == trip["trip_id"]),
                            key=lambda row: row["stop_sequence"])
            expected = trip["stop_times"]
            self.assertEqual(len(actual), len(expected))
            self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                              for row in actual],
                             [(row["arrival_time"], row["departure_time"], row["platform"])
                              for row in expected])
            self.assertIsNone(actual[0]["arrival_time"])
            self.assertIsNone(actual[-1]["departure_time"])
            self.assertEqual([row["stop_sequence"] for row in actual], list(range(1, len(actual) + 1)))

    def test_reviewed_current_routes_are_partial_and_operator_boundaries_remain_open(self):
        completeness = rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        by_trip = {}
        for row in completeness:
            by_trip.setdefault(row["entity_id"], {})[row["dimension"]] = row["status"]
        self.assertEqual(len(by_trip), 4)
        target_ids = {
            "jr-kyushu.kaio.2.2026-09-30",
            "jr-kyushu.kirameki.2.2026-09-30",
        }
        for trip_id, dimensions in by_trip.items():
            self.assertEqual(dimensions["stops"], "verified")
            self.assertEqual(dimensions["times"], "verified")
            self.assertEqual(dimensions["operator"], "unknown")
            self.assertEqual(dimensions["route_lines"],
                             "partial" if trip_id in target_ids else "unknown")
        route_rows = rows(BASE / f"normalized/trip-lines/{PRIORITY_ROUTES}/seeds.jsonl")
        expected = {
            "jr-kyushu.kaio.2.2026-09-30":
                ["jp-九州旅客鉄道-鹿児島線", "jp-九州旅客鉄道-篠栗線"]
                + ["jp-九州旅客鉄道-筑豊線"] * 3,
            "jr-kyushu.kirameki.2.2026-09-30":
                ["jp-九州旅客鉄道-鹿児島線"] * 9,
        }
        for trip_id, line_ids in expected.items():
            actual = sorted((row for row in route_rows if row["trip_id"] == trip_id),
                            key=lambda row: row["sequence"])
            self.assertEqual([row["current_n02_line_id"] for row in actual], line_ids)
            self.assertTrue(all(row["reference_kind"] == "current_n02" for row in actual))
            self.assertTrue(all(row["source_id"] ==
                                "jr-kyushu-line-inventory-priority-route-batch-a"
                                for row in actual))
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
