"""Reviewed JR East equipment stays tied to the published train and service date."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-east-reservation-equipment-20260930"
DAY = "2026-09-30"
GREEN = {
    "jr-east.kaiji.2.exact-2026-09-30",
    "jr-east.kaiji.6.exact-2026-09-30",
    "jr-east.kaiji.10.exact-2026-09-30",
    "jr-east.kaiji.11.exact-2026-09-30",
    "jr-east.odoriko.1.3021m-izukyu-shimoda.2026-09-29",
}
CROSS_DAY = {
    "jr-east.wakashio.17.weekday-requested-dates.2026-09-29",
    "jr-east.odoriko.1.3021m-izukyu-shimoda.2026-09-29",
    "jr-east.odoriko.1.4021m-shuzenji.2026-09-29",
}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class EastReservationEquipmentTests(unittest.TestCase):
    def test_exact_date_formations_preserve_known_and_unknown_fields(self):
        candidate = json.loads((BASE / "candidates/jr-east-reservation-equipment-20260930.json")
                               .read_text(encoding="utf-8"))
        expected = {row["trip_id"]: row for row in candidate["trips"]}
        formations = rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(expected), 11)
        self.assertEqual(len(formations), 11)
        self.assertEqual({row["trip_id"] for row in formations}, set(expected))
        self.assertEqual(sum(row["green_car_available"] is True for row in formations), 5)
        for row in formations:
            trip_id = row["trip_id"]
            self.assertEqual((row["service_date"], row["evidence_kind"], row["all_reserved"]),
                             (DAY, "planned", True))
            self.assertIs(row["green_car_available"], True if trip_id in GREEN else None)
            self.assertEqual(row["source_id"], expected[trip_id]["source_id"])
            for unknown in ("formation_label", "car_count", "vehicle_series", "reserved_seat_capacity"):
                self.assertIsNone(row.get(unknown))
        self.assertFalse((BASE / f"normalized/trip-formation-cars/{SUFFIX}").exists())

    def test_provenance_and_cross_day_occurrences(self):
        candidate = json.loads((BASE / "candidates/jr-east-reservation-equipment-20260930.json")
                               .read_text(encoding="utf-8"))
        source_rows = [row for path in (BASE / "sources").glob("source-registry*.jsonl")
                       for row in rows(path)]
        sources = {row["source_id"]: row for row in source_rows}
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        completeness = rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        self.assertEqual(len(facts), 16)
        self.assertEqual(len(completeness), 11)
        for row in candidate["trips"]:
            self.assertEqual(sources[row["source_id"]]["url_or_locator"], row["source_url"])
            fields = {fact["field_name"] for fact in facts if fact["entity_id"] == row["trip_id"]}
            self.assertEqual(fields, {"formation.all_reserved"}
                             | ({"formation.green_car_available"} if row["trip_id"] in GREEN else set()))
        exceptions = [row for path in (BASE / "normalized/calendar-exceptions").glob("**/*.jsonl")
                      for row in rows(path)]
        trips = {row["trip_id"]: row
                 for path in (BASE / "normalized/trips").glob("**/*.jsonl") for row in rows(path)}
        for trip_id in CROSS_DAY:
            calendar_id = trips[trip_id]["calendar_id"]
            self.assertIn((calendar_id, DAY, "add"), {
                (row["calendar_id"], row["service_date"], row["exception_type"])
                for row in exceptions})
        self.assertTrue(all(row["service_date"] == DAY
                            for row in rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")))


if __name__ == "__main__":
    unittest.main()
