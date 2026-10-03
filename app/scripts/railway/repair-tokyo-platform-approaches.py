#!/usr/bin/env python3
"""Replay the bounded Tokyo display policy and Shinagawa station-seam repair.

The original Japan builder is in the older Web repository. This override is
kept here so rebuilding or replacing its published compact package is repeatable.
No station IDs, station order, or unrelated intervals change.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "public/rail/jp-2025.json"
JR = "jp-東日本旅客鉄道-"
SHINKANSEN = "jp-東海旅客鉄道-東海道新幹線"
SPUR = [[139.7401467, 35.6296413], [139.7404284, 35.6293804]]
NEXT = [139.740806, 35.630912]


def km(a, b):
    lon1, lat1, lon2, lat2 = map(math.radians, (*a, *b))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 6371 * 2 * math.atan2(math.sqrt(h), math.sqrt(1-h))


def repair(package):
    lines = {line["id"]: line for line in package["lines"]}
    shinkansen = lines[SHINKANSEN]
    assert [s[1] for s in shinkansen["stations"][15:17]] == ["品川", "東京"]
    interval = shinkansen["segments"][15]
    assert interval[1] == 1
    if interval[2][:2] == SPUR:
        assert interval[2][2] == NEXT
        interval[2] = interval[2][2:]
        path = [shinkansen["stations"][15][2:4]] + interval[2]
        interval[0] = round(sum(km(a, b) for a, b in zip(path, path[1:])), 3)
    else:
        assert interval[2][0] == NEXT, "Shinagawa source changed; re-review before applying"
    # These are aliases of the same physical platform family at the main JR
    # complex. The separate Keiyo and Metro stops retain their own locations.
    for alias, owner in ((JR+"東北線-2", JR+"東海道線"), (JR+"総武線-3", JR+"総武線")):
        row = next(row for row in lines[alias]["stations"] if row[0] == "003766")
        landlord = next(row for row in lines[owner]["stations"] if row[0] == "003766")
        assert row[2:4] == landlord[2:4]
        lines[alias].setdefault("stationCircleOwnerByCode", {})["003766"] = owner
        lines[alias].setdefault("stationLaneByCode", {})["003766"] = 0
    # Restore the surveyed tunnel through Shimbashi. The current display policy
    # joins the conventional family at Shinagawa, not south of Yurakucho.
    # Original stations/segments/km remain physical inputs.
    surface, tunnel = lines[JR+"東海道線"], lines[JR+"総武線-3"]
    def decode(line):
        paths, previous = [], None
        for index, row in enumerate(line["segments"]):
            points = ([previous] if row[1] else []) + [list(p) for p in row[2]]
            points[0] = line["stations"][index][2:4]
            points[-1] = line["stations"][(index+1) % len(line["stations"])][2:4]
            previous = points[-1]
            paths.append(points)
        return paths
    surface_paths, tunnel_paths = decode(surface), decode(tunnel)
    # N02's Shimbashi point is 1.5 m east of the retained OSM tunnel vertex.
    # Use that already-surveyed seam for display instead of a two-vertex barb.
    shimbashi = tunnel_paths[1][1]
    assert km(shimbashi, tunnel_paths[1][0]) < 0.002
    anchors = {"003872": shimbashi[:],
               "004095": next(s[2:4] for s in surface["stations"] if s[0] == "004095")}
    # Transition along the reviewed station throat rather than dragging the
    # last tunnel vertex 130 m sideways onto the surface station centroid.
    incoming = [p[:] for p in tunnel_paths[1][1:]]
    remaining = [0.0] * len(incoming)
    for i in range(len(incoming)-2, -1, -1):
        remaining[i] = remaining[i+1] + 1000*km(incoming[i], incoming[i+1])
    shift = [anchors["004095"][i]-incoming[-1][i] for i in (0, 1)]
    for i, point in enumerate(incoming):
        t = max(0.0, 1.0-remaining[i]/350.0)
        weight = t*t*(3-2*t)
        incoming[i] = [point[j] + weight*shift[j] for j in (0, 1)]
    incoming[-1] = anchors["004095"]
    overrides = tunnel.setdefault("displayIntervalCoordinates", {})
    overrides["0"] = tunnel_paths[0][:-1]
    assert overrides["0"][-1] == shimbashi
    overrides["1"] = incoming
    # Keep the outbound approach on the old shared N02 trunk as well. This
    # preserves the eastern trunk fork and the later western branch fork.
    common = [139.73881, 35.62549]
    departure = surface_paths[6][:surface_paths[6].index(common)+1]
    departure += tunnel_paths[2][tunnel_paths[2].index(common)+1:]
    overrides["2"] = departure
    tunnel["displayStationCoordinates"] = anchors
    tunnel.setdefault("stationCircleOwnerByCode", {}).pop("003872", None)
    tunnel.setdefault("stationLaneByCode", {})["003872"] = 0
    for code in ("004095",):
        tunnel.setdefault("stationCircleOwnerByCode", {})[code] = surface["id"]
        tunnel.setdefault("stationLaneByCode", {}).pop(code, None)
        surface.setdefault("stationLaneByCode", {}).pop(code, None)
    package["version"] = "2025.5.2"
    package["geometrySource"].setdefault("manualOverrides", {})["tokyo-platform-approaches"] = {
        "reviewedAt": "2026-09-30", "crs": "WGS84",
        "script": "app/scripts/railway/repair-tokyo-platform-approaches.py",
        "source": "existing N02-25 / registered 2026-08-18 OSM Tokyo interval",
        "transformation": "Remove two reversed seam vertices in Shinagawa-to-Tokyo; retain both station anchors and all following survey vertices",
        "stationDisplay": "Four main JR Tokyo platform families; duplicate conventional/Sobu members share circle and endpoint lane",
    }
    package["geometrySource"]["manualOverrides"]["tokyo-conventional-display-corridor"] = {
        "reviewedAt": "2026-10-01", "crs": "WGS84",
        "script": "app/scripts/railway/repair-tokyo-platform-approaches.py",
        "policy": "User-requested schematic; not physical track topology",
        "source": "Existing N02 surface paths and registered OSM Tokyo tunnel",
        "transformation": "Restore the surveyed Tokyo/Shimbashi tunnel; alias only the Shinagawa throat to the conventional display family; preserve the outbound N02 eastern and western forks and physical intervals",
        "junction": anchors["004095"],
        "transitionMeters": 350,
        "transitionPolicy": "Smoothstep endpoint alias within the last 350 m of the retained tunnel; display only, source stations/intervals/km unchanged",
    }
    # The new branches must be integrated after restoring the outbound trunk.
    # Calling this replay command therefore cannot resurrect the old appended
    # parallel main or leave stale fork aliases from an earlier display policy.
    if JR+"大崎支線" in lines:
        path = Path(__file__).with_name('repair-tokyo-southern-branches.py')
        spec = importlib.util.spec_from_file_location('tokyo_southern', path)
        branches = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(branches)
        package = branches.integrate_legacy_display(
            branches.repair(package), json.loads(branches.EVIDENCE.read_text()))
    return package


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    before = PACKAGE.read_text()
    after = json.dumps(repair(json.loads(before)), ensure_ascii=False, separators=(",", ":"))
    # The published file is one compact JSON line, without a trailing newline.
    if args.check:
        if before.rstrip() != after:
            raise SystemExit("Tokyo platform override is not applied")
        print("Tokyo platform override is current")
    elif before.rstrip() != after:
        PACKAGE.write_text(after)
        print("Restored Tokyo tunnel, Shinagawa display join and legacy-compatible Osaki forks")


if __name__ == "__main__":
    main()
