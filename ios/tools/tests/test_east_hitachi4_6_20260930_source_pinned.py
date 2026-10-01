"""JR East Hitachi 4/6 exact-day pages retain their printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "4": ("4M", "https://timetables.jreast.co.jp/2610/train/045/048471.html", [
        ("いわき", None, "07:03", None), ("湯本", "07:08", "07:09", None),
        ("泉", "07:13", "07:14", None), ("磯原", "07:29", "07:29", None),
        ("日立", "07:44", "07:45", None), ("常陸多賀", "07:49", "07:49", None),
        ("大甕", "07:53", "07:53", None), ("勝田", "08:03", "08:04", None),
        ("水戸", "08:09", "08:10", "７"), ("土浦", "08:38", "08:39", None),
        ("上野", "09:32", "09:33", "９"), ("東京", "09:38", "09:39", "１０"),
        ("品川", "09:48", None, "９"),
    ]),
    "6": ("6M", "https://timetables.jreast.co.jp/2610/train/045/048491.html", [
        ("いわき", None, "08:18", None), ("湯本", "08:23", "08:24", None),
        ("泉", "08:28", "08:29", None), ("勿来", "08:37", "08:37", None),
        ("高萩", "08:50", "08:50", None), ("日立", "09:01", "09:01", None),
        ("常陸多賀", "09:05", "09:06", None), ("大甕", "09:09", "09:10", None),
        ("勝田", "09:20", "09:21", None), ("水戸", "09:26", "09:27", "７"),
        ("上野", "10:35", "10:37", "９"), ("東京", "10:42", "10:43", "１０"),
        ("品川", "10:51", None, "９"),
    ]),
}


class EastHitachi4And6Tests(unittest.TestCase):
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
