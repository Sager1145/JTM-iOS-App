"""Source-pinned tests for the independent JR Kyushu discovery batch."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "kyushu-discovery-2026"
TRIP_ID = "jr-kyushu.kyushu-cross-express.5.2026-09-30"
SOURCE_ID = "jr-kyushu-kyushu-odan5-20260930"


def load_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class KyushuDiscovery2026SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = load_jsonl(BASE / "sources/source-registry-discovery-kyushu-2026.jsonl")
        cls.candidate = json.loads(
            (BASE / "candidates/jr-kyushu-kyushu-odan5-20260930.json").read_text(encoding="utf-8")
        )
        cls.trips = load_jsonl(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        cls.stops = load_jsonl(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        cls.exceptions = load_jsonl(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        cls.completeness = load_jsonl(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")

    def test_curated_inventory_and_exact_day_sources_are_distinct(self):
        by_id = {row["source_id"]: row for row in self.registry}
        self.assertEqual(len(by_id), len(self.registry))
        self.assertGreaterEqual(len(self.registry), 20)
        self.assertIn("jr-kyushu-standard-limited-express-inventory-20260930", by_id)
        self.assertIn("jr-kyushu-ds-limited-express-inventory-20260314", by_id)
        exact = [row for row in self.registry if row.get("effective_date") == "2026-09-30"]
        self.assertGreaterEqual(len(exact), 15)
        self.assertTrue(all(row["automated_extraction_allowed"] is False for row in self.registry))
        self.assertTrue(all(row["redistribution_status"] == "verification_only" for row in self.registry))

    def test_exact_source_and_single_date_are_pinned(self):
        source = next(row for row in self.registry if row["source_id"] == SOURCE_ID)
        self.assertEqual(
            source["url_or_locator"],
            "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0030/00308301.html"
            "?c=28742&d=30&ym=202609",
        )
        self.assertEqual(self.candidate["service_date"], "2026-09-30")
        self.assertEqual(self.candidate["trip"]["train_number"], "1075D")
        self.assertEqual(self.exceptions, [{
            "calendar_id": TRIP_ID + ".calendar",
            "exception_type": "add",
            "reason": "Exact date-qualified official train-detail page; no recurrence inferred",
            "service_date": "2026-09-30",
            "source_id": SOURCE_ID,
        }])

    def test_complete_twelve_stop_sequence_and_clocks(self):
        self.assertEqual(len(self.trips), 1)
        self.assertEqual(self.trips[0]["trip_id"], TRIP_ID)
        self.assertEqual(self.trips[0]["public_number"], "5")
        self.assertEqual(self.trips[0]["train_number"], "1075D")
        names = [row["name_snapshot"] for row in self.candidate["trip"]["stop_times"]]
        self.assertEqual(names, [
            "熊本", "新水前寺", "肥後大津", "立野", "阿蘇", "宮地",
            "豊後荻", "豊後竹田", "緒方", "三重町", "大分", "別府",
        ])
        self.assertEqual(len(self.stops), 12)
        self.assertEqual((self.stops[0]["departure_time"], self.stops[-1]["arrival_time"]), ("15:23", "18:45"))
        self.assertEqual((self.stops[10]["arrival_time"], self.stops[10]["departure_time"]), ("18:30", "18:34"))

    def test_route_and_operator_are_not_promoted(self):
        status = {
            row["dimension"]: row["status"]
            for row in self.completeness if row["entity_id"] == TRIP_ID
        }
        self.assertEqual(status["identity"], "verified")
        self.assertEqual(status["stops"], "verified")
        self.assertEqual(status["times"], "verified")
        self.assertEqual(status["validity_calendar"], "verified")
        self.assertEqual(status["operator"], "unknown")
        self.assertEqual(status["route_lines"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())

    def test_official_english_name_is_source_pinned(self):
        names = load_jsonl(BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl")
        english = [row for row in names if row["language"] == "en"]
        self.assertEqual([(row["name"], row["source_id"]) for row in english], [
            ("KYUSHU ODAN TOKKYU", "jr-kyushu-kyushu-odan-official-english-2026")
        ])
        source = next(row for row in self.registry if row["source_id"] == english[0]["source_id"])
        self.assertEqual(source["url_or_locator"], "https://www.jrkyushu.co.jp/english/train/odan.html")


if __name__ == "__main__":
    unittest.main()
