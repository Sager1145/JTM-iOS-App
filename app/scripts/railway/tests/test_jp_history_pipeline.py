import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

import shapefile


RAILWAY_DIR = Path(__file__).resolve().parents[1]
HISTORY_DIR = RAILWAY_DIR / "history"


def load_script(name):
    path = HISTORY_DIR / name
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


inventory = load_script("inventory-jp-history.py")
diff = load_script("diff-jp-history.py")
matcher = load_script("match-jp-history-events.py")
legacy = load_script("normalize-n02-1996.py")


def feature(kind, coordinates, line="L", operator="O", name=None, code=None):
    props = {
        "feature_kind": kind,
        "line_name": line,
        "operator": operator,
        "railway_class_code": "11",
        "institution_type_code": "2",
    }
    if name is not None:
        props["station_name"] = name
    if code is not None:
        props["station_code"] = code
    return {
        "type": "Feature",
        "properties": props,
        "geometry": {"type": "LineString", "coordinates": coordinates},
    }


def write_geojson(path, features):
    path.write_text(json.dumps({"type": "FeatureCollection", "features": features}), encoding="utf-8")


class SnapshotInventoryTests(unittest.TestCase):
    def test_review_queue_reads_extra_snapshot_outside_source_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            history = root / "history"
            history.mkdir()
            old = history / "N02-24.json"
            extra = root / "N02-25.json"
            write_geojson(old, [feature("section", [[139, 35], [139.01, 35.01]])])
            write_geojson(extra, [feature("section", [[139, 35], [139.02, 35.02]])])
            events = root / "events.json"
            events.write_text('{"events": [], "temporal_events": []}')
            output = root / "report.json"
            result = subprocess.run([
                sys.executable, str(HISTORY_DIR / "build-jp-history-review-queue.py"),
                "--source-dir", str(history), "--extra-snapshot", str(extra),
                "--events", str(events), "--output", str(output),
            ], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text())
            self.assertEqual(report["summary"]["snapshot_count"], 2)
            self.assertEqual(report["summary"]["comparison_count"], 1)
            self.assertEqual(report["comparisons"][0]["sources"][1]["source_path"], "N02-25.json")

    def test_normalized_geojson_inventory_is_deterministic_and_year_precision(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = root / "N02-23.geojson"
            # Reverse orientation must canonicalize to the same geometry id.
            write_geojson(path, [
                feature("section", [[1, 0], [0, 0]], line="Alpha"),
                feature("station", [[0.2, 0], [0.3, 0]], line="Alpha", name="中央", code="001"),
            ])
            first = inventory.inventory_snapshot(path, root)
            second = inventory.inventory_snapshot(path, root)
            self.assertEqual(first, second)
            self.assertEqual(first["snapshot_id"], "jp-n02-2023")
            self.assertEqual(first["observation"]["precision"], "year")
            self.assertEqual(first["observation"]["value"], "2023")
            self.assertIsNone(first["observation"]["event_date"])
            self.assertEqual(first["observation"]["event_date_inference"], "forbidden")
            self.assertEqual(first["counts"], {"sections": 1, "stations": 1})
            self.assertEqual(first["sections"][0]["geometry"]["coordinates"], [[0.0, 0.0], [1.0, 0.0]])
            self.assertEqual(first["provenance"]["source_path"], "N02-23.geojson")
            self.assertEqual(len(first["provenance"]["sha256"]), 64)
            manifest = inventory.inventory_snapshot(path, root, record_mode="manifest")
            self.assertNotIn("sections", manifest)
            self.assertNotIn("stations", manifest)
            self.assertEqual(manifest["counts"], {"sections": 1, "stations": 1})
            self.assertEqual(len(manifest["identity_inventory"]), 2)

    def test_zip_shapefile_layout_matches_runtime_release_reader(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            archive = root / "N02-23_GML.zip"
            build = root / "build"
            build.mkdir()

            section_base = build / "N02-23_RailroadSection"
            writer = shapefile.Writer(str(section_base), shapeType=shapefile.POLYLINE, encoding="cp932")
            for field in ("N02_001", "N02_002", "N02_003", "N02_004"):
                writer.field(field, "C", size=80)
            writer.line([[[139.0, 35.0], [139.1, 35.1]]])
            writer.record("11", "2", "本線", "試験鉄道")
            writer.close()

            station_base = build / "N02-23_Station"
            (build / 'N02-23_RailroadSection.prj').write_text('GEOGCS["GCS_JGD_2011"]')
            writer = shapefile.Writer(str(station_base), shapeType=shapefile.POLYLINE, encoding="cp932")
            for field in ("N02_001", "N02_002", "N02_003", "N02_004", "N02_005", "N02_005c"):
                writer.field(field, "C", size=80)
            writer.line([[[139.0, 35.0], [139.001, 35.0]]])
            writer.record("11", "2", "本線", "試験鉄道", "試験駅", "990001")
            writer.close()

            with zipfile.ZipFile(archive, "w") as zf:
                for path in sorted(build.iterdir()):
                    zf.write(path, f"Shift-JIS/{path.name}")

            snapshot = inventory.inventory_snapshot(archive, root)
            self.assertEqual(snapshot["counts"], {"sections": 1, "stations": 1})
            self.assertEqual(snapshot["sections"][0]["attributes"]["line_name"], "本線")
            self.assertEqual(snapshot["stations"][0]["attributes"]["station_name"], "試験駅")
            self.assertIn("Shift-JIS", snapshot["provenance"]["archive_members"]["sections"])
            self.assertEqual(snapshot['provenance']['crs'], 'EPSG:6668')
            self.assertIn('native geographic', snapshot['provenance']['coordinate_operation'])

    def test_provenance_override_keeps_precision_explicit_and_cannot_supply_event_date(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = root / "snapshot-2024.geojson"
            write_geojson(path, [feature("section", [[0, 0], [1, 0]])])
            snapshot = inventory.inventory_snapshot(path, root, {
                path.name: {
                    "release_label": "N02-24",
                    "source_url": "https://example.test/n02-24",
                    "license": "example-license",
                    "observation": {"value": "2025-06", "precision": "month", "event_date": "2025-06-01"},
                }
            })
            self.assertEqual(snapshot["observation"]["precision"], "month")
            self.assertEqual(snapshot["observation"]["value"], "2025-06")
            self.assertIsNone(snapshot["observation"]["event_date"])
            self.assertEqual(snapshot["provenance"]["source_url"], "https://example.test/n02-24")


class SnapshotDiffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        before_path = self.root / "N02-23.geojson"
        after_path = self.root / "N02-24.geojson"
        before = [
            feature("section", [[0, 0], [1, 0]], line="Unchanged"),
            feature("section", [[0, 1], [1, 1]], line="Transfer", operator="Old"),
            feature("section", [[0, 2], [1, 2]], line="Removed"),
            feature("station", [[0.1, 4], [0.2, 4]], name="Same", code="A"),
            feature("station", [[0.1, 5], [0.2, 5]], name="Old Name", code="B"),
            feature("station", [[0.1, 6], [0.2, 6]], name="Moved", code="C"),
            feature("station", [[0.1, 7], [0.2, 7]], name="Removed Station", code="D"),
            feature("station", [[0.1, 8], [0.2, 8]], line="Transfer", operator="Old", name="Identity", code="F"),
        ]
        after = [
            feature("section", [[0, 0], [1, 0]], line="Unchanged"),
            feature("section", [[0, 1], [1, 1]], line="Transfer", operator="New"),
            feature("section", [[0, 3], [1, 3]], line="Added"),
            feature("station", [[0.1, 4], [0.2, 4]], name="Same", code="A"),
            feature("station", [[0.1, 5], [0.2, 5]], name="New Name", code="B"),
            feature("station", [[0.15, 6], [0.25, 6]], name="Moved", code="C"),
            feature("station", [[0.1, 9], [0.2, 9]], name="Added Station", code="E"),
            feature("station", [[0.1, 8], [0.2, 8]], line="Transfer", operator="New", name="Identity", code="F"),
        ]
        write_geojson(before_path, before)
        write_geojson(after_path, after)
        self.before = inventory.inventory_snapshot(before_path, self.root)
        self.after = inventory.inventory_snapshot(after_path, self.root)

    def tearDown(self):
        self.temp.cleanup()

    def test_diff_covers_geometry_identity_and_station_change_classes(self):
        result = diff.diff_snapshots(self.before, self.after)
        self.assertEqual(result["summary"]["by_kind"], {
            "section_geometry_added": 1,
            "section_geometry_removed": 1,
            "section_identity_changed": 1,
            "station_added": 1,
            "station_identity_changed": 1,
            "station_moved": 1,
            "station_name_changed": 1,
            "station_removed": 1,
        })
        self.assertEqual(result["summary"]["candidate_count"], 8)
        transfer = next(c for c in result["review_queue"] if c["candidate_kind"] == "section_identity_changed")
        self.assertEqual(transfer["match_basis"], "exact_geometry")
        self.assertEqual(transfer["details"]["changed_fields"]["operator"], {"before": "Old", "after": "New"})
        moved = next(c for c in result["review_queue"] if c["candidate_kind"] == "station_moved")
        self.assertGreater(moved["details"]["distance_m"], 4000)
        for candidate in result["review_queue"]:
            self.assertEqual(candidate["status"], "needs_review")
            self.assertEqual(candidate["verification"], {"state": "unverified", "automatic": False})
            self.assertIsNone(candidate["temporal_evidence"]["event_date"])

    def test_candidate_ids_and_queue_order_are_stable(self):
        first = diff.diff_snapshots(self.before, self.after)
        second = diff.diff_snapshots(self.before, self.after)
        self.assertEqual(first, second)
        ids = [candidate["candidate_id"] for candidate in first["review_queue"]]
        self.assertEqual(len(ids), len(set(ids)))


class EventMatcherTests(unittest.TestCase):
    def test_matcher_proposes_ranked_links_without_verifying(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            before_path = root / "N02-23.geojson"
            after_path = root / "N02-24.geojson"
            write_geojson(before_path, [
                feature("section", [[0, 0], [1, 0]], line="Closed"),
                feature("section", [[0, 1], [1, 1]], line="Transfer", operator="Old"),
                feature("station", [[0.1, 2], [0.2, 2]], line="Closed", name="Last", code="S"),
            ])
            write_geojson(after_path, [
                feature("section", [[0, 1], [1, 1]], line="Transfer", operator="New"),
            ])
            before = inventory.inventory_snapshot(before_path, root)
            after = inventory.inventory_snapshot(after_path, root)
            candidates = diff.diff_snapshots(before, after)
            events = {"events": [
                {"id": "closed.a", "line": "Closed", "operator": "O", "year": "23", "valid_to": "2024-01-01", "source": "primary-a"},
                {"id": "closed.b", "line": "Closed", "operator": "O", "year": "23", "valid_to": "2024-01-01", "source": "primary-b"},
                {"id": "closed.station", "kind": "station_closure", "line": "Closed", "operator": "O", "year": "23", "station": "Last", "valid_to": "2024-01-01", "source": "primary"},
                {"id": "transfer", "kind": "operator_transfer", "line": "Transfer", "operator": "Old", "to_operator": "New", "year": "23", "valid_to": "2024-01-01", "source": "primary"},
                {"id": "not-seen", "line": "Elsewhere", "operator": "O", "year": "23", "valid_to": "2024-01-01", "source": "primary"},
            ]}
            result = matcher.match_candidates(candidates, events)

            removed = next(
                item for item in result["candidate_queue"]
                if item["candidate_kind"] == "section_geometry_removed"
            )
            self.assertEqual(removed["match_status"], "ambiguous")
            self.assertEqual([m["event_id"] for m in removed["proposed_event_matches"]], ["closed.a", "closed.b"])
            station = next(item for item in result["candidate_queue"] if item["candidate_kind"] == "station_removed")
            self.assertEqual(station["match_status"], "possible_match")
            self.assertEqual(station["proposed_event_matches"][0]["event_id"], "closed.station")
            transfer = next(item for item in result["candidate_queue"] if item["candidate_kind"] == "section_identity_changed")
            self.assertEqual(transfer["proposed_event_matches"][0]["event_id"], "transfer")
            for item in result["candidate_queue"]:
                self.assertFalse(item["verification"]["automatic"])
                self.assertEqual(item["verification"]["state"], "unverified")
            missing = next(item for item in result["event_queue"] if item["event_id"] == "not-seen")
            self.assertEqual(missing["snapshot_evidence_status"], "no_candidate_link")
            self.assertFalse(result["policy"]["auto_verify_candidates"])


def fixed_record(fields, width=80):
    row = [" "] * width
    for start, end, value in fields:
        text = str(value)
        if len(text) > end - start:
            raise AssertionError((start, end, text))
        row[start:end] = list(text.rjust(end - start))
    return "".join(row).rstrip()


def legacy_fixture_text(bad_coordinate=False):
    header = fixed_record([(0, 3, "H  "), (13, 23, "N02-07L-2K")], 33)
    counts = "".join(f"{value:8d}" for value in (8, 2, 2, 2, 1, 0, 1))
    lon = 8000000 if bad_coordinate else 5004000  # 222.2E invalid, or 139E
    node_a = fixed_record([
        (0, 3, "N  "), (3, 9, 533946), (9, 15, 1), (15, 23, lon), (23, 31, 1260000),
        (31, 33, 1), (33, 43, "5339460001"), (43, 46, 1),
    ])
    node_b = fixed_record([
        (0, 3, "N  "), (3, 9, 533946), (9, 15, 2), (15, 23, 5007600), (23, 31, 1260000),
        (31, 33, 0), (43, 46, 1),
    ])
    link = fixed_record([
        (0, 3, "L  "), (3, 9, 533946), (9, 15, 1), (15, 21, 533946), (21, 27, 2),
        (27, 33, 1), (33, 35, 0), (45, 51, 2),
    ])
    points = fixed_record([
        (0, 8, lon), (8, 16, 1260000), (16, 24, 5007600), (24, 32, 1260000),
    ])
    line = fixed_record([
        (0, 3, "S  "), (3, 9, 533946), (9, 15, 1), (15, 21, 533946), (21, 27, 1),
        (27, 35, 1), (35, 37, 1), (37, 47, "11050000"), (47, 53, 1),
    ])
    line_links = fixed_record([(0, 6, 533946), (6, 12, 1), (12, 14, 0)], 70)
    station = fixed_record([(0, 3, "DP "), (3, 13, "5339460001"), (13, 16, 1), (16, 72, "試験駅")])
    route = fixed_record([(0, 3, "DS "), (3, 13, "11050000"), (13, 16, 1), (16, 18, 4),
                          (18, 72, "試験鉄道  試験線")])
    return "\n".join((header, counts, node_a, node_b, link, points, line, line_links, station, route))


class Legacy1996AdapterTests(unittest.TestCase):
    def test_fixed_width_jgd2000_schema_normalizes_without_inventing_operator(self):
        parsed = legacy.parse_unified_text(legacy_fixture_text())
        result = legacy.normalize(parsed, "fixture-sha")
        section = result["sections"]["features"][0]
        station = result["stations"]["features"][0]
        self.assertEqual(section["geometry"]["coordinates"], [[139.0, 35.0], [139.1, 35.0]])
        self.assertEqual(section["properties"]["N02_002"], "4")
        self.assertEqual(section["properties"]["N02_003"], "試験鉄道  試験線")
        self.assertIsNone(section["properties"]["N02_004"])
        self.assertEqual(station["properties"]["N02_005"], "試験駅")
        self.assertEqual(station["properties"]["N02_005c"], "5339460001")
        self.assertEqual(result["metadata"]["source_crs"], "EPSG:4612 (JGD2000 geographic latitude/longitude)")
        self.assertEqual(result["metadata"]["observation"]["value"], "1996-12-31")
        self.assertIsNone(result["metadata"]["observation"]["event_date"])
        self.assertIn("not asserted", result["metadata"]["provenance"]["license"]["status"])

    def test_fixed_width_parser_rejects_coordinates_outside_declared_domain(self):
        with self.assertRaisesRegex(ValueError, "outside Japan bounds"):
            legacy.parse_unified_text(legacy_fixture_text(bad_coordinate=True))


if __name__ == "__main__":
    unittest.main()
