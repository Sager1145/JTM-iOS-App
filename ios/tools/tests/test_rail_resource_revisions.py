import importlib.util
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "rail_resource_revisions", Path(__file__).resolve().parents[1] / "rail_resource_revisions.py")
resources = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resources)


class ResourceRevisionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name) / "repo"
        self.bundle = Path(self.temporary.name) / "bundle"
        self.bundle.mkdir()
        self.rail = self.repo / "app/public/rail"
        self.rail.mkdir(parents=True)
        for region in resources.REGIONS:
            (self.bundle / f"{region}-2025.json").write_text(region)

    def manifest(self):
        return resources.build_manifest(self.repo, self.bundle)

    def changed_regions(self, before):
        after = self.manifest()
        return {region for region in resources.REGIONS
                if before["regions"][region] != after["regions"][region]}

    def test_hashes_are_stable_and_ignore_conflict_copies_and_mtimes(self):
        before = self.manifest()
        self.assertEqual(set(before["regions"]), set(resources.REGIONS))
        (self.bundle / "tw-2025.json").touch()
        (self.bundle / "tw-2025 2.json").write_text("different conflict")
        (self.rail / "shared-corridors 2.json").write_text("conflict")
        self.assertEqual(before, self.manifest())

    def test_every_regional_solver_resource_changes_only_its_region(self):
        for region in resources.REGIONS:
            suffix = "" if region == "jp" else f"-{region}"
            names = [f"{region}-2025.json"] + [
                f"{family}{suffix}.json" for family in
                ("stations", "rail-sections", "station-readings", "rail-history", "train-store")]
            names += [f"rail-display-network/{region}.{ending}" for ending in
                      ("display.bin", "stations.json", "display-history.json")]
            for name in names:
                with self.subTest(region=region, resource=name):
                    before = self.manifest()
                    path = self.bundle / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(path.read_bytes() + b"changed" if path.exists() else b"added")
                    self.assertEqual(self.changed_regions(before), {region})

    def test_removed_optional_history_invalidates_revision(self):
        history = self.bundle / "rail-history-ca.json"
        history.write_text("history")
        before = self.manifest()
        history.unlink()
        self.assertEqual(self.changed_regions(before), {"ca"})
        self.assertIn(history.name, before["sourceHashes"])
        self.assertNotIn(history.name, self.manifest()["sourceHashes"])

    def test_source_hashes_are_raw_bytes_for_precompute_attestations(self):
        path = self.bundle / "rail-sections-ca.json"
        path.write_bytes(b'{"sections":[]}\n')
        hashes = self.manifest()["sourceHashes"]
        self.assertEqual(hashes[path.name], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(hashes["ca-2025.json"], hashlib.sha256(b"ca").hexdigest())

    def test_shared_render_inputs_invalidate_all_regions(self):
        for name in resources.SHARED_DISPLAY_INPUTS:
            with self.subTest(resource=name):
                before = self.manifest()
                (self.rail / name).write_text("shared display change")
                self.assertEqual(self.changed_regions(before), set(resources.REGIONS))

    def test_map_manifest_versions_and_catalog_invalidate_routes(self):
        path = self.bundle / "rail-display-network/manifest.json"
        path.parent.mkdir()
        manifest = {
            "format": "jtm-display-network-v2", "version": "1",
            "generatedAt": "first build", "built": {"vertices": 100},
            "lines": {"jp|line": {"region": "jp", "color": "blue"},
                      "ca|line": {"region": "ca", "color": "red"}},
            "regions": [{"region": "jp", "sha256": "jp"},
                        {"region": "ca", "sha256": "ca"}],
        }
        def write():
            path.write_text(json.dumps(manifest))
        write()
        before = self.manifest()
        manifest["generatedAt"] = "later build"
        manifest["built"]["vertices"] += 1
        write()
        self.assertEqual(before, self.manifest())
        manifest["lines"]["jp|line"]["color"] = "green"
        write()
        self.assertEqual(self.changed_regions(before), {"jp"})
        before = self.manifest()
        manifest["version"] = "2"
        write()
        self.assertEqual(self.changed_regions(before), set(resources.REGIONS))
        before = self.manifest()
        path.unlink()
        self.assertEqual(self.changed_regions(before), set(resources.REGIONS))

    def test_sample_chunk_change_and_removal_invalidates_its_region(self):
        directory = self.bundle / "sample-data-tw"
        directory.mkdir()
        chunk = directory / "part-000.json"
        chunk.write_text("chunk")
        before = self.manifest()
        (directory / "part-000 2.json").write_text("conflict")
        self.assertEqual(before, self.manifest())
        chunk.write_text("new chunk")
        self.assertEqual(self.changed_regions(before), {"tw"})
        before = self.manifest()
        chunk.unlink()
        self.assertEqual(self.changed_regions(before), {"tw"})

    def test_timetable_snapshot_includes_wal_and_is_repeatable(self):
        source = self.repo / "canonical.sqlite"
        destination = self.bundle / "train-service-timetable.sqlite"
        with sqlite3.connect(source) as database:
            database.execute("PRAGMA journal_mode=WAL")
            database.execute("CREATE TABLE trips (id TEXT)")
            database.commit()
            database.execute("INSERT INTO trips VALUES ('latest')")
            database.commit()
            self.assertTrue(Path(str(source) + "-wal").is_file())
            resources.snapshot_timetable(source, destination)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o644)
            with sqlite3.connect(destination) as copied:
                self.assertEqual(copied.execute("SELECT id FROM trips").fetchall(), [("latest",)])
            before = self.manifest()
            resources.snapshot_timetable(source, destination)
            self.assertEqual(before, self.manifest())
            database.execute("INSERT INTO trips VALUES ('newer')")
            database.commit()
            resources.snapshot_timetable(source, destination)
            self.assertNotEqual(before["timetableRevision"], self.manifest()["timetableRevision"])


if __name__ == "__main__":
    unittest.main()
