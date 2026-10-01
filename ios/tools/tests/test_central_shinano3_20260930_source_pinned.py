"""Exact-date source and calendar checks for Shinano 3 on 2026-09-30."""

import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-central-shinano3-20260930"
TRIP_ID = "jr-central.shinano.3.2026-09-30"
SOURCE_ID = "jr-east-shinano3-20260930"

sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()]


class CentralShinano3SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(
            (BASE / "candidates/jr-central-shinano3-20260930.json").read_text()
        )
        manifest = timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.data, origins = timetable.load_dataset(
            timetable.DEFAULT_CANONICAL, manifest
        )
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.station_names = {
            row["station_id"]: row["name_snapshot"]
            for row in cls.data["station_identities"]
        }

    def test_selected_variant_source_and_official_english_name_are_pinned(self):
        trip = self.candidate["trip"]
        self.assertEqual(trip["service_date"], "2026-09-30")
        self.assertEqual(
            trip["source"]["url_or_locator"],
            "https://timetables.jreast.co.jp/2610/train/000/000081.html",
        )
        self.assertIs(trip["source"]["automated_extraction_allowed"], False)
        self.assertEqual(
            self.candidate["official_english_name"],
            {
                "name": "Shinano",
                "source_id": "jr-central-conventional-limited-express-2026-en",
                "url_or_locator": "https://global.jr-central.co.jp/en/nozomi/pdf/zairai_English.pdf",
            },
        )
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        self.assertEqual(sources[SOURCE_ID], rows(
            BASE / f"sources/source-registry-{SUFFIX}.jsonl"
        )[0])
        english_names = [
            row for row in self.data["service_name_periods"]
            if row["service_id"] == "shinano" and row["language"] == "en"
            and row["valid_from"] <= "2026-09-30" < row["valid_until"]
        ]
        self.assertEqual(
            [(row["name"], row["source_id"]) for row in english_names],
            [("Shinano", "jr-central-conventional-limited-express-2026-en")],
        )

    def test_only_september_30_materializes_with_ten_published_calls(self):
        self.assertFalse([
            row for row in timetable.materialize(self.data, "2026-09-29")
            if row["trip_id"] == TRIP_ID
        ])
        trips = [
            row for row in timetable.materialize(self.data, "2026-09-30")
            if row["trip_id"] == TRIP_ID
        ]
        self.assertEqual(len(trips), 1)
        trip = trips[0]
        self.assertEqual((trip["service_id"], trip["public_number"],
                          trip["train_number"]), ("shinano", "3", "1003M"))
        self.assertEqual(
            [self.station_names[stop["station_id"]] for stop in trip["stop_times"]],
            ["名古屋", "千種", "多治見", "恵那", "中津川", "木曽福島",
             "塩尻", "松本", "篠ノ井", "長野"],
        )
        self.assertNotIn("上松", [
            self.station_names[stop["station_id"]] for stop in trip["stop_times"]
        ])
        self.assertEqual(
            [(stop["arrival_time"], stop["departure_time"]) for stop in trip["stop_times"]],
            [
                (None, "08:00"), ("08:06", "08:06"), ("08:22", "08:23"),
                ("08:42", "08:42"), ("08:50", "08:51"), ("09:25", "09:26"),
                ("09:54", "09:56"), ("10:05", "10:06"), ("10:51", "10:52"),
                ("11:02", None),
            ],
        )

    def test_calendar_and_evidence_boundaries_remain_explicit(self):
        calendar = rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        exceptions = rows(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl"
        )
        self.assertEqual(len(calendar), 1)
        self.assertTrue(all(calendar[0][weekday] == 0 for weekday in (
            "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday",
        )))
        self.assertEqual(
            [(row["service_date"], row["exception_type"], row["source_id"])
             for row in exceptions],
            [("2026-09-30", "add", SOURCE_ID)],
        )
        completeness = {
            row["dimension"]: (row["status"], row["confidence"])
            for row in rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
            if row["entity_id"] == TRIP_ID
        }
        for dimension in (
            "identity", "train_number", "validity_calendar", "origin_destination",
            "stops", "times", "station_refs",
        ):
            self.assertEqual(completeness[dimension], ("verified", "high"))
        self.assertEqual(completeness["operator"], ("unknown", "low"))
        self.assertEqual(completeness["route_lines"], ("unknown", "low"))
        self.assertEqual(completeness["provenance"], ("partial", "medium"))


if __name__ == "__main__":
    unittest.main()
