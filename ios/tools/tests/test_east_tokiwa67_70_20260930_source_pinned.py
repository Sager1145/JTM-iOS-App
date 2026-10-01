"""JR East Tokiwa 67/68/69/70 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "67": ("67M", "https://timetables.jreast.co.jp/2610/train/045/048391.html", [
        ("品川", None, "15:15", "９"), ("東京", "15:22", "15:23", "８"),
        ("上野", "15:28", "15:30", "８"), ("柏", "15:49", "15:50", None),
        ("土浦", "16:15", "16:15", None), ("石岡", "16:25", "16:25", None),
        ("友部", "16:36", "16:37", None), ("水戸", "16:46", "16:47", "４"),
        ("勝田", "16:52", None, None),
    ]),
    "68": ("68M", "https://timetables.jreast.co.jp/2610/train/050/050331.html", [
        ("勝田", None, "12:47", None), ("水戸", "12:52", "12:53", "７"),
        ("友部", "13:03", "13:03", None), ("石岡", "13:14", "13:15", None),
        ("土浦", "13:25", "13:26", None), ("柏", "13:47", "13:48", None),
        ("上野", "14:07", "14:09", "９"), ("東京", "14:14", "14:15", "９"),
        ("品川", "14:22", None, "９"),
    ]),
    "69": ("69M", "https://timetables.jreast.co.jp/2610/train/045/048401.html", [
        ("品川", None, "16:15", "９"), ("東京", "16:22", "16:23", "８"),
        ("上野", "16:28", "16:30", "８"), ("柏", "16:49", "16:49", None),
        ("土浦", "17:15", "17:15", None), ("石岡", "17:25", "17:25", None),
        ("友部", "17:36", "17:37", None), ("水戸", "17:46", "17:47", "４"),
        ("勝田", "17:52", None, None),
    ]),
    "70": ("70M", "https://timetables.jreast.co.jp/2610/train/075/076471.html", [
        ("勝田", None, "13:47", None), ("水戸", "13:52", "13:53", "７"),
        ("友部", "14:03", "14:03", None), ("石岡", "14:14", "14:15", None),
        ("土浦", "14:25", "14:26", None), ("柏", "14:47", "14:48", None),
        ("上野", "15:07", "15:09", "９"), ("東京", "15:14", "15:15", "９"),
        ("品川", "15:23", None, "９"),
    ]),
}


class EastTokiwa67And68And69And70Tests(unittest.TestCase):
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
