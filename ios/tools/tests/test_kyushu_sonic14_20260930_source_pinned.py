"""Exact-date timetable and planned-guide checks for Sonic 14."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-sonic14-20260930"
TRIP = "jr-kyushu.sonic.14.2026-09-30"
URL = "https://www.jrkyushu-timetable.jp/sp/2610/0011/00117401.html?t=2874200e&d=20260930"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class Sonic14SourcePinnedTests(unittest.TestCase):
    def test_dated_source_and_eight_calls(self):
        candidate = json.loads((BASE / "candidates/jr-kyushu-sonic14-20260930.json").read_text())
        self.assertEqual((candidate["service_date"], candidate["source_url"],
                          candidate["trip"]["train_number"]), ("2026-09-30", URL, "3014M"))
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        self.assertEqual((len(source), source[0]["url_or_locator"], source[0]["automated_extraction_allowed"]),
                         (1, URL, False))
        stops = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"),
                       key=lambda row: row["stop_sequence"])
        self.assertEqual(len(stops), 8)
        self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"]) for row in stops],
                         [(stop["arrival_time"], stop["departure_time"], stop["platform"])
                          for stop in candidate["trip"]["stop_times"]])
        self.assertEqual((stops[2]["arrival_time"], stops[2]["departure_time"]), ("09:29", "09:29"))
        self.assertEqual([row["platform"] for row in stops],
                         ["3", None, None, None, "4", None, "3", "6"])

    def test_planned_885_formation_and_conservative_car_seats(self):
        formation = rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(formation), 1)
        self.assertEqual((formation[0]["trip_id"], formation[0]["evidence_kind"],
                          formation[0]["vehicle_series"], formation[0]["car_count"],
                          formation[0]["all_reserved"], formation[0]["green_car_available"]),
                         (TRIP, "planned", "885", 6, False, True))
        self.assertIn("Actual consist unverified", formation[0]["notes"])
        cars = sorted(rows(BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl"),
                      key=lambda row: row["car_sequence"])
        self.assertEqual([car["car_number"] for car in cars], ["1", "2", "3", "4", "5", "6"])
        self.assertTrue(all(car["source_id"] == "jr-kyushu-sonic-885-diagram-20260930" for car in cars))
        self.assertIn("Green and reserved ordinary", cars[0]["notes"])
        self.assertEqual((cars[1]["seat_class"], cars[1]["reservation_type"]), ("ordinary", "reserved"))
        for car in cars[2:4]:
            self.assertNotIn("seat_class", car)
            self.assertNotIn("reservation_type", car)
        self.assertTrue(all((car["seat_class"], car["reservation_type"]) ==
                            ("ordinary", "non_reserved") for car in cars[4:]))
        facts = {(row["field_name"], row["source_id"]) for row in
                 rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")}
        self.assertIn(("formation.vehicle_series", "jr-kyushu-sonic-configuration-guide-20260930"), facts)
        self.assertIn(("formation.car_count", "jr-kyushu-sonic-equipment-guide-20260930"), facts)

    def test_exact_day_only_and_unknown_routes(self):
        dates = {row["service_date"] for row in
                 rows(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")}
        self.assertEqual(dates, {"2026-09-30"})
        completeness = {row["dimension"]: row["status"] for row in
                        rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")}
        self.assertEqual((completeness["operator"], completeness["route_lines"]), ("unknown", "unknown"))
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
