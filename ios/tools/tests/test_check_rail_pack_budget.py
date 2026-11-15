#!/usr/bin/env python3
"""check-rail-pack-budget.sh: fails on an over-budget pack, an unknown region and an over-budget bundle."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "ios/tools/check-rail-pack-budget.sh"
COMMITTED = ROOT / "ios/tools/railbake/pack-budgets.json"


def run(pack_dir: Path, budgets: Path) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", str(SCRIPT), str(pack_dir), str(budgets)], capture_output=True, text=True)


class BudgetScriptTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name) / "packs"
        self.dir.mkdir()
        self.budgets = Path(self._tmp.name) / "budgets.json"
        self.write_budgets(bundle=1000, packs={"jp": 600, "hk": 300})

    def write_budgets(self, bundle, packs):
        self.budgets.write_text(json.dumps({
            "bundleBytes": bundle, "phoneWindowVertices": 1, "padWindowVertices": 1,
            "packs": {name: {"bytes": size, "levelVertices": {}} for name, size in packs.items()},
        }))

    def pack(self, name, size):
        (self.dir / name).write_bytes(b"x" * size)

    def test_within_budget_passes(self):
        self.pack("jp.railpack", 500)
        self.pack("hk.railpack", 200)
        result = run(self.dir, self.budgets)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("700 bytes", result.stdout)

    def test_a_pack_over_its_budget_fails(self):
        self.pack("jp.railpack", 601)
        result = run(self.dir, self.budgets)
        self.assertEqual(result.returncode, 1)
        self.assertIn("OVER its budget of 600", result.stdout)

    def test_the_bundle_over_its_budget_fails_even_when_every_pack_fits(self):
        self.pack("jp.railpack", 600)
        self.write_budgets(bundle=800, packs={"jp": 600, "hk": 300})
        self.pack("hk.railpack", 300)
        result = run(self.dir, self.budgets)
        self.assertEqual(result.returncode, 1)
        self.assertIn("over the 800 byte bundle budget by 100", result.stderr)

    def test_a_region_without_a_budget_fails(self):
        self.pack("zz.railpack", 10)
        self.assertEqual(run(self.dir, self.budgets).returncode, 1)

    def test_an_empty_directory_is_an_error(self):
        self.assertEqual(run(self.dir, self.budgets).returncode, 2)

    def test_the_committed_budgets_hold_the_user_requirement(self):
        budgets = json.loads(COMMITTED.read_text())
        # Limits record docs/maintenance/2026-11-13-rail-pack-limits.md: hard ceilings.
        self.assertEqual(budgets["bundleBytes"], 30_000_000)
        self.assertEqual(budgets["packs"]["jp"]["bytes"], 22_000_000)
        self.assertEqual(budgets["phoneWindowVertices"], 100_000)
        # One file per region (the GCJ-02 shift is the reader's), so the budgets simply add up.
        self.assertLessEqual(sum(entry["bytes"] for entry in budgets["packs"].values()), budgets["bundleBytes"])
        self.assertEqual(set(budgets["packs"]), {"jp", "tw", "hk", "mo", "kr"})


if __name__ == "__main__":
    unittest.main()
