"""Source-pinned checks for the JR Shikoku Ishizuchi Silver Week batch."""

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
VERSION_ID = "jr-shikoku.ishizuchi.silver-week-2026.version"
ANNOUNCEMENT_SOURCE_ID = "jr-shikoku-summer-20260515-ishizuchi-silver-week-following"
FIVE_DAY_NUMBERS = {"3", "4"}
SPECIAL_DATES = [f"2026-09-{day:02d}" for day in range(18, 24)]
POLICY = {
    "publisher": "西日本旅客鉄道株式会社 / 株式会社交通新聞社",
    "source_type": "official_train_timetable",
    "license_status": "explicit_reproduction_and_processing_prohibition",
    "redistribution_status": "verification_only",
    "automated_extraction_allowed": False,
}

# station, arrival, departure, platform; official pass rows are intentionally absent.
TRAIN_DATA = {
    "3": ("9003M", "246621", [("高松", None, "08:45", "8"), ("坂出", "09:00", "09:02", None), ("宇多津", "09:06", None, None)]),
    "4": ("9004D", "177111", [("宇多津", None, "07:14", None), ("坂出", "07:20", "07:21", None), ("高松", "07:36", None, "8")]),
    "5": ("9005D", "227751", [("高松", None, "09:42", "7"), ("坂出", "09:55", "09:56", None), ("宇多津", "10:00", "10:01", None), ("丸亀", "10:04", "10:05", None), ("多度津", "10:10", None, None)]),
    "6": ("9006D", "227821", [("宇多津", None, "08:26", None), ("坂出", "08:30", "08:31", None), ("高松", "08:45", None, "7")]),
    "7": ("9007D", "227761", [("高松", None, "10:47", "6"), ("坂出", "11:03", "11:04", None), ("宇多津", "11:08", "11:09", None), ("丸亀", "11:12", "11:12", None), ("多度津", "11:17", None, None)]),
    "8": ("9008D", "227771", [("宇多津", None, "09:25", None), ("坂出", "09:31", "09:32", None), ("高松", "09:47", None, "6")]),
    "9": ("9009M", "177201", [("高松", None, "11:50", "7"), ("坂出", "12:03", "12:04", None), ("宇多津", "12:08", "12:09", None), ("丸亀", "12:12", "12:13", None), ("多度津", "12:18", None, None)]),
    "10": ("9010M", "177241", [("宇多津", None, "10:19", None), ("坂出", "10:24", "10:24", None), ("高松", "10:39", None, "7")]),
    "11": ("9011D", "392781", [("高松", None, "12:50", "7"), ("坂出", "13:03", "13:04", None), ("宇多津", "13:09", "13:09", None), ("丸亀", "13:12", "13:13", None), ("多度津", "13:18", None, None)]),
    "12": ("9012D", "392791", [("宇多津", None, "11:33", None), ("坂出", "11:38", "11:39", None), ("高松", "11:54", None, "7")]),
    "13": ("9013D", "247041", [("高松", None, "13:50", "7"), ("坂出", "14:03", "14:04", None), ("宇多津", "14:09", "14:09", None), ("丸亀", "14:12", "14:13", None), ("多度津", "14:18", None, None)]),
    "14": ("9014D", "247051", [("宇多津", None, "12:33", None), ("坂出", "12:38", "12:39", None), ("高松", "12:54", None, "7")]),
    "15": ("9015M", "177211", [("高松", None, "14:50", "7"), ("坂出", "15:04", "15:04", None), ("宇多津", "15:09", "15:09", None), ("丸亀", "15:12", "15:13", None), ("多度津", "15:18", None, None)]),
    "16": ("9016M", "177251", [("宇多津", None, "13:34", None), ("坂出", "13:39", "13:39", None), ("高松", "13:55", None, "7")]),
    "17": ("9017D", "308031", [("高松", None, "15:50", "7"), ("坂出", "16:04", "16:04", None), ("宇多津", "16:09", "16:09", None), ("丸亀", "16:12", "16:13", None), ("多度津", "16:18", None, None)]),
    "18": ("9018D", "308041", [("宇多津", None, "14:34", None), ("坂出", "14:39", "14:39", None), ("高松", "14:56", None, "7")]),
    "19": ("9019D", "227781", [("高松", None, "16:50", "7"), ("坂出", "17:04", "17:04", None), ("宇多津", "17:09", "17:09", None), ("丸亀", "17:12", "17:13", None), ("多度津", "17:18", None, None)]),
    "20": ("9020D", "227801", [("宇多津", None, "15:34", None), ("坂出", "15:39", "15:39", None), ("高松", "15:56", None, "7")]),
    "21": ("9021M", "177221", [("高松", None, "17:53", "7"), ("坂出", "18:07", "18:08", None), ("宇多津", "18:12", "18:13", None), ("丸亀", "18:16", "18:17", None), ("多度津", "18:22", None, None)]),
    "22": ("9022M", "177261", [("宇多津", None, "16:34", None), ("坂出", "16:38", "16:39", None), ("高松", "16:54", None, "7")]),
    "23": ("9023D", "227791", [("高松", None, "18:59", "8"), ("坂出", "19:12", "19:13", None), ("宇多津", "19:17", "19:17", None), ("丸亀", "19:20", "19:20", None), ("多度津", "19:26", None, None)]),
    "24": ("9024D", "227811", [("宇多津", None, "17:35", None), ("坂出", "17:40", "17:41", None), ("高松", "17:57", None, "8")]),
    "25": ("9025D", "246131", [("高松", None, "19:51", "7"), ("坂出", "20:07", "20:07", None), ("宇多津", "20:12", "20:12", None), ("丸亀", "20:15", "20:16", None), ("多度津", "20:22", None, None)]),
    "26": ("9026D", "246141", [("宇多津", None, "18:36", None), ("坂出", "18:40", "18:41", None), ("高松", "18:56", None, "7")]),
    "27": ("9027M", "177231", [("高松", None, "20:59", "8"), ("坂出", "21:13", "21:13", None), ("宇多津", "21:18", "21:18", None), ("丸亀", "21:21", "21:22", None), ("多度津", "21:27", None, None)]),
    "28": ("9028M", "177271", [("宇多津", None, "19:38", None), ("坂出", "19:42", "19:43", None), ("高松", "19:58", None, "8")]),
}


