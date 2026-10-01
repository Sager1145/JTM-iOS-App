"""Source-pinned checks for the dated Sonic/Uwakai eight-train batch."""

import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-sonic11-17-uwakai10-16-20260930"
SCRIPT = ROOT / "ios/tools/normalize-reviewed-sonic11-17-uwakai10-16-20260930.py"


def read_rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class SonicUwakaiSecondDatedBatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("dated_eight", SCRIPT)
        cls.normalizer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.normalizer)
        cls.inventory = json.loads((BASE / "sources/candidates/sonic-uwakai-closed-inventory-20260930.json")
                                   .read_text(encoding="utf-8"))

    def test_closed_inventory_and_short_turns(self):
        sonic = self.inventory["services"]["sonic"]
        uwakai = self.inventory["services"]["uwakai"]
        self.assertEqual((len(sonic), len(uwakai)), (64, 32))
        self.assertEqual({int(r["public_number"]) for r in sonic}, set(range(1, 61)) | {101, 102, 201, 202})
        self.assertEqual({int(r["public_number"]) for r in uwakai}, set(range(1, 33)))
        self.assertEqual({int(r["public_number"]) for r in sonic if r["category"] != "regular"},
                         {12, 41, 101, 102, 201, 202})
        self.assertEqual({(r["origin"], r["destination"]) for r in uwakai if int(r["public_number"]) % 2},
                         {("松山", "宇和島")})
        self.assertEqual({(r["origin"], r["destination"]) for r in uwakai if int(r["public_number"]) % 2 == 0},
                         {("宇和島", "松山")})
        self.assertTrue(all("20260930" in r["detail_url"] for r in sonic + uwakai))

    def test_candidates_match_source_pins_and_normalized_calls(self):
        trips = {r["trip_id"]: r for r in read_rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = read_rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        self.assertEqual((len(trips), len(stops)), (8, 79))
        for (service, number), pin in self.normalizer.PINS.items():
            operator = "jr-kyushu" if service == "sonic" else "jr-shikoku"
            trip_id = f"{operator}.{service}.{number}.2026-09-30"
            candidate = json.loads((BASE / f"candidates/{operator}-{service}{number}-20260930.json")
                                   .read_text(encoding="utf-8"))
            detail = next(r for r in self.inventory["services"][service]
                          if r["public_number"] == str(number))
            self.assertEqual(self.normalizer.stop_pin(candidate["trip"]["stop_times"]), pin)
            self.assertEqual((candidate["trip"]["train_number"], trips[trip_id]["train_number"]),
                             (detail["train_number"], detail["train_number"]))
            self.assertEqual(candidate["trip"]["operating_note"], "毎日運転")
            source = (candidate["new_source"] if service == "sonic" else candidate["sources"][0])
            self.assertEqual(source["url_or_locator"], detail["detail_url"])
            self.assertIs(source["automated_extraction_allowed"], False)
            actual = sorted((r for r in stops if r["trip_id"] == trip_id), key=lambda r: r["stop_sequence"])
            self.assertEqual([(r["arrival_time"], r["departure_time"], r["platform"]) for r in actual],
                             [(r["arrival_time"], r["departure_time"], r["platform"])
                              for r in candidate["trip"]["stop_times"]])

    def test_equipment_scope_and_exact_date(self):
        formations = read_rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(formations), 8)
        self.assertTrue(all(f["all_reserved"] is False and f["evidence_kind"] == "planned"
                            for f in formations))
        sonic = [f for f in formations if ".sonic." in f["trip_id"]]
        uwakai = [f for f in formations if ".uwakai." in f["trip_id"]]
        self.assertTrue(all(f["green_car_available"] is True for f in sonic))
        self.assertTrue(all("green_car_available" not in f for f in uwakai))
        series = {int(f["trip_id"].split(".")[2]): (f.get("vehicle_series"), f.get("car_count"))
                  for f in sonic}
        self.assertEqual(series, {11: ("885", 6), 13: (None, None),
                                  15: ("885", 6), 17: (None, None)})
        cars = read_rows(BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(cars), 12)
        self.assertEqual({r["car_number"] for r in cars if r["car_number"] in ("3", "4")}, {"3", "4"})
        self.assertTrue(all("reservation_type" not in r for r in cars if r["car_number"] in ("3", "4")))
        self.assertTrue(all("seat_class" not in r for r in cars if r["car_number"] == "1"))
        self.assertTrue(all(r.get("reservation_type") == "reserved" for r in cars if r["car_number"] == "2"))
        self.assertTrue(all(r.get("reservation_type") == "non_reserved" for r in cars
                            if int(r["car_number"]) >= 5))
        self.assertIn("アンパンマン列車", next(f for f in uwakai if ".uwakai.16." in f["trip_id"])["notes"])
        exceptions = read_rows(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        self.assertEqual({r["service_date"] for r in exceptions}, {"2026-09-30"})
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
