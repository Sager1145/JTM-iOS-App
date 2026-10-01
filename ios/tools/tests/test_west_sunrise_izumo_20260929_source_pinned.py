"""Verify the September 29 Sunrise Izumo stop table and coupling evidence."""

import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable

SCRIPT = ROOT / "ios/tools/normalize-reviewed-west-sunrise-izumo-20260929.py"
spec = importlib.util.spec_from_file_location("sunrise_izumo_normalizer", SCRIPT)
normalizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(normalizer)


class SunriseIzumoSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / "candidates/jr-west-sunrise-izumo-20260929.json").read_text())
        cls.manifest = timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.data, cls.origins = timetable.load_dataset(timetable.DEFAULT_CANONICAL, cls.manifest)

    def test_candidate_and_official_shared_source_are_pinned(self):
        normalizer.validate(self.candidate)
        self.assertEqual(self.candidate["source_url"], normalizer.URL)
        self.assertEqual(self.candidate["source_sha256"], normalizer.HASH)
        self.assertEqual(len(self.candidate["trip"]["stop_times"]), 17)
        self.assertEqual(self.candidate["trip"]["stop_times"][8]["departure_time"], "06:34")
        self.assertIsNone(self.candidate["trip"]["stop_times"][-1]["departure_time"])

    def test_calendar_overnight_number_change_and_coupling(self):
        self.assertEqual(timetable.validate_dataset(self.data,self.origins,self.manifest),[])
        self.assertFalse([t for t in timetable.materialize(self.data,"2026-09-30")
                          if t["trip_id"]==normalizer.TRIP])
        trips=[t for t in timetable.materialize(self.data,"2026-09-29")
               if t["trip_id"]==normalizer.TRIP]
        self.assertEqual(len(trips),1)
        self.assertEqual(len(trips[0]["stop_times"]),17)
        self.assertEqual([s["day_offset"] for s in trips[0]["stop_times"]],
                         [0]*6+[1]*11)
        segments=[r for r in self.data["trip_number_segments"] if r["trip_id"]==normalizer.TRIP]
        self.assertEqual([(r["from_sequence"],r["to_sequence"],r["train_number"])
                          for r in segments],[(1,9,"5031M"),(9,17,"4031M")])
        relations=[r for r in self.data["trip_relations"]
                   if {r["trip_id"],r["related_trip_id"]}=={normalizer.TRIP,normalizer.SETO}]
        self.assertEqual(len(relations),2)
        self.assertTrue(all(r["relation_type"]=="couples_with" and
                            (r["from_sequence"],r["to_sequence"])==(1,9)
                            for r in relations))
        facts={r["dimension"]:r["status"] for r in self.data["fact_completeness"]
               if r["entity_id"]==normalizer.TRIP}
        self.assertEqual(facts["route_lines"],"unknown")
        self.assertEqual(facts["operator"],"unknown")


if __name__ == "__main__":
    unittest.main()
