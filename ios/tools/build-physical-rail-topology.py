#!/usr/bin/env python3
"""Inventory five-country physical track identities without inventing joins.

Coincident surveyed vertices are candidates for review, never connections.
Only the separate evidenced junction registry can authorize a graph join.
"""
import argparse
from collections import defaultdict
import hashlib
import itertools
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGIONS = ("jp", "tw", "hk", "mo", "kr")

def build():
    registry_path = ROOT / "app/data/physical-rail-junctions.json"
    registry = json.loads(registry_path.read_text())
    assert registry["format"] == "jtm-physical-rail-junctions-v1"
    reviewed = defaultdict(list)
    for row in registry["junctions"]:
        assert row["region"] in REGIONS
        assert row["evidence"] and all(row["evidence"])
        assert row["from"]["coordinate"] == row["to"]["coordinate"]
        reviewed[row["region"]].append(row)
    result = {"format": "jtm-physical-rail-topology-v1",
              "policy": "Coincidence, station transfer and through-service display never authorize track connectivity.",
              "registrySHA256": hashlib.sha256(registry_path.read_bytes()).hexdigest(), "regions": {}}
    for region in REGIONS:
        suffix = "" if region == "jp" else "-" + region
        path = ROOT / f"app/data/rail-sections{suffix}.json"
        raw = path.read_bytes()
        document = json.loads(raw)
        vertices = defaultdict(set)
        identities = set()
        segments = 0
        for feature in document["features"]:
            props = feature.get("properties") or {}
            def field(n02, plain):
                return str(props.get(n02) or props.get(plain) or "")
            identity = (field("N02_004", "operator"), field("N02_003", "line_name"),
                        field("N02_001", "railway_class_code"),
                        str(props.get("level") or ""), str(props.get("track_id") or ""))
            identities.add(identity)
            geometry = feature.get("geometry") or {}
            parts = ([geometry["coordinates"]] if geometry.get("type") == "LineString"
                     else geometry.get("coordinates", []) if geometry.get("type") == "MultiLineString" else [])
            for part in parts:
                segments += max(0, len(part) - 1)
                for lon, lat, *_ in part:
                    # Source coordinate equality is stricter than proximity.
                    vertices[(lon, lat)].add(identity)
        pairs = defaultdict(list)
        for point, memberships in vertices.items():
            for pair in itertools.combinations(sorted(memberships), 2):
                pairs[pair].append(point)
        def record(identity):
            return dict(zip(("operatorName", "lineName", "railwayClassCode", "level", "trackID"), identity))
        result["regions"][region] = {
            "sourceSHA256": hashlib.sha256(raw).hexdigest(), "physicalIdentities": len(identities),
            "surveyedSegments": segments, "surveyedVertices": len(vertices),
            "reviewedJunctionIDs": [row["id"] for row in reviewed[region]],
            "candidates": [{"fromIdentity": record(pair[0]), "toIdentity": record(pair[1]),
                            "sharedSourceVertices": len(points), "sampleSourceCoordinate": list(sorted(points)[0]),
                            "status": "requires-independent-physical-evidence"}
                           for pair, points in sorted(pairs.items())],
        }
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    target = ROOT / "app/data/physical-rail-topology.json"
    output = json.dumps(build(), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        assert target.read_text() == output, "Physical topology inventory is stale; rebuild and review it."
        print("[PASS] physical topology inventory; candidate coincidences create no edges")
    else:
        target.write_text(output)
        print(target)
