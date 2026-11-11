"""Guards for `{region}.topology.bin`, the display network's topology file.

Standard library only; run with `python3 -I -m unittest` from this directory or
by path. Three layers:

* the encoder against the contract (Swift constants and the hand-built fixture),
* the derivation on small hand-made lines (continuous, split, non-continuous),
* the real builder on the tw, hk, mo and kr packages, run twice.

`JTM_DISPLAY_BUILD_DIR` points the last group at a complete builder output
(including jp) instead of building one.
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import math
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
RAILWAY = ROOT / "app/scripts/railway"


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    sys.modules[name] = module      # dataclasses look their module up here
    spec.loader.exec_module(module)
    return module


topology = _load("display_topology", RAILWAY / "lib/display_topology.py")
SWIFT = ROOT / "ios/RailKit/Sources/RailCore/Topology/RailTopologyFormat.swift"
FIXTURE = ROOT / "ios/RailKit/Tests/RailCoreTests/Topology/Fixtures/topology-mini.bin"


def metres_between(a, b) -> float:
    lat = ((a[1] + b[1]) / 2) * math.pi / 180
    return math.hypot((b[0] - a[0]) * 111320 * math.cos(lat), (b[1] - a[1]) * 111320)


# ---------------------------------------------------------------------------
# The encoder against the contract
# ---------------------------------------------------------------------------

class FormatContractTests(unittest.TestCase):
    def swift_constants(self) -> dict[str, int]:
        """`public static let name = 12` inside `enum Line { ... }` and friends."""
        text = SWIFT.read_text()
        found: dict[str, int] = {}
        for enum in ("Header", "Line", "Node", "Edge", "Run", "Link", "Identity", "Stop"):
            body = re.search(r"public enum %s \{(.*?)\n    \}" % enum, text, re.S)
            self.assertIsNotNone(body, enum)
            for name, value in re.findall(r"public static let (\w+) = (\d+)", body.group(1)):
                found[f"{enum}.{name}"] = int(value)
        return found

    def test_record_sizes_and_header_match_the_swift_contract(self):
        swift = self.swift_constants()
        self.assertEqual(swift["Header.size"], topology.HEADER_SIZE)
        for enum, table in (("Line", "lines"), ("Node", "nodes"), ("Edge", "edges"), ("Run", "runs"),
                            ("Link", "links"), ("Identity", "identities"), ("Stop", "stops")):
            self.assertEqual(swift[f"{enum}.size"], topology.RECORD_SIZE[table], enum)
        self.assertEqual(swift["Header.directoryOffset"], 88)
        self.assertEqual(swift["Header.fileLengthOffset"], 80)
        text = SWIFT.read_text()
        self.assertIn('formatName = "%s"' % topology.FORMAT_NAME, text)
        self.assertIn("formatVersion: UInt16 = %d" % topology.FORMAT_VERSION, text)
        self.assertIn("noString: UInt32 = 0xFFFF_FFFF", text)
        self.assertIn("unsetMetres: UInt32 = 0xFFFF_FFFF", text)
        flags = dict(re.findall(r"static let (\w+) = (?:Line|Node|Edge)Flag\(rawValue: 1 << (\d)\)", text))
        expected = {
            "loop": topology.LINE_LOOP, "highSpeed": topology.LINE_HIGH_SPEED,
            "pairedUpDown": topology.LINE_PAIRED, "retired": topology.LINE_RETIRED,
            "nonContinuous": topology.LINE_NON_CONTINUOUS,
            "junctionPoint": topology.NODE_JUNCTION_POINT, "noChainSlot": topology.NODE_NO_CHAIN_SLOT,
            "forward": topology.EDGE_FORWARD, "reverse": topology.EDGE_REVERSE,
            "withheld": topology.EDGE_WITHHELD, "hasRuns": topology.EDGE_HAS_RUNS,
        }
        for name, value in expected.items():
            self.assertEqual(1 << int(flags[name]), value, name)

    def fixture_records(self):
        decoded = topology.read_topology(FIXTURE.read_bytes())
        lines = []
        for index, line in enumerate(decoded["lines"]):
            nodes = [topology.Node(n["code"], n["chain"], n["full"], n["overview"], n["lon"],
                                   n["lat"], n["flags"]) for n in line["nodes"]]
            edges = [topology.Edge(e["lengthCm"], e["cumulativeCm"], e["validFrom"], e["validTo"],
                                   e["flags"], [topology.Run(r["chain"], r["fullFrom"], r["fullTo"],
                                                             r["overviewFrom"], r["overviewTo"])
                                                for r in e["runs"]]) for e in line["edges"]]
            identities = [topology.Identity(i["name"], i["family"], i["validFrom"], i["validTo"])
                          for i in decoded["identities"] if i["line"] == index]
            lines.append(topology.LineRecord(
                line["id"], line["family"], line["name"], line["aliases"], line["institution"],
                line["categoryMask"], line["flags"], line["chainCount"], line["validFrom"],
                line["validTo"], nodes, edges, identities))
        links = [topology.Link(l["nodeA"], l["nodeB"], l["kind"], l["directed"], l["validFrom"],
                               l["validTo"], l["registryID"]) for l in decoded["links"]]
        stops = [topology.Stop(s["key"], s["kind"], s["nodes"]) for s in decoded["stops"]]
        return decoded, lines, links, stops

    def test_encoder_reproduces_the_hand_built_fixture_byte_for_byte(self):
        decoded, lines, links, stops = self.fixture_records()
        again = topology.encode_topology(
            decoded["region"], decoded["packageSHA256"], decoded["displaySHA256"], lines, links, stops)
        self.assertEqual(again, FIXTURE.read_bytes())

    def test_fixture_shape(self):
        decoded, lines, links, stops = self.fixture_records()
        self.assertEqual([len(l.nodes) for l in lines], [3, 3])
        self.assertEqual(len(links), 2)
        self.assertEqual(sum(len(e.runs) for l in lines for e in l.edges), 4)

    def test_truncated_and_foreign_files_are_refused(self):
        data = FIXTURE.read_bytes()
        with self.assertRaises(topology.TopologyError):
            topology.read_topology(data[:-4])
        with self.assertRaises(topology.TopologyError):
            topology.read_topology(b"XXXX" + data[4:])

    def test_day_numbers(self):
        self.assertEqual(topology.day_number("1800-01-01"), 1)
        self.assertEqual(topology.day_number("1800-03-01"), 60)
        self.assertEqual(topology.day_number("2000-03-01") - topology.day_number("2000-02-28"), 2)
        self.assertEqual(topology.day_number("1900-03-01") - topology.day_number("1900-02-28"), 1)
        self.assertEqual(topology.optional_day(None), 0)
        self.assertEqual(topology.optional_day(""), 0)
        for bad in ("1799-12-31", "2020-13-01", "2020-1-1", "x"):
            with self.assertRaises(topology.TopologyError):
                topology.day_number(bad)

    def test_ruler_matches_the_swift_function(self):
        # Measures printed by a Swift script that repeats the arithmetic of
        # `joinedChainCoordinates` (MapLineGeometry.swift), in centimetres.
        chains = [
            ([(139.7671248, 35.6812362), (139.7730040, 35.6896000), (139.7798000, 35.6984210),
              (139.7912340, 35.7141000), (139.8001000, 35.7290000)],
             [0, 107212, 223046, 425891, 610098]),
            ([(135.4959506, 34.7024854), (135.5011230, 34.6937000), (135.5106660, 34.6851050),
              (135.5201000, 34.6702000)], [0, 108654, 238209, 425263]),
            ([(141.3544506, 43.0686606), (141.3501000, 43.0601000), (141.3432000, 43.0512000),
              (141.3398000, 43.0311000), (141.3350000, 43.0102000), (141.3311000, 42.9855000)],
             [0, 101653, 215521, 440978, 676893, 953681]),
            ([(127.6791000, 26.2123000), (127.6823000, 26.2191000), (127.6890000, 26.2260000)],
             [0, 82167, 184033]),
            ([(126.9726000, 37.5547000), (126.9783000, 37.5651000), (127.0011000, 37.5802000),
              (127.0276000, 37.5801000)], [0, 126228, 388377, 622166]),
        ]
        for points, expected in chains:
            self.assertEqual([topology.to_cm(m) for m in topology.ruler(points)], expected)


# ---------------------------------------------------------------------------
# Hand-made lines
# ---------------------------------------------------------------------------

def station(code, lon, lat):
    return [code, code, lon, lat, code]


def package_line(line_id, stations, kms, loop=False, **extra):
    segments = [[km, 0, [[0, 0], [0, 0]]] for km in kms]
    line = {"id": line_id, "name": line_id, "operator": "op", "stations": stations,
            "segments": segments, "isLoop": loop or None}
    line.update(extra)
    return line


def source(key, line, continuous, fragments, overview=None, chains=(), pieces=(), withheld=(),
           slots=None, stamps=None):
    return topology.LineSource(
        key=key, line=line, continuous=continuous, fragments=fragments, overview=overview,
        chains=list(chains), pieces=list(pieces), withheld=set(withheld), slots=slots or {},
        stamps=stamps or {},
        draw_ids=[f"{key}#{f.get('chain', 0)}" if f.get("continuous") else f"{key}@{f.get('lane', 0.0)}"
                  for f in fragments])


def build(sources, junctions=None, through=None, registry=None):
    data, report = topology.build_region_topology(
        "jp", sources, b"\x01" * 32, b"\x02" * 32, junctions, through, registry)
    return topology.read_topology(data), report, data


class DerivationTests(unittest.TestCase):
    PART0 = [(0.0, 0.0), (0.001, 0.0)]
    PART1 = [(0.001, 0.0), (0.002, 0.0005), (0.003, 0.0)]
    PART2 = [(0.003, 0.0), (0.004, 0.0)]

    def continuous_line(self):
        parts = [self.PART0, self.PART1, self.PART2]
        joined = self.PART0 + self.PART1[1:] + self.PART2[1:]
        # Stations sit at joined vertices 0, 2 (inside part 1), 3 and 4.
        stations = [station("S0", *joined[0]), station("S1", *joined[2]),
                    station("S2", *joined[3]), station("S3", *joined[4])]
        line = package_line("jp-c", stations, [0.5, 0.25, 0.1])
        chain = {"polyline": [list(p) for p in joined], "firstInterval": None,
                 "anchorIndexByStation": {0: 0, 1: 2, 2: 3, 3: 4}}
        fragment = {"lineKey": "jp|jp-c", "continuous": True, "chain": 0, "lane": 0.0,
                    "parts": [[list(p) for p in part] for part in parts]}
        overview = dict(fragment)
        overview["parts"] = [[list(p) for p in self.PART0], [[0.001, 0.0], [0.003, 0.0]],
                             [list(p) for p in self.PART2]]
        return line, chain, fragment, overview, joined

    def test_continuous_chain_positions_and_direct_edges(self):
        line, chain, fragment, overview, joined = self.continuous_line()
        decoded, report, _ = build([source("jp|jp-c", line, True, [fragment], [overview], [chain])])
        nodes = decoded["lines"][0]["nodes"]
        ruler = topology.ruler(joined)
        self.assertEqual([n["full"] for n in nodes], [topology.to_cm(ruler[i]) for i in (0, 2, 3, 4)])
        self.assertEqual({n["chain"] for n in nodes}, {0})
        # The station inside part 1 is projected onto the simplified part: the
        # interior vertex (0.002, 0.0005) is above the segment's midpoint.
        segment = topology.ruler([(0.001, 0.0), (0.003, 0.0)])[-1]
        overview_ruler = topology.ruler([(0.0, 0.0), (0.001, 0.0), (0.003, 0.0), (0.004, 0.0)])
        self.assertAlmostEqual(nodes[1]["overview"], topology.to_cm(overview_ruler[1] + segment / 2), delta=2)
        self.assertEqual(nodes[2]["overview"], topology.to_cm(overview_ruler[2]))
        edges = decoded["lines"][0]["edges"]
        self.assertEqual([e["lengthCm"] for e in edges], [50000, 25000, 10000])
        self.assertEqual([e["cumulativeCm"] for e in edges], [0, 50000, 75000])
        for edge in edges:      # each edge is exactly the range between its nodes
            self.assertEqual(edge["flags"] & topology.EDGE_HAS_RUNS, 0)
            self.assertEqual(edge["runs"], [])
            self.assertEqual(edge["flags"] & 3, 3)
        self.assertEqual(report["unanchoredStations"], [])

    def test_continuous_chain_split_by_history_gives_runs_on_both_chains(self):
        line, chain, fragment, overview, joined = self.continuous_line()
        # History cut the chain at joined vertex 2: two final chains sharing it.
        first = dict(fragment, chain=0, parts=[[list(p) for p in self.PART0], [[0.001, 0.0], [0.002, 0.0005]]])
        second = dict(fragment, chain=1, parts=[[[0.002, 0.0005], [0.003, 0.0]], [list(p) for p in self.PART2]])
        line["stations"] = [station("S0", *joined[0]), station("S1", *joined[1]),
                            station("S2", *joined[3]), station("S3", *joined[4])]
        chain["anchorIndexByStation"] = {0: 0, 1: 1, 2: 3, 3: 4}
        decoded, report, _ = build([source("jp|jp-c", line, True, [first, second], None, [chain])])
        nodes = decoded["lines"][0]["nodes"]
        self.assertEqual([n["chain"] for n in nodes], [0, 0, 1, 1])
        edges = decoded["lines"][0]["edges"]
        self.assertEqual(edges[0]["flags"] & topology.EDGE_HAS_RUNS, 0)
        crossing = edges[1]
        self.assertTrue(crossing["flags"] & topology.EDGE_HAS_RUNS)
        self.assertEqual([r["chain"] for r in crossing["runs"]], [0, 1])
        first_ruler = topology.ruler(self.PART0 + [(0.002, 0.0005)])
        second_ruler = topology.ruler([(0.002, 0.0005), (0.003, 0.0), (0.004, 0.0)])
        self.assertEqual(crossing["runs"][0]["fullFrom"], topology.to_cm(first_ruler[1]))
        self.assertEqual(crossing["runs"][0]["fullTo"], topology.to_cm(first_ruler[2]))
        self.assertEqual(crossing["runs"][1]["fullFrom"], 0)
        self.assertEqual(crossing["runs"][1]["fullTo"], topology.to_cm(second_ruler[1]))
        self.assertEqual(report["slotMismatches"], [])

    def lead_in_line(self, stations_on):
        """Main chain A and a spur B that leaves A's last vertex; stations given as
        (code, chain name, vertex) with B holding the stations the spur serves."""
        a = [(0.0, 0.0), (0.001, 0.0), (0.002, 0.0), (0.003, 0.0)]
        b = [(0.003, 0.0), (0.003, 0.001)]
        chains = {"A": a, "B": b}
        rows, anchors = [], {"A": {}, "B": {}}
        for number, (code, name, vertex) in enumerate(stations_on):
            rows.append(station(code, *chains[name][vertex]))
            anchors[name][number] = vertex
        line = package_line("jp-l", rows, [0.2] * (len(rows) - 1))
        built = [{"polyline": [list(p) for p in chains[name]], "firstInterval": None,
                  "anchorIndexByStation": anchors[name]} for name in ("A", "B")]
        fragments = [{"lineKey": "jp|jp-l", "continuous": True, "chain": number, "lane": 0.0,
                      "parts": [[list(p) for p in chains[name]]]} for number, name in enumerate(("A", "B"))]
        return line, built, fragments, chains

    def test_an_interval_split_over_two_chains_that_meet_is_routed_and_reported(self):
        line, built, fragments, chains = self.lead_in_line([("S0", "A", 0), ("S1", "B", 1)])
        decoded, report, _ = build([source("jp|jp-l", line, True, fragments, None, built)])
        edge = decoded["lines"][0]["edges"][0]
        self.assertTrue(edge["flags"] & topology.EDGE_HAS_RUNS)
        a_ruler, b_ruler = topology.ruler(chains["A"]), topology.ruler(chains["B"])
        self.assertEqual([(r["chain"], r["fullFrom"], r["fullTo"]) for r in edge["runs"]],
                         [(0, 0, topology.to_cm(a_ruler[3])), (1, 0, topology.to_cm(b_ruler[1]))])
        self.assertEqual([row["hops"] for row in report["routedEdges"]], [2])
        self.assertEqual(report["edgesWithoutGeometry"], [])

    def test_an_interval_nothing_can_carry_is_reported_without_geometry(self):
        line, built, fragments, chains = self.lead_in_line([("S0", "A", 0), ("S1", "B", 1)])
        built[0]["polyline"][3] = [0.0035, 0.0]            # the chains no longer meet
        fragments[0]["parts"][0][3] = [0.0035, 0.0]
        decoded, report, _ = build([source("jp|jp-l", line, True, fragments, None, built)])
        self.assertEqual(report["edgesWithoutGeometry"], ["jp|jp-l#0"])
        self.assertEqual(decoded["lines"][0]["edges"][0]["runs"], [])

    def test_a_closed_chain_that_runs_against_the_station_order_is_walked_the_other_way_round(self):
        ring = [(0.0, 0.0), (0.001, 0.0), (0.001, 0.001), (0.0, 0.001), (0.0, 0.0)]
        stations = [station("R0", *ring[0]), station("R1", *ring[3]),
                    station("R2", *ring[2]), station("R3", *ring[1])]
        line = package_line("jp-r", stations, [0.11, 0.11, 0.11, 0.11], loop=True)
        chain = {"polyline": [list(p) for p in ring], "firstInterval": None,
                 "anchorIndexByStation": {0: 0, 1: 3, 2: 2, 3: 1}}
        fragment = {"lineKey": "jp|jp-r", "continuous": True, "chain": 0, "lane": 0.0,
                    "parts": [[list(p) for p in ring]]}
        decoded, report, _ = build([source("jp|jp-r", line, True, [fragment], None, [chain])])
        measures = topology.ruler(ring)
        edges = decoded["lines"][0]["edges"]
        nodes = decoded["lines"][0]["nodes"]
        spans = [((e["runs"][0]["fullFrom"], e["runs"][0]["fullTo"]) if e["runs"]
                  else (nodes[i]["full"], nodes[(i + 1) % 4]["full"])) for i, e in enumerate(edges)]
        cm = topology.to_cm
        self.assertEqual(spans, [(cm(measures[4]), cm(measures[3])), (cm(measures[3]), cm(measures[2])),
                                 (cm(measures[2]), cm(measures[1])), (cm(measures[1]), cm(measures[0]))])
        self.assertEqual(report["lengthMismatchEdges"], [])

    def test_an_edge_drawn_far_from_its_surveyed_length_is_listed(self):
        line, fragments, pieces = self.non_continuous_line()
        line["segments"][0][0] = 5.0
        decoded, report, _ = build([source("jp|jp-n", line, False, fragments, None, pieces=pieces,
                                           withheld={1})])
        self.assertEqual([(row["line"], row["interval"]) for row in report["lengthMismatchEdges"]],
                         [("jp|jp-n", 0), ("jp|jp-n", 2)])

    def test_fragment_that_is_not_a_slice_of_the_builders_chain_stops_the_build(self):
        line, chain, fragment, overview, _ = self.continuous_line()
        fragment["parts"][0][1] = [0.0015, 0.0]
        with self.assertRaises(topology.TopologyError):
            build([source("jp|jp-c", line, True, [fragment], None, [chain])])

    def non_continuous_line(self, withheld_middle=True):
        a = [(0.0, 0.0), (0.001, 0.0)]
        b = [(0.001, 0.0), (0.001, 0.001)]
        c1 = [(0.001, 0.001), (0.0005, 0.0015)]
        c2 = [(0.0005, 0.0015), (0.0, 0.0)]
        stations = [station("N0", 0.0, 0.0), station("N1", 0.001, 0.0), station("N2", 0.001, 0.001)]
        line = package_line("jp-n", stations, [0.1, 0.1, 0.2], loop=True)
        pieces = [(0.0, 0, a), (0.0, 2, c1), (1.0, 2, c2)]
        if not withheld_middle:
            pieces.insert(1, (0.0, 1, b))
        lane0 = [a, c1] if withheld_middle else [a, b, c1]
        fragments = [
            {"lineKey": "jp|jp-n", "lane": 0.0, "parts": [[list(p) for p in part] for part in lane0]},
            {"lineKey": "jp|jp-n", "lane": 1.0, "parts": [[list(p) for p in c2]]},
        ]
        return line, fragments, pieces

    def test_non_continuous_parts_are_numbered_flat_and_withheld_edges_have_no_runs(self):
        line, fragments, pieces = self.non_continuous_line()
        decoded, report, _ = build([source("jp|jp-n", line, False, fragments, None, pieces=pieces,
                                           withheld={1})])
        record = decoded["lines"][0]
        self.assertTrue(record["flags"] & topology.LINE_NON_CONTINUOUS)
        self.assertTrue(record["flags"] & topology.LINE_LOOP)
        self.assertEqual(record["chainCount"], 3)
        edges = record["edges"]
        self.assertEqual(len(edges), 3)
        for edge in edges:      # the non-continuous rule: every edge carries runs
            self.assertTrue(edge["flags"] & topology.EDGE_HAS_RUNS)
        self.assertEqual([r["chain"] for r in edges[0]["runs"]], [0])
        self.assertEqual(edges[1]["runs"], [])
        self.assertTrue(edges[1]["flags"] & topology.EDGE_WITHHELD)
        self.assertEqual([r["chain"] for r in edges[2]["runs"]], [1, 2])      # lane 0 piece, then lane 1 piece
        first_length = topology.to_cm(topology.ruler(self.non_continuous_line()[2][0][2])[-1])
        self.assertEqual(edges[0]["runs"][0]["fullFrom"], 0)
        self.assertEqual(edges[0]["runs"][0]["fullTo"], first_length)
        nodes = record["nodes"]
        self.assertEqual([n["chain"] for n in nodes], [0, 0, 1])
        self.assertEqual(nodes[0]["full"], 0)
        self.assertEqual(nodes[1]["full"], first_length)         # no outgoing run: end of the incoming part
        self.assertEqual(nodes[2]["full"], 0)                    # start of the piece that leaves it
        self.assertEqual(report["unanchoredStations"], [])

    def test_a_part_cut_in_two_by_history_gives_the_edge_two_runs(self):
        line, fragments, pieces = self.non_continuous_line(withheld_middle=False)
        a = fragments[0]["parts"][0]
        middle = [0.0005, 0.0]
        fragments[0]["parts"][0:1] = [[a[0], middle], [middle, a[1]]]
        # The builder cut one piece with a vertex in the middle; history cut it there.
        pieces[0] = (0.0, 0, [tuple(a[0]), tuple(middle), tuple(a[1])])
        decoded, _, _ = build([source("jp|jp-n", line, False, fragments, None, pieces=pieces)])
        edges = decoded["lines"][0]["edges"]
        self.assertEqual([r["chain"] for r in edges[0]["runs"]], [0, 1])
        self.assertEqual(decoded["lines"][0]["chainCount"], 5)
        self.assertEqual([r["chain"] for r in edges[1]["runs"]], [2])

    def test_validity_comes_from_the_history_stamp_and_a_close_date_is_kept_exclusive(self):
        line, fragments, pieces = self.non_continuous_line(withheld_middle=False)
        stamps = {("jp|jp-n@0.0", 0): ("2024-03-16", None), ("jp|jp-n@0.0", 1): (None, "2020-01-01")}
        decoded, report, _ = build([source("jp|jp-n", line, False, fragments, None, pieces=pieces,
                                           stamps=stamps)])
        edges = decoded["lines"][0]["edges"]
        self.assertEqual((edges[0]["validFrom"], edges[0]["validTo"]), (topology.day_number("2024-03-16"), 0))
        self.assertEqual((edges[1]["validFrom"], edges[1]["validTo"]), (0, topology.day_number("2020-01-01")))
        self.assertEqual((edges[2]["validFrom"], edges[2]["validTo"]), (0, 0))
        self.assertEqual(report["datedEdges"], 2)

    def test_edge_with_zero_surveyed_length_stops_the_build(self):
        line, fragments, pieces = self.non_continuous_line()
        line["segments"][0][0] = 0
        with self.assertRaises(topology.TopologyError):
            build([source("jp|jp-n", line, False, fragments, None, pieces=pieces, withheld={1})])

    def test_allowed_directions_follow_the_package_metadata(self):
        stations = [station("A", 0, 0), station("B", 1, 0), station("C", 2, 0)]
        plain = package_line("x", stations, [1, 1])
        self.assertEqual(topology.allowed_directions(plain, 0), [-1, 1])
        self.assertEqual(topology.allowed_directions(dict(plain, permittedTraversal="forward"), 0), [1])
        self.assertEqual(topology.allowed_directions(dict(plain, permittedTraversal="reverse"), 1), [-1])
        up = dict(plain, stationOrderDirection="up", alignmentDirection="down")
        self.assertEqual(topology.allowed_directions(up, 0), [-1])
        paired = dict(plain, stationOrderDirection="down", alignmentPairs=[
            {"with": "y", "from": "A", "to": "B", "direction": "down"}])
        self.assertEqual(topology.allowed_directions(paired, 0), [1])
        self.assertEqual(topology.allowed_directions(paired, 1), [-1, 1])


# ---------------------------------------------------------------------------
# Links and stops
# ---------------------------------------------------------------------------

class LinkTests(unittest.TestCase):
    NODES = {("jp-a", "001"): 0, ("jp-a", "002"): 1, ("jp-b", "002"): 2, ("jp-b", "003"): 3,
             ("jp-c", "003"): 4}

    def node_of(self, line, code):
        return self.NODES.get((line, code))

    def junction(self, **fields):
        row = {"id": "j1", "region": "jp", "stationCode": "002", "lineIDs": ["jp-a", "jp-b"],
               "evidence": ["https://example.org/a"], "validFrom": "2003-03-19", "validTo": None}
        row.update(fields)
        return {"format": "jtm-physical-rail-junctions-v1", "junctions": [row]}

    def test_a_reviewed_junction_becomes_one_dated_link(self):
        links, skipped = topology.compile_junction_links(self.junction(), "jp", self.node_of)
        self.assertEqual(skipped, [])
        self.assertEqual([(l.node_a, l.node_b, l.kind, l.registry_id) for l in links],
                         [(1, 2, topology.LINK_PHYSICAL_JUNCTION, "j1")])
        self.assertEqual((links[0].valid_from, links[0].valid_to), (topology.day_number("2003-03-19"), 0))

    def test_rows_that_cannot_be_placed_or_do_not_qualify_are_reported_not_linked(self):
        cases = [
            (self.junction(stationCode="009"), "stationCodeNotOnLine"),
            (self.junction(lineIDs=["jp-a"]), "noTwoLinePair"),
            (self.junction(evidence=[]), "noStationCodeOrEvidence"),
            (self.junction(stationCode=None), "noStationCodeOrEvidence"),
            (self.junction(endJunction={}, evidence=["https://www.openstreetmap.org/way/1", "way 12"]),
             "endJunctionWithoutTrainEvidence"),
            (self.junction(region="cn"), None),
        ]
        for document, reason in cases:
            links, skipped = topology.compile_junction_links(document, "jp", self.node_of)
            self.assertEqual(links, [], reason)
            self.assertEqual([row["reason"] for row in skipped], [reason] if reason else [])

    def test_a_row_naming_more_than_two_lines_needs_disjoint_sides(self):
        document = self.junction(lineIDs=["jp-a", "jp-b", "jp-c"], stationCode="003",
                                 fromLineIDs=["jp-b"], toLineIDs=["jp-c", "jp-a"])
        links, skipped = topology.compile_junction_links(document, "jp", self.node_of)
        self.assertEqual([(l.node_a, l.node_b) for l in links], [(3, 4)])
        self.assertEqual([row["lines"] for row in skipped], [["jp-a"]])

    def through(self, patterns, connectors=(), coverage="2005-01-01"):
        return {"coverageFrom": coverage, "connectors": list(connectors), "patterns": patterns}

    def pattern(self, **fields):
        row = {"id": "p1", "serviceCode": "P", "validFrom": None, "validTo": None, "legs": [
            {"lineID": "jp-a", "fromStationCode": "001", "toStationCode": "002"},
            {"lineID": "jp-b", "fromStationCode": "002", "toStationCode": "003"}]}
        row.update(fields)
        return row

    def on(self, link, day):
        valid_from, valid_to = link.valid_from, link.valid_to
        return (valid_from == 0 or day >= valid_from) and (valid_to == 0 or day < valid_to)

    def test_a_through_service_link_exists_only_inside_the_pattern_and_catalog_window(self):
        document = self.through([self.pattern(validTo="2020-01-01")])
        links, skipped = topology.compile_through_links(document, self.node_of)
        self.assertEqual(skipped, [])
        self.assertEqual(len(links), 1)
        link = links[0]
        self.assertEqual((link.node_a, link.node_b, link.kind, link.registry_id),
                         (1, 2, topology.LINK_THROUGH_SERVICE, "p1"))
        # No leading bound on the pattern: the catalog's coverage start is the first day.
        self.assertEqual(link.valid_from, topology.day_number("2005-01-01"))
        self.assertEqual(link.valid_to, topology.day_number("2020-01-01"))
        self.assertFalse(self.on(link, topology.day_number("2004-12-31")))
        self.assertTrue(self.on(link, topology.day_number("2005-01-01")))
        self.assertTrue(self.on(link, topology.day_number("2019-12-31")))
        self.assertFalse(self.on(link, topology.day_number("2020-01-01")))

    def test_an_open_ended_through_service_is_valid_for_undated_rides(self):
        links, _ = topology.compile_through_links(self.through([self.pattern(validFrom="2010-06-01")]), self.node_of)
        self.assertEqual((links[0].valid_from, links[0].valid_to), (topology.day_number("2010-06-01"), 0))

    def test_a_dated_leg_splits_the_window(self):
        legs = [{"lineID": "jp-a", "fromStationCode": "001", "toStationCode": "002"},
                {"lineID": "jp-b", "fromStationCode": "002", "toStationCode": "003", "validFrom": "2010-01-01"},
                {"lineID": "jp-c", "fromStationCode": "003", "toStationCode": "004", "validTo": "2015-01-01"}]
        document = self.through([self.pattern(legs=legs)])
        links, _ = topology.compile_through_links(document, self.node_of)
        by_pair = {(l.node_a, l.node_b): (l.valid_from, l.valid_to) for l in links}
        # a to b exists while both legs are active and the third leg does not leave a gap
        self.assertEqual(by_pair[(1, 2)], (topology.day_number("2010-01-01"), 0))
        self.assertEqual(by_pair[(3, 4)], (topology.day_number("2010-01-01"), topology.day_number("2015-01-01")))

    def test_a_connector_joins_two_different_codes_and_nothing_else_does(self):
        legs = [{"lineID": "jp-a", "fromStationCode": "001", "toStationCode": "002"},
                {"lineID": "jp-b", "fromStationCode": "003", "toStationCode": "003"}]
        without = self.through([self.pattern(legs=legs)])
        links, _ = topology.compile_through_links(without, self.node_of)
        self.assertEqual(links, [])
        connector = {"id": "c", "fromLineID": "jp-a", "fromStationCode": "002",
                     "toLineID": "jp-b", "toStationCode": "003"}
        links, _ = topology.compile_through_links(self.through([self.pattern(legs=legs)], [connector]), self.node_of)
        self.assertEqual([(l.node_a, l.node_b) for l in links], [(1, 3)])

    def test_two_lines_sharing_a_station_code_and_a_name_are_not_linked(self):
        stations = [station("S", 0, 0), station("T", 0.001, 0)]
        a = package_line("jp-a", stations, [1])
        b = package_line("jp-b", stations, [1])
        fragments = lambda key: [{"lineKey": key, "lane": 0.0, "parts": [[[0, 0], [0.001, 0]]]}]
        pieces = [(0.0, 0, [(0.0, 0.0), (0.001, 0.0)])]
        decoded, report, _ = build([
            source("jp|jp-a", a, False, fragments("jp|jp-a"), None, pieces=pieces),
            source("jp|jp-b", b, False, fragments("jp|jp-b"), None, pieces=pieces)],
            junctions={"format": "jtm-physical-rail-junctions-v1", "junctions": []},
            through=self.through([]))
        self.assertEqual(decoded["links"], [])
        stops = {(s["key"], s["kind"]): s["nodes"] for s in decoded["stops"]}
        self.assertEqual(stops[("S", topology.STOP_PLATFORM)], [0, 2])

    def test_stop_index_is_sorted_by_key_bytes_then_kind(self):
        stations = [station("S", 0, 0), station("T", 0.001, 0)]
        line = package_line("jp-a", stations, [1])
        registry = {"stations": {"st:jp:1": {"codes": ["S"], "group": "S"}, "st:jp:2": {"codes": [], "group": "T"}},
                    "stationCodes": {"T": "st:jp:2"}, "groupCodes": {"S": ["st:jp:1"], "T": ["st:jp:2"]}}
        fragments = [{"lineKey": "jp|jp-a", "lane": 0.0, "parts": [[[0, 0], [0.001, 0]]]}]
        decoded, _, _ = build([source("jp|jp-a", line, False, fragments, None,
                                      pieces=[(0.0, 0, [(0.0, 0.0), (0.001, 0.0)])])], registry=registry)
        keys = [(s["key"].encode(), s["kind"]) for s in decoded["stops"]]
        self.assertEqual(keys, sorted(keys))
        self.assertEqual({(s["key"], s["kind"]) for s in decoded["stops"]},
                         {("S", 1), ("T", 1), ("S", 3), ("T", 3), ("st:jp:1", 2), ("st:jp:2", 2)})

    def test_every_link_carries_the_row_it_came_from(self):
        with self.assertRaises(topology.TopologyError):
            topology.encode_topology("jp", b"\0" * 32, b"\0" * 32, [], [topology.Link(0, 1, 1, False, 0, 0, "")], [])


# ---------------------------------------------------------------------------
# The real builder
# ---------------------------------------------------------------------------

def empty_package(country: str) -> dict:
    return {"format": "compact-v1", "version": "test", "country": country, "lines": []}


class BuilderRunMixin:
    """Builds tw, hk, mo and kr from the shipped packages (jp and cn empty)."""

    _outputs: dict[str, Path] = {}
    _temp = None

    @classmethod
    def build_once(cls, name: str) -> Path:
        if name in cls._outputs:
            return cls._outputs[name]
        if cls._temp is None:
            cls._temp = tempfile.TemporaryDirectory()
        base = Path(cls._temp.name)
        rail = base / "rail"
        rail.mkdir(exist_ok=True)
        for region in ("tw", "hk", "mo", "kr"):
            target = rail / f"{region}-2025.json"
            if not target.exists():
                target.symlink_to(ROOT / f"app/public/rail/{region}-2025.json")
        for region in ("jp", "cn"):
            (rail / f"{region}-2025.json").write_text(json.dumps(empty_package(region.upper())))
        for shared in ("shared-corridors.json", "display-lanes.json", "display-hubs.json", "jp-render-groups.json"):
            target = rail / shared
            if not target.exists():
                target.symlink_to(ROOT / "app/public/rail" / shared)
        builder = _load("display_network_for_topology", RAILWAY / "build-display-network.py")
        output = base / name
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            builder.build(
                rail, output,
                junctions_path=ROOT / "app/data/physical-rail-junctions.json",
                through_services_path=ROOT / "ios/RailKit/Sources/RailCore/Resources/japan-through-services.json",
                registry_dir=ROOT / "app/data/registry-bundle")
        cls._outputs[name] = output
        return output


def load_build(directory: Path):
    manifest = json.loads((directory / "manifest.json").read_text())
    return manifest


def region_checks(testcase: unittest.TestCase, directory: Path, region: str, packages_dir: Path) -> dict:
    """The invariants of one built region. Returns counts for the callers."""
    manifest = load_build(directory)
    record = next(r for r in manifest["regions"] if r["region"] == region)
    data = (directory / record["topologyFile"]).read_bytes()
    testcase.assertEqual(len(data), record["topologyBytes"])
    import hashlib
    testcase.assertEqual(hashlib.sha256(data).hexdigest(), record["topologySHA256"])
    decoded = topology.read_topology(data)
    testcase.assertEqual(decoded["region"], region)
    testcase.assertEqual(decoded["displaySHA256"].hex(), record["sha256"])
    testcase.assertEqual(decoded["packageSHA256"].hex(), manifest["packageSHA256"][region])
    package = json.loads((packages_dir / f"{region}-2025.json").read_text())
    package_lines = {line["id"]: line for line in package["lines"]}
    blob = (directory / record["file"]).read_bytes()
    display_by_line = {}
    for key, entry in manifest["lines"].items():
        if entry["region"] != region:
            continue
        chunk = entry["chunk"]
        display_by_line[entry["id"]] = json.loads(blob[chunk["offset"]:chunk["offset"] + chunk["length"]])
    # Lines are the display lines, in blob order.
    ordered = sorted(display_by_line, key=lambda line_id: manifest["lines"][f"{region}|{line_id}"]["chunk"]["offset"])
    testcase.assertEqual([line["id"] for line in decoded["lines"]], ordered)
    counts = {"nodes": 0, "edges": 0, "slice": 0, "noslot": 0}
    summary = json.loads((directory / "display-network-report.json").read_text())["regions"][region]["topology"]
    for name in ("unanchoredStations", "slotMismatches", "edgesWithoutGeometry"):
        testcase.assertEqual(summary[name]["count"], 0, f"{region} {name}: {summary[name]['first'][:5]}")
    testcase.assertEqual(summary["overviewAlignFailures"], 0)
    counts["lengthMismatch"] = {(row["line"], row["interval"]) for row in summary["lengthMismatchEdges"]["first"]}
    testcase.assertEqual(len(counts["lengthMismatch"]), summary["lengthMismatchEdges"]["count"])
    base = 0
    for line in decoded["lines"]:
        package_line_row = package_lines[line["id"]]
        stations = package_line_row["stations"]
        # every package station has a node, in station order
        testcase.assertEqual([n["code"] for n in line["nodes"]], [row[0] for row in stations], line["id"])
        loop = bool(package_line_row.get("isLoop"))
        testcase.assertEqual(len(line["edges"]), len(stations) if loop else len(stations) - 1)
        running = 0
        for index, edge in enumerate(line["edges"]):
            km = float(package_line_row["segments"][index][0])
            testcase.assertGreater(edge["lengthCm"], 0)
            testcase.assertEqual(edge["lengthCm"], topology.to_cm(km * 1000.0))
            testcase.assertEqual(edge["cumulativeCm"], running)
            running += edge["lengthCm"]
        testcase.assertEqual(line["firstNode"], base)
        base += len(line["nodes"])
        counts["nodes"] += len(line["nodes"])
        counts["edges"] += len(line["edges"])
        # slicing the display chunk at a node's metres lands on the station
        fragments = display_by_line[line["id"]]["lines"]
        continuous = not (line["flags"] & topology.LINE_NON_CONTINUOUS)
        station_records = {s["stationCode"]: s for s in display_by_line[line["id"]]["stations"]}
        rulers = {}
        if continuous:
            for fragment in fragments:
                points, _ = topology.join_parts(fragment["parts"])
                rulers[fragment["chain"]] = (points, topology.ruler(points))
        else:
            flat = 0
            for fragment in fragments:
                for part in fragment["parts"]:
                    rulers[flat] = (part, topology.ruler(part))
                    flat += 1
            testcase.assertEqual(line["chainCount"], flat)
        for node in line["nodes"]:
            if node["flags"] & topology.NODE_NO_CHAIN_SLOT:
                counts["noslot"] += 1
                testcase.assertEqual(node["full"], topology.UNSET)
                continue
            points, measures = rulers[node["chain"]]
            metres = node["full"] / 100
            testcase.assertLessEqual(metres, measures[-1] + 0.005)
            index = max(i for i, m in enumerate(measures) if m <= metres + 1e-9)
            if index == len(points) - 1:
                point = points[index]
            else:
                span = measures[index + 1] - measures[index]
                t = 0 if span == 0 else (metres - measures[index]) / span
                point = [points[index][0] + t * (points[index + 1][0] - points[index][0]),
                         points[index][1] + t * (points[index + 1][1] - points[index][1])]
            record_row = station_records.get(node["code"])
            if continuous and record_row is not None and record_row.get("slot"):
                chain, vertex = record_row["slot"]
                testcase.assertEqual(chain, node["chain"], (line["id"], node["code"]))
                expected = rulers[chain][0][vertex]
            else:
                row = next(r for r in stations if r[0] == node["code"])
                expected = [row[2], row[3]]
            testcase.assertLessEqual(metres_between(point, expected), 0.5, (line["id"], node["code"]))
            counts["slice"] += 1
        # runs address parts or chains that exist, with ordered ends inside the ruler
        for edge in line["edges"]:
            for run in edge["runs"]:
                testcase.assertIn(run["chain"], rulers)
                total = rulers[run["chain"]][1][-1]
                testcase.assertLessEqual(max(run["fullFrom"], run["fullTo"]) / 100, total + 0.005)
    return counts


class RealBuildTests(BuilderRunMixin, unittest.TestCase):
    @classmethod
    def tearDownClass(cls):
        if cls._temp is not None:
            cls._temp.cleanup()
            cls._temp = None
            cls._outputs = {}

    def test_every_station_has_a_node_every_edge_has_length_and_slices_land_on_stations(self):
        directory = self.build_once("first")
        for region in ("tw", "hk", "mo", "kr"):
            with self.subTest(region=region):
                counts = region_checks(self, directory, region, ROOT / "app/public/rail")
                self.assertGreater(counts["nodes"], 0)
                self.assertEqual(counts["lengthMismatch"], set())     # drawn length equals the surveyed length

    def test_same_input_gives_byte_identical_files(self):
        first, second = self.build_once("first"), self.build_once("second")
        for region in ("jp", "tw", "hk", "mo", "kr"):
            for suffix in ("topology.bin", "display.bin"):
                name = f"{region}.{suffix}"
                self.assertEqual((first / name).read_bytes(), (second / name).read_bytes(), name)

    def test_regions_without_reviewed_junctions_have_no_links(self):
        directory = self.build_once("first")
        manifest = load_build(directory)
        for record in manifest["regions"]:
            if record["region"] in ("tw", "hk", "mo", "kr"):
                decoded = topology.read_topology((directory / record["topologyFile"]).read_bytes())
                self.assertEqual(decoded["links"], [], record["region"])
                self.assertGreater(len(decoded["stops"]), 0)

    def test_the_display_blob_does_not_depend_on_the_topology_inputs(self):
        # The blobs are the same with and without the inputs the links are compiled from.
        directory = self.build_once("first")
        base = Path(self._temp.name)
        builder = _load("display_network_plain", RAILWAY / "build-display-network.py")
        plain = base / "plain"
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            builder.build(base / "rail", plain)
        for region in ("tw", "hk", "mo", "kr"):
            self.assertEqual((directory / f"{region}.display.bin").read_bytes(),
                             (plain / f"{region}.display.bin").read_bytes())

    def test_manifest_records_the_topology_file(self):
        directory = self.build_once("first")
        manifest = load_build(directory)
        for record in manifest["regions"]:
            if record["region"] == "cn":
                self.assertNotIn("topologyFile", record)
            elif record["region"] in ("tw", "hk", "mo", "kr", "jp"):
                self.assertEqual(record["topologyFile"], f"{record['region']}.topology.bin")
                self.assertEqual(record["topologyBytes"], (directory / record["topologyFile"]).stat().st_size)
        self.assertEqual(len(manifest["inputSHA256"]["topology/physical-rail-junctions.json"]), 64)


@unittest.skipUnless(os.environ.get("JTM_DISPLAY_BUILD_DIR"), "set JTM_DISPLAY_BUILD_DIR to a full builder output")
class FullBuildTests(unittest.TestCase):
    """The same invariants on a complete output including jp, plus the link rules."""

    def setUp(self):
        self.directory = Path(os.environ["JTM_DISPLAY_BUILD_DIR"])

    # Edges whose drawn length is far from the surveyed one in the source data
    # itself (tram stations placed along the track differently from the stored
    # kilometres). A list that may only shrink.
    KNOWN_LENGTH_MISMATCHES = {
        ("jp|jp-伊予鉄道-城北線", 4), ("jp|jp-伊予鉄道-城北線", 5), ("jp|jp-伊予鉄道-城北線", 6),
        ("jp|jp-伊予鉄道-花園線", 0), ("jp|jp-万葉線-高岡軌道線", 5), ("jp|jp-万葉線-高岡軌道線", 12),
    }

    def test_every_region(self):
        for region in ("jp", "tw", "hk", "mo", "kr"):
            with self.subTest(region=region):
                counts = region_checks(self, self.directory, region, ROOT / "app/public/rail")
                extra = counts["lengthMismatch"] - self.KNOWN_LENGTH_MISMATCHES
                self.assertEqual(extra, set())

    def test_no_link_exists_without_a_registry_or_through_service_row(self):
        junction_ids = {row["id"] for row in json.loads(
            (ROOT / "app/data/physical-rail-junctions.json").read_text())["junctions"]}
        through = json.loads((ROOT / "ios/RailKit/Sources/RailCore/Resources/japan-through-services.json").read_text())
        through_ids = {pattern["id"] for pattern in through["patterns"]}
        decoded = topology.read_topology((self.directory / "jp.topology.bin").read_bytes())
        self.assertGreater(len(decoded["links"]), 0)
        owner = {}
        for line_index, line in enumerate(decoded["lines"]):
            for ordinal in range(len(line["nodes"])):
                owner[line["firstNode"] + ordinal] = line_index
        for link in decoded["links"]:
            ids = junction_ids if link["kind"] == topology.LINK_PHYSICAL_JUNCTION else through_ids
            self.assertIn(link["registryID"], ids)
            self.assertNotEqual(owner[link["nodeA"]], owner[link["nodeB"]])


if __name__ == "__main__":
    unittest.main()
