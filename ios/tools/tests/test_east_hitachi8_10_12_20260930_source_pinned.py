"""JR East Hitachi 8/10/12 exact-day pages retain their printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "8": ("8M", "https://timetables.jreast.co.jp/2610/train/045/048501.html", [
        ("いわき", None, "09:21", None), ("湯本", "09:26", "09:27", None),
        ("泉", "09:31", "09:32", None), ("磯原", "09:46", "09:47", None),
        ("日立", "10:02", "10:02", None), ("常陸多賀", "10:06", "10:07", None),
        ("大甕", "10:10", "10:11", None), ("勝田", "10:20", "10:21", None),
        ("水戸", "10:26", "10:27", "７"), ("上野", "11:35", "11:37", "９"),
        ("東京", "11:42", "11:43", "１０"), ("品川", "11:51", None, "９"),
    ]),
    "10": ("10M", "https://timetables.jreast.co.jp/2610/train/045/048511.html", [
        ("いわき", None, "10:17", None), ("湯本", "10:22", "10:23", None),
        ("泉", "10:27", "10:28", None), ("勿来", "10:36", "10:37", None),
        ("高萩", "10:50", "10:51", None), ("日立", "11:02", "11:02", None),
        ("常陸多賀", "11:06", "11:07", None), ("勝田", "11:20", "11:21", None),
        ("水戸", "11:26", "11:27", "７"), ("上野", "12:35", "12:37", "９"),
        ("東京", "12:42", "12:43", "１０"), ("品川", "12:51", None, "９"),
    ]),
    "12": ("12M", "https://timetables.jreast.co.jp/2610/train/095/098701.html", [
        ("仙台", None, "08:48", "６"), ("相馬", "09:32", "09:33", None),
        ("原ノ町", "09:49", "09:51", None), ("浪江", "10:05", "10:06", None),
        ("双葉", "10:10", "10:10", None), ("大野", "10:15", "10:15", None),
        ("富岡", "10:24", "10:24", None), ("広野", "10:40", "10:44", None),
        ("いわき", "11:08", "11:13", None), ("湯本", "11:19", "11:20", None),
        ("泉", "11:25", "11:25", None), ("磯原", "11:42", "11:42", None),
        ("日立", "12:00", "12:00", None), ("常陸多賀", "12:05", "12:05", None),
        ("勝田", "12:20", "12:21", None), ("水戸", "12:26", "12:27", "７"),
        ("上野", "13:35", "13:37", "９"), ("東京", "13:42", "13:43", "１０"),
        ("品川", "13:51", None, "９"),
    ]),
}


class EastHitachi8To12Tests(unittest.TestCase):
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
