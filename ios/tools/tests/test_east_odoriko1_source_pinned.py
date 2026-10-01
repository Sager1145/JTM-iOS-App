"""Source-pinned checks for the two Odoriko 1 branches on 2026-09-29/30."""
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
TOOLS = ROOT / "ios/tools"
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


SUFFIX = "east-odoriko1-20260929-30"
SOURCE_ID = "jr-east-odoriko1-20260929-30"
TRIP_IDS = {
    "3021M": "jr-east.odoriko.1.3021m-izukyu-shimoda.2026-09-29",
    "4021M": "jr-east.odoriko.1.4021m-shuzenji.2026-09-29",
}


def load_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


class EastOdoriko1SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(
            (BASE / "candidates/jr-east-odoriko1-20260929-30.json").read_text()
        )
        cls.sources = load_jsonl(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        cls.trips = load_jsonl(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        cls.stops = load_jsonl(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        cls.calendars = load_jsonl(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        cls.exceptions = load_jsonl(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl"
        )
        cls.relations = load_jsonl(
            BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl"
        )
        cls.completeness = load_jsonl(
            BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl"
        )

        manifest = timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.data, origins = timetable.load_dataset(timetable.DEFAULT_CANONICAL, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.station_names = {
            row["station_id"]: row["name_snapshot"]
            for row in cls.data["station_identities"]
        }

    def test_official_source_hash_dates_and_branch_numbers_are_pinned(self):
        source = self.candidate["source"]
        self.assertEqual(source["source_id"], SOURCE_ID)
        self.assertEqual(
            source["url_or_locator"],
            "https://timetables.jreast.co.jp/2610/train/095/098901.html",
        )
        self.assertEqual(
            source["content_hash"],
            "sha256:35f39d356ca9f8e1cb1493a86b95235387c2f05128fa83c59658895493027c66",
        )
        self.assertIs(source["automated_extraction_allowed"], False)
        self.assertEqual(source["license_status"], "unknown")
        self.assertEqual(source["redistribution_status"], "unknown")
        self.assertEqual(self.sources, [source])

        by_number = {trip["train_number"]: trip for trip in self.candidate["trips"]}
        self.assertEqual(set(by_number), {"3021M", "4021M"})
        for trip in by_number.values():
            self.assertEqual(trip["operating_dates"], ["2026-09-29", "2026-09-30"])

    def test_3021m_printed_column_is_complete(self):
        stops = sorted(
            (row for row in self.stops if row["trip_id"] == TRIP_IDS["3021M"]),
            key=lambda row: row["stop_sequence"],
        )
        self.assertEqual(
            [self.station_names[row["station_id"]] for row in stops],
            [
                "東京", "品川", "川崎", "横浜", "大船", "小田原", "湯河原", "熱海",
                "伊東", "伊豆高原", "伊豆熱川", "伊豆稲取", "河津", "伊豆急下田",
            ],
        )
        self.assertEqual(
            [(row["arrival_time"], row["departure_time"]) for row in stops],
            [
                (None, "09:00"), ("09:07", "09:08"), ("09:16", "09:16"),
                ("09:24", "09:24"), ("09:37", "09:37"), ("10:01", "10:01"),
                ("10:13", "10:14"), ("10:20", "10:23"), ("10:43", "10:45"),
                ("11:02", "11:02"), ("11:11", "11:13"), ("11:19", "11:22"),
                ("11:27", "11:28"), ("11:39", None),
            ],
        )
        self.assertTrue(all(row["time_accuracy"] == "minute" for row in stops))

    def test_4021m_shared_segment_does_not_copy_3021m_times(self):
        stops = sorted(
            (row for row in self.stops if row["trip_id"] == TRIP_IDS["4021M"]),
            key=lambda row: row["stop_sequence"],
        )
        self.assertEqual(
            [self.station_names[row["station_id"]] for row in stops],
            [
                "東京", "品川", "川崎", "横浜", "大船", "小田原", "湯河原", "熱海",
                "三島", "三島田町", "大場", "伊豆長岡", "大仁", "修善寺",
            ],
        )
        for stop in stops[:7]:
            self.assertIsNone(stop["arrival_time"])
            self.assertIsNone(stop["departure_time"])
            self.assertIsNone(stop["platform"])
            self.assertEqual(stop["time_accuracy"], "unknown")
        self.assertEqual(
            (stops[7]["arrival_time"], stops[7]["departure_time"], stops[7]["platform"]),
            (None, "10:25", "２"),
        )
        self.assertEqual(
            [(row["arrival_time"], row["departure_time"]) for row in stops[8:]],
            [
                ("10:38", "10:40"), ("10:43", "10:44"),
                ("10:48", "10:48"), ("10:55", "10:56"),
                ("11:02", "11:03"), ("11:08", None),
            ],
        )

    def test_exact_date_materialization_and_coupling_relation(self):
        def branches(day):
            return sorted(
                (trip for trip in timetable.materialize(self.data, day)
                 if trip["trip_id"] in set(TRIP_IDS.values())),
                key=lambda trip: trip["train_number"],
            )

        self.assertFalse(branches("2026-09-28"))
        self.assertEqual([trip["train_number"] for trip in branches("2026-09-29")], ["3021M", "4021M"])
        self.assertEqual([trip["train_number"] for trip in branches("2026-09-30")], ["3021M", "4021M"])
        self.assertFalse(branches("2026-10-01"))
        self.assertEqual(len(self.calendars), 2)
        self.assertTrue(all(not any(calendar[weekday] for weekday in [
            "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday",
        ]) for calendar in self.calendars))
        self.assertEqual(len(self.exceptions), 4)

        self.assertEqual(
            {(row["trip_id"], row["related_trip_id"], row["relation_type"], row["from_sequence"], row["to_sequence"])
             for row in self.relations},
            {
                (TRIP_IDS["3021M"], TRIP_IDS["4021M"], "couples_with", 1, 8),
                (TRIP_IDS["4021M"], TRIP_IDS["3021M"], "couples_with", 1, 8),
            },
        )

    def test_completeness_distinguishes_the_two_time_columns(self):
        statuses = {
            (row["entity_id"], row["dimension"]): row["status"]
            for row in self.completeness
        }
        self.assertEqual(statuses[(TRIP_IDS["3021M"], "times")], "verified")
        self.assertEqual(statuses[(TRIP_IDS["4021M"], "times")], "partial")
        for trip_id in TRIP_IDS.values():
            self.assertEqual(statuses[(trip_id, "stops")], "verified")
            self.assertEqual(statuses[(trip_id, "validity_calendar")], "verified")
            self.assertEqual(statuses[(trip_id, "operator")], "unknown")
            self.assertEqual(statuses[(trip_id, "route_lines")], "unknown")


if __name__ == "__main__":
    unittest.main()
