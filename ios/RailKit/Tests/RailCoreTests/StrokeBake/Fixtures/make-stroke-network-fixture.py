#!/usr/bin/env python3
"""Cut the stroke-bake test fixture out of a builder output directory.

    python3 -I make-stroke-network-fixture.py <display-network-dir> stroke-network.json

The fixture holds, per region, the manifest's line metadata and the display
chunk of every selected railway (stations reduced to id, lineKey and slot, the
only parts the stroke engine reads). hk and mo are complete; jp is a selection:
lines with follows, lines with family windows, reviewed lane and branch-boundary
lines, a Tokyo window of small lines for junctions, and the `dependsOn` closure
of all of them.
"""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
out = Path(sys.argv[2])
manifest = json.loads((root / "manifest.json").read_text())
lines = manifest["lines"]
META = ("id", "region", "name", "nameRoma", "operator", "rank", "color", "colorDark",
        "minZoomMapLibre", "lodMinZoomMapLibre", "visibilityLengthKm", "dependsOn")
blobs = {r: (root / f"{r}.display.bin").read_bytes() for r in ("hk", "mo", "jp")}


def chunk_of(key):
    info = lines[key]
    c = info["chunk"]
    doc = json.loads(blobs[info["region"]][c["offset"]:c["offset"] + c["length"]])
    doc["stations"] = [
        {k: s[k] for k in ("id", "lineKey", "slot") if k in s} for s in doc["stations"]]
    return doc


selected = {"hk": [], "mo": [], "jp": []}
for key, info in lines.items():
    if info["region"] in ("hk", "mo") and info.get("chunk"):
        selected[info["region"]].append(key)

jp_info = {}
for key, info in lines.items():
    if info["region"] != "jp" or not info.get("chunk"):
        continue
    flags = set()
    for f in chunk_of(key)["lines"]:
        if f.get("follows"):
            flags.add("follows")
        if f.get("familyWindows"):
            flags.add("family")
        if f.get("joinPrevious") is False:
            flags.add("nojoin")
        if f.get("lane"):
            flags.add("lane")
        if f.get("continuous") is not True:
            flags.add("noncont")
    b = info.get("bounds") or {}
    tokyo = bool(b) and 139.55 <= b["minLon"] and b["maxLon"] <= 140.1 \
        and 35.5 <= b["minLat"] and b["maxLat"] <= 35.85
    jp_info[key] = (info["chunk"]["length"], flags, tokyo)

by_id = {info["id"]: key for key, info in lines.items()}


def closure(key):
    seen = {key}
    frontier = [key]
    while frontier:
        current = frontier.pop()
        for dep in lines[current].get("dependsOn") or []:
            dep_key = by_id.get(dep)
            if dep_key and dep_key not in seen and lines[dep_key].get("chunk"):
                seen.add(dep_key)
                frontier.append(dep_key)
    return seen


def weight(keys):
    return sum(lines[k]["chunk"]["length"] for k in keys)


# A candidate is taken with its whole dependsOn closure, and only while the closure stays small:
# the fixture is committed, so a long trunk (Sanin, Nippo) cannot ride in as someone's canonical.
chosen = set()
budget = 330000
for flag, limit in (("follows", 6), ("family", 6), ("nojoin", 3), ("lane", 2), ("noncont", 2)):
    taken = 0
    for key, (size, flags, _) in sorted(jp_info.items(), key=lambda kv: (kv[1][0], kv[0])):
        if taken >= limit:
            break
        if flag not in flags or key in chosen:
            continue
        group = closure(key)
        if weight(chosen | group) > budget or weight(group) > 120000:
            continue
        chosen |= group
        taken += 1
tokyo_small = sorted((kv for kv in jp_info.items() if kv[1][2] and kv[1][0] < 25000),
                     key=lambda kv: (kv[1][0], kv[0]))
for key, _ in tokyo_small:
    if len([k for k in chosen if jp_info[k][2]]) >= 24:
        break
    group = closure(key)
    if weight(chosen | group) <= budget + 250000:
        chosen |= group
selected["jp"] = sorted(chosen)



