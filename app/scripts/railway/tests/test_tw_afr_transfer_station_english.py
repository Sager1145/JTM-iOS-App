"""Operator-scoped proof for the shared TRA/AFR Chiayi station."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "verify-tw-afr-transfer-station-english.py"
spec = importlib.util.spec_from_file_location("afr_transfer", SCRIPT)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class AFRTransferTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # An existing but incomplete archive must still fail its original checks.
        if not verifier.RAW.exists():
            raise unittest.SkipTest("本地官方原始证据未提供: " + str(verifier.RAW))
        cls.manifest = json.loads((verifier.RAW / "manifest.json").read_text())
        cls.raw = {key: (verifier.RAW / row["filename"]).read_bytes() for key, row in cls.manifest.items()}
        cls.package = json.loads((verifier.APP / "public/rail/tw-2025.json").read_text())

    def test_only_afr_membership_is_verified(self):
        result = verifier.build(self.package, self.raw, self.manifest)
        self.assertEqual(list(result["byLineStation"]), ["tw-alsr-alishan:tw-official-tra-4080"])
        row = next(iter(result["byLineStation"].values()))
        self.assertEqual(row["en"], "Chiayi")
        self.assertEqual(row["identityEvidence"][0]["en"], "Chiayi Station")

    def test_package_operator_change_rejects_evidence(self):
        package = copy.deepcopy(self.package)
        next(line for line in package["lines"] if line["id"] == "tw-alsr-alishan")["operator"] = "Other Operator"
        with self.assertRaisesRegex(ValueError, "package identity changed"):
            verifier.build(package, self.raw, self.manifest)

    def test_source_change_requires_review(self):
        raw = dict(self.raw)
        raw["en"] += b" "
        with self.assertRaisesRegex(ValueError, "source hash mismatch"):
            verifier.build(self.package, raw, self.manifest)


if __name__ == "__main__":
    unittest.main()