def operating_dates(public_number):
    return SPECIAL_DATES[1:] if public_number in FIVE_DAY_NUMBERS else SPECIAL_DATES


def train_source_id(train_number, day):
    return f"jr-odekake-ishizuchi-{train_number.lower()}-{day.replace('-', '')}-special"


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

    def test_announcement_and_154_exact_dated_sources_are_pinned(self):
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        announcement = sources[ANNOUNCEMENT_SOURCE_ID]
        self.assertEqual(
            announcement["url_or_locator"],
            "https://www.jr-shikoku.co.jp/03_news/press/assets/2026/07/15/20260515%20.pdf",
        )
        self.assertEqual(
            announcement["content_hash"],
            "sha256:64e69d7df9da8d58326653d9334a7b0683c1645b5b6ba2d42d32d0f714d3c2c6",
        )
        expected_ids = set()
        for public_number, (train_number, page_id, _) in TRAIN_DATA.items():
            for day in operating_dates(public_number):
                source_id = train_source_id(train_number, day)
                expected_ids.add(source_id)
                source = sources[source_id]
                self.assertEqual(
                    source["url_or_locator"],
                    f"https://timetable.jr-odekake.net/train-timetable/{page_id}?date={day.replace('-', '')}",
                )
                self.assertEqual(source["effective_date"], day)
                for key, value in POLICY.items():
                    self.assertEqual(source[key], value)
        self.assertEqual(len(expected_ids), 154)
        actual_ids = {
            source_id for source_id in sources
            if source_id.startswith("jr-odekake-ishizuchi-")
        }
        self.assertEqual(actual_ids, expected_ids)

    def test_exact_date_variant_selection_materializes_154_occurrences(self):
        on_18 = {trip["public_number"]: trip["train_number"] for trip in self.trips("2026-09-18")}
        on_19 = {trip["public_number"]: trip["train_number"] for trip in self.trips("2026-09-19")}
        self.assertEqual(len(on_18), 24)
        self.assertNotIn("3", on_18)
        self.assertNotIn("4", on_18)
        self.assertEqual(on_19, {number: data[0] for number, data in TRAIN_DATA.items()})
        self.assertEqual(len(self.trips("2026-09-23")), 26)
        self.assertFalse(self.trips("2026-09-17"))
        self.assertFalse(self.trips("2026-09-24"))
        current = date(2026, 9, 18)
        total = 0
        while current <= date(2026, 9, 24):
            total += len(self.trips(current.isoformat()))
            current += timedelta(days=1)
        self.assertEqual(total, 154)

    def test_all_26_passenger_call_sequences_clocks_and_platforms_are_pinned(self):
        trips = {trip["public_number"]: trip for trip in self.trips("2026-09-19")}
        self.assertEqual(set(trips), set(TRAIN_DATA))
        self.assertEqual(sum(len(data[2]) for data in TRAIN_DATA.values()), 102)
        for public_number, (train_number, _, expected_calls) in TRAIN_DATA.items():
            trip = trips[public_number]
            self.assertEqual(trip["train_number"], train_number)
            actual_calls = [
                (
                    self.station_names[row["station_id"]],
                    row["arrival_time"], row["departure_time"], row.get("platform"),
                )
                for row in trip["stop_times"]
            ]
            self.assertEqual(actual_calls, expected_calls)
            self.assertEqual(trip["stop_times"][0]["call_type"], "origin")
            self.assertEqual(trip["stop_times"][-1]["call_type"], "destination")
            self.assertNotIn("pass", {row["call_type"] for row in trip["stop_times"]})

    def test_complete_dimensions_and_each_applicable_dated_source_are_pinned(self):
        # Public numbers are reused by the independently reviewed September 30 trains.
        templates = [
            trip for trip in self.data["trips"]
            if trip["service_id"] == SERVICE_ID
            and trip["timetable_version_id"] == VERSION_ID
        ]
        self.assertEqual(len(templates), 26)
        self.assertEqual({trip["public_number"] for trip in templates}, set(TRAIN_DATA))
        ids = {trip["trip_id"] for trip in templates}
        statuses = {
            (row["entity_id"], row["dimension"]): row["status"]
            for row in self.data["fact_completeness"]
            if row["entity_id"] in ids
        }
        fact_sources = [row for row in self.data["fact_sources"] if row["entity_id"] in ids]
        templates_by_number = {trip["public_number"]: trip for trip in templates}
        for public_number, (train_number, _, _) in TRAIN_DATA.items():
            trip = templates_by_number[public_number]
            trip_id = trip["trip_id"]
            self.assertEqual(trip_id, f"jr-shikoku.ishizuchi.{public_number}.2026-09-18")
            self.assertEqual(trip["train_number"], train_number)
            for dimension in ("train_number", "stops", "times"):
                self.assertEqual(statuses[(trip_id, dimension)], "verified")
            self.assertEqual(statuses[(trip_id, "operator")], "unknown")
            self.assertEqual(statuses[(trip_id, "route_lines")], "unknown")
            self.assertEqual(statuses[(trip_id, "provenance")], "partial")
            expected_sources = {
                train_source_id(train_number, day) for day in operating_dates(public_number)
            }
            for dimension in ("identity", "train_number", "origin_destination", "stops", "times"):
                actual_sources = {
                    row["source_id"] for row in fact_sources
                    if row["entity_id"] == trip_id and row["field_name"] == dimension
                }
                self.assertEqual(actual_sources, expected_sources)

    def test_shared_version_and_calendar_sources_are_complete(self):
        versions = [
            row for row in self.data["timetable_versions"]
            if row["timetable_version_id"] == VERSION_ID
        ]
        self.assertEqual(len(versions), 1)
        self.assertEqual((versions[0]["effective_from"], versions[0]["effective_until"]),
                         ("2026-09-18", "2026-09-24"))
        self.assertEqual(len(versions[0]["source_ids"]), 155)
        self.assertEqual(len(set(versions[0]["source_ids"])), 155)
        exceptions = [
            row for row in self.data["calendar_exceptions"]
            if row["source_id"] == ANNOUNCEMENT_SOURCE_ID
            and row["calendar_id"].startswith("jr-shikoku.ishizuchi.silver-week-2026")
        ]
        self.assertEqual(len(exceptions), 11)


if __name__ == "__main__":
    unittest.main()
