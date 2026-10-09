"""Verify shifted legacy debt, increased metrics and incomplete lint evidence."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("quality_debt_report", Path(__file__).resolve().parents[1] / "quality-debt-report.py")
quality = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(quality)
FILE = "ios/RailMap/Route.swift"


def finding(line=1, reason="Function should have complexity 15 or less; currently complexity is 16"):
    return {"file": FILE, "line": line, "rule": "cyclomatic_complexity", "severity": "Warning", "reason": reason}


class DebtComparisonTests(unittest.TestCase):
    def test_unrelated_insertions_preserve_line_identity(self):
        report = quality.compare({FILE: ["func route() {", "}"]}, [finding()],
                                 {FILE: ["// unrelated", "func route() {", "}"]}, [finding(2)])
        self.assertTrue(report["passed"])
        self.assertEqual(report["inherited_findings"], 1)

    def test_increased_complexity_is_not_hidden_by_existing_warning(self):
        report = quality.compare({FILE: ["func route() {"]}, [finding()],
                                 {FILE: ["func route() {"]}, [finding(reason="currently complexity is 17")])
        self.assertFalse(report["passed"])
        self.assertEqual(len(report["new_findings"]), 1)

    def test_changed_warning_declaration_requires_review(self):
        report = quality.compare({FILE: ["func route() {"]}, [finding()],
                                 {FILE: ["func replacement() {"]}, [finding()])
        self.assertFalse(report["passed"])

    def test_multiline_parameter_change_requires_review(self):
        old = ["func route(", "    source: OldSource", ") -> Int {"]
        new = ["func route(", "    source: NewSource", ") -> Int {"]
        report = quality.compare({FILE: old}, [finding()], {FILE: new}, [finding()])
        self.assertFalse(report["passed"])

    def test_default_closure_and_string_braces_do_not_end_declaration(self):
        old = ["func route(", '    action: () -> String = { "}" }', ") -> OldResult {"]
        new = old[:-1] + [") -> NewResult {"]
        report = quality.compare({FILE: old}, [finding()], {FILE: new}, [finding()])
        self.assertFalse(report["passed"])
        self.assertTrue(quality.compare({FILE: old}, [finding()], {FILE: old}, [finding()])["passed"])

    def test_removed_debt_does_not_pay_for_a_new_warning_elsewhere(self):
        other = "ios/RailMap/Other.swift"
        new = dict(finding(), file=other)
        report = quality.compare({FILE: ["func route() {"]}, [finding()],
                                 {other: ["func route() {"]}, [new])
        self.assertFalse(report["passed"])
        self.assertEqual(report["removed_findings"], 1)

    def test_duplicate_findings_are_counted_individually(self):
        report = quality.compare({FILE: ["func route() {"]}, [finding()],
                                 {FILE: ["func route() {"]}, [finding(), finding()])
        self.assertFalse(report["passed"])
        self.assertEqual(len(report["new_findings"]), 1)

    def test_deleted_warning_passes_with_visible_removed_count(self):
        report = quality.compare({FILE: ["func route() {"]}, [finding()], {}, [])
        self.assertTrue(report["passed"])
        self.assertEqual(report["removed_findings"], 1)

    def test_report_reader_fails_closed_on_missing_sources_and_failed_tool(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name); report = root / "reports"; report.mkdir()
            source = root / FILE; source.parent.mkdir(parents=True); source.write_text("func route() {}\n")
            summary = {"source_file_count": 1, "tools": {"swiftlint": {
                "actual_version": "0.65.1", "version_exit_status": 0, "exit_status": 0, "status": "passed"}}}
            (report / "summary.json").write_text(json.dumps(summary))
            (report / "sources.txt").write_text(str(source) + "\n")
            (report / "swiftlint.json").write_text("[]")
            self.assertEqual(len(quality.read_run(report, root)[0]), 1)
            summary["tools"]["swiftlint"]["exit_status"] = 127
            (report / "summary.json").write_text(json.dumps(summary))
            with self.assertRaises(ValueError): quality.read_run(report, root)
            summary["tools"]["swiftlint"]["exit_status"] = 0
            summary["source_file_count"] = 2
            (report / "summary.json").write_text(json.dumps(summary))
            with self.assertRaises(ValueError): quality.read_run(report, root)


if __name__ == "__main__":
    unittest.main()
