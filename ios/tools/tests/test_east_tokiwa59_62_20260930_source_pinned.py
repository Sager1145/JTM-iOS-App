"""JR East Tokiwa 59/60/61/62 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "59": ("59M", "https://timetables.jreast.co.jp/2610/train/045/048331.html", [
        ("品川", None, "11:15", "９"), ("東京", "11:22", "11:23", "８"),
        ("上野", "11:28", "11:30", "８"), ("柏", "11:49", "11:50", None),
        ("土浦", "12:11", "12:12", None), ("石岡", "12:22", "12:22", None),
        ("友部", "12:33", "12:34", None), ("水戸", "12:44", "12:45", "４"),
        ("勝田", "12:50", None, None),
    ]),
    "60": ("60M", "https://timetables.jreast.co.jp/2610/train/075/076441.html", [
        ("高萩", None, "08:10", None), ("日立", "08:21", "08:21", None),
        ("常陸多賀", "08:26", "08:26", None), ("大甕", "08:30", "08:31", None),
        ("勝田", "08:40", "08:41", None), ("水戸", "08:47", "08:48", "７"),
        ("友部", "08:58", "08:59", None), ("石岡", "09:09", "09:10", None),
        ("土浦", "09:19", "09:20", None), ("柏", "09:44", "09:45", None),
        ("上野", "10:06", "10:08", "９"), ("東京", "10:13", "10:14", "１０"),
        ("品川", "10:23", None, "９"),
    ]),
    "61": ("61M", "https://timetables.jreast.co.jp/2610/train/045/048351.html", [
        ("品川", None, "12:15", "９"), ("東京", "12:22", "12:23", "８"),
        ("上野", "12:28", "12:30", "８"), ("柏", "12:49", "12:50", None),
        ("土浦", "13:11", "13:12", None), ("石岡", "13:22", "13:22", None),
        ("友部", "13:33", "13:34", None), ("水戸", "13:44", "13:45", "４"),
        ("勝田", "13:50", None, None),
    ]),
    "62": ("62M", "https://timetables.jreast.co.jp/2610/train/075/076461.html", [
        ("勝田", None, "09:47", None), ("水戸", "09:52", "09:53", "７"),
        ("友部", "10:03", "10:03", None), ("石岡", "10:14", "10:15", None),
        ("土浦", "10:24", "10:25", None), ("柏", "10:46", "10:47", None),
        ("上野", "11:06", "11:08", "９"), ("東京", "11:13", "11:14", "９"),
        ("品川", "11:22", None, "９"),
    ]),
}


class EastTokiwa59And60And61And62Tests(unittest.TestCase):
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
