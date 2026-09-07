import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "build-display-network.py"
SPEC = importlib.util.spec_from_file_location("display_network", SCRIPT)
display_network = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(display_network)


class DisplayNetworkTests(unittest.TestCase):
    @staticmethod
    def line(line_id, kind, station, coordinates):
        return {
            "id": line_id, "name": line_id, "operator": "Test Rail",
            "kind": kind, "rank": 0, "color": "#123456",
            "stations": [
                [station[0], "Shared", station[1], station[2], "Shared"],
                [f"{line_id}-far", "Far", coordinates[-1][0], coordinates[-1][1], "Far"],
            ],
            "segments": [[1.0, 0, coordinates]],
        }

    @staticmethod
    def region_packages(package, region_with_lines):
        """The seven shipped regions, with the lines in exactly one of them."""
        built = {}
        for region in display_network.REGIONS:
            copy = dict(package)
            copy["country"] = region.upper()
            copy["lines"] = package["lines"] if region == region_with_lines else []
            built[region] = copy
        return built

    def test_a_long_interval_crosses_a_tile_boundary_in_one_piece(self):
        """The whole point of the derivative: geometry is never cut up.

        139.70E-139.90E straddles the z10 storage boundary the old pyramid
        would have split this segment at, and 35.65N-35.75N straddles the
        z4 one. One part, both endpoints, no intermediate vertex invented.
        """
        package = {
            "format": "compact-v1", "version": "test", "country": "JP",
            "lines": [{
                "id": "jp-long", "name": "Long", "operator": "Test Rail",
                "rank": 0, "color": "#123456",
                "stations": [
                    ["a", "A", 139.70, 35.65, "A"],
                    ["b", "B", 139.90, 35.75, "B"],
                ],
                "segments": [[30.0, 0, [[139.70, 35.65], [139.90, 35.75]]]],
            }],
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))

            display_network.build(rail, out)

            payload = json.loads((out / "jp.json").read_text())
            parts = [
                part for line in payload["lines"]
                if line["lineKey"] == "jp|jp-long" for part in line["parts"]
            ]
            self.assertEqual(parts, [[[139.7, 35.65], [139.9, 35.75]]])

    def test_every_shipped_region_gets_one_file_and_one_index_entry(self):
        package = {
            "format": "compact-v1", "version": "test", "country": "JP",
            "lines": [{
                "id": "jp-test", "name": "Test", "operator": "Test Rail",
                "rank": 0, "color": "#123456",
                "stations": [
                    ["a", "A", 139.0, 35.0, "A"],
                    ["b", "B", 141.0, 36.0, "B"],
                ],
                "segments": [[200.0, 0, [[139.0, 35.0], [140.0, 35.5], [141.0, 36.0]]]],
            }],
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))

            manifest = display_network.build(rail, out)

            self.assertEqual(manifest["format"], display_network.FORMAT)
            self.assertEqual(
                [record["region"] for record in manifest["regions"]],
                list(display_network.REGIONS))
            self.assertEqual(
                sorted(path.name for path in out.iterdir()),
                sorted(["manifest.json"]
                       + [f"{region}.json" for region in display_network.REGIONS]))
            for record in manifest["regions"]:
                raw = (out / record["file"]).read_bytes()
                self.assertEqual(len(raw), record["bytes"])
                self.assertEqual(
                    display_network.hashlib.sha256(raw).hexdigest(), record["sha256"])
                self.assertEqual(json.loads(raw)["region"], record["region"])
            # Only Japan has geometry here, so only Japan has an extent — the
            # six empty regions must not advertise one, or the client would
            # read six national files for a camera off West Africa.
            japan = next(r for r in manifest["regions"] if r["region"] == "jp")
            self.assertEqual(
                (japan["minLon"], japan["minLat"], japan["maxLon"], japan["maxLat"]),
                (139.0, 35.0, 141.0, 36.0))
            # 200 km clears the ported length tier at MapLibre z3 but not the
            # finer wide-view ladder, which holds a line of that length to z4.
            self.assertEqual(japan["minZoomMapLibre"], 4)
            for record in manifest["regions"]:
                if record["region"] == "jp":
                    continue
                self.assertNotIn("minLon", record)

    def test_a_reviewed_alignment_release_opens_exactly_that_interval(self):
        """A withheld interval named by the reviewed release table (copied
        into the lane artefact as `releasedIntervalsByRegion`) is drawn
        again; every other withheld interval of the line stays absent."""
        line = {
            "id": "us-gate", "name": "Gate", "operator": "Test Rail",
            "kind": "commuter", "rank": 0, "color": "#123456",
            "stations": [
                ["a", "A", -87.64, 41.88, "A"],
                ["b", "B", -87.63, 41.88, "B"],
                ["c", "C", -87.62, 41.88, "C"],
                ["d", "D", -87.61, 41.88, "D"],
            ],
            "segments": [
                [1.0, 0, [[-87.64, 41.88], [-87.63, 41.88]]],
                [1.0, 0, [[-87.63, 41.88], [-87.62, 41.88]]],
                [1.0, 0, [[-87.62, 41.88], [-87.61, 41.88]]],
            ],
        }
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [line],
            "geometrySource": {"officialGeometryComparison": {"byLine": {
                "us-gate": {"displayBlockedIntervals": [0, 2]}}}},
        }
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": []},
            "releasedIntervalsByRegion": {"us": [["us-gate", 2]]},
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            manifest = display_network.build(rail, out)
            payload = json.loads((out / "us.json").read_text())
            fragments = [f for f in payload["lines"] if f["lineKey"] == "us|us-gate"]
            # Interval 0 stays withheld, so the chain starts at B; intervals
            # 1 and 2 form one chain because 2 was released.
            self.assertEqual(len(fragments), 1)
            self.assertEqual(len(fragments[0]["parts"]), 2)
            self.assertEqual(fragments[0]["parts"][0][0], [-87.63, 41.88])
            self.assertIsNotNone(manifest)

    def test_lane_rows_on_a_withheld_line_stay_inside_their_chain(self):
        """A withheld interval splits the display parts on both clients at the
        same place, so a blocked line may carry lanes and follows — keyed by
        the web's part, honoured here as the matching chain — but no row may
        ever reach past the chain it belongs to, and none may bridge the gap."""
        rail = Path(__file__).parents[3] / "public" / "rail"
        lanes = json.loads((rail / "display-lanes.json").read_text())
        for region in ("us", "ca"):
            package = json.loads((rail / f"{region}-2025.json").read_text())
            comparison = (
                (package.get("geometrySource") or {})
                .get("officialGeometryComparison", {})
                .get("byLine", {}))
            withheld_lines = {
                line_id for line_id, entry in comparison.items()
                if entry.get("displayBlockedIntervals")}
            rows = [row for row in lanes["byRegion"].get(region, [])
                    if row[0] in withheld_lines]
            follows = [row for row in lanes.get("followsByRegion", {}).get(region, [])
                       if row[0] in withheld_lines]
            for line in package["lines"]:
                if line["id"] not in withheld_lines:
                    continue
                withheld = set(comparison[line["id"]]["displayBlockedIntervals"])
                chains = display_network.continuous_chains(
                    display_network.decoded_intervals(line), withheld)
                self.assertEqual(
                    [chain["partIndex"] for chain in chains], list(range(len(chains))))
                for chain in chains:
                    total = chain.get("endMetres", chain["startMetres"]) - chain["startMetres"]
                    for row in display_network.chain_lane_rows(
                            [r for r in rows if r[0] == line["id"]], chain):
                        self.assertGreaterEqual(row[0], 0.0)
                        self.assertLessEqual(row[1], total + 0.2)
                    for row in display_network.chain_follow_rows(
                            [r for r in follows if r[0] == line["id"]], chain, {}, region):
                        self.assertGreaterEqual(row[0], 0.0)
                        self.assertLessEqual(row[1], total + 0.2)

    def test_kensington_shared_track_has_no_synthetic_display_lanes(self):
        rail = SCRIPT.parents[2] / "public" / "rail"
        lanes = json.loads((rail / "display-lanes.json").read_text())
        rows = lanes["byRegion"]["us"]
        offset = {row[0] for row in rows}
        kensington_lines = {
            "metra-me",
            "south-shore-line-lakeshore",
            "south-shore-line-monon",
        }
        self.assertEqual(
            set(lanes.get("excludedLineIds", [])),
            kensington_lines,
        )
        self.assertFalse(kensington_lines & offset)

    def test_kensington_services_use_the_metra_physical_centreline(self):
        rail = SCRIPT.parents[2] / "public" / "rail"
        package = json.loads((rail / "us-2025.json").read_text())
        lines = {line["id"]: line for line in package["lines"]}
        junction = [-87.612401, 41.683519]

        def path(line_id):
            points = []
            for piece in display_network.decoded_intervals(lines[line_id]):
                display_network.append_distinct(points, piece)
            return points

        def vertex_nearest(points, target):
            return min(
                range(len(points)),
                key=lambda index: display_network.equirectangular_metres(
                    {"lon": points[index][0], "lat": points[index][1]},
                    {"lon": target[0], "lat": target[1]}),
            )

        def cut_from_start(points, target):
            distance, segment, ratio = min(
                (display_network.point_segment_projection(target, first, second)[0],
                 index,
                 display_network.point_segment_projection(target, first, second)[1])
                for index, (first, second) in enumerate(
                    zip(points, points[1:]))
            )
            self.assertLess(distance, 0.2)
            first, second = points[segment], points[segment + 1]
            cut = [
                first[0] + (second[0] - first[0]) * ratio,
                first[1] + (second[1] - first[1]) * ratio,
            ]
            return points[:segment + 1] + [cut]

        def maximum_distance(points, reference):
            return max(
                min(display_network.point_segment_projection(point, first, second)[0]
                    for first, second in zip(reference, reference[1:]))
                for point in points
            )

        metra = path("metra-me")
        lakeshore = path("south-shore-line-lakeshore")
        monon = path("south-shore-line-monon")
        metra_spine = cut_from_start(metra, junction)
        lakeshore_spine = lakeshore[:vertex_nearest(lakeshore, junction) + 1]
        monon_spine = monon[vertex_nearest(monon, junction):]

        for member_spine in (lakeshore_spine, monon_spine):
            self.assertLess(maximum_distance(member_spine, metra_spine), 0.2)
            self.assertLess(maximum_distance(metra_spine, member_spine), 0.2)
        self.assertEqual(
            lines["south-shore-line-lakeshore"]
            ["sharedTrackCanonicalLineId"],
            "metra-me",
        )
        self.assertEqual(
            lines["south-shore-line-monon"]["sharedTrackCanonicalLineId"],
            "metra-me",
        )

    def test_a_lane_change_is_a_drift_and_never_a_step(self):
        """The reader must see one stroke moving, not a stroke cut in two.

        A lane offset is applied per drawn piece, so a change of lane is a
        change of piece — and the ONLY thing that keeps the two pieces reading
        as one railway is that the offset between them is smaller than the ink
        that draws them. Quarter lanes are well under a pixel at every scale
        lanes are drawn at; a whole lane is not, and three lanes at once (which
        Newark's approach asks for) is a visible break.
        """
        rows = [
            [None, 0, 0.0, 4000.0, 3.0],
            [None, 0, 4000.0, 9000.0, -3.0],
            [None, 0, 12000.0, 18000.0, -0.5],
        ]
        profile = display_network.ramped_lane_rows(rows, 20000.0)
        self.assertTrue(profile)
        for (_, _, before), (_, _, after) in zip(profile, profile[1:]):
            self.assertLessEqual(
                abs(after - before),
                display_network.LANE_RAMP_QUANTUM + 1e-9,
                f"{before} -> {after} is a step, not a drift",
            )
        # ...and the profile covers the part end to end, with nothing between
        # its pieces for the geometry to fall through.
        self.assertEqual(profile[0][0], 0.0)
        self.assertAlmostEqual(profile[-1][1], 20000.0)
        for (_, end, _), (start, _, _) in zip(profile, profile[1:]):
            self.assertAlmostEqual(start, end)

    def test_a_row_covering_a_whole_part_leaves_no_stub_behind(self):
        """One lane over one part is ONE piece — a stroke that cannot break.

        Rows are rounded to a tenth of a metre and re-measured downstream, so a
        row covering a whole part still ends a metre or two short of it. That
        remainder is not evidence of a lane change and must not become one.
        """
        profile = display_network.ramped_lane_rows(
            [[None, 0, 0.0, 99998.0, -2.0]], 100000.0)
        self.assertEqual(profile, [(0.0, 100000.0, -2.0)])

    def test_north_american_lanes_group_services_by_operator_kind_and_color(self):
        rail = SCRIPT.parents[2] / "public" / "rail"
        lanes = json.loads((rail / "display-lanes.json").read_text())
        self.assertEqual(
            lanes.get("northAmericaGrouping"),
            ["operator", "color"],
        )
        # Nobody is excluded from the corridor pass. Amtrak and VIA share
        # their whole eastern network with commuter operators, and holding
        # them on the commuter centreline hid one railway under the other
        # everywhere they run together.
        self.assertEqual(lanes.get("excludedOperators"), [])

        package = json.loads((rail / "us-2025.json").read_text())
        by_id = {line["id"]: line for line in package["lines"]}
        offset_ids = {row[0] for row in lanes["byRegion"]["us"]}
        # Amtrak's shared stretches take a lane of their own. One display
        # class still covers every Amtrak service, so the named services stay
        # co-linear WITH EACH OTHER while the class as a whole moves clear of
        # the commuter railways it shares track with.
        self.assertTrue(any(
            line_id in offset_ids
            and by_id[line_id].get("operator") == "Amtrak"
            for line_id in by_id
        ))
        canada = json.loads((rail / "ca-2025.json").read_text())
        ca_by_id = {line["id"]: line for line in canada["lines"]}
        ca_offset_ids = {row[0] for row in lanes["byRegion"]["ca"]}
        self.assertTrue(any(
            line_id in ca_offset_ids
            and ca_by_id[line_id].get("operator", "").lower().startswith("via rail")
            for line_id in ca_by_id
        ))
        # Every Amtrak lane row carries the same lane, because they are one
        # display class: a lane that differed between two Amtrak services
        # would fan the intercity network out into its timetable.
        amtrak_lanes = {
            row[4] for row in lanes["byRegion"]["us"]
            if by_id.get(row[0], {}).get("operator") == "Amtrak"
        }
        self.assertEqual(len(amtrak_lanes), 1, amtrak_lanes)
        # Chicago Union's south approach is the representative terminal:
        # Metra BNSF takes a screen-space lane from the station onward.
        self.assertTrue(any(
            row[0] == "metra-bnsf"
            and row[2] == 0
            and row[4] != 0
            for row in lanes["byRegion"]["us"]
        ))

    def test_small_package_build_records_source_completeness(self):
        package = {
            "format": "compact-v1", "version": "test", "country": "JP",
            "lines": [{
                "id": "jp-test", "name": "Test", "operator": "Test Rail",
                "rank": 0, "color": "#123456",
                "stations": [
                    ["jp-official-a", "A", 139.0, 35.0, "A"],
                    ["jp-official-b", "B", 141.0, 36.0, "B"],
                ],
                "segments": [[200.0, 0, [[139.0, 35.0], [140.0, 35.5], [141.0, 36.0]]]],
            }],
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            manifest = display_network.build(rail, out)
            self.assertEqual(manifest["source"]["lines"], 1)
            self.assertEqual(manifest["source"]["segments"], 2)
            # Two source segments, one station interval, one part: the
            # derivative neither loses geometry nor invents a break in it.
            self.assertEqual(manifest["built"]["parts"], 1)
            self.assertEqual(manifest["built"]["vertices"], 3)
            for record in manifest["regions"]:
                raw = (out / record["file"]).read_bytes()
                self.assertEqual(display_network.hashlib.sha256(raw).hexdigest(), record["sha256"])
                payload = json.loads(raw)
                for line in payload["lines"]:
                    self.assertTrue(all(len(part) >= 2 for part in line["parts"]))

    def test_display_lane_is_carried_by_line_fragments_and_stations(self):
        """North America draws continuous strokes: the fragment carries the
        reviewed lane rows in metres and each platform the vertex it sits on;
        the offset itself is baked in on device (RailCore ContinuousStroke)."""
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [{
                "id": "city-loop", "name": "City Loop", "operator": "City Rail",
                "rank": 0, "color": "#123456",
                "stations": [
                    ["a", "A", -87.64, 41.88, "A"],
                    ["b", "B", -87.60, 41.88, "B"],
                ],
                "segments": [[4.0, 0, [[-87.64, 41.88], [-87.62, 41.881], [-87.60, 41.88]]]],
            }],
        }
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": [["city-loop", 0, 0, 5000, 1]]},
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            manifest = display_network.build(rail, out)
            payloads = [
                json.loads((out / record["file"]).read_text())
                for record in manifest["regions"]
            ]
            fragments = [
                line for payload in payloads for line in payload["lines"]
                if line["lineKey"] == "us|city-loop"
            ]
            stations = {
                station["id"]: station
                for payload in payloads for station in payload["stations"]
            }
            self.assertEqual(len(fragments), 1)
            fragment = fragments[0]
            self.assertTrue(fragment["continuous"])
            self.assertEqual(fragment["lane"], 0.0)
            self.assertEqual(fragment["chain"], 0)
            # The row is clipped to the chain it falls in and re-based on it.
            self.assertEqual(len(fragment["laneRows"]), 1)
            self.assertEqual(fragment["laneRows"][0][0], 0.0)
            self.assertAlmostEqual(
                fragment["laneRows"][0][1], fragment["totalMetres"], places=1)
            self.assertEqual(fragment["laneRows"][0][2], 1.0)
            # One uncut part per interval; the platforms are its two ends.
            self.assertEqual(len(fragment["parts"]), 1)
            self.assertEqual(stations["city-loop:a"]["slot"], [0, 0])
            self.assertEqual(stations["city-loop:b"]["slot"], [0, 2])
            self.assertNotIn("lane", stations["city-loop:a"])

    def test_a_withheld_interval_breaks_the_chain_and_rebases_the_rows(self):
        """A withheld interval is the alignment gate's verdict and still cuts
        the stroke; the chains either side each carry their own share of the
        rows, measured from their own start."""
        # Rows are keyed by the web's display part and measured from that
        # part's start: the gate splits the line into two parts here too.
        rows = [[None, 0, 0.0, 1000.0, -1.0], [None, 1, 0.0, 600.0, -1.0], [None, 1, 600.0, 2000.0, 0.5]]
        intervals = [
            [[0.0, 0.0], [0.01, 0.0]],
            [[0.01, 0.0], [0.02, 0.0]],
            [[0.02, 0.0], [0.03, 0.0]],
        ]
        chains = display_network.continuous_chains(intervals, {1})
        self.assertEqual([c["firstInterval"] for c in chains], [0, 2])
        self.assertEqual([c["partIndex"] for c in chains], [0, 1])
        self.assertEqual(chains[0]["anchorIndexByStation"], {0: 0, 1: 1})
        self.assertEqual(chains[1]["anchorIndexByStation"], {2: 0, 3: 1})
        first = display_network.chain_lane_rows(rows, chains[0])
        second = display_network.chain_lane_rows(rows, chains[1])
        self.assertEqual([row[2] for row in first], [-1.0])
        self.assertEqual(first[0][0], 0.0)
        # ...and a row is clipped to its chain: the second part is ~1113 m.
        self.assertEqual([row[2] for row in second], [-1.0, 0.5])
        self.assertEqual(second[0][0], 0.0)
        self.assertAlmostEqual(second[0][1], second[1][0], places=1)
        self.assertLessEqual(second[1][1], 1200.0)

    def test_unverified_station_interval_is_not_written_to_the_display_network(self):
        line = {
            "id": "us-test", "name": "Test", "operator": "Test Rail",
            "kind": "regional", "rank": 0, "color": "#123456",
            "stations": [
                ["a", "A", -122.0, 48.0, "A"],
                ["b", "B", -121.9, 48.0, "B"],
                ["c", "C", -121.8, 48.1, "C"],
            ],
            "segments": [
                [8.0, 0, [[-122.0, 48.0], [-121.9, 48.0]]],
                [12.0, 1, [[-121.8, 48.1]]],
            ],
        }
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [line],
            "geometrySource": {"officialGeometryComparison": {"byLine": {
                "us-test": {"displayBlockedIntervals": [1]},
            }}},
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region in display_network.REGIONS:
                copy = dict(package)
                copy["country"] = region.upper()
                copy["lines"] = package["lines"] if region == "us" else []
                if region != "us":
                    copy["geometrySource"] = {}
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))

            manifest = display_network.build(rail, out)

            self.assertEqual(manifest["built"]["alignmentWithheldIntervals"], 1)
            self.assertEqual(manifest["built"]["alignmentWithheldLines"], 1)
            self.assertEqual(
                manifest["lines"]["us|us-test"]["withheldDisplayIntervals"],
                [1])
            points = set()
            payload = json.loads((out / "us.json").read_text())
            for drawn in payload["lines"]:
                if drawn["lineKey"] == "us|us-test":
                    points.update(tuple(point) for part in drawn["parts"]
                                  for point in part)
            self.assertIn((-121.9, 48.0), points)
            self.assertNotIn((-121.8, 48.1), points)

    def test_display_derivative_preserves_shared_station_anchors_and_geometry(self):
        a = self.line("a", "commuter", ("shared", -71.0, 42.0), [
            [-71.0, 42.0], [-70.995, 42.0], [-70.990, 42.0], [-70.985, 42.0],
        ])
        b = self.line("b", "commuter", ("shared", -71.0, 42.0003), [
            [-71.0, 42.0003], [-70.995, 42.00025], [-70.990, 42.0002],
            [-70.985, 42.004],
        ])
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [a, b],
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            manifest = display_network.build(rail, out)
            self.assertEqual(manifest["built"]["sharedCorridors"], {
                "groups": 0, "arms": 0, "mergedStations": 0,
                "snappedMetres": 0.0, "releasedIntervals": 0,
                "unresolvedGroups": 0,
            })
            stations = {}
            points = {"us|a": set(), "us|b": set()}
            payload = json.loads((out / "us.json").read_text())
            for station in payload["stations"]:
                stations[station["id"]] = (station["lon"], station["lat"])
            for line in payload["lines"]:
                points[line["lineKey"]].update(
                    tuple(point) for part in line["parts"] for point in part)
            self.assertEqual(stations["a:shared"], (-71.0, 42.0))
            self.assertEqual(stations["b:shared"], (-71.0, 42.0003))
            self.assertIn((-71.0, 42.0), points["us|a"])
            self.assertIn((-71.0, 42.0003), points["us|b"])
            source_by_key = {
                "us|a": a["segments"][0][2],
                "us|b": b["segments"][0][2],
            }
            for key, drawn_points in points.items():
                source = source_by_key[key]
                for point in drawn_points:
                    self.assertTrue(any(
                        self.point_is_on_segment(point, first, second)
                        for first, second in zip(source, source[1:])),
                        f"{key} gained off-source display vertex {point}")

    def test_reviewed_same_kind_corridor_uses_one_station_arm(self):
        a = self.line("a", "commuter", ("shared", -71.0, 42.0), [
            [-71.0, 42.0], [-70.995, 42.0], [-70.990, 42.0],
            [-70.985, 42.004],
        ])
        b = self.line("b", "commuter", ("shared", -71.0, 42.0003), [
            [-71.0, 42.0003], [-70.995, 42.00025], [-70.990, 42.0002],
            [-70.985, 42.008],
        ])
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [a, b],
        }
        reviewed = {
            "format": "jtm-shared-corridors-v1",
            "corridors": [{
                "id": "reviewed-test-corridor", "region": "us",
                "kind": "commuter", "canonicalLineId": "a",
                "mergeStation": True,
                "maxStationSeparationMeters": 50,
                "maxCutSeparationMeters": 50,
                "evidence": [
                    {"type": "operator-gtfs", "url": "https://example.test/gtfs"},
                    {"type": "osm-track", "url": "https://example.test/osm"},
                ],
                "members": [
                    {"lineId": "a", "stationCode": "shared",
                     "intervalIndex": 0, "side": "start",
                     "cut": [-70.990, 42.0]},
                    {"lineId": "b", "stationCode": "shared",
                     "intervalIndex": 0, "side": "start",
                     "cut": [-70.990, 42.0002]},
                ],
            }],
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "shared-corridors.json").write_text(json.dumps(reviewed))
            manifest = display_network.build(rail, out)
            stats = manifest["built"]["sharedCorridors"]
            self.assertEqual(stats["groups"], 1)
            self.assertEqual(stats["arms"], 2)
            self.assertEqual(stats["mergedStations"], 1)
            self.assertGreater(stats["snappedMetres"], 0)

            stations = {}
            points = {"us|a": set(), "us|b": set()}
            payload = json.loads((out / "us.json").read_text())
            for station in payload["stations"]:
                stations[station["id"]] = (station["lon"], station["lat"])
            for line in payload["lines"]:
                points[line["lineKey"]].update(
                    tuple(point) for part in line["parts"] for point in part)
            self.assertEqual(stations["a:shared"], (-71.0, 42.0))
            self.assertEqual(stations["b:shared"], (-71.0, 42.0))
            self.assertIn((-70.995, 42.0), points["us|b"])
            self.assertNotIn((-70.995, 42.00025), points["us|b"])

    def test_reviewed_cut_station_welds_two_local_intervals_to_express_arm(self):
        express = {
            "id": "express", "name": "Express", "operator": "Test Rail",
            "kind": "commuter", "rank": 0, "color": "#123456",
            "stations": [
                ["a", "A", -71.0, 42.0, "A"],
                ["b", "B", -70.98, 42.0, "B"],
            ],
            "segments": [[1.0, 0, [
                [-71.0, 42.0], [-70.99, 42.0], [-70.98, 42.0],
            ]]],
        }
        local = {
            "id": "local", "name": "Local", "operator": "Test Rail",
            "kind": "commuter", "rank": 0, "color": "#654321",
            "stations": [
                ["a", "A", -71.0, 42.0001, "A"],
                ["middle", "Middle", -70.99, 42.0002, "Middle"],
                ["b", "B", -70.98, 42.0001, "B"],
            ],
            "segments": [
                [0.5, 0, [[-71.0, 42.0001], [-70.99, 42.0002]]],
                [0.5, 0, [[-70.99, 42.0002], [-70.98, 42.0001]]],
            ],
        }
        intervals = {
            "express": display_network.decoded_intervals(express),
            "local": display_network.decoded_intervals(local),
        }
        evidence = [{"type": "operator"}, {"type": "government-gis"}]
        corridors = [
            {
                "id": "a-to-middle", "region": "us", "kind": "commuter",
                "canonicalLineId": "express", "mergeStation": True,
                "maxStationSeparationMeters": 50,
                "maxCutSeparationMeters": 50, "evidence": evidence,
                "members": [
                    {"lineId": "express", "stationCode": "a",
                     "intervalIndex": 0, "side": "start",
                     "cut": [-70.99, 42.0]},
                    {"lineId": "local", "stationCode": "a",
                     "cutStationCode": "middle", "intervalIndex": 0,
                     "side": "start", "cut": [-70.99, 42.0002]},
                ],
            },
            {
                "id": "middle-to-b", "region": "us", "kind": "commuter",
                "canonicalLineId": "express", "mergeStation": True,
                "maxStationSeparationMeters": 50,
                "maxCutSeparationMeters": 50, "evidence": evidence,
                "members": [
                    {"lineId": "express", "stationCode": "b",
                     "intervalIndex": 0, "side": "end",
                     "cut": [-70.99, 42.0]},
                    {"lineId": "local", "stationCode": "b",
                     "cutStationCode": "middle", "intervalIndex": 1,
                     "side": "end", "cut": [-70.99, 42.0]},
                ],
            },
        ]

        stats = display_network.apply_shared_corridors(
            "us", {"lines": [express, local]}, intervals, corridors)

        self.assertEqual(stats["groups"], 2)
        self.assertEqual(local["stations"][1][2:4], [-70.99, 42.0])
        self.assertEqual(intervals["local"][0], [
            [-71.0, 42.0], [-70.99, 42.0],
        ])
        self.assertEqual(intervals["local"][1], [
            [-70.99, 42.0], [-70.98, 42.0],
        ])
        self.assertNotIn([-70.99, 42.0002], intervals["local"][0])
        self.assertNotIn([-70.99, 42.0002], intervals["local"][1])

    def test_reviewed_full_interval_reuses_one_path_in_both_directions(self):
        a = {
            "id": "a", "name": "a", "operator": "Test Rail",
            "kind": "lightrail", "rank": 0, "color": "#123456",
            "stations": [
                ["first", "First", -71.0, 42.0, "First"],
                ["second", "Second", -70.99, 42.0, "Second"],
            ],
            "segments": [[1.0, 0, [
                [-71.0, 42.0], [-70.995, 42.0], [-70.99, 42.0],
            ]]],
        }
        b = {
            "id": "b", "name": "b", "operator": "Test Rail",
            "kind": "lightrail", "rank": 0, "color": "#654321",
            "stations": [
                ["second", "Second", -70.99, 42.0002, "Second"],
                ["first", "First", -71.0, 42.0002, "First"],
            ],
            "segments": [[1.0, 0, [
                [-70.99, 42.0002], [-70.995, 42.0002], [-71.0, 42.0002],
            ]]],
        }
        intervals = {
            "a": display_network.decoded_intervals(a),
            "b": display_network.decoded_intervals(b),
        }
        corridor = {
            "id": "reviewed-full-interval", "region": "us",
            "kind": "lightrail", "mergeStation": True,
            "maxStationSeparationMeters": 50,
            "evidence": [{"type": "operator"}, {"type": "osm"}],
            "intervals": [{
                "stationCodes": ["first", "second"],
                "canonicalLineId": "a", "lineIds": ["a", "b"],
            }],
        }

        stats = display_network.apply_shared_corridors(
            "us", {"lines": [a, b]}, intervals, [corridor])

        self.assertEqual(stats["groups"], 1)
        self.assertEqual(stats["arms"], 2)
        self.assertEqual(stats["mergedStations"], 2)
        self.assertEqual(intervals["a"][0], [
            [-71.0, 42.0], [-70.995, 42.0], [-70.99, 42.0],
        ])
        self.assertEqual(intervals["b"][0], [
            [-70.99, 42.0], [-70.995, 42.0], [-71.0, 42.0],
        ])
        self.assertEqual(b["stations"][0][2:4], [-70.99, 42.0])
        self.assertEqual(b["stations"][1][2:4], [-71.0, 42.0])

    def test_reviewed_corridor_rejects_different_railway_types(self):
        a = self.line("a", "commuter", ("shared", -71.0, 42.0), [
            [-71.0, 42.0], [-70.99, 42.0],
        ])
        b = self.line("b", "highspeed", ("shared", -71.0, 42.0), [
            [-71.0, 42.0], [-70.99, 42.0],
        ])
        intervals = {
            "a": display_network.decoded_intervals(a),
            "b": display_network.decoded_intervals(b),
        }
        corridor = {
            "id": "mixed-kind", "region": "us", "kind": "commuter",
            "canonicalLineId": "a",
            "evidence": [{"type": "official"}, {"type": "osm"}],
            "members": [
                {"lineId": "a", "stationCode": "shared", "intervalIndex": 0,
                 "side": "start", "cut": [-70.99, 42.0]},
                {"lineId": "b", "stationCode": "shared", "intervalIndex": 0,
                 "side": "start", "cut": [-70.99, 42.0]},
            ],
        }
        with self.assertRaisesRegex(RuntimeError, "not reviewed kind"):
            display_network.apply_shared_corridors(
                "us", {"lines": [a, b]}, intervals, [corridor])

    def test_reviewed_interval_uses_unblocked_canonical_and_releases_member(self):
        a = self.line("a", "intercity", ("shared", -71.0, 42.0), [
            [-71.0, 42.0], [-70.99, 42.0],
        ])
        b = self.line("b", "intercity", ("shared", -71.0, 42.0002), [
            [-71.0, 42.0002], [-70.99, 42.0002],
        ])
        package = {
            "lines": [a, b],
            "geometrySource": {"officialGeometryComparison": {"byLine": {
                "a": {"displayBlockedIntervals": [0]},
                "b": {"displayBlockedIntervals": []},
            }}},
        }
        intervals = {
            "a": display_network.decoded_intervals(a),
            "b": display_network.decoded_intervals(b),
        }
        corridor = {
            "id": "reviewed-shared-track", "region": "us",
            "kind": "intercity", "mergeStation": True,
            "maxStationSeparationMeters": 50,
            "evidence": [{"type": "operator"}, {"type": "government-gis"}],
            "lineIds": ["a", "b"],
            "canonicalLinePriority": ["a", "b"],
            "stationPairs": [["shared", "a-far"]],
        }
        # Give both services the same identity at the far end, as real shared
        # Amtrak station intervals do.
        b["stations"][1][0] = "a-far"
        released = set()

        stats = display_network.apply_shared_corridors(
            "us", package, intervals, [corridor], released)

        self.assertEqual(stats["groups"], 1)
        self.assertEqual(stats["releasedIntervals"], 1)
        self.assertEqual(released, {("a", 0)})
        self.assertEqual(intervals["a"][0], intervals["b"][0])

    def test_reviewed_interval_stays_unresolved_when_every_source_is_blocked(self):
        a = self.line("a", "intercity", ("shared", -71.0, 42.0), [
            [-71.0, 42.0], [-70.99, 42.0],
        ])
        b = self.line("b", "intercity", ("shared", -71.0, 42.0002), [
            [-71.0, 42.0002], [-70.99, 42.0002],
        ])
        b["stations"][1][0] = "a-far"
        package = {
            "lines": [a, b],
            "geometrySource": {"officialGeometryComparison": {"byLine": {
                "a": {"displayBlockedIntervals": [0]},
                "b": {"displayBlockedIntervals": [0]},
            }}},
        }
        intervals = {
            "a": display_network.decoded_intervals(a),
            "b": display_network.decoded_intervals(b),
        }
        original = {key: [point[:] for point in value[0]]
                    for key, value in intervals.items()}
        corridor = {
            "id": "unresolved-shared-track", "region": "us",
            "kind": "intercity",
            "evidence": [{"type": "operator"}, {"type": "government-gis"}],
            "lineIds": ["a", "b"],
            "stationPairs": [["shared", "a-far"]],
        }

        stats = display_network.apply_shared_corridors(
            "us", package, intervals, [corridor])

        self.assertEqual(stats["groups"], 0)
        self.assertEqual(stats["unresolvedGroups"], 1)
        self.assertEqual(intervals["a"][0], original["a"])
        self.assertEqual(intervals["b"][0], original["b"])

    @staticmethod
    def point_is_on_segment(point, first, second, tolerance=2e-7):
        dx, dy = second[0] - first[0], second[1] - first[1]
        px, py = point[0] - first[0], point[1] - first[1]
        length_squared = dx * dx + dy * dy
        if length_squared == 0:
            return abs(px) <= tolerance and abs(py) <= tolerance
        parameter = (px * dx + py * dy) / length_squared
        if parameter < -tolerance or parameter > 1 + tolerance:
            return False
        nearest = (first[0] + parameter * dx, first[1] + parameter * dy)
        return abs(point[0] - nearest[0]) <= tolerance \
            and abs(point[1] - nearest[1]) <= tolerance


if __name__ == "__main__":
    unittest.main()
