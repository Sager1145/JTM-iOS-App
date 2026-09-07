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

    @staticmethod
    def whole_line_parts_by_region(region, *lines):
        """One `partsByRegion` "plain" row per line, covering every one of
        its intervals as a single part — the shape build-display-lanes.mjs
        emits for an ordinary line the network engine builds whole. Most
        fixtures in this module do not care about partIndex splitting at
        all; since a continuous-stroke line with no usable rows now fails
        the build unless its own `serviceStatus` explains the absence, a
        fixture that isn't testing that split needs a minimal row like this
        one just to keep building.
        """
        rows = []
        for line in lines:
            interval_count = len(line.get("segments") or [])
            if interval_count == 0:
                continue
            rows.append([
                line["id"], 0, 0, interval_count - 1,
                len(line.get("stations") or []), 0.0,
            ])
        return {region: rows}

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
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"jp": []},
            "partsByRegion": self.whole_line_parts_by_region(
                "jp", *package["lines"]),
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

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
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"jp": []},
            "partsByRegion": self.whole_line_parts_by_region(
                "jp", *package["lines"]),
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

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
        into the lane artefact as `releasedIntervalsByRegion`) is drawn like
        any other interval — released intervals were never dashed to begin
        with; every other withheld interval of the line stays dashed
        (`withheld` on its fragment), but still bridged into the same
        chain."""
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
            "partsByRegion": self.whole_line_parts_by_region("us", line),
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
            # Interval 2 was released, so nothing splits the chain any more:
            # all three intervals (A-B-C-D) bridge into one fragment. Interval
            # 0 is still blocked, so it alone shows up in `withheld`.
            self.assertEqual(len(fragments), 1)
            self.assertEqual(len(fragments[0]["parts"]), 3)
            self.assertEqual(fragments[0]["parts"][0][0], [-87.64, 41.88])
            self.assertEqual(len(fragments[0]["withheld"]), 1)
            self.assertEqual(fragments[0]["withheld"][0][0], 0.0)
            self.assertIsNotNone(manifest)

    def test_a_render_group_colour_override_replaces_only_the_listed_line(self):
        """`colorByRegion` (build-display-lanes.mjs, from na-render-groups.json
        `groups`) is an operator-collapse override — LIRR, Metro-North and
        Metrolink each draw their whole railroad in one group colour instead
        of each branch's own published GTFS hex. A line named in the table
        gets the group's colour and colorDark in the manifest's own line
        metadata (what fragments join against by `lineKey`); a line absent
        from it keeps the package's own colour untouched, exactly like the
        web's `colorOverrideByLine` in rail-network.js.
        """
        overridden = {
            "id": "us-overridden", "name": "Overridden", "operator": "Test Rail",
            "kind": "commuter", "rank": 0, "color": "#00985f", "colorDark": "#00d686",
            "stations": [
                ["a", "A", -87.64, 41.88, "A"],
                ["b", "B", -87.63, 41.88, "B"],
            ],
            "segments": [[1.0, 0, [[-87.64, 41.88], [-87.63, 41.88]]]],
        }
        plain = {
            "id": "us-plain", "name": "Plain", "operator": "Test Rail",
            "kind": "commuter", "rank": 0, "color": "#6e3219", "colorDark": "#af4f28",
            "stations": [
                ["c", "C", -87.60, 41.88, "C"],
                ["d", "D", -87.59, 41.88, "D"],
            ],
            "segments": [[1.0, 0, [[-87.60, 41.88], [-87.59, 41.88]]]],
        }
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [overridden, plain],
        }
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": []},
            "partsByRegion": self.whole_line_parts_by_region(
                "us", overridden, plain),
            "colorByRegion": {
                "us": {"us-overridden": {"color": "#0039a6", "colorDark": "#004ad6"}},
            },
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            manifest = display_network.build(rail, out)
            self.assertEqual(
                manifest["lines"]["us|us-overridden"]["color"], "#0039a6")
            self.assertEqual(
                manifest["lines"]["us|us-overridden"]["colorDark"], "#004ad6")
            # Unlisted: the package's own colour survives untouched.
            self.assertEqual(
                manifest["lines"]["us|us-plain"]["color"], "#6e3219")
            self.assertEqual(
                manifest["lines"]["us|us-plain"]["colorDark"], "#af4f28")

    def test_render_group_identity_is_carried_regardless_of_colour(self):
        """`renderGroupByRegion` (build-display-lanes.mjs's
        `deriveRenderGroupByRegion`, from na-render-groups.json's
        `byLineId`) names EVERY line the reviewed policy groups, not only
        the ones that also carry a colour override — most groups exist so
        several service names collapse onto one railway identity
        (rail-network.js's `railwayIdentityFor`), not to repaint anything.
        The manifest must carry that group id next to (but independent of)
        `color`, so the Swift side can mirror the same collapse: a grouped
        line with no colour override still gets its package colour AND its
        `renderGroup`; an ungrouped line gets neither a colour override nor
        a `renderGroup`.
        """
        grouped_no_color = {
            "id": "us-branch-a", "name": "Branch A", "operator": "Test Rail",
            "kind": "commuter", "rank": 0, "color": "#111111", "colorDark": "#222222",
            "stations": [
                ["a", "A", -87.64, 41.88, "A"],
                ["b", "B", -87.63, 41.88, "B"],
            ],
            "segments": [[1.0, 0, [[-87.64, 41.88], [-87.63, 41.88]]]],
        }
        grouped_with_color = {
            "id": "us-branch-b", "name": "Branch B", "operator": "Test Rail",
            "kind": "commuter", "rank": 0, "color": "#333333", "colorDark": "#444444",
            "stations": [
                ["c", "C", -87.62, 41.88, "C"],
                ["d", "D", -87.61, 41.88, "D"],
            ],
            "segments": [[1.0, 0, [[-87.62, 41.88], [-87.61, 41.88]]]],
        }
        ungrouped = {
            "id": "us-solo", "name": "Solo", "operator": "Test Rail",
            "kind": "commuter", "rank": 0, "color": "#6e3219", "colorDark": "#af4f28",
            "stations": [
                ["e", "E", -87.60, 41.88, "E"],
                ["f", "F", -87.59, 41.88, "F"],
            ],
            "segments": [[1.0, 0, [[-87.60, 41.88], [-87.59, 41.88]]]],
        }
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [grouped_no_color, grouped_with_color, ungrouped],
        }
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": []},
            "partsByRegion": self.whole_line_parts_by_region(
                "us", grouped_no_color, grouped_with_color, ungrouped),
            "colorByRegion": {
                "us": {"us-branch-b": {"color": "#0039a6", "colorDark": "#004ad6"}},
            },
            "renderGroupByRegion": {
                "us": {"us-branch-a": "test-branches", "us-branch-b": "test-branches"},
            },
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            manifest = display_network.build(rail, out)
            # Grouped, no colour override: keeps its own colour, gains the
            # group id.
            self.assertEqual(
                manifest["lines"]["us|us-branch-a"]["renderGroup"], "test-branches")
            self.assertEqual(
                manifest["lines"]["us|us-branch-a"]["color"], "#111111")
            # Grouped AND colour-overridden: both apply independently.
            self.assertEqual(
                manifest["lines"]["us|us-branch-b"]["renderGroup"], "test-branches")
            self.assertEqual(
                manifest["lines"]["us|us-branch-b"]["color"], "#0039a6")
            # Unlisted: neither a colour override nor a render group.
            self.assertIsNone(manifest["lines"]["us|us-solo"]["renderGroup"])
            self.assertEqual(
                manifest["lines"]["us|us-solo"]["color"], "#6e3219")

    def test_lane_rows_on_a_withheld_line_stay_inside_their_chain(self):
        """A blocked line's chains still line up with the web's own display
        parts one-for-one (a withheld interval bridges rather than splits,
        so most such lines are a single chain now — see
        `bridgeBlockedIntervals` in rail-network.js), so a blocked line may
        carry lanes and follows — keyed by the web's part, honoured here as
        the matching chain — but no row may ever reach past the chain it
        belongs to.

        Runs the real `build()` over the actual committed rail directory
        (not a synthetic package) so `chains_by_line` is the genuine
        `partsByRegion`-driven chain list for every line, including every
        withheld line's own canonical partners — the fail-closed guard in
        `chain_follow_rows`/`chain_lane_rows` means a mismatch anywhere in
        real data now raises rather than silently clipping to nothing, so
        simply completing without raising is itself part of what this test
        checks.
        """
        rail = Path(__file__).parents[3] / "public" / "rail"
        comparison_by_region = {}
        for region in ("us", "ca"):
            package = json.loads((rail / f"{region}-2025.json").read_text())
            comparison_by_region[region] = (
                (package.get("geometrySource") or {})
                .get("officialGeometryComparison", {})
                .get("byLine", {}))
        with tempfile.TemporaryDirectory() as root:
            out = Path(root) / "network"
            manifest = display_network.build(rail, out)
            self.assertIsNotNone(manifest)
            for region in ("us", "ca"):
                comparison = comparison_by_region[region]
                withheld_lines = {
                    line_id for line_id, entry in comparison.items()
                    if entry.get("displayBlockedIntervals")}
                payload = json.loads((out / f"{region}.json").read_text())
                fragments_by_line: dict[str, list[dict]] = {}
                for fragment in payload["lines"]:
                    line_id = fragment["lineKey"].split("|", 1)[1]
                    fragments_by_line.setdefault(line_id, []).append(fragment)
                for line_id in withheld_lines:
                    for fragment in fragments_by_line.get(line_id, []):
                        total = fragment["totalMetres"]
                        for row in fragment.get("laneRows") or []:
                            self.assertGreaterEqual(row[0], 0.0)
                            self.assertLessEqual(row[1], total + 0.2)
                        for row in fragment.get("follows") or []:
                            self.assertGreaterEqual(row[0], 0.0)
                            self.assertLessEqual(row[1], total + 0.2)

    def test_kensington_shared_track_follows_the_metra_physical_centreline(self):
        """South Shore rides Metra Electric's own tracks into Kensington.

        `excludedLineIds` (shared-corridors.json's reviewed policy) still
        names these three lines, on record for why they were once
        special-cased: a naive LANE offset produced false stubs and branch
        jumps where the physical corridor splits at the Kensington
        interlocking. But that is a complaint about the offset mechanism,
        not about drawing the corridor at all — build-display-lanes.mjs no
        longer treats the policy as a switch that suppresses every row for
        the lines it names. The correct fix for two independently-digitised
        strokes on one physical track is a FOLLOW row (rail-stroke.js draws
        the tenant from the landlord's own alignment instead of offsetting
        the tenant's noisier one), and `sharedTrackCanonicalLineId` in the
        compact package already records which line is the landlord here.
        """
        rail = SCRIPT.parents[2] / "public" / "rail"
        lanes = json.loads((rail / "display-lanes.json").read_text())
        package = json.loads((rail / "us-2025.json").read_text())
        lines = {line["id"]: line for line in package["lines"]}
        rows = lanes["byRegion"]["us"]
        follows = lanes.get("followsByRegion", {}).get("us", [])
        kensington_lines = {
            "metra-me",
            "south-shore-line-lakeshore",
            "south-shore-line-monon",
        }
        self.assertEqual(
            set(lanes.get("excludedLineIds", [])),
            kensington_lines,
        )
        # Every one of the three now takes part in the corridor: either it
        # carries its own lane row, or it is a follower of one of the others
        # (metra-me, the landlord, is neither — it is only ever followed).
        offset = {row[0] for row in rows}
        followers = {row[0] for row in follows}
        self.assertTrue(kensington_lines <= (offset | followers))
        # The follow direction matches the reviewed landlord, not whichever
        # source label the generic provenance heuristic would rank highest.
        for tenant in ("south-shore-line-lakeshore", "south-shore-line-monon"):
            self.assertEqual(
                lines[tenant]["sharedTrackCanonicalLineId"], "metra-me")
        lakeshore_follows_metra = any(
            row[0] == "south-shore-line-lakeshore" and row[4] == "metra-me"
            for row in follows)
        self.assertTrue(lakeshore_follows_metra)
        metra_never_follows = all(row[0] != "metra-me" for row in follows)
        self.assertTrue(metra_never_follows)

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

    def test_a_branch_shard_follows_its_own_trunk_below_the_follow_length_gate(self):
        """A branch shares its trunk's track by definition, however short.

        FOLLOW_MIN_RUN_METRES (build-display-lanes.mjs) exists to stop two
        UNRELATED lines that merely cross paths for a block from reading as a
        shared corridor. It used to apply to a `branchOf` shard just the
        same, so a short-turn streetcar variant whose entire length is under
        that window could never generate a follow row for the trunk it is a
        published subset of — the two were drawn as independent, stacked
        strokes. `isKin` (build-display-lanes.mjs) now exempts a line from
        its own trunk (or a sibling branch of the same trunk) from that
        length gate. FOLLOW_MIN_RUN_METRES is 1000 m, and every branch
        named below runs shorter than that against its own trunk:
        ttc-510-b2 (146 m) is the shortest of the CA branch shards stacked
        on their trunk, and new-orleans-rta-12-b2 (517 m) is its US
        analogue. The TTC ids here are the day-route identities (504/506/
        510); they were 304/306/310 before the Blue Night numbering was
        corrected, and the branch shards were renumbered with them, so do
        not assume b5 here is the b5 that was here before.
        """
        rail = SCRIPT.parents[2] / "public" / "rail"
        lanes = json.loads((rail / "display-lanes.json").read_text())
        ca_follows = lanes.get("followsByRegion", {}).get("ca", [])
        us_follows = lanes.get("followsByRegion", {}).get("us", [])

        def follows_its_trunk(follows, branch, trunk):
            return any(
                row[0] == branch and row[4] == trunk for row in follows)

        for branch in (
                "ttc-506-b1", "ttc-506-b2", "ttc-506-b3",
                "ttc-506-b4", "ttc-506-b6", "ttc-506-b7", "ttc-506-b8"):
            self.assertTrue(
                follows_its_trunk(ca_follows, branch, "ttc-506"),
                f"{branch} should follow its trunk ttc-506")
        self.assertTrue(follows_its_trunk(ca_follows, "ttc-504-b5", "ttc-504"))
        self.assertTrue(follows_its_trunk(ca_follows, "ttc-510-b1", "ttc-510"))
        self.assertTrue(follows_its_trunk(ca_follows, "ttc-510-b2", "ttc-510"))
        self.assertTrue(
            follows_its_trunk(
                us_follows, "new-orleans-rta-12-b2", "new-orleans-rta-12"))

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
        # Amtrak is one display class, so it takes one lane on the open
        # corridor — a lane that differed between two Amtrak services there
        # would fan the intercity network out into its timetable. Convergence
        # hubs (display-hubs.json, computeHubOverrides in
        # build-display-lanes.mjs) are the one deliberate exception: several
        # render-key classes can converge on one platform throat over a
        # window shorter than the corridor pass's own MIN_RUN_METRES, and
        # every Amtrak member there still takes the SAME hub-assigned slot as
        # every other Amtrak member — the class stays one stroke, it simply
        # is not always -0.5 while it is inside a several-hundred-metre
        # throat. So the invariant is not "exactly one lane value region
        # wide" but "one lane value carries essentially all of it": the
        # dominant value's own share of the total Amtrak-drawn length must
        # stay in the high nineties, with hub throats accounting for the
        # remainder.
        amtrak_rows = [
            row for row in lanes["byRegion"]["us"]
            if by_id.get(row[0], {}).get("operator") == "Amtrak"
        ]
        length_by_lane: dict[float, float] = {}
        total_length = 0.0
        for _, _, low, high, lane in amtrak_rows:
            length_by_lane[lane] = length_by_lane.get(lane, 0.0) + (high - low)
            total_length += high - low
        self.assertGreater(total_length, 0.0)
        dominant_lane, dominant_length = max(
            length_by_lane.items(), key=lambda item: item[1])
        self.assertGreaterEqual(
            dominant_length / total_length, 0.95,
            f"dominant lane {dominant_lane} only covers "
            f"{dominant_length / total_length:.1%} of Amtrak's drawn length: "
            f"{length_by_lane}")
        # Chicago Union's south approach is the representative terminal:
        # Metra BNSF takes its own screen-space lane through the throat, and
        # that lane is not the one it settles into on the open corridor
        # beyond it. This used to assert the throat lane is specifically
        # nonzero, which convergence hubs (display-hubs.json) made stale the
        # same way as the Amtrak check above: which numeric slot a class
        # lands in among a hub's other members depends on how many classes
        # converge there and in what order (computeHubOverrides,
        # build-display-lanes.mjs), a reviewed policy detail this test
        # should not pin a specific number to. What must still hold is that
        # there IS a hub-forced lane distinct from the general one.
        bnsf_rows = sorted(
            (row for row in lanes["byRegion"]["us"] if row[0] == "metra-bnsf"),
            key=lambda row: row[2])
        self.assertTrue(bnsf_rows)
        self.assertEqual(bnsf_rows[0][2], 0)
        self.assertTrue(any(row[4] != bnsf_rows[0][4] for row in bnsf_rows[1:]))

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
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"jp": []},
            "partsByRegion": self.whole_line_parts_by_region(
                "jp", *package["lines"]),
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
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
            "partsByRegion": self.whole_line_parts_by_region(
                "us", *package["lines"]),
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

    def _branch_line_package_and_chains(self):
        """A 3-station, 2-interval line where `partsByRegion` names a split
        (one part per interval) that the raw-interval-only splitter
        (`continuous_chains`) would never produce on its own — neither
        interval is empty or withheld, so without `partsByRegion` this line
        would build as ONE chain. Stands in for a real branch/retrace/
        reversal cut on the web: what matters for this test is only that the
        web's part count (2) and this module's own splitter's part count (1)
        disagree, which is exactly the situation `partsByRegion` exists to
        reconcile.
        """
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [{
                "id": "branch-line", "name": "Branch Line", "operator": "Test Rail",
                "rank": 0, "color": "#123456",
                "stations": [
                    ["a", "A", -87.64, 41.88, "A"],
                    ["b", "B", -87.62, 41.88, "B"],
                    ["c", "C", -87.60, 41.88, "C"],
                ],
                "segments": [
                    [2.0, 0, [[-87.64, 41.88], [-87.62, 41.88]]],
                    [2.0, 0, [[-87.62, 41.88], [-87.60, 41.88]]],
                ],
            }],
        }
        parts_by_region = {"us": [
            ["branch-line", 0, 0, 0, 2, 1656.5],
            ["branch-line", 1, 1, 1, 2, 1656.5],
        ]}
        return package, parts_by_region

    def test_parts_by_region_splits_a_line_the_interval_only_splitter_would_not(self):
        """Two `partsByRegion` rows for one line build two native chains —
        matching the web's own part count — even though the raw intervals
        alone give this module's old splitter no reason to cut at all."""
        package, parts_by_region = self._branch_line_package_and_chains()
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": [
                ["branch-line", 0, 0, 5000, 1],
                ["branch-line", 1, 0, 5000, -1],
            ]},
            "partsByRegion": parts_by_region,
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            manifest = display_network.build(rail, out)
            self.assertIsNotNone(manifest)
            payload = json.loads((out / "us.json").read_text())
            fragments = sorted(
                (f for f in payload["lines"] if f["lineKey"] == "us|branch-line"),
                key=lambda f: f["chain"])
            # partIndex parity: exactly one chain per `partsByRegion` row, in
            # the same order — not the one merged chain the raw-interval
            # splitter alone would have produced.
            self.assertEqual([f["chain"] for f in fragments], [0, 1])
            self.assertEqual(len(fragments), 2)
            for fragment in fragments:
                # Each chain is ONE interval (~1656 m at this latitude), not
                # the whole ~3313 m line — proof the split actually happened
                # rather than one chain merely being reported twice.
                self.assertLess(fragment["totalMetres"], 2000.0)
                self.assertGreater(fragment["totalMetres"], 1000.0)
            # Each part's own lane row landed on its own chain, not on the
            # other chain or nowhere at all.
            self.assertEqual([row[2] for row in fragments[0]["laneRows"]], [1.0])
            self.assertEqual([row[2] for row in fragments[1]["laneRows"]], [-1.0])
            stations = {s["id"]: s for s in payload["stations"]}
            self.assertEqual(stations["branch-line:a"]["slot"], [0, 0])
            self.assertEqual(stations["branch-line:b"]["slot"], [0, 1])
            self.assertEqual(stations["branch-line:c"]["slot"], [1, 1])

    def test_an_orphan_lane_row_raises_instead_of_being_dropped(self):
        """A lane row naming a partIndex with no matching chain used to be
        silently skipped (the `partIndex >= len(chains)` bug this whole
        mechanism exists to close). It must now stop the build instead."""
        package, parts_by_region = self._branch_line_package_and_chains()
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": [
                ["branch-line", 0, 0, 5000, 1],
                # partIndex 2 does not exist — only parts 0 and 1 do.
                ["branch-line", 2, 0, 5000, -1],
            ]},
            "partsByRegion": parts_by_region,
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            with self.assertRaises(RuntimeError) as context:
                display_network.build(rail, out)
            message = str(context.exception)
            self.assertIn("branch-line", message)
            self.assertIn("partIndex", message)

    def test_a_withheld_interval_bridges_the_chain_and_keeps_the_rows_together(self):
        """A withheld interval is the alignment gate's verdict on the
        geometry, not on whether it may be drawn — the stroke stays one
        chain, the middle interval's own span lands in `withheld`, and the
        reviewed lane rows (all keyed to the web's one display part now that
        nothing splits it) stay in one piece too."""
        # Rows are keyed by the web's display part and measured from that
        # part's start: bridging means there is only ever part 0 here.
        rows = [[None, 0, 0.0, 1000.0, -1.0], [None, 0, 1000.0, 3000.0, 0.5]]
        intervals = [
            [[0.0, 0.0], [0.01, 0.0]],
            [[0.01, 0.0], [0.02, 0.0]],
            [[0.02, 0.0], [0.03, 0.0]],
        ]
        chains = display_network.continuous_chains(intervals, {1})
        self.assertEqual([c["firstInterval"] for c in chains], [0])
        self.assertEqual([c["partIndex"] for c in chains], [0])
        self.assertEqual(
            chains[0]["anchorIndexByStation"], {0: 0, 1: 1, 2: 2, 3: 3})
        # The middle interval (~1113 m) is the one that was withheld.
        self.assertEqual(len(chains[0]["withheld"]), 1)
        self.assertAlmostEqual(chains[0]["withheld"][0][0], 1113.2, places=1)
        self.assertAlmostEqual(chains[0]["withheld"][0][1], 2226.4, places=1)
        rows_out = display_network.chain_lane_rows(rows, chains[0])
        self.assertEqual([row[2] for row in rows_out], [-1.0, 0.5])
        self.assertEqual(rows_out[0][0], 0.0)
        self.assertAlmostEqual(rows_out[0][1], rows_out[1][0], places=1)
        self.assertLessEqual(rows_out[1][1], chains[0]["endMetres"] + 0.2)

    def test_withheld_station_interval_is_bridged_not_dropped(self):
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
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": []},
            "partsByRegion": self.whole_line_parts_by_region("us", line),
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
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            manifest = display_network.build(rail, out)

            self.assertEqual(manifest["built"]["alignmentWithheldIntervals"], 1)
            self.assertEqual(manifest["built"]["alignmentWithheldLines"], 1)
            self.assertEqual(
                manifest["lines"]["us|us-test"]["withheldDisplayIntervals"],
                [1])
            points = set()
            fragments = []
            payload = json.loads((out / "us.json").read_text())
            for drawn in payload["lines"]:
                if drawn["lineKey"] == "us|us-test":
                    fragments.append(drawn)
                    points.update(tuple(point) for part in drawn["parts"]
                                  for point in part)
            # The blocked interval (B→C) is real, surveyed geometry — only
            # withheld from the official-alignment comparison, not missing —
            # so it draws through like any other interval rather than being
            # dropped. One bridged fragment, both stations on it, and the
            # interval's own span recorded in `withheld` for the renderer to
            # dash instead of cut.
            self.assertIn((-121.9, 48.0), points)
            self.assertIn((-121.8, 48.1), points)
            self.assertEqual(len(fragments), 1)
            self.assertEqual(len(fragments[0]["parts"]), 2)
            self.assertEqual(len(fragments[0]["withheld"]), 1)
            self.assertGreater(fragments[0]["withheld"][0][0], 0.0)
            self.assertAlmostEqual(
                fragments[0]["withheld"][0][1], fragments[0]["totalMetres"],
                places=1)

    @staticmethod
    def embedded_withheld_case(blocked):
        """A four-station line whose single display part is a fallback
        (embedded-geometry) `partsByRegion` row, with `blocked` withheld.

        The row shape is the one build-display-lanes.mjs emits when a part
        cannot be described as a plain run of whole raw intervals: -1/-1 for
        the interval range, then the part's own final vertices in slot 7.
        """
        line = {
            "id": "us-test", "name": "Test", "operator": "Test Rail",
            "kind": "regional", "rank": 0, "color": "#123456",
            "stations": [
                ["a", "A", -122.0, 48.0, "A"],
                ["b", "B", -121.9, 48.0, "B"],
                ["c", "C", -121.8, 48.0, "C"],
                ["d", "D", -121.7, 48.0, "D"],
            ],
            "segments": [
                [8.0, 0, [[-122.0, 48.0], [-121.9, 48.0]]],
                [8.0, 0, [[-121.9, 48.0], [-121.8, 48.0]]],
                [8.0, 0, [[-121.8, 48.0], [-121.7, 48.0]]],
            ],
        }
        coordinates = [
            [-122.0, 48.0], [-121.9, 48.0], [-121.8, 48.0], [-121.7, 48.0],
        ]
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [line],
            "geometrySource": {"officialGeometryComparison": {"byLine": {
                "us-test": {"displayBlockedIntervals": list(blocked)},
            }}},
        }
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": []},
            "partsByRegion": {"us": [[
                "us-test", 0, -1, -1, len(coordinates), 0.0,
                "complex", coordinates,
            ]]},
        }
        return package, lanes

    def test_embedded_part_keeps_its_withheld_spans(self):
        """A blocked interval on an embedded-geometry part must still reach
        the renderer as a dashed span.

        This is the regression. A fallback `partsByRegion` row has no raw
        interval range to accumulate withheld spans against, and
        `chain_from_embedded_coordinates` used to answer that by handing
        back an empty `withheld` — so the alignment gate's verdict was
        dropped and the stretch drew as a confident SOLID line over track
        the gate had refused to confirm. On the shipped packages that
        silently released 1,808 km across ten lines, amtrak-acela among
        them, whose every display part is a fallback row.

        The spans are located on the part's own vertices instead, through
        the station anchors `anchor_indices_for_polyline` already finds
        there, which is the same answer rail-network.js reaches from the
        other side by tagging the vertices a blocked interval contributed.
        """
        package, lanes = self.embedded_withheld_case([1])
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                if region != "us":
                    copy["geometrySource"] = {}
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            display_network.build(rail, out)

            payload = json.loads((out / "us.json").read_text())
            fragments = [drawn for drawn in payload["lines"]
                         if drawn["lineKey"] == "us|us-test"]
            self.assertEqual(len(fragments), 1)
            spans = fragments[0]["withheld"]
            self.assertEqual(len(spans), 1)
            # Station B to station C: the middle third of a part whose three
            # intervals are the same length, so the span runs from a third
            # of the way along to two thirds.
            total = fragments[0]["totalMetres"]
            self.assertAlmostEqual(spans[0][0], total / 3.0, delta=1.0)
            self.assertAlmostEqual(spans[0][1], 2.0 * total / 3.0, delta=1.0)

    def test_embedded_part_merges_touching_withheld_spans(self):
        """Two adjacent blocked intervals on an embedded part are one dashed
        run, not two abutting ones — the same shape `merged_withheld_spans`
        gives the other two chain builders, and the same shape
        rail-network.js's own vertex tagging produces for the web."""
        package, lanes = self.embedded_withheld_case([0, 1])
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                if region != "us":
                    copy["geometrySource"] = {}
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            display_network.build(rail, out)

            payload = json.loads((out / "us.json").read_text())
            fragments = [drawn for drawn in payload["lines"]
                         if drawn["lineKey"] == "us|us-test"]
            spans = fragments[0]["withheld"]
            self.assertEqual(len(spans), 1)
            self.assertAlmostEqual(spans[0][0], 0.0, places=1)
            self.assertAlmostEqual(
                spans[0][1], 2.0 * fragments[0]["totalMetres"] / 3.0, delta=1.0)

    def test_an_unplaceable_withheld_interval_fails_the_build(self):
        """A blocked interval no display part can carry fails the build.

        Drawing a withheld stretch dashed is honest; drawing it solid is a
        false claim about surveyed track, so a verdict that cannot be
        placed must stop the build rather than quietly vanish — the failure
        this whole path exists to make impossible. Here the part's embedded
        geometry does not pass through station D at all, so the last
        interval has no anchor to hang its span on.
        """
        package, lanes = self.embedded_withheld_case([2])
        lanes["partsByRegion"]["us"][0][7] = [
            [-122.0, 48.0], [-121.9, 48.0], [-121.8, 48.0],
        ]
        lanes["partsByRegion"]["us"][0][4] = 3
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                if region != "us":
                    copy["geometrySource"] = {}
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            with self.assertRaises(RuntimeError) as raised:
                display_network.build(rail, out)
        self.assertIn("draw solid", str(raised.exception))

    def test_a_released_interval_is_not_expected_on_an_embedded_part(self):
        """A reviewed release opens the interval, so nothing is left to
        place and the fail-closed check must not fire on it. The release
        table is the one legitimate way a blocked interval stops being
        drawn dashed (a reviewed shared corridor replacing the geometry is
        the other); the bug this file guards against is the flag going away
        without one."""
        package, lanes = self.embedded_withheld_case([1])
        lanes["releasedIntervalsByRegion"] = {"us": [["us-test", 1]]}
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                if region != "us":
                    copy["geometrySource"] = {}
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            manifest = display_network.build(rail, out)

            self.assertNotIn(
                "withheldDisplayIntervals", manifest["lines"]["us|us-test"])
            payload = json.loads((out / "us.json").read_text())
            fragments = [drawn for drawn in payload["lines"]
                         if drawn["lineKey"] == "us|us-test"]
            self.assertEqual(fragments[0]["withheld"], [])

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
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": []},
            "partsByRegion": self.whole_line_parts_by_region("us", a, b),
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
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
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": []},
            "partsByRegion": self.whole_line_parts_by_region("us", a, b),
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "shared-corridors.json").write_text(json.dumps(reviewed))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
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

    def test_continuous_chains_with_nothing_withheld_is_one_chain(self):
        """Every station anchors the right vertex of the concatenated
        polyline, and shared endpoints between intervals are not doubled."""
        intervals = [
            [[0.0, 0.0], [1.0, 0.0]],
            [[1.0, 0.0], [2.0, 0.0], [3.0, 0.0]],
            [[3.0, 0.0], [4.0, 0.0]],
        ]
        chains = display_network.continuous_chains(intervals, set())
        self.assertEqual(len(chains), 1)
        chain = chains[0]
        self.assertEqual(chain["partIndex"], 0)
        self.assertEqual(chain["firstInterval"], 0)
        self.assertEqual(
            chain["polyline"],
            [[0.0, 0.0], [1.0, 0.0], [2.0, 0.0], [3.0, 0.0], [4.0, 0.0]])
        self.assertEqual(
            chain["anchorIndexByStation"], {0: 0, 1: 1, 2: 3, 3: 4})

    def test_continuous_chains_withheld_first_interval_still_bridges(self):
        """A withheld interval no longer opens a gap in the chain — it is
        drawn through, like any other interval, and its own span lands in
        `withheld` (metres, this chain's own measure space)."""
        intervals = [
            [[0.0, 0.0], [1.0, 0.0]],
            [[1.0, 0.0], [2.0, 0.0]],
            [[2.0, 0.0], [3.0, 0.0]],
        ]
        chains = display_network.continuous_chains(intervals, {0})
        self.assertEqual(len(chains), 1)
        self.assertEqual(chains[0]["firstInterval"], 0)
        self.assertEqual(chains[0]["partIndex"], 0)
        self.assertEqual(chains[0]["anchorIndexByStation"][0], 0)
        self.assertEqual(len(chains[0]["withheld"]), 1)
        self.assertEqual(chains[0]["withheld"][0][0], 0.0)
        self.assertAlmostEqual(
            chains[0]["withheld"][0][1],
            display_network.lane_measure_length(intervals[0]), places=1)

    def test_continuous_chains_two_withheld_intervals_stay_one_bridged_chain(self):
        """Two withheld intervals that are not adjacent (something real sits
        between them) still bridge into ONE chain, and produce two SEPARATE
        withheld spans rather than one merged run."""
        intervals = [
            [[0.0, 0.0], [1.0, 0.0]],
            [[1.0, 0.0], [2.0, 0.0]],
            [[2.0, 0.0], [2.0, 1.0]],
            [[2.0, 1.0], [3.0, 1.0]],
            [[3.0, 1.0], [4.0, 1.0]],
        ]
        chains = display_network.continuous_chains(intervals, {1, 3})
        self.assertEqual(len(chains), 1)
        self.assertEqual(chains[0]["partIndex"], 0)
        self.assertEqual(len(chains[0]["parts"]), 5)
        self.assertEqual(len(chains[0]["withheld"]), 2)
        self.assertLess(chains[0]["withheld"][0][1], chains[0]["withheld"][1][0])

    def test_continuous_chains_short_interval_is_treated_like_withheld(self):
        """An interval with fewer than two points cannot anchor a chain, so
        it breaks the run the same way an explicitly withheld one does."""
        intervals = [
            [[0.0, 0.0], [1.0, 0.0]],
            [[1.0, 0.0]],
            [[2.0, 0.0], [3.0, 0.0]],
        ]
        chains = display_network.continuous_chains(intervals, set())
        self.assertEqual([c["firstInterval"] for c in chains], [0, 2])

    def test_chain_lane_rows_keys_clips_and_drops_out_of_range_rows(self):
        chain = {"partIndex": 0, "startMetres": 100.0, "endMetres": 600.0}
        rows = [
            [None, 0, -50.0, 200.0, 2.0],   # applies, clipped at the start
            [None, 0, 400.0, 700.0, 3.0],   # applies, clipped at the end
            [None, 1, 0.0, 300.0, 9.0],     # wrong web part -> dropped
            [None, 0, 600.0, 900.0, 5.0],   # entirely past the chain -> dropped
        ]
        result = display_network.chain_lane_rows(rows, chain)
        self.assertEqual(result, [[0.0, 200.0, 2.0], [400.0, 500.0, 3.0]])

    def test_chain_follow_rows_clips_and_interpolates_canonical_measures(self):
        chain = {"partIndex": 0, "startMetres": 0.0, "endMetres": 1000.0}
        canon_chain = {"partIndex": 0, "startMetres": 0.0, "endMetres": 2000.0}
        chains_by_line = {"A": [canon_chain]}
        follows = [
            # Clipped at the start; the canonical range runs the same way.
            ["B", 0, -100.0, 500.0, "A", 0, 50.0, 450.0],
            # Not clipped; the canonical range runs the opposite way.
            ["B", 0, 100.0, 500.0, "A", 0, 450.0, 50.0],
            # A different web part than this chain's own -> dropped.
            ["B", 1, 0.0, 100.0, "A", 0, 0.0, 100.0],
        ]
        out = display_network.chain_follow_rows(follows, chain, chains_by_line, "us")
        self.assertEqual(len(out), 2)
        forward = out[0]
        self.assertEqual(forward[:2], [0.0, 500.0])
        self.assertEqual(forward[2], "us|A")
        self.assertEqual(forward[3], 0)
        self.assertAlmostEqual(forward[4], 116.7, places=1)
        self.assertEqual(forward[5], 450.0)
        reversed_row = out[1]
        self.assertEqual(reversed_row[:2], [100.0, 500.0])
        self.assertEqual(reversed_row[2], "us|A")
        self.assertEqual(reversed_row[4], 450.0)
        self.assertEqual(reversed_row[5], 50.0)

    def test_chain_follow_rows_fails_closed_on_a_missing_canonical_chain(self):
        """A follow naming a canonical partIndex with no matching chain used
        to be dropped silently — the same shape of bug `chains_from_parts_rows`
        exists to close on a line's own parts, just on the canonical side.
        Now it raises, naming the line, the row, and how many chains the
        canonical line actually has, so the mismatch cannot ship unnoticed.
        """
        chain = {"partIndex": 0, "startMetres": 0.0, "endMetres": 1000.0}
        canon_chain = {"partIndex": 0, "startMetres": 0.0, "endMetres": 2000.0}
        chains_by_line = {"A": [canon_chain]}
        follows = [
            # Names a canonical chain index that does not exist.
            ["B", 0, 100.0, 300.0, "A", 5, 0.0, 200.0],
        ]
        with self.assertRaises(RuntimeError) as context:
            display_network.chain_follow_rows(follows, chain, chains_by_line, "us", "B")
        message = str(context.exception)
        self.assertIn("B", message)
        self.assertIn("partIndex 5", message)

    def test_build_carries_follow_rows_onto_the_following_lines_fragment(self):
        """A follow row keyed to line B's own part clips to B's chain and its
        canonical measures re-base onto line A's chain; A itself, which
        nothing follows, carries none."""
        line_a = {
            "id": "A", "name": "A", "operator": "Test Rail", "kind": "commuter",
            "rank": 0, "color": "#123456",
            "stations": [
                ["a1", "A1", -87.64, 41.88, "A1"],
                ["a2", "A2", -87.60, 41.88, "A2"],
            ],
            "segments": [[4.0, 0, [[-87.64, 41.88], [-87.60, 41.88]]]],
        }
        line_b = {
            "id": "B", "name": "B", "operator": "Test Rail", "kind": "commuter",
            "rank": 0, "color": "#654321",
            "stations": [
                ["b1", "B1", -87.64, 41.881, "B1"],
                ["b2", "B2", -87.60, 41.881, "B2"],
            ],
            "segments": [[4.0, 0, [[-87.64, 41.881], [-87.60, 41.881]]]],
        }
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [line_a, line_b],
        }
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": []},
            "partsByRegion": self.whole_line_parts_by_region(
                "us", line_a, line_b),
            "followsByRegion": {"us": [["B", 0, 0.0, 1000.0, "A", 0, 0.0, 1000.0]]},
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            display_network.build(rail, out)

            payload = json.loads((out / "us.json").read_text())
            fragments = {f["lineKey"]: f for f in payload["lines"]}
            b_follows = fragments["us|B"]["follows"]
            self.assertEqual(len(b_follows), 1)
            self.assertEqual(b_follows[0][:2], [0.0, 1000.0])
            self.assertEqual(b_follows[0][2], "us|A")
            self.assertEqual(b_follows[0][3], 0)
            self.assertEqual(b_follows[0][4:6], [0.0, 1000.0])
            self.assertEqual(fragments["us|A"]["follows"], [])

    def test_family_windows_are_carried_and_their_colour_resolved(self):
        """`familyWindowsByRegion` (the web agent's `display-lanes.json`,
        rows `[lineId, partIndex, fromMetres, toMetres, role, groupId]`)
        lands on the fragment beside `withheld`, clipped to its chain like
        every other part-keyed row — and the group's colour, read straight
        out of `na-render-groups.json` rather than through any per-line
        override, lands in the payload's own `families` header block so the
        client never has to open a second file to draw the shared stroke.
        """
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [{
                "id": "tenant-line", "name": "Tenant Line", "operator": "Test Rail",
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
            "byRegion": {"us": []},
            "partsByRegion": self.whole_line_parts_by_region(
                "us", *package["lines"]),
            "familyWindowsByRegion": {
                "us": [["tenant-line", 0, 500.0, 2500.0, 1, "test-family"]],
            },
        }
        render_groups = {
            "format": display_network.NA_RENDER_GROUPS_FORMAT,
            "families": {
                "test-family": {"color": "#0039a6", "colorDark": "#004ad6"},
            },
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            (rail / "na-render-groups.json").write_text(json.dumps(render_groups))

            display_network.build(rail, out)

            payload = json.loads((out / "us.json").read_text())
            fragment = next(
                f for f in payload["lines"] if f["lineKey"] == "us|tenant-line")
            self.assertEqual(len(fragment["familyWindows"]), 1)
            window = fragment["familyWindows"][0]
            self.assertEqual(window[:2], [500.0, 2500.0])
            self.assertEqual(window[2], 1)
            self.assertEqual(window[3], "test-family")
            self.assertEqual(
                payload["families"]["test-family"],
                {"color": "#0039a6", "colorDark": "#004ad6"})
            # An untouched region carries no family palette at all.
            japan = json.loads((out / "jp.json").read_text())
            self.assertEqual(japan["families"], {})

    def test_an_orphan_family_window_raises_instead_of_being_dropped(self):
        """A family window naming a partIndex with no matching chain is the
        same disagreement `chains_from_parts_rows`'s orphan-partIndex check
        exists to catch for lane and follow rows — it must stop the build."""
        package, parts_by_region = self._branch_line_package_and_chains()
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"us": []},
            "partsByRegion": parts_by_region,
            "familyWindowsByRegion": {
                # partIndex 2 does not exist — only parts 0 and 1 do.
                "us": [["branch-line", 2, 0.0, 1000.0, 0, "test-family"]],
            },
        }
        render_groups = {
            "format": display_network.NA_RENDER_GROUPS_FORMAT,
            "families": {"test-family": {"color": "#0039a6", "colorDark": "#004ad6"}},
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            (rail / "na-render-groups.json").write_text(json.dumps(render_groups))
            with self.assertRaises(RuntimeError):
                display_network.build(rail, out)

    def test_a_family_window_naming_an_unresolvable_group_raises(self):
        """A family window naming a group `na-render-groups.json` gives no
        colour — including a build with no `na-render-groups.json` at all —
        fails closed rather than drawing the shared stroke in an unreviewed
        colour."""
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [{
                "id": "tenant-line", "name": "Tenant Line", "operator": "Test Rail",
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
            "byRegion": {"us": []},
            "familyWindowsByRegion": {
                "us": [["tenant-line", 0, 500.0, 2500.0, 1, "no-such-group"]],
            },
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            # Deliberately no na-render-groups.json on disk at all.
            with self.assertRaises(RuntimeError):
                display_network.build(rail, out)

    def test_a_family_window_resolves_against_its_own_regions_render_group_policy(self):
        """Two reviewed render-group policy files can each claim their own
        `scope` (na-render-groups.json: us/ca; jp-render-groups.json: jp) —
        a family window in one region must resolve its colour against THAT
        region's policy file, not the other one's, even when a group id of
        the same shape happens to appear in both."""
        package = {
            "format": "compact-v1", "version": "test", "country": "JP",
            "lines": [{
                "id": "jp-tenant-line", "name": "Tenant Line", "operator": "Test Rail",
                "rank": 0, "color": "#123456",
                "stations": [
                    ["a", "A", 139.70, 35.65, "A"],
                    ["b", "B", 139.72, 35.65, "B"],
                ],
                "segments": [[4.0, 0, [[139.70, 35.65], [139.71, 35.651], [139.72, 35.65]]]],
            }],
        }
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"jp": []},
            "partsByRegion": self.whole_line_parts_by_region(
                "jp", *package["lines"]),
            "familyWindowsByRegion": {
                "jp": [["jp-tenant-line", 0, 500.0, 2500.0, 1, "shared-family"]],
            },
        }
        na_render_groups = {
            "format": display_network.NA_RENDER_GROUPS_FORMAT,
            "scope": ["us", "ca"],
            "families": {"shared-family": {"color": "#111111", "colorDark": "#222222"}},
        }
        jp_render_groups = {
            "format": display_network.JP_RENDER_GROUPS_FORMAT,
            "scope": ["jp"],
            "families": {"shared-family": {"color": "#0039a6", "colorDark": "#004ad6"}},
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            (rail / "na-render-groups.json").write_text(json.dumps(na_render_groups))
            (rail / "jp-render-groups.json").write_text(json.dumps(jp_render_groups))

            display_network.build(rail, out)

            payload = json.loads((out / "jp.json").read_text())
            self.assertEqual(
                payload["families"]["shared-family"],
                {"color": "#0039a6", "colorDark": "#004ad6"})

    def test_two_render_group_policies_claiming_one_region_raises(self):
        """build-display-lanes.mjs raises when two reviewed render-group
        policy files both name the same region in their own `scope`; this
        reader checks the same invariant independently."""
        package = {
            "format": "compact-v1", "version": "test", "country": "US",
            "lines": [{
                "id": "tenant-line", "name": "Tenant Line", "operator": "Test Rail",
                "rank": 0, "color": "#123456",
                "stations": [
                    ["a", "A", -87.64, 41.88, "A"],
                    ["b", "B", -87.60, 41.88, "B"],
                ],
                "segments": [[4.0, 0, [[-87.64, 41.88], [-87.62, 41.881], [-87.60, 41.88]]]],
            }],
        }
        lanes = {"format": display_network.DISPLAY_LANES_FORMAT, "byRegion": {"us": []}}
        na_render_groups = {
            "format": display_network.NA_RENDER_GROUPS_FORMAT,
            "scope": ["us", "ca"],
            "families": {},
        }
        jp_render_groups = {
            "format": display_network.JP_RENDER_GROUPS_FORMAT,
            # Deliberately overlaps na-render-groups.json's own scope.
            "scope": ["jp", "us"],
            "families": {},
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "us").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            (rail / "na-render-groups.json").write_text(json.dumps(na_render_groups))
            (rail / "jp-render-groups.json").write_text(json.dumps(jp_render_groups))
            with self.assertRaises(RuntimeError):
                display_network.build(rail, out)

    def test_a_lane_row_on_a_reversed_loop_part_raises(self):
        """`reversedLoopParts` (build-display-lanes.mjs) names a `loop` part
        whose geometry was reversed to its canonical winding — the web
        builder itself refuses to also let that part carry a lane, follow,
        or family-window row, because their measures would then mirror
        rail-network.js's own (unreversed) part. This module checks the
        same invariant independently rather than trusting a
        display-lanes.json that might disagree with its own promise."""
        package = {
            "format": "compact-v1", "version": "test", "country": "JP",
            "lines": [{
                "id": "jp-loop-line", "name": "Loop Line", "operator": "Test Rail",
                "rank": 0, "color": "#123456", "isLoop": True,
                "stations": [
                    ["a", "A", 139.70, 35.65, "A"],
                    ["b", "B", 139.71, 35.66, "B"],
                    ["c", "C", 139.72, 35.65, "C"],
                ],
                "segments": [
                    [1.0, 0, [[139.70, 35.65], [139.71, 35.66]]],
                    [1.0, 0, [[139.71, 35.66], [139.72, 35.65]]],
                    [1.0, 0, [[139.72, 35.65], [139.70, 35.65]]],
                ],
            }],
        }
        coordinates = [
            [139.70, 35.65], [139.71, 35.66], [139.72, 35.65], [139.70, 35.65],
        ]
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {
                "jp": [["jp-loop-line", 0, 0.0, 100.0, 1.0]],
            },
            "partsByRegion": {
                "jp": [[
                    "jp-loop-line", 0, -1, -1, len(coordinates), 400.0,
                    "loop", coordinates,
                ]],
            },
            "reversedLoopParts": {"jp": ["jp-loop-line#0"]},
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            with self.assertRaises(RuntimeError):
                display_network.build(rail, out)

    def test_a_loop_seam_station_anchors_to_the_chains_own_start(self):
        """A closed loop's embedded `partsByRegion` polyline repeats its
        first vertex as its last (the seam), so the seam STATION's own
        coordinate matches two vertices, not one. Before this fix
        `anchor_indices_for_polyline`'s exact-match scan left a station like
        that with no `slot` at all — the real-world case is 大阪環状線's
        桜ノ宮 and the Disney Resort Line's own seam, both loop-seam
        stations whose bead used to land at its raw, un-offset coordinate
        instead of on the drawn stroke. The seam now anchors to the chain's
        own start (vertex 0), same as any other station reached at the very
        first interval."""
        package = {
            "format": "compact-v1", "version": "test", "country": "JP",
            "lines": [{
                "id": "jp-loop-line", "name": "Loop Line", "operator": "Test Rail",
                "rank": 0, "color": "#123456", "isLoop": True,
                "stations": [
                    ["a", "A", 139.70, 35.65, "A"],
                    ["b", "B", 139.71, 35.66, "B"],
                    ["c", "C", 139.72, 35.65, "C"],
                ],
                "segments": [
                    [1.0, 0, [[139.70, 35.65], [139.71, 35.66]]],
                    [1.0, 0, [[139.71, 35.66], [139.72, 35.65]]],
                    [1.0, 0, [[139.72, 35.65], [139.70, 35.65]]],
                ],
            }],
        }
        coordinates = [
            [139.70, 35.65], [139.71, 35.66], [139.72, 35.65], [139.70, 35.65],
        ]
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"jp": []},
            "partsByRegion": {
                "jp": [[
                    "jp-loop-line", 0, -1, -1, len(coordinates), 400.0,
                    "loop", coordinates,
                ]],
            },
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            display_network.build(rail, out)

            payload = json.loads((out / "jp.json").read_text())
            stations = {s["id"]: s for s in payload["stations"]}
            self.assertEqual(stations["jp-loop-line:a"]["slot"], [0, 0])
            # The interior stations are unaffected — plain exact matches.
            self.assertEqual(stations["jp-loop-line:b"]["slot"], [0, 1])
            self.assertEqual(stations["jp-loop-line:c"]["slot"], [0, 2])

    def test_a_continuous_station_far_from_every_chain_vertex_raises(self):
        """Every station of a continuous-stroke line must resolve to a
        `slot` — nothing upstream should ever leave a real gap, so this is
        a fail-closed net over a genuine data bug (a station whose recorded
        coordinate disagrees with the geometry by more than a rounding
        error), not an expected path. Uses the same embedded-coordinate
        chain as the loop-seam test above, since that is the only chain
        shape whose anchoring depends on the station's own coordinate at
        all — a `partsByRegion` "plain" row anchors by interval position,
        not by matching coordinates, and can never hit this gap."""
        package = {
            "format": "compact-v1", "version": "test", "country": "JP",
            "lines": [{
                "id": "jp-loop-line", "name": "Loop Line", "operator": "Test Rail",
                "rank": 0, "color": "#123456", "isLoop": True,
                "stations": [
                    ["a", "A", 139.70, 35.65, "A"],
                    # B's recorded coordinate is ~1.1 km from its real
                    # vertex (139.71, 35.66) below.
                    ["b", "B", 139.72, 35.67, "B"],
                    ["c", "C", 139.72, 35.65, "C"],
                ],
                "segments": [
                    [1.0, 0, [[139.70, 35.65], [139.71, 35.66]]],
                    [1.0, 0, [[139.71, 35.66], [139.72, 35.65]]],
                    [1.0, 0, [[139.72, 35.65], [139.70, 35.65]]],
                ],
            }],
        }
        coordinates = [
            [139.70, 35.65], [139.71, 35.66], [139.72, 35.65], [139.70, 35.65],
        ]
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"jp": []},
            "partsByRegion": {
                "jp": [[
                    "jp-loop-line", 0, -1, -1, len(coordinates), 400.0,
                    "loop", coordinates,
                ]],
            },
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            with self.assertRaises(RuntimeError) as failure:
                display_network.build(rail, out)
            self.assertIn("jp-loop-line:b", str(failure.exception))

    def test_a_servicestatus_split_line_draws_through_the_lane_path(self):
        """A line the JS network model declines to build into one stroke —
        recorded here by build-display-lanes.mjs's own
        `strokeExcludedByRegion` (a bus substitution or suspension over part
        or all of the line) — has no `partsByRegion` rows to build a chain
        from. It must still draw: through the same non-continuous,
        per-interval lane path tw/hk/mo/kr always use, exactly like the
        web's own "legacy multi-feature branch" for these lines. The
        exclusion reason need not start with "partial_" — a whole-line
        substitution is recorded the same way."""
        package = {
            "format": "compact-v1", "version": "test", "country": "JP",
            "lines": [{
                "id": "jp-split-line", "name": "Split Line", "operator": "Test Rail",
                "rank": 0, "color": "#123456",
                "serviceStatus": "substitute_bus",
                "stations": [
                    ["a", "A", 139.70, 35.65, "A"],
                    ["b", "B", 139.71, 35.66, "B"],
                ],
                "segments": [[1.0, 0, [[139.70, 35.65], [139.71, 35.66]]]],
            }],
        }
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"jp": []},
            "partsByRegion": {"jp": []},
            "strokeExcludedByRegion": {
                "jp": [["jp-split-line", "substitute_bus"]],
            },
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))

            display_network.build(rail, out)

            payload = json.loads((out / "jp.json").read_text())
            fragments = [
                f for f in payload["lines"] if f["lineKey"] == "jp|jp-split-line"]
            self.assertTrue(fragments)
            for fragment in fragments:
                self.assertNotIn("continuous", fragment)
                self.assertNotIn("chain", fragment)
            stations = {s["id"]: s for s in payload["stations"]}
            for station in stations.values():
                # No `slot` (that's the continuous-chain path this line no
                # longer takes). `station_lane` itself never records a lane
                # 0 (the default centreline, same as every plain tw/hk
                # station) — the point of this test is the absent `slot`,
                # not a lane override this fixture never asked for.
                self.assertNotIn("slot", station)

    def test_a_continuous_line_missing_rows_without_servicestatus_raises(self):
        """No `partsByRegion` rows and no `strokeExcludedByRegion` entry to
        explain the absence is a real gap — a stale or missing
        display-lanes.json, a checkout mid-migration — and must fail the
        build rather than silently drawing nothing or guessing a chain from
        raw intervals."""
        package = {
            "format": "compact-v1", "version": "test", "country": "JP",
            "lines": [{
                "id": "jp-mystery-line", "name": "Mystery Line", "operator": "Test Rail",
                "rank": 0, "color": "#123456",
                "stations": [
                    ["a", "A", 139.70, 35.65, "A"],
                    ["b", "B", 139.71, 35.66, "B"],
                ],
                "segments": [[1.0, 0, [[139.70, 35.65], [139.71, 35.66]]]],
            }],
        }
        lanes = {
            "format": display_network.DISPLAY_LANES_FORMAT,
            "byRegion": {"jp": []},
            "partsByRegion": {"jp": []},
        }
        with tempfile.TemporaryDirectory() as root:
            rail = Path(root) / "rail"
            out = Path(root) / "network"
            rail.mkdir()
            for region, copy in self.region_packages(package, "jp").items():
                (rail / f"{region}-2025.json").write_text(json.dumps(copy))
            (rail / "display-lanes.json").write_text(json.dumps(lanes))
            with self.assertRaises(RuntimeError) as failure:
                display_network.build(rail, out)
            self.assertIn("jp-mystery-line", str(failure.exception))

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
