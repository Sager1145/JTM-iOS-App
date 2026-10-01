"""Source-pinned checks for the four exact-date Shiokaze Obon timetables."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-shikoku-shiokaze-obon-2026-full-timetables.json"
DATES = ["2026-08-08", "2026-08-09", "2026-08-15", "2026-08-16"]
PAGE_IDS = {
    "5": "292", "6": "49632", "7": "362", "8": "422", "9": "125432",
    "10": "125452", "11": "3452", "12": "602", "13": "7632", "14": "642",
    "15": "692", "16": "722", "17": "762", "18": "17822", "19": "822",
    "20": "902", "21": "125442", "22": "125462", "23": "23072", "24": "982",
    "25": "25382", "26": "1032", "27": "27302", "28": "27932",
}


def jsonl(path):
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


class ShiokazeSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.sources = {
            row["source_id"]: row
            for row in jsonl(BASE / "sources/source-registry-shiokaze.jsonl")
        }
        cls.trips = jsonl(BASE / "normalized/trips/reviewed-shiokaze/seeds.jsonl")
        cls.stop_times = jsonl(BASE / "normalized/stop-times/reviewed-shiokaze/seeds.jsonl")
        cls.station_names = {
            row["station_id"]: row["name_snapshot"]
            for path in (BASE / "normalized").glob("station-identities*.jsonl")
            for row in jsonl(path)
        }
        cls.completeness = jsonl(BASE / "normalized/fact-completeness-shiokaze.jsonl")
        cls.facts = jsonl(BASE / "normalized/fact-sources-shiokaze.jsonl")
        cls.research = jsonl(BASE / "normalized/research-queue-shiokaze.jsonl")
        cls.exceptions = jsonl(
            BASE / "normalized/calendar-exceptions/reviewed-shiokaze/seeds.jsonl"
        )

    def test_all_96_exact_dated_official_pages_are_pinned(self):
        self.assertEqual(set(self.candidate["trips"]), set(PAGE_IDS))
        self.assertEqual(self.candidate["evidence_interpretation"]["special_dates"], DATES)
        official_sources = [
            row for source_id, row in self.sources.items()
            if source_id.startswith("jr-odekake-shiokaze-")
        ]
        self.assertEqual(len(official_sources), 96)
        for number, page_id in PAGE_IDS.items():
            trip = self.candidate["trips"][number]
            self.assertEqual(trip["page_id"], page_id)
            self.assertEqual(trip["train_number"], number + "M")
            for day in DATES:
                yyyymmdd = day.replace("-", "")
                source_id = f"jr-odekake-shiokaze-{number}m-{yyyymmdd}-special"
                source = self.sources[source_id]
                self.assertEqual(
                    source["url_or_locator"],
                    f"https://timetable.jr-odekake.net/train-timetable/{page_id}?date={yyyymmdd}",
                )
                self.assertEqual(source["effective_date"], day)
                self.assertEqual(source["source_type"], "official_train_timetable")
                self.assertEqual(
                    source["license_status"],
                    "explicit_reproduction_and_processing_prohibition",
                )
                self.assertEqual(source["redistribution_status"], "verification_only")
                self.assertIs(source["automated_extraction_allowed"], False)

    def test_normalized_rows_keep_complete_passenger_calls_and_omit_pass_marks(self):
        self.assertEqual(len(self.trips), 24)
        self.assertEqual(len(self.stop_times), 335)
        by_number = {row["public_number"]: row for row in self.trips}
        stops_by_trip = {}
        for row in self.stop_times:
            stops_by_trip.setdefault(row["trip_id"], []).append(row)
            self.assertNotEqual(row["call_type"], "pass")
        for number, reviewed in self.candidate["trips"].items():
            trip = by_number[number]
            self.assertEqual(trip["train_number"], number + "M")
            stops = sorted(stops_by_trip[trip["trip_id"]], key=lambda row: row["stop_sequence"])
            self.assertEqual(len(stops), len(reviewed["passenger_calls"]))
            actual = [[
                self.station_names[row["station_id"]],
                row.get("arrival_time") or "", row.get("departure_time") or "",
                row.get("platform") or "",
            ] for row in stops]
            self.assertEqual(actual, reviewed["passenger_calls"])
            self.assertEqual(len(stops) + reviewed["omitted_pass_row_count"], 59)

    def test_row_specific_call_patterns_are_preserved(self):
        calls = {
            number: [row[0] for row in trip["passenger_calls"]]
            for number, trip in self.candidate["trips"].items()
        }
        self.assertIn("伊予北条", calls["13"])
        self.assertNotIn("伊予北条", calls["14"])
        self.assertIn("詫間", calls["23"])
        self.assertIn("高瀬", calls["23"])
        self.assertNotIn("詫間", calls["21"])
        self.assertNotIn("高瀬", calls["21"])

    def test_resolved_dimensions_leave_only_actual_research_gaps(self):
        statuses = {
            (row["entity_id"], row["dimension"]): row["status"]
            for row in self.completeness
        }
        expected_research = {"operator", "route_lines", "provenance"}
        research_by_trip = {}
        for row in self.research:
            research_by_trip.setdefault(row["entity_id"], set()).add(row["missing_dimension"])
        for trip in self.trips:
            trip_id = trip["trip_id"]
            for dimension in ["identity", "train_number", "validity_calendar",
                              "origin_destination", "stops", "times", "station_refs"]:
                self.assertEqual(statuses[(trip_id, dimension)], "verified")
            self.assertEqual(statuses[(trip_id, "operator")], "unknown")
            self.assertEqual(statuses[(trip_id, "route_lines")], "unknown")
            self.assertEqual(statuses[(trip_id, "provenance")], "partial")
            self.assertEqual(research_by_trip[trip_id], expected_research)

            number_sources = {
                row["source_id"] for row in self.facts
                if row["entity_id"] == trip_id and row["field_name"] == "train_number"
            }
            self.assertEqual(len(number_sources), 4)
            self.assertTrue(all(source_id.endswith("-special") for source_id in number_sources))

    def test_calendar_remains_limited_to_the_four_announcement_dates(self):
        self.assertEqual(len(self.exceptions), 96)
        by_calendar = {}
        for row in self.exceptions:
            by_calendar.setdefault(row["calendar_id"], set()).add(row["service_date"])
            self.assertEqual(row["source_id"], "jr-shikoku-west-shiokaze-obon-20260624")
        self.assertEqual(len(by_calendar), 24)
        self.assertTrue(all(days == set(DATES) for days in by_calendar.values()))


if __name__ == "__main__":
    unittest.main()
