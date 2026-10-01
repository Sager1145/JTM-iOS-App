"""Exact-date source checks for 2026-09-27 Yakumo 12."""

import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT / "app/data/train-service-history"
sys.path.insert(0,str(ROOT / "ios/tools"))
import train_timetable as timetable

spec=importlib.util.spec_from_file_location("yakumo12_normalizer",
         ROOT / "ios/tools/normalize-reviewed-west-yakumo12-20260927.py")
normalizer=importlib.util.module_from_spec(spec)
spec.loader.exec_module(normalizer)


class Yakumo12SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate=json.loads((BASE / "candidates/jr-west-yakumo12-20260927.json").read_text())
        cls.source=json.loads((BASE / "sources/source-registry-west-yakumo12-20260927.jsonl").read_text())
        cls.manifest=timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.data,cls.origins=timetable.load_dataset(timetable.DEFAULT_CANONICAL,cls.manifest)

    def test_selected_page_identity_and_passenger_table(self):
        normalizer.validate(self.candidate,self.source)
        self.assertEqual(self.source["url_or_locator"],normalizer.URL)
        self.assertEqual(self.source["effective_date"],"2026-09-27")
        self.assertFalse(self.source["automated_extraction_allowed"])
        actual=[(r["name_snapshot"],r["arrival_time"],r["departure_time"])
                for r in self.candidate["trip"]["stop_times"]]
        expected=[(n,a,d) for n,_,a,d,_,_ in normalizer.STOPS]
        self.assertEqual(actual,expected)
        self.assertEqual(len(actual),11)

    def test_exact_date_materialization_and_unknown_route(self):
        self.assertEqual(timetable.validate_dataset(self.data,self.origins,self.manifest),[])
        self.assertFalse([t for t in timetable.materialize(self.data,"2026-09-26")
                          if t["trip_id"]==normalizer.TRIP])
        trips=[t for t in timetable.materialize(self.data,"2026-09-27")
               if t["trip_id"]==normalizer.TRIP]
        self.assertEqual(len(trips),1)
        self.assertEqual(trips[0]["train_number"],"1012M")
        self.assertEqual(len(trips[0]["stop_times"]),11)
        self.assertIsNone(trips[0]["stop_times"][0]["arrival_time"])
        self.assertIsNone(trips[0]["stop_times"][-1]["departure_time"])
        facts={r["dimension"]:r["status"] for r in self.data["fact_completeness"]
               if r["entity_id"]==normalizer.TRIP}
        self.assertEqual(facts["operator"],"unknown")
        self.assertEqual(facts["route_lines"],"unknown")


if __name__=="__main__":
    unittest.main()
