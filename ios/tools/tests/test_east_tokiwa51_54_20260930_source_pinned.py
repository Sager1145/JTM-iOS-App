"""JR East Tokiwa 51/52/53/54 exact-day pages retain printed facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "51": ("51M", "https://timetables.jreast.co.jp/2610/train/050/050241.html", [
        ("品川", None, "07:15", "９"), ("東京", "07:22", "07:23", "７"),
        ("上野", "07:28", "07:30", "８"), ("柏", "07:52", "07:52", None),
        ("土浦", "08:19", "08:20", None), ("石岡", "08:29", "08:30", None),
        ("友部", "08:40", "08:41", None), ("水戸", "08:51", "08:52", "４"),
        ("勝田", "08:56", "08:57", None), ("東海", "09:02", "09:03", None),
        ("大甕", "09:08", "09:08", None), ("常陸多賀", "09:12", "09:12", None),
        ("日立", "09:16", "09:16", None), ("高萩", "09:27", None, None),
    ]),
    "52": ("52M", "https://timetables.jreast.co.jp/2610/train/075/076391.html", [
        ("土浦", None, "06:05", None), ("荒川沖", "06:09", "06:10", None),
        ("ひたち野うしく", "06:12", "06:13", None), ("牛久", "06:16", "06:16", None),
        ("龍ケ崎市", "06:20", "06:21", None), ("柏", "06:36", "06:37", None),
        ("日暮里", "07:01", "07:02", None), ("上野", "07:06", "07:07", "９"),
        ("東京", "07:12", "07:13", "１０"), ("品川", "07:21", None, "９"),
    ]),
    "53": ("53M", "https://timetables.jreast.co.jp/2610/train/075/076271.html", [
        ("品川", None, "08:13", "９"), ("東京", "08:22", "08:23", "７"),
        ("上野", "08:29", "08:30", "８"), ("柏", "08:53", "08:53", None),
        ("土浦", "09:16", "09:17", None), ("石岡", "09:27", "09:28", None),
        ("友部", "09:39", "09:39", None), ("水戸", "09:49", "09:50", "４"),
        ("勝田", "09:55", None, None),
    ]),
    "54": ("54M", "https://timetables.jreast.co.jp/2610/train/075/076401.html", [
        ("勝田", None, "05:44", None), ("水戸", "05:49", "05:50", "７"),
        ("赤塚", "05:56", "05:56", None), ("友部", "06:03", "06:03", None),
        ("石岡", "06:14", "06:15", None), ("土浦", "06:24", "06:25", None),
        ("荒川沖", "06:30", "06:31", None), ("ひたち野うしく", "06:33", "06:34", None),
        ("牛久", "06:37", "06:38", None), ("龍ケ崎市", "06:42", "06:42", None),
        ("柏", "06:56", "06:57", None), ("日暮里", "07:23", "07:24", None),
        ("上野", "07:29", "07:31", "９"), ("東京", "07:37", "07:38", "９"),
        ("品川", "07:46", None, "９"),
    ]),
}


class EastTokiwa51And52And53And54Tests(unittest.TestCase):
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

    def test_nippori_is_a_printed_passenger_stop_for_52_and_54(self):
        for number, arrival, departure in (("52", "07:01", "07:02"), ("54", "07:23", "07:24")):
            trip_id = f"jr-east.tokiwa.{number}.exact-2026-09-30"
            rows = [row for row in self.data["stop_times"] if row["trip_id"] == trip_id
                    and self.names[row["station_id"]] == "日暮里"]
            with self.subTest(trip=trip_id):
                self.assertEqual(len(rows), 1)
                self.assertEqual((rows[0]["arrival_time"], rows[0]["departure_time"], rows[0]["call_type"]),
                                 (arrival, departure, "passenger_stop"))

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
