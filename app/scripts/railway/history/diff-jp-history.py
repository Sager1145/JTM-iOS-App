#!/usr/bin/env python3
"""Diff two JP railway snapshot inventories into an unverified review queue.

The diff reports exact surveyed-geometry additions/removals, exact geometry
whose operator or line identity changed, and station additions, removals,
renames, identity changes, and moves.  Every result remains a candidate: an
annual snapshot interval cannot establish an event's calendar day or cause.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path


SCHEMA_VERSION = "jp-rail-history-diff-candidates-v1"


def canonical_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def digest(value, size=24):
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()[:size]


def semantic_key(record):
    return canonical_json({"attributes": record.get("attributes", {}), "geometry_id": record["geometry_id"]})


def identity_key(record, include_name=False):
    attrs = record.get("attributes", {})
    keys = ["operator", "line_name"]
    if include_name:
        keys.append("station_name")
    return tuple(attrs.get(key) for key in keys)


def station_code(record):
    return record.get("attributes", {}).get("station_code")


def record_sort_key(record):
    return (semantic_key(record), record.get("record_id", ""))


def pop_exact_unchanged(before, after):
    by_key = defaultdict(list)
    for record in sorted(after, key=record_sort_key):
        by_key[semantic_key(record)].append(record)
    remaining_before = []
    matched_after_ids = set()
    for record in sorted(before, key=record_sort_key):
        values = by_key.get(semantic_key(record))
        if values:
            other = values.pop(0)
            matched_after_ids.add(id(other))
        else:
            remaining_before.append(record)
    remaining_after = [record for record in after if id(record) not in matched_after_ids]
    return remaining_before, remaining_after


def pair_by_key(before, after, key_fn):
    before_groups, after_groups = defaultdict(list), defaultdict(list)
    for record in before:
        key = key_fn(record)
        if key is not None:
            before_groups[key].append(record)
    for record in after:
        key = key_fn(record)
        if key is not None:
            after_groups[key].append(record)
    pairs = []
    used_before, used_after = set(), set()
    for key in sorted(set(before_groups) & set(after_groups), key=canonical_json):
        left = sorted(before_groups[key], key=record_sort_key)
        right = sorted(after_groups[key], key=record_sort_key)
        for old, new in zip(left, right):
            pairs.append((old, new))
            used_before.add(id(old))
            used_after.add(id(new))
    return (
        pairs,
        [record for record in before if id(record) not in used_before],
        [record for record in after if id(record) not in used_after],
    )


def changed_fields(old, new, names):
    old_attrs, new_attrs = old.get("attributes", {}), new.get("attributes", {})
    return {
        name: {"before": old_attrs.get(name), "after": new_attrs.get(name)}
        for name in names
        if old_attrs.get(name) != new_attrs.get(name)
    }


def centroid(record):
    coords = record.get("geometry", {}).get("coordinates", [])
    if not coords:
        bbox = record["bbox"]
        return ((bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2)
    return (
        sum(point[0] for point in coords) / len(coords),
        sum(point[1] for point in coords) / len(coords),
    )


def distance_m(a, b):
    lon1, lat1 = map(math.radians, a)
    lon2, lat2 = map(math.radians, b)
    x = (lon2 - lon1) * math.cos((lat1 + lat2) / 2)
    y = lat2 - lat1
    return math.hypot(x, y) * 6371008.8


def evidence(snapshot, record):
    if record is None:
        return None
    provenance = snapshot.get("provenance", {})
    return {
        "snapshot_id": snapshot["snapshot_id"],
        "observation": snapshot["observation"],
        "source": {
            "release_label": provenance.get("release_label"),
            "source_path": provenance.get("source_path"),
            "sha256": provenance.get("sha256"),
            "publisher": provenance.get("publisher"),
            "dataset": provenance.get("dataset"),
            "source_url": provenance.get("source_url"),
            "license": provenance.get("license"),
        },
        "record": record,
    }


def make_candidate(kind, before_snapshot, after_snapshot, old=None, new=None, basis=None, details=None):
    details = details or {}
    identity = {
        "kind": kind,
        "before_snapshot": before_snapshot["snapshot_id"],
        "after_snapshot": after_snapshot["snapshot_id"],
        "before_record": old.get("record_id") if old else None,
        "after_record": new.get("record_id") if new else None,
        "match_basis": basis,
        "details": details,
    }
    candidate_id = "jp-history-candidate-" + digest(identity, 28)
    return {
        "candidate_id": candidate_id,
        "candidate_kind": kind,
        "status": "needs_review",
        "verification": {"state": "unverified", "automatic": False},
        "temporal_evidence": {
            "last_observed_snapshot": before_snapshot["observation"],
            "first_observed_snapshot": after_snapshot["observation"],
            "event_date": None,
            "precision": "snapshot_interval",
            "note": "The state changed between snapshots; no event day is inferred.",
        },
        "match_basis": basis,
        "details": details,
        "before": evidence(before_snapshot, old),
        "after": evidence(after_snapshot, new),
        "review": {
            "required": True,
            "state": "unreviewed",
            "requirements": [
                "confirm the change against a primary source",
                "record the exact date and its precision only when sourced",
                "decide service and infrastructure validity separately when they differ",
            ],
        },
    }


def diff_sections(before_snapshot, after_snapshot):
    old, new = pop_exact_unchanged(before_snapshot.get("sections", []), after_snapshot.get("sections", []))
    pairs, old, new = pair_by_key(old, new, lambda record: record["geometry_id"])
    candidates = []
    identity_fields = ("operator", "line_name", "railway_class_code", "institution_type_code")
    for before_record, after_record in pairs:
        changes = changed_fields(before_record, after_record, identity_fields)
        if changes:
            candidates.append(make_candidate(
                "section_identity_changed", before_snapshot, after_snapshot,
                before_record, after_record, "exact_geometry", {"changed_fields": changes},
            ))
    for record in old:
        candidates.append(make_candidate(
            "section_geometry_removed", before_snapshot, after_snapshot,
            old=record, basis="unmatched_exact_geometry",
        ))
    for record in new:
        candidates.append(make_candidate(
            "section_geometry_added", before_snapshot, after_snapshot,
            new=record, basis="unmatched_exact_geometry",
        ))
    return candidates


def diff_stations(before_snapshot, after_snapshot):
    old, new = pop_exact_unchanged(before_snapshot.get("stations", []), after_snapshot.get("stations", []))
    all_pairs = []

    pairs, old, new = pair_by_key(old, new, lambda record: station_code(record) or None)
    all_pairs.extend((a, b, "stable_station_code") for a, b in pairs)

    pairs, old, new = pair_by_key(old, new, lambda record: record["geometry_id"])
    all_pairs.extend((a, b, "exact_geometry") for a, b in pairs)

    pairs, old, new = pair_by_key(old, new, lambda record: identity_key(record, include_name=True))
    all_pairs.extend((a, b, "exact_operator_line_name") for a, b in pairs)

    candidates = []
    for before_record, after_record, basis in all_pairs:
        attrs_before = before_record.get("attributes", {})
        attrs_after = after_record.get("attributes", {})
        if attrs_before.get("station_name") != attrs_after.get("station_name"):
            candidates.append(make_candidate(
                "station_name_changed", before_snapshot, after_snapshot,
                before_record, after_record, basis,
                {"changed_fields": changed_fields(before_record, after_record, ("station_name",))},
            ))
        identity_changes = changed_fields(
            before_record, after_record,
            ("operator", "line_name", "station_code", "station_group_code", "railway_class_code", "institution_type_code"),
        )
        if identity_changes:
            candidates.append(make_candidate(
                "station_identity_changed", before_snapshot, after_snapshot,
                before_record, after_record, basis, {"changed_fields": identity_changes},
            ))
        if before_record["geometry_id"] != after_record["geometry_id"]:
            candidates.append(make_candidate(
                "station_moved", before_snapshot, after_snapshot,
                before_record, after_record, basis,
                {
                    "distance_m": round(distance_m(centroid(before_record), centroid(after_record)), 1),
                    "before_geometry_id": before_record["geometry_id"],
                    "after_geometry_id": after_record["geometry_id"],
                },
            ))
    for record in old:
        candidates.append(make_candidate(
            "station_removed", before_snapshot, after_snapshot,
            old=record, basis="unmatched_station",
        ))
    for record in new:
        candidates.append(make_candidate(
            "station_added", before_snapshot, after_snapshot,
            new=record, basis="unmatched_station",
        ))
    return candidates


def validate_interval(before_snapshot, after_snapshot):
    before_value = before_snapshot.get("observation", {}).get("value")
    after_value = after_snapshot.get("observation", {}).get("value")
    if not before_value or not after_value:
        raise ValueError("both snapshots need an observation value")
    if before_value >= after_value:
        raise ValueError(f"before snapshot {before_value!r} must precede after snapshot {after_value!r}")


def diff_snapshots(before_snapshot, after_snapshot):
    validate_interval(before_snapshot, after_snapshot)
    candidates = diff_sections(before_snapshot, after_snapshot)
    candidates += diff_stations(before_snapshot, after_snapshot)
    candidates.sort(key=lambda c: (c["candidate_kind"], c["candidate_id"]))
    counts = Counter(candidate["candidate_kind"] for candidate in candidates)
    return {
        "schema_version": SCHEMA_VERSION,
        "interval": {
            "before_snapshot_id": before_snapshot["snapshot_id"],
            "after_snapshot_id": after_snapshot["snapshot_id"],
            "event_date": None,
            "precision": "snapshot_interval",
        },
        "policy": {
            "auto_verify_candidates": False,
            "infer_day_dates_from_snapshots": False,
        },
        "summary": {"candidate_count": len(candidates), "by_kind": dict(sorted(counts.items()))},
        "review_queue": candidates,
    }


def load_inventory(path):
    with open(path, encoding="utf-8") as f:
        value = json.load(f)
    if "snapshots" not in value:
        if "snapshot_id" in value:
            return [value]
        raise ValueError(f"{path}: not a snapshot inventory")
    return value["snapshots"]


def select_snapshot(snapshots, snapshot_id, label):
    if snapshot_id:
        selected = [snapshot for snapshot in snapshots if snapshot.get("snapshot_id") == snapshot_id]
        if len(selected) != 1:
            raise ValueError(f"{label}: snapshot id {snapshot_id!r} matched {len(selected)} snapshots")
        return selected[0]
    if len(snapshots) != 1:
        raise ValueError(f"{label}: choose a snapshot id from an inventory with {len(snapshots)} snapshots")
    return snapshots[0]


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
    parser.add_argument("inventory", help="before inventory, or the inventory containing both snapshots")
    parser.add_argument("--after-inventory", help="separate after inventory")
    parser.add_argument("--before", help="before snapshot_id (required when inventory has several)")
    parser.add_argument("--after", help="after snapshot_id (required when inventory has several)")
    parser.add_argument("--output", default="-", help="output JSON path (default: stdout)")
    args = parser.parse_args(argv)
    try:
        before_values = load_inventory(args.inventory)
        after_values = load_inventory(args.after_inventory) if args.after_inventory else before_values
        before = select_snapshot(before_values, args.before, "before")
        after = select_snapshot(after_values, args.after, "after")
        if before is after:
            raise ValueError("before and after resolve to the same snapshot")
        write_json(diff_snapshots(before, after), args.output)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(2, f"diff-jp-history: {error}\n")


if __name__ == "__main__":
    main()
