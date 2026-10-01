"""JR East Hitachi 25/27/28/30 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "25": ("25M", "https://timetables.jreast.co.jp/2610/train/045/048421.html", [
        ("品川", None, "18:45", "９"), ("東京", "18:52", "18:53", "７"),
        ("上野", "18:58", "19:00", "８"), ("土浦", "19:39", "19:40", None),
        ("水戸", "20:09", "20:10", "４"), ("勝田", "20:15", "20:16", None),
        ("大甕", "20:25", "20:25", None), ("常陸多賀", "20:29", "20:29", None),
        ("日立", "20:33", "20:34", None), ("高萩", "20:44", "20:44", None),
        ("勿来", "20:57", "20:58", None), ("泉", "21:06", "21:06", None),
        ("湯本", "21:11", "21:11", None), ("いわき", "21:17", None, None),
    ]),
    "27": ("27M", "https://timetables.jreast.co.jp/2610/train/045/048431.html", [
        ("品川", None, "19:45", "９"), ("東京", "19:52", "19:53", "７"),
        ("上野", "19:58", "20:00", "８"), ("土浦", "20:39", "20:39", None),
        ("水戸", "21:08", "21:09", "４"), ("勝田", "21:13", "21:14", None),
        ("大甕", "21:24", "21:24", None), ("常陸多賀", "21:28", "21:28", None),
        ("日立", "21:32", "21:32", None), ("磯原", "21:49", "21:49", None),
        ("泉", "22:05", "22:05", None), ("湯本", "22:10", "22:10", None),
        ("いわき", "22:16", None, None),
    ]),
    "28": ("28M", "https://timetables.jreast.co.jp/2610/train/045/048631.html", [
        ("いわき", None, "19:18", None), ("湯本", "19:23", "19:24", None),
        ("泉", "19:28", "19:29", None), ("磯原", "19:43", "19:44", None),
        ("日立", "19:59", "20:00", None), ("常陸多賀", "20:04", "20:04", None),
        ("大甕", "20:08", "20:08", None), ("東海", "20:13", "20:14", None),
        ("勝田", "20:20", "20:21", None), ("水戸", "20:26", "20:27", "７"),
        ("上野", "21:37", "21:39", "９"), ("東京", "21:44", "21:46", "１０"),
        ("品川", "21:54", None, "９"),
    ]),
    "30": ("30M", "https://timetables.jreast.co.jp/2610/train/060/064251.html", [
        ("仙台", None, "18:02", "６"), ("岩沼", "18:18", "18:19", None),
        ("亘理", "18:26", "18:27", None), ("相馬", "18:49", "18:50", None),
        ("原ノ町", "19:05", "19:06", None), ("浪江", "19:20", "19:21", None),
        ("双葉", "19:25", "19:25", None), ("大野", "19:30", "19:30", None),
        ("富岡", "19:38", "19:39", None), ("広野", "19:57", "19:57", None),
        ("いわき", "20:15", "20:17", None), ("湯本", "20:22", "20:23", None),
        ("泉", "20:27", "20:28", None), ("勿来", "20:36", "20:36", None),
        ("高萩", "20:49", "20:49", None), ("日立", "20:59", "21:00", None),
        ("常陸多賀", "21:04", "21:04", None), ("大甕", "21:08", "21:09", None),
        ("東海", "21:13", "21:14", None), ("勝田", "21:20", "21:21", None),
        ("水戸", "21:26", "21:27", "７"), ("土浦", "21:55", "21:56", None),
        ("上野", "22:37", "22:39", "９"), ("東京", "22:44", "22:45", "９"),
        ("品川", "22:52", None, "９"),
    ]),
}


class EastHitachi25And27And28And30Tests(unittest.TestCase):
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
