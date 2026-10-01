"""Source-pinned checks for the exact-date JR West Yakumo 15 discovery seed."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "discovery-west-2026"
TRIP_ID = "jr-west.yakumo.15.2026-09-30"


def jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class WestDiscovery2026SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(
            (BASE / "candidates/jr-west-yakumo15-20260930-discovery.json").read_text(encoding="utf-8")
        )
        cls.sources = jsonl(BASE / "sources/source-registry-discovery-west-2026.jsonl")
        cls.trips = jsonl(BASE / f"normalized/trips/reviewed-{SUFFIX}/seeds.jsonl")
        cls.stops = jsonl(BASE / f"normalized/stop-times/reviewed-{SUFFIX}/seeds.jsonl")
        cls.calendars = jsonl(BASE / f"normalized/calendars/reviewed-{SUFFIX}/seeds.jsonl")
        cls.exceptions = jsonl(BASE / f"normalized/calendar-exceptions/reviewed-{SUFFIX}/seeds.jsonl")
        cls.facts = jsonl(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")

    def test_directory_inventory_is_distinct_and_explicitly_limited(self):
        inventory = next(row for row in self.sources if row["source_type"] == "official_service_inventory")
        family_rows = [row for row in self.sources if row["source_type"] == "official_service_detail"]
        self.assertEqual(len(family_rows), 23)
        self.assertEqual(len({row["title"] for row in family_rows}), 23)
        self.assertIn("not proof that JR West is the sole operator", inventory["notes"])
        self.assertIn("sightseeing trains", inventory["notes"])

    def test_exact_date_source_is_pinned_and_verification_only(self):
        source = next(row for row in self.sources if row["source_id"] == self.candidate["trip"]["source_id"])
        self.assertEqual(source["effective_date"], "2026-09-30")
        self.assertIn("date=20260930", source["url_or_locator"])
        self.assertEqual(source["license_status"], "explicit_reproduction_and_processing_prohibition")
        self.assertEqual(source["redistribution_status"], "verification_only")
        self.assertFalse(source["automated_extraction_allowed"])

    def test_only_exact_september_30_occurrence_is_normalized(self):
        self.assertEqual(len(self.trips), 1)
        self.assertEqual(self.trips[0]["trip_id"], TRIP_ID)
        self.assertEqual(self.trips[0]["train_number"], "1015M")
        self.assertEqual(self.trips[0]["public_number"], "15")
        self.assertEqual(len(self.calendars), 1)
        self.assertTrue(all(self.calendars[0][day] == 0 for day in (
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
        )))
        self.assertEqual(self.exceptions, [{
            "calendar_id": "jr-west.yakumo.15.2026-09-30.calendar",
            "exception_type": "add",
            "reason": "Exact date parameter and displayed September 2026 calendar; daily label not expanded",
            "service_date": "2026-09-30",
            "source_id": "jr-west-odekake-yakumo15-1015m-20260930",
        }])

    def test_passenger_calls_and_clocks_match_reviewed_page(self):
        self.assertEqual([row["stop_sequence"] for row in self.stops], list(range(1, 12)))
        station_ids = jsonl(BASE / f"normalized/station-identities-{SUFFIX}.jsonl")
        local_names = {row["station_id"]: row["name_snapshot"] for row in station_ids}
        for path in BASE.glob("normalized/station-identities*.jsonl"):
            for row in jsonl(path):
                local_names.setdefault(row["station_id"], row["name_snapshot"])
        self.assertEqual([local_names[row["station_id"]] for row in self.stops], [
            "岡山", "倉敷", "備中高梁", "新見", "根雨", "米子",
            "安来", "松江", "玉造温泉", "宍道", "出雲市",
        ])
        self.assertEqual((self.stops[0]["arrival_time"], self.stops[0]["departure_time"]), (None, "14:13"))
        self.assertEqual((self.stops[-1]["arrival_time"], self.stops[-1]["departure_time"]), ("17:23", None))
        self.assertEqual(
            [(row["arrival_time"], row["departure_time"]) for row in self.stops[1:-1]],
            [
                ("14:24", "14:24"), ("14:47", "14:48"), ("15:15", "15:16"),
                ("16:03", "16:04"), ("16:27", "16:28"), ("16:35", "16:35"),
                ("16:51", "16:54"), ("17:02", "17:02"), ("17:10", "17:10"),
            ],
        )

    def test_unsourced_operator_and_route_dimensions_remain_unknown(self):
        by_dimension = {row["dimension"]: row for row in self.facts if row["entity_id"] == TRIP_ID}
        self.assertEqual(by_dimension["operator"]["status"], "unknown")
        self.assertEqual(by_dimension["route_lines"]["status"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/reviewed-{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/reviewed-{SUFFIX}/seeds.jsonl").exists())

    def test_official_english_name_has_its_own_source(self):
        names = jsonl(BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl")
        english = [row for row in names if row["language"] == "en"]
        self.assertEqual([(row["name"], row["source_id"]) for row in english], [
            ("Yakumo", "jr-west-yakumo-official-english-2026")
        ])
        source = next(row for row in self.sources if row["source_id"] == english[0]["source_id"])
        self.assertEqual(source["url_or_locator"], "https://www.westjr.co.jp/global/en/train/yakumo/")


if __name__ == "__main__":
    unittest.main()
