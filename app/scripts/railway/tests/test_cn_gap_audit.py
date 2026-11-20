"""Guard and audit: gaps in the shipped mainland China (cn) rail data.

Two kinds of gap, read from the shipped files only:

1. Drawn-line breaks. A cn line is a row of station-to-station intervals. The
   drawn line breaks when an interval has no geometry, when one interval does
   not start where the previous one ended, or when an interval ends away from
   its station. There are none today and there must stay none.

2. Junction gaps. Two cn lines are joined for a ride only by a row in
   `app/data/physical-rail-junctions.json`. The generated rows join lines at a
   vertex both of them have (one original OpenStreetMap node). That rule is
   complete today: no two lines share a vertex without being joined. What is
   left is lines that end at a station another line also serves but share no
   vertex with it (different tracks in the station). Each of those needs a
   reviewed lead-in from OpenStreetMap (as 哈尔滨 京哈高速线 / 哈牡客专线 has), so the
   count is ratcheted here: it may fall, it must not rise.

Run with `--list <file.json>` to write every open terminus site.
"""
import json
import math
import sys
import unittest
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).parents[3]
PACKAGE = ROOT / "public" / "rail" / "cn-2025.json"
SOURCES = ROOT / "public" / "rail" / "cn-2025.sources.json"
REGISTRY = ROOT / "data" / "physical-rail-junctions.json"

SEAM_M = 1.0
STATION_END_M = 50.0
# Ratchets, measured 2026-11-15 on package 2026.10.18. Lower them when reviewed
# lead-ins are added; never raise them to make a change pass.
MAX_MAINLINE_COMPONENTS = 1271
MAX_OPEN_TERMINUS_SITES = 2584


def metres(a, b):
    lat = math.radians((a[1] + b[1]) / 2)
    return math.hypot((a[0] - b[0]) * 111320 * math.cos(lat), (a[1] - b[1]) * 110540)


def line_breaks(lines):
    """(empty intervals, seams, interval ends away from their station)."""
    empty, seams, off_station = [], [], []
    for line in lines:
        stations, segments = line["stations"], line["segments"]
        # A row with as many intervals as stations closes back on its first station.
        closes = len(segments) == len(stations)
        previous = None
        for index, row in enumerate(segments):
            points = row[2]
            if not points or len(points) < 2:
                empty.append((line["id"], index))
                previous = None
                continue
            if previous is not None and metres(previous, points[0]) > SEAM_M:
                seams.append((line["id"], index, round(metres(previous, points[0]))))
            previous = points[-1]
            ends = [(points[0], stations[index])]
            if index + 1 < len(stations):
                ends.append((points[-1], stations[index + 1]))
            elif closes:
                ends.append((points[-1], stations[0]))
            for point, station in ends:
                if metres(point, station[2:4]) > STATION_END_M:
                    off_station.append((line["id"], index, station[1]))
    return empty, seams, off_station


def junction_audit(lines, junctions, physical_sections):
    """(row ends on no vertex of their line, unjoined vertex-sharing pairs,
    mainline component count, open terminus sites)."""
    by_id = {line["id"]: line for line in lines}
    vertices = defaultdict(set)
    for line in lines:
        for row in line["segments"]:
            for point in row[2]:
                vertices[line["id"]].add((point[0], point[1]))
    # Reviewed physical sections add track that is joined but not drawn.
    for record in physical_sections.values():
        track = record["identity"]["trackID"]
        for point in record["coordinates"]:
            vertices[track].add((point[0], point[1]))

    parent = {}

    def find(key):
        parent.setdefault(key, key)
        while parent[key] != key:
            parent[key] = parent[parent[key]]
            key = parent[key]
        return key

    detached = []
    for row in junctions:
        tracks = []
        for side in ("from", "to"):
            track = row[side]["identity"]["trackID"]
            coordinate = row[side]["coordinate"]
            tracks.append(track)
            # A lead-in row carries its own path; its ends are checked by its builder.
            if row["kind"] == "zeroLength" and (coordinate[0], coordinate[1]) not in vertices[track]:
                detached.append((row["id"], side, track))
        parent[find(tracks[0])] = find(tracks[1])

    owners = defaultdict(set)
    for line in lines:
        for point in vertices[line["id"]]:
            owners[point].add(line["id"])
    unjoined = set()
    for ids in owners.values():
        if len(ids) > 1:
            ordered = sorted(ids)
            for other in ordered[1:]:
                if find(ordered[0]) != find(other):
                    unjoined.add((ordered[0], other))

    mainline = [line for line in lines if line["kind"] != "metro"]
    components = {find(line["id"]) for line in mainline}
    lines_at = defaultdict(set)
    for line in mainline:
        for station in line["stations"]:
            lines_at[station[0]].add(line["id"])
    sites = []
    for line in mainline:
        stations = line["stations"]
        ends = {0: stations[0], len(stations) - 1: stations[-1]}
        for station in ends.values():
            apart = sorted(o for o in lines_at[station[0]] if find(o) != find(line["id"]))
            if apart:
                sites.append({
                    "line": line["id"], "name": line["name"], "operator": line["operator"],
                    "kind": line["kind"], "station": station[1], "stationCode": station[0],
                    "coordinate": [station[2], station[3]],
                    "notJoinedTo": [{"line": o, "name": by_id[o]["name"]} for o in apart],
                })
    return detached, sorted(unjoined), len(components), sites


def load():
    lines = json.loads(PACKAGE.read_text())["lines"]
    junctions = [row for row in json.loads(REGISTRY.read_text())["junctions"]
                 if row.get("region") == "cn"]
    sections = json.loads(SOURCES.read_text()).get("byPhysicalSection", {})
    return lines, junctions, sections


class ChinaGapAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lines, cls.junctions, cls.sections = load()
        cls.audit = junction_audit(cls.lines, cls.junctions, cls.sections)

    def test_package_is_the_one_measured(self):
        self.assertGreater(len(self.lines), 3000)
        self.assertGreater(len(self.junctions), 3000)

    def test_no_drawn_line_breaks(self):
        empty, seams, off_station = line_breaks(self.lines)
        self.assertEqual(empty, [], "intervals with no geometry")
        self.assertEqual(seams, [], "intervals that do not start where the previous one ended")
        self.assertEqual(off_station, [], "intervals that end away from their station")

    def test_every_junction_row_sits_on_both_of_its_lines(self):
        self.assertEqual(self.audit[0], [])

    def test_lines_that_share_a_vertex_are_joined(self):
        self.assertEqual(self.audit[1], [])

    def test_open_junction_gaps_do_not_grow(self):
        _, _, components, sites = self.audit
        self.assertLessEqual(components, MAX_MAINLINE_COMPONENTS)
        self.assertLessEqual(len(sites), MAX_OPEN_TERMINUS_SITES)

    def test_audit_detects_a_break_and_a_missing_junction(self):
        line = json.loads(json.dumps(self.lines[0]))
        line["segments"][1][2][0] = [line["segments"][1][2][0][0] + 0.01, line["segments"][1][2][0][1]]
        empty, seams, off_station = line_breaks([line])
        self.assertEqual(len(seams), 1)
        self.assertEqual(len(off_station), 1)
        reviewed_only = [row for row in self.junctions if row["kind"] != "zeroLength"]
        self.assertNotEqual(junction_audit(self.lines, reviewed_only, self.sections)[1], [])


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--list":
        Path(sys.argv[2]).write_text(json.dumps(
            junction_audit(*load())[3], ensure_ascii=False, indent=1))
        sys.exit(0)
    unittest.main()
