"""Source-pinned checks for the exact-date JR Kyushu Sonic 1 addition."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "kyushu-sonic1-20260929"
TRIP_ID = "jr-kyushu.sonic.1.2026-09-29"
SOURCE_ID = "jr-kyushu-sonic1-20260929-exact"


def load_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class KyushuSonic1SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(
            (BASE / "candidates/jr-kyushu-sonic1-20260929.json").read_text(encoding="utf-8")
        )
        cls.registry = load_jsonl(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        cls.services = load_jsonl(BASE / f"normalized/services-{SUFFIX}.jsonl")
        cls.trips = load_jsonl(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        cls.stops = load_jsonl(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        cls.exceptions = load_jsonl(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        cls.completeness = load_jsonl(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        cls.queue = load_jsonl(BASE / f"normalized/research-queue-{SUFFIX}.jsonl")

    def test_official_source_and_single_date_are_pinned(self):
        self.assertEqual(len(self.registry), 1)
        source = self.registry[0]
        self.assertEqual(source["source_id"], SOURCE_ID)
        self.assertEqual(
            source["url_or_locator"],
            "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0001/00013201.html"
            "?c=28283&ym=202609&d=29",
        )
        self.assertFalse(source["automated_extraction_allowed"])
        self.assertEqual(source["redistribution_status"], "verification_only")
        self.assertEqual(self.candidate["service_date"], "2026-09-29")
        self.assertEqual(self.exceptions, [{
            "calendar_id": TRIP_ID + ".calendar",
            "exception_type": "add",
            "reason": "Exact date-qualified official train-detail page; no recurrence inferred",
            "service_date": "2026-09-29",
            "source_id": SOURCE_ID,
        }])

    def test_limited_express_identity_and_complete_sixteen_call_table(self):
        self.assertEqual(len(self.services), 1)
        self.assertEqual(
            (self.services[0]["service_id"], self.services[0]["canonical_name"],
             self.services[0]["service_class"]),
            ("sonic", "ソニック", "limited_express"),
        )
        self.assertEqual(len(self.trips), 1)
        self.assertEqual(
            (self.trips[0]["trip_id"], self.trips[0]["public_number"],
             self.trips[0]["train_number"], self.trips[0]["direction"]),
            (TRIP_ID, "1", "3001M", "博多→大分"),
        )
        expected_names = [
            "博多", "香椎", "福間", "赤間", "折尾", "黒崎", "小倉", "朽網",
            "行橋", "宇島", "中津", "柳ケ浦", "宇佐", "杵築", "別府", "大分",
        ]
        self.assertEqual(
            [row["name_snapshot"] for row in self.candidate["trip"]["stop_times"]],
            expected_names,
        )
        self.assertEqual(len(self.stops), 16)
        self.assertEqual(
            (self.stops[0]["departure_time"], self.stops[6]["arrival_time"],
             self.stops[6]["departure_time"], self.stops[-1]["arrival_time"]),
            ("06:21", "07:11", "07:14", "08:44"),
        )
        self.assertEqual(
            (self.candidate["trip"]["stop_times"][7]["source_marker"],
             self.candidate["trip"]["stop_times"][7]["source_marker_meaning"]),
            ("★", "臨時停車"),
        )

    def test_evidence_bounds_leave_route_and_operator_open(self):
        statuses = {
            row["dimension"]: row["status"]
            for row in self.completeness if row["entity_id"] == TRIP_ID
        }
        self.assertEqual(statuses["identity"], "verified")
        self.assertEqual(statuses["validity_calendar"], "verified")
        self.assertEqual(statuses["origin_destination"], "verified")
        self.assertEqual(statuses["stops"], "verified")
        self.assertEqual(statuses["times"], "verified")
        self.assertEqual(statuses["operator"], "unknown")
        self.assertEqual(statuses["route_lines"], "unknown")
        self.assertEqual(
            {(row["missing_dimension"], row["status"]) for row in self.queue},
            {("operator", "open"), ("route_lines", "open"), ("provenance", "license_blocked")},
        )
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
