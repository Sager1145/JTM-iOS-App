"""Thirty-six September 30 Haruka trips carry only the supported nine-car plan."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka-planned-nine-car-20260930"
DAY = "2026-09-30"
EXPECTED = {f"jr-west.haruka.{number}.{DAY}" for number in range(1, 61)}


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class HarukaNineCarPlanTests(unittest.TestCase):
    def test_official_sources_and_planned_count_are_pinned(self):
        candidate = json.loads((BASE / f"candidates/jr-{SUFFIX}.json").read_text(encoding="utf-8"))
        sources = {row["source_id"]: row for row in rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")}
        self.assertEqual(set(candidate["trip_ids"]), EXPECTED)
        self.assertEqual((candidate["service_date"], candidate["planned_car_count"],
                          candidate["evidence_kind"]), (DAY, 9, "planned"))
        self.assertEqual(sources["jr-west-haruka-current-nine-car-guide-20260930"]["url_or_locator"],
                         "https://www.jr-odekake.net/railroad/train/haruka/")
        self.assertEqual(sources["jr-west-2024-haruka-all-nine-car-policy"]["url_or_locator"],
                         "https://www.westjr.co.jp/press/article/items/231215_00_press_daiyakaisei_kinto.pdf")
        self.assertEqual(sources["jr-west-2024-haruka-all-nine-car-policy"]["publication_date"],
                         "2023-12-15")
        self.assertTrue(all(source["redistribution_status"] == "verification_only"
                            for source in sources.values()))

    def test_all_reviewed_formations_and_provenance_without_speculative_cars(self):
        formations = [row for path in BASE.glob("normalized/trip-formations/**/*.jsonl")
                      for row in rows(path) if row["trip_id"] in EXPECTED]
        self.assertEqual({row["trip_id"] for row in formations}, EXPECTED)
        self.assertEqual(len(formations), 60)
        for formation in formations:
            with self.subTest(trip=formation["trip_id"]):
                self.assertEqual((formation["service_date"], formation["evidence_kind"],
                                  formation["car_count"]), (DAY, "planned", 9))
                self.assertNotIn("vehicle_series", formation)
                self.assertNotIn("reserved_seat_capacity", formation)
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        self.assertEqual(len(facts), 120)
        for tid in EXPECTED:
            self.assertEqual({f["source_id"] for f in facts if f["entity_id"] == tid},
                             {"jr-west-haruka-current-nine-car-guide-20260930",
                              "jr-west-2024-haruka-all-nine-car-policy"})
        self.assertFalse(any(row["formation_id"] in {f["formation_id"] for f in formations}
                             for path in BASE.glob("normalized/trip-formation-cars/**/*.jsonl")
                             for row in rows(path)))


if __name__ == "__main__":
    unittest.main()
