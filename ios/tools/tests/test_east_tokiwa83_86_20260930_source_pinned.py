"""JR East Tokiwa 83/84/85/86 exact-day pages retain printed facts."""

import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
PAGES = {
    "83": ("83M", "https://timetables.jreast.co.jp/2610/train/075/076381.html", [
        ("品川", None, "22:15", "９"), ("東京", "22:22", "22:23", "８"),
        ("上野", "22:28", "22:30", "８"), ("柏", "22:50", "22:51", None),
        ("龍ケ崎市", "23:02", "23:02", None), ("牛久", "23:06", "23:07", None),
        ("ひたち野うしく", "23:10", "23:10", None), ("荒川沖", "23:13", "23:13", None),
        ("土浦", "23:18", None, None),
    ]),
    "84": ("84M", "https://timetables.jreast.co.jp/2610/train/050/050351.html", [
        ("勝田", None, "20:47", None), ("水戸", "20:52", "20:53", "７"),
        ("友部", "21:03", "21:03", None), ("石岡", "21:14", "21:14", None),
        ("土浦", "21:24", "21:24", None), ("柏", "21:45", "21:46", None),
        ("上野", "22:06", "22:08", "９"), ("東京", "22:12", "22:14", "９"),
        ("品川", "22:22", None, "９"),
    ]),
    "85": ("85M", "https://timetables.jreast.co.jp/2610/train/050/050291.html", [
        ("品川", None, "22:45", "９"), ("東京", "22:52", "22:53", "８"),
        ("上野", "22:58", "23:00", "８"), ("柏", "23:20", "23:20", None),
        ("龍ケ崎市", "23:32", "23:32", None), ("牛久", "23:36", "23:36", None),
        ("ひたち野うしく", "23:39", "23:40", None), ("荒川沖", "23:42", "23:43", None),
        ("土浦", "23:47", "23:48", None), ("石岡", "23:58", "23:58", None),
        ("友部", "24:09", "24:09", None), ("水戸", "24:19", "24:20", "４"),
        ("勝田", "24:26", None, None),
    ]),
    "86": ("86M", "https://timetables.jreast.co.jp/2610/train/050/050361.html", [
        ("勝田", None, "21:47", None), ("水戸", "21:52", "21:53", "７"),
        ("友部", "22:03", "22:03", None), ("石岡", "22:14", "22:14", None),
        ("土浦", "22:24", "22:24", None), ("柏", "22:45", "22:46", None),
        ("上野", "23:07", "23:09", "９"), ("東京", "23:14", "23:15", "９"),
        ("品川", "23:23", None, "１０"),
    ]),
}


class EastTokiwa83And84And85And86Tests(unittest.TestCase):
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
        candidates = {
            trip["public_number"]: trip for trip in json.loads(
                (BASE / "candidates/jr-east-tokiwa83-86-20260930.json").read_text(encoding="utf-8")
            )["trips"]
        }

        def local_clock(clock):
            if clock is None:
                return None
            hour, minute = map(int, clock.split(":"))
            return f"{hour % 24:02d}:{minute:02d}"

        for number, (train_number, url, printed) in PAGES.items():
            trip_id = f"jr-east.tokiwa.{number}.exact-2026-09-30"
            with self.subTest(trip=trip_id):
                actual = day[trip_id]
                self.assertEqual((actual["train_number"], actual["public_number"]), (train_number, number))
                self.assertEqual(sources[f"jr-east-tokiwa{number}-20260930"]["url_or_locator"], url)
                self.assertEqual(
                    [(name, arrival, departure, candidates[number]["printed_platforms"].get(name))
                     for name, arrival, departure in candidates[number]["stops"]], printed,
                )
                self.assertEqual(
                    [(self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"],
                      stop["platform"], stop["day_offset"])
                     for stop in actual["stop_times"]],
                    [(name, local_clock(arrival), local_clock(departure), platform,
                      int((arrival or departure).split(":")[0]) // 24)
                     for name, arrival, departure, platform in printed],
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
