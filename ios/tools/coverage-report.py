#!/usr/bin/env python3
"""Report supplied LLVM LCOV coverage against a frozen candidate diff.

Production scope defaults to ios/RailKit/Sources and ios/RailMap. Input paths
may use either frozen snapshot prefix; repository-relative source identities
are preserved. A missing changed file is unmapped, never an excluded comment.
This report describes supplied instrumentation, not test-suite completeness.
"""
from __future__ import annotations

import argparse
import ast
import json
import posixpath
import re
from pathlib import Path


PRODUCTION_ROOTS = ("ios/RailKit/Sources/", "ios/RailMap/")
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def decode_path(value: str) -> str:
    value = value.strip()
    if value.startswith('"'):
        decoded = ast.literal_eval(value)
        if not isinstance(decoded, str):
            raise ValueError("Expected a quoted file path")
        # Git quotes non-ASCII UTF-8 bytes as octal C escapes.
        if re.search(r"\\[0-7]{3}", value):
            decoded = decoded.encode("latin1").decode("utf-8")
        return decoded
    return value.split("\t", 1)[0]


def normalize_path(value: str, source_root: Path) -> str | None:
    value = decode_path(value)
    if value == "/dev/null":
        return None
    if value.startswith(("a/", "b/")):
        value = value[2:]
    value = posixpath.normpath(value)
    root = source_root.resolve().as_posix().rstrip("/")
    if value.startswith(root + "/"):
        value = value[len(root) + 1:]
    # Match a stable production suffix when baseline/candidate absolute
    # prefixes differ. This also handles git --no-index absolute headers.
    for prefix in PRODUCTION_ROOTS:
        marker = "/" + prefix
        if marker in value:
            value = value[value.rfind(marker) + 1:]
            break
    # A standalone SwiftPM snapshot may itself be the supplied source root.
    if value.startswith("Sources/"):
        value = "ios/RailKit/" + value
    if value.startswith(("RailKit/Sources/", "RailMap/")):
        value = "ios/" + value
    if not value.startswith(PRODUCTION_ROOTS) or not value.endswith(".swift"):
        return None
    if any(part in {"Tests", "Resources"} for part in value.split("/")):
        return None
    return value


def parse_lcov(text: str, source_root: Path) -> dict[str, dict[int, int]]:
    records: dict[str, dict[int, int]] = {}
    current: str | None = None
    saw_source = False
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if line.startswith("SF:"):
            saw_source = True
            current = normalize_path(line[3:], source_root)
            if current is not None:
                records.setdefault(current, {})
        elif line == "end_of_record":
            current = None
            saw_source = False
        elif line.startswith("DA:"):
            if not saw_source:
                raise ValueError(f"LCOV line {number}: DA has no source record")
            if current is None:
                continue
            fields = line[3:].split(",")
            if len(fields) not in {2, 3}:
                raise ValueError(f"LCOV line {number}: malformed DA record")
            try:
                source_line, hits = int(fields[0]), int(fields[1])
            except ValueError as error:
                raise ValueError(f"LCOV line {number}: non-integer line/hit count") from error
            if source_line < 1 or hits < 0:
                raise ValueError(f"LCOV line {number}: invalid line/hit count")
            previous = records[current].get(source_line, 0)
            records[current][source_line] = max(previous, hits)
    return records


def merge_coverage(inputs: list[dict[str, dict[int, int]]]) -> dict[str, dict[int, int]]:
    merged: dict[str, dict[int, int]] = {}
    for records in inputs:
        for path, lines in records.items():
            target = merged.setdefault(path, {})
            for line, hits in lines.items():
                target[line] = max(target.get(line, 0), hits)
    return merged


def parse_diff(text: str, source_root: Path) -> tuple[dict[str, set[int]], set[str]]:
    changed: dict[str, set[int]] = {}
    deleted: set[str] = set()
    previous: str | None = None
    current: str | None = None
    old_remaining = new_remaining = 0
    new_line = 0
    for number, raw in enumerate(text.splitlines(), 1):
        if raw.startswith("\\ No newline at end of file"):
            continue
        if old_remaining or new_remaining:
            if raw.startswith("+") and new_remaining:
                if current is not None:
                    changed.setdefault(current, set()).add(new_line)
                new_line += 1
                new_remaining -= 1
            elif raw.startswith("-") and old_remaining:
                old_remaining -= 1
            elif raw.startswith(" ") and old_remaining and new_remaining:
                new_line += 1
                old_remaining -= 1
                new_remaining -= 1
            else:
                raise ValueError(f"Diff line {number}: hunk length/content mismatch")
            continue
        if raw.startswith("diff --git "):
            previous = current = None
        elif raw.startswith("--- "):
            previous = normalize_path(raw[4:], source_root)
        elif raw.startswith("+++ "):
            current = normalize_path(raw[4:], source_root)
            if decode_path(raw[4:]) == "/dev/null" and previous is not None:
                deleted.add(previous)
            elif current is not None:
                changed.setdefault(current, set())
        elif raw.startswith("@@"):
            match = HUNK.match(raw)
            if match is None:
                raise ValueError(f"Diff line {number}: malformed unified hunk")
            old_remaining = int(match[2]) if match[2] is not None else 1
            new_line = int(match[3])
            new_remaining = int(match[4]) if match[4] is not None else 1
    if old_remaining or new_remaining:
        raise ValueError("Diff ends before its final hunk is complete")
    return changed, deleted


