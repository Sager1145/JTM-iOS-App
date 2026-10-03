import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from train_timetable import load_dataset, entity_paths, source_fingerprint


class TimetableCopyInputTests(unittest.TestCase):
    def test_only_identical_numbered_copies_are_skipped_and_all_inputs_remain(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            row = json.dumps({"operator_id": "original"}) + "\n"
            (root / "operators.jsonl").write_text(row)
            (root / "operators 2.jsonl").write_text(row)
            (root / "operators 10.jsonl").write_text(row)
            (root / "operators 3.jsonl").write_text(json.dumps({"operator_id": "different"}) + "\n")
            manifest = {"entities": {"operators": ["operators*.jsonl"]}}
            data, _ = load_dataset(root, manifest)
            self.assertEqual(sorted(r["operator_id"] for r in data["operators"]), ["different", "original"])
            self.assertEqual(len(entity_paths(root, ["operators*.jsonl"])), 4)
            self.assertEqual(len(list(root.glob("*.jsonl"))), 4)

    def test_numbered_file_without_original_is_never_discarded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "operators 2.jsonl").write_text(json.dumps({"operator_id": "only"}) + "\n")
            data, _ = load_dataset(root, {"entities": {"operators": ["operators*.jsonl"]}})
            self.assertEqual(data["operators"], [{"operator_id": "only"}])

    def test_exact_copies_do_not_change_source_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = {"schema_path": "schema.sql", "entities": {"operators": ["operators*.jsonl"]}}
            (root / "manifest.json").write_text(json.dumps(manifest))
            (root / "schema.sql").write_text("fixture schema")
            original = root / "operators.jsonl"
            original.write_text(json.dumps({"operator_id": "original"}) + "\n")
            expected = source_fingerprint(root, manifest)
            for suffix in [2, 10]:
                (root / f"operators {suffix}.jsonl").write_bytes(original.read_bytes())
            self.assertEqual(source_fingerprint(root, manifest), expected)
            (root / "operators 2.jsonl").unlink()
            (root / "operators 10.jsonl").unlink()
            self.assertEqual(source_fingerprint(root, manifest), expected)

    def test_differing_copy_changes_source_fingerprint_and_is_loaded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = {"schema_path": "schema.sql", "entities": {"operators": ["operators*.jsonl"]}}
            (root / "manifest.json").write_text(json.dumps(manifest))
            (root / "schema.sql").write_text("fixture schema")
            (root / "operators.jsonl").write_text(json.dumps({"operator_id": "original"}) + "\n")
            expected = source_fingerprint(root, manifest)
            (root / "operators 2.jsonl").write_text(json.dumps({"operator_id": "different"}) + "\n")
            self.assertNotEqual(source_fingerprint(root, manifest), expected)
            data, _ = load_dataset(root, manifest)
            self.assertEqual(sorted(r["operator_id"] for r in data["operators"]), ["different", "original"])
