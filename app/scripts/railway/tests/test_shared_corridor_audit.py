import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "audit-shared-corridors.py"
SPEC = importlib.util.spec_from_file_location("shared_corridor_audit", SCRIPT)
shared_corridor_audit = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(shared_corridor_audit)


class SharedCorridorAuditTests(unittest.TestCase):
    def test_proper_crossing_ignores_shared_endpoints_and_collinear_track(self):
        self.assertEqual(
            shared_corridor_audit.proper_crossing_count(
                [[0, 0], [1, 1]], [[0, 0], [1, -1]]),
            0,
        )
        self.assertEqual(
            shared_corridor_audit.proper_crossing_count(
                [[0, 0], [1, 1]], [[0, 0], [0.5, 0.5], [1, 1]]),
            0,
        )

    def test_proper_crossing_reports_interior_side_swaps(self):
        self.assertEqual(
            shared_corridor_audit.proper_crossing_count(
                [[0, 0], [2, 2]], [[0, 2], [2, 0]]),
            1,
        )


if __name__ == "__main__":
    unittest.main()
