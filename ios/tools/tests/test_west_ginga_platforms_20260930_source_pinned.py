"""Five printed platform cells apply to Ginga 8078M on September 30 only."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-west-ginga-platforms-20260930"
TRIP = "jr-west.west-express-ginga.kumano-day.2026-07-05"
DAY = "2026-09-30"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class GingaPlatformTests(unittest.TestCase):
    def test_dated_platforms_and_provenance(self):
        candidate = json.loads((BASE / "candidates/jr-west-ginga-8078m-platforms-20260930.json")
                               .read_text(encoding="utf-8"))
        overrides = rows(BASE / f"normalized/trip-stop-time-overrides/{SUFFIX}/seeds.jsonl")
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        expected = {r["stop_sequence"]: r["platform"] for r in candidate["platforms"]}
        self.assertEqual(expected, {11: "1", 13: "18", 14: "24", 15: "1", 16: "31"})
        self.assertEqual(len(overrides), len(facts))
        self.assertEqual({r["stop_sequence"]: r["platform_override"] for r in overrides}, expected)
        self.assertTrue(all(r["trip_id"] == TRIP and r["service_date"] == DAY
                            and r["platform_override_present"] == 1
                            and "arrival_override" not in r and "departure_override" not in r
                            for r in overrides))
        source = next(r for path in (BASE / "sources").glob("source-registry*.jsonl")
                      for r in rows(path) if r["source_id"] == candidate["source_id"])
        self.assertEqual(source["url_or_locator"], candidate["source_url"])
        self.assertEqual({f["entity_id"] for f in facts}, {f"{TRIP}:{n}" for n in expected})

    def test_materialization_is_date_scoped(self):
        sys.path.insert(0, str(ROOT / "ios/tools"))
        import train_timetable as timetable
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        selected = next(t for t in timetable.materialize(data, DAY) if t["trip_id"] == TRIP)
        previous = next(t for t in timetable.materialize(data, "2026-09-27") if t["trip_id"] == TRIP)
        expected = {11: "1", 13: "18", 14: "24", 15: "1", 16: "31"}
        self.assertEqual({s["stop_sequence"]: s.get("platform") for s in selected["stop_times"]
                          if s["stop_sequence"] in expected}, expected)
        self.assertTrue(all(s.get("platform") is None for s in previous["stop_times"]
                            if s["stop_sequence"] in expected))


if __name__ == "__main__":
    unittest.main()
