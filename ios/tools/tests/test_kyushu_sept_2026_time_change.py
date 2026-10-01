"""Source-pinned date boundary for JR Kyushu's revised Ibusuki 5 departure."""

import json
from pathlib import Path
import sys
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


class KyushuSeptemberTimeChangeTests(unittest.TestCase):
    def test_september_18_boundary_and_original_earlier_clock(self):
        base = timetable.DEFAULT_CANONICAL
        candidate = json.loads((base / "candidates/jr-kyushu-ibusuki-5-september-2026-minute-change.json").read_text())
        self.assertEqual(candidate["source"]["url_or_locator"],
            "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0016/00167901.html?c=29007&d=20&ym=202609")
        manifest = timetable.load_manifest(base)
        data, origins = timetable.load_dataset(base, manifest)
        self.assertFalse(timetable.validate_dataset(data, origins, manifest))
        def departure(day):
            trips = [row for row in timetable.materialize(data, day)
                     if row["trip_id"] == candidate["trip_id"]]
            self.assertEqual(len(trips), 1)
            return trips[0]["stop_times"][0]["departure_time"]
        self.assertEqual(departure("2026-09-17"), "13:56")
        self.assertEqual(departure("2026-09-18"), "13:57")
        self.assertEqual(departure("2026-09-29"), "13:57")
        self.assertEqual(departure("2026-09-30"), "13:57")
        rows = [row for row in data["trip_stop_time_overrides"] if row["trip_id"] == candidate["trip_id"]]
        self.assertEqual(len(rows), 13)
        self.assertEqual({row["source_id"] for row in rows}, {candidate["source"]["source_id"]})


if __name__ == "__main__":
    unittest.main()
