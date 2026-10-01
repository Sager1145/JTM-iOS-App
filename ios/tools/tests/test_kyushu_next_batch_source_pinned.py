"""Source-pinned checks for the JR Kyushu 2026 summer Ibusuki batch."""

from datetime import date
import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


SERVICE_ID = "ibusuki-no-tamatebako"
CALENDAR_SOURCE_ID = "jr-kyushu-summer-ds-plan-current-20260515"
TIMETABLE_SOURCE_ID = "jr-kyushu-ibusuki-no-tamatebako-timetable-20260314"
ROUTE_SOURCE_ID = "jr-kyushu-ds-line-list-20260314"
OPERATOR_SOURCE_ID = "jr-kyushu-ibusuki-line-operator-20250315"


class KyushuNextBatchSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.as_of = date.fromisoformat(manifest["as_of_date"])
        cls.data, origins = timetable.load_dataset(timetable.DEFAULT_CANONICAL, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.station_names = {
            row["station_id"]: row["name_snapshot"]
            for row in cls.data["station_identities"]
        }

    def service_trips(self, day):
        return [
            trip
            for trip in timetable.materialize(self.data, day)
            if trip["service_id"] == SERVICE_ID
        ]

    def test_official_sources_are_pinned(self):
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        calendar_source = sources[CALENDAR_SOURCE_ID]
        self.assertEqual(
            calendar_source["url_or_locator"],
            "https://www.jrkyushu.co.jp/news/__icsFiles/afieldfile/2026/07/13/"
            "20260515_Special_Train_Operation_Plan_and_DS_Train_Operating_Dates.pdf",
        )
        self.assertEqual(
            calendar_source["content_hash"],
            "3309ec0977ecb9f75a483a626d3cfc71a66ea5bf3db8e5bd809ef9113576b166",
        )
        self.assertEqual(
            sources[TIMETABLE_SOURCE_ID]["url_or_locator"],
            "https://www.jrkyushu.co.jp/trains/ibusukinotamatebako/",
        )
        self.assertEqual(sources[ROUTE_SOURCE_ID]["url_or_locator"], "https://www.jrkyushu.co.jp/trains/")
        self.assertEqual(sources[OPERATOR_SOURCE_ID]["url_or_locator"],
                         "https://www.jrkyushu.co.jp/company/info/data/line_km.html")

    def test_explicit_summer_range_is_capped_at_manifest_date(self):
        candidate = json.loads(
            (timetable.DEFAULT_CANONICAL / "candidates/jr-kyushu-ibusuki-no-tamatebako-2026-summer-kyushu-next-batch.json")
            .read_text(encoding="utf-8")
        )
        self.assertEqual(candidate["operating_date_range"]["until_inclusive"], "2026-09-30")
        self.assertEqual(len(self.service_trips("2026-07-01")), 6)
        self.assertEqual(len(self.service_trips("2026-09-28")), 6)
        self.assertEqual(len(self.service_trips("2026-09-29")), 6)
        self.assertFalse(self.service_trips("2026-06-30"))
        self.assertEqual(
            len(self.service_trips("2026-09-30")),
            6 if self.as_of >= date(2026, 9, 30) else 0,
        )
        exceptions = [
            row
            for row in self.data["calendar_exceptions"]
            if row["source_id"] == CALENDAR_SOURCE_ID
        ]
        expected_last = min(self.as_of, date(2026, 9, 30))
        self.assertEqual(len(exceptions), (expected_last - date(2026, 7, 1)).days + 1)
        self.assertEqual(
            (exceptions[0]["service_date"], exceptions[-1]["service_date"]),
            ("2026-07-01", expected_last.isoformat()),
        )

    def test_all_six_official_endpoint_clocks(self):
        expected = {
            "1": ("鹿児島中央", "9:56", "指宿", "10:47"),
            "3": ("鹿児島中央", "11:56", "指宿", "12:48"),
            "5": ("鹿児島中央", "13:56", "指宿", "14:49"),
            "2": ("指宿", "10:56", "鹿児島中央", "11:48"),
            "4": ("指宿", "12:57", "鹿児島中央", "13:48"),
            "6": ("指宿", "15:07", "鹿児島中央", "16:00"),
        }
        trips = {trip["public_number"]: trip for trip in self.service_trips("2026-07-01")}
        self.assertEqual(set(trips), set(expected))
        for public_number, (origin, departure, destination, arrival) in expected.items():
            trip = trips[public_number]
            self.assertEqual(
                [self.station_names[stop["station_id"]] for stop in trip["stop_times"]],
                [origin, destination],
            )
            self.assertEqual(trip["stop_times"][0]["departure_time"], departure)
            self.assertEqual(trip["stop_times"][1]["arrival_time"], arrival)
            self.assertIsNone(trip["train_number"])

    def test_each_endpoint_pair_has_a_current_line_identity_with_partial_historical_validity(self):
        trip_ids = {
            row["trip_id"] for row in self.data["trips"]
            if row["service_id"] == SERVICE_ID
        }
        segments = [
            row for row in self.data["trip_line_segments"]
            if row["trip_id"] in trip_ids
        ]
        operators = [
            row for row in self.data["trip_operator_segments"]
            if row["trip_id"] in trip_ids
        ]
        self.assertEqual(len(trip_ids), 6)
        self.assertEqual(len(segments), 6)
        self.assertEqual(len(operators), 6)
        for row in segments:
            self.assertEqual(row["sequence"], 1)
            self.assertEqual(row["line_name"], "指宿枕崎線")
            self.assertEqual(row["operator_id"], "jr-kyushu")
            self.assertEqual(row["source_id"], ROUTE_SOURCE_ID)
            self.assertEqual(row["confidence"], "medium")
            self.assertEqual(row["reference_kind"], "current_n02")
            self.assertEqual(row["current_n02_line_id"], "jp-九州旅客鉄道-指宿枕崎線")
            self.assertEqual(
                (self.station_names[row["from_station_id"]],
                 self.station_names[row["to_station_id"]]),
                ("鹿児島中央", "指宿") if row["trip_id"].split(".")[2] in {"1", "3", "5"}
                else ("指宿", "鹿児島中央"),
            )
            self.assertNotIn("rail_history_id", row)
        for row in operators:
            self.assertEqual((row["from_sequence"], row["to_sequence"], row["operator_id"]),
                             (1, 2, "jr-kyushu"))
        statuses = {
            (row["entity_id"], row["dimension"]): row["status"]
            for row in self.data["fact_completeness"] if row["entity_id"] in trip_ids
        }
        for trip_id in trip_ids:
            self.assertEqual(statuses[(trip_id, "operator")], "verified")
            self.assertEqual(statuses[(trip_id, "route_lines")], "partial")
        operator_sources = {
            row["entity_id"]: row["source_id"]
            for row in self.data["fact_sources"]
            if row["entity_id"] in trip_ids and row["field_name"] == "operator"
        }
        self.assertEqual(set(operator_sources.values()), {OPERATOR_SOURCE_ID})
        self.assertFalse(any(
            row["entity_id"] in trip_ids and row["missing_dimension"] == "operator"
            for row in self.data["research_queue"]
        ))


if __name__ == "__main__":
    unittest.main()
