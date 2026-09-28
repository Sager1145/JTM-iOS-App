"""Source-pinned checks for the JR Kyushu 2026 summer Ibusuki batch."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


SERVICE_ID = "ibusuki-no-tamatebako"
CALENDAR_SOURCE_ID = "jr-kyushu-summer-ds-plan-current-20260515"
TIMETABLE_SOURCE_ID = "jr-kyushu-ibusuki-no-tamatebako-timetable-20260314"


class KyushuNextBatchSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(timetable.DEFAULT_CANONICAL)
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

    def test_explicit_summer_range_is_capped_at_manifest_date(self):
        self.assertEqual(len(self.service_trips("2026-07-01")), 6)
        self.assertEqual(len(self.service_trips("2026-09-28")), 6)
        self.assertFalse(self.service_trips("2026-06-30"))
        self.assertFalse(self.service_trips("2026-09-29"))
        exceptions = [
            row
            for row in self.data["calendar_exceptions"]
            if row["source_id"] == CALENDAR_SOURCE_ID
        ]
        self.assertEqual(len(exceptions), 90)
        self.assertEqual(
            (exceptions[0]["service_date"], exceptions[-1]["service_date"]),
            ("2026-07-01", "2026-09-28"),
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


if __name__ == "__main__":
    unittest.main()
