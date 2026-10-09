"""Small LCOV/diff fixtures; no Swift builds or production data are loaded."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "coverage-report.py"
SPEC = importlib.util.spec_from_file_location("coverage_report", SCRIPT)
coverage_report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(coverage_report)
ROOT = Path("/frozen/candidate")
CORE = "ios/RailKit/Sources/RailCore/Route.swift"
APP = "ios/RailMap/Sharing.swift"


class CoverageParserTests(unittest.TestCase):
    def test_standalone_package_root_maps_to_repository_identity(self):
        self.assertEqual(coverage_report.normalize_path(
            "/frozen/candidate/Sources/RailCore/Route.swift", ROOT), CORE)
        self.assertIsNone(coverage_report.normalize_path(
            "/unrelated/Sources/RailCore/Route.swift", ROOT))

    def test_repeated_records_and_binaries_union_lines_with_max_hits(self):
        first = coverage_report.parse_lcov(
            f"SF:/frozen/baseline/{CORE}\nDA:3,0\nDA:4,2,checksum\nend_of_record\n"
            f"SF:{CORE}\nDA:3,5\nDA:5,0\nend_of_record\n", ROOT)
        second = coverage_report.parse_lcov(
            f"SF:/another/candidate/{CORE}\nDA:3,1\nDA:4,7\nDA:6,0\nend_of_record\n", ROOT)
        merged = coverage_report.merge_coverage([first, second])
        self.assertEqual(merged, {CORE: {3: 5, 4: 7, 5: 0, 6: 0}})
        report = coverage_report.make_report(merged, {CORE: {3, 5}}, set(), ROOT)
        self.assertEqual(report["totals"]["overall"]["percent"], 50)
        self.assertEqual(report["totals"]["changed"]["percent"], 50)

    def test_short_hunks_zero_count_and_actual_added_line_positions(self):
        diff = f"""diff --git a/{CORE} b/{CORE}
--- a/{CORE}
+++ b/{CORE}
@@ -3 +3 @@ old function
-old
+new
@@ -7,0 +8,2 @@
+first
+second
@@ -20,2 +22,0 @@
-removed
-removed again
"""
        changed, deleted = coverage_report.parse_diff(diff, ROOT)
        self.assertEqual(changed, {CORE: {3, 8, 9}})
        self.assertEqual(deleted, set())

    def test_context_lines_and_content_resembling_headers_are_not_added_headers(self):
        diff = f"""--- a/{APP}
+++ b/{APP}
@@ -1,2 +1,3 @@
 context
-old
+++ file content, not a new header
+another
"""
        changed, _ = coverage_report.parse_diff(diff, ROOT)
        self.assertEqual(changed[APP], {2, 3})

    def test_deleted_only_and_removed_files_do_not_require_candidate_mapping(self):
        diff = f"""--- a/{APP}
