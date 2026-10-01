"""Source-pinned checks for the independent Wakashio 17 dated batch."""
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "east-wakashio17-20260929-30"
SOURCE_ID = "jr-east-wakashio17-20260929-30"
TRIP_ID = "jr-east.wakashio.17.weekday-requested-dates.2026-09-29"


def load_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


class EastWakashio17SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(
            (BASE / "candidates/jr-east-wakashio17-20260929-30.json").read_text()
        )
        cls.sources = load_jsonl(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        cls.services = load_jsonl(BASE / f"normalized/services-{SUFFIX}.jsonl")
        cls.stations = load_jsonl(BASE / f"normalized/station-identities-{SUFFIX}.jsonl")
        cls.trips = load_jsonl(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        cls.stops = load_jsonl(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        cls.calendars = load_jsonl(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        cls.exceptions = load_jsonl(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl"
        )
        cls.completeness = load_jsonl(
            BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl"
        )

    def test_official_page_hash_reuse_flags_and_exact_dates_are_pinned(self):
        reviewed = self.candidate["trips"]
        self.assertEqual(len(reviewed), 1)
        trip = reviewed[0]
        source = trip["source"]
        self.assertEqual(source["source_id"], SOURCE_ID)
        self.assertEqual(
            source["url_or_locator"],
            "https://timetables.jreast.co.jp/2610/train/095/098781.html",
        )
        self.assertEqual(
            source["content_hash"],
            "sha256:15ff3b2fde28534cf240474658742b9cad30d29313510ffe17eff91d1640414a",
        )
        self.assertIs(source["automated_extraction_allowed"], False)
        self.assertEqual(source["license_status"], "unknown")
        self.assertEqual(source["redistribution_status"], "unknown")
        self.assertEqual(trip["operating_dates"], ["2026-09-29", "2026-09-30"])
        self.assertEqual(self.sources, [source])

    def test_complete_train_identity_and_clocks_are_preserved(self):
        self.assertEqual(len(self.trips), 1)
        trip = self.trips[0]
        self.assertEqual(trip["trip_id"], TRIP_ID)
        self.assertEqual(trip["service_id"], "wakashio")
        self.assertEqual(trip["public_number"], "17")
        self.assertEqual(trip["train_number"], "1067M")

        station_names = {
            row["station_id"]: row["name_snapshot"]
            for row in self.stations
        }
        stops = sorted(self.stops, key=lambda row: row["stop_sequence"])
        self.assertEqual(
            [station_names[row["station_id"]] for row in stops],
            ["東京", "蘇我", "土気", "大網", "茂原", "上総一ノ宮"],
        )
        self.assertEqual(
            [(row["arrival_time"], row["departure_time"], row["platform"]) for row in stops],
            [
                (None, "20:00", "京１"),
                ("20:36", "20:37", "５"),
                ("20:46", "20:47", None),
                ("20:51", "20:51", "２"),
                ("20:59", "21:00", "３"),
                ("21:08", None, "２"),
            ],
        )
        self.assertTrue(all(row["source_id"] == SOURCE_ID for row in stops))

    def test_calendar_is_exact_date_only_and_tokyo_is_keiyo_group(self):
        self.assertEqual(len(self.calendars), 1)
        calendar = self.calendars[0]
        self.assertFalse(any(calendar[weekday] for weekday in [
            "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday",
        ]))
        self.assertEqual(
            [row["service_date"] for row in self.exceptions],
            ["2026-09-29", "2026-09-30"],
        )
        self.assertTrue(all(row["exception_type"] == "add" for row in self.exceptions))
        tokyo = next(row for row in self.stations if row["name_snapshot"] == "東京")
        self.assertEqual(tokyo["station_id"], "jp.n02.003785")
        self.assertEqual(tokyo["current_source_code"], "003785")
        self.assertEqual(self.trips[0]["origin_station_id"], tokyo["station_id"])

    def test_verified_facts_and_intentional_gaps_are_explicit(self):
        statuses = {
            row["dimension"]: (row["status"], row["confidence"])
            for row in self.completeness
            if row["entity_id"] == TRIP_ID
        }
        for dimension in [
            "identity", "train_number", "validity_calendar", "origin_destination",
            "stops", "times", "station_refs",
        ]:
            self.assertEqual(statuses[dimension], ("verified", "high"))
        self.assertEqual(statuses["operator"], ("unknown", "low"))
        self.assertEqual(statuses["route_lines"], ("unknown", "low"))
        self.assertEqual(statuses["provenance"], ("partial", "medium"))


if __name__ == "__main__":
    unittest.main()
