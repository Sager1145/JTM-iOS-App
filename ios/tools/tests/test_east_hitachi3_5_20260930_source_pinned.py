"""JR East Hitachi 3/5 exact-day pages retain their printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "3": ("3M", "https://timetables.jreast.co.jp/2610/train/075/076491.html", [
        ("品川", None, "07:43", "９"), ("東京", "07:51", "07:52", "８"),
        ("上野", "07:58", "08:00", "８"), ("柏", "08:28", "08:28", None),
        ("土浦", "08:49", "08:50", None), ("水戸", "09:18", "09:19", "４"),
        ("勝田", "09:24", "09:25", None), ("常陸多賀", "09:36", "09:37", None),
        ("日立", "09:41", "09:41", None), ("磯原", "09:56", "09:57", None),
        ("泉", "10:11", "10:12", None), ("湯本", "10:16", "10:17", None),
        ("いわき", "10:23", "10:25", None), ("広野", "10:42", "10:43", None),
        ("富岡", "10:58", "10:58", None), ("大野", "11:06", "11:07", None),
        ("双葉", "11:11", "11:12", None), ("浪江", "11:16", "11:16", None),
        ("原ノ町", "11:31", "11:32", None), ("相馬", "11:47", "11:48", None),
        ("仙台", "12:27", None, "１"),
    ]),
    "5": ("5M", "https://timetables.jreast.co.jp/2610/train/050/050251.html", [
        ("品川", None, "08:43", "９"), ("東京", "08:51", "08:53", "８"),
        ("上野", "08:59", "09:00", "８"), ("水戸", "10:16", "10:17", "４"),
        ("勝田", "10:21", "10:22", None), ("大甕", "10:31", "10:32", None),
        ("常陸多賀", "10:35", "10:36", None), ("日立", "10:40", "10:40", None),
        ("高萩", "10:50", "10:51", None), ("勿来", "11:04", "11:04", None),
        ("泉", "11:12", "11:13", None), ("湯本", "11:17", "11:18", None),
        ("いわき", "11:24", None, None),
    ]),
}


class EastHitachi3And5Tests(unittest.TestCase):
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
