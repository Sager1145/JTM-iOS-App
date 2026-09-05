import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "make-display-releases.py"
SPEC = importlib.util.spec_from_file_location("display_releases", SCRIPT)
display_releases = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(display_releases)


class DisplayReleasesTests(unittest.TestCase):
    def test_main_sorts_rows_into_releases_withheld_and_not_measured(self):
        """A (consistent) and C (tunnel-only disagreement) rows are released;
        B (measured and found wrong) stays withheld, with its numbers kept
        as evidence; D (never measured) is recorded separately. The region
        for each row is derived from its package name, not carried
        explicitly."""
        rows = [
            {
                "package": "us-2025", "lineId": "line-a", "index": 0,
                "verdict": "A", "stations": ["a", "b"],
                "limitM": 50.0, "packageMaxDeviationM": 10.0,
                "medianM": 5.0, "p95M": 8.0, "maxM": 9.0,
                "maxAt": "vertex-3", "note": "consistent",
            },
            {
                "package": "us-2025", "lineId": "line-b", "index": 1,
                "verdict": "B", "stations": ["c", "d"],
                "limitM": 50.0, "medianM": 120.0, "maxM": 200.0,
                "maxAt": "vertex-7", "note": "deviates",
            },
            {
                "package": "ca-2025", "lineId": "line-c", "index": 2,
                "verdict": "C", "stations": ["e", "f"],
                "limitM": 60.0, "packageMaxDeviationM": 15.0,
                "medianM": 20.0, "p95M": 25.0, "maxM": 30.0,
                "maxAt": "vertex-2", "note": "tunnel approximation",
            },
            {
                "package": "ca-2025", "lineId": "line-d", "index": 3,
                "stations": ["g", "h"], "note": "not measured",
            },
        ]
        with tempfile.TemporaryDirectory() as root:
            results_path = Path(root) / "results.json"
            results_path.write_text(json.dumps(rows))
            rail_dir = Path(root) / "rail"
            rail_dir.mkdir()

            original_rail = display_releases.RAIL
            display_releases.RAIL = rail_dir
            try:
                display_releases.main(str(results_path))
            finally:
                display_releases.RAIL = original_rail

            out = json.loads((rail_dir / "display-releases.json").read_text())

        self.assertEqual(out["format"], "jtm-display-releases-v1")

        # A and C rows land in `releases`, region derived from the package
        # name ("us-2025" -> "us", "ca-2025" -> "ca"), sorted by
        # (region, lineId, interval) so "ca" sorts before "us".
        releases = out["releases"]
        self.assertEqual(len(releases), 2)
        self.assertEqual(
            [(row["region"], row["lineId"], row["interval"]) for row in releases],
            [("ca", "line-c", 2), ("us", "line-a", 0)])
        self.assertEqual(releases[0]["verdict"], "C")
        self.assertEqual(releases[1]["verdict"], "A")

        # The B row stays withheld, carrying the numbers that justify it.
        withheld = out["withheldAfterMeasurement"]
        self.assertEqual(len(withheld), 1)
        row = withheld[0]
        self.assertEqual(row["region"], "us")
        self.assertEqual(row["lineId"], "line-b")
        self.assertEqual(row["interval"], 1)
        self.assertEqual(row["verdict"], "B")
        self.assertEqual(row["limitMetres"], 50.0)
        self.assertEqual(row["osmMedianMetres"], 120.0)
        self.assertEqual(row["osmMaxMetres"], 200.0)
        self.assertEqual(row["osmMaxAt"], "vertex-7")

        # The D row (no A/B/C verdict) is recorded as not measured.
        self.assertEqual(out["notMeasured"], [["ca", "line-d", 3]])


if __name__ == "__main__":
    unittest.main()
