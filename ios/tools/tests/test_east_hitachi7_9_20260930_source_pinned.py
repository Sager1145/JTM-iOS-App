"""JR East Hitachi 7/9 exact-day pages retain their printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "7": ("7M", "https://timetables.jreast.co.jp/2610/train/045/047851.html", [
        ("品川", None, "09:45", "９"), ("東京", "09:52", "09:53", "７"),
        ("上野", "09:58", "10:00", "８"), ("水戸", "11:05", "11:06", "４"),
        ("勝田", "11:10", "11:11", None), ("日立", "11:26", "11:26", None),
        ("磯原", "11:41", "11:42", None), ("泉", "11:56", "11:57", None),
        ("湯本", "12:01", "12:02", None), ("いわき", "12:07", None, None),
    ]),
    "9": ("9M", "https://timetables.jreast.co.jp/2610/train/045/048321.html", [
        ("品川", None, "10:45", "９"), ("東京", "10:52", "10:53", "８"),
        ("上野", "10:58", "11:00", "８"), ("水戸", "12:06", "12:07", "４"),
        ("勝田", "12:11", "12:12", None), ("東海", "12:18", "12:18", None),
        ("大甕", "12:23", "12:23", None), ("常陸多賀", "12:27", "12:27", None),
        ("日立", "12:31", "12:32", None), ("高萩", "12:42", "12:42", None),
        ("勿来", "12:55", "12:56", None), ("泉", "13:04", "13:04", None),
        ("湯本", "13:09", "13:09", None), ("いわき", "13:15", None, None),
    ]),
}


class EastHitachi7And9Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_printed_clocks_platforms_and_sources(self):
        day = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        for number, (train_number, url, printed) in PAGES.items():
            trip_id = f"jr-east.hitachi.{number}.exact-2026-09-30"
            with self.subTest(trip=trip_id):
                actual = day[trip_id]
                self.assertEqual((actual["train_number"], actual["public_number"]), (train_number, number))
                self.assertEqual(sources[f"jr-east-hitachi{number}-20260930"]["url_or_locator"], url)
                self.assertEqual(
                    [(self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"], stop["platform"])
                     for stop in actual["stop_times"]], printed,
                )

    def test_day_scope_and_unresolved_segments(self):
        ids = {f"jr-east.hitachi.{number}.exact-2026-09-30" for number in PAGES}
        for other in ("2026-09-29", "2026-10-01"):
            self.assertFalse(ids & {trip["trip_id"] for trip in timetable.materialize(self.data, other)})
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_operator_segments"]))

    def test_train_specific_seat_evidence_stays_partial(self):
        ids = {f"jr-east.hitachi.{number}.exact-2026-09-30" for number in PAGES}
        formations = {row["trip_id"]: row for row in self.data["trip_formations"] if row["trip_id"] in ids}
        for number in PAGES:
            trip_id = f"jr-east.hitachi.{number}.exact-2026-09-30"
            with self.subTest(trip=trip_id):
                formation = formations[trip_id]
                self.assertEqual(formation["source_id"], f"jr-east-hitachi{number}-20260930")
                self.assertEqual(formation["evidence_kind"], "planned")
                self.assertIs(formation["all_reserved"], True)
                self.assertIs(formation["green_car_available"], True)
                for field in ("car_count", "vehicle_series", "formation_label", "reserved_seat_capacity"):
                    self.assertIsNone(formation.get(field))


if __name__ == "__main__":
    unittest.main()
