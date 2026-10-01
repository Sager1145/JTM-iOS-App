#!/usr/bin/env python3
"""Normalize MLIT's legacy 1996-reference N02 archive to GeoJSON.

This adapter is intentionally specific to the official JGD2000 unified-text
archive N02-07L-48-01.1a.zip.  The source has nodes, links, named line ledgers,
and station-node ledgers.  It does *not* have a separate operator/company
field: N02_004 is therefore null and the route descriptor is never split by a
name heuristic.

The source is a historical snapshot.  Its 1996-12-31 metadata reference date
is an observation, not an inferred opening/closure day and not current track.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import zipfile
from collections import defaultdict
from pathlib import Path


SOURCE_URL = "https://nlftp.mlit.go.jp/ksj/old/data/N02/N02-07L/N02-07L-48-01.1a.zip"
EXPECTED_SHA256 = "106509ab37025656fda7d8f9357fe8a20d2fcdb653fe5bf9f4c6ebd066aa07fa"
DATA_MEMBER = "N02-07L-2K.txt"
FORMAT_MEMBER = "N02-07L.html"
METADATA_MEMBER = "KS-META-N02-07L.html"
SCHEMA_VERSION = "jtm-n02-normalized-snapshot-v1"


FIELD_MAPPING = {
    "node": {
        "mesh": "N[3:9]",
        "node_number": "N[9:15]",
        "longitude": "N[15:23] / 36000 (0.1 arc-second)",
        "latitude": "N[23:31] / 36000 (0.1 arc-second)",
        "station_attribute": "N[33:43] when the ledger flag N[31:33] is 1",
    },
    "link": {
        "key": "L start-mesh[3:9] + link-number[27:33]",
        "start_node": "L[3:15]",
        "end_node": "L[15:27]",
        "point_count": "L[45:51]",
        "points": "continuation rows, five (longitude, latitude) pairs per row",
    },
    "line": {
        "line_id": "S[27:35]",
        "line_attribute": "S[37:47]",
        "link_count": "S[47:53]",
        "links": "continuation rows, five (mesh, link-number, display-flag) triples per row",
    },
    "station_ledger": {"station_code": "DP[3:13]", "station_name": "DP[16:72]"},
    "line_ledger": {
        "route_code": "DS[3:13]",
        "institution_type_code": "DS[16:18]",
        "route_descriptor": "DS[18:]",
        "operator": None,
    },
}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def integer(text, label, allow_blank=False):
    value = text.strip()
    if not value and allow_blank:
        return None
    try:
        return int(value)
    except ValueError as error:
        raise ValueError(f"{label}: invalid integer {text!r}") from error


def coordinate(raw_lon, raw_lat, label):
    lon, lat = raw_lon / 36000.0, raw_lat / 36000.0
    if not (120 <= lon <= 155 and 20 <= lat <= 50):
        raise ValueError(f"{label}: coordinate outside Japan bounds: {(lon, lat)}")
    # JGD2000 and WGS84 are retained numerically at the source's 0.1 arc-second
    # resolution. The operation and resolution are stated in output metadata.
    return [round(lon, 7), round(lat, 7)]


def node_key(mesh, number):
    return f"{mesh:06d}:{number:06d}"


def link_key(mesh, number):
    return f"{mesh:06d}:{number:06d}"


def _parse_nodes(lines):
    nodes = {}
    attribute_nodes = {}
    for ordinal, line in enumerate(lines):
        if not line.startswith("N  "):
            raise ValueError(f"node row {ordinal}: expected N record")
        mesh = integer(line[3:9], "node mesh")
        number = integer(line[9:15], "node number")
        key = node_key(mesh, number)
        nodes[key] = coordinate(
            integer(line[15:23], "node longitude"),
            integer(line[23:31], "node latitude"),
            key,
        )
        ledger_flag = integer(line[31:33], "node ledger flag")
        attribute = line[33:43].strip()
        if ledger_flag == 1:
            if not attribute:
                raise ValueError(f"{key}: station ledger flag without attribute number")
            attribute_nodes[attribute] = key
    return nodes, attribute_nodes


def _point_rows(rows, count, label):
    points = []
    for row in rows:
        padded = row.ljust(80)
        for offset in range(0, 80, 16):
            lon_text, lat_text = padded[offset:offset + 8], padded[offset + 8:offset + 16]
            if not lon_text.strip() and not lat_text.strip():
                continue
            points.append(coordinate(
                integer(lon_text, f"{label} longitude"),
                integer(lat_text, f"{label} latitude"),
                label,
            ))
    if len(points) != count:
        raise ValueError(f"{label}: expected {count} points, read {len(points)}")
    return points


def _parse_links(lines):
    links = {}
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith("L  "):
            raise ValueError(f"link source row {index}: expected L record")
        start_mesh = integer(line[3:9], "link start mesh")
        start_number = integer(line[9:15], "link start node")
        end_mesh = integer(line[15:21], "link end mesh")
        end_number = integer(line[21:27], "link end node")
        number = integer(line[27:33], "link number")
        count = integer(line[45:51], "link point count")
        continuation_count = math.ceil(count / 5)
        key = link_key(start_mesh, number)
        points = _point_rows(lines[index + 1:index + 1 + continuation_count], count, key)
        links[key] = {
            "start_node": node_key(start_mesh, start_number),
            "end_node": node_key(end_mesh, end_number),
            "coordinates": points,
        }
        index += 1 + continuation_count
    return links


def _line_refs(rows, count, label):
    refs = []
    for row in rows:
        padded = row.ljust(70)
        for offset in range(0, 70, 14):
            mesh_text = padded[offset:offset + 6]
            if not mesh_text.strip():
                continue
            mesh = integer(mesh_text, f"{label} link mesh")
            number = integer(padded[offset + 6:offset + 12], f"{label} link number")
            flag = integer(padded[offset + 12:offset + 14], f"{label} display flag")
            refs.append({"link_key": link_key(mesh, number), "display_flag": flag})
    if len(refs) != count:
        raise ValueError(f"{label}: expected {count} links, read {len(refs)}")
    return refs


def _parse_lines(lines):
    values = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith("S  "):
            raise ValueError(f"line source row {index}: expected S record")
        line_id = line[27:35].strip()
        attribute = line[37:47].strip()
        count = integer(line[47:53], "line link count")
        continuation_count = math.ceil(count / 5)
        refs = _line_refs(lines[index + 1:index + 1 + continuation_count], count, line_id)
        values.append({"line_id": line_id, "attribute": attribute, "links": refs})
        index += 1 + continuation_count
    return values


def _parse_station_ledger(lines):
    ledger = {}
    for line in lines:
        if not line.startswith("DP "):
            raise ValueError("expected DP station-ledger record")
        attribute = line[3:13].strip()
        if integer(line[13:16], "station attribute line count") != 1:
            raise ValueError(f"{attribute}: multiline station ledger is unsupported")
        ledger[attribute] = line[16:72].strip()
    return ledger


def _parse_line_ledger(lines):
    ledger = {}
    for line in lines:
        if not line.startswith("DS "):
            raise ValueError("expected DS line-ledger record")
        attribute = line[3:13].strip()
        if integer(line[13:16], "line attribute line count") != 1:
            raise ValueError(f"{attribute}: multiline line ledger is unsupported")
        ledger[attribute] = {
            "institution_type_code": line[16:18].strip(),
            "route_descriptor": line[18:].strip(),
        }
    return ledger


def parse_unified_text(text):
    rows = text.splitlines()
    if len(rows) < 2 or not rows[0].startswith("H  "):
        raise ValueError("missing legacy N02 header")
    if rows[0][13:23].strip() != "N02-07L-2K":
        raise ValueError(f"unexpected data code {rows[0][13:23].strip()!r}")
    counts = [integer(rows[1][offset:offset + 8], "header count") for offset in range(0, 56, 8)]
    total, node_count, link_rows, line_rows, station_rows, link_ledger_rows, line_ledger_rows = counts
    if link_ledger_rows:
        raise ValueError("unexpected link ledger records")
    if total != sum(counts[1:]):
        raise ValueError(f"header total {total} does not equal component rows {sum(counts[1:])}")
    if len(rows) != total + 2:
        raise ValueError(f"header says {total} data rows; file has {len(rows) - 2}")
    index = 2
    node_lines = rows[index:index + node_count]; index += node_count
    link_lines = rows[index:index + link_rows]; index += link_rows
    line_lines = rows[index:index + line_rows]; index += line_rows
    station_lines = rows[index:index + station_rows]; index += station_rows
    index += link_ledger_rows
    ledger_lines = rows[index:index + line_ledger_rows]
    nodes, attribute_nodes = _parse_nodes(node_lines)
    return {
        "nodes": nodes,
        "attribute_nodes": attribute_nodes,
        "links": _parse_links(link_lines),
        "lines": _parse_lines(line_lines),
        "station_ledger": _parse_station_ledger(station_lines),
        "line_ledger": _parse_line_ledger(ledger_lines),
        "header": {"declared_counts": {
            "total": total, "nodes": node_count, "link_rows": link_rows,
            "line_rows": line_rows, "station_ledger_rows": station_rows,
            "line_ledger_rows": line_ledger_rows,
        }},
    }


def _oriented_first(coords, following):
    if not following:
        return list(coords)
    endpoints = {tuple(following[0]), tuple(following[-1])}
    if tuple(coords[0]) in endpoints and tuple(coords[-1]) not in endpoints:
        return list(reversed(coords))
    return list(coords)


def chain_links(refs, links):
    visible = [ref for ref in refs if ref["display_flag"] == 0]
    if not visible:
        return []
    raw = []
    for ref in visible:
        if ref["link_key"] not in links:
            raise ValueError(f"line references missing link {ref['link_key']}")
        raw.append(links[ref["link_key"]]["coordinates"])
    parts = []
    current = _oriented_first(raw[0], raw[1] if len(raw) > 1 else None)
    for index, coords in enumerate(raw[1:], 1):
        if current[-1] == coords[0]:
            current.extend(coords[1:])
        elif current[-1] == coords[-1]:
            current.extend(list(reversed(coords[:-1])))
        else:
            parts.append(current)
            following = raw[index + 1] if index + 1 < len(raw) else None
            current = _oriented_first(coords, following)
    parts.append(current)
    return [part for part in parts if len(part) >= 2]


def normalize(parsed, source_sha256=EXPECTED_SHA256):
    sections, stations = [], []
    node_lines = defaultdict(set)
    anomalies = []
    referenced_attributes = {line["attribute"] for line in parsed["lines"]}
    for attribute in sorted(set(parsed["line_ledger"]) - referenced_attributes):
        anomalies.append({
            "code": "UNREFERENCED_LINE_LEDGER",
            "line_attribute": attribute,
            "route_descriptor": parsed["line_ledger"][attribute]["route_descriptor"],
            "resolution": "left unlinked; no correction inferred",
        })
    for line in parsed["lines"]:
        ledger = parsed["line_ledger"].get(line["attribute"])
        if not ledger:
            ledger = {}
            anomalies.append({
                "code": "MISSING_LINE_LEDGER",
                "line_id": line["line_id"],
                "line_attribute": line["attribute"],
                "resolution": "geometry retained with N02_001..N02_004 null; no identity guessed",
            })
        properties = {
            "feature_kind": "section",
            "N02_001": None,
            "N02_002": ledger.get("institution_type_code") or None,
            "N02_003": ledger.get("route_descriptor") or None,
            "N02_004": None,
            "legacy_line_id": line["line_id"],
            "legacy_route_code": line["attribute"],
            "legacy_identity_precision": "route_descriptor_only; operator field unavailable",
        }
        for ref in line["links"]:
            link = parsed["links"].get(ref["link_key"])
            if link:
                node_lines[link["start_node"]].add(line["line_id"])
                node_lines[link["end_node"]].add(line["line_id"])
        for part_index, coordinates in enumerate(chain_links(line["links"], parsed["links"])):
            feature_properties = dict(properties, legacy_part_index=part_index)
            sections.append({
                "type": "Feature", "properties": feature_properties,
                "geometry": {"type": "LineString", "coordinates": coordinates},
            })

    lines_by_id = {line["line_id"]: line for line in parsed["lines"]}
    for attribute in sorted(set(parsed["attribute_nodes"]) - set(parsed["station_ledger"])):
        anomalies.append({
            "code": "UNREFERENCED_STATION_NODE_ATTRIBUTE",
            "station_attribute": attribute,
            "node": parsed["attribute_nodes"][attribute],
            "resolution": "node retained in section geometry; no station name inferred",
        })
    for attribute, name in sorted(parsed["station_ledger"].items()):
        node = parsed["attribute_nodes"].get(attribute)
        if not node:
            anomalies.append({
                "code": "UNLOCATED_STATION_LEDGER",
                "station_attribute": attribute,
                "station_name": name,
                "resolution": "station omitted because the source provides no matching geometry; no location inferred",
            })
            continue
        memberships = sorted(node_lines.get(node, ())) or [None]
        for line_id in memberships:
            line = lines_by_id.get(line_id) if line_id else None
            ledger = (parsed["line_ledger"].get(line["attribute"]) or {}) if line else {}
            stations.append({
                "type": "Feature",
                "properties": {
                    "feature_kind": "station",
                    "N02_001": None,
                    "N02_002": ledger.get("institution_type_code") or None,
                    "N02_003": ledger.get("route_descriptor") or None,
                    "N02_004": None,
                    "N02_005": name,
                    "N02_005c": attribute,
                    "legacy_line_id": line_id,
                    "legacy_identity_precision": "route descriptor and station name; operator field unavailable",
                },
                "geometry": {"type": "Point", "coordinates": parsed["nodes"][node]},
            })
    return {
        "schema_version": SCHEMA_VERSION,
        "metadata": {
            "snapshot_id": "jp-n02-1996",
            "release_label": "N02-96",
            "release_year": 1996,
            "observation": {
                "value": "1996-12-31", "precision": "day",
                "role": "source_metadata_reference_date", "event_date": None,
                "event_date_inference": "forbidden",
            },
            "crs": "EPSG:4326",
            "source_crs": "EPSG:4612 (JGD2000 geographic latitude/longitude)",
            "coordinate_operation": {
                "method": "numeric identity at source precision",
                "source_resolution": "0.1 arc-second",
                "note": "JGD2000 geographic values are retained numerically as WGS84; no event or current-track meaning is implied.",
            },
            "provenance": {
                "publisher": "Japan National Land Agency / MLIT archive",
                "dataset": "National Land Numerical Information Railway N02-07L",
                "source_url": SOURCE_URL,
                "sha256": source_sha256,
                "archive_members": [METADATA_MEMBER, DATA_MEMBER, FORMAT_MEMBER],
                "format_specification_member": FORMAT_MEMBER,
                "metadata_member": METADATA_MEMBER,
                "license": {
                    "status": "legacy_terms_apply; redistribution/commercial status not asserted",
                    "terms_url": "https://nlftp.mlit.go.jp/ksj/other/agreement_02.html",
                    "faq_url": "https://nlftp.mlit.go.jp/ksj/other/faq.html",
                },
            },
            "identity_limitations": [
                "The legacy DS ledger has no separate operator/company field; N02_004 remains null.",
                "DS route descriptors may contain operator text, but this adapter does not split or infer it.",
                "The four-class DS code is preserved as N02_002; N02_001 is unavailable and remains null.",
            ],
            "source_anomalies": anomalies,
            "field_mapping": FIELD_MAPPING,
            "source_counts": parsed["header"]["declared_counts"],
        },
        "sections": {"type": "FeatureCollection", "features": sections},
        "stations": {"type": "FeatureCollection", "features": stations},
    }


def normalize_archive(path, enforce_hash=True):
    actual_hash = sha256(path)
    if enforce_hash and actual_hash != EXPECTED_SHA256:
        raise ValueError(f"archive SHA-256 {actual_hash} does not match pinned official archive")
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        missing = {DATA_MEMBER, FORMAT_MEMBER, METADATA_MEMBER} - names
        if missing:
            raise ValueError(f"archive missing required members: {', '.join(sorted(missing))}")
        text = archive.read(DATA_MEMBER).decode("cp932")
    return normalize(parse_unified_text(text), actual_hash)


def write_json(value, output):
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if output == "-":
        sys.stdout.write(text)
    else:
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        Path(output).write_text(text, encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", help="official N02-07L-48-01.1a.zip")
    parser.add_argument("--output", default="-", help="normalized JSON path (default: stdout)")
    parser.add_argument("--allow-unpinned", action="store_true", help="development fixtures only: accept a different SHA-256")
    args = parser.parse_args(argv)
    try:
        write_json(normalize_archive(args.archive, not args.allow_unpinned), args.output)
    except (OSError, ValueError, UnicodeDecodeError, zipfile.BadZipFile) as error:
        parser.exit(2, f"normalize-n02-1996: {error}\n")


if __name__ == "__main__":
    main()
