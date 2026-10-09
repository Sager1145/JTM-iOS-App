#!/usr/bin/env bash
# Read-only, advisory Swift checks. Tool exit codes are evidence, not a CI gate.
set -euo pipefail
exec python3 - "${BASH_SOURCE[0]}" "$@" <<'PY'
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

script = Path(sys.argv[1]).resolve()
root = script.parents[2]
parser = argparse.ArgumentParser(description="Run pinned, read-only advisory Swift checks.")
parser.add_argument("--swiftlint", default=os.environ.get("SWIFTLINT_BIN", "swiftlint"))
parser.add_argument("--swiftformat", default=os.environ.get("SWIFTFORMAT_BIN", "swiftformat"))
parser.add_argument("--output-dir", default=os.environ.get("QUALITY_REPORT_DIR"))
parser.add_argument("--source", action="append", help="Swift file/directory; repeatable, defaults to ios.")
args = parser.parse_args(sys.argv[2:])
output = Path(args.output_dir or tempfile.mkdtemp(prefix="jtm-swift-quality-")).resolve()
output.mkdir(parents=True, exist_ok=True)

# Explicit files avoid traversing generated Swift or tool caches. Neither tool
# receives an autocorrection flag, and SwiftFormat's cache is disabled.
files = set()
pruned = {".build", ".swiftpm", "build", "DerivedData", "Pods", "Carthage"}
for source in args.source or [str(root / "ios")]:
    path = Path(source).resolve()
    if not path.exists():
        parser.error(f"source does not exist: {path}")
    if path.is_file():
        if path.suffix == ".swift":
            files.add(str(path))
    else:
        for directory, children, names in os.walk(path):
            children[:] = sorted(name for name in children if name not in pruned and not name.startswith("."))
            files.update(str(Path(directory) / name) for name in names if name.endswith(".swift"))
files = sorted(files)
if not files:
    parser.error("no Swift source files found")
(output / "sources.txt").write_text("\n".join(files) + "\n", encoding="utf-8")


def run(command, prefix):
    try:
        result = subprocess.run(command, cwd=root, capture_output=True, text=True, errors="replace")
        code, stdout, stderr = result.returncode, result.stdout, result.stderr
    except OSError as error:
        code, stdout, stderr = 127, "", str(error) + "\n"
    (output / f"{prefix}.stdout.log").write_text(stdout, encoding="utf-8")
    (output / f"{prefix}.stderr.log").write_text(stderr, encoding="utf-8")
    return code, stdout.strip()


# These configurations enable only the named refactor rules. Keep --strict so
# SwiftLint warnings have a real nonzero status; advisory behavior lives here.
lint_command = [args.swiftlint, "lint", "--config", str(script.with_name("swiftlint-refactor.yml")),
                "--strict", "--no-cache", "--quiet", "--reporter", "json", *files]
format_command = [args.swiftformat, *files, "--config", str(script.with_name("swiftformat-refactor.conf")),
                  "--lint", "--cache", "ignore", "--reporter", "json", "--report", str(output / "swiftformat.json")]
tools = {}
for name, binary, version, version_args, command in [
    ("swiftlint", args.swiftlint, "0.65.1", ["version"], lint_command),
    ("swiftformat", args.swiftformat, "0.63.1", ["--version"], format_command),
]:
    version_status, actual = run([binary, *version_args], name + ".version")
    entry = {"expected_version": version, "actual_version": actual,
             "version_exit_status": version_status, "command": command,
             "exit_status": None, "advisory": True}
    if version_status != 0:
        entry["status"] = "version_command_failed"
    elif actual != version:
        entry["status"] = "version_mismatch"
    else:
        exit_status, _ = run(command, name)
        entry.update(exit_status=exit_status, status="passed" if exit_status == 0 else "nonzero")
        if name == "swiftlint":
            # Preserve the reporter's bytes, including partial output on errors.
            (output / "swiftlint.json").write_bytes((output / "swiftlint.stdout.log").read_bytes())
    tools[name] = entry

summary = {"schema_version": 1, "advisory": True, "source_file_count": len(files), "tools": tools}
(output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(f"Advisory Swift quality reports: {output}")
for name, entry in tools.items():
    print(f"{name}: {entry['status']}, exit_status={entry['exit_status']}, version_exit_status={entry['version_exit_status']}")
# Findings and tool failures remain visible above and in JSON. They do not gate
# refactor commits; argument/report-writing failures still return nonzero.
PY
