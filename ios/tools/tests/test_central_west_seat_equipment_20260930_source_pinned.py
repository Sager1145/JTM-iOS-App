"""Planned seats stay tied to the exact September 30 train instances."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-central-west-seat-equipment-20260930"
DAY = "2026-09-30"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class CentralWestSeatEquipmentTests(unittest.TestCase):
    def test_planned_seat_facts_preserve_unknown_consist_fields(self):
        candidate = json.loads((BASE / "candidates/jr-central-west-seat-equipment-20260930.json")
                               .read_text(encoding="utf-8"))
        expected = {row["trip_id"]: row for row in candidate["trips"]}
        formations = rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(expected), 15)
        self.assertEqual({row["trip_id"] for row in formations}, set(expected))
        for formation in formations:
            source = expected[formation["trip_id"]]
            self.assertEqual((formation["service_date"], formation["evidence_kind"],
                              formation["all_reserved"], formation["source_id"]),
                             (DAY, "planned", source["all_reserved"], source["source_id"]))
            self.assertIs(formation.get("green_car_available"), source["green_car_available"])
            if (formation["trip_id"] == "jr-west.haruka.1.2026-09-30"
                    or formation["trip_id"].startswith("jr-west.thunderbird.")):
                self.assertEqual(formation.get("car_count"), 9)
            else:
                self.assertIsNone(formation.get("car_count"))
            if formation["trip_id"].startswith("jr-west.thunderbird."):
                self.assertEqual(formation.get("reserved_seat_capacity"), 546)
            else:
                self.assertIsNone(formation.get("reserved_seat_capacity"))
            for unknown in ("vehicle_series", "formation_label"):
                self.assertIsNone(formation.get(unknown))
        self.assertFalse((BASE / f"normalized/trip-formation-cars/{SUFFIX}").exists())

    def test_source_identity_and_date_materialization(self):
        candidate = json.loads((BASE / "candidates/jr-central-west-seat-equipment-20260930.json")
                               .read_text(encoding="utf-8"))
        sources = {row["source_id"]: row
                   for path in (BASE / "sources").glob("source-registry*.jsonl")
                   for row in rows(path)}
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        completeness = rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        self.assertEqual(len(facts), 29)
        self.assertEqual(len(completeness), 15)
        for row in candidate["trips"]:
            self.assertEqual(sources[row["source_id"]]["url_or_locator"], row["source_url"])
            names = {fact["field_name"] for fact in facts if fact["entity_id"] == row["trip_id"]}
            self.assertEqual(names, {"formation.all_reserved"} |
                             ({"formation.green_car_available"} if row["green_car_available"] else set()))
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        dataset, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        materialized = {trip["trip_id"] for trip in timetable.materialize(dataset, DAY)}
        self.assertTrue({row["trip_id"] for row in candidate["trips"]} <= materialized)


if __name__ == "__main__":
    unittest.main()
