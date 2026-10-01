"""JR East Tokiwa 71/72/73/74 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "71": ("71M", "https://timetables.jreast.co.jp/2610/train/050/050271.html", [
        ("品川", None, "17:15", "９"), ("東京", "17:22", "17:23", "８"),
        ("上野", "17:28", "17:30", "８"), ("柏", "17:50", "17:51", None),
        ("龍ケ崎市", "18:03", "18:03", None), ("牛久", "18:07", "18:08", None),
        ("土浦", "18:16", "18:16", None), ("石岡", "18:26", "18:27", None),
        ("友部", "18:38", "18:39", None), ("水戸", "18:50", "18:51", "４"),
        ("勝田", "18:56", None, None),
    ]),
    "72": ("72M", "https://timetables.jreast.co.jp/2610/train/050/050341.html", [
        ("勝田", None, "14:47", None), ("水戸", "14:52", "14:53", "７"),
        ("友部", "15:03", "15:04", None), ("石岡", "15:15", "15:15", None),
        ("土浦", "15:25", "15:26", None), ("柏", "15:47", "15:47", None),
        ("上野", "16:07", "16:09", "９"), ("東京", "16:14", "16:15", "９"),
        ("品川", "16:23", None, "９"),
    ]),
    "73": ("73M", "https://timetables.jreast.co.jp/2610/train/075/076322.html", [
        ("品川", None, "18:15", "９"), ("東京", "18:22", "18:23", "８"),
        ("上野", "18:29", "18:30", "８"), ("柏", "18:51", "18:51", None),
        ("龍ケ崎市", "19:02", "19:03", None), ("牛久", "19:07", "19:07", None),
        ("土浦", "19:15", "19:16", None), ("石岡", "19:25", "19:26", None),
        ("友部", "19:37", "19:37", None), ("水戸", "19:47", "19:48", "４"),
        ("勝田", "19:52", "19:53", None), ("東海", "19:58", "19:59", None),
        ("大甕", "20:04", "20:04", None), ("常陸多賀", "20:08", "20:08", None),
        ("日立", "20:12", "20:12", None), ("高萩", "20:23", None, None),
    ]),
    "74": ("74M", "https://timetables.jreast.co.jp/2610/train/045/048521.html", [
        ("勝田", None, "15:47", None), ("水戸", "15:52", "15:53", "７"),
        ("友部", "16:03", "16:03", None), ("石岡", "16:14", "16:15", None),
        ("土浦", "16:24", "16:25", None), ("柏", "16:46", "16:46", None),
        ("上野", "17:07", "17:08", "９"), ("東京", "17:13", "17:14", "１０"),
        ("品川", "17:22", None, "９"),
    ]),
}


class EastTokiwa71And72And73And74Tests(unittest.TestCase):
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
