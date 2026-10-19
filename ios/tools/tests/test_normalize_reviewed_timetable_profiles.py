"""Shared profile CLI keeps the reviewed coupled-column record semantics."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parents[1]
BASE = ROOT / "app/data/train-service-history"
FIXTURES = Path(__file__).resolve().parent / "fixtures/reviewed-timetable-profiles"
CLI = TOOLS / "normalize-reviewed-timetable.py"
PROFILES = {
    "nex1": BASE / "candidates/jr-east-narita-express1-20260930.profile.json",
    "nex7": BASE / "candidates/jr-east-narita-express7-20260930.profile.json",
}


def records(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def evidence(path):
    return {item.relative_to(path): item.read_bytes()
            for item in path.rglob("*.jsonl")}


class ReviewedTimetableProfileTests(unittest.TestCase):
    def test_two_profiles_match_legacy_records(self):
        for name, profile_path in PROFILES.items():
            with self.subTest(profile=name), tempfile.TemporaryDirectory() as scratch:
                base = Path(scratch)
                profile = json.loads(profile_path.read_text(encoding="utf-8"))
                candidate = base / profile["candidate"]
                candidate.parent.mkdir(parents=True)
                shutil.copy2(BASE / profile["candidate"], candidate)
                proc = subprocess.run(
                    [sys.executable, str(CLI), "--profile", str(profile_path),
                     "--base", str(base), "--write"],
                    cwd=ROOT, capture_output=True, text=True)
                self.assertEqual(proc.returncode, 0, proc.stderr)
                golden = FIXTURES / name
                expected = {path.relative_to(golden).as_posix(): records(path)
                            for path in golden.rglob("*.jsonl")}
                actual = {}
                for path in base.rglob("*.jsonl"):
                    rel = path.relative_to(base).as_posix()
                    if profile["suffix"] in rel:
                        actual[rel] = records(path)
                self.assertEqual(expected, actual)

    def test_changed_source_pinned_seat_is_rejected(self):
        with tempfile.TemporaryDirectory() as scratch:
            base = Path(scratch)
            profile_path = PROFILES["nex1"]
            profile = json.loads(profile_path.read_text(encoding="utf-8"))
            candidate = base / profile["candidate"]
            candidate.parent.mkdir(parents=True)
            shutil.copy2(BASE / profile["candidate"], candidate)
            sentinel = base / "normalized/fact-completeness-kept.jsonl"
            sentinel.parent.mkdir(parents=True)
            sentinel.write_text('{"notes":"Previously accepted evidence"}\n', encoding="utf-8")
            before = evidence(base)
            profile["pinned"]["trips"][0]["equipment"][0] = "changed-seat"
            mutated = Path(scratch) / "mutated.profile.json"
            mutated.write_text(json.dumps(profile, ensure_ascii=False), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, str(CLI), "--profile", str(mutated),
                 "--base", str(base), "--write"],
                cwd=ROOT, capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn(
                "Source-pinned column, calendar, seat or coupling fact changed",
                proc.stderr)
            self.assertEqual([], [str(path) for path in before.keys() | evidence(base).keys()
                                  if before.get(path) != evidence(base).get(path)])

    def test_default_does_not_write(self):
        with tempfile.TemporaryDirectory() as scratch:
            base = Path(scratch)
            profile_path = PROFILES["nex7"]
            profile = json.loads(profile_path.read_text(encoding="utf-8"))
            candidate = base / profile["candidate"]
            candidate.parent.mkdir(parents=True)
            shutil.copy2(BASE / profile["candidate"], candidate)
            before = evidence(base)
            proc = subprocess.run(
                [sys.executable, str(CLI), "--profile", str(profile_path), "--base", str(base)],
                cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("dry-run, not written", proc.stdout)
            self.assertEqual(before, evidence(base))


if __name__ == "__main__":
    unittest.main()
