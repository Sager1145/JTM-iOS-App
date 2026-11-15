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
END_STATION_M = 500.0  # segment end -> station match; kept separate from the builder on purpose


def _metres(a, b):
    lat = math.radians((a[1] + b[1]) / 2)
    return math.hypot((a[0] - b[0]) * 111320 * math.cos(lat), (a[1] - b[1]) * 110540)


def _terminal_codes(line):
    """Station codes at the first point of the first segment and the last point
    of the last segment (the line's true termini)."""
    segs = [r for r in line.get("segments") or [] if len(r) > 2 and r[2]]
    if not segs:
        return set()
    codes = set()
    for end in (segs[0][2][0], segs[-1][2][-1]):
        near = [(_metres(end, (s[2], s[3])), str(s[0])) for s in line["stations"]]
        near = [n for n in near if n[0] <= END_STATION_M]
        if near:
            codes.add(min(near)[1])
    return codes


def joined_same_name_pairs(lines):
    """Same-name lines where one's terminus station is also a station of the other."""
    by_name = defaultdict(list)
    for line in lines:
        by_name[line["name"]].append(
            (line, _terminal_codes(line), {str(s[0]) for s in line["stations"]}))
    for members in by_name.values():
        for i, (a, ta, sa) in enumerate(members):
            for b, tb, sb in members[i + 1:]:
                if ta & sb or tb & sa:
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

    def test_known_corridors_joined_and_unrelated_lines_apart(self):
        groups = display_network.visibility_groups(self.lines)
        by_id = {l["id"]: l for l in self.lines}

        def tiers(name, operator):
            return {groups[i] for i, l in by_id.items()
                    if l["name"] == name and l.get("operator") == operator}

        # JR East + JR Central + JR West 東海道線 are one trunk (shared station 熱海).
        trunk = [tiers("東海道線", op) for op in ("東日本旅客鉄道", "東海旅客鉄道", "西日本旅客鉄道")]
        self.assertTrue(all(len(t) == 1 for t in trunk))
        self.assertEqual(trunk[0], trunk[1])
        self.assertEqual(trunk[1], trunk[2])
        # 七尾線 (JR West + のと鉄道) meet at 七尾.
        self.assertEqual(tiers("七尾線", "のと鉄道"), tiers("七尾線", "西日本旅客鉄道"))
        # Unrelated same-name lines that only run near each other stay apart.
        self.assertNotEqual(tiers("日光線", "東日本旅客鉄道"), tiers("日光線", "東武鉄道"))
        self.assertNotEqual(tiers("京都線", "近畿日本鉄道"), tiers("京都線", "阪急電鉄"))
        self.assertNotEqual(tiers("本線", "富山地方鉄道"), tiers("本線", "黒部峡谷鉄道"))

    def test_grouping_never_makes_a_line_rank_zero(self):
        groups = display_network.visibility_groups(self.lines)
        for line in self.lines:
            if int(line.get("rank", 0)) > 0:
                self.assertGreaterEqual(groups[line["id"]][1], 1, line["id"])

    def test_deterministic_under_line_order(self):
        forward = display_network.visibility_groups(self.lines)
        backward = display_network.visibility_groups(list(reversed(self.lines)))
        norm = lambda g: {k: (round(v[0], 6), v[1]) for k, v in g.items()}
        self.assertEqual(norm(forward), norm(backward))

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
