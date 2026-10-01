"""Source-pinned checks for six dated Sonic train details."""

import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-sonic46-56-20260930"
SCRIPT = ROOT / "ios/tools/normalize-reviewed-sonic46-56-20260930.py"


def read_rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class Sonic46To56DatedBatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("sonic_eight", SCRIPT)
        cls.normalizer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.normalizer)
        cls.inventory = json.loads((BASE / "sources/candidates/sonic-uwakai-closed-inventory-20260930.json")
                                   .read_text(encoding="utf-8"))["services"]["sonic"]

    def test_source_pins_and_passenger_calls(self):
        trips = {r["trip_id"]: r for r in read_rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
        stops = read_rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        self.assertEqual((len(trips), len(stops)), (6, 78))
        for (service, number), pin in self.normalizer.PINS.items():
            self.assertEqual(service, "sonic")
            trip_id = f"jr-kyushu.sonic.{number}.2026-09-30"
            candidate = json.loads((BASE / f"candidates/jr-kyushu-sonic{number}-20260930.json")
                                   .read_text(encoding="utf-8"))
            inventory = next(r for r in self.inventory if r["public_number"] == str(number))
            self.assertEqual(self.normalizer.stop_pin(candidate["trip"]["stop_times"]), pin)
            self.assertEqual(candidate["trip"]["train_number"], inventory["train_number"])
            self.assertEqual(trips[trip_id]["train_number"], inventory["train_number"])
            self.assertEqual(candidate["trip"]["operating_note"], "毎日運転")
            self.assertEqual(candidate["trip"]["direction"],
                             f'{inventory["origin"]}→{inventory["destination"]}')
            self.assertEqual(candidate["new_source"]["url_or_locator"], inventory["detail_url"])
            self.assertIs(candidate["new_source"]["automated_extraction_allowed"], False)
            actual = sorted((r for r in stops if r["trip_id"] == trip_id), key=lambda r: r["stop_sequence"])
            self.assertEqual([(r["arrival_time"], r["departure_time"], r["platform"]) for r in actual],
                             [(r["arrival_time"], r["departure_time"], r["platform"])
                              for r in candidate["trip"]["stop_times"]])

    def test_planned_series_and_unknown_actual_consists(self):
        formations = read_rows(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(formations), 6)
        self.assertTrue(all(f["evidence_kind"] == "planned" and f["all_reserved"] is False and
                            f["green_car_available"] is True for f in formations))
        series = {int(f["trip_id"].split(".")[2]): (f.get("vehicle_series"), f.get("car_count"))
                  for f in formations}
        self.assertEqual(series, {46: (None, None), 48: ("883", 7), 50: ("885", 6),
                                  52: ("883", 7), 54: ("885", 6), 56: ("885", 6)})
        cars = read_rows(BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(cars), 32)
        self.assertTrue(all("seat_class" not in r for r in cars if r["car_number"] == "1"))
        self.assertTrue(all("reservation_type" not in r for r in cars if r["car_number"] in ("3", "4")))
        self.assertTrue(all(r.get("reservation_type") == "reserved" for r in cars if r["car_number"] == "2"))
        self.assertTrue(all(r.get("reservation_type") == "non_reserved" for r in cars
                            if int(r["car_number"]) >= 5))

    def test_unknown_series_and_exact_date(self):
        candidate = json.loads((BASE / "candidates/jr-kyushu-sonic46-20260930.json")
                               .read_text())
        self.assertNotIn("formation_evidence", candidate)
        for number in (50, 54, 56):
            candidate = json.loads((BASE / f"candidates/jr-kyushu-sonic{number}-20260930.json")
                                   .read_text())
            self.assertEqual(candidate["trip"]["seat_description_snapshot"][0],
                             "「白いソニック」で運転")
        stops = read_rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        self.assertEqual({r["day_offset"] for r in stops}, {0})
        exceptions = read_rows(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        self.assertEqual({r["service_date"] for r in exceptions}, {"2026-09-30"})
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
