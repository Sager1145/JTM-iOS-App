"""Guard: one physical corridor published as several same-name package lines
must get one visibility tier.

In Japan a trunk is often split by operator (JR East / Central / West), so the
old operator+name visibility group gave each piece its own length and rank and
the corridor lost a piece at overview zoom. Two same-name lines joined end to
end must have the same group length, rank and minimum zoom.

Fast: reads the shipped jp package only. Set JTM_DISPLAY_NETWORK_DIR to a built
display-network directory to also check that build's manifest.
"""
import importlib.util
import json
import math
import os
import unittest
from collections import defaultdict
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "build-display-network.py"
SPEC = importlib.util.spec_from_file_location("display_network", SCRIPT)
display_network = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(display_network)

PACKAGE = SCRIPT.parents[2] / "public" / "rail" / "jp-2025.json"
JOIN_M = 100.0  # same tolerance the builder uses; kept separate on purpose


def _metres(a, b):
    lat = math.radians((a[1] + b[1]) / 2)
    return math.hypot((a[0] - b[0]) * 111320 * math.cos(lat), (a[1] - b[1]) * 110540)


def _termini(line):
    counts = defaultdict(int)
    for row in line.get("segments") or []:
        pts = row[2]
        if len(pts) >= 2:
            for p in (pts[0], pts[-1]):
                counts[(round(p[0], 5), round(p[1], 5))] += 1
    return [p for p, n in counts.items() if n == 1]


def joined_same_name_pairs(lines):
    by_name = defaultdict(list)
    for line in lines:
        by_name[line["name"]].append((line, _termini(line)))
    for members in by_name.values():
        for i, (a, ta) in enumerate(members):
            for b, tb in members[i + 1:]:
                if any(_metres(p, q) <= JOIN_M for p in ta for q in tb):
                    yield a, b


class CorridorVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lines = json.loads(PACKAGE.read_text())["lines"]

    def test_there_are_operator_split_corridors_to_guard(self):
        pairs = [(a, b) for a, b in joined_same_name_pairs(self.lines)
                 if a.get("operator") != b.get("operator")]
        self.assertGreater(len(pairs), 5)

    def test_builder_gives_joined_same_name_lines_one_tier(self):
        groups = display_network.visibility_groups(self.lines)
        bad = []
        for a, b in joined_same_name_pairs(self.lines):
            ga, gb = groups[a["id"]], groups[b["id"]]
            za = display_network.length_min_zoom(ga[0])
            zb = display_network.length_min_zoom(gb[0])
            if ga != gb or za != zb:
                bad.append((a["name"], a.get("operator"), b.get("operator"), ga, gb))
        self.assertEqual(bad, [], f"{len(bad)} joined same-name pairs differ")

    def test_group_never_shorter_or_lower_ranked_than_own_line(self):
        groups = display_network.visibility_groups(self.lines)
        for line in self.lines:
            km, rank = groups[line["id"]]
            own = sum(float(r[0]) for r in line.get("segments") or [])
            self.assertGreaterEqual(km + 1e-6, own)
            self.assertLessEqual(rank, int(line.get("rank", 0)))

    @unittest.skipUnless(os.environ.get("JTM_DISPLAY_NETWORK_DIR"),
                         "set JTM_DISPLAY_NETWORK_DIR to check a built manifest")
    def test_built_manifest_joined_same_name_lines_share_tier(self):
        manifest = json.loads(
            (Path(os.environ["JTM_DISPLAY_NETWORK_DIR"]) / "manifest.json").read_text())
        entries = manifest["lines"]
        bad = []
        for a, b in joined_same_name_pairs(self.lines):
            ea, eb = entries.get("jp|" + a["id"]), entries.get("jp|" + b["id"])
            if not ea or not eb:
                continue
            fields = lambda e: (e["visibilityLengthKm"], e["rank"], e["minZoomMapLibre"])
            if fields(ea) != fields(eb):
                bad.append((a["name"], fields(ea), fields(eb)))
        self.assertEqual(bad, [], f"{len(bad)} joined same-name pairs differ in the build")


if __name__ == "__main__":
    unittest.main()
