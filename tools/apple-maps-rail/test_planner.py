import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
from planner import apply_network_extents, _geometry_bounds, _line_matches_city, _line_segments, _load_lines, _segment_intersects_rect, plan_tiles
from audit_coverage import _supplement_resolves, audit, line_covered, rectangle_covered


def city(city_id="test", bounds=None):
    return {"id": city_id, "country": "US", "bounds": bounds or [[0.0, 0.0, 0.1, 0.1]]}


def line(line_id, operator, kind, coordinates):
    return {"id": line_id, "operator": operator, "kind": kind, "segments": [[0, 0, coordinates]]}


class PlannerTests(unittest.TestCase):
    def rail_file(self, lines):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "rail.json"
        path.write_text(json.dumps({"lines": lines}), encoding="utf-8")
        return path

    def test_long_segment_is_sampled_without_gaps(self):
        path = self.rail_file([line("local", "Example Transit", "light_rail", [[0.05, 0.05], [0.95, 0.05]])])
        tiles = plan_tiles([city(bounds=[[0, 0, 0.1, 0.1]])], width_m=1000, height_m=1000,
                           overlap=0.2, rail_files=[path])
        centers = sorted(tile["lon"] for tile in tiles if tile["rail_lines"] == ["local"] and abs(tile["lat"] - 0.05) < 0.03)
        self.assertGreater(len(centers), 50)
        self.assertLess(max(b - a for a, b in zip(centers, centers[1:])), 0.02)

    def test_amtrak_excluded_lirr_included_and_full_line_kept(self):
        path = self.rail_file([
            line("amtrak", "Amtrak", "intercity", [[0.05, 0.05], [1.0, 0.05]]),
            line("lirr", "Long Island Rail Road", "commuter", [[0.05, 0.05], [1.0, 0.05]]),
        ])
        tiles = plan_tiles([city(bounds=[[0, 0, 0.1, 0.1]])], width_m=10000, height_m=5000, rail_files=[path])
        self.assertTrue(all("amtrak" not in tile["rail_lines"] for tile in tiles))
        self.assertTrue(any("lirr" in tile["rail_lines"] for tile in tiles))
        self.assertGreater(max(tile["lon"] for tile in tiles), 0.9)

    def test_city_filter_and_unmatched_fallback(self):
        path = self.rail_file([line("a-line", "Agency", "light_rail", [[0.05, 0.05], [0.1, 0.05]])])
        cities = [city("a"), city("b", [[2, 2, 2.02, 2.02]])]
        tiles = plan_tiles(cities, city_ids=["b"], mode="corridors", rail_files=[path])
        self.assertTrue(tiles)
        self.assertEqual({tile["city"] for tile in tiles}, {"b"})
        self.assertTrue(all(tile["coverage_source"] == "catalog-area-fallback" for tile in tiles))

    def test_disconnected_segments_do_not_create_a_connector(self):
        path = self.rail_file([{
            "id": "branched", "operator": "Agency", "kind": "light_rail",
            "segments": [[0, 0, [[0.02, 0.02], [0.04, 0.02]]], [0, 0, [[10.0, 10.0], [10.02, 10.0]]]],
        }])
        tiles = plan_tiles([city(bounds=[[0, 0, 0.1, 0.1]])], width_m=5_000, height_m=5_000, rail_files=[path])
        self.assertTrue(any(tile["lat"] > 9 for tile in tiles))  # whole line still reaches its far branch
        self.assertFalse(any(1 < tile["lat"] < 9 for tile in tiles))

    def test_shared_geometry_does_not_trigger_second_city_fallback(self):
        path = self.rail_file([line("shared", "Agency", "light_rail", [[0.05, 0.05], [0.08, 0.05]])])
        tiles = plan_tiles([city("first"), city("second")], mode="corridors", rail_files=[path])
        self.assertEqual({tile["city"] for tile in tiles}, {"first"})
        self.assertTrue(all(tile["coverage_source"] == "rail-corridor" for tile in tiles))

    def test_small_tiles_use_small_sampling_intervals(self):
        path = self.rail_file([line("tiny", "Agency", "light_rail", [[0.0, 0.0], [0.00002, 0.0]])])
        tiles = plan_tiles([city(bounds=[[0, 0, 0.001, 0.001]])], width_m=0.1, height_m=0.1,
                           overlap=0, rail_files=[path])
        self.assertGreater(len(tiles), 20)

    def test_line_rectangle_clipping_includes_corner_and_rejects_near_miss(self):
        self.assertTrue(_segment_intersects_rect(-1, 1, 1, -1, 0, 0, 1, 1))
        self.assertFalse(_segment_intersects_rect(-1, 1.01, 1, 1.01, 0, 0, 1, 1))

    def test_city_match_detects_segment_that_crosses_box_without_vertex_inside(self):
        crossing = line("crossing", "Agency", "commuter", [[-1, 0.05], [1, 0.05]])
        self.assertTrue(_line_matches_city(crossing, city()))

    def test_city_match_reuses_preparsed_geometry_and_bounds(self):
        crossing = line("crossing", "Agency", "commuter", [[-1, 0.05], [1, 0.05]])
        segments = _line_segments(crossing)
        with patch("planner._line_segments", side_effect=AssertionError("geometry reparsed")):
            self.assertTrue(_line_matches_city(crossing, city(), segments, _geometry_bounds(segments)))

    def test_compact_continuation_restores_omitted_shared_vertex(self):
        compact = {
            "segments": [
                [0, 0, [[0.0, 0.0], [0.1, 0.0]]],
                [0, 1, [[0.2, 0.0]]],
                [0, 0, [[10.0, 10.0], [10.1, 10.0]]],
            ]
        }
        self.assertEqual(_line_segments(compact)[1], [(0.0, 0.1), (0.0, 0.2)])
        self.assertEqual(_line_segments(compact)[2][0], (10.0, 10.0))

    def test_split_outer_branch_is_owned_by_nearest_city_with_same_operator(self):
        path = self.rail_file([
            line("trunk", "Regional Rail", "commuter", [[0.05, 0.05], [0.08, 0.05]]),
            line("outer", "Regional Rail", "commuter", [[1.0, 0.05], [1.2, 0.05]]),
        ])
        tiles = plan_tiles([city()], width_m=10_000, height_m=5_000, rail_files=[path])
        self.assertTrue(any("outer" in tile["rail_lines"] and tile["lon"] > 1 for tile in tiles))

    def test_default_scale_tolerance_uses_low_side_accepted_footprint(self):
        path = self.rail_file([])
        tolerant = plan_tiles([city(bounds=[[0, 0, 0.3, 0.3]])], mode="areas",
                              width_m=10_000, height_m=10_000, rail_files=[path])
        exact = plan_tiles([city(bounds=[[0, 0, 0.3, 0.3]])], mode="areas",
                           width_m=10_000, height_m=10_000, rail_files=[path], scale_tolerance=0)
        self.assertGreater(len(tolerant), len(exact))

    def test_network_extents_are_merged_and_verification_state_is_preserved(self):
        catalog = [city("a"), city("b")]
        merged = apply_network_extents(catalog, {"cities": {
            "a": {"verified": True, "bounds": [[1, 1, 2, 2]], "systems": ["A"], "source_urls": ["https://example.test"]},
            "b": {"verified": False, "bounds": [[3, 3, 4, 4]]},
        }})
        self.assertIn([1, 1, 2, 2], merged[0]["bounds"])
        self.assertIn([3, 3, 4, 4], merged[1]["bounds"])
        self.assertTrue(merged[0]["network_extent_verified"])
        self.assertFalse(merged[1]["network_extent_verified"])
        self.assertEqual(len(catalog[0]["bounds"]), 1)  # caller input is not mutated

    def test_rectangle_union_audit_detects_narrow_hole(self):
        target = [0, 0, 1, 1]
        self.assertTrue(rectangle_covered(target, [[0, 0, 1, 0.5], [0, 0.5, 1, 1]]))
        self.assertFalse(rectangle_covered(target, [[0, 0, 1, 0.49], [0, 0.51, 1, 1]]))

    def test_line_audit_checks_continuous_coverage_not_only_vertices(self):
        route = line("route", "Agency", "commuter", [[0, 0.5], [1, 0.5]])
        self.assertTrue(line_covered(route, [[0, -0.1, 0.6, 0.6], [0.4, 0.4, 1, 1]]))
        self.assertFalse(line_covered(route, [[0, -0.1, 0.49, 0.6], [0.51, 0.4, 1, 1]]))

    def test_supplement_requires_every_named_route_in_system_extent(self):
        lines = [{"name": "MAX Blue Line", "operator": "TriMet"},
                 {"name": "MAX Red Line", "operator": "TriMet"}]
        self.assertTrue(_supplement_resolves("MAX", lines, ["MAX Blue Line", "MAX Red Line"]))
        self.assertFalse(_supplement_resolves("MAX", lines, ["MAX Blue Line", "MAX Green Line"]))
        self.assertTrue(_supplement_resolves(
            "CATS LYNX", [{"name": "LYNX Blue Line", "operator": "Charlotte Area Transit System"}],
            ["LYNX Blue Line"],
        ))

    def test_up_express_identity_matches_union_pearson_canonical_line(self):
        lines = [{"id": "union-pearson-express-up", "name": "Union Pearson Express",
                  "operator": "UP Express", "kind": "commuter"}]
        self.assertTrue(_supplement_resolves("UP Express", lines, ["UP Express"]))

    def test_audit_limits_static_gaps_and_lines_to_selected_city_scope(self):
        catalog = {"cities": [city("toronto", [[0, 0, 0.01, 0.01]]),
                              city("calgary", [[10, 10, 10.01, 10.01]])]}
        up = line("union-pearson-express-up", "UP Express", "commuter", [[0, 0], [0.001, 0]])
        up["name"] = "Union Pearson Express"
        calibration = {
            "image_size": [1000, 1000], "inner_margin_px": 100, "target_meters_per_pixel": 100,
            "coordinate_alignment_verified": True, "coordinate_offset_pixels": [0, 0],
            "alignment_validation": {"station_matches": 2, "residual_offset_pixels": [0, 0]},
        }
        plan = {"calibration": calibration, "selected_city_ids": ["toronto"], "tiles": [{
            "id": "t", "city": "toronto", "cities": ["toronto"], "lat": 0.0, "lon": 0.0,
            "rail_lines": [up["id"]], "coverage_source": "rail-corridor",
        }]}
        report = audit(catalog, plan, [{"lines": [up]}], {"cities": {}})
        self.assertEqual(report["scope"]["selected_cities"], 1)
        self.assertEqual(report["known_repository_inventory_gaps"], [])
        self.assertEqual(report["canonical_inventory_matches_for_static_findings"], [
            {"city": "toronto", "systems_or_routes": ["UP Express"]}
        ])

    def test_overlapping_area_tile_records_every_selected_city(self):
        tiles = plan_tiles([city("first"), city("second")], mode="areas",
                           width_m=50_000, height_m=50_000)
        self.assertTrue(any(set(tile["cities"]) == {"first", "second"} for tile in tiles))

    def test_stale_supplemental_filter_cache_is_ignored(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        supplement = Path(directory.name) / "supplement"
        supplement.mkdir()
        (supplement / "old.json").write_text(json.dumps({
            "format": "compact-v1-supplement", "filterVersion": 3,
            "lines": [line("stale", "Agency", "tram", [[0, 0], [1, 1]])],
        }), encoding="utf-8")
        base = self.rail_file([])
        self.assertEqual(_load_lines([base], supplemental_dir=supplement), [])

    def test_default_metros_keeps_area_for_partial_geometry_and_outer_commuter_line(self):
        path = self.rail_file([line("commuter", "Agency", "commuter", [[0.05, 0.05], [1.0, 0.05]])])
        tiles = plan_tiles([city(bounds=[[0, 0, 0.1, 0.1]])], width_m=10_000, height_m=5_000, rail_files=[path])
        self.assertTrue(any(tile["coverage_source"].startswith("metro-area") for tile in tiles))
        self.assertTrue(any("commuter" in tile["rail_lines"] and tile["lon"] > 0.9 for tile in tiles))

    def test_invalid_arguments(self):
        with self.assertRaises(ValueError):
            plan_tiles([city()], width_m=0)
        with self.assertRaises(ValueError):
            plan_tiles([city()], overlap=1)
        with self.assertRaises(ValueError):
            plan_tiles([city()], mode="unknown")
        with self.assertRaises(ValueError):
            plan_tiles([city()], city_ids=["missing"])
        with self.assertRaises(ValueError):
            plan_tiles([city()], scale_tolerance=1)


if __name__ == "__main__":
    unittest.main()
