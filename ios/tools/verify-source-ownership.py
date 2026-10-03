#!/usr/bin/env python3
"""Check active production Swift files against ios/source-ownership.json.

Discovers sources from the RailMap application's explicit synchronized root
and from RailKit `.target` directories (not test targets). Skips package
Resources, `.build`, and sync-conflict copies. Fails when a discovered file
is unassigned, a manifest path is missing, a path is assigned more than once,
or a package target imports a module outside its allow list.

RailCore may import SQLite3 only from TrainTimetableDatabase.swift.
RailPresentation may import Foundation and RailCore.
RailApplication may import Foundation, Observation, and RailCore.

    python3 ios/tools/verify-source-ownership.py
    python3 ios/tools/verify-source-ownership.py --repo-root /path/to/fixture

The repo root defaults to the repository that contains this script, so the
working directory does not matter. One scan is enough: new files are reported
and the process does not wait for more of them.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path


PROJECT_FILE = "ios/RailMap.xcodeproj/project.pbxproj"
PACKAGE_FILE = "ios/RailKit/Package.swift"
MANIFEST_FILE = "ios/source-ownership.json"
SQLITE_ONLY = "ios/RailKit/Sources/RailCore/TrainTimetableDatabase.swift"

# Allow lists are the package boundary. Anything else, including UI and app
# frameworks, is a forbidden import. SQLite3 is listed for RailCore and then
# restricted to one file.
PACKAGE_POLICIES = {
    "RailCore": {
        "allow": ["Foundation", "SQLite3"],
        "sqlite3Only": [SQLITE_ONLY],
    },
    "RailPresentation": {
        "allow": ["Foundation", "RailCore"],
    },
    "RailApplication": {
        "allow": ["Foundation", "Observation", "RailCore"],
        "forbid": [
            "AppKit",
            "CoreLocation",
            "MapKit",
            "RailPresentation",
            "SwiftData",
            "SwiftUI",
            "UIKit",
        ],
    },
}

_CONFLICT_STEM = re.compile(r".+ [2-9]\Z")


def main(argv: list[str]) -> int:
    repo, error = parse_args(argv)
    if error:
        print(error, file=sys.stderr)
        return 2
    diagnostics, count = check_repo(repo)
    if diagnostics:
        for line in diagnostics:
            print(line, file=sys.stderr)
        return 1
    print(f"ok: {count} production Swift sources")
    return 0


def parse_args(argv: list[str]) -> tuple[Path | None, str | None]:
    parser = argparse.ArgumentParser(
        prog="verify-source-ownership.py",
        description="Check the production Swift ownership manifest.",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        help="repository root (default: the repo that contains this script)",
    )
    args = parser.parse_args(argv)
    if args.repo_root is None:
        return Path(__file__).resolve().parents[2], None
    return args.repo_root.expanduser().resolve(), None


def check_repo(repo: Path) -> tuple[list[str], int]:
    if not repo.is_dir():
        return [f"manifest: repo root does not exist: {repo}"], 0
    discovered, discovery_errors = discover_sources(repo)
    manifest_path = repo / MANIFEST_FILE
    manifest, manifest_errors = load_manifest(manifest_path)
    if discovery_errors or manifest is None:
        return sorted(set(discovery_errors + manifest_errors)), len(discovered)
    diagnostics = list(manifest_errors)
    diagnostics.extend(assignment_diagnostics(discovered, manifest))
    diagnostics.extend(import_diagnostics(repo, discovered))
    ordered = sorted(set(diagnostics))
    if any(line.startswith("unassigned:") for line in ordered):
        ordered.append(
            "refresh: update ios/source-ownership.json for the unassigned paths. "
            "This scan does not wait for more files."
        )
    return ordered, len(discovered)


def discover_sources(repo: Path) -> tuple[dict[str, str], list[str]]:
    """Return repo-relative Swift paths mapped to their target name."""
    diagnostics: list[str] = []
    found: dict[str, str] = {}

    def take(path: Path, origin: str) -> None:
        relative = posix_relative(repo, path)
        if relative is None:
            diagnostics.append(f"synchronized-root: {path} is outside the repo")
            return
        previous = found.get(relative)
        if previous is not None and previous != origin:
            diagnostics.append(f"duplicate: {relative} is in both {previous} and {origin}")
            return
        found[relative] = origin

    diagnostics.extend(discover_app_sources(repo, take))
    diagnostics.extend(discover_package_sources(repo, take))
    return found, diagnostics


def discover_app_sources(repo: Path, take) -> list[str]:
    project_path = repo / PROJECT_FILE
    if not project_path.is_file():
        return [f"synchronized-root: {PROJECT_FILE} is missing"]
    text = project_path.read_text(encoding="utf-8", errors="replace")
    projects = object_bodies(text, "PBXProject")
    if len(projects) != 1:
        return [f"synchronized-root: {PROJECT_FILE} needs one PBXProject"]
    project_dir = field(projects[0], "projectDirPath")
    if project_dir is None or unquote(project_dir) != "":
        return [
            "synchronized-root: projectDirPath is not empty; "
            "simple explicit validation only accepts an empty projectDirPath"
        ]
    container = project_path.parent.parent
    diagnostics: list[str] = []
    app_targets = []
    for body in object_bodies(text, "PBXNativeTarget"):
        product = field(body, "productType")
        if product is None or unquote(product) != "com.apple.product-type.application":
            continue
        app_targets.append(body)
    if not app_targets:
        return [f"synchronized-root: no application target in {PROJECT_FILE}"]
    for body in app_targets:
        name = field(body, "name")
        origin = unquote(name) if name else "application"
        groups = field(body, "fileSystemSynchronizedGroups")
        if groups is None:
            diagnostics.append(
                f"synchronized-root: {origin} has no fileSystemSynchronizedGroups"
            )
            continue
        ids = re.findall(r"\b[A-Fa-f0-9]{24}\b", groups)
        if not ids:
            diagnostics.append(f"synchronized-root: {origin} has no synchronized root id")
            continue
        for group_id in ids:
            root_body = object_by_id(text, group_id)
            if root_body is None:
                diagnostics.append(f"synchronized-root: group {group_id} is missing")
                continue
            if "isa = PBXFileSystemSynchronizedRootGroup;" not in root_body:
                diagnostics.append(
                    f"synchronized-root: group {group_id} is not an explicit synchronized root"
                )
                continue
            for key in (
                "exceptions",
                "membershipExceptions",
                "explicitFolders",
                "explicitFileTypes",
            ):
                if re.search(rf"^\s*{key}\s*=", root_body, re.M):
                    diagnostics.append(
                        f"synchronized-root: group {group_id} sets {key}; "
                        "membership is not the directory itself"
                    )
            path_value = field(root_body, "path")
            source_tree = field(root_body, "sourceTree")
            if path_value is None or source_tree is None:
                diagnostics.append(
                    f"synchronized-root: group {group_id} needs an explicit path and sourceTree"
                )
                continue
            if unquote(source_tree) != "<group>":
                diagnostics.append(
                    f"synchronized-root: group {group_id} sourceTree is not <group>"
                )
                continue
            relative_root = unquote(path_value)
            if not explicit_directory(relative_root):
                diagnostics.append(
                    f"synchronized-root: group {group_id} path is not an explicit directory"
                )
                continue
            root = container / relative_root
            if not root.is_dir():
                diagnostics.append(f"synchronized-root: {relative_root} is not a directory")
                continue
            for swift in swift_files(root):
                take(swift, origin)
    return diagnostics


def discover_package_sources(repo: Path, take) -> list[str]:
    package_path = repo / PACKAGE_FILE
    if not package_path.is_file():
        return [f"package-target: {PACKAGE_FILE} is missing"]
    text = strip_comments(package_path.read_text(encoding="utf-8", errors="replace"))
    diagnostics: list[str] = []
    seen: set[str] = set()
    for name, declared_path in package_targets(text):
        if name in seen:
            diagnostics.append(f"package-target: duplicate source target {name}")
            continue
        seen.add(name)
        if declared_path is None:
            relative = f"Sources/{name}"
        else:
            relative = declared_path
        if not explicit_directory(relative):
            diagnostics.append(f"package-target: {name} path is not an explicit directory")
            continue
        root = package_path.parent / relative
        # A target directory may be created while this check runs. Absence is
        # zero files, not a failure, and this function does not retry.
        if not root.is_dir():
            continue
        for swift in swift_files(root):
            take(swift, name)
    if not seen:
        diagnostics.append(f"package-target: {PACKAGE_FILE} declares no source targets")
    return diagnostics


def package_targets(text: str) -> list[tuple[str, str | None]]:
    targets: list[tuple[str, str | None]] = []
    token = ".target("
    index = 0
    while True:
        found = text.find(token, index)
        if found < 0:
            return targets
        open_paren = found + len(token) - 1
        end = balanced_end(text, open_paren, "(", ")")
        if end is None:
            return targets
        body = text[open_paren + 1 : end]
        name_match = re.search(r'name:\s*"([^"]+)"', body)
        path_match = re.search(r'path:\s*"([^"]+)"', body)
        if name_match:
            targets.append((name_match.group(1), path_match.group(1) if path_match else None))
        index = end + 1


def swift_files(root: Path) -> list[Path]:
    found: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            name
            for name in dirnames
            if name not in {".build", "Resources", "sync-conflicts"}
            and "sync-conflict" not in name.lower()
        ]
        for name in filenames:
            if not name.endswith(".swift"):
                continue
            path = Path(dirpath) / name
            if is_excluded_copy(path):
                continue
            found.append(path)
    return found


def is_excluded_copy(path: Path) -> bool:
    if "sync-conflict" in path.name.lower():
        return True
    if any("sync-conflict" in part.lower() for part in path.parts):
        return True
    # iCloud duplicate copies use a trailing " 2.swift", " 3.swift", and so on.
    return _CONFLICT_STEM.fullmatch(path.stem) is not None


def assignment_diagnostics(discovered: dict[str, str], manifest: dict) -> list[str]:
    diagnostics: list[str] = []
    assigned: list[str] = []
    seen_ids: set[str] = set()
    for group in manifest["groups"]:
        group_id = group["id"]
        if group_id in seen_ids:
            diagnostics.append(f"manifest: duplicate group id {group_id}")
        seen_ids.add(group_id)
        exact_sources: list[str] = []
        for source in group["sources"]:
            if not exact_swift_path(source):
                diagnostics.append(
                    f"manifest: group {group_id} source is not an exact path: {source}"
                )
                continue
            exact_sources.append(source)
            assigned.append(source)
        diagnostics.extend(declared_policy_diagnostics(group, exact_sources))
    counts: dict[str, int] = {}
    for source in assigned:
        counts[source] = counts.get(source, 0) + 1
    for source, count in sorted(counts.items()):
        if count > 1:
            diagnostics.append(f"duplicate: {source} is assigned {count} times")
    assigned_set = set(counts)
    for source in sorted(assigned_set - set(discovered)):
        diagnostics.append(f"missing: {source}")
    for source in sorted(set(discovered) - assigned_set):
        diagnostics.append(f"unassigned: {source}")
    return diagnostics


def declared_policy_diagnostics(group: dict, sources: list[str]) -> list[str]:
    if "imports" not in group:
        return []
    group_id = group["id"]
    declared = group["imports"]
    if not isinstance(declared, dict):
        return [f"manifest: group {group_id} imports must be an object"]
    unknown = sorted(set(declared) - {"allow", "sqlite3Only", "forbid"})
    if unknown:
        return [f"manifest: group {group_id} imports has unsupported keys: {', '.join(unknown)}"]
    targets = {package_target(source) for source in sources}
    targets.discard(None)
    if len(targets) != 1:
        return [f"manifest: group {group_id} imports do not belong to one package target"]
    target = next(iter(targets))
    if target not in PACKAGE_POLICIES:
        return [f"manifest: group {group_id} imports do not belong to one package target"]
    expected = normalized_policy(PACKAGE_POLICIES[target])
    actual = normalized_policy(declared)
    if actual != expected:
        return [f"manifest: group {group_id} imports do not match the {target} rule"]
    return []


def import_diagnostics(repo: Path, discovered: dict[str, str]) -> list[str]:
    diagnostics: list[str] = []
    sqlite_importers: list[str] = []
    core_files = False
    for path in sorted(discovered):
        target = discovered[path]
        policy = PACKAGE_POLICIES.get(target)
        if policy is None:
            continue
        if target == "RailCore":
            core_files = True
        try:
            text = (repo / path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            diagnostics.append(f"unreadable: {path}")
            continue
        modules = imported_modules(text)
        if "SQLite3" in modules:
            sqlite_importers.append(path)
        allow = set(policy["allow"])
        for module in modules:
            if module == "SQLite3" and target == "RailCore":
                continue
            if module not in allow:
                diagnostics.append(f"forbidden-import: {path} imports {module}")
    if core_files and sqlite_importers != [SQLITE_ONLY]:
        found = ", ".join(sqlite_importers) if sqlite_importers else "none"
        diagnostics.append(
            f"forbidden-import: SQLite3 importers are {found}; only {SQLITE_ONLY} may import SQLite3"
        )
    return diagnostics


def imported_modules(text: str) -> list[str]:
    modules: list[str] = []
    for line in code_lines(text):
        statement = line.strip()
        changed = True
        while changed and statement:
            changed = False
            for prefix in (
                "public ",
                "private ",
                "internal ",
                "package ",
                "fileprivate ",
                "open ",
                "final ",
            ):
                if statement.startswith(prefix):
                    statement = statement[len(prefix) :]
                    changed = True
            if statement.startswith("@"):
                parts = statement.split(None, 1)
                if len(parts) == 2:
                    statement = parts[1]
                    changed = True
        if not statement.startswith("import "):
            continue
        rest = statement[len("import ") :].strip()
        for kind in (
            "struct ",
            "class ",
            "enum ",
            "protocol ",
            "func ",
            "typealias ",
            "var ",
            "let ",
        ):
            if rest.startswith(kind):
                rest = rest[len(kind) :].strip()
                break
        name = rest.split(".", 1)[0].split()
        if not name:
            continue
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name[0]):
            modules.append(name[0])
    return modules


def load_manifest(path: Path) -> tuple[dict | None, list[str]]:
    if not path.is_file():
        return None, [f"manifest: {MANIFEST_FILE} is missing"]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return None, [f"manifest: {MANIFEST_FILE} is not JSON ({exc.lineno}:{exc.colno})"]
    if not isinstance(data, dict):
        return None, [f"manifest: {MANIFEST_FILE} must be an object"]
    diagnostics: list[str] = []
    if data.get("version") != 1:
        diagnostics.append("manifest: version must be 1")
    groups = data.get("groups")
    if not isinstance(groups, list) or not groups:
        diagnostics.append("manifest: groups must be a non-empty list")
        return None, diagnostics
    for index, group in enumerate(groups):
        diagnostics.extend(group_shape_diagnostics(index, group))
    if diagnostics:
        return None, diagnostics
    return data, []


def group_shape_diagnostics(index: int, group: object) -> list[str]:
    label = f"groups[{index}]"
    if not isinstance(group, dict):
        return [f"manifest: {label} must be an object"]
    group_id = group.get("id")
    if isinstance(group_id, str) and group_id.strip():
        label = group_id
    else:
        return [f"manifest: {label} needs an id"]
    diagnostics: list[str] = []
    responsibility = group.get("responsibility")
    if not isinstance(responsibility, str) or not responsibility.strip():
        diagnostics.append(f"manifest: group {label} needs a responsibility")
    validation = group.get("validation")
    if not isinstance(validation, list) or not validation:
        diagnostics.append(f"manifest: group {label} needs validation entries")
    else:
        seen: set[str] = set()
        for entry in validation:
            if not isinstance(entry, dict):
                diagnostics.append(f"manifest: group {label} validation entry must be an object")
                continue
            entry_id = entry.get("id")
            command = entry.get("command")
            if not isinstance(entry_id, str) or not entry_id.strip():
                diagnostics.append(f"manifest: group {label} validation entry needs an id")
            elif entry_id in seen:
                diagnostics.append(f"manifest: group {label} duplicate validation id {entry_id}")
            else:
                seen.add(entry_id)
            if not isinstance(command, str) or not command.strip():
                diagnostics.append(
                    f"manifest: group {label} validation entry needs a command"
                )
    sources = group.get("sources")
    if not isinstance(sources, list):
        diagnostics.append(f"manifest: group {label} sources must be a list")
    return diagnostics


def normalized_policy(policy: dict) -> dict[str, list]:
    return {
        "allow": list(policy.get("allow", [])),
        "sqlite3Only": list(policy.get("sqlite3Only", [])),
        "forbid": list(policy.get("forbid", [])),
    }


def package_target(path: str) -> str | None:
    prefix = "ios/RailKit/Sources/"
    if not path.startswith(prefix):
        return None
    name = path[len(prefix) :].split("/", 1)[0]
    if name in PACKAGE_POLICIES:
        return name
    return None


def exact_swift_path(path: object) -> bool:
    if not isinstance(path, str) or not path.endswith(".swift"):
        return False
    if path.startswith("/") or "\\" in path or "*" in path or "?" in path or "[" in path:
        return False
    parts = Path(path).parts
    return ".." not in parts and parts[0] != ""


def explicit_directory(path: str) -> bool:
    if not path or path.startswith("/") or "\\" in path:
        return False
    if "*" in path or "?" in path or "[" in path:
        return False
    return ".." not in Path(path).parts


def posix_relative(repo: Path, path: Path) -> str | None:
    try:
        return path.resolve().relative_to(repo.resolve()).as_posix()
    except ValueError:
        return None


def field(body: str, key: str) -> str | None:
    match = re.search(rf"(?m)^\s*{re.escape(key)} = ([^;]*);", body)
    if match is None:
        return None
    return match.group(1).strip()


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def object_bodies(text: str, isa: str) -> list[str]:
    bodies: list[str] = []
    needle = f"isa = {isa};"
    start = 0
    while True:
        found = text.find(needle, start)
        if found < 0:
            return bodies
        brace = text.rfind("{", 0, found)
        if brace < 0:
            return bodies
        end = balanced_end(text, brace, "{", "}")
        if end is None:
            return bodies
        bodies.append(text[brace + 1 : end])
        start = end + 1


def object_by_id(text: str, group_id: str) -> str | None:
    match = re.search(rf"\b{re.escape(group_id)}\b\s*(?:/\*.*?\*/)?\s*=\s*\{{", text, re.S)
    if match is None:
        return None
    brace = match.end() - 1
    end = balanced_end(text, brace, "{", "}")
    if end is None:
        return None
    return text[brace + 1 : end]


def balanced_end(text: str, open_index: int, open_ch: str, close_ch: str) -> int | None:
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == open_ch:
            depth += 1
        elif char == close_ch:
            depth -= 1
            if depth == 0:
                return index
    return None


def strip_comments(text: str) -> str:
    return "\n".join(code_lines(text))


def code_lines(text: str) -> list[str]:
    lines: list[str] = []
    in_block = False
    for raw in text.splitlines():
        line = raw
        kept = []
        index = 0
        while index < len(line):
            if in_block:
                end = line.find("*/", index)
                if end < 0:
                    index = len(line)
                    break
                in_block = False
                index = end + 2
                continue
            if line.startswith("//", index):
                break
            if line.startswith("/*", index):
                in_block = True
                index += 2
                continue
            kept.append(line[index])
            index += 1
        lines.append("".join(kept))
    return lines


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
