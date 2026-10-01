"""JR East Hitachi 11/15/16/17 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "11": ("11M", "https://timetables.jreast.co.jp/2610/train/045/048341.html", [
        ("品川", None, "11:45", "９"), ("東京", "11:52", "11:53", "７"),
        ("上野", "11:58", "12:00", "８"), ("水戸", "13:06", "13:07", "４"),
        ("勝田", "13:11", "13:12", None), ("日立", "13:27", "13:27", None),
        ("磯原", "13:42", "13:43", None), ("泉", "13:57", "13:58", None),
        ("湯本", "14:02", "14:03", None), ("いわき", "14:09", None, None),
    ]),
    "15": ("15M", "https://timetables.jreast.co.jp/2610/train/045/048361.html", [
        ("品川", None, "13:45", "９"), ("東京", "13:52", "13:53", "８"),
        ("上野", "13:58", "14:00", "８"), ("水戸", "15:08", "15:09", "４"),
        ("勝田", "15:13", "15:14", None), ("日立", "15:29", "15:29", None),
        ("磯原", "15:44", "15:45", None), ("泉", "15:59", "16:00", None),
        ("湯本", "16:04", "16:05", None), ("いわき", "16:11", None, None),
    ]),
    "16": ("16M", "https://timetables.jreast.co.jp/2610/train/045/048561.html", [
        ("いわき", None, "13:23", None), ("湯本", "13:28", "13:29", None),
        ("泉", "13:33", "13:34", None), ("磯原", "13:48", "13:49", None),
        ("日立", "14:04", "14:05", None), ("勝田", "14:20", "14:21", None),
        ("水戸", "14:26", "14:27", "７"), ("上野", "15:35", "15:37", "９"),
        ("東京", "15:42", "15:43", "９"), ("品川", "15:51", None, "９"),
    ]),
    "17": ("17M", "https://timetables.jreast.co.jp/2610/train/045/048381.html", [
        ("品川", None, "14:45", "９"), ("東京", "14:52", "14:53", "７"),
        ("上野", "14:58", "15:00", "８"), ("水戸", "16:06", "16:07", "４"),
        ("勝田", "16:11", "16:12", None), ("大甕", "16:21", "16:22", None),
        ("常陸多賀", "16:25", "16:26", None), ("日立", "16:29", "16:30", None),
        ("高萩", "16:40", "16:40", None), ("勿来", "16:53", "16:54", None),
        ("泉", "17:02", "17:02", None), ("湯本", "17:07", "17:07", None),
        ("いわき", "17:14", None, None),
    ]),
}


class EastHitachi11And15And16And17Tests(unittest.TestCase):
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
