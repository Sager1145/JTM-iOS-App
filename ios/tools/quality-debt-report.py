#!/usr/bin/env python3
"""Compare pinned SwiftLint reports using unchanged source-line identities."""
from __future__ import annotations

import argparse
from collections import Counter
from difflib import SequenceMatcher
import json
import re
from pathlib import Path


RULES = {"duplicate_imports", "force_cast", "force_try", "cyclomatic_complexity", "function_body_length"}


def read_run(directory: Path, root: Path):
    summary = json.loads((directory / "summary.json").read_text())
    tool = summary["tools"]["swiftlint"]
    if tool["actual_version"] != "0.65.1" or tool["version_exit_status"] != 0:
        raise ValueError("Pinned SwiftLint version was not verified")
    if tool["exit_status"] not in (0, 2) or tool["status"] not in ("passed", "nonzero"):
        raise ValueError("SwiftLint report is not a completed lint run")
    sources = {}
    for name in (directory / "sources.txt").read_text().splitlines():
        path = Path(name).resolve()
        identity = path.relative_to(root.resolve()).as_posix()
        if not path.is_file() or path.suffix != ".swift" or identity in sources:
            raise ValueError("Invalid or duplicate source identity")
        sources[identity] = path.read_text().splitlines()
    if not sources or len(sources) != summary["source_file_count"]:
        raise ValueError("Incomplete source inventory")
    expected = {path.relative_to(root.resolve()).as_posix()
                for path in (root.resolve() / "ios").rglob("*.swift")
                if not any(part.startswith(".") or part in {"build", "DerivedData", "Pods", "Carthage"}
                           for part in path.relative_to(root.resolve()).parts)}
    if set(sources) != expected:
        raise ValueError("Report omitted Swift files from the complete ios inventory")
    findings = json.loads((directory / "swiftlint.json").read_text())
    if not isinstance(findings, list):
        raise ValueError("SwiftLint JSON must contain a finding array")
    normalized = []
    for item in findings:
        identity = Path(item["file"]).resolve().relative_to(root.resolve()).as_posix()
        line = item["line"]
        if identity not in sources or not isinstance(line, int) or not 1 <= line <= len(sources[identity]):
            raise ValueError("Finding is outside the linted source inventory")
        if item["rule_id"] not in RULES or item["severity"] not in ("Warning", "Error"):
            raise ValueError("Unexpected lint rule or severity")
        normalized.append({"file": identity, "line": line, "rule": item["rule_id"],
                           "severity": item["severity"], "reason": item["reason"]})
    if (not findings) != (tool["exit_status"] == 0):
        raise ValueError("Lint exit status and findings disagree")
    return sources, normalized



def declaration(lines, line):
    text = "\n".join(lines[line - 1:])
    # Ignore strings/comments for delimiter counting while retaining the original
    # declaration bytes in its identity. Default closures remain inside parens.
    masked = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"',
                    lambda match: "".join("\n" if char == "\n" else " " for char in match.group()),
                    text, flags=re.DOTALL)
    parentheses = brackets = 0
    for index, char in enumerate(masked):
        if char == "(": parentheses += 1
        elif char == ")": parentheses -= 1
        elif char == "[": brackets += 1
        elif char == "]": brackets -= 1
        elif char == "{" and parentheses == brackets == 0:
            return text[:index + 1]
    return None

def compare(baseline_sources, baseline_findings, candidate_sources, candidate_findings):
    # Map only byte-equal lines. A shifted warning survives an unrelated insertion;
    # a changed declaration, new finding or worsened numeric reason is new debt.
    mapping = {}
    for file in baseline_sources.keys() & candidate_sources.keys():
        matcher = SequenceMatcher(None, baseline_sources[file], candidate_sources[file], autojunk=False)
        for block in matcher.get_matching_blocks():
            for offset in range(block.size):
                mapping[(file, block.b + offset + 1)] = block.a + offset + 1
    def key(finding, line):
        return (finding["file"], line, finding["rule"], finding["severity"], finding["reason"])
    remaining = Counter(key(item, item["line"]) for item in baseline_findings)
    added = []
    inherited = 0
    for item in candidate_findings:
        old_line = mapping.get((item["file"], item["line"]))
        identity = key(item, old_line)
        same_declaration = True
        if old_line is not None and item["rule"] in {"cyclomatic_complexity", "function_body_length"}:
            old_declaration = declaration(baseline_sources[item["file"]], old_line)
            new_declaration = declaration(candidate_sources[item["file"]], item["line"])
            same_declaration = old_declaration is not None and old_declaration == new_declaration
        if old_line is not None and remaining[identity] and same_declaration:
            remaining[identity] -= 1
            inherited += 1
        else:
            added.append(item)
    return {"schema_version": 1, "scope": "Pinned five-rule lint findings; unchanged source lines and exact reasons",
            "baseline_findings": len(baseline_findings), "candidate_findings": len(candidate_findings),
            "inherited_findings": inherited, "removed_findings": sum(remaining.values()),
            "new_findings": added, "passed": not added,
            "limitations": ["Legacy findings remain visible; this is not a global complexity pass.",
                            "Changed warning declarations require review and count as new debt.",
                            "Source renames count as new identities; no suppression baseline is generated."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline-root", "candidate-root", "baseline-report", "candidate-report", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    try:
        old_sources, old_findings = read_run(args.baseline_report, args.baseline_root)
        new_sources, new_findings = read_run(args.candidate_report, args.candidate_root)
        report = compare(old_sources, old_findings, new_sources, new_findings)
        report.update(baseline_files=len(old_sources), candidate_files=len(new_sources))
    except (ValueError, KeyError, TypeError, OSError, json.JSONDecodeError) as error:
        report = {"schema_version": 1, "passed": False, "error": str(error)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
