"""Current official Thunderbird guide supports a bounded standard nine-car plan."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-thunderbird-planned-nine-car-20260930"
DAY = "2026-09-30"
EXPECTED = {f"jr-west.thunderbird.{number}.{DAY}" for number in range(1, 51)}
GUIDE = "jr-west-thunderbird-current-nine-car-guide-20260930"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class ThunderbirdStandardPlanTests(unittest.TestCase):
    def test_source_and_bounded_standard_plan(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")[0]
        self.assertEqual(set(candidate["trip_ids"]), EXPECTED)
        self.assertEqual((candidate["service_date"], candidate["planned_car_count"],
                          candidate["evidence_kind"], candidate["women_only_seat_car_number"]),
                         (DAY, 9, "planned", "3"))
        self.assertEqual((source["source_id"], source["url_or_locator"],
                          source["redistribution_status"]),
                         (GUIDE, "https://www.jr-odekake.net/railroad/train/thunderbird/",
                          "verification_only"))
        self.assertEqual(candidate["standard_reserved_seat_capacity"], 546)
        self.assertEqual(candidate["standard_seats_by_car"], [32, 64, 72, 50, 72, 64, 64, 64, 64])
        self.assertEqual(candidate["per_car_plan"], [
            {"car_number": str(number), "seat_class": "green" if number == 1 else "ordinary",
             "reservation_type": "reserved"} for number in range(1, 10)])

    def test_all_reviewed_formations_preserve_actual_dispatch_uncertainty(self):
        formations = {row["trip_id"]: row
                      for path in BASE.glob("normalized/trip-formations/**/*.jsonl")
                      for row in rows(path) if row["trip_id"] in EXPECTED}
        cars = rows(BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl")
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        self.assertEqual(set(formations), EXPECTED)
        self.assertEqual(len(cars), 450)
        self.assertEqual(len(facts), 250)
        for tid, formation in formations.items():
            with self.subTest(trip=tid):
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["car_count"], formation["reserved_seat_capacity"],
                                  formation["all_reserved"],
                                  formation["green_car_available"]),
                                 (DAY, "planned", 9, 546, True, True))
                self.assertIn("女性専用席があります", formation["notes"])
                self.assertIn("Actual dispatch", formation["notes"])
                self.assertNotIn("vehicle_series", formation)
                listed = sorted((row for row in cars if row["formation_id"] == formation["formation_id"]),
                                key=lambda row: row["car_sequence"])
                self.assertEqual([row["car_number"] for row in listed],
                                 [str(number) for number in range(1, 10)])
                self.assertEqual([row["seat_class"] for row in listed],
                                 ["green"] + ["ordinary"] * 8)
                self.assertTrue(all(row["reservation_type"] == "reserved" and
                                    row["source_id"] == GUIDE for row in listed))
                self.assertIn("women-only", listed[2]["notes"])
                self.assertIn("72 seats", listed[2]["notes"])
                cited = {row["field_name"]: row["source_id"] for row in facts
                         if row["entity_id"] == tid}
                self.assertEqual(cited["formation.women_only_seat_available"],
                                 formation["source_id"])
                self.assertEqual(cited["formation.women_only_seat_car"], GUIDE)
                self.assertEqual(cited["formation.reserved_seat_capacity"], GUIDE)


if __name__ == "__main__":
    unittest.main()