def synthetic():
    """Two hand-made jp chains covering what shipped data does not: withheld spans, a landlord and
    a tenant family window in one group, and a follow onto a second chain."""
    import math

    def path(offset):
        points = []
        for i in range(41):
            t = i / 40
            points.append([139.700 + 0.12 * t, 35.600 + offset + 0.02 * math.sin(t * 9) + 0.03 * t])
        return points

    def metres(points):
        total = 0.0
        for a, b in zip(points, points[1:]):
            lat = (a[1] + b[1]) / 2 * math.pi / 180
            total += math.hypot((b[0] - a[0]) * 111320 * math.cos(lat), (b[1] - a[1]) * 111320)
        return total

    def chunk(key, points, extra):
        parts = [points[i:i + 11] for i in range(0, 40, 10)]
        total = metres(points)
        fragment = {"lineKey": key, "parts": parts, "continuous": True, "chain": 0,
                    "laneRows": [[0, total, 0]], "totalMetres": total}
        for name, rows in extra.items():
            fragment[name] = [[v * total if isinstance(v, float) and v < 1 and name != "follows"
                               else v for v in row] for row in rows] if name != "follows" else rows
        return {"format": "synthetic", "region": "jp", "lines": [fragment], "stations": [
            {"id": key + ":a", "lineKey": key, "slot": [0, 0]},
            {"id": key + ":b", "lineKey": key, "slot": [0, 20]},
            {"id": key + ":c", "lineKey": key, "slot": [0, 40]}]}

    canon = path(0.0)
    tenant = path(0.004)
    total_canon = metres(canon)
    total_tenant = metres(tenant)
    entries = []
    base_meta = {"region": "jp", "nameRoma": None, "operator": "synthetic", "rank": 1,
                 "color": "#aa3300", "colorDark": "#ff6633", "minZoomMapLibre": 7,
                 "lodMinZoomMapLibre": 7, "visibilityLengthKm": 12.0, "dependsOn": []}
    extra_canon = {"familyWindows": [[0.5, 0.7, 0, "syn:family"]]}
    canon_chunk = chunk("jp|syn-canon", canon, extra_canon)
    canon_chunk["lines"][0]["familyWindows"] = [[0.5 * total_canon, 0.7 * total_canon, 0, "syn:family"]]
    entries.append({"lineKey": "jp|syn-canon",
                    "meta": dict(base_meta, id="syn-canon", name="Synthetic canon", color="#aa3300"),
                    "chunk": canon_chunk})
    tenant_chunk = chunk("jp|syn-tenant", tenant, {})
    fragment = tenant_chunk["lines"][0]
    fragment["withheld"] = [[0.30 * total_tenant, 0.40 * total_tenant],
                            [0.55 * total_tenant, 0.65 * total_tenant]]
    fragment["familyWindows"] = [[0.10 * total_tenant, 0.20 * total_tenant, 1, "syn:family"],
                                 [0.50 * total_tenant, 0.70 * total_tenant, 1, "syn:family"]]
    fragment["follows"] = [[0.45 * total_tenant, 0.75 * total_tenant, "jp|syn-canon", 0,
                            0.45 * total_canon, 0.75 * total_canon]]
    entries.append({"lineKey": "jp|syn-tenant",
                    "meta": dict(base_meta, id="syn-tenant", name="Synthetic tenant", color="#0033aa"),
                    "chunk": tenant_chunk})

    # One railway cut into three chains that meet at shared vertices: chain 1 is a reviewed branch
    # boundary (joinPrevious false), chain 2 continues chain 1 (joinPrevious true).
    route = []
    for i in range(61):
        t = i / 60
        route.append([139.800 + 0.10 * t, 35.700 + 0.015 * math.sin(t * 14) - 0.02 * t])
    fragments = []
    stations = []
    for chain, (lo, hi) in enumerate(((0, 20), (20, 40), (40, 60))):
        points = route[lo:hi + 1]
        total = metres(points)
        fragments.append({
            "lineKey": "jp|syn-branch", "parts": [points[:11], points[10:]], "continuous": True,
            "chain": chain, "joinPrevious": chain != 1, "laneRows": [[0, total, 0]],
            "totalMetres": total})
        stations.append({"id": "syn-branch:%d" % chain, "lineKey": "jp|syn-branch", "slot": [chain, 10]})
    entries.append({"lineKey": "jp|syn-branch",
                    "meta": dict(base_meta, id="syn-branch", name="Synthetic branch", color="#33aa00"),
                    "chunk": {"format": "synthetic", "region": "jp", "lines": fragments, "stations": stations}})
    return entries


result = {"format": "jtm-stroke-network-fixture-1", "regions": {}}
for region, keys in selected.items():
    families = {}
    for record in manifest["regions"]:
        if record["region"] == region:
            families.update(record.get("families") or {})
    entries = []
    for key in sorted(keys):
        doc = chunk_of(key)
        entries.append({"lineKey": key,
                        "meta": {k: lines[key][k] for k in META if k in lines[key]},
                        "chunk": doc})
    if region == "jp":
        families["syn:family"] = {"color": "#112233", "colorDark": "#445566"}
        entries.extend(synthetic())
    result["regions"][region] = {"families": families, "lines": entries}
out.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
print({r: len(v["lines"]) for r, v in result["regions"].items()}, out.stat().st_size)
