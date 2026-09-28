"""Source-pinned checks for the JR Shikoku Ishizuchi next batch."""

from datetime import date, timedelta
import os
from pathlib import Path
import sys
import unittest


REPO_ROOT = Path(__file__).resolve().parents[3]
TOOLS = REPO_ROOT / "ios/tools"
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


CANONICAL = Path(
    os.environ.get("JTM_ISHIZUCHI_CANONICAL", str(REPO_ROOT / "app/data/train-service-history"))
).resolve()
SERVICE_ID = "ishizuchi"
SOURCE_ID = "jr-shikoku-summer-20260515-ishizuchi-silver-week-following"


class IshizuchiNextSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(CANONICAL)
        cls.data, origins = timetable.load_dataset(CANONICAL, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.station_names = {
            row["station_id"]: row["name_snapshot"]
            for row in cls.data["station_identities"]
        }

    def trips(self, day):
        return [
            trip for trip in timetable.materialize(self.data, day)
            if trip["service_id"] == SERVICE_ID
        ]

    def test_source_url_hash_and_shape_are_pinned(self):
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        source = sources[SOURCE_ID]
        self.assertEqual(
            source["url_or_locator"],
            "https://www.jr-shikoku.co.jp/03_news/press/assets/2026/07/15/20260515%20.pdf",
        )
        self.assertEqual(
            source["content_hash"],
            "sha256:64e69d7df9da8d58326653d9334a7b0683c1645b5b6ba2d42d32d0f714d3c2c6",
        )
        templates = [trip for trip in self.data["trips"] if trip["service_id"] == SERVICE_ID]
        self.assertEqual(len(templates), 26)
        self.assertEqual(
            len([row for row in self.data["stop_times"] if row["trip_id"] in {t["trip_id"] for t in templates}]),
            52,
        )
        self.assertEqual(
            len([row for row in self.data["calendar_exceptions"] if row["source_id"] == SOURCE_ID]),
            11,
        )

    def test_five_and_six_day_cells_materialize_154_occurrences(self):
        on_18 = {trip["public_number"] for trip in self.trips("2026-09-18")}
        on_19 = {trip["public_number"] for trip in self.trips("2026-09-19")}
        self.assertEqual(len(on_18), 24)
        self.assertNotIn("3", on_18)
        self.assertNotIn("4", on_18)
        self.assertEqual(on_19, {str(value) for value in range(3, 29)})
        self.assertEqual(len(self.trips("2026-09-23")), 26)
        self.assertFalse(self.trips("2026-09-17"))
        self.assertFalse(self.trips("2026-09-24"))
        current = date(2026, 9, 18)
        total = 0
        while current <= date(2026, 9, 24):
            total += len(self.trips(current.isoformat()))
            current += timedelta(days=1)
        self.assertEqual(total, 154)

    def test_all_26_endpoint_clocks_are_source_pinned(self):
        expected = {
            "3": ("高松", "08:45", "宇多津", "09:06"),
            "5": ("高松", "09:42", "多度津", "10:10"),
            "7": ("高松", "10:47", "多度津", "11:17"),
            "9": ("高松", "11:50", "多度津", "12:18"),
            "11": ("高松", "12:50", "多度津", "13:18"),
            "13": ("高松", "13:50", "多度津", "14:18"),
            "15": ("高松", "14:50", "多度津", "15:18"),
            "17": ("高松", "15:50", "多度津", "16:18"),
            "19": ("高松", "16:50", "多度津", "17:18"),
            "21": ("高松", "17:53", "多度津", "18:22"),
            "23": ("高松", "18:59", "多度津", "19:26"),
            "25": ("高松", "19:51", "多度津", "20:22"),
            "27": ("高松", "20:59", "多度津", "21:27"),
            "4": ("宇多津", "07:14", "高松", "07:36"),
            "6": ("宇多津", "08:26", "高松", "08:45"),
            "8": ("宇多津", "09:25", "高松", "09:47"),
            "10": ("宇多津", "10:19", "高松", "10:39"),
            "12": ("宇多津", "11:33", "高松", "11:54"),
            "14": ("宇多津", "12:33", "高松", "12:54"),
            "16": ("宇多津", "13:34", "高松", "13:55"),
            "18": ("宇多津", "14:34", "高松", "14:56"),
            "20": ("宇多津", "15:34", "高松", "15:56"),
            "22": ("宇多津", "16:34", "高松", "16:54"),
            "24": ("宇多津", "17:35", "高松", "17:57"),
            "26": ("宇多津", "18:36", "高松", "18:56"),
            "28": ("宇多津", "19:38", "高松", "19:58"),
        }
        trips = {trip["public_number"]: trip for trip in self.trips("2026-09-19")}
        self.assertEqual(set(trips), set(expected))
        for number, (origin, departure, destination, arrival) in expected.items():
            trip = trips[number]
            stops = trip["stop_times"]
            self.assertEqual([self.station_names[row["station_id"]] for row in stops], [origin, destination])
            self.assertEqual(stops[0]["departure_time"], departure)
            self.assertEqual(stops[1]["arrival_time"], arrival)
            self.assertIsNone(trip["train_number"])

    def test_partial_and_unknown_dimensions_stay_conservative(self):
        templates = [trip for trip in self.data["trips"] if trip["service_id"] == SERVICE_ID]
        ids = {trip["trip_id"] for trip in templates}
        statuses = {
            (row["entity_id"], row["dimension"]): row["status"]
            for row in self.data["fact_completeness"]
            if row["entity_id"] in ids
        }
        for trip_id in ids:
            self.assertEqual(statuses[(trip_id, "train_number")], "unknown")
            self.assertEqual(statuses[(trip_id, "stops")], "partial")
            self.assertEqual(statuses[(trip_id, "times")], "partial")
            self.assertEqual(statuses[(trip_id, "operator")], "unknown")
            self.assertEqual(statuses[(trip_id, "route_lines")], "unknown")


if __name__ == "__main__":
    unittest.main()
