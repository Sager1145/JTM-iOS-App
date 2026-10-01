"""JR East Hitachi 14/18 exact-day pages retain their printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "14": ("14M", "https://timetables.jreast.co.jp/2610/train/095/098711.html", [
        ("いわき", None, "12:18", None), ("湯本", "12:23", "12:24", None),
        ("泉", "12:28", "12:29", None), ("勿来", "12:37", "12:38", None),
        ("高萩", "12:50", "12:51", None), ("日立", "13:01", "13:02", None),
        ("常陸多賀", "13:05", "13:06", None), ("大甕", "13:10", "13:10", None),
        ("勝田", "13:20", "13:21", None), ("水戸", "13:26", "13:27", "７"),
        ("上野", "14:35", "14:37", "９"), ("東京", "14:42", "14:43", "１０"),
        ("品川", "14:51", None, "９"),
    ]),
    "18": ("18M", "https://timetables.jreast.co.jp/2610/train/045/048591.html", [
        ("いわき", None, "14:18", None), ("湯本", "14:23", "14:24", None),
        ("泉", "14:28", "14:29", None), ("勿来", "14:37", "14:37", None),
        ("高萩", "14:50", "14:50", None), ("日立", "15:01", "15:02", None),
        ("常陸多賀", "15:05", "15:06", None), ("大甕", "15:09", "15:10", None),
        ("勝田", "15:20", "15:21", None), ("水戸", "15:26", "15:27", "７"),
        ("上野", "16:36", "16:38", "９"), ("東京", "16:43", "16:44", "９"),
        ("品川", "16:51", None, "９"),
    ]),
}


class EastHitachi14And18Tests(unittest.TestCase):
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
