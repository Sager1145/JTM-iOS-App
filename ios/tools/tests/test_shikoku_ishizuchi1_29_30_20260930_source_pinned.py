"""Source-pinned checks for exact-date JR Shikoku Ishizuchi staging."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-shikoku-ishizuchi1-29-30-20260930"
CANDIDATE = BASE / "candidates/jr-shikoku-ishizuchi1-29-30-20260930.json"


def jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class IshizuchiExactDateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.trips = {row["trip_id"]: row for row in cls.candidate["trips"]}
        cls.normalized_trips = {row["trip_id"]: row for row in jsonl(
            BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        cls.stops = jsonl(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")

    def test_exact_date_official_urls_and_td_ok(self):
        expected = {
            "jr-shikoku.ishizuchi.1.1001m.exact-2026-09-30": "18541",
            "jr-shikoku.ishizuchi.29.1029m.exact-2026-09-30": "99561",
            "jr-shikoku.ishizuchi.30.1030m.exact-2026-09-30": "28651",
        }
        self.assertEqual(set(self.trips), set(expected))
        for trip_id, page_id in expected.items():
            trip = self.trips[trip_id]
            self.assertEqual(
                trip["source_url"],
                f"https://timetable.jr-odekake.net/train-timetable/{page_id}?date=20260930",
            )
            self.assertEqual(
                trip["calendar_observation"],
                {"month": "2026年9月", "day": 30, "cell_class": "ok", "operation_text": "毎日運転"},
            )
        new_sources = jsonl(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        self.assertEqual({row["source_id"] for row in new_sources}, {
            "jr-odekake-ishizuchi29-20260930-train",
            "jr-odekake-ishizuchi30-20260930-train",
        })
        self.assertTrue(all(row["automated_extraction_allowed"] is False for row in new_sources))

    def test_all_printed_passenger_clocks_and_platforms_are_preserved(self):
        expected_counts = {
            "jr-shikoku.ishizuchi.1.1001m.exact-2026-09-30": 15,
            "jr-shikoku.ishizuchi.29.1029m.exact-2026-09-30": 12,
            "jr-shikoku.ishizuchi.30.1030m.exact-2026-09-30": 16,
        }
        by_trip = {trip_id: [] for trip_id in self.trips}
        for row in self.stops:
            if row["trip_id"] in by_trip:
                by_trip[row["trip_id"]].append(row)
        for trip_id, count in expected_counts.items():
            normalized = sorted(by_trip[trip_id], key=lambda row: row["stop_sequence"])
            reviewed = self.trips[trip_id]["stops"]
            self.assertEqual(len(normalized), count)
            self.assertEqual(
                [(row["arrival_time"], row["departure_time"], row["platform"]) for row in normalized],
                [(row["arrival"], row["departure"], row["platform"]) for row in reviewed],
            )
            self.assertTrue(all(row["clock_column"] for row in reviewed))
            self.assertEqual(normalized[0]["call_type"], "origin")
            self.assertEqual(normalized[-1]["call_type"], "destination")

    def test_train_numbers_and_coupling_sections(self):
        expected = {
            "jr-shikoku.ishizuchi.1.1001m.exact-2026-09-30": ("1001M", "1M", "宇多津－松山", [3, 15]),
            "jr-shikoku.ishizuchi.29.1029m.exact-2026-09-30": ("1029M", "29M", "多度津－伊予西条", [5, 12]),
            "jr-shikoku.ishizuchi.30.1030m.exact-2026-09-30": ("1030M", "30M", "松山－宇多津", [1, 14]),
        }
        for trip_id, (number, partner, section, sequence_range) in expected.items():
            reviewed = self.trips[trip_id]
            self.assertEqual(self.normalized_trips[trip_id]["train_number"], number)
            self.assertEqual(reviewed["coupling"]["partner_train_number"], partner)
            self.assertEqual(reviewed["coupling"]["printed_section"], section)
            self.assertEqual(reviewed["coupled_stop_range"], sequence_range)
        relations = jsonl(BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(relations), 2)
        self.assertEqual({(row["from_sequence"], row["to_sequence"]) for row in relations}, {(3, 15)})
        self.assertEqual({row["relation_type"] for row in relations}, {"couples_with"})

    def test_formation_is_planned_and_does_not_invent_cars_or_dispatch(self):
        formations = {row["trip_id"]: row for row in jsonl(
            BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")}
        self.assertEqual(set(formations), set(self.trips))
        for trip_id, formation in formations.items():
            self.assertEqual(formation["evidence_kind"], "planned")
            self.assertIs(formation["all_reserved"], False)
            for field in ("car_count", "reserved_seat_capacity", "vehicle_series"):
                self.assertNotIn(field, formation)
        self.assertIs(formations["jr-shikoku.ishizuchi.1.1001m.exact-2026-09-30"]["green_car_available"], True)
        self.assertNotIn("green_car_available", formations["jr-shikoku.ishizuchi.29.1029m.exact-2026-09-30"])
        self.assertNotIn("green_car_available", formations["jr-shikoku.ishizuchi.30.1030m.exact-2026-09-30"])

    def test_route_operator_and_actual_dispatch_remain_unknown(self):
        completeness = jsonl(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        statuses = {(row["entity_id"], row["dimension"]): row["status"] for row in completeness}
        for trip_id in self.trips:
            self.assertEqual(statuses[(trip_id, "operator")], "unknown")
            self.assertEqual(statuses[(trip_id, "route_lines")], "unknown")
            self.assertEqual(statuses[(trip_id, "formation")], "partial")
            self.assertIsNone(self.trips[trip_id]["formation"]["actual_dispatch"])
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
