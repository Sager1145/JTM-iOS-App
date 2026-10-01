"""JR East Tsugaru 42 and Super Tsugaru 2 exact-day printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "tsugaru": ("42", "2042M", "https://timetables.jreast.co.jp/2610/train/005/008181.html", [
        ("青森", None, "09:04", "５"), ("新青森", "09:09", "09:11", "２"),
        ("浪岡", "09:26", "09:26", None), ("弘前", "09:38", "09:40", None),
        ("大鰐温泉", "09:50", "09:50", None), ("碇ケ関", "09:58", "09:58", None),
        ("大館", "10:16", "10:17", None), ("鷹ノ巣", "10:32", "10:32", None),
        ("二ツ井", "10:42", "10:43", None), ("東能代", "10:56", "10:56", None),
        ("森岳", "11:06", "11:06", None), ("八郎潟", "11:20", "11:21", None),
        ("秋田", "11:45", None, "４"),
    ]),
    "super-tsugaru": ("2", "2022M", "https://timetables.jreast.co.jp/2610/train/095/098671.html", [
        ("青森", None, "12:40", "３"), ("新青森", "12:45", "12:47", "２"),
        ("弘前", "13:13", "13:15", None), ("大鰐温泉", "13:24", "13:25", None),
        ("大館", "13:49", "13:50", None), ("鷹ノ巣", "14:05", "14:05", None),
        ("東能代", "14:27", "14:28", None), ("秋田", "15:12", None, "４"),
    ]),
}


class EastTsugaru42SuperTsugaru2Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_service_identity_printed_clocks_platforms_and_sources(self):
        day = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        for service, (number, train_number, url, printed) in PAGES.items():
            trip_id = f"jr-east.{service}.{number}.exact-2026-09-30"
            with self.subTest(trip=trip_id):
                actual = day[trip_id]
                self.assertEqual((actual["service_id"], actual["public_number"], actual["train_number"]),
                                 (service, number, train_number))
                self.assertEqual(sources[f"jr-east-{service}{number}-20260930"]["url_or_locator"], url)
                self.assertEqual(
                    [(self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"], stop["platform"])
                     for stop in actual["stop_times"]], printed,
                )

    def test_day_scope_and_unresolved_segments(self):
        ids = {f"jr-east.{service}.{number}.exact-2026-09-30"
               for service, (number, *_rest) in PAGES.items()}
        for other in ("2026-09-29", "2026-10-01"):
            self.assertFalse(ids & {trip["trip_id"] for trip in timetable.materialize(self.data, other)})
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_operator_segments"]))

    def test_partial_ordinary_reservation_and_green_car(self):
        formations = {row["trip_id"]: row for row in self.data["trip_formations"]}
        for service, (number, *_rest) in PAGES.items():
            trip_id = f"jr-east.{service}.{number}.exact-2026-09-30"
            with self.subTest(trip=trip_id):
                formation = formations[trip_id]
                self.assertEqual(formation["source_id"], f"jr-east-{service}{number}-20260930")
                self.assertEqual(formation["evidence_kind"], "planned")
                self.assertIs(formation["all_reserved"], False)
                self.assertIs(formation["green_car_available"], True)
                for field in ("car_count", "vehicle_series", "formation_label", "reserved_seat_capacity"):
                    self.assertIsNone(formation.get(field))


if __name__ == "__main__":
    unittest.main()
