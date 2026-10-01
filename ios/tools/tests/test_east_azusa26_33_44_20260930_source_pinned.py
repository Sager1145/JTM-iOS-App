"""JR East Azusa exact-day pages retain the selected source facts."""

import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-east-azusa26-33-44-20260930.json"
EXPECTED = {
    "26": ("26M", 10, "松本", "12:10", "新宿", "14:43", "立川", "14:20", "14:21", "３"),
    "33": ("33M", 11, "新宿", "15:00", "松本", "17:37", "韮崎", "16:36", "16:36", None),
    "44": ("44M", 17, "松本", "15:50", "新宿", "18:48", "大月", "17:42", "17:45", "５"),
}


class EastAzusa263344SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))

    def test_exact_date_printed_identity_stops_and_platforms(self):
        day = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        self.assertEqual(self.candidate["candidate_status"], "reviewed_official_html")
        self.assertFalse(self.candidate["canonical"])
        for candidate in self.candidate["trips"]:
            number = candidate["public_number"]
            internal, count, first, departure, last, arrival, middle, mid_arr, mid_dep, platform = EXPECTED[number]
            with self.subTest(number=number):
                actual = day[candidate["trip_id"]]
                self.assertEqual((actual["train_number"], actual["public_number"]), (internal, number))
                self.assertEqual(sources[candidate["source_id"]]["url_or_locator"], candidate["source_url"])
                printed = [(self.names[s["station_id"]], s["arrival_time"], s["departure_time"], s["platform"])
                           for s in actual["stop_times"]]
                self.assertEqual(len(printed), count)
                self.assertEqual(printed[0][:3], (first, None, departure))
                self.assertEqual(printed[-1][:3], (last, arrival, None))
                self.assertIn((middle, mid_arr, mid_dep, platform), printed)
                self.assertEqual(printed, [(name, arr, dep, candidate["printed_platforms"].get(name))
                                           for name, arr, dep in candidate["stops"]])

    def test_scope_and_evidence_limits(self):
        ids = {f"jr-east.azusa.{number}.exact-2026-09-30" for number in EXPECTED}
        for other in ("2026-09-29", "2026-10-01"):
            self.assertFalse(ids & {trip["trip_id"] for trip in timetable.materialize(self.data, other)})
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_operator_segments"]))
        formations = {row["trip_id"]: row for row in self.data["trip_formations"] if row["trip_id"] in ids}
        self.assertEqual(set(formations), ids)
        for formation in formations.values():
            self.assertEqual((formation["evidence_kind"], formation["all_reserved"],
                              formation["green_car_available"]), ("planned", True, True))
            for field in ("car_count", "vehicle_series", "formation_label", "reserved_seat_capacity"):
                self.assertIsNone(formation.get(field))

    def test_printed_coupling_is_source_scoped(self):
        trip_id = "jr-east.azusa.44.exact-2026-09-30"
        candidate = next(t for t in self.candidate["trips"] if t["public_number"] == "44")
        self.assertEqual(candidate["printed_coupling"], "大月－新宿は2144Mを併結")
        normalized = next(t for t in self.data["trips"] if t["trip_id"] == trip_id)
        self.assertIn(candidate["printed_coupling"], normalized["notes"])
        self.assertFalse(any(row["trip_id"] == trip_id for row in self.data["trip_line_segments"]))


if __name__ == "__main__":
    unittest.main()
