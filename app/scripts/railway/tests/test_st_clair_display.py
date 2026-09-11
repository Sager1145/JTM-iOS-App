"""The native 512 schematic must never move the Line 1 interchange platform."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest


SCRIPT = Path(__file__).parents[1] / "build-display-network.py"
SPEC = importlib.util.spec_from_file_location("st_clair_display", SCRIPT)
display = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(display)
RAIL = Path(__file__).resolve().parents[3] / "public" / "rail"


class StClairDisplayTests(unittest.TestCase):
    def setUp(self):
        self.package = json.loads((RAIL / "ca-2025.json").read_text())
        self.intervals = {
            line["id"]: display.decoded_intervals(line)
            for line in self.package["lines"]
        }
        self.lanes = json.loads((RAIL / "display-lanes.json").read_text())
        self.follows = self.lanes["followsByRegion"]["ca"]

    def test_only_512_station_and_two_adjacent_display_intervals_change(self):
        original = copy.deepcopy(self.package)
        intervals = copy.deepcopy(self.intervals)
        display.straighten_st_clair_west_display("ca", self.package, self.intervals, self.follows)
        for before, after in zip(original["lines"], self.package["lines"]):
            if before["id"] != "ttc-512":
                self.assertEqual(before, after)  # Includes ALL of Line 1.
                self.assertEqual(intervals[before["id"]], self.intervals[before["id"]])
                continue
            restored = copy.deepcopy(after)
            restored["stations"][8][2:4] = before["stations"][8][2:4]
            self.assertEqual(restored, before)  # No IDs, source geometry or other stops move.
        parts = self.intervals["ttc-512"]
        for index, part in enumerate(parts):
            if index not in (7, 8):
                self.assertEqual(part, intervals["ttc-512"][index])
        a, station, b = parts[7][0], parts[7][-1], parts[8][-1]
        self.assertEqual(parts[8][0], station)
        cross = (station[0] - a[0]) * (b[1] - a[1]) - (station[1] - a[1]) * (b[0] - a[0])
        self.assertAlmostEqual(cross, 0, places=14)
        self.assertLess(display.line_length_metres(parts[7]) + display.line_length_metres(parts[8]),
                        display.line_length_metres(intervals["ttc-512"][7])
                        + display.line_length_metres(intervals["ttc-512"][8]))
        line = next(line for line in self.package["lines"] if line["id"] == "ttc-512")
        rows = [row for row in self.lanes["partsByRegion"]["ca"] if row[0] == "ttc-512"]
        chain = display.chains_from_parts_rows(rows, parts, line["stations"], set(), "ttc-512", "ca")[0]
        self.assertEqual(chain["polyline"][chain["anchorIndexByStation"][8]], station)
        self.assertEqual(line["stations"][8][2:4], station)

    def test_western_branch_follows_the_same_track_after_shortening(self):
        original = copy.deepcopy(self.follows)
        old_total = sum(display.line_length_metres(part) for part in self.intervals["ttc-512"])
        display.straighten_st_clair_west_display("ca", self.package, self.intervals, self.follows)
        new_total = sum(display.line_length_metres(part) for part in self.intervals["ttc-512"])
        for before, after in zip(original, self.follows):
            if before[4] == "ttc-512":
                self.assertEqual(before[:6], after[:6])
                self.assertAlmostEqual(after[6] - before[6], new_total - old_total)
                self.assertAlmostEqual(after[7] - before[7], new_total - old_total)
            else:
                self.assertEqual(before, after)

    def test_other_regions_are_untouched(self):
        before = copy.deepcopy((self.package, self.intervals, self.follows))
        display.straighten_st_clair_west_display("us", self.package, self.intervals, self.follows)
        self.assertEqual((self.package, self.intervals, self.follows), before)


if __name__ == "__main__":
    unittest.main()
