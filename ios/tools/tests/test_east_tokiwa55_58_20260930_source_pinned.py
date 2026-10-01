"""JR East Tokiwa 55/56/57/58 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "55": ("55M", "https://timetables.jreast.co.jp/2610/train/075/076291.html", [
        ("品川", None, "09:15", "９"), ("東京", "09:23", "09:24", "７"),
        ("上野", "09:29", "09:30", "８"), ("柏", "09:50", "09:51", None),
        ("土浦", "10:14", "10:15", None), ("石岡", "10:25", "10:26", None),
        ("友部", "10:37", "10:37", None), ("水戸", "10:47", "10:48", "４"),
        ("勝田", "10:53", None, None),
    ]),
    "56": ("56M", "https://timetables.jreast.co.jp/2610/train/075/076421.html", [
        ("高萩", None, "05:48", None), ("日立", "05:58", "05:58", None),
        ("常陸多賀", "06:02", "06:03", None), ("大甕", "06:06", "06:07", None),
        ("東海", "06:11", "06:12", None), ("勝田", "06:18", "06:19", None),
        ("水戸", "06:24", "06:25", "７"), ("赤塚", "06:30", "06:30", None),
        ("友部", "06:37", "06:38", None), ("石岡", "06:48", "06:49", None),
        ("土浦", "06:59", "06:59", None), ("牛久", "07:07", "07:08", None),
        ("龍ケ崎市", "07:12", "07:12", None), ("柏", "07:29", "07:30", None),
        ("上野", "08:01", "08:03", "９"), ("東京", "08:09", "08:11", "９"),
        ("品川", "08:19", None, "９"),
    ]),
    "57": ("57M", "https://timetables.jreast.co.jp/2610/train/045/048311.html", [
        ("品川", None, "10:14", "９"), ("東京", "10:22", "10:23", "８"),
        ("上野", "10:28", "10:30", "８"), ("柏", "10:50", "10:51", None),
        ("土浦", "11:15", "11:16", None), ("石岡", "11:26", "11:27", None),
        ("友部", "11:37", "11:38", None), ("水戸", "11:48", "11:49", "４"),
        ("勝田", "11:53", None, None),
    ]),
    "58": ("58M", "https://timetables.jreast.co.jp/2610/train/050/050301.html", [
        ("高萩", None, "06:56", None), ("日立", "07:06", "07:07", None),
        ("常陸多賀", "07:10", "07:11", None), ("大甕", "07:14", "07:15", None),
        ("東海", "07:20", "07:20", None), ("勝田", "07:26", "07:27", None),
        ("水戸", "07:32", "07:33", "７"), ("赤塚", "07:38", "07:38", None),
        ("友部", "07:45", "07:45", None), ("石岡", "07:56", "07:56", None),
        ("土浦", "08:05", "08:06", None), ("牛久", "08:15", "08:15", None),
        ("龍ケ崎市", "08:19", "08:20", None), ("柏", "08:37", "08:38", None),
        ("上野", "09:05", "09:07", "９"), ("東京", "09:12", "09:13", "９"),
        ("品川", "09:21", None, "９"),
    ]),
}


class EastTokiwa55And56And57And58Tests(unittest.TestCase):
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
