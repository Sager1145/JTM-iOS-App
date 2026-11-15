"""Guard: app-control builds into a per-worktree folder, stamps the commit, and launch checks it
(map-lock run 3: another worktree's build replaced the app under test).

Run: python3 -I -m unittest discover -s ios/tools/tests -p test_app_control_build_isolation.py
"""
import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "app-control.py"


def load():
    spec = importlib.util.spec_from_file_location("app_control", PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BuildIsolation(unittest.TestCase):
    def test_derived_data_is_keyed_on_the_worktree(self):
        m = load()
        self.assertEqual(m.DERIVED.parent.name, "DerivedData")
        self.assertEqual(len(m.DERIVED.name), 10)
        self.assertNotEqual(m.DERIVED.name, "DerivedData")

    def test_commit_mismatch_ignores_dirty_suffix_only(self):
        m = load()
        self.assertFalse(m.commit_mismatch("abc123", "abc123"))
        self.assertFalse(m.commit_mismatch("abc123-dirty", "abc123"))
        self.assertTrue(m.commit_mismatch("abc122", "abc123"))
        self.assertTrue(m.commit_mismatch(None, "abc123"))
        self.assertTrue(m.commit_mismatch("abc123", None))

    def test_built_commit_reads_both_bundle_layouts(self):
        m = load()
        for rel in ("Contents/Info.plist", "Info.plist"):
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(plistlib.dumps({"JTMBuildCommit": "deadbeef"}))
                self.assertEqual(m.built_commit(tmp), "deadbeef")
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(m.built_commit(tmp))

    def test_state_file_is_keyed_on_the_worktree(self):
        m = load()
        class A: target = "mac"; device = None
        self.assertTrue(m.state_file(A).name.endswith("-" + m.WORKTREE_KEY + ".json"))

    def test_launch_refuses_a_dirty_build_unless_allowed(self):
        source = PATH.read_text()
        self.assertIn("--allow-dirty", source)
        self.assertIn('stamped.endswith("-dirty") and not a.allow_dirty', source)

    def test_build_command_stamps_the_commit(self):
        source = PATH.read_text()
        self.assertIn('"JTM_BUILD_COMMIT=" + build_commit_stamp()', source)


if __name__ == "__main__":
    unittest.main()
