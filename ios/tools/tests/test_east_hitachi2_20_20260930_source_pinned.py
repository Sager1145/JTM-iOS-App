"""JR East Hitachi 2/20 exact-day pages retain their printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "2": ("2M", "https://timetables.jreast.co.jp/2610/train/045/048451.html", [
        ("いわき", None, "05:53", None), ("湯本", "05:59", "05:59", None),
        ("泉", "06:04", "06:04", None), ("勿来", "06:12", "06:13", None),
        ("磯原", "06:20", "06:21", None), ("高萩", "06:27", "06:27", None),
        ("日立", "06:38", "06:39", None), ("常陸多賀", "06:42", "06:43", None),
        ("勝田", "06:55", "06:56", None), ("水戸", "07:01", "07:02", "７"),
        ("土浦", "07:31", "07:32", None), ("上野", "08:35", "08:36", "９"),
        ("東京", "08:41", "08:43", "９"), ("品川", "08:50", None, "９"),
    ]),
    "20": ("20M", "https://timetables.jreast.co.jp/2610/train/045/048601.html", [
        ("いわき", None, "15:18", None), ("湯本", "15:23", "15:24", None),
        ("泉", "15:28", "15:29", None), ("磯原", "15:43", "15:44", None),
        ("日立", "16:01", "16:02", None), ("常陸多賀", "16:05", "16:06", None),
        ("大甕", "16:09", "16:10", None), ("勝田", "16:20", "16:21", None),
        ("水戸", "16:26", "16:27", "７"), ("上野", "17:37", "17:38", "９"),
        ("東京", "17:43", "17:44", "１０"), ("品川", "17:52", None, "９"),
    ]),
}


class EastHitachi2And20Tests(unittest.TestCase):
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
