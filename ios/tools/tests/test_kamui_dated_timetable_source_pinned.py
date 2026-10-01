"""Pin retrievable JR Hokkaido dated details without spreading them across a season."""

import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
ROOT = BASE / "normalized"
CANDIDATE = BASE / "candidates/jr-hokkaido-hokuto-2026summer-north-shikoku-batch.json"


def rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line]


class HokkaidoDatedSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text())
        cls.trips = rows(ROOT / "trips/north-shikoku-batch/seeds.jsonl")
        cls.exceptions = rows(ROOT / "calendar-exceptions/north-shikoku-batch/seeds.jsonl")
        cls.stop_rows = rows(ROOT / "stop-times/north-shikoku-batch/seeds.jsonl")
        cls.names = {
            row["station_id"]: row["name_snapshot"]
            for path in ROOT.glob("station-identities*.jsonl")
            for row in rows(path)
        }
        cls.dates = {
            trip["trip_id"]: {row["service_date"] for row in cls.exceptions if row["calendar_id"] == trip["calendar_id"]}
            for trip in cls.trips
        }

    def test_kamui_retrievable_september_27_columns_only(self):
        self.assertEqual(
            {source["url_or_locator"] for source in self.candidate["kamui_timetable_sources"]},
            {
                "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260927&s=110",
                "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260927&s=111",
            },
        )
        expected = {
            "9": ("8009M", ["札幌", "岩見沢", "美唄", "砂川", "滝川", "深川", "旭川"],
                  ["09:30", "09:55", "10:06", "10:17", "10:22", "10:36", "10:55"]),
            "26": ("8026M", ["旭川", "深川", "滝川", "砂川", "美唄", "岩見沢", "札幌"],
                   ["14:30", "14:49", "15:02", "15:08", "15:20", "15:30", "15:55"]),
        }
        for number, (internal, stations, clocks) in expected.items():
            dated = [trip for trip in self.trips if trip["service_id"] == "kamui" and trip["public_number"] == number
                     and trip["train_number"] == internal]
            self.assertEqual(len(dated), 1)
            trip = dated[0]
            self.assertEqual(self.dates[trip["trip_id"]], {"2026-09-27"})
            calls = sorted((row for row in self.stop_rows if row["trip_id"] == trip["trip_id"]),
                           key=lambda row: row["stop_sequence"])
            self.assertEqual([self.names[row["station_id"]] for row in calls], stations)
            self.assertEqual([row["departure_time"] or row["arrival_time"] for row in calls], clocks)
            base = [row for row in self.trips if row["service_id"] == "kamui" and row["public_number"] == number
                    and row["train_number"] is None]
            self.assertEqual(len(base), 1)
            self.assertNotIn("2026-09-27", self.dates[base[0]["trip_id"]])
            self.assertIn("2026-08-07", self.dates[base[0]["trip_id"]])

    def test_unretrievable_august_kamui_details_are_not_promoted(self):
        for number in ("15", "36"):
            matching = [trip for trip in self.trips if trip["service_id"] == "kamui" and trip["public_number"] == number]
            self.assertEqual(len(matching), 1)
            trip = matching[0]
            self.assertIsNone(trip["train_number"])
            self.assertEqual(self.dates[trip["trip_id"]], {"2026-08-07", "2026-08-08", "2026-08-09"})
            self.assertEqual(len([row for row in self.stop_rows if row["trip_id"] == trip["trip_id"]]), 2)

    def test_hokuto_niseko_and_sarobetsu_details_are_each_exact_day(self):
        expected = {
            ("hokuto", "84", "8022D"): {"2026-09-19", "2026-09-20"},
            ("hokuto", "91", "8021D"): {"2026-09-19", "2026-09-20"},
            ("niseko", None, "8012D"): {"2026-09-22", "2026-09-23", "2026-09-27"},
            ("niseko", None, "9011D"): {"2026-09-22", "2026-09-26", "2026-09-27"},
            ("sarobetsu", "3", "6063D"): {"2026-09-30"},
            ("sarobetsu", "4", "6064D"): {"2026-09-30"},
        }
        for key, days in expected.items():
            matching = [trip for trip in self.trips if
                        (trip["service_id"], trip["public_number"], trip["train_number"]) == key]
            self.assertEqual(len(matching), len(days), key)
            self.assertEqual({day for trip in matching for day in self.dates[trip["trip_id"]]}, days)
            self.assertTrue(all(len(self.dates[trip["trip_id"]]) == 1 for trip in matching))
        for number in ("3", "4"):
            base = [trip for trip in self.trips if trip["service_id"] == "sarobetsu"
                    and trip["public_number"] == number and trip["train_number"] is None]
            self.assertEqual(len(base), 1)
            self.assertEqual(len(self.dates[base[0]["trip_id"]]), 91)
            self.assertNotIn("2026-09-30", self.dates[base[0]["trip_id"]])
            self.assertEqual(len([row for row in self.stop_rows if row["trip_id"] == base[0]["trip_id"]]), 2)


if __name__ == "__main__":
    unittest.main()
