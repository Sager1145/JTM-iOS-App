"""Source-pinned regression checks for the independent JR East next batch."""
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "east-next-batch"


def load_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


class EastNextBatchSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(
            (BASE / "candidates/jr-east-202609-east-next-batch.json").read_text()
        )
        cls.sources = load_jsonl(
            BASE / f"sources/source-registry-{SUFFIX}.jsonl"
        )
        cls.trips = load_jsonl(
            BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl"
        )
        cls.stops = load_jsonl(
            BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"
        )
        cls.calendars = load_jsonl(
            BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl"
        )
        cls.exceptions = load_jsonl(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl"
        )
        cls.completeness = load_jsonl(
            BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl"
        )

    def test_official_urls_hashes_and_td_ok_dates_are_pinned(self):
        expected = {
            "jr-east-azusa1-202609-east-next": (
                "https://timetables.jreast.co.jp/2610/train/005/008042.html",
                "sha256:e715b0b17a9c8c75ef04857689e9d0084ddf0d58813046519a35bc854a375e8c",
                ["2026-09-19", "2026-09-20", "2026-09-21", "2026-09-26"],
                12,
            ),
            "jr-east-azusa1-base-202609-east-next": (
                "https://timetables.jreast.co.jp/2610/train/005/008041.html",
                "sha256:b86839567b5c38369bd19bc9e72f1e5f6b2bc323863cc488a7de414432e8cb64",
                [
                    "2026-09-18", "2026-09-22", "2026-09-23", "2026-09-24",
                    "2026-09-25", "2026-09-27", "2026-09-28",
                ],
                12,
            ),
            "jr-east-tokiwa55-202609-east-next": (
                "https://timetables.jreast.co.jp/2610/train/075/076301.html",
                "sha256:aaaa428210b824f16f5fa4a7a786245b19c3fabc1579148da2431b0a181bf380",
                [
                    "2026-09-19", "2026-09-20", "2026-09-21", "2026-09-22",
                    "2026-09-23", "2026-09-26", "2026-09-27",
                ],
                9,
            ),
        }
        candidate_by_source = {
            trip["source"]["source_id"]: trip for trip in self.candidate["trips"]
        }
        registry_by_source = {row["source_id"]: row for row in self.sources}
        self.assertEqual(set(candidate_by_source), set(expected))
        self.assertEqual(set(registry_by_source), set(expected))
        for source_id, (url, content_hash, dates, stop_count) in expected.items():
            trip = candidate_by_source[source_id]
            self.assertEqual(trip["source"]["url_or_locator"], url)
            self.assertEqual(trip["source"]["content_hash"], content_hash)
            self.assertEqual(trip["operating_dates"], dates)
            self.assertEqual(len(trip["stop_times"]), stop_count)
            self.assertEqual(registry_by_source[source_id]["url_or_locator"], url)
            self.assertEqual(registry_by_source[source_id]["content_hash"], content_hash)

    def test_azusa_variants_partition_every_date_through_cutoff(self):
        azusa_calendars = {
            trip["calendar_id"]
            for trip in self.trips
            if trip["service_id"] == "azusa" and trip["public_number"] == "1"
        }
        dates = sorted(
            row["service_date"]
            for row in self.exceptions
            if row["calendar_id"] in azusa_calendars
        )
        self.assertEqual(dates, [f"2026-09-{day:02}" for day in range(18, 29)])
        self.assertEqual(len(dates), len(set(dates)))
        for calendar in self.calendars:
            self.assertFalse(any(calendar[weekday] for weekday in [
                "monday", "tuesday", "wednesday", "thursday",
                "friday", "saturday", "sunday",
            ]))

    def test_variant_clocks_and_complete_stop_facts_are_preserved(self):
        station_rows = {}
        for path in (BASE / "normalized").glob("station-identities*.jsonl"):
            for row in load_jsonl(path):
                station_rows[row["station_id"]] = row["name_snapshot"]

        def trip_stops(fragment):
            trip = next(row for row in self.trips if fragment in row["trip_id"])
            return trip, sorted(
                (row for row in self.stops if row["trip_id"] == trip["trip_id"]),
                key=lambda row: row["stop_sequence"],
            )

        selected_trip, selected = trip_stops("selected-saturday-holiday")
        base_trip, base = trip_stops(".base.")
        tokiwa_trip, tokiwa = trip_stops("jr-east.tokiwa.55.main")
        self.assertEqual(
            [station_rows[row["station_id"]] for row in selected],
            ["新宿", "立川", "八王子", "大月", "甲府", "韮崎", "小淵沢", "茅野", "上諏訪", "岡谷", "塩尻", "松本"],
        )
        self.assertEqual(selected[-1]["arrival_time"], "09:43")
        self.assertEqual(base[-1]["arrival_time"], "09:38")
        self.assertEqual(tokiwa_trip["train_number"], "55M")
        self.assertEqual((tokiwa[0]["departure_time"], tokiwa[-1]["arrival_time"]), ("09:15", "10:53"))

        status = {
            (row["entity_id"], row["dimension"]): row["status"]
            for row in self.completeness
        }
        for trip in [selected_trip, base_trip, tokiwa_trip]:
            self.assertEqual(status[(trip["trip_id"], "stops")], "verified")
            self.assertEqual(status[(trip["trip_id"], "times")], "verified")
            self.assertEqual(status[(trip["trip_id"], "validity_calendar")], "verified")
            self.assertEqual(status[(trip["trip_id"], "operator")], "unknown")


if __name__ == "__main__":
    unittest.main()
