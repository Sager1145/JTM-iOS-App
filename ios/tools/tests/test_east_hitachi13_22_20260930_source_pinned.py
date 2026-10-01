"""Two JR East Hitachi columns are confined to their reviewed service day."""

import json
from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-east-hitachi13-22-20260930.json"
EXPECTED_PLATFORMS = {
    "13": {"品川": "９", "東京": "７", "上野": "８", "水戸": "４", "仙台": "６"},
    "22": {"仙台": "６", "水戸": "７", "上野": "９", "東京": "９", "品川": "９"},
}
EXPECTED_EQUIPMENT = ["座席未指定券", "グリーン車指定席", "普通車全車指定席"]


class EastHitachi13And22Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reviewed = json.loads(CANDIDATE.read_text(encoding="utf-8"))["trips"]
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_selected_date_has_exact_printed_stops_and_train_numbers(self):
        day = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        for reviewed in self.reviewed:
            with self.subTest(trip=reviewed["trip_id"]):
                actual = day[reviewed["trip_id"]]
                self.assertEqual(actual["train_number"], reviewed["train_number"])
                self.assertEqual(sources[reviewed["source_id"]]["url_or_locator"], reviewed["source_url"])
                self.assertEqual(
                    [[self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"]]
                     for stop in actual["stop_times"]], reviewed["stops"]
                )

    def test_exact_day_scope_and_unresolved_route(self):
        ids = {trip["trip_id"] for trip in self.reviewed}
        for other in ("2026-09-29", "2026-10-01"):
            self.assertFalse(ids & {trip["trip_id"] for trip in timetable.materialize(self.data, other)})
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] in ids for row in self.data["trip_operator_segments"]))
        for row in self.data["fact_completeness"]:
            if row["entity_id"] in ids and row["dimension"] in ("route_lines", "operator"):
                self.assertEqual(row["status"], "unknown")

    def test_printed_platforms_and_equipment_are_scoped_to_each_train(self):
        day = {trip["trip_id"]: trip for trip in timetable.materialize(self.data, "2026-09-30")}
        formations = {row["trip_id"]: row for row in self.data["trip_formations"]
                      if row["trip_id"] in day and row["service_date"] == "2026-09-30"}
        for reviewed in self.reviewed:
            with self.subTest(trip=reviewed["trip_id"]):
                number = reviewed["public_number"]
                self.assertEqual(reviewed["printed_platforms"], EXPECTED_PLATFORMS[number])
                self.assertEqual(reviewed["printed_equipment"], EXPECTED_EQUIPMENT)
                self.assertEqual(
                    {self.names[stop["station_id"]]: stop["platform"]
                     for stop in day[reviewed["trip_id"]]["stop_times"] if stop["platform"] is not None},
                    EXPECTED_PLATFORMS[number],
                )
                formation = formations[reviewed["trip_id"]]
                self.assertEqual(formation["source_id"], reviewed["source_id"])
                self.assertEqual(formation["evidence_kind"], "planned")
                self.assertIs(formation["all_reserved"], True)
                self.assertIs(formation["green_car_available"], True)
                for unverified in ("car_count", "vehicle_series", "formation_label", "reserved_seat_capacity"):
                    self.assertIsNone(formation.get(unverified))
                self.assertFalse(any(row["formation_id"] == formation["formation_id"]
                                     for row in self.data["trip_formation_cars"]))


if __name__ == "__main__":
    unittest.main()