def module_for(path: str) -> str:
    if path.startswith("ios/RailMap/"):
        return "RailMap"
    return path.split("/")[3]


def metric(covered: int, executable: int) -> dict:
    return {
        "covered_lines": covered,
        "executable_lines": executable,
        "percent": 100.0 * covered / executable if executable else None,
    }


def summarize(paths: list[dict]) -> dict:
    overall = metric(sum(p["overall"]["covered_lines"] for p in paths),
                     sum(p["overall"]["executable_lines"] for p in paths))
    changed = metric(sum(p["changed"]["covered_lines"] for p in paths),
                     sum(p["changed"]["executable_lines"] for p in paths))
    changed.update({
        "source_lines": sum(len(p["changed_source_lines"]) for p in paths),
        "excluded_non_executable_lines": sum(len(p["excluded_non_executable_lines"]) for p in paths),
        "unmapped_files": sorted(p["path"] for p in paths if p["status"] == "unmapped"),
    })
    return {"overall": overall, "changed": changed}


def make_report(coverage: dict[str, dict[int, int]], changed: dict[str, set[int]],
                deleted: set[str], source_root: Path, includes: list[str] | None = None,
                minimum_line: float | None = None, minimum_changed: float | None = None) -> dict:
    def included(path: str) -> bool:
        return not includes or any(path == prefix.rstrip("/") or path.startswith(prefix.rstrip("/") + "/")
                                   for prefix in includes)

    files = []
    for path in sorted(set(coverage) | set(changed)):
        if not included(path):
            continue
        lines = coverage.get(path, {})
        additions = changed.get(path, set())
        mapped = path in coverage
        executable_changed = additions.intersection(lines)
        files.append({
            "path": path, "module": module_for(path), "mapped": mapped,
            "status": "unmapped" if additions and not mapped else
                      "no_added_lines" if path in changed and not additions else
                      "changed" if additions else "unchanged",
            "changed_source_lines": sorted(additions),
            "excluded_non_executable_lines": sorted(additions.difference(lines)) if mapped else [],
            "unmapped_source_lines": sorted(additions) if not mapped else [],
            "overall": metric(sum(hits > 0 for hits in lines.values()), len(lines)),
            "changed": metric(sum(lines[line] > 0 for line in executable_changed), len(executable_changed)),
        })
    totals = summarize(files)
    failures = []
    if totals["changed"]["unmapped_files"]:
        failures.append("Changed production files are absent from supplied coverage")
    for name, threshold in (("overall", minimum_line), ("changed", minimum_changed)):
        if threshold is not None:
            percentage = totals[name]["percent"]
            if percentage is None:
                failures.append(f"{name} coverage has no executable denominator")
            elif percentage < threshold:
                failures.append(f"{name} coverage {percentage:.6f}% is below {threshold:.6f}%")
    modules = {module: summarize([item for item in files if item["module"] == module])
               for module in sorted({item["module"] for item in files})}
    return {
        "schema_version": 1,
        "source_root": str(source_root.resolve()),
        "interpretation": "Supplied instrumentation only; test-suite completeness and full Domain coverage are not inferred.",
        "included_paths": includes or [prefix.rstrip("/") for prefix in PRODUCTION_ROOTS],
        "totals": totals, "modules": modules, "files": files,
        "deleted_files": sorted(path for path in deleted if included(path)),
        "gate": {"passed": not failures, "failures": failures,
                 "minimum_line_coverage": minimum_line,
                 "minimum_changed_line_coverage": minimum_changed},
    }


def percentage(value: str) -> float:
    result = float(value)
    if not 0 <= result <= 100:
        raise argparse.ArgumentTypeError("Coverage thresholds must be between 0 and 100")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lcov", action="append", required=True, type=Path)
    parser.add_argument("--diff", required=True, type=Path)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--include", action="append", help="Narrow production scope to a repository-relative file/directory")
    parser.add_argument("--minimum-line-coverage", type=percentage)
    parser.add_argument("--minimum-changed-line-coverage", type=percentage)
    arguments = parser.parse_args()
    if arguments.include:
        normalized_includes = [posixpath.normpath(path) for path in arguments.include]
        for path in normalized_includes:
            if not any(path == root.rstrip("/") or path.startswith(root) for root in PRODUCTION_ROOTS) \
                    or any(part in {"Tests", "Resources"} for part in path.split("/")):
                parser.error("--include must be within ios/RailKit/Sources or ios/RailMap")
        arguments.include = normalized_includes
    try:
        coverage = merge_coverage([parse_lcov(path.read_text(), arguments.source_root) for path in arguments.lcov])
        changed, deleted = parse_diff(arguments.diff.read_text(), arguments.source_root)
        report = make_report(coverage, changed, deleted, arguments.source_root, arguments.include,
                             arguments.minimum_line_coverage, arguments.minimum_changed_line_coverage)
    except (OSError, ValueError, SyntaxError) as error:
        parser.error(str(error))
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"output": str(arguments.output), "totals": report["totals"], "gate": report["gate"]}, sort_keys=True))
    return 0 if report["gate"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
