"""JR East Tokiwa 75/76/77/78 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "75": ("75M", "https://timetables.jreast.co.jp/2610/train/075/076341.html", [
        ("品川", None, "19:15", "９"), ("東京", "19:22", "19:24", "７"),
        ("上野", "19:29", "19:30", "８"), ("柏", "19:52", "19:53", None),
        ("龍ケ崎市", "20:05", "20:06", None), ("牛久", "20:10", "20:10", None),
        ("土浦", "20:20", "20:21", None), ("石岡", "20:30", "20:31", None),
        ("友部", "20:42", "20:42", None), ("赤塚", "20:48", "20:49", None),
        ("水戸", "20:53", "20:54", "４"), ("勝田", "20:59", None, None),
    ]),
    "76": ("76M", "https://timetables.jreast.co.jp/2610/train/045/048531.html", [
        ("勝田", None, "16:47", None), ("水戸", "16:52", "16:53", "７"),
        ("友部", "17:03", "17:03", None), ("石岡", "17:14", "17:15", None),
        ("土浦", "17:24", "17:25", None), ("柏", "17:46", "17:46", None),
        ("上野", "18:06", "18:08", "９"), ("東京", "18:13", "18:15", "９"),
        ("品川", "18:23", None, "９"),
    ]),
    "77": ("77M", "https://timetables.jreast.co.jp/2610/train/075/076361.html", [
        ("品川", None, "20:15", "９"), ("東京", "20:22", "20:23", "７"),
        ("上野", "20:29", "20:30", "８"), ("柏", "20:50", "20:51", None),
        ("龍ケ崎市", "21:04", "21:04", None), ("牛久", "21:08", "21:09", None),
        ("土浦", "21:17", "21:17", None), ("石岡", "21:27", "21:27", None),
        ("友部", "21:38", "21:38", None), ("赤塚", "21:45", "21:45", None),
        ("水戸", "21:50", "21:51", "４"), ("勝田", "21:55", "21:56", None),
        ("大甕", "22:05", "22:06", None), ("常陸多賀", "22:09", "22:10", None),
        ("日立", "22:13", "22:14", None), ("高萩", "22:24", None, None),
    ]),
    "78": ("78M", "https://timetables.jreast.co.jp/2610/train/045/048541.html", [
        ("勝田", None, "17:47", None), ("水戸", "17:52", "17:53", "７"),
        ("友部", "18:03", "18:03", None), ("石岡", "18:14", "18:14", None),
        ("土浦", "18:24", "18:24", None), ("柏", "18:45", "18:46", None),
        ("上野", "19:06", "19:08", "９"), ("東京", "19:12", "19:14", "９"),
        ("品川", "19:21", None, "９"),
    ]),
}


class EastTokiwa75And76And77And78Tests(unittest.TestCase):
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
            trip_id = f"jr-east.tokiwa.{number}.exact-2026-09-30"
            with self.subTest(trip=trip_id):
                actual = day[trip_id]
                self.assertEqual((actual["train_number"], actual["public_number"]), (train_number, number))
                self.assertEqual(sources[f"jr-east-tokiwa{number}-20260930"]["url_or_locator"], url)
                self.assertEqual(
                    [(self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"], stop["platform"])
                     for stop in actual["stop_times"]], printed,
                )

    def test_day_scope_and_unresolved_segments(self):
        ids = {f"jr-east.tokiwa.{number}.exact-2026-09-30" for number in PAGES}
        for other in ("2026-09-29", "2026-10-01"):
            self.assertFalse(ids & {trip["trip_id"] for trip in timetable.materialize(self.data, other)})
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_operator_segments"]))

    def test_train_specific_seat_evidence_stays_partial(self):
        ids = {f"jr-east.tokiwa.{number}.exact-2026-09-30" for number in PAGES}
        formations = {row["trip_id"]: row for row in self.data["trip_formations"] if row["trip_id"] in ids}
        for number in PAGES:
            trip_id = f"jr-east.tokiwa.{number}.exact-2026-09-30"
            with self.subTest(trip=trip_id):
                formation = formations[trip_id]
                self.assertEqual(formation["source_id"], f"jr-east-tokiwa{number}-20260930")
                self.assertEqual(formation["evidence_kind"], "planned")
                self.assertIs(formation["all_reserved"], True)
                self.assertIs(formation["green_car_available"], True)
                for field in ("car_count", "vehicle_series", "formation_label", "reserved_seat_capacity"):
                    self.assertIsNone(formation.get(field))


if __name__ == "__main__":
    unittest.main()
