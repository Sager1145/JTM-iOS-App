#!/usr/bin/env python3
"""Inventory MLIT N02 railway snapshots without assigning event dates.

The output is an evidence artefact for temporal-history review.  A release
label such as N02-23 is recorded as a year-precision *snapshot observation*;
it is deliberately never converted to a YYYY-MM-DD event date.

Inputs may be the original N02 ZIP/GML distribution (the SHP/DBF members are
read directly) or normalized GeoJSON.  Normalized GeoJSON can be either a
FeatureCollection or an object with ``sections`` and ``stations`` arrays.
Station features are recognized by N02_005/station_name, or by an explicit
feature_kind/type value of ``station``.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import sys
import zipfile
from collections import Counter
from pathlib import Path

import shapefile


SCHEMA_VERSION = "jp-rail-history-snapshot-inventory-v1"
PUBLISHER = "Japan Ministry of Land, Infrastructure, Transport and Tourism"
DATASET = "National Land Numerical Information Railway Data (N02)"
N02_RE = re.compile(r"N02[-_](\d{2,4})", re.IGNORECASE)


def canonical_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def digest(value, size=24):
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()[:size]


def file_sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def release_year(value):
    """Return the year named by a release label, never a day-level date."""
    match = N02_RE.search(str(value))
    if not match:
        match = re.search(r"(?<!\d)(19\d{2}|20\d{2})(?!\d)", str(value))
    if not match:
        raise ValueError(f"cannot find an N02 release year in {value!r}")
    raw = match.group(1)
    if len(raw) == 4:
        return int(raw)
    year = int(raw)
    return 2000 + year if year < 70 else 1900 + year


def release_label(value):
    match = N02_RE.search(str(value))
    if match:
        raw = match.group(1)
        return f"N02-{int(raw) % 100:02d}"
    return f"N02-{release_year(value) % 100:02d}"


def round_coord(value):
    value = round(float(value), 7)
    return 0.0 if value == 0 else value


def normalize_line_coordinates(coordinates):
    if not coordinates:
        raise ValueError("empty geometry")
    if isinstance(coordinates[0], (int, float)):
        coordinates = [coordinates]
    points = []
    for point in coordinates:
        if len(point) < 2:
            raise ValueError("coordinate needs longitude and latitude")
        points.append([round_coord(point[0]), round_coord(point[1])])
    if not points:
        raise ValueError("empty geometry")
    reverse = list(reversed(points))
    return reverse if canonical_json(reverse) < canonical_json(points) else points


def geometry_summary(coordinates):
    coordinates = normalize_line_coordinates(coordinates)
    xs = [point[0] for point in coordinates]
    ys = [point[1] for point in coordinates]
    geometry_id = "geom-" + digest(coordinates, 32)
    return {
        "geometry_id": geometry_id,
        "geometry": {"type": "LineString", "coordinates": coordinates},
        "bbox": [min(xs), min(ys), max(xs), max(ys)],
        "vertex_count": len(coordinates),
    }


def clean(value):
    if isinstance(value, str):
        return value.replace("\x00", "").strip()
    return value


def first(props, *names):
    for name in names:
        value = props.get(name)
        if value is not None and value != "":
            return clean(value)
    return None


def normalized_record(kind, props, coordinates, source_feature_id=None):
    geometry = geometry_summary(coordinates)
    common = {
        "railway_class_code": first(props, "N02_001", "railway_class_code"),
        "institution_type_code": first(props, "N02_002", "institution_type_code"),
        "line_name": first(props, "N02_003", "line_name", "railway"),
        "operator": first(props, "N02_004", "operator", "operator_name"),
    }
    if kind == "station":
        attributes = {
            **common,
            "station_name": first(props, "N02_005", "station_name", "name"),
            "station_code": first(props, "N02_005c", "station_code", "n02_station_code"),
            "station_group_code": first(props, "N02_005g", "station_group_code", "n02_group_code"),
        }
    else:
        attributes = common
    record = {
        "kind": kind,
        "attributes": attributes,
        **geometry,
    }
    if source_feature_id is not None:
        record["source_feature_id"] = str(source_feature_id)
    identity = {"kind": kind, "attributes": attributes, "geometry_id": geometry["geometry_id"]}
    record["record_id"] = f"{kind}-{digest(identity)}"
    return record


def _zip_members(zf, kind):
    candidates = [name for name in zf.namelist() if name.endswith(f"{kind}.shp")]
    if not candidates:
        raise ValueError(f"archive has no {kind}.shp")
    # Match the runtime builder: avoid the superseded N02-05 v1.0 copy and
    # prefer Shift-JIS when an archive also contains a UTF-8 copy.
    candidates.sort(key=lambda name: ("v1.0" in name.lower(), "utf" in name.lower(), name))
    return candidates[0][:-4]


def read_zip_rows(path, kind):
    with zipfile.ZipFile(path) as zf:
        base = _zip_members(zf, kind)
        encoding = "utf-8" if "utf" in base.lower() else "cp932"
        reader = shapefile.Reader(
            shp=io.BytesIO(zf.read(base + ".shp")),
            dbf=io.BytesIO(zf.read(base + ".dbf")),
            encoding=encoding,
        )
        fields = [field[0].split("\x00")[0] for field in reader.fields[1:]]
        rows = []
        for index, shape_record in enumerate(reader.iterShapeRecords()):
            props = {key: clean(value) for key, value in zip(fields, shape_record.record)}
            parts = list(shape_record.shape.parts) + [len(shape_record.shape.points)]
            for part_index, (start, end) in enumerate(zip(parts, parts[1:])):
                points = shape_record.shape.points[start:end]
                minimum = 1 if kind == "Station" else 2
                if len(points) >= minimum:
                    rows.append((props, points, f"{index}:{part_index}"))
        return rows, base


def zip_coordinate_metadata(path, section_member):
    """Read the archive's declared datum; never label native JGD as WGS84."""
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        chosen = section_member + '.prj'
        if chosen not in names:
            chosen = next((n for n in sorted(names) if n.lower().endswith('.xml')
                           and 'meta' in n.lower()), None)
        if not chosen:
            chosen = next((n for n in sorted(names) if n.lower().endswith('.xml')), None)
        if not chosen:
            return {'crs': None, 'coordinate_operation': 'none; source datum undeclared'}
        raw = zf.read(chosen)
        declared = raw.decode('utf-8', errors='replace')
        crs = ('EPSG:6668' if 'JGD_2011' in declared or 'JGD2011' in declared else
               'EPSG:4612' if 'JGD_2000' in declared or 'JGD2000' in declared else None)
        return {'crs': crs, 'crs_evidence_member': chosen,
                'crs_evidence_sha256': hashlib.sha256(raw).hexdigest(),
                'coordinate_order': 'longitude_latitude',
                'coordinate_operation': 'none; native geographic coordinates preserved'}


