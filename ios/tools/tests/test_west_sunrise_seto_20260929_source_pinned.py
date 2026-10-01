"""Source-pinned checks for the 2026-09-29 Sunrise Seto overnight trip."""

import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parents[1]
sys.path.insert(0, str(TOOLS))

import train_timetable as timetable


BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-west-sunrise-seto-20260929.json"
SUFFIX = "west-sunrise-seto-20260929"
TRIP_ID = "jr-west.sunrise-seto.5031m.2026-09-29"


def jsonl(path):
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


class WestSunriseSeto20260929SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.sources = jsonl(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        cls.services = jsonl(BASE / f"normalized/services-{SUFFIX}.jsonl")
        cls.versions = jsonl(BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl")
        cls.trips = jsonl(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        cls.stops = jsonl(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        cls.calendars = jsonl(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        cls.exceptions = jsonl(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        cls.facts = jsonl(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        cls.completeness = jsonl(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")

    def test_candidate_pins_official_dated_page_and_reuse_restriction(self):
        self.assertEqual(self.candidate["selected_service_date"], "2026-09-29")
        self.assertEqual(self.candidate["actual_operation_status"], "unverified_plan")
        source = self.sources[0]
        self.assertEqual(
            source["url_or_locator"],
            "https://timetable.jr-odekake.net/train-timetable/38492?date=20260929",
        )
        self.assertEqual(
            source["content_hash"],
            "sha256:8c47b02e1a5fda8e8f5a6080037869a1c95896b2a32d328b7d9bdbf3ab8afa1c",
        )
        self.assertEqual(source["redistribution_status"], "verification_only")
        self.assertIs(source["automated_extraction_allowed"], False)

    def test_5031m_passenger_calls_match_the_reviewed_column(self):
        self.assertEqual(self.services[0]["service_id"], "sunrise-seto")
        self.assertEqual(len(self.trips), 1)
        trip = self.trips[0]
        self.assertEqual(trip["trip_id"], TRIP_ID)
        self.assertEqual(trip["train_number"], "5031M")
        self.assertIsNone(trip["public_number"])
        observed = [
            (row["station_id"], row["arrival_time"], row["departure_time"],
             row["day_offset"], row["platform"])
            for row in self.stops
        ]
        self.assertEqual(observed, [
            ("jp.n02.003766", None, "21:26", 0, "9"),
            ("jp.n02.004633", "21:51", "21:52", 0, "6"),
            ("jp.n02.005685", "22:55", "22:57", 0, "2"),
            ("jp.n02.005689", "23:15", "23:16", 0, None),
            ("jp.n02.005522", "23:31", "23:32", 0, None),
            ("jp.n02.006128", "23:57", "23:59", 0, "4"),
            ("jp.n02.007059", "00:53", "00:54", 1, "4"),
            ("jp.n02.006509", "05:25", "05:26", 1, "8"),
            ("jp.n02.007310", "06:27", "06:31", 1, "8"),
            ("jp.n02.007919", "06:52", "06:53", 1, None),
            ("jp.n02.008240", "07:09", "07:10", 1, None),
            ("jp.n02.008163", "07:27", None, 1, "6"),
        ])

    def test_service_date_materialization_preserves_next_day_offsets(self):
        data = {
            "timetable_versions": self.versions,
            "calendars": self.calendars,
            "calendar_exceptions": self.exceptions,
            "holiday_dates": [],
            "holiday_calendar_years": [],
            "trips": self.trips,
            "stop_times": self.stops,
            "trip_stop_time_overrides": [],
        }
        occurrences = timetable.materialize(data, "2026-09-29")
        self.assertEqual(len(occurrences), 1)
        occurrence = occurrences[0]
        self.assertEqual(occurrence["service_date"], "2026-09-29")
        hamamatsu = occurrence["stop_times"][6]
        takamatsu = occurrence["stop_times"][-1]
        self.assertEqual(hamamatsu["day_offset"], 1)
        self.assertEqual(hamamatsu["arrival_seconds"], 24 * 3600 + 53 * 60)
        self.assertEqual(takamatsu["day_offset"], 1)
        self.assertEqual(takamatsu["arrival_seconds"], 31 * 3600 + 27 * 60)
        self.assertEqual(timetable.materialize(data, "2026-09-30"), [])

    def test_calendar_is_one_exact_service_date(self):
        self.assertEqual(len(self.calendars), 1)
        calendar = self.calendars[0]
        self.assertEqual((calendar["valid_from"], calendar["valid_until"]),
                         ("2026-09-29", "2026-09-30"))
        for weekday in (
            "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday",
        ):
            self.assertEqual(calendar[weekday], 0)
        self.assertEqual(self.exceptions, [{
            "calendar_id": TRIP_ID + ".calendar",
            "exception_type": "add",
            "reason": "2026-09-29 is marked drivingday-01 on official page 38492",
            "service_date": "2026-09-29",
            "source_id": "jr-west-sunrise-seto-20260929",
        }])

    def test_completeness_uses_only_supported_dimensions_and_keeps_gaps(self):
        statuses = {row["dimension"]: row["status"] for row in self.completeness}
        self.assertEqual(set(statuses), {
            "identity", "train_number", "operator", "validity_calendar",
            "origin_destination", "stops", "times", "route_lines",
            "station_refs", "provenance",
        })
        self.assertEqual(statuses["times"], "verified")
        self.assertEqual(statuses["operator"], "unknown")
        self.assertEqual(statuses["route_lines"], "unknown")
        self.assertFalse(any(row["field_name"] == "operator" for row in self.facts))
        self.assertFalse(any(row["field_name"] == "route_lines" for row in self.facts))


if __name__ == "__main__":
    unittest.main()
