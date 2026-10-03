#!/usr/bin/env python3
"""Snapshot the canonical timetable and fingerprint the resources iOS ships.

Stable *-2025 names identify the compact-v1 contract, not a publication year.
Only explicitly named canonical inputs are used; numbered conflict copies are
never candidates for the latest version. Revisions contain no timestamps.
"""
from __future__ import annotations

import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile

REGIONS = ("jp", "tw", "hk", "mo", "kr")
MANIFEST_NAME = "rail-resource-revisions.json"
SHARED_DISPLAY_INPUTS = (
    "shared-corridors.json", "display-lanes.json", "display-hubs.json",
    "jp-render-groups.json",
)


def file_digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def digest_inputs(inputs: list[tuple[str, Path]]) -> str:
    """Hash names, presence and bytes, independently of paths and mtimes."""
    rows = []
    for name, path in sorted(inputs):
        digest = file_digest(path) if path.is_file() else None
        rows.append([name, digest])
    return hashlib.sha256(json.dumps(rows, separators=(",", ":")).encode()).hexdigest()


def display_manifest_revision(bundle: Path, region: str) -> str:
    """Include map catalog/version changes, ignoring build timestamps and totals."""
    path = bundle / "rail-display-network/manifest.json"
    if not path.is_file():
        return "missing"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    # Keep global format/version/input identities plus only this region's catalog.
    # Aggregate build counts change when an unrelated country is rebuilt.
    identity = {key: value for key, value in manifest.items()
                if key not in ("generatedAt", "source", "built", "lines", "regions", "packageSHA256")}
    identity["packageSHA256"] = manifest.get("packageSHA256", {}).get(region)
    identity["lines"] = {key: value for key, value in manifest.get("lines", {}).items()
                         if value.get("region") == region}
    identity["regions"] = [value for value in manifest.get("regions", [])
                           if value.get("region") == region]
    encoded = json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def snapshot_timetable(source: Path, destination: Path) -> None:
    """Use SQLite backup so committed WAL changes reach the shipped database."""
    if not source.is_file():
        raise FileNotFoundError(f"missing canonical timetable: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, suffix=".sqlite", delete=False) as temporary:
        snapshot = Path(temporary.name)
    try:
        with closing(sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True)) as original:
            with closing(sqlite3.connect(snapshot)) as copied:
                original.backup(copied)
                result = copied.execute("PRAGMA quick_check").fetchone()
                if result != ("ok",):
                    raise ValueError(f"invalid canonical timetable: {result}")
        # Replace only after a complete snapshot; never ship a partial copy.
        snapshot.chmod(0o644)
        snapshot.replace(destination)
    finally:
        snapshot.unlink(missing_ok=True)


def build_manifest(repo: Path, bundle: Path) -> dict:
    rail = repo / "app/public/rail"
    shared = [(f"display-input/{name}", rail / name) for name in SHARED_DISPLAY_INPUTS]
    shared += [(f"builder/{name}", repo / "app/scripts/railway" / name) for name in (
        "build-display-network.py", "lib/display_identity.py", "lib/na_geo.py",
    )]
    # Legacy matched routes may cover any region; changes invalidate every region.
    shared += [(name, bundle / name) for name in ("matched-routes.json", "matched-stops.json", "physical-rail-junctions.json")]
    regions = {}
    source_hashes = {name: file_digest(bundle / name) for name in
                     ("matched-routes.json", "matched-stops.json", "physical-rail-junctions.json")
                     if (bundle / name).is_file()}
    for region in REGIONS:
        suffix = "" if region == "jp" else f"-{region}"
        names = [f"{region}-2025.json"] + [
            f"{family}{suffix}.json" for family in
            ("stations", "rail-sections", "station-readings", "rail-history", "train-store")
        ] + [f"rail-display-network/{region}.{ending}" for ending in
             ("display.bin", "stations.json", "display-history.json")]
        inputs = shared + [(name, bundle / name) for name in names]
        for name in names:
            path = bundle / name
            if "/" not in name and path.is_file():
                source_hashes[name] = file_digest(path)
        datasets = [f"sample-data{suffix}"]
        if region == "jp":
            datasets += ["new-year-grand-loop-data", "tokyo-limited-express-loop-data"]
            inputs += [(name, bundle / name) for name in
                       ("new-year-grand-loop.json", "tokyo-limited-express-loop.json")]
        for dataset in datasets:
            directory = bundle / dataset
            inputs.append((dataset, directory / "manifest.json"))
            if directory.is_dir():
                # Sample chunks are referenced by their manifest, never conflict copies.
                for path in sorted(directory.rglob("*.json")):
                    if " " not in path.name and path != directory / "manifest.json":
                        inputs.append((path.relative_to(bundle).as_posix(), path))
        revision = [digest_inputs(inputs), display_manifest_revision(bundle, region)]
        regions[region] = hashlib.sha256(json.dumps(revision).encode()).hexdigest()
    timetable = bundle / "train-service-timetable.sqlite"
    return {
        "schemaVersion": 1,
        "regions": regions,
        "sourceHashes": source_hashes,
        "timetableRevision": digest_inputs([(timetable.name, timetable)]),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    args = parser.parse_args()
    snapshot_timetable(
        args.repo / "app/data/train-service-history/derived/train-service-timetable.sqlite",
        args.bundle / "train-service-timetable.sqlite",
    )
    manifest = build_manifest(args.repo, args.bundle)
    (args.bundle / MANIFEST_NAME).write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
