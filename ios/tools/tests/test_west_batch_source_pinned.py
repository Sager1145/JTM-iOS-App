"""Source-pinned checks for the reviewed 2026 WEST EXPRESS GINGA batch."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-west-ginga-kumano-2026-summer-west-batch.json"


def jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class WestBatchSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.sources = {
            row["source_id"]: row
            for row in jsonl(BASE / "sources/source-registry-west-batch.jsonl")
        }
        cls.trips = {
            row["trip_id"]: row
            for row in jsonl(BASE / "normalized/trips/reviewed-west-batch/seeds-west-batch.jsonl")
        }
        cls.facts = jsonl(BASE / "normalized/fact-sources-west-batch.jsonl")
        cls.completeness = jsonl(BASE / "normalized/fact-completeness-west-batch.jsonl")
        cls.research = jsonl(BASE / "normalized/research-queue-west-batch.jsonl")
        cls.calendars = jsonl(
            BASE / "normalized/calendars/reviewed-west-batch/seeds-west-batch.jsonl")
        cls.calendar_exceptions = jsonl(
            BASE / "normalized/calendar-exceptions/reviewed-west-batch/seeds-west-batch.jsonl")

    def test_candidate_pins_official_train_pages_and_september_30_daytime_service(self):
        day = self.candidate["trip"]
        night = self.candidate["night_trip"]
        self.assertEqual(day["train_number"], "8078M")
        self.assertEqual(night["train_number"], "8077M")
        self.assertIn("2026-09-30", day["operating_dates"])
        supplemental = {
            source["source_id"]: source
            for source in self.candidate["supplemental_sources"]
        }
        self.assertEqual(supplemental[day["train_number_source_id"]]["url_or_locator"],
                         "https://timetable.jr-odekake.net/train-timetable/193801?date=20260930")
        self.assertEqual(supplemental[night["train_number_source_id"]]["url_or_locator"],
                         "https://timetable.jr-odekake.net/train-timetable/193791?date=20260925")

    def test_normalized_trips_retain_internal_numbers_without_inventing_public_numbers(self):
        by_template = {
            "kumano-day": "8078M",
            "kumano-night": "8077M",
        }
        for template, expected in by_template.items():
            trip = next(row for trip_id, row in self.trips.items() if f".{template}." in trip_id)
            self.assertEqual(trip["train_number"], expected)
            self.assertIsNone(trip["public_number"])

    def test_september_30_cutoff_materializes_daytime_calendar_source(self):
        day_trip = next(row for trip_id, row in self.trips.items() if ".kumano-day." in trip_id)
        calendar_id = day_trip["calendar_id"]
        calendar = next(row for row in self.calendars if row["calendar_id"] == calendar_id)
        self.assertEqual(calendar["valid_until"], "2026-10-01")
        self.assertTrue(any(
            row["calendar_id"] == calendar_id
            and row["service_date"] == "2026-09-30"
            and row["exception_type"] == "add"
            for row in self.calendar_exceptions
        ))

    def test_train_number_facts_point_to_reuse_blocked_official_sources(self):
        number_facts = [row for row in self.facts if row["field_name"] == "train_number"]
        self.assertEqual(len(number_facts), 2)
        for fact in number_facts:
            self.assertEqual(fact["verification_status"], "verified")
            self.assertEqual(fact["confidence"], "high")
            source = self.sources[fact["source_id"]]
            self.assertEqual(source["source_type"], "official_train_timetable")
            self.assertEqual(source["license_status"], "explicit_reproduction_and_processing_prohibition")
            self.assertEqual(source["redistribution_status"], "verification_only")
            self.assertIs(source["automated_extraction_allowed"], False)

        statuses = {
            (row["entity_id"], row["dimension"]): row["status"]
            for row in self.completeness
        }
        for trip_id in self.trips:
            self.assertEqual(statuses[(trip_id, "train_number")], "verified")
        self.assertFalse(any(row["missing_dimension"] == "train_number" for row in self.research))


if __name__ == "__main__":
    unittest.main()
