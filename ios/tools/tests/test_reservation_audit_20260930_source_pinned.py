"""The published 2026-09-30 equipment labels stay tied to dated train pages."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
REVIEW = BASE / "candidates/jr-kyushu-shikoku-reservation-audit-20260930.json"
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable

DAY = "2026-09-30"
SUFFIX = "reviewed-kyushu-shikoku-reservations-audit-20260930"


class ReservationAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.review = json.loads(REVIEW.read_text(encoding="utf-8"))
        cls.data, cls.origins = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        cls.sources = {row["source_id"]: row for row in cls.data["source_documents"]}
        cls.formations = {row["trip_id"]: row for index, row in enumerate(cls.data["trip_formations"])
                          if SUFFIX in cls.origins[("trip_formations", index)]}
        cls.facts = [row for index, row in enumerate(cls.data["fact_sources"])
                     if SUFFIX in cls.origins[("fact_sources", index)]]

    def test_all_24_reviewed_trips_have_dated_planned_equipment(self):
        self.assertEqual(len(self.review["trips"]), 24)
        self.assertEqual(set(self.formations), {row["trip_id"] for row in self.review["trips"]})
        for row in self.review["trips"]:
            with self.subTest(trip=row["trip_id"]):
                formation = self.formations[row["trip_id"]]
                source = self.sources[formation["source_id"]]
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["all_reserved"]), (DAY, "planned", False))
                self.assertIsNone(formation.get("car_count"))
                self.assertIsNone(formation.get("vehicle_series"))
                self.assertIsNone(formation.get("formation_label"))
                self.assertIsNone(formation.get("reserved_seat_capacity"))
                self.assertEqual(formation.get("green_car_available"),
                                 True if "グリーン車指定席" in row["printed_equipment"] else None)
                self.assertEqual((source["url_or_locator"], source["effective_date"]),
                                 (row["source_url"], DAY))
                for label in row["printed_equipment"]:
                    self.assertIn(label, formation["notes"])
                self.assertFalse(any(car["formation_id"] == formation["formation_id"]
                                     for car in self.data["trip_formation_cars"]))

    def test_special_equipment_keeps_train_specific_provenance(self):
        by_trip = {row["trip_id"]: row for row in self.review["trips"]}
        nanpu2 = by_trip["jr-shikoku.nanpu.2.2026-09-30"]
        nanpu6 = by_trip["jr-shikoku.nanpu.6.2026-09-30"]
        self.assertIn("アンパンマン列車で運転", nanpu2["printed_equipment"])
        self.assertIn("アンパンマン列車で運転", nanpu6["printed_equipment"])
        self.assertEqual(sum("ＤＸグリーンがあります" in row["printed_equipment"]
                             for row in self.review["trips"]), 4)
        self.assertEqual(sum("グリーン車指定席（４人用グリーン個室連結）" in row["printed_equipment"]
                             for row in self.review["trips"]), 3)
        self.assertEqual(sum(row["trip_id"].startswith("jr-shikoku.")
                             for row in self.review["trips"]), 7)
        self.assertEqual(sum(row["trip_id"].startswith("jr-kyushu.")
                             for row in self.review["trips"]), 17)
        facts = {(row["entity_id"], row["field_name"]): row for row in self.facts}
        for trip in (nanpu2, nanpu6):
            fact = facts[(trip["trip_id"], "formation.service_branding")]
            self.assertEqual(fact["source_id"], self.formations[trip["trip_id"]]["source_id"])
            self.assertIn(trip["train_number"], fact["page_or_locator"])
        relay = self.formations["jr-kyushu.relay-kamome.1.2026-09-30"]
        self.assertNotIn("Ｎ７００Ｓ", relay["notes"])
        self.assertNotIn("６両編成", relay["notes"])

    def test_dataset_and_fact_source_references_validate(self):
        self.assertEqual(timetable.validate_dataset(self.data, self.origins,
                                                    timetable.load_manifest(BASE)), [])
        completeness = [row for index, row in enumerate(self.data["fact_completeness"])
                        if SUFFIX in self.origins[("fact_completeness", index)]]
        self.assertEqual(len(completeness), 24)
        self.assertTrue(all(row["dimension"] == "formation" and row["status"] == "partial"
                            for row in completeness))


if __name__ == "__main__":
    unittest.main()
