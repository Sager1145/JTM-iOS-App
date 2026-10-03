"""Fixture checks for the production Swift ownership gate.

The tests build a temporary repository and run the checker. They do not
reimplement discovery, import rules, or manifest comparison.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "verify-source-ownership.py"

ACTIVE = {
    "app-root": ["ios/RailMap/AppShell.swift"],
    "rail-core": [
        "ios/RailKit/Sources/RailCore/Model.swift",
        "ios/RailKit/Sources/RailCore/TrainTimetableDatabase.swift",
    ],
    "rail-presentation": ["ios/RailKit/Sources/RailPresentation/ViewState.swift"],
    "rail-application": ["ios/RailKit/Sources/RailApplication/UseCase.swift"],
}


class SourceOwnershipTests(unittest.TestCase):
    def test_help_exits_successfully(self) -> None:
        result = subprocess.run([sys.executable, str(SCRIPT), "--help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--repo-root", result.stdout)

    def test_valid_fixture_passes_from_another_directory(self) -> None:
        with tempfile.TemporaryDirectory() as repo_name, tempfile.TemporaryDirectory() as cwd_name:
            repo = Path(repo_name)
            write_fixture(repo)
            write_manifest(repo, ACTIVE)
            result = run_checker(repo, Path(cwd_name))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("ok:"))
        self.assertEqual(result.stderr, "")

    def test_missing_assignment(self) -> None:
        groups = {key: list(value) for key, value in ACTIVE.items()}
        groups["app-root"] = []
        with tempfile.TemporaryDirectory() as repo_name, tempfile.TemporaryDirectory() as cwd_name:
            repo = Path(repo_name)
            write_fixture(repo)
            write_manifest(repo, groups)
            result = run_checker(repo, Path(cwd_name))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unassigned: ios/RailMap/AppShell.swift", result.stderr)

    def test_duplicate_assignment(self) -> None:
        groups = {key: list(value) for key, value in ACTIVE.items()}
        groups["rail-presentation"] = groups["rail-presentation"] + [
            "ios/RailMap/AppShell.swift"
        ]
        with tempfile.TemporaryDirectory() as repo_name, tempfile.TemporaryDirectory() as cwd_name:
            repo = Path(repo_name)
            write_fixture(repo)
            write_manifest(repo, groups)
            result = run_checker(repo, Path(cwd_name))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate: ios/RailMap/AppShell.swift is assigned 2 times", result.stderr)

    def test_prohibited_import(self) -> None:
        with tempfile.TemporaryDirectory() as repo_name, tempfile.TemporaryDirectory() as cwd_name:
            repo = Path(repo_name)
            write_fixture(repo)
            target = repo / "ios/RailKit/Sources/RailApplication/UseCase.swift"
            target.write_text(
                "import Foundation\nimport SwiftUI\nimport RailPresentation\n",
                encoding="utf-8",
            )
            write_manifest(repo, ACTIVE)
            result = run_checker(repo, Path(cwd_name))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "forbidden-import: ios/RailKit/Sources/RailApplication/UseCase.swift imports SwiftUI",
            result.stderr,
        )
        self.assertIn(
            "forbidden-import: ios/RailKit/Sources/RailApplication/UseCase.swift imports RailPresentation",
            result.stderr,
        )

    def test_source_addition_drift(self) -> None:
        with tempfile.TemporaryDirectory() as repo_name, tempfile.TemporaryDirectory() as cwd_name:
            repo = Path(repo_name)
            cwd = Path(cwd_name)
            write_fixture(repo)
            write_manifest(repo, ACTIVE)
            baseline = run_checker(repo, cwd)
            self.assertEqual(baseline.returncode, 0, baseline.stderr)
            added = repo / "ios/RailKit/Sources/RailApplication/AnotherUseCase.swift"
            added.write_text("import Foundation\nimport RailCore\n", encoding="utf-8")
            result = run_checker(repo, cwd)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"unassigned: {added.relative_to(repo).as_posix()}", result.stderr)

    def test_missing_source(self) -> None:
        groups = {key: list(value) for key, value in ACTIVE.items()}
        groups["app-root"].append("ios/RailMap/DoesNotExist.swift")
        with tempfile.TemporaryDirectory() as repo_name, tempfile.TemporaryDirectory() as cwd_name:
            repo = Path(repo_name)
            write_fixture(repo)
            write_manifest(repo, groups)
            result = run_checker(repo, Path(cwd_name))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing: ios/RailMap/DoesNotExist.swift", result.stderr)


def run_checker(repo: Path, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--repo-root", str(repo)],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )


def write_manifest(repo: Path, groups: dict[str, list[str]]) -> None:
    payload = {
        "version": 1,
        "groups": [
            {
                "id": group_id,
                "responsibility": f"{group_id} fixture responsibility",
                "validation": [{"id": "fixture", "command": "fixture"}],
                "sources": sources,
            }
            for group_id, sources in groups.items()
        ],
    }
    path = repo / "ios/source-ownership.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def write_fixture(repo: Path) -> None:
    files = {
        "ios/RailMap.xcodeproj/project.pbxproj": PBXPROJ,
        "ios/RailKit/Package.swift": PACKAGE,
        "ios/RailMap/AppShell.swift": "import SwiftUI\n",
        "ios/RailMap/AppShell 2.swift": "import UIKit\n",
        "ios/RailMap/sync-conflicts/Ghost.swift": "import SwiftUI\n",
        "ios/RailMapUITests/Hidden.swift": "import SwiftUI\n",
        "ios/RailKit/Sources/RailCore/Model.swift": "// import SwiftUI\n/* import UIKit */\nimport Foundation\n",
        "ios/RailKit/Sources/RailCore/TrainTimetableDatabase.swift": "import Foundation\nimport SQLite3\n",
        "ios/RailKit/Sources/RailCore/Resources/Skip.swift": "import SwiftUI\n",
        "ios/RailKit/Sources/RailCore/.build/Ghost.swift": "import SwiftUI\n",
        "ios/RailKit/Sources/RailCoreTests/ShouldNotCount.swift": "import SwiftUI\n",
        "ios/RailKit/Tests/RailCoreTests/Hidden.swift": "import SwiftUI\n",
        "ios/RailKit/.build/Ghost.swift": "import SwiftUI\n",
        "ios/RailKit/Sources/RailPresentation/ViewState.swift": "import Foundation\nimport RailCore\n",
        "ios/RailKit/Sources/RailApplication/UseCase.swift": "import Foundation\nimport Observation\nimport RailCore\n",
    }
    for relative, content in files.items():
        path = repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(textwrap.dedent(content), encoding="utf-8")


PBXPROJ = """\
// !$*UTF8*$!
{
	objects = {
		AABBCCDDEEFF001122334455 /* RailMap */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = RailMap;
			sourceTree = "<group>";
		};
		AABBCCDDEEFF001122334456 /* RailMapUITests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = RailMapUITests;
			sourceTree = "<group>";
		};
		AABBCCDDEEFF001122334401 /* RailMap */ = {
			isa = PBXNativeTarget;
			fileSystemSynchronizedGroups = (
				AABBCCDDEEFF001122334455 /* RailMap */,
			);
			name = RailMap;
			productType = "com.apple.product-type.application";
		};
		AABBCCDDEEFF001122334402 /* RailMapUITests */ = {
			isa = PBXNativeTarget;
			fileSystemSynchronizedGroups = (
				AABBCCDDEEFF001122334456 /* RailMapUITests */,
			);
			name = RailMapUITests;
			productType = "com.apple.product-type.bundle.ui-testing";
		};
		AABBCCDDEEFF001122334400 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				LastUpgradeCheck = 2700;
			};
			projectDirPath = "";
			targets = (
				AABBCCDDEEFF001122334401 /* RailMap */,
				AABBCCDDEEFF001122334402 /* RailMapUITests */,
			);
		};
	};
}
"""

PACKAGE = """\
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RailKit",
    targets: [
        .testTarget(name: "RailCoreTests", dependencies: ["RailCore"]),
        .target(name: "RailCore"),
        .target(name: "RailPresentation", dependencies: ["RailCore"]),
        .target(name: "RailApplication", dependencies: ["RailCore"]),
    ]
)
"""


if __name__ == "__main__":
    unittest.main()
