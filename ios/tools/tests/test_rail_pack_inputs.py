"""Guards for ios/tools/rail_pack_inputs.py: the pack cache key and the freshness check.

The key must move when anything a pack is made of moves (bake sources, the region's builder
output and manifest slice, ladder, datum, toolchain) and stay put when it is not (another region,
files outside the list). A pack whose header hash differs from the recomputed key is stale.
"""

from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "ios/tools/rail_pack_inputs.py"

spec = importlib.util.spec_from_file_location("rail_pack_inputs", SCRIPT)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def write(path: Path, data: bytes | str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())


class Fixture:
    """A miniature repository and builder directory with every input present."""

    def __init__(self, tmp: Path):
        self.repo = tmp / "repo"
        self.builder = tmp / "builder"
        for relative in tool.SOURCE_PATHS:
            path = self.repo / relative
            if relative.endswith((".swift", ".json")):
                write(path, f"// {relative}\n")
            else:
                write(path / "A.swift", f"// {relative}/A\n")
        self.manifest = {
            "lines": {"a": {"region": "hk", "color": "#111111"}, "b": {"region": "mo", "color": "#222222"}},
            "regions": [{"region": "hk", "file": "hk.display.bin"}, {"region": "mo", "file": "mo.display.bin"}],
        }
        self.write_manifest()
        for region in ("hk", "mo"):
            write(self.builder / f"{region}.display.bin", f"{region} blob")
            write(self.builder / f"{region}.stations.json", f"{region} stations")
            topology = bytearray(160)
            topology[tool.TOPOLOGY_DISPLAY_OFFSET:tool.TOPOLOGY_DISPLAY_OFFSET + 32] = bytes([7]) * 32
            write(self.builder / f"{region}.topology.bin", bytes(topology))

    def write_manifest(self) -> None:
        write(self.builder / "manifest.json", json.dumps(self.manifest))

    def key(self, region="hk", datum="wgs84", levels="8...34", toolchain="swift 6.0") -> str:
        return tool.inputs_sha256(self.repo, self.builder, region, datum, levels, toolchain)

    def pack(self, key_hex: str, display: bytes = bytes([7]) * 32) -> Path:
        header = bytearray(100)
        header[0:4] = b"JTRP"
        header[tool.HEADER_DISPLAY_OFFSET:tool.HEADER_DISPLAY_OFFSET + 32] = display
        header[tool.HEADER_INPUTS_OFFSET:tool.HEADER_INPUTS_OFFSET + 32] = bytes.fromhex(key_hex)
        path = self.builder / "hk.railpack"
        write(path, bytes(header))
        return path


class KeyTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.f = Fixture(Path(self._tmp.name))

    def test_key_is_stable_and_hex(self):
        key = self.f.key()
        self.assertRegex(key, r"^[0-9a-f]{64}$")
        self.assertEqual(key, self.f.key())

    def test_key_moves_with_every_input(self):
        base = self.f.key()
        keys = {base}
        for change in (
            lambda: write(self.f.repo / "ios/RailKit/Sources/RailCore/Rendering/A.swift", "// edited\n"),
            lambda: write(self.f.repo / "ios/tools/railbake/Sources/A.swift", "// edited\n"),
            lambda: write(self.f.repo / "ios/RailKit/Sources/RailCore/Pack/RailPackFormat.swift", "// edited\n"),
            lambda: write(self.f.repo / "ios/tools/railbake/pack-budgets.json", "{}"),
            lambda: write(self.f.builder / "hk.display.bin", "changed"),
            lambda: write(self.f.builder / "hk.stations.json", "changed"),
            lambda: write(self.f.builder / "hk.topology.bin", b"\x01" + bytes(159)),
            lambda: write(self.f.builder / "hk.display-history.json", "{}"),
        ):
            change()
            key = self.f.key()
            self.assertNotIn(key, keys)
            keys.add(key)

    def test_key_moves_with_ladder_datum_and_toolchain(self):
        base = self.f.key()
        self.assertNotEqual(base, self.f.key(levels="8...30"))
        self.assertNotEqual(base, self.f.key(datum="gcj02"))
        self.assertNotEqual(base, self.f.key(toolchain="swift 6.1"))

    def test_manifest_slice_is_the_regions_own(self):
        base = self.f.key()
        self.f.manifest["lines"]["b"]["color"] = "#333333"  # another region's line
        self.f.write_manifest()
        self.assertEqual(base, self.f.key())
        self.f.manifest["lines"]["a"]["color"] = "#333333"  # this region's line
        self.f.write_manifest()
        self.assertNotEqual(base, self.f.key())

    def test_files_outside_the_list_do_not_matter(self):
        base = self.f.key()
        write(self.f.repo / "ios/RailMap/Map/Other.swift", "// app\n")
        write(self.f.repo / "ios/RailKit/Sources/RailCore/Search/Other.swift", "// search\n")
        self.assertEqual(base, self.f.key())

    def test_missing_inputs_are_errors(self):
        (self.f.builder / "hk.topology.bin").unlink()
        with self.assertRaises(tool.InputsError):
            self.f.key()
        with self.assertRaises(tool.InputsError):
            self.f.key(region="kr")
        (self.f.repo / "ios/RailKit/Sources/RailCore/Utilities/GCJ02.swift").unlink()
        with self.assertRaises(tool.InputsError):
            tool.source_files(self.f.repo)
        with self.assertRaises(tool.InputsError):
            tool.inputs_sha256(self.f.repo, self.f.builder, "hk", "mercator", "8...34", "t")


class CheckTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.f = Fixture(Path(self._tmp.name))

    def check(self, pack: Path):
        tool.check_pack(pack, self.f.repo, self.f.builder, "hk", "wgs84", "8...34", "swift 6.0")

    def test_fresh_pack_passes(self):
        self.check(self.f.pack(self.f.key()))

    def test_stale_pack_fails_after_any_input_change(self):
        pack = self.f.pack(self.f.key())
        write(self.f.repo / "ios/RailKit/Sources/RailCore/Rendering/A.swift", "// edited\n")
        with self.assertRaisesRegex(tool.InputsError, "stale"):
            self.check(pack)

    def test_pack_of_another_display_blob_fails(self):
        with self.assertRaisesRegex(tool.InputsError, "display blob"):
            self.check(self.f.pack(self.f.key(), display=bytes([9]) * 32))

    def test_not_a_pack_fails(self):
        path = self.f.builder / "junk.railpack"
        write(path, b"nope" * 40)
        with self.assertRaises(tool.InputsError):
            self.check(path)
        write(path, b"JTRP")
        with self.assertRaises(tool.InputsError):
            self.check(path)

    def test_command_line_matches_the_function(self):
        base = [sys.executable, "-I", str(SCRIPT), "--repo", str(self.f.repo), "--builder-dir", str(self.f.builder),
                "--region", "hk", "--toolchain", "swift 6.0"]
        key = subprocess.run(base + ["key"], capture_output=True, text=True, check=True).stdout.strip()
        self.assertEqual(key, self.f.key())
        pack = self.f.pack(key)
        self.assertEqual(subprocess.run(base + ["check", "--pack", str(pack)], capture_output=True).returncode, 0)
        write(self.f.builder / "hk.display.bin", "changed")
        self.assertEqual(subprocess.run(base + ["check", "--pack", str(pack)], capture_output=True).returncode, 1)


class RepositoryTests(unittest.TestCase):
    def test_every_listed_source_exists_in_the_repository(self):
        files = [path.relative_to(ROOT).as_posix() for path in tool.source_files(ROOT)]
        for expected in (
            "ios/RailKit/Sources/RailCore/Rendering/StrokeBake.swift",
            "ios/RailKit/Sources/RailCore/Rendering/NetworkStrokeBake.swift",
            "ios/RailKit/Sources/RailCore/Utilities/GCJ02.swift",
            "ios/RailKit/Sources/RailCore/Pack/RailPackWriter.swift",
            "ios/tools/railbake/Sources/RailBakeKit/PieceCutter.swift",
            "ios/tools/railbake/Sources/RailBakeKit/PackAssembler.swift",
            "ios/tools/railbake/Sources/RailBakeKit/PackBudget.swift",
            "ios/tools/railbake/Sources/RailBake/main.swift",
            "ios/tools/railbake/pack-budgets.json",
            "ios/RailKit/Sources/RailCore/Rendering/NetworkStrokeThin.swift",
            "ios/RailKit/Sources/RailPresentation/Map/NetworkVisibilityPolicy.swift",
        ):
            self.assertIn(expected, files)

    def test_variant_table_matches_the_swift_datum_regions(self):
        text = (ROOT / "ios/RailKit/Sources/RailCore/Utilities/GCJ02.swift").read_text()
        match = re.search(r"candidateRegions[^=]*=\s*\[([^\]]*)\]", text)
        self.assertIsNotNone(match)
        swift_regions = set(re.findall(r'"([a-z]{2})"', match.group(1)))
        self.assertEqual(set(tool.GCJ_REGIONS), swift_regions)

    def test_variants(self):
        rows = tool.variants(("jp", "hk"))
        self.assertEqual(rows, [("jp", "wgs84", "jp.railpack"), ("hk", "wgs84", "hk.railpack"),
                                ("hk", "gcj02", "hk.gcj.railpack")])
        self.assertEqual(len(tool.variants()), 1 + 2 * 4)

    def test_pack_header_offsets_match_the_format(self):
        text = (ROOT / "ios/RailKit/Sources/RailCore/Pack/RailPackFormat.swift").read_text()
        self.assertIn("//   28  displaySHA256           32", text)
        self.assertIn("//   60  inputsSHA256", text)
        self.assertIn("//   92  fileLength", text)
        topology = (ROOT / "ios/RailKit/Sources/RailCore/Topology/RailTopologyFormat.swift").read_text()
        self.assertIn("displaySHA256Offset = 48", topology)


if __name__ == "__main__":
    unittest.main()
