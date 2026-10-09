"""Exercise bundle discovery and LLVM command receipts through a fake runner."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "export-package-coverage.py"
SPEC = importlib.util.spec_from_file_location("export_package_coverage", SCRIPT)
exporter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exporter)
LCOV = "SF:/frozen/ios/RailKit/Sources/RailCore/Route.swift\nDA:1,1\nend_of_record\n"


def binary(path: Path, content: bytes = b"instrumented fake binary") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    path.chmod(0o755)
    return path


def bundle(products: Path, name: str, executable_name: str | None = None, flat: bool = False) -> Path:
    root = products / f"{name}.xctest"
    executable_name = executable_name or name
    executable = root / executable_name if flat else root / "Contents" / "MacOS" / executable_name
    binary(executable)
    metadata = root / "Info.plist" if flat else root / "Contents" / "Info.plist"
    with metadata.open("wb") as destination:
        plistlib.dump({"CFBundleExecutable": executable_name}, destination)
    return executable


class DiscoveryTests(unittest.TestCase):
    def test_xcode27_per_target_bundles_are_all_discovered(self):
        with tempfile.TemporaryDirectory() as temporary:
            products = Path(temporary)
            expected = [bundle(products, target) for target in
                        ("RailCoreTests", "RailPresentationTests", "RailApplicationTests")]
            self.assertEqual(exporter.discover_executables(products), sorted(path.resolve() for path in expected))

    def test_plist_executable_name_and_flat_bundle_layout(self):
        with tempfile.TemporaryDirectory() as temporary:
            products = Path(temporary)
            custom = bundle(products, "Package", "ActualRunner")
            flat = bundle(products, "FlatRunner", flat=True)
            self.assertEqual(exporter.discover_executables(products), sorted([custom.resolve(), flat.resolve()]))

    def test_legacy_bundle_without_plist_and_executable_xctest_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            products = Path(temporary)
            legacy = binary(products / "Legacy.xctest" / "Contents" / "MacOS" / "Legacy")
            standalone = binary(products / "Standalone.xctest")
            self.assertEqual(exporter.discover_executables(products), sorted([legacy.resolve(), standalone.resolve()]))

    def test_missing_products_empty_products_and_missing_bundle_binary_reject(self):
        with tempfile.TemporaryDirectory() as temporary:
            products = Path(temporary)
            for path in (products / "missing", products):
                with self.assertRaises(ValueError):
                    exporter.discover_executables(path)
            (products / "Broken.xctest").mkdir()
            with self.assertRaisesRegex(ValueError, "Expected one executable"):
                exporter.discover_executables(products)

    def test_nonexecutable_or_ambiguous_bundle_cannot_silently_disappear(self):
        with tempfile.TemporaryDirectory() as temporary:
            products = Path(temporary)
            executable = bundle(products, "Package")
            executable.chmod(0o644)
            with self.assertRaises(ValueError):
                exporter.discover_executables(products)
            executable.chmod(0o755)
            binary(products / "Package.xctest" / "Package")
            with self.assertRaises(ValueError):
                exporter.discover_executables(products)


class ExportTests(unittest.TestCase):
    def inputs(self, root):
        root = Path(root)
        products = root / "products"
        executable = bundle(products, "RailApplicationTests")
        profile = root / "merged.profdata"
        profile.write_bytes(b"matching merged profile")
        return products, executable, profile, root / "reports"

    def test_separate_exports_record_identity_commands_and_profile_is_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            products, executable, profile, outputs = self.inputs(temporary)
            second = bundle(products, "RailCoreTests")
            calls = []

            def runner(command, output):
                calls.append(command)
                output.write_text(LCOV)
                return 0, ""

            before_profile = profile.read_bytes()
            before_binaries = {path.resolve(): path.read_bytes() for path in (executable, second)}
            report = exporter.export_coverage(profile, outputs, products=products, runner=runner)
            self.assertEqual(report["status"], "passed")
            self.assertEqual(len(report["exports"]), 2)
            self.assertEqual(len({item["lcov"] for item in report["exports"]}), 2)
            self.assertEqual(report["profile"]["sha256"], hashlib.sha256(before_profile).hexdigest())
            for item in report["exports"]:
                path = Path(item["executable"])
                self.assertEqual(item["binary_sha256"], hashlib.sha256(before_binaries[path]).hexdigest())
                self.assertEqual(item["command"], ["xcrun", "llvm-cov", "export", "--format=lcov",
                                                  f"--instr-profile={profile.resolve()}", str(path)])
                self.assertEqual(item["exit_code"], 0)
                self.assertTrue(item["has_source_records"])
                self.assertEqual(Path(item["lcov"]).read_text(), LCOV)
            self.assertEqual(profile.read_bytes(), before_profile)
            self.assertEqual({path: path.read_bytes() for path in before_binaries}, before_binaries)
            self.assertEqual(json.loads((outputs / "manifest.json").read_text()), report)
            self.assertIn("completeness", report["interpretation"])

    def test_explicit_binaries_override_discovery_and_duplicate_aliases_are_removed(self):
        with tempfile.TemporaryDirectory() as temporary:
            products, _, profile, outputs = self.inputs(temporary)
            explicit = binary(Path(temporary) / "other-layout" / "Runner")
            calls = []

            def runner(command, output):
                calls.append(command)
                output.write_text(LCOV)
                return 0, ""

            report = exporter.export_coverage(profile, outputs, products=products,
                                              explicit=[explicit, explicit], runner=runner)
            self.assertEqual(len(calls), 1)
            self.assertEqual(report["exports"][0]["executable"], str(explicit.resolve()))
            self.assertEqual(report["discovery"], "explicit executables")

    def test_missing_profile_binary_or_executable_inputs_never_call_tool(self):
        with tempfile.TemporaryDirectory() as temporary:
            products, _, profile, outputs = self.inputs(temporary)
            def forbidden(command, output):
                self.fail("LLVM must not run with invalid inputs")
            for options in ({"profile": profile.parent / "missing", "products": products},
                            {"profile": profile, "explicit": [profile.parent / "missing-binary"]},
                            {"profile": profile}):
                with self.assertRaises(ValueError):
                    exporter.export_coverage(output_directory=outputs, runner=forbidden, **options)
            self.assertFalse((outputs / "manifest.json").exists())

    def test_tool_failures_and_no_mapping_write_failed_manifest(self):
        for return_code, lcov in ((1, LCOV), (0, ""), (0, "SF:truncated\n")):
            with self.subTest(return_code=return_code, lcov=lcov), tempfile.TemporaryDirectory() as temporary:
                products, _, profile, outputs = self.inputs(temporary)
                def runner(command, output):
                    output.write_text(lcov)
                    return return_code, "tool diagnostic"
                report = exporter.export_coverage(profile, outputs, products=products, runner=runner)
                self.assertEqual(report["status"], "failed")
                self.assertEqual(report["exports"][0]["status"], "failed")
                self.assertEqual(report["exports"][0]["exit_code"], return_code)
                self.assertEqual(report["exports"][0]["stderr"], "tool diagnostic")
                self.assertTrue((outputs / "manifest.json").exists())

    def test_missing_tool_records_actual_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            products, _, profile, outputs = self.inputs(temporary)
            def runner(command, output):
                raise FileNotFoundError("xcrun missing")
            report = exporter.export_coverage(profile, outputs, products=products, runner=runner)
            self.assertEqual(report["status"], "failed")
            self.assertIsNone(report["exports"][0]["exit_code"])
            self.assertIn("xcrun missing", report["exports"][0]["failure"])

    def test_runner_streams_stdout_to_disk_instead_of_capture_buffer(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "export.lcov"
            def fake_process(command, *, stdout, stderr, text):
                self.assertEqual(command, ["fake-tool"])
                self.assertTrue(text)
                self.assertEqual(stderr, exporter.subprocess.PIPE)
                stdout.write(LCOV)
                return SimpleNamespace(returncode=0, stderr="")
            with patch.object(exporter.subprocess, "run", fake_process):
                self.assertEqual(exporter.run_export(["fake-tool"], output), (0, ""))
            self.assertEqual(output.read_text(), LCOV)

    def test_output_cannot_overwrite_profile(self):
        with tempfile.TemporaryDirectory() as temporary:
            products, _, _, outputs = self.inputs(temporary)
            outputs.mkdir()
            profile = outputs / "manifest.json"
            profile.write_bytes(b"profile")
            with self.assertRaisesRegex(ValueError, "overwrite"):
                exporter.export_coverage(profile, outputs, products=products)
            self.assertEqual(profile.read_bytes(), b"profile")

    def test_cli_status_matches_manifest_and_repeatable_executables(self):
        for status in (0, 1):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temporary:
                _, executable, profile, outputs = self.inputs(temporary)
                def runner(command, output):
                    output.write_text(LCOV)
                    return status, ""
                with patch("builtins.print"):
                    code = exporter.main(["--profile", str(profile), "--output-dir", str(outputs),
                                          "--executable", str(executable), "--executable", str(executable)], runner)
                self.assertEqual(code, status)
                report = json.loads((outputs / "manifest.json").read_text())
                self.assertEqual(len(report["exports"]), 1)
                self.assertEqual(report["status"], "passed" if status == 0 else "failed")


if __name__ == "__main__":
    unittest.main()
