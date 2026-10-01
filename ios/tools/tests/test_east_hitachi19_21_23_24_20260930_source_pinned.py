"""JR East Hitachi 19/21/23/24 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "19": ("19M", "https://timetables.jreast.co.jp/2610/train/095/098681.html", [
        ("品川", None, "15:45", "９"), ("東京", "15:52", "15:53", "７"),
        ("上野", "15:58", "16:00", "８"), ("水戸", "17:05", "17:06", "４"),
        ("勝田", "17:11", "17:12", None), ("大甕", "17:21", "17:21", None),
        ("常陸多賀", "17:25", "17:25", None), ("日立", "17:29", "17:30", None),
        ("磯原", "17:45", "17:45", None), ("泉", "18:00", "18:00", None),
        ("湯本", "18:05", "18:05", None), ("いわき", "18:11", None, None),
    ]),
    "21": ("21M", "https://timetables.jreast.co.jp/2610/train/095/098691.html", [
        ("品川", None, "16:45", "９"), ("東京", "16:52", "16:53", "７"),
        ("上野", "16:58", "17:00", "８"), ("水戸", "18:07", "18:08", "４"),
        ("勝田", "18:12", "18:13", None), ("大甕", "18:22", "18:23", None),
        ("常陸多賀", "18:26", "18:27", None), ("日立", "18:30", "18:31", None),
        ("高萩", "18:41", "18:41", None), ("勿来", "18:54", "18:55", None),
        ("泉", "19:03", "19:04", None), ("湯本", "19:08", "19:09", None),
        ("いわき", "19:15", "19:17", None), ("広野", "19:35", "19:35", None),
        ("富岡", "19:53", "19:53", None), ("大野", "20:01", "20:01", None),
        ("双葉", "20:06", "20:06", None), ("浪江", "20:10", "20:11", None),
        ("原ノ町", "20:26", "20:27", None), ("相馬", "20:42", "20:42", None),
        ("亘理", "21:06", "21:07", None), ("岩沼", "21:17", "21:17", None),
        ("仙台", "21:32", None, "１"),
    ]),
    "23": ("23M", "https://timetables.jreast.co.jp/2610/train/045/048411.html", [
        ("品川", None, "17:45", "９"), ("東京", "17:52", "17:53", "７"),
        ("上野", "17:58", "18:00", "８"), ("土浦", "18:40", "18:40", None),
        ("水戸", "19:09", "19:11", "４"), ("勝田", "19:15", "19:16", None),
        ("大甕", "19:25", "19:26", None), ("常陸多賀", "19:29", "19:30", None),
        ("日立", "19:33", "19:34", None), ("磯原", "19:49", "19:49", None),
        ("泉", "20:04", "20:04", None), ("湯本", "20:09", "20:09", None),
        ("いわき", "20:15", None, None),
    ]),
    "24": ("24M", "https://timetables.jreast.co.jp/2610/train/045/048611.html", [
        ("いわき", None, "17:21", None), ("湯本", "17:26", "17:27", None),
        ("泉", "17:31", "17:32", None), ("磯原", "17:47", "17:47", None),
        ("日立", "18:03", "18:03", None), ("勝田", "18:20", "18:21", None),
        ("水戸", "18:26", "18:27", "７"), ("上野", "19:36", "19:38", "９"),
        ("東京", "19:42", "19:44", "９"), ("品川", "19:51", None, "９"),
    ]),
}


class EastHitachi19And21And23And24Tests(unittest.TestCase):
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
