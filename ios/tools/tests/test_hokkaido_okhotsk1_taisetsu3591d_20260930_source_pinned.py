"""The two selected JR Hokkaido down columns retain their printed cells."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
SOURCE = "jr-hokkaido-okhotsk1-taisetsu3591d-20260930"
URL = "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110"
IDS = {
    "71D": "jr-hokkaido.okhotsk.1.exact-2026-09-30",
    "3591D": "jr-hokkaido.taisetsu.3591d.exact-2026-09-30",
}
PRINTED = {
    "71D": [
        ("札幌", None, "06:52"), ("岩見沢", None, "07:20"),
        ("美唄", None, "07:32"), ("砂川", None, "07:45"),
        ("滝川", None, "07:51"), ("深川", None, "08:06"),
        ("旭川", "08:28", "08:31"), ("上川", None, "09:12"),
        ("白滝", None, "09:54"), ("丸瀬布", None, "10:13"),
        ("遠軽", None, "10:33"), ("生田原", None, "10:49"),
        ("留辺蘂", None, "11:09"), ("北見", None, "11:28"),
        ("美幌", None, "11:51"), ("女満別", None, "12:02"),
        ("網走", "12:17", None),
    ],
    "3591D": [
        ("旭川", None, "12:38"), ("上川", None, "13:21"),
        ("白滝", None, "14:01"), ("丸瀬布", None, "14:19"),
        ("遠軽", None, "14:41"), ("生田原", None, "14:57"),
        ("留辺蘂", None, "15:18"), ("北見", None, "15:42"),
        ("美幌", None, "16:06"), ("女満別", None, "16:17"),
        ("網走", "16:32", None),
    ],
}


class HokkaidoDown71DAnd3591DTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}
        cls.day = {row["trip_id"]: row for row in timetable.materialize(cls.data, "2026-09-30")}

    def test_exact_printed_clocks_and_platforms(self):
        for number, tid in IDS.items():
            with self.subTest(train=number):
                trip = self.day[tid]
                self.assertEqual(trip["train_number"], number)
                self.assertEqual(
                    [(self.names[row["station_id"]], row["arrival_time"], row["departure_time"])
                     for row in trip["stop_times"]], PRINTED[number]
                )
                self.assertEqual(
                    {self.names[row["station_id"]]: row["platform"] for row in trip["stop_times"] if row["platform"]},
                    {"札幌": "(10)"} if number == "71D" else {},
                )
        self.assertIsNone(self.day[IDS["3591D"]]["public_number"])

    def test_source_and_date_scope(self):
        source = next(row for row in self.data["source_documents"] if row["source_id"] == SOURCE)
        self.assertEqual(source["url_or_locator"], URL)
        self.assertEqual(source["effective_date"], "2026-09-30")
        for other in ("2026-09-29", "2026-10-01"):
            self.assertFalse(set(IDS.values()) & {row["trip_id"] for row in timetable.materialize(self.data, other)})
        self.assertEqual(sum(row["service_id"] == "okhotsk" for row in self.data["services"]), 1)
        self.assertEqual(sum(row["service_id"] == "taisetsu" for row in self.data["services"]), 1)

    def test_unresolved_segments_and_arrival_sides(self):
        ids = set(IDS.values())
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_operator_segments"]))
        for tid in ids:
            times = [row for row in self.data["fact_completeness"]
                     if row["entity_id"] == tid and row["dimension"] == "times"]
            self.assertEqual([row["status"] for row in times], ["partial"])
        self.assertIsNone(self.day[IDS["71D"]]["stop_times"][1]["arrival_time"])
        self.assertIsNone(self.day[IDS["3591D"]]["stop_times"][1]["arrival_time"])


if __name__ == "__main__":
    unittest.main()
