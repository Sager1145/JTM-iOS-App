"""The official 30-train Hitachi inventory has one materialized trip per number."""

from collections import Counter
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable


BASE = ROOT / "app/data/train-service-history"
INVENTORY = ROOT / "docs/train-timetable-east-hitachi-2026-09-30-inventory.md"
ROW = re.compile(r"^\| (\d+) \| (下行|上行) \| \[(\d+)\]\((https://timetables\.jreast\.co\.jp/2610/train/\d+/\d+\.html)\) \| `td\.ok` \|")


class EastHitachiClosedInventoryTests(unittest.TestCase):
    def test_official_inventory_matches_one_trip_per_number_on_day(self):
        rows = [ROW.match(line) for line in INVENTORY.read_text(encoding="utf-8").splitlines()]
        links = [(int(row[1]), row[2], row[3], row[4]) for row in rows if row]
        self.assertEqual([number for number, *_ in links], list(range(1, 31)))
        for number, direction, label, url in links:
            with self.subTest(number=number):
                self.assertEqual(label, url.rsplit("/", 1)[-1].removesuffix(".html"))
                self.assertEqual(direction, "下行" if number % 2 else "上行")

        manifest = timetable.load_manifest(BASE)
        data, origins = timetable.load_dataset(BASE, manifest)
        self.assertFalse(timetable.validate_dataset(data, origins, manifest))
        hitachi = [trip for trip in timetable.materialize(data, "2026-09-30")
                   if trip["service_id"] == "hitachi"]
        counts = Counter(int(trip["public_number"]) for trip in hitachi)
        self.assertEqual(counts, Counter({number: 1 for number, *_ in links}))
        for trip in hitachi:
            self.assertEqual(trip["train_number"], f'{trip["public_number"]}M')

    def test_observed_endpoints_and_planned_equipment_coverage(self):
        manifest = timetable.load_manifest(BASE)
        data, origins = timetable.load_dataset(BASE, manifest)
        self.assertFalse(timetable.validate_dataset(data, origins, manifest))
        names = {row["station_id"]: row["name_snapshot"] for row in data["station_identities"]}
        hitachi = [trip for trip in timetable.materialize(data, "2026-09-30")
                   if trip["service_id"] == "hitachi"]
        self.assertEqual(Counter((names[trip["origin_station_id"]],
                                  names[trip["destination_station_id"]]) for trip in hitachi),
                         Counter({("品川", "いわき"): 12, ("いわき", "品川"): 12,
                                  ("品川", "仙台"): 3, ("仙台", "品川"): 3}))
        ids = {trip["trip_id"] for trip in hitachi}
        formations = [row for row in data["trip_formations"]
                      if row["trip_id"] in ids and row["service_date"] == "2026-09-30"]
        self.assertEqual(Counter(row["trip_id"] for row in formations),
                         Counter({trip_id: 1 for trip_id in ids}))


if __name__ == "__main__":
    unittest.main()
