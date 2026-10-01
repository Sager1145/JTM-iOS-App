"""JR East Hitachi 1/29 exact-day pages retain their printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "1": ("1M", "https://timetables.jreast.co.jp/2610/train/045/047841.html", [
        ("品川", None, "06:45", "９"), ("東京", "06:52", "06:53", "７"),
        ("上野", "06:58", "07:00", "８"), ("土浦", "07:41", "07:42", None),
        ("水戸", "08:10", "08:11", "４"), ("勝田", "08:16", "08:17", None),
        ("日立", "08:34", "08:34", None), ("高萩", "08:44", "08:45", None),
        ("勿来", "08:58", "08:58", None), ("泉", "09:06", "09:07", None),
        ("湯本", "09:11", "09:12", None), ("いわき", "09:18", None, None),
    ]),
    "29": ("29M", "https://timetables.jreast.co.jp/2610/train/045/048441.html", [
        ("品川", None, "20:45", "９"), ("東京", "20:52", "20:54", "８"),
        ("上野", "20:59", "21:00", "８"), ("土浦", "21:41", "21:42", None),
        ("水戸", "22:10", "22:11", "４"), ("勝田", "22:16", "22:17", None),
        ("大甕", "22:27", "22:27", None), ("常陸多賀", "22:31", "22:31", None),
        ("日立", "22:35", "22:35", None), ("磯原", "22:50", "22:51", None),
        ("勿来", "22:58", "22:59", None), ("泉", "23:07", "23:07", None),
        ("湯本", "23:12", "23:12", None), ("いわき", "23:19", None, None),
    ]),
}


class EastHitachi1And29Tests(unittest.TestCase):
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
