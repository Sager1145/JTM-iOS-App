"""The dated Sonic formations follow JR Kyushu's published planned diagrams."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-shikoku-seat-equipment-20260930"
DAY = "2026-09-30"
SONIC = {2: ("883", 7), 4: ("883", 7), 6: ("885", 6),
         8: ("883", 7), 10: ("885", 6), 12: ("885", 6)}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class KyushuShikokuSeatEquipmentTests(unittest.TestCase):
    def test_sonic_planned_series_counts_and_unchanged_seat_categories(self):
        formations = {row["trip_id"]: row for row in
                      rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")}
        self.assertEqual(len(formations), 13)
        sources = {row["source_id"]: row for path in (BASE / "sources").glob("source-registry*.jsonl")
                   for row in rows(path)}
        for number, (series, count) in SONIC.items():
            trip_id = f"jr-kyushu.sonic.{number}.{DAY}"
            formation = formations[trip_id]
            candidate = json.loads((BASE / f"candidates/jr-kyushu-sonic{number}-20260930.json")
                                   .read_text(encoding="utf-8"))
            self.assertEqual((formation["service_date"], formation["evidence_kind"],
                              formation["vehicle_series"], formation["car_count"],
                              formation["all_reserved"], formation["green_car_available"]),
                             (DAY, "planned", series, count, False, True))
            self.assertEqual(formation["source_id"], candidate["source_id"])
            self.assertEqual(sources[formation["source_id"]]["url_or_locator"], candidate["source_url"])
            self.assertIn("d=20260930", candidate["source_url"])
            self.assertIn("グリーン車指定席", candidate["trip"]["seat_description_snapshot"])
            self.assertIn("普通車一部指定席", candidate["trip"]["seat_description_snapshot"])
            self.assertIn("actual consist unverified", formation["notes"])

    def test_configuration_sources_and_conservative_car_rows(self):
        sources = {row["source_id"]: row for path in (BASE / "sources").glob("source-registry*.jsonl")
                   for row in rows(path)}
        self.assertEqual(sources["jr-kyushu-sonic-configuration-guide-20260930"]["url_or_locator"],
                         "https://www.jrkyushu.co.jp/english/train/sonic.html")
        self.assertEqual(sources["jr-kyushu-sonic-equipment-guide-20260930"]["url_or_locator"],
                         "https://www.jrkyushu.co.jp/train/kids/guardian/train_equipment/index.html")
        cars = rows(BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl")
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        self.assertEqual(len(cars), sum(count for _, count in SONIC.values()))
        for number, (series, count) in SONIC.items():
            trip_id = f"jr-kyushu.sonic.{number}.{DAY}"
            formation_id = f"{trip_id}.formation.{DAY}"
            mine = {int(car["car_number"]): car for car in cars if car["formation_id"] == formation_id}
            self.assertEqual(set(mine), set(range(1, count + 1)))
            diagram_source = f"jr-kyushu-sonic-{series}-diagram-20260930"
            self.assertTrue(all(car["source_id"] == diagram_source and car["vehicle_series"] == series
                                for car in mine.values()))
            self.assertEqual((mine[2]["seat_class"], mine[2]["reservation_type"]),
                             ("ordinary", "reserved"))
            self.assertIn("Green and reserved ordinary", mine[1]["notes"])
            for car_number in (3, 4):
                self.assertNotIn("seat_class", mine[car_number])
                self.assertNotIn("reservation_type", mine[car_number])
            for car_number in range(5, count + 1):
                self.assertEqual((mine[car_number]["seat_class"], mine[car_number]["reservation_type"]),
                                 ("ordinary", "non_reserved"))
            provenance = {(fact["field_name"], fact["source_id"]) for fact in facts
                          if fact["entity_id"] == trip_id}
            self.assertIn(("formation.vehicle_series", "jr-kyushu-sonic-configuration-guide-20260930"),
                          provenance)
            self.assertIn(("formation.car_count", "jr-kyushu-sonic-equipment-guide-20260930"),
                          provenance)
        self.assertTrue(all(not sources[car["source_id"]]["automated_extraction_allowed"] for car in cars))


if __name__ == "__main__":
    unittest.main()
