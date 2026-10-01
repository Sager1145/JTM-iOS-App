"""Source-pinned checks for two exact Kasasagi 103 train-detail pages."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "kyushu-kasasagi103-20260929-30"
DATES = ("2026-09-29", "2026-09-30")
NAMES = ("博多", "二日市", "鳥栖", "新鳥栖", "佐賀", "江北", "肥前鹿島")
TIMES = (
    (None, "13:16"), ("13:27", "13:27"), ("13:37", "13:38"),
    ("13:41", "13:42"), ("13:54", "13:55"), ("14:04", "14:04"),
    ("14:17", None),
)


def load_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class Kasasagi103SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(
            (BASE / "candidates/jr-kyushu-kasasagi103-20260929-30.json").read_text(encoding="utf-8")
        )
        cls.registry = load_jsonl(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        cls.services = load_jsonl(BASE / f"normalized/services-{SUFFIX}.jsonl")
        cls.trips = load_jsonl(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        cls.stops = load_jsonl(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        cls.exceptions = load_jsonl(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        cls.completeness = load_jsonl(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        cls.queue = load_jsonl(BASE / f"normalized/research-queue-{SUFFIX}.jsonl")

    def test_two_date_qualified_official_pages_and_exact_calendars(self):
        self.assertEqual(tuple(self.candidate["service_dates"]), DATES)
        self.assertEqual(len(self.registry), 2)
        for day, source in zip(DATES, self.registry):
            self.assertEqual(source["effective_date"], day)
            self.assertEqual(
                source["url_or_locator"],
                "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0019/00194501.html"
                f"?c=08291&d={day[-2:]}&ym=202609",
            )
            self.assertFalse(source["automated_extraction_allowed"])
            self.assertEqual(source["redistribution_status"], "verification_only")
        self.assertEqual(
            {(row["service_date"], row["source_id"]) for row in self.exceptions},
            {(day, f"jr-kyushu-kasasagi103-{day.replace('-', '')}-exact") for day in DATES},
        )

    def test_identity_and_all_seven_calls_retain_published_times(self):
        self.assertEqual(len(self.services), 1)
        self.assertEqual(
            (self.services[0]["service_id"], self.services[0]["canonical_name"]),
            ("kasasagi", "かささぎ"),
        )
        self.assertEqual(len(self.trips), 2)
        self.assertEqual(
            {(row["public_number"], row["train_number"], row["direction"]) for row in self.trips},
            {("103", "1003M", "博多→肥前鹿島")},
        )
        self.assertEqual(
            tuple(row["name_snapshot"] for row in self.candidate["trip"]["stop_times"]), NAMES
        )
        for trip in self.trips:
            rows = sorted((row for row in self.stops if row["trip_id"] == trip["trip_id"]), key=lambda row: row["stop_sequence"])
            self.assertEqual(len(rows), 7)
            self.assertEqual(tuple((row["arrival_time"], row["departure_time"]) for row in rows), TIMES)
            self.assertEqual(tuple(row["day_offset"] for row in rows), (0,) * 7)
            self.assertEqual(tuple(row["call_type"] for row in rows),
                             ("origin",) + ("passenger_stop",) * 5 + ("destination",))

    def test_only_verified_dimensions_are_promoted(self):
        for trip in self.trips:
            status = {
                row["dimension"]: row["status"]
                for row in self.completeness if row["entity_id"] == trip["trip_id"]
            }
            for dimension in ("identity", "train_number", "validity_calendar", "origin_destination", "stops", "times", "station_refs"):
                self.assertEqual(status[dimension], "verified")
            self.assertEqual(status["operator"], "unknown")
            self.assertEqual(status["route_lines"], "unknown")
            self.assertEqual(status["provenance"], "partial")
        self.assertEqual(len(self.queue), 6)
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
