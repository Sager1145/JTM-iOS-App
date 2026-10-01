"""Checks for the second exact-date Shikoku/Kyushu limited express batch."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-shikoku-kyushu-20260930-next"
PRIORITY_ROUTES = "priority-current-n02-route-identities-20260930"
CANDIDATES = (
    "jr-kyushu-relay-kamome1-20260930.json",
    "jr-kyushu-midori7-20260930.json",
    "jr-shikoku-shimanto2-20260930.json",
)


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class ShikokuKyushuNextSourcePinnedTests(unittest.TestCase):
    def test_exact_day_and_sources(self):
        candidates = [json.loads((BASE / "candidates" / name).read_text()) for name in CANDIDATES]
        self.assertEqual([c.get("source_url") for c in candidates[:2]], [
            "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0018/00189101.html?c=28283&ym=202609&d=30",
            "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00085901.html?c=28283&ym=202609&d=30",
        ])
        self.assertEqual([s["url_or_locator"] for s in candidates[2]["sources"]], [
            "https://timetable.jr-odekake.net/train-timetable/90141?date=20260930",
            "https://timetable.jr-odekake.net/line-timetable/2473?day=30&month=9&year=2026",
        ])
        self.assertEqual(len(rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")), 2)
        self.assertEqual({r["service_date"] for r in rows(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")}, {"2026-09-30"})
        for calendar in rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl"):
            self.assertEqual(sum(calendar[day] for day in (
                "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")), 0)

    def test_passenger_calls_and_null_sides(self):
        trips = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        self.assertEqual({trip["train_number"] for trip in trips}, {"2001H", "4007M", "2002D"})
        self.assertEqual(len(stops), 29)
        self.assertNotIn("2001G", {trip["train_number"] for trip in trips})
        for candidate_name in CANDIDATES:
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

    def test_current_routes_are_partial_and_operator_boundaries_remain_open(self):
        completeness = rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        by_trip = {}
        for row in completeness:
            by_trip.setdefault(row["entity_id"], {})[row["dimension"]] = row["status"]
        self.assertEqual(len(by_trip), 3)
        for dimensions in by_trip.values():
            self.assertEqual(dimensions["stops"], "verified")
            self.assertEqual(dimensions["times"], "verified")
            self.assertEqual(dimensions["operator"], "unknown")
            self.assertEqual(dimensions["route_lines"], "partial")
        route_rows = rows(BASE / f"normalized/trip-lines/{PRIORITY_ROUTES}/seeds.jsonl")
        expected = {
            "jr-kyushu.relay-kamome.1.2026-09-30":
                ["jp-九州旅客鉄道-鹿児島線"] * 2
                + ["jp-九州旅客鉄道-長崎線"] * 3
                + ["jp-九州旅客鉄道-佐世保線"],
            "jr-kyushu.midori.7.2026-09-30":
                ["jp-九州旅客鉄道-鹿児島線"] * 2
                + ["jp-九州旅客鉄道-長崎線"] * 3
                + ["jp-九州旅客鉄道-佐世保線"] * 4,
            "jr-shikoku.shimanto.2.2026-09-30":
                ["jp-四国旅客鉄道-土讃線"] * 8
                + ["jp-四国旅客鉄道-予讃線"] * 3,
        }
        for trip_id, line_ids in expected.items():
            actual = sorted((row for row in route_rows if row["trip_id"] == trip_id),
                            key=lambda row: row["sequence"])
            self.assertEqual([row["current_n02_line_id"] for row in actual], line_ids)
            self.assertTrue(all(row["reference_kind"] == "current_n02" for row in actual))
            self.assertTrue(all(row.get("rail_history_id") is None for row in actual))
            source_id = ("jr-shikoku-network-priority-route-batch-a"
                         if trip_id.startswith("jr-shikoku.")
                         else "jr-kyushu-line-inventory-priority-route-batch-a")
            self.assertTrue(all(row["source_id"] == source_id for row in actual))
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
