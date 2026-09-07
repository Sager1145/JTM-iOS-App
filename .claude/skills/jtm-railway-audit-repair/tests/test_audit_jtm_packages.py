#!/usr/bin/env python3
"""Regression tests for the deterministic JTM package preflight."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from collections import Counter
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts/audit_jtm_packages.py"
SPEC = importlib.util.spec_from_file_location("jtm_package_audit", SCRIPT)
assert SPEC and SPEC.loader
audit_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit_module)


def path_km(path: list[list[float]]) -> float:
    return sum(audit_module.haversine(a, b) for a, b in zip(path, path[1:])) / 1000.0


class PackageAuditGeometryTests(unittest.TestCase):
    def new_audit(self):
        return audit_module.Audit(Path.cwd())

    def test_continuation_row_restores_omitted_shared_vertex(self):
        a, b, c = [0.0, 0.0], [0.01, 0.0], [0.02, 0.0]
        audit = self.new_audit()
        paths = audit.audit_geometry(
            "xx",
            "continuation",
            [a, b, c],
            [
                [path_km([a, b]), 0, [a, b]],
                [path_km([b, c]), 1, [c]],
            ],
            Counter(),
        )
        self.assertEqual(paths, [[a, b], [b, c]])
        self.assertFalse([issue for issue in audit.issues if issue["severity"] == "ERROR"])

    def test_reversed_adjacent_interval_does_not_manufacture_overlap(self):
        a, b, c = [0.0, 0.0], [0.01, 0.0], [0.02, 0.0]
        audit = self.new_audit()
        tally = Counter()
        paths = audit.audit_geometry(
            "xx",
            "reversed-neighbour",
            [a, b, c],
            [
                [path_km([a, b]), 0, [a, b]],
                [path_km([b, c]), 0, [c, b]],
            ],
            tally,
        )
        self.assertEqual(paths, [[a, b], [b, c]])
        audit.check_self_overlap("xx", "reversed-neighbour", paths, tally)
        self.assertNotIn("SELF_OVERLAP", {issue["code"] for issue in audit.issues})

    def test_real_out_and_back_is_reported(self):
        a, b = [0.0, 0.0], [0.02, 0.0]
        audit = self.new_audit()
        audit.check_self_overlap("xx", "out-and-back", [[a, b], [b, a]], Counter())
        self.assertIn("SELF_OVERLAP", {issue["code"] for issue in audit.issues})

    def test_absolute_overlap_threshold_catches_local_defect_on_long_line(self):
        a, b, c = [0.0, 0.0], [0.9, 0.0], [0.918, 0.0]
        audit = self.new_audit()
        audit.check_self_overlap("xx", "long-line-local-overlap", [[a, b], [b, c], [c, b]], Counter())
        issue = next(issue for issue in audit.issues if issue["code"] == "SELF_OVERLAP")
        self.assertIn("km (", issue["message"])

    def test_coarse_extra_lap_is_reported_using_segment_distance(self):
        path = [[0.0, 0.0], [0.01, 0.0], [0.01, 0.01], [0.0, 0.01], [0.0, 0.0]]
        stations = [
            [0.0, 0.0], [0.005, 0.0], [0.01, 0.0], [0.01, 0.005],
            [0.01, 0.01], [0.005, 0.01], [0.0, 0.01], [0.0, 0.005],
        ]
        walked = path_km(path) * 1000.0
        audit = self.new_audit()
        audit.check_retrace("xx", "coarse-extra-lap", 0, path, walked, walked * 2, stations)
        self.assertIn("INTERVAL_RETRACES_LINE", {issue["code"] for issue in audit.issues})

    def test_horseshoe_with_separate_legs_is_not_self_overlap(self):
        path = [
            [0.0, 0.0], [0.0, 0.01], [0.0006, 0.0104],
            [0.0012, 0.01], [0.0012, 0.0],
        ]
        audit = self.new_audit()
        audit.check_self_overlap("xx", "horseshoe", [path], Counter())
        self.assertNotIn("SELF_OVERLAP", {issue["code"] for issue in audit.issues})

    def test_web_only_checkout_is_a_valid_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            nested = root / "work/deep"
            nested.mkdir(parents=True)
            (root / "app/public/rail").mkdir(parents=True)
            self.assertEqual(audit_module.find_repo(nested), root.resolve())

            audit = audit_module.Audit(root)
            audit.audit_cross_platform([])
            self.assertEqual([issue["code"] for issue in audit.issues], ["WEB_ONLY_CHECKOUT"])


if __name__ == "__main__":
    unittest.main()
