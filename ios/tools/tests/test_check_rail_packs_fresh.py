#!/usr/bin/env python3
"""check-rail-packs-fresh.sh: passes only when every pack of every region is present and current.

Runs the real script and the real rail_pack_inputs.py inside a scratch copy of ios/tools with a
miniature repository and builder directory, so no builder output and no RailBake build is needed.
A guard that checked nothing (an empty or failed pack list) must fail, never pass.
"""
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]

spec = importlib.util.spec_from_file_location("rail_pack_inputs", TOOLS / "rail_pack_inputs.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

REGIONS = ("hk", "mo")


def write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())


class FreshnessScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The script asks for the toolchain string itself; one call here keeps the fixture keys cheap.
        cls.toolchain = tool.toolchain_string()

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.top = Path(tmp.name)
        self.repo = self.top / "repo"
        self.tools = self.repo / "ios/tools"
        for relative in tool.SOURCE_PATHS:
            path = self.repo / relative
            if relative.endswith((".swift", ".json")):
                write(path, f"// {relative}\n")
            else:
                write(path / "A.swift", f"// {relative}/A\n")
        shutil.copy(TOOLS / "check-rail-packs-fresh.sh", self.tools)
        shutil.copy(TOOLS / "rail_pack_inputs.py", self.tools)
        self.builder = self.top / "builder"
        write(self.builder / "manifest.json", json.dumps({
            "lines": {region: {"region": region, "color": "#111111"} for region in REGIONS},
            "regions": [{"region": region} for region in REGIONS],
        }))
        for index, region in enumerate(REGIONS):
            write(self.builder / f"{region}.display.bin", f"{region} blob")
            write(self.builder / f"{region}.stations.json", f"{region} stations")
            topology = bytearray(160)
            topology[tool.TOPOLOGY_DISPLAY_OFFSET:tool.TOPOLOGY_DISPLAY_OFFSET + 32] = bytes([index + 1]) * 32
            write(self.builder / f"{region}.topology.bin", bytes(topology))
        self.packs = self.top / "packs"
        self.packs.mkdir()
        for index, region in enumerate(REGIONS):
            key = subprocess.run(
                ["python3", "-I", str(self.tools / "rail_pack_inputs.py"), "key",
                 "--builder-dir", str(self.builder), "--region", region, "--toolchain", self.toolchain],
                capture_output=True, text=True, check=True).stdout.strip()
            header = bytearray(100)
            header[0:4] = tool.PACK_HEADER_MAGIC
            header[tool.HEADER_DISPLAY_OFFSET:tool.HEADER_DISPLAY_OFFSET + 32] = bytes([index + 1]) * 32
            header[tool.HEADER_INPUTS_OFFSET:tool.HEADER_INPUTS_OFFSET + 32] = bytes.fromhex(key)
            write(self.packs / f"{region}.railpack", bytes(header))

    def run_guard(self, regions=" ".join(REGIONS)):
        return subprocess.run(
            ["bash", str(self.tools / "check-rail-packs-fresh.sh"), str(self.builder), str(self.packs),
             "--regions", regions],
            capture_output=True, text=True)

    def test_current_packs_pass(self):
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("hk.railpack is fresh", result.stdout)
        self.assertIn("mo.railpack is fresh", result.stdout)

    def test_missing_pack_fails(self):
        (self.packs / "mo.railpack").unlink()
        result = self.run_guard()
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing pack", result.stderr)
        self.assertIn("hk.railpack is fresh", result.stdout)

    def test_changed_builder_input_fails(self):
        with (self.builder / "hk.display.bin").open("ab") as handle:
            handle.write(b"\0")
        result = self.run_guard()
        self.assertEqual(result.returncode, 1)
        self.assertIn("hk.railpack is stale", result.stderr)
        self.assertIn("mo.railpack is fresh", result.stdout)

    def test_changed_bake_source_fails_every_pack(self):
        write(self.repo / "ios/tools/railbake/pack-budgets.json", "{}\n")
        result = self.run_guard()
        self.assertEqual(result.returncode, 1)
        self.assertIn("hk.railpack is stale", result.stderr)
        self.assertIn("mo.railpack is stale", result.stderr)

    def test_pack_of_another_region_fails(self):
        shutil.copy(self.packs / "hk.railpack", self.packs / "mo.railpack")
        result = self.run_guard()
        self.assertEqual(result.returncode, 1)
        self.assertIn("mo.railpack is stale", result.stderr)

    def test_empty_pack_list_fails(self):
        result = self.run_guard(regions=" ")
        self.assertEqual(result.returncode, 1)
        self.assertIn("no packs to check", result.stderr)

    def test_failed_pack_list_fails(self):
        # Every other command still works; only the pack list fails.
        (self.tools / "rail_pack_inputs.py").rename(self.tools / "real_inputs.py")
        (self.tools / "rail_pack_inputs.py").write_text(
            "import runpy, sys\nfrom pathlib import Path\n"
            "if sys.argv[1] == 'variants':\n    sys.exit(3)\n"
            "runpy.run_path(str(Path(__file__).with_name('real_inputs.py')), run_name='__main__')\n")
        toolchain = subprocess.run(["python3", "-I", str(self.tools / "rail_pack_inputs.py"), "toolchain"],
                                   capture_output=True, text=True)
        self.assertEqual(toolchain.returncode, 0, toolchain.stderr)
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("is fresh", result.stdout)


if __name__ == "__main__":
    unittest.main()
