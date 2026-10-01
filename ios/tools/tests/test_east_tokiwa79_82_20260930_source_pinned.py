"""JR East Tokiwa 79/80/81/82 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "79": ("79M", "https://timetables.jreast.co.jp/2610/train/050/050281.html", [
        ("品川", None, "21:15", "９"), ("東京", "21:22", "21:23", "７"),
        ("上野", "21:29", "21:30", "８"), ("柏", "21:52", "21:53", None),
        ("龍ケ崎市", "22:04", "22:05", None), ("牛久", "22:08", "22:09", None),
        ("ひたち野うしく", "22:12", "22:12", None), ("荒川沖", "22:15", "22:15", None),
        ("土浦", "22:20", "22:21", None), ("石岡", "22:30", "22:31", None),
        ("友部", "22:41", "22:42", None), ("赤塚", "22:48", "22:49", None),
        ("水戸", "22:54", "22:55", "４"), ("勝田", "23:00", None, None),
    ]),
    "80": ("80M", "https://timetables.jreast.co.jp/2610/train/045/048571.html", [
        ("勝田", None, "18:47", None), ("水戸", "18:52", "18:53", "７"),
        ("友部", "19:03", "19:03", None), ("石岡", "19:14", "19:14", None),
        ("土浦", "19:24", "19:24", None), ("柏", "19:45", "19:46", None),
        ("上野", "20:08", "20:10", "９"), ("東京", "20:15", "20:16", "１０"),
        ("品川", "20:23", None, "９"),
    ]),
    "81": ("81M", "https://timetables.jreast.co.jp/2610/train/075/076371.html", [
        ("品川", None, "21:45", "９"), ("東京", "21:52", "21:53", "８"),
        ("上野", "21:58", "22:00", "８"), ("柏", "22:21", "22:22", None),
        ("土浦", "22:42", "22:43", None), ("石岡", "22:52", "22:53", None),
        ("友部", "23:04", "23:04", None), ("水戸", "23:14", "23:15", "４"),
        ("勝田", "23:19", "23:20", None), ("東海", "23:25", "23:26", None),
        ("大甕", "23:31", "23:31", None), ("常陸多賀", "23:35", "23:35", None),
        ("日立", "23:39", "23:39", None), ("高萩", "23:50", None, None),
    ]),
    "82": ("82M", "https://timetables.jreast.co.jp/2610/train/075/076481.html", [
        ("勝田", None, "19:47", None), ("水戸", "19:52", "19:53", "７"),
        ("友部", "20:03", "20:03", None), ("石岡", "20:14", "20:14", None),
        ("土浦", "20:24", "20:24", None), ("柏", "20:45", "20:46", None),
        ("上野", "21:06", "21:08", "９"), ("東京", "21:13", "21:14", "１０"),
        ("品川", "21:23", None, "９"),
    ]),
}


class EastTokiwa79And80And81And82Tests(unittest.TestCase):
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
