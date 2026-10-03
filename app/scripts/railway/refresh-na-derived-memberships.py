#!/usr/bin/env python3
"""Reconcile NA solver artifacts to compact packages, without deriving track.

Existing membership identities are retained. Missing identities are an error,
not an invitation to infer a station from its name. Only per-region files write.
"""
import argparse
import copy
import importlib.util
import json
import math
from collections import defaultdict
from pathlib import Path


HERE = Path(__file__).resolve().parent


def decode(line):
    previous = None
    result = []
    for km, continues, coordinates in line['segments']:
        points = copy.deepcopy(coordinates)
        if continues:
            if previous is None:
                raise ValueError('continuing first interval')
            points.insert(0, previous)
        if len(points) < 2:
            raise ValueError('empty interval')
        previous = points[-1]
        result.append(points)
    return result


def reconcile(package, stations, sections):
    available = defaultdict(list)
    for feature in stations['features']:
        p = feature['properties']
        point = p.get('display_point') or feature['geometry']['coordinates'][0]
        key = (p['operator'], p['line_name'], p['n02_group_code'], tuple(point))
        available[key].append(feature)
    section_properties = {}
    for feature in sections['features']:
        p = feature['properties']
        section_properties.setdefault((p['operator'], p['line_name']), p)
    new_stations, new_sections = [], []
    for line in package['lines']:
        intervals = decode(line)
        key = (line['operator'], line['name'])
        properties = section_properties.get(key)
        if properties is None:
            raise ValueError(f'no section identity for {line["id"]}')
        for points in intervals:
            new_sections.append({'type': 'Feature', 'properties': copy.deepcopy(properties),
                                 'geometry': {'type': 'LineString', 'coordinates': points}})
        for i, row in enumerate(line['stations']):
            point = row[2:4]
            identity = (*key, row[0], tuple(point))
            if not available[identity]:
                raise ValueError(f'missing membership {line["id"]}: {row[0]} at {point}')
            feature = copy.deepcopy(available[identity].pop(0))
            feature['properties']['station_name'] = row[1]
            feature['properties']['display_point'] = point
            if i < len(intervals):
                neighbour = intervals[i][1]
            elif intervals:
                neighbour = intervals[-1][-2]
            else:
                raise ValueError(f'unrepresented identity-only line {line["id"]}')
            # One metre of actual surveyed track around the canonical anchor.
            # A sparse long-haul edge is not the footprint of its terminal.
            lon1, lat1, lon2, lat2 = map(math.radians, (*point, *neighbour))
            h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
            distance = 2 * 6371008.8 * math.asin(min(1, math.sqrt(h)))
            fraction = min(1, 1 / distance) if distance else 0
            stub = [round(point[j] + fraction * (neighbour[j] - point[j]), 6) for j in (0, 1)]
            feature['geometry']['coordinates'] = [point, stub]
            new_stations.append(feature)
    return ({'type': 'FeatureCollection', 'features': new_stations},
            {'type': 'FeatureCollection', 'features': new_sections})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', type=Path, required=True)
    parser.add_argument('--region', choices=('us', 'ca'), action='append', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('na_membership_builder', HERE / 'build-north-america-rail-package.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    for region in args.region:
        root = args.app_root
        package = json.loads((root / 'public/rail' / f'{region}-2025.json').read_text())
        sp, ep, rp = [root / 'data' / f'{name}-{region}.json' for name in ('stations', 'rail-sections', 'station-readings')]
        old = json.loads(sp.read_text())
        stations, sections = reconcile(package, old, json.loads(ep.read_text()))
        readings = json.loads(rp.read_text())
        fresh = builder.readings_for(stations['features'], region)
        for key in ('byCode', 'byName', 'stats'):
            readings[key] = fresh[key]
        for path, value in ((sp, stations), (ep, sections), (rp, readings)):
            builder.write_json(str(path), value)
        print(f'{region}: memberships {len(old["features"])} -> {len(stations["features"])}; sections {len(sections["features"])}')


if __name__ == '__main__':
    main()
