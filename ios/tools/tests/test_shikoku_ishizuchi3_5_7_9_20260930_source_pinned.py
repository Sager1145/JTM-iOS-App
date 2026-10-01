"""Source-pinned tests for exact-date Ishizuchi 3, 5, 7, and 9."""

import hashlib
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-shikoku-ishizuchi3-5-7-9-20260930"
CANDIDATE = BASE / "candidates/jr-shikoku-ishizuchi3-5-7-9-20260930.json"

EXPECTED = {
    "3": ("1003M", "3M", "33291", 14, "8", "bb1f6969fcbd7f73d88c0220f60449c68d49e804fd7ffaf887aad953babb1c2a"),
    "5": ("1005M", "5M", "292", 13, "7", "14925bc25ec8488267dab2146a301febb2fbe73230c71a285f44616e01ddcd29"),
    "7": ("1007M", "7M", "362", 13, "6", "dcc942e8df780d2855138ecb3f3719f422823db2d5279c65cdfe41ebf7d6bbbc"),
    "9": ("1009M", "9M", "125062", 13, "7", "eabe467e592d3a715183a053ad8cce5d6fcb266d1261aba99537bb5ed4518d7c"),
}


def jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def stops_hash(stops):
    payload = json.dumps(stops, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


class Ishizuchi3579ExactDateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.trips = {row["public_number"]: row for row in cls.candidate["trips"]}
        cls.normalized = {row["public_number"]: row for row in jsonl(
            BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        cls.stop_rows = jsonl(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")

    def test_exact_date_pages_and_running_date_evidence(self):
        self.assertEqual(set(self.trips), set(EXPECTED))
        sources = {row["source_id"]: row for row in jsonl(
            BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
        self.assertEqual(len(sources), 4)
        for public, (number, partner, page, count, platform, digest) in EXPECTED.items():
            trip = self.trips[public]
            url = f"https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930"
            self.assertEqual(trip["source_url"], url)
            self.assertEqual(sources[trip["source_id"]]["url_or_locator"], url)
            self.assertEqual(trip["calendar_observation"]["month"], "2026年9月")
            self.assertEqual(trip["calendar_observation"]["day"], 30)
            self.assertEqual(trip["calendar_observation"]["cell_class"], "ok")
            self.assertNotIn("３０", trip["calendar_observation"]["operation_text"])
            self.assertIs(sources[trip["source_id"]]["automated_extraction_allowed"], False)

    def test_source_pinned_stop_clocks_and_platforms(self):
        by_trip = {}
        for row in self.stop_rows:
            by_trip.setdefault(row["trip_id"], []).append(row)
        self.assertEqual(len(self.stop_rows), 53)
        for public, (number, partner, page, count, platform, digest) in EXPECTED.items():
            trip = self.trips[public]
            self.assertEqual(len(trip["stops"]), count)
            self.assertEqual(stops_hash(trip["stops"]), digest)
            self.assertEqual(trip["stops"][0]["platform"], platform)
            self.assertEqual(trip["stops"][-1]["platform"], "1")
            rows = sorted(by_trip[trip["trip_id"]], key=lambda row: row["stop_sequence"])
            self.assertEqual(
                [(row["arrival_time"], row["departure_time"], row["platform"]) for row in rows],
                [(row["arrival"], row["departure"], row["platform"]) for row in trip["stops"]],
            )
            self.assertTrue(all(row["clock_column"] for row in trip["stops"]))

    def test_train_identity_and_coupling_are_preserved_without_dangling_relations(self):
        for public, (number, partner, page, count, platform, digest) in EXPECTED.items():
            trip = self.trips[public]
            self.assertEqual(self.normalized[public]["train_number"], number)
            self.assertEqual(trip["coupling"]["partner_train_number"], partner)
            self.assertEqual(trip["coupling"]["printed_section"], "宇多津－松山")
            self.assertIsNone(trip["coupling"]["partner_trip_id"])
        facts = jsonl(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        coupling_facts = [row for row in facts if row["field_name"] == "coupling.partner_train_number"]
        self.assertEqual(len(coupling_facts), 4)
        self.assertFalse((BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl").exists())

    def test_only_printed_planned_seat_category_is_promoted(self):
        formations = jsonl(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(formations), 4)
        for formation in formations:
            self.assertEqual(formation["evidence_kind"], "planned")
            self.assertIs(formation["all_reserved"], False)
            for field in ("green_car_available", "car_count", "reserved_seat_capacity", "vehicle_series"):
                self.assertNotIn(field, formation)
        for trip in self.trips.values():
            self.assertIsNone(trip["formation"]["actual_dispatch"])

    def test_route_operator_and_actual_dispatch_remain_unresolved(self):
        completeness = jsonl(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")
        statuses = {(row["entity_id"], row["dimension"]): row["status"] for row in completeness}
        for trip in self.trips.values():
            trip_id = trip["trip_id"]
            self.assertEqual(statuses[(trip_id, "operator")], "unknown")
            self.assertEqual(statuses[(trip_id, "route_lines")], "unknown")
            self.assertEqual(statuses[(trip_id, "formation")], "partial")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