def _features(value):
    if isinstance(value, dict) and value.get("type") == "FeatureCollection":
        return value.get("features", [])
    if isinstance(value, list):
        return value
    raise ValueError("GeoJSON collection must be a FeatureCollection or feature array")


def _geojson_kind(feature, fallback=None):
    props = feature.get("properties") or {}
    named = first(props, "feature_kind", "record_kind", "kind", "type")
    if named and str(named).lower() in ("station", "stations"):
        return "station"
    if named and str(named).lower() in ("section", "sections", "railroadsection"):
        return "section"
    if first(props, "N02_005", "station_name") is not None:
        return "station"
    return fallback or "section"


def _geometry_parts(feature):
    geometry = feature.get("geometry") or {}
    kind = geometry.get("type")
    coords = geometry.get("coordinates")
    if kind == "Point":
        return [[coords]]
    if kind == "LineString":
        return [coords]
    if kind == "MultiLineString":
        return coords
    raise ValueError(f"unsupported GeoJSON geometry {kind!r}")


def read_geojson(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    metadata = data.get("metadata", {}) if isinstance(data, dict) else {}
    rows = []
    if isinstance(data, dict) and ("sections" in data or "stations" in data):
        collections = (("section", data.get("sections", [])), ("station", data.get("stations", [])))
    else:
        collections = ((None, _features(data)),)
    for fallback, collection in collections:
        for index, feature in enumerate(_features(collection)):
            props = feature.get("properties") or {}
            kind = _geojson_kind(feature, fallback)
            feature_id = feature.get("id", index)
            for part_index, points in enumerate(_geometry_parts(feature)):
                rows.append((kind, props, points, f"{feature_id}:{part_index}"))
    return rows, metadata


def _deduplicate_ids(records):
    counts = Counter(record["record_id"] for record in records)
    seen = Counter()
    for record in records:
        record_id = record["record_id"]
        if counts[record_id] > 1:
            seen[record_id] += 1
            record["record_id"] = f"{record_id}-{seen[record_id]:03d}"


def load_provenance(path):
    if not path:
        return {}
    with open(path, encoding="utf-8") as f:
        value = json.load(f)
    if not isinstance(value, dict):
        raise ValueError("provenance manifest must be an object keyed by source path or filename")
    return value


def provenance_override(manifest, path, relative_path):
    for key in (relative_path, path.name, str(path)):
        if key in manifest:
            value = manifest[key]
            if not isinstance(value, dict):
                raise ValueError(f"provenance entry {key!r} must be an object")
            return value
    return {}


def _identity_inventory(records):
    groups = {}
    for record in records:
        attrs = record["attributes"]
        key = (record["kind"], attrs.get("operator"), attrs.get("line_name"))
        group = groups.setdefault(key, {"geometry_ids": [], "station_names": set()})
        group["geometry_ids"].append(record["geometry_id"])
        if attrs.get("station_name"):
            group["station_names"].add(attrs["station_name"])
    result = []
    for (kind, operator, line_name), values in sorted(groups.items(), key=lambda item: canonical_json(item[0])):
        row = {
            "kind": kind,
            "operator": operator,
            "line_name": line_name,
            "record_count": len(values["geometry_ids"]),
            "geometry_set_digest": digest(sorted(values["geometry_ids"]), 32),
        }
        if kind == "station":
            row["station_name_count"] = len(values["station_names"])
        result.append(row)
    return result


def inventory_snapshot(path, source_root=None, provenance=None, record_mode="full"):
    path = Path(path).resolve()
    source_root = Path(source_root).resolve() if source_root else path.parent
    try:
        relative_path = path.relative_to(source_root).as_posix()
    except ValueError:
        relative_path = path.name
    override = provenance_override(provenance or {}, path, relative_path)
    if record_mode not in ("full", "summary", "manifest"):
        raise ValueError(f"unknown record mode {record_mode!r}")

    if path.suffix.lower() == ".zip":
        section_rows, section_member = read_zip_rows(path, "RailroadSection")
        station_rows, station_member = read_zip_rows(path, "Station")
        records = [normalized_record("section", p, pts, fid) for p, pts, fid in section_rows]
        records += [normalized_record("station", p, pts, fid) for p, pts, fid in station_rows]
        source_format = "n02-zip-shapefile"
        members = {"sections": section_member, "stations": station_member}
        metadata = zip_coordinate_metadata(path, section_member)
    elif path.suffix.lower() in (".json", ".geojson"):
        rows, metadata = read_geojson(path)
        records = [normalized_record(kind, props, pts, fid) for kind, props, pts, fid in rows]
        source_format = "normalized-geojson"
        members = None
    else:
        raise ValueError(f"unsupported snapshot input {path}")

    embedded_provenance = metadata.get("provenance", {}) if isinstance(metadata.get("provenance"), dict) else {}
    source_metadata = {**embedded_provenance, **override}
    label = source_metadata.get("release_label") or metadata.get("release_label") or release_label(path.name)
    year = source_metadata.get("release_year") or metadata.get("release_year") or release_year(label)
    year = int(year)
    label = str(label)
    snapshot_id = source_metadata.get("snapshot_id") or metadata.get("snapshot_id") or f"jp-n02-{year}"
    observation = {
        "value": f"{year:04d}",
        "precision": "year",
        "role": "dataset_snapshot_vintage",
        "event_date": None,
        "event_date_inference": "forbidden",
    }
    supplied = source_metadata.get("observation", metadata.get("observation"))
    if supplied is not None:
        if not isinstance(supplied, dict) or supplied.get("precision") not in ("year", "month", "day"):
            raise ValueError(f"{path}: observation needs explicit year/month/day precision")
        observation.update(supplied)
        observation["event_date"] = None
        observation["event_date_inference"] = "forbidden"

    records.sort(key=lambda r: (r["kind"], canonical_json(r["attributes"]), r["geometry_id"], r.get("source_feature_id", "")))
    _deduplicate_ids(records)
    sections = [record for record in records if record["kind"] == "section"]
    stations = [record for record in records if record["kind"] == "station"]
    content_digest = digest([record["record_id"] for record in records], 64)
    identities = _identity_inventory(records)
    source = {
        "publisher": source_metadata.get("publisher", PUBLISHER),
        "dataset": source_metadata.get("dataset", DATASET),
        "release_label": label,
        "source_path": relative_path,
        "sha256": file_sha256(path),
        "format": source_format,
        "crs": source_metadata.get("crs", metadata.get("crs", "EPSG:4326")),
        "source_url": source_metadata.get("source_url"),
        "license": source_metadata.get("license"),
        "licence_reference": source_metadata.get('licence_reference'),
        "retrieved": source_metadata.get("retrieved"),
    }
    for key in ('crs_evidence_member', 'crs_evidence_sha256', 'coordinate_order', 'coordinate_operation'):
        if key in metadata:
            source[key] = metadata[key]
    if members:
        source["archive_members"] = members
    if embedded_provenance:
        source["upstream"] = embedded_provenance
    snapshot = {
        "snapshot_id": snapshot_id,
        "observation": observation,
        "provenance": source,
        "record_mode": record_mode,
        "content_digest": content_digest,
        "counts": {"sections": len(sections), "stations": len(stations)},
        "identity_inventory": identities,
    }
    if record_mode != "manifest":
        if record_mode == "summary":
            for record in records:
                record.pop("geometry", None)
        snapshot["sections"] = sections
        snapshot["stations"] = stations
    return snapshot


def discover_inputs(source_dir):
    root = Path(source_dir)
    paths = []
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in (".zip", ".json", ".geojson"):
            if not N02_RE.search(path.name):
                continue
            try:
                release_year(path.name)
            except ValueError:
                continue
            paths.append(path)
    return sorted(paths, key=lambda path: (release_year(path.name), path.name))


def build_inventory(paths, source_root=None, provenance=None, record_mode="full"):
    snapshots = [inventory_snapshot(path, source_root, provenance, record_mode) for path in paths]
    snapshots.sort(key=lambda s: (s["observation"]["value"], s["snapshot_id"]))
    seen = Counter(snapshot["snapshot_id"] for snapshot in snapshots)
    duplicates = [key for key, count in seen.items() if count > 1]
    if duplicates:
        raise ValueError(f"duplicate snapshot ids: {', '.join(duplicates)}")
    return {
        "schema_version": SCHEMA_VERSION,
        "temporal_policy": {
            "snapshot_observations_are_event_dates": False,
            "candidate_event_dates_require_external_review": True,
        },
        "snapshots": snapshots,
    }


def write_json(value, output):
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if output == "-":
        sys.stdout.write(text)
    else:
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        with open(output, "w", encoding="utf-8") as f:
            f.write(text)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="*", help="N02 ZIP or normalized GeoJSON snapshots")
    parser.add_argument("--source-dir", help="discover snapshots here; also anchors relative source paths")
    parser.add_argument("--provenance", help="JSON metadata keyed by relative path or filename")
    parser.add_argument(
        "--record-mode", choices=("full", "summary", "manifest"), default="full",
        help="full coordinates, per-record summaries, or compact snapshot/identity manifest",
    )
    parser.add_argument("--output", default="-", help="output JSON path (default: stdout)")
    args = parser.parse_args(argv)
    if args.inputs:
        paths = [Path(path) for path in args.inputs]
        source_root = args.source_dir or os.path.commonpath([str(path.resolve().parent) for path in paths])
    elif args.source_dir:
        paths = discover_inputs(args.source_dir)
        source_root = args.source_dir
    else:
        parser.error("provide snapshots or --source-dir")
    if not paths:
        parser.error("no N02 snapshot inputs found")
    try:
        value = build_inventory(paths, source_root, load_provenance(args.provenance), args.record_mode)
        write_json(value, args.output)
    except (OSError, ValueError, json.JSONDecodeError, zipfile.BadZipFile, shapefile.ShapefileException) as error:
        parser.exit(2, f"inventory-jp-history: {error}\n")


if __name__ == "__main__":
    main()
