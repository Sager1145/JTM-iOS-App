#!/usr/bin/env python3
"""inputsSHA256 of a rail map pack: the cache key and the freshness check, one function.

A `{region}.railpack` is a function of
  - the region's builder output: `{region}.display.bin`, `{region}.stations.json`,
    `{region}.display-history.json` (absent for a region without history),
    `{region}.topology.bin`, and the region's slice of `manifest.json` (its lines and its region
    record: colours, ranks and visibility lengths decide groups and tiers, and the other regions'
    lines have no say);
  - the bake sources: RailBakeKit and the RailBake tool, RailCore/Rendering, the coordinate,
    geometry and GCJ-02 utilities, the pack format, writer and ladder, the topology format
    constants, and the line visibility policy;
  - the ladder (`--levels`), the datum, and the Swift toolchain version string.

`inputs_sha256` hashes one canonical text of `name<TAB>sha256` lines (sorted by name), so the
same inputs give the same key on any machine with the same toolchain string. The bake tool
(`RailBake --inputs-sha256`) writes it into the pack header at byte 60, and `check_pack`
recomputes it: a pack whose header differs from the recomputed value is stale.

    python3 -I ios/tools/rail_pack_inputs.py key   --builder-dir DIR --region jp --datum wgs84 --levels 8...34
    python3 -I ios/tools/rail_pack_inputs.py check --builder-dir DIR --region jp --datum wgs84 --levels 8...34 --pack PACK
    python3 -I ios/tools/rail_pack_inputs.py variants [--regions "jp tw hk mo kr"]
    python3 -I ios/tools/rail_pack_inputs.py toolchain

`variants` prints one `region datum filename` line per pack the build makes: jp has `jp.railpack`;
tw, hk, mo and kr (regions drawn on the China map service, `GCJ02.candidateRegions`) have both
`{region}.railpack` (WGS84) and `{region}.gcj.railpack` (GCJ-02).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

# Paths are relative to the repository root. A directory contributes every `*.swift` file in it
# (recursively); a missing path is an error, never skipped.
SOURCE_PATHS = (
    "ios/tools/railbake/Package.swift",
    "ios/tools/railbake/Sources",
    "ios/RailKit/Sources/RailCore/Rendering",
    "ios/RailKit/Sources/RailCore/Utilities/Coordinates.swift",
    "ios/RailKit/Sources/RailCore/Utilities/Geometry.swift",
    "ios/RailKit/Sources/RailCore/Utilities/GCJ02.swift",
    "ios/RailKit/Sources/RailCore/Pack/RailPackFormat.swift",
    "ios/RailKit/Sources/RailCore/Pack/RailPackWriter.swift",
    "ios/RailKit/Sources/RailCore/Pack/RailPackLadder.swift",
    "ios/RailKit/Sources/RailCore/Topology/RailTopologyFormat.swift",
    "ios/RailKit/Sources/RailPresentation/Map/NetworkVisibilityPolicy.swift",
)

DEFAULT_REGIONS = ("jp", "tw", "hk", "mo", "kr")
GCJ_REGIONS = frozenset({"tw", "hk", "mo", "kr", "cn"})

HEADER_INPUTS_OFFSET = 60
HEADER_DISPLAY_OFFSET = 28
PACK_HEADER_MAGIC = b"JTRP"
TOPOLOGY_DISPLAY_OFFSET = 48


class InputsError(Exception):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def source_files(repo: Path) -> list[Path]:
    found: list[Path] = []
    for relative in SOURCE_PATHS:
        path = repo / relative
        if path.is_dir():
            files = sorted(path.rglob("*.swift"))
            if not files:
                raise InputsError(f"no Swift sources under {relative}")
            found.extend(files)
        elif path.is_file():
            found.append(path)
        else:
            raise InputsError(f"missing bake input {relative}")
    return found


def region_manifest_slice(manifest_path: Path, region: str) -> bytes:
    manifest = json.loads(manifest_path.read_text())
    lines = {key: value for key, value in manifest.get("lines", {}).items() if value.get("region") == region}
    regions = [record for record in manifest.get("regions", []) if record.get("region") == region]
    if not regions:
        raise InputsError(f"manifest has no region {region}")
    return json.dumps({"lines": lines, "regions": regions}, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode()


def toolchain_string() -> str:
    """The Swift compiler's version output, one line, as `swift --version` prints it."""
    try:
        out = subprocess.run(["xcrun", "swift", "--version"], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        out = subprocess.run(["swift", "--version"], capture_output=True, text=True, check=True).stdout
    return " ".join(out.split())


def inputs_sha256(repo: Path, builder_dir: Path, region: str, datum: str, levels: str, toolchain: str) -> str:
    """The hex SHA-256 over every input of one pack."""
    if datum not in ("wgs84", "gcj02"):
        raise InputsError(f"datum must be wgs84 or gcj02, not {datum}")
    entries: dict[str, str] = {}
    for path in source_files(repo):
        entries["source/" + path.relative_to(repo).as_posix()] = sha256_file(path)
    for suffix in ("display.bin", "stations.json", "topology.bin"):
        path = builder_dir / f"{region}.{suffix}"
        if not path.is_file():
            raise InputsError(f"builder output has no {path.name}")
        entries[f"input/{path.name}"] = sha256_file(path)
    history = builder_dir / f"{region}.display-history.json"
    entries[f"input/{history.name}"] = sha256_file(history) if history.is_file() else "absent"
    manifest = builder_dir / "manifest.json"
    if not manifest.is_file():
        raise InputsError("builder output has no manifest.json")
    entries["input/manifest.json#" + region] = hashlib.sha256(region_manifest_slice(manifest, region)).hexdigest()
    entries["param/ladder"] = levels
    entries["param/datum"] = datum
    entries["param/toolchain"] = toolchain
    text = "".join(f"{name}\t{value}\n" for name, value in sorted(entries.items()))
    return hashlib.sha256(text.encode()).hexdigest()


def variants(regions: tuple[str, ...] | list[str] = DEFAULT_REGIONS) -> list[tuple[str, str, str]]:
    """(region, datum, pack file name) for every pack of the given regions."""
    rows: list[tuple[str, str, str]] = []
    for region in regions:
        rows.append((region, "wgs84", f"{region}.railpack"))
        if region in GCJ_REGIONS:
            rows.append((region, "gcj02", f"{region}.gcj.railpack"))
    return rows


def pack_header_hashes(pack: Path) -> tuple[bytes, bytes]:
    """(displaySHA256, inputsSHA256) from a pack's header."""
    with pack.open("rb") as handle:
        header = handle.read(HEADER_INPUTS_OFFSET + 32)
    if len(header) < HEADER_INPUTS_OFFSET + 32 or header[:4] != PACK_HEADER_MAGIC:
        raise InputsError(f"{pack} is not a rail pack")
    return (header[HEADER_DISPLAY_OFFSET:HEADER_DISPLAY_OFFSET + 32],
            header[HEADER_INPUTS_OFFSET:HEADER_INPUTS_OFFSET + 32])


def check_pack(pack: Path, repo: Path, builder_dir: Path, region: str, datum: str, levels: str, toolchain: str) -> None:
    """Raises InputsError when the pack is stale or does not belong to the region's topology."""
    display, inputs = pack_header_hashes(pack)
    expected = inputs_sha256(repo, builder_dir, region, datum, levels, toolchain)
    if inputs.hex() != expected:
        raise InputsError(f"{pack.name} is stale: header inputs {inputs.hex()[:12]}, current {expected[:12]}")
    topology = (builder_dir / f"{region}.topology.bin").read_bytes()[TOPOLOGY_DISPLAY_OFFSET:TOPOLOGY_DISPLAY_OFFSET + 32]
    if display != topology:
        raise InputsError(f"{pack.name} was baked for another display blob than {region}.topology.bin names")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("key", "check", "variants", "toolchain"))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--builder-dir", type=Path)
    parser.add_argument("--region")
    parser.add_argument("--regions", default=" ".join(DEFAULT_REGIONS))
    parser.add_argument("--datum", default="wgs84")
    parser.add_argument("--levels", default="8...34")
    parser.add_argument("--toolchain", help="override the Swift toolchain string (tests)")
    parser.add_argument("--pack", type=Path)
    args = parser.parse_args(argv)
    if args.command == "toolchain":
        print(toolchain_string())
        return 0
    if args.command == "variants":
        for region, datum, name in variants(args.regions.split()):
            print(region, datum, name)
        return 0
    if args.builder_dir is None or args.region is None:
        parser.error("--builder-dir and --region are required")
    try:
        toolchain = args.toolchain if args.toolchain is not None else toolchain_string()
        if args.command == "key":
            print(inputs_sha256(args.repo, args.builder_dir, args.region, args.datum, args.levels, toolchain))
        else:
            if args.pack is None:
                parser.error("check needs --pack")
            check_pack(args.pack, args.repo, args.builder_dir, args.region, args.datum, args.levels, toolchain)
            print(f"{args.pack.name} is fresh")
    except InputsError as error:
        print(f"rail_pack_inputs: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
