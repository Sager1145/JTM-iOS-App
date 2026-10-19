#!/usr/bin/env python3
"""Import a pinned CRTrainRoute JSON snapshot into local railway candidates.

This is a source builder, not a runtime package publisher or audit runner.
Source way fragments stay separate. No pickle, upstream server code, snapping,
synthetic connections, alias merging or coordinate transformation is used.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import re


UPSTREAM = "https://github.com/Laide140/CRTrainRoute"
MAINLAND_PROVINCES = frozenset((
    "110000", "120000", "130000", "140000", "150000", "210000", "220000", "230000",
    "310000", "320000", "330000", "340000", "350000", "360000", "370000", "410000",
    "420000", "430000", "440000", "450000", "460000", "500000", "510000", "520000",
    "530000", "540000", "610000", "620000", "630000", "640000", "650000"))
EXISTING_REGIONS = {"810000": "hk", "820000": "mo"}
BLOCKERS = [
    "Original OSM node IDs and relation membership are absent; coordinate coincidence does not prove connectivity.",
    "Passenger operation, line/operator identity and ordered station-to-track membership are not established.",
    "12306 station datum is declared GCJ02 by upstream, not independently verified; WGS84 anchors are unresolved.",
    "OSM snapshot/version and extraction metadata are absent; 12306 data redistribution terms are not documented upstream.",
]


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def load(path):
    raw = path.read_bytes()
    return json.loads(raw), {"path": path.as_posix(), "bytes": len(raw),
                            "sha256": hashlib.sha256(raw).hexdigest()}


def coordinate(point, context):
    if (not isinstance(point, list) or len(point) < 2
            or any(isinstance(v, bool) or not isinstance(v, (int, float))
                   or not math.isfinite(v) for v in point)
            or not -180 <= point[0] <= 180 or not -90 <= point[1] <= 90):
        raise ValueError(f"Invalid coordinate: {context}")


def parts_of(feature, context):
    geometry = feature.get("geometry") or {}
    kind, coords = geometry.get("type"), geometry.get("coordinates")
    if kind == "LineString":
        parts = [coords]
    elif kind == "MultiLineString" and isinstance(coords, list):
        parts = coords
    else:
        raise ValueError(f"Unsupported railway geometry: {context}")
    if not parts:
        raise ValueError(f"Empty railway geometry: {context}")
    for part in parts:
        if not isinstance(part, list) or len(part) < 2:
            raise ValueError(f"Invalid railway part: {context}")
        for point in part:
            coordinate(point, context)
    return parts


def build(source_root, output, manifest_path, revision, retrieved_at):
    source_root, output, manifest_path = map(Path, (source_root, output, manifest_path))
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("A full pinned Git commit is required")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", retrieved_at):
        raise ValueError("retrieved_at must be YYYY-MM-DD")
    # Never mix a previous successful candidate build with an interrupted one.
    # A replacement is an explicit caller decision, not destructive cleanup here.
    if output.exists() and any(output.iterdir()):
        raise ValueError("Candidate output must be empty; preserve previous imports in a separate directory")
    if manifest_path.exists():
        raise ValueError("Manifest already exists; choose a new path to preserve previous evidence")
    paths = sorted((source_root / "data/geojson").glob("*.geojson"))
    if not paths:
        raise ValueError("No province GeoJSON files found")
    provinces = {p.stem for p in paths}
    if provinces - MAINLAND_PROVINCES - set(EXISTING_REGIONS):
        raise ValueError("Unknown province file; classify it explicitly before import")
    output.mkdir(parents=True, exist_ok=True)
    inputs, province_rows = [], []
    total_modes, mainland_modes = Counter(), Counter()
    counts = Counter({"syntheticConnections": 0, "mainlandFeatures": 0,
                      "excludedRegionalFeatures": 0, "coordinateOccurrences": 0,
                      "mainlandCoordinateOccurrences": 0, "mainlandProvinces": 0})
    property_fields = set()
    for path in paths:
        collection, metadata = load(path)
        metadata["path"] = path.relative_to(source_root).as_posix()
        metadata["url"] = f"{UPSTREAM}/blob/{revision}/{metadata['path']}"
        inputs.append(metadata)
        if collection.get("type") != "FeatureCollection" or not isinstance(collection.get("features"), list):
            raise ValueError(f"Invalid FeatureCollection: {path.name}")
        source_crs = collection.get("crs")
        if source_crs is not None:
            accepted = {"urn:ogc:def:crs:OGC:1.3:CRS84", "urn:ogc:def:crs:EPSG::4326",
                        "EPSG:4326", "OGC:CRS84", "CRS84"}
            if (not isinstance(source_crs, dict) or source_crs.get("type") != "name"
                    or source_crs.get("properties", {}).get("name") not in accepted):
                raise ValueError(f"Incompatible or unresolved source CRS: {path.name}")
        modes, points = Counter(), 0
        mainland = path.stem in MAINLAND_PROVINCES
        target = output / f"tracks-{path.stem}.jsonl"
        stream = target.open("x", encoding="utf-8") if mainland else None
        try:
            for index, feature in enumerate(collection["features"]):
                context = f"{path.name}:features[{index}]"
                if feature.get("type") != "Feature" or not isinstance(feature.get("properties"), dict):
                    raise ValueError(f"Invalid feature: {context}")
                props = feature["properties"]
                if not str(props.get("osm_id", "")).isdigit():
                    raise ValueError(f"Missing OSM way identity: {context}")
                parts = parts_of(feature, context)
                point_count = sum(map(len, parts))
                mode = props.get("fclass") or "unknown"
                modes[mode] += 1
                points += point_count
                property_fields.update(props)
                if stream:
                    record = {
                        "type": "Feature", "id": f"cn-candidate-{path.stem}-{props['osm_id']}-{index}",
                        "properties": props, "geometry": feature["geometry"],
                        "candidate": {"region": "cn", "crs": "WGS84",
                                      "crsBasis": "OSM declared by upstream; extraction metadata absent",
                                      "sourceFile": metadata["path"], "featureIndex": index,
                                      "sourceCommit": revision, "sourceOSMNodeIDs": None,
                                      "runtimeEligible": False}}
                    stream.write(encoded(record) + "\n")
        finally:
            if stream:
                stream.close()
        total_modes.update(modes)
        counts["coordinateOccurrences"] += points
        if mainland:
            mainland_modes.update(modes)
            counts["mainlandFeatures"] += sum(modes.values())
            counts["mainlandProvinces"] += 1
            counts["mainlandCoordinateOccurrences"] += points
        else:
            counts["excludedRegionalFeatures"] += sum(modes.values())
        province_rows.append({"code": path.stem, "features": sum(modes.values()),
                              "coordinateOccurrences": points, "modes": dict(sorted(modes.items())),
                              "collectionMetadata": {k: v for k, v in collection.items() if k != "features"},
                              "disposition": "candidate" if mainland else f"existing-region-{EXISTING_REGIONS[path.stem]}"})

    tables = {}
    for family in ("station_names", "stations", "station_lanes"):
        path = source_root / "data" / f"{family}.json"
        tables[family], metadata = load(path)
        metadata["path"] = path.relative_to(source_root).as_posix()
        metadata["url"] = f"{UPSTREAM}/blob/{revision}/{metadata['path']}"
        inputs.append(metadata)
    names, positions = tables["station_names"], tables["stations"]
    aliases = tables["station_lanes"].get("stations", {})
    codes = sorted(set(names) | set(positions))
    with (output / "stations.jsonl").open("x", encoding="utf-8") as stream:
        for code in codes:
            if not re.fullmatch(r"[A-Z]{3}", code):
                raise ValueError(f"Invalid station telecode: {code}")
            position = positions.get(code)
            original = None
            if position:
                point = [position["lon"], position["lat"]]
                coordinate(point, f"station {code}")
                original = {"value": point, "declaredCRS": "GCJ02",
                            "datumStatus": "upstream-assertion-unverified"}
            city = (position or {}).get("city", "")
            # Region ownership follows the railway, not the station's border:
            # all high-speed rail through West Kowloon is exclusively CN.
            # Macau LRT (including Hengqin) remains exclusively MO.
            region = "cn" if code == "XJA" else "hk" if city == "香港特别行政区" else "mo" if city == "澳门特别行政区" else "cn"
            record = {"id": f"cn-12306-candidate-{code}", "sourceCode": code,
                      "name": names.get(code) or (position or {}).get("name", ""),
                      "sourceCoordinateRecord": position, "coordinate": original,
                      "canonicalWGS84": None, "physicalTrackID": None,
                      "region": region, "regionStatus": "inventory-scope-not-a-track-assignment",
                      "sourceCommit": revision, "runtimeEligible": False,
                      "upstreamAliasCandidate": aliases.get(code)}
            stream.write(encoded(record) + "\n")
    counts.update({"stationNames": len(names), "stationCoordinates": len(positions),
                   "stationIdentities": len(codes), "stationsWithoutCoordinates": len(set(names) - set(positions)),
                   "upstreamAliasCandidates": len(aliases)})
    manifest = {
        "schema": "jtm-crtrainroute-source-intake-v1", "country": "CN", "status": "candidate-only",
        "upstream": {"repository": UPSTREAM, "commit": revision, "retrievedAt": retrieved_at,
                     "osmSnapshotDate": None, "stationSnapshotDate": None},
        "storage": {"sourceRoot": os.path.relpath(source_root.resolve(), manifest_path.parent.resolve()),
                    "candidates": os.path.relpath(output.resolve(), manifest_path.parent.resolve()),
                    "pathsRelativeTo": "this manifest's directory", "rawInputsTracked": False},
        "counts": dict(sorted(counts.items())), "modes": dict(sorted(total_modes.items())),
        "mainlandModes": dict(sorted(mainland_modes.items())), "sourcePropertyFields": sorted(property_fields),
        "provinces": province_rows, "inputs": inputs,
        "runtimeRelease": {"eligible": False, "blockers": BLOCKERS,
                           "filesWrittenToAppResources": [], "graphImported": False},
        "licensing": {
            "code": {"license": "MIT", "notice": "Copyright (c) 2026 Laide",
                     "url": f"{UPSTREAM}/blob/{revision}/LICENSE"},
            "geometry": {"provider": "OpenStreetMap contributors via next.laide.net.cn",
                         "license": "ODbL-1.0", "url": "https://www.openstreetmap.org/copyright",
                         "extractionMetadata": "not supplied by upstream"},
            "stations": {"provider": "12306, as attributed by upstream",
                         "redistributionTerms": "not documented by upstream; unresolved"}},
        "notes": ["All modes are retained as candidates; fclass=rail is not proof of passenger service.",
                  "Hong Kong/Macao track files are inventoried but excluded from CN candidates.",
                  "Station coordinate records are retained in their declared source datum; no WGS84 anchor is inferred.",
                  "Candidate feature IDs are source locators, not persistent runtime station/line IDs.",
                  "No features are merged across source ways, parts, provinces or equal coordinates."]}
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--retrieved-at", required=True)
    args = parser.parse_args()
    manifest = build(args.source_root, args.output, args.manifest, args.source_commit, args.retrieved_at)
    print(json.dumps({"status": manifest["status"], "counts": manifest["counts"],
                      "runtimeEligible": manifest["runtimeRelease"]["eligible"]}, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
