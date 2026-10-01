"""JR East Tokiwa 63/64/65/66 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "63": ("63M", "https://timetables.jreast.co.jp/2610/train/075/076311.html", [
        ("品川", None, "13:15", "９"), ("東京", "13:22", "13:23", "８"),
        ("上野", "13:28", "13:30", "８"), ("柏", "13:49", "13:50", None),
        ("土浦", "14:11", "14:12", None), ("石岡", "14:22", "14:22", None),
        ("友部", "14:33", "14:34", None), ("水戸", "14:44", "14:45", "４"),
        ("勝田", "14:50", None, None),
    ]),
    "64": ("64M", "https://timetables.jreast.co.jp/2610/train/060/064261.html", [
        ("高萩", None, "10:16", None), ("日立", "10:26", "10:27", None),
        ("常陸多賀", "10:30", "10:31", None), ("大甕", "10:34", "10:35", None),
        ("東海", "10:40", "10:40", None), ("勝田", "10:46", "10:47", None),
        ("水戸", "10:52", "10:53", "７"), ("友部", "11:03", "11:03", None),
        ("石岡", "11:14", "11:15", None), ("土浦", "11:24", "11:25", None),
        ("柏", "11:46", "11:47", None), ("上野", "12:06", "12:08", "９"),
        ("東京", "12:13", "12:14", "１０"), ("品川", "12:22", None, "９"),
    ]),
    "65": ("65M", "https://timetables.jreast.co.jp/2610/train/045/048371.html", [
        ("品川", None, "14:15", "９"), ("東京", "14:22", "14:23", "８"),
        ("上野", "14:28", "14:30", "８"), ("柏", "14:49", "14:50", None),
        ("土浦", "15:11", "15:11", None), ("石岡", "15:22", "15:23", None),
        ("友部", "15:34", "15:35", None), ("水戸", "15:45", "15:46", "４"),
        ("勝田", "15:51", None, None),
    ]),
    "66": ("66M", "https://timetables.jreast.co.jp/2610/train/050/050321.html", [
        ("勝田", None, "11:47", None), ("水戸", "11:52", "11:53", "７"),
        ("友部", "12:03", "12:03", None), ("石岡", "12:14", "12:15", None),
        ("土浦", "12:25", "12:26", None), ("柏", "12:47", "12:48", None),
        ("上野", "13:07", "13:09", "９"), ("東京", "13:14", "13:15", "９"),
        ("品川", "13:22", None, "９"),
    ]),
}


class EastTokiwa63And64And65And66Tests(unittest.TestCase):
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
