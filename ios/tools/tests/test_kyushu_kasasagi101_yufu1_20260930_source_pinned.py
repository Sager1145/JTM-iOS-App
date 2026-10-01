"""Source-pinned checks for September 30 Kasasagi 101 and Yufu 1."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-kasasagi101-yufu1-20260930"
CANDIDATES = {
    "jr-kyushu-kasasagi101-20260930.json": (
        "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0019/00194101.html?c=28283&ym=202609&d=30",
        "1001M", "門司港", "肥前鹿島", 15),
    "jr-kyushu-yufu1-20260930.json": (
        "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0016/00167101.html?c=28283&ym=202609&d=30",
        "81D", "博多", "別府", 15),
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class KyushuKasasagiYufuSourcePinnedTests(unittest.TestCase):
    def test_exact_date_sources_and_no_recurring_calendar(self):
        for filename, (url, number, origin, destination, count) in CANDIDATES.items():
            candidate = json.loads((BASE / "candidates" / filename).read_text(encoding="utf-8"))
            self.assertEqual(candidate["candidate_status"], "reviewed_official_html")
            self.assertEqual(candidate["source_url"], url)
            self.assertEqual(candidate["service_date"], "2026-09-30")
        self.assertEqual({row["service_date"] for row in rows(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")}, {"2026-09-30"})
        for calendar in rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl"):
            self.assertEqual(calendar["valid_from"], "2026-09-30")
            self.assertEqual(calendar["valid_until"], "2026-10-01")
            self.assertEqual(sum(calendar[day] for day in (
                "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")), 0)
        self.assertEqual(rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl"), [])

    def test_all_published_passenger_calls(self):
        trips = {row["trip_id"]: row for row in rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(trips), 2)
        self.assertEqual(len(stops), 30)
        for filename, (_, number, origin, destination, count) in CANDIDATES.items():
            trip = json.loads((BASE / "candidates" / filename).read_text(encoding="utf-8"))["trip"]
            self.assertEqual(trips[trip["trip_id"]]["train_number"], number)
            calls = sorted((row for row in stops if row["trip_id"] == trip["trip_id"]),
                           key=lambda row: row["stop_sequence"])
            self.assertEqual(len(calls), count)
            self.assertEqual([row["stop_sequence"] for row in calls], list(range(1, count + 1)))
            self.assertEqual([row["station_id"] for row in (calls[0], calls[-1])],
                             [trips[trip["trip_id"]]["origin_station_id"],
                              trips[trip["trip_id"]]["destination_station_id"]])
            self.assertEqual(trip["stop_times"][0]["name_snapshot"], origin)
            self.assertEqual(trip["stop_times"][-1]["name_snapshot"], destination)
            self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                              for row in calls],
                             [(row["arrival_time"], row["departure_time"], row["platform"])
                              for row in trip["stop_times"]])
            self.assertIsNone(calls[0]["arrival_time"])
            self.assertIsNone(calls[-1]["departure_time"])

    def test_only_new_service_and_unproved_dimensions_stay_open(self):
        self.assertEqual([row["service_id"] for row in rows(
            BASE / f"normalized/services-{SUFFIX}.jsonl")], ["yufu"])
        completeness = rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        by_trip = {}
        for row in completeness:
            by_trip.setdefault(row["entity_id"], {})[row["dimension"]] = row["status"]
        self.assertEqual(len(by_trip), 2)
        for dimensions in by_trip.values():
            self.assertEqual(dimensions["operator"], "unknown")
            self.assertEqual(dimensions["route_lines"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
