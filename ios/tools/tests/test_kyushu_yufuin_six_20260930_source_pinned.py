"""Pinned JR Kyushu 2026-09-30 Yufuin-no-Mori train details."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-kyushu-yufuin-no-mori-six-20260930.json"
SUFFIX = "reviewed-kyushu-yufuin-six-20260930"


def read_rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def calls(rows):
    return [tuple(row) for row in rows]


class KyushuYufuinSixSeptember30Tests(unittest.TestCase):
    PAGE_PATHS = {
        "1": "00166501", "2": "00166801", "3": "00166601",
        "4": "00166901", "5": "00166701", "6": "00167001",
    }
    # Each tuple is the printed station, arrival, departure and platform on the
    # six train-specific JR Kyushu pages with September 30 selected.
    EXPECTED = {
        "1": [("博多",None,"09:17","6"),("鳥栖","09:42","09:43","6"),
              ("久留米","09:50","09:51","3"),("日田","10:36","10:37",None),
              ("天ケ瀬","10:49","10:49",None),("豊後森","11:04","11:04",None),
              ("由布院","11:31",None,None)],
        "2": [("由布院",None,"12:01",None),("豊後森","12:32","12:32",None),
              ("天ケ瀬","12:46","12:47",None),("日田","12:59","13:01",None),
              ("久留米","13:45","13:46","1"),("鳥栖","13:54","13:55","1"),
              ("博多","14:19",None,"6")],
        "3": [("博多",None,"10:11","6"),("鳥栖","10:36","10:37","5"),
              ("久留米","10:45","10:47","1"),("日田","11:31","11:33",None),
              ("天ケ瀬","11:45","11:45",None),("豊後森","12:00","12:00",None),
              ("由布院","12:27","12:32",None),("大分","13:18","13:20","7"),
              ("別府","13:31",None,None)],
        "4": [("別府",None,"14:36",None),("大分","14:48","14:58","8"),
              ("由布院","15:46","15:56",None),("豊後森","16:23","16:24",None),
              ("天ケ瀬","16:37","16:40",None),("日田","16:52","16:53",None),
              ("久留米","17:35","17:36","4"),("鳥栖","17:43","17:44","1"),
              ("博多","18:10",None,"5")],
        "5": [("博多",None,"14:38","6"),("鳥栖","15:03","15:04","6"),
              ("久留米","15:11","15:12","3"),("日田","15:53","15:56",None),
              ("天ケ瀬","16:08","16:09",None),("豊後森","16:23","16:24",None),
              ("由布院","16:50",None,None)],
        "6": [("由布院",None,"17:17",None),("豊後森","17:44","17:44",None),
              ("天ケ瀬","17:58","17:59",None),("日田","18:11","18:12",None),
              ("久留米","18:53","18:54","4"),("鳥栖","19:01","19:02","1"),
              ("博多","19:27",None,"3")],
    }

    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))

    def test_six_exact_date_pages_and_all_46_calls(self):
        self.assertEqual(sum(map(len, self.EXPECTED.values())), 46)
        pages = {page["public_number"]: page for page in self.candidate["train_pages"]}
        self.assertEqual(set(pages), set(self.EXPECTED))
        self.assertEqual(self.candidate["service_date"], "2026-09-30")
        for trip in self.candidate["trips"]:
            number = trip["public_number"]
            with self.subTest(number=number):
                self.assertEqual(calls(trip["stop_times"]), self.EXPECTED[number])
                self.assertEqual(trip["train_number"], f"800{number}D")
                self.assertEqual(trip["source_id"], pages[number]["source_id"])
                self.assertIn("d=20260930", pages[number]["url_or_locator"])
                self.assertIn(f"/2610/0016/{self.PAGE_PATHS[number]}.html",
                              pages[number]["url_or_locator"])

    def test_planned_formation_assignment_and_diagram_sources(self):
        sources = {source["source_id"]: source for source in self.candidate["formation_sources"]}
        self.assertEqual(set(sources), {
            "jr-kyushu-yufuin-20260930-calendar",
            "jr-kyushu-yufuin-formation-i",
            "jr-kyushu-yufuin-formation-iii",
        })
        self.assertEqual({trip["public_number"]: trip["formation_label"]
                          for trip in self.candidate["trips"]},
                         {"1":"III世","2":"III世","3":"I世","4":"I世",
                          "5":"III世","6":"III世"})
        self.assertIn("cal_202609.png", sources["jr-kyushu-yufuin-20260930-calendar"]["url_or_locator"])

    def test_normalized_exact_day_is_unique_and_cars_face_correct_way(self):
        trips_path = BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl"
        stops_path = BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"
        formations_path = BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl"
        cars_path = BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl"
        if not trips_path.exists():
            self.skipTest("New normalized rows are staged by the unified rebuild")
        trips = read_rows(trips_path)
        self.assertEqual(len(trips), 6)
        self.assertEqual({t["train_number"] for t in trips},
                         {f"800{number}D" for number in range(1, 7)})
        stops = read_rows(stops_path)
        self.assertEqual(len(stops), 46)
        formations = read_rows(formations_path)
        cars = read_rows(cars_path)
        self.assertEqual(len(formations), 6)
        self.assertEqual(len(cars), 28)
        for number in range(1, 7):
            trip_id = f"jr-kyushu.yufuin-no-mori.{number}.2026-09-30"
            fid = trip_id + ".formation.2026-09-30"
            formation = next(row for row in formations if row["formation_id"] == fid)
            expected_count = 4 if number in (3, 4) else 5
            self.assertEqual(formation["car_count"], expected_count)
            self.assertTrue(formation["all_reserved"])
            self.assertEqual(formation["evidence_kind"], "planned")
            ordered = [row["car_number"] for row in cars if row["formation_id"] == fid]
            self.assertEqual(ordered,
                             [str(x) for x in (range(expected_count, 0, -1) if number % 2
                                               else range(1, expected_count + 1))])
        root_exceptions = read_rows(BASE / "normalized/calendar-exceptions/reviewed-root/seeds.jsonl")
        self.assertFalse(any(row["service_date"] == "2026-09-30" and
                             row["calendar_id"].startswith("jr-kyushu.yufuin-no-mori.")
                             for row in root_exceptions))


if __name__ == "__main__":
    unittest.main()