+++ b/{APP}
@@ -7 +6,0 @@
-deleted
--- a/{CORE}
+++ /dev/null
@@ -1 +0,0 @@
-removed file
"""
        changed, deleted = coverage_report.parse_diff(diff, ROOT)
        report = coverage_report.make_report({}, changed, deleted, ROOT)
        self.assertEqual(changed, {APP: set()})
        self.assertEqual(report["deleted_files"], [CORE])
        self.assertEqual(report["totals"]["changed"]["unmapped_files"], [])
        self.assertIsNone(report["totals"]["changed"]["percent"])
        self.assertTrue(report["gate"]["passed"])

    def test_comments_are_excluded_only_in_a_mapped_file(self):
        report = coverage_report.make_report({CORE: {3: 1}}, {CORE: {3, 4}, APP: {9}}, set(), ROOT)
        by_path = {entry["path"]: entry for entry in report["files"]}
        self.assertEqual(by_path[CORE]["excluded_non_executable_lines"], [4])
        self.assertEqual(by_path[APP]["excluded_non_executable_lines"], [])
        self.assertEqual(by_path[APP]["unmapped_source_lines"], [9])
        self.assertEqual(report["totals"]["changed"]["unmapped_files"], [APP])
        self.assertFalse(report["gate"]["passed"])

    def test_empty_denominators_are_unknown_and_configured_thresholds_fail(self):
        report = coverage_report.make_report({APP: {}}, {APP: {1}}, set(), ROOT,
                                             minimum_line=0, minimum_changed=0)
        self.assertIsNone(report["totals"]["overall"]["percent"])
        self.assertIsNone(report["totals"]["changed"]["percent"])
        self.assertEqual(report["files"][0]["excluded_non_executable_lines"], [1])
        self.assertFalse(report["gate"]["passed"])
        self.assertEqual(len(report["gate"]["failures"]), 2)

    def test_threshold_uses_coverage_not_duplicate_hit_sum(self):
        report = coverage_report.make_report({CORE: {1: 100, 2: 0, 3: 0}}, {CORE: {1, 2}}, set(), ROOT,
                                             minimum_line=34, minimum_changed=50)
        self.assertFalse(report["gate"]["passed"])
        self.assertEqual(len(report["gate"]["failures"]), 1)
        self.assertIn("overall", report["gate"]["failures"][0])

    def test_normalizes_absolute_prefixes_relative_paths_and_quoted_spaces(self):
        for path in (f"/frozen/baseline/{APP}", f"/frozen/candidate/{APP}",
                     f"a/frozen/baseline/{APP}", f"b/frozen/candidate/{APP}",
                     APP, "./" + APP, "RailMap/Sharing.swift"):
            self.assertEqual(coverage_report.normalize_path(path, ROOT), APP)
        spaced = '"b/frozen/candidate/ios/RailMap/Share Card.swift"'
        self.assertEqual(coverage_report.normalize_path(spaced, ROOT), "ios/RailMap/Share Card.swift")
        self.assertEqual(coverage_report.normalize_path("/snapshot/RailKit/Sources/RailCore/Route.swift", Path("/snapshot")), CORE)

    def test_tests_resources_and_non_swift_are_outside_scope(self):
        for path in ("ios/RailMapUITests/Sharing.swift", "ios/RailKit/Tests/RailCoreTests/Route.swift",
                     "ios/RailKit/Sources/RailCore/Resources/Fixture.swift", "ios/RailMap/Resources/Test.swift",
                     "ios/RailMap/Sharing.json", "app/public/rail/Route.swift"):
            self.assertIsNone(coverage_report.normalize_path(path, ROOT), path)

    def test_git_octal_utf8_paths_keep_the_same_lcov_identity(self):
        path = "ios/RailMap/東京.swift"
        quoted = r'"b/baseline/ios/RailMap/\346\235\261\344\272\254.swift"'
        self.assertEqual(coverage_report.normalize_path(quoted, ROOT), path)
        changed, _ = coverage_report.parse_diff(
            f"--- /dev/null\n+++ {quoted}\n@@ -0,0 +1 @@\n+source\n", ROOT)
        report = coverage_report.make_report({path: {1: 1}}, changed, set(), ROOT, minimum_changed=100)
        self.assertTrue(report["gate"]["passed"])

    def test_module_and_include_totals_are_scoped_explicitly(self):
        presentation = "ios/RailKit/Sources/RailPresentation/State.swift"
        data = {CORE: {1: 1}, APP: {1: 0}, presentation: {1: 1, 2: 0}}
        report = coverage_report.make_report(data, {CORE: {1}, APP: {1}}, set(), ROOT)
        self.assertEqual(set(report["modules"]), {"RailCore", "RailMap", "RailPresentation"})
        self.assertEqual(report["modules"]["RailMap"]["changed"]["percent"], 0)
        scoped = coverage_report.make_report(data, {CORE: {1}, APP: {1}}, set(), ROOT,
                                             includes=["ios/RailKit/Sources/RailCore"], minimum_line=100)
        self.assertEqual(set(scoped["modules"]), {"RailCore"})
        self.assertTrue(scoped["gate"]["passed"])
        self.assertIn("completeness", scoped["interpretation"])

    def test_malformed_records_or_truncated_hunks_fail_instead_of_partial_report(self):
        for record in ("DA:1,3", f"SF:{APP}\nDA:0,3", f"SF:{APP}\nDA:3,-1",
                       f"SF:{APP}\nDA:no,3", f"SF:{APP}\nDA:1"):
            with self.assertRaises(ValueError):
                coverage_report.parse_lcov(record, ROOT)
        for diff in (f"+++ b/{APP}\n@@ -1 +1,2 @@\n+one\n",
                     f"+++ b/{APP}\n@@ not a hunk\n"):
            with self.assertRaises(ValueError):
                coverage_report.parse_diff(diff, ROOT)


class CoverageCLITests(unittest.TestCase):
    def run_report(self, directory, lcov, diff, *extra):
        root = Path(directory)
        inputs = []
        for number, text in enumerate(lcov):
            path = root / f"{number}.lcov"
            path.write_text(text)
            inputs.extend(["--lcov", str(path)])
        patch = root / "candidate.diff"
        patch.write_text(diff)
        output = root / "reports" / "coverage.json"
        result = subprocess.run([sys.executable, str(SCRIPT), *inputs, "--diff", str(patch),
                                 "--source-root", str(root), "--output", str(output), *extra],
                                capture_output=True, text=True)
        return result, json.loads(output.read_text()) if output.exists() else None

    def test_cli_repeated_lcov_inputs_and_passing_gate(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, report = self.run_report(
                temporary, [f"SF:{CORE}\nDA:1,0\nend_of_record\n", f"SF:{CORE}\nDA:1,1\nend_of_record\n"],
                f"--- a/{CORE}\n+++ b/{CORE}\n@@ -1 +1 @@\n-old\n+new\n",
                "--minimum-changed-line-coverage", "100")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(report["totals"]["overall"]["executable_lines"], 1)
            self.assertEqual(report["totals"]["changed"]["percent"], 100)

    def test_unmapped_change_fails_cli_even_without_percentage_threshold(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, report = self.run_report(temporary, [""],
                f"--- /dev/null\n+++ b/{APP}\n@@ -0,0 +1 @@\n+new\n")
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertFalse(report["gate"]["passed"])
            self.assertEqual(report["totals"]["changed"]["unmapped_files"], [APP])

    def test_invalid_threshold_does_not_create_a_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, report = self.run_report(temporary, [""], "", "--minimum-line-coverage", "101")
            self.assertEqual(result.returncode, 2)
            self.assertIsNone(report)

    def test_include_cannot_select_tests_resources_or_escape_production(self):
        for scope in ("ios/RailMap/../../Tests", "ios/RailKit/Sources/RailCore/Resources", "ios/RailMapUITests"):
            with self.subTest(scope=scope), tempfile.TemporaryDirectory() as temporary:
                result, report = self.run_report(temporary, [""], "", "--include", scope)
                self.assertEqual(result.returncode, 2)
                self.assertIsNone(report)


if __name__ == "__main__":
    unittest.main()
