import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
RAIL_ROOT = REPO_ROOT / "app" / "public" / "rail"


class AuditHotspotRegistryTests(unittest.TestCase):
    def setUp(self):
        self.registry = json.loads(
            (RAIL_ROOT / "audit-hotspots.json").read_text(encoding="utf-8")
        )

    def test_registry_is_reviewed_and_each_camera_is_valid(self):
        self.assertEqual(
            self.registry["format"], "jtm-railway-audit-hotspots-v1"
        )
        self.assertRegex(self.registry["reviewedAt"], r"^\d{4}-\d{2}-\d{2}$")

        hotspots = self.registry["hotspots"]
        self.assertGreaterEqual(len(hotspots), 5)
        self.assertEqual(len({row["id"] for row in hotspots}), len(hotspots))
        for row in hotspots:
            self.assertRegex(row["id"], r"^[a-z0-9-]+$")
            self.assertIn(row["region"], {"jp", "tw", "hk", "mo", "kr", "us", "ca"})
            self.assertTrue(row["reason"].strip())
            self.assertTrue(row["lineIds"])
            latitude, longitude, span = row["camera"]
            self.assertGreaterEqual(latitude, -90)
            self.assertLessEqual(latitude, 90)
            self.assertGreaterEqual(longitude, -180)
            self.assertLessEqual(longitude, 180)
            self.assertGreater(span, 0)
            self.assertLessEqual(span, 1)

    def test_every_reviewed_line_still_exists_in_its_canonical_package(self):
        packages = {}
        for region in {row["region"] for row in self.registry["hotspots"]}:
            payload = json.loads(
                (RAIL_ROOT / f"{region}-2025.json").read_text(encoding="utf-8")
            )
            packages[region] = {line["id"] for line in payload["lines"]}

        for row in self.registry["hotspots"]:
            with self.subTest(hotspot=row["id"]):
                self.assertLessEqual(set(row["lineIds"]), packages[row["region"]])


if __name__ == "__main__":
    unittest.main()
