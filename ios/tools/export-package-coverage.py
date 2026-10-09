#!/usr/bin/env python3
"""Export existing instrumented SwiftPM binaries with a supplied merged profile.

Runs llvm-cov sequentially; never builds, tests, merges or mutates profiles.
Each binary gets a separate LCOV file and an input-identity manifest receipt.
Coverage describes supplied instrumentation, not complete package/test coverage.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import subprocess
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_executable(path: Path) -> Path:
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError(f"Missing or non-executable test binary: {path}")
    return path.resolve()


def discover_executables(products: Path) -> list[Path]:
    if not products.is_dir():
        raise ValueError(f"Missing product directory: {products}")
    executables = []
    for bundle in sorted(products.rglob("*.xctest")):
        if bundle.is_file():
            executables.append(validate_executable(bundle))
            continue
        if not bundle.is_dir():
            continue
        plist = bundle / "Contents" / "Info.plist"
        if not plist.exists():
            plist = bundle / "Info.plist"
        name = bundle.stem
        if plist.exists():
            try:
                with plist.open("rb") as source:
                    metadata = plistlib.load(source)
                if not isinstance(metadata, dict):
                    raise ValueError("Info.plist must contain a dictionary")
                name = metadata.get("CFBundleExecutable", name)
                if not isinstance(name, str) or not name or Path(name).name != name:
                    raise ValueError("CFBundleExecutable must name one binary")
            except (OSError, plistlib.InvalidFileException, ValueError) as error:
                raise ValueError(f"Invalid test bundle metadata: {plist}: {error}") from error
        candidates = [bundle / "Contents" / "MacOS" / name, bundle / name]
        found = [candidate for candidate in candidates if candidate.is_file() and os.access(candidate, os.X_OK)]
        if len(found) != 1:
            raise ValueError(f"Expected one executable in test bundle: {bundle}; found {len(found)}")
        executables.append(validate_executable(found[0]))
    # Resolve aliases and avoid exporting one binary twice.
    executables = sorted(set(executables))
    if not executables:
        raise ValueError(f"No .xctest executable found under: {products}")
    return executables


def run_export(command: list[str], output: Path) -> tuple[int, str]:
    # Stream potentially large national-package LCOV output to disk rather
    # than retaining all source records in the exporter process.
    with output.open("w") as destination:
        result = subprocess.run(command, stdout=destination, stderr=subprocess.PIPE, text=True)
    return result.returncode, result.stderr


def has_source_record(path: Path) -> bool:
    found_source = False
    with path.open() as source:
        for line in source:
            if line.startswith("SF:") and line[3:].strip():
                found_source = True
            elif found_source and line.strip() == "end_of_record":
                return True
    return False


def export_coverage(profile: Path, output_directory: Path, products: Path | None = None,
                    explicit: list[Path] | None = None, runner=run_export) -> dict:
    if not profile.is_file() or profile.stat().st_size == 0:
        raise ValueError(f"Missing or empty merged profile: {profile}")
    if explicit:
        executables = list(dict.fromkeys(validate_executable(path) for path in explicit))
    elif products is not None:
        executables = discover_executables(products)
    else:
        raise ValueError("Supply --products or at least one --executable")
    profile = profile.resolve()
    targets = [output_directory / f"{index:02d}-{executable.name}.lcov"
               for index, executable in enumerate(executables, 1)]
    targets.append(output_directory / "manifest.json")
    if any(target.resolve() in set(executables) | {profile} for target in targets):
        raise ValueError("Output would overwrite a supplied binary or profile")
    output_directory.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema_version": 1,
        "interpretation": "Supplied instrumentation and merged profile only; test-suite completeness and full Domain coverage are not inferred.",
        "products": str(products.resolve()) if products is not None else None,
        "discovery": "explicit executables" if explicit else "xctest bundles",
        "profile": {"path": str(profile), "sha256": sha256(profile)},
        "exports": [],
    }
    for index, executable in enumerate(executables, 1):
        output = output_directory / f"{index:02d}-{executable.name}.lcov"
        command = ["xcrun", "llvm-cov", "export", "--format=lcov",
                   f"--instr-profile={profile}", str(executable)]
        record = {"executable": str(executable), "binary_sha256": sha256(executable),
                  "command": command, "lcov": str(output.resolve()),
                  "exit_code": None, "status": "failed", "stderr": ""}
        try:
            status, diagnostic = runner(command, output)
            record.update(exit_code=status, stderr=diagnostic)
            source_records = output.is_file() and has_source_record(output)
            record["has_source_records"] = source_records
            if output.is_file():
                record["lcov_sha256"] = sha256(output)
            if status == 0 and source_records:
                record["status"] = "passed"
            elif status == 0:
                record["failure"] = "llvm-cov returned no complete LCOV source records"
            else:
                record["failure"] = "llvm-cov export failed"
        except (OSError, UnicodeError) as error:
            record["failure"] = str(error)
        manifest["exports"].append(record)
    manifest["status"] = "passed" if all(record["status"] == "passed" for record in manifest["exports"]) else "failed"
    manifest_path = output_directory / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def main(argv: list[str] | None = None, runner=run_export) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path, help="Existing instrumented SwiftPM product directory")
    parser.add_argument("--profile", required=True, type=Path, help="Matching existing merged .profdata")
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--executable", action="append", type=Path,
                        help="Explicit test binary; repeatable, overrides bundle discovery")
    arguments = parser.parse_args(argv)
    try:
        manifest = export_coverage(arguments.profile, arguments.output_dir, arguments.products,
                                   arguments.executable, runner)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(json.dumps({"manifest": str((arguments.output_dir / "manifest.json").resolve()),
                      "status": manifest["status"], "binary_count": len(manifest["exports"])}, sort_keys=True))
    return 0 if manifest["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
