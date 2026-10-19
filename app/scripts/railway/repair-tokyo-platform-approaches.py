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
SHINAGAWA_REFERENCE = ROOT.parent / "docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/shinagawa/sources/passenger-pair-reference-20261011.json"
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
    # Restore the retained tunnel through Shimbashi and the independent
    # Yokosuka / Hinkaku platform family at Shinagawa (JR platforms 13–15).
    # Original stations/segments/km remain physical inputs.
    tunnel = lines[JR+"総武線-3"]
    def decode(line):
        paths, previous = [], None
        for index, row in enumerate(line["segments"]):
            points = ([previous] if row[1] else []) + [list(p) for p in row[2]]
            points[0] = line["stations"][index][2:4]
            points[-1] = line["stations"][(index+1) % len(line["stations"])][2:4]
            previous = points[-1]
            paths.append(points)
        return paths
    # The terminal N02 station centroid adds an 8.6 m sideways barb after
    # the retained Tohoku platform support. End display on that existing
    # support; do not merge the independently drawn Shinkansen families.
    tohoku = lines[JR+"東北新幹線"]
    tohoku_terminal = decode(tohoku)[21]
    assert tohoku["stations"][-1][0] == "003766"
    assert tohoku_terminal[-1] == [139.767579, 35.68113]
    assert tohoku_terminal[-2] == [139.7676701, 35.681109], "Tokyo terminal support changed; re-review before applying"
    tohoku.setdefault("displayStationCoordinates", {})["003766"] = tohoku_terminal[-2][:]
    tohoku.setdefault("displayIntervalCoordinates", {})["21"] = tohoku_terminal[:-1]
    tunnel_paths = decode(tunnel)
    # N02's Shimbashi point is 1.5 m east of the retained OSM tunnel vertex.
    # Use that already-surveyed seam for display instead of a two-vertex barb.
    shimbashi = tunnel_paths[1][1]
    assert km(shimbashi, tunnel_paths[1][0]) < 0.002
    anchors = dict(tunnel.get("displayStationCoordinates", {}))
    anchors["003872"] = shimbashi[:]
    anchors.pop("004095", None)
    overrides = tunnel.setdefault("displayIntervalCoordinates", {})
    overrides["0"] = tunnel_paths[0][:-1]
    assert overrides["0"][-1] == shimbashi
    overrides["1"] = [p[:] for p in tunnel_paths[1][1:]]
    # Start from physical inputs on every replay; apply the independently
    # identified normal passenger pair below before inserting the reviewed Osaki southern shared-tail points.
    overrides["2"] = [p[:] for p in tunnel_paths[2]]
    reference = json.loads(SHINAGAWA_REFERENCE.read_text())
    assert reference["status"] == "bounded-display-corridor-ready"
    assert reference["lineId"] == tunnel["id"]
    evidence_ways = {row["id"]: row for row in json.loads(
        SHINAGAWA_REFERENCE.with_name("osm-bounded-rail-ways.json").read_text())["elements"]}
    main_ways = reference["identity"]["upMainWays"] + reference["identity"]["downMainWays"]
    assert 853189601 not in main_ways, "Station siding cannot define the passenger corridor"
    for way_id in main_ways:
        tags = evidence_ways[way_id]["tags"]
        assert tags.get("usage") == "main" and tags.get("operator") == "東日本旅客鉄道"
        assert tags.get("railway:traffic_mode") == "passenger" and tags.get("gauge") == "1067"
        assert tags.get("service") != "siding"
    boundaries = reference["boundaries"]
    assert tunnel["stations"][2][2:4] == boundaries["physicalStation"] == [139.739427, 35.629035]
    north_support = boundaries["northRetainedSource"]
    south_support = boundaries["southRetainedSource"]
    assert north_support == [139.7396393, 35.6297092]
    assert south_support == [139.73205, 35.61655]
    north_transition = reference["displayPaths"]["northTransition"]
    south_centre = reference["displayPaths"]["south"]
    centre = boundaries["displayStation"]
    assert north_transition[0] == north_support and north_transition[-1] == centre
    assert south_centre[0] == centre and south_centre[-1] == south_support
    # This is a representative display centre, not a new platform survey or
    # crossover topology. Both exact source bounds remain; all physical inputs
    # and every source support outside the reviewed window are unchanged.
    north_index = overrides["1"].index(north_support)
    south_index = overrides["2"].index(south_support)
    overrides["1"] = overrides["1"][:north_index] + north_transition
    overrides["2"] = south_centre[:-1] + overrides["2"][south_index:]
    anchors["004095"] = centre[:]
    tunnel["displayStationCoordinates"] = anchors
    tunnel.setdefault("stationCircleOwnerByCode", {}).pop("003872", None)
    tunnel.setdefault("stationLaneByCode", {})["003872"] = 0
    tunnel.setdefault("stationCircleOwnerByCode", {}).pop("004095", None)
    tunnel.setdefault("stationLaneByCode", {})["004095"] = 0
    package["version"] = "2025.5.2"
    package["geometrySource"].setdefault("manualOverrides", {})["tokyo-platform-approaches"] = {
        "reviewedAt": "2026-09-30", "crs": "WGS84",
        "script": "app/scripts/railway/repair-tokyo-platform-approaches.py",
        "source": "existing N02-25 / registered 2026-08-18 OSM Tokyo interval",
        "transformation": "Remove two reversed seam vertices in Shinagawa-to-Tokyo; retain both station anchors and all following survey vertices",
        "stationDisplay": "Four main JR Tokyo platform families; duplicate conventional/Sobu members share circle and endpoint lane",
    }
    package["geometrySource"]["manualOverrides"]["tokyo-conventional-display-corridor"] = {
        "reviewedAt": "2026-10-11", "crs": "WGS84",
        "script": "app/scripts/railway/repair-tokyo-platform-approaches.py",
        "policy": "Independently routed passenger platform families retain separate circles and approaches",
        "source": "Existing N02 / registered OSM Tokyo tunnel; JR East Shinagawa platform map, July 2026, platforms 13–15 distinct from 6–12",
        "transformation": "Retain the Shimbashi surveyed display seam; remove the Shinagawa conventional-family alias and restore both retained Sobu source approaches; preserve physical intervals and the outbound eastern/western display fork projections",
        "stationDisplay": "Independent Sobu platform family; bounded normal-passenger-pair override supplies its representative display centre",
        "stationLanePinMeters": 300,
    }
    package["geometrySource"]["manualOverrides"]["shinagawa-normal-passenger-pair"] = {
        "reviewedAt": "2026-10-11", "crs": "WGS84",
        "script": "app/scripts/railway/repair-tokyo-platform-approaches.py",
        "reference": str(SHINAGAWA_REFERENCE.relative_to(ROOT.parent)),
        "source": "Identified OSM JR East main passenger up/down pair; GSI large-scale railway coordinates, 2026-07-01 snapshot; GSI2019 ortho; dated track diagram v7 and JR East July2026 platform family13–15",
        "northRetainedSource": north_support, "southRetainedSource": south_support,
        "displayStation": centre, "physicalStation": boundaries["physicalStation"],
        "transformation": "Representative centre of two identified normal passenger rails through Shinagawa and actual western curve; north transition remains inside that pair; exact retained source prefix/tail and Osaki southern shared-tail supports preserved",
        "limits": reference["limits"],
        "stationLanePinMeters": 300,
    }
    package["geometrySource"]["manualOverrides"]["tokyo-tohoku-terminal-display"] = {
        "reviewedAt": "2026-10-11", "crs": "WGS84",
        "script": "app/scripts/railway/repair-tokyo-platform-approaches.py",
        "source": "Existing registered survey support; native Tokyo overlay/basemap terminal comparison",
        "transformation": "End the displayed Tohoku Shinkansen terminal at its final retained platform support; remove only the sideways connection to the physical station centroid; retain all non-anchor survey supports and physical stations/segments/km",
        "stationDisplay": "Independent Tohoku Shinkansen platform circle on retained support; no Tokaido Shinkansen merge or added lane pin",
        "derivedDisplay": "Refresh the terminal ruler/end lane cap; remove only the excluded jp-tokyo Tohoku overlap diagnostic sampled inside the old centroid-warped terminal approach, since its start has no exact retained support for remapping",
    }
    # The new branches must be integrated after restoring the outbound trunk.
    # The branch owner preserves physical forks but retires capped display
    # leads, binding the local station stem and southern tail to their owners.
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
        print("Restored independent Shinagawa passenger approaches and independent Osaki passenger approaches")


if __name__ == "__main__":
    main()
