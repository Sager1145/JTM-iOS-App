"""Source-pinned checks for the reviewed JR West Inishie 2026-09-27 slice."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-west-inishie-20260927.json"
SUFFIX = "west-inishie-20260927"
BATCH = "reviewed-west-inishie-20260927"


def jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class WestInishie20260927SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.sources = jsonl(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        cls.services = jsonl(BASE / f"normalized/services-{SUFFIX}.jsonl")
        cls.trips = jsonl(BASE / f"normalized/trips/{BATCH}/seeds.jsonl")
        cls.stops = jsonl(BASE / f"normalized/stop-times/{BATCH}/seeds.jsonl")
        cls.calendars = jsonl(BASE / f"normalized/calendars/{BATCH}/seeds.jsonl")
        cls.exceptions = jsonl(BASE / f"normalized/calendar-exceptions/{BATCH}/seeds.jsonl")
        cls.facts = jsonl(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        cls.completeness = jsonl(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        cls.research = jsonl(BASE / f"normalized/research-queue-{SUFFIX}.jsonl")

    def test_candidate_pins_the_visually_reviewed_official_pdf(self):
        source = self.candidate["source"]
        self.assertEqual(source["url_or_locator"],
                         "https://www.westjr.co.jp/press/article/2026/05/15/items/260515_00_press_2026einjiunten.pdf")
        self.assertEqual(source["content_hash"],
                         "0e53aa203fcd480ec92823ba7e7cfd468a856618c79ca3b30e4647c80f6563c1")
        self.assertEqual(source["redistribution_status"], "verification_only")
        self.assertIs(source["automated_extraction_allowed"], False)
        self.assertEqual(self.candidate["selected_service_date"], "2026-09-27")
        self.assertEqual(self.candidate["actual_operation_status"], "unverified_plan")

    def test_exact_selected_date_is_an_exception_not_an_expanded_weekend_claim(self):
        self.assertEqual(len(self.calendars), 1)
        calendar = self.calendars[0]
        self.assertEqual(calendar["valid_from"], "2026-09-27")
        self.assertEqual(calendar["valid_until"], "2026-09-28")
        for weekday in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"):
            self.assertEqual(calendar[weekday], 0)
        self.assertEqual(len(self.exceptions), 1)
        self.assertEqual(self.exceptions[0]["service_date"], "2026-09-27")
        self.assertEqual(self.exceptions[0]["exception_type"], "add")

    def test_directional_public_numbers_and_clocks_are_exact(self):
        self.assertEqual(self.services[0]["service_id"], "inishie")
        self.assertEqual(self.services[0]["service_class"], "limited_express")
        self.assertEqual({trip["public_number"] for trip in self.trips}, {"61", "62"})
        self.assertTrue(all(trip["train_number"] is None for trip in self.trips))

        observed = {
            (trip["public_number"], stop["stop_sequence"]): (
                stop["station_id"], stop["arrival_time"], stop["departure_time"])
            for trip in self.trips
            for stop in self.stops
            if stop["trip_id"] == trip["trip_id"]
        }
        self.assertEqual(observed, {
            ("61", 1): ("jp.n02.006079", None, "10:42"),
            ("61", 2): ("jp.n02.006334", "10:58", None),
            ("61", 3): ("jp.n02.007210", "11:32", None),
            ("62", 1): ("jp.n02.007210", None, "16:13"),
            ("62", 2): ("jp.n02.006334", "16:44", None),
            ("62", 3): ("jp.n02.006079", "17:00", None),
        })

    def test_unprinted_train_numbers_routes_and_uji_departures_remain_unresolved(self):
        statuses = {
            (row["entity_id"], row["dimension"]): row["status"]
            for row in self.completeness
        }
        for trip in self.trips:
            trip_id = trip["trip_id"]
            self.assertEqual(statuses[(trip_id, "train_number")], "unknown")
            self.assertEqual(statuses[(trip_id, "operator")], "unknown")
            self.assertEqual(statuses[(trip_id, "route_lines")], "unknown")
            self.assertEqual(statuses[(trip_id, "times")], "partial")
        self.assertFalse(any(row["field_name"] == "train_number" for row in self.facts))
        self.assertEqual(
            {(row["entity_id"], row["missing_dimension"]) for row in self.research
             if row["missing_dimension"] in {"train_number", "route_lines", "times"}},
            {(trip["trip_id"], dimension) for trip in self.trips
             for dimension in {"train_number", "route_lines", "times"}},
        )
        uji = [stop for stop in self.stops if stop["station_id"] == "jp.n02.006334"]
        self.assertEqual(len(uji), 2)
        self.assertTrue(all(stop["departure_time"] is None for stop in uji))

    def test_source_registry_retains_manual_verification_only_contract(self):
        self.assertEqual(len(self.sources), 1)
        source = self.sources[0]
        self.assertEqual(source["source_type"], "official_planned_exception")
        self.assertEqual(source["license_status"], "no_reuse_grant_identified")
        self.assertEqual(source["redistribution_status"], "verification_only")
        self.assertIs(source["automated_extraction_allowed"], False)


if __name__ == "__main__":
    unittest.main()
