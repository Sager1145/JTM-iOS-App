#!/usr/bin/env python3
"""bake-rail-packs.sh stage-check-swap: stale packs are removed, an over-budget bundle leaves DEST_DIR untouched.

Runs the real script inside a scratch copy of ios/tools with a stub rail_pack_inputs.py, a stub freshness
check and a pre-filled pack cache, so no builder directory and no RailBake build is needed.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]

STUB_INPUTS = '''\
import sys
cmd = sys.argv[1]
if cmd == "toolchain":
    print("stub-toolchain")
elif cmd == "key":
    print("key-" + sys.argv[sys.argv.index("--region") + 1])
elif cmd == "variants":
    for region in sys.argv[sys.argv.index("--regions") + 1].split():
        print(region, region + ".railpack")
'''


class BakeScriptTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.top = Path(tmp.name)
        tools = self.top / "repo/ios/tools"
        (tools / "railbake").mkdir(parents=True)
        shutil.copy(TOOLS / "bake-rail-packs.sh", tools)
        shutil.copy(TOOLS / "check-rail-pack-budget.sh", tools)
        (tools / "check-rail-packs-fresh.sh").write_text("#!/bin/bash\nexit 0\n")
        (tools / "rail_pack_inputs.py").write_text(STUB_INPUTS)
        self.tools = tools
        self.budgets = tools / "railbake/pack-budgets.json"
        self.write_budgets(bundle=1000)
        cache = self.top / "repo/ios/.build/railpack-cache"
        for region, size in (("jp", 500), ("hk", 200)):
            (cache / f"key-{region}").mkdir(parents=True)
            (cache / f"key-{region}" / f"{region}.railpack").write_bytes(b"n" * size)
        self.builder = self.top / "builder"
        self.builder.mkdir()
        self.dest = self.top / "dest"
        self.dest.mkdir()

    def write_budgets(self, bundle):
        self.budgets.write_text(json.dumps({
            "bundleBytes": bundle, "phoneWindowVertices": 1, "padWindowVertices": 1,
            "packs": {"jp": {"bytes": 600, "levelVertices": {}}, "hk": {"bytes": 300, "levelVertices": {}}},
        }))

    def bake(self):
        return subprocess.run(
            ["bash", str(self.tools / "bake-rail-packs.sh"), str(self.builder), str(self.dest), "--regions", "jp hk"],
            capture_output=True, text=True)

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.dest.iterdir()}

    def test_stale_packs_in_destination_are_removed(self):
        (self.dest / "hk.gcj.railpack").write_bytes(b"stale")
        result = self.bake()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(self.snapshot()), ["hk.railpack", "jp.railpack"])
        self.assertEqual(self.snapshot()["jp.railpack"], b"n" * 500)
        self.assertEqual([p.name for p in self.top.iterdir() if "staging" in p.name], [], "staging folder left behind")

    def test_over_budget_bundle_leaves_destination_untouched(self):
        (self.dest / "hk.gcj.railpack").write_bytes(b"stale")
        (self.dest / "jp.railpack").write_bytes(b"previous")
        before = self.snapshot()
        self.write_budgets(bundle=600)  # 500 + 200 = 700 bytes of packs
        result = self.bake()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual([p.name for p in self.top.iterdir() if "staging" in p.name], [], "staging folder left behind")


if __name__ == "__main__":
    unittest.main()
