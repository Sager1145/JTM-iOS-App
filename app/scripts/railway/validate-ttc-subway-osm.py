#!/usr/bin/env python3
"""Measure Toronto's subway geometries against the City's topographic survey.

    python3 scripts/railway/validate-ttc-subway-osm.py \
        --source-dir /path/to/na-rail

Three statements of where TTC Line 1 and Line 2 run are compared here:

* the City of Toronto subway route layer, which is byte-for-byte the TTC's
  own GTFS shape (`official-networks/ttc-subway-{1,2}.geojson`);
* the OpenStreetMap route relations the registry accepts for the two lines
  (`osm-routes/ttc-subway-relations.json`);
* the City's topographic mapping of subway track, `COTGEO_TOPO_RAILWAY`
  subtype 2005 (`official-raw/toronto-topo-railway-subway.geojson`).

The survey is the arbiter and it is a partial one: a topographer maps the
track that can be seen, so it covers the open-cut and surface sections and
nothing in a tunnel. The question this script answers is therefore not "is
the OSM relation right everywhere" -- nobody has published the evidence for
that -- but "where the City's own survey can see the railway, which of the
two candidate alignments does it agree with". The registry's
`osmRelationEvidenceByRouteId` entries for the TTC quote the answer, and a
reviewer who doubts them re-runs this.

The measurement runs from the survey towards the candidates, not the other
way round. Every surveyed vertex is real track, so asking "how far is the
nearest candidate from this vertex" has no edge effect; asking the reverse
question of a candidate vertex that sits in a tunnel mouth 140 m past the
last surveyed record would score a correct alignment as a 140 m error. Only
the surveyed records that run ALONG either candidate are asked -- most of a
record's vertices inside a corridor drawn round both -- so the survey's yard
tracks at Wilson, Davisville and Greenwood, which sit beside the main line
without following it, are not counted against either candidate, and a record
that follows one candidate is asked about both.

Exit status is non-zero when the survey no longer prefers the relation, so
that a re-cut route layer or a damaged relation is noticed at rebuild time
rather than shipped on stale evidence.
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
import na_geo as geo                                     # noqa: E402

#: Which relation the registry accepts for which route, and the two points
#: the original fail-closed review named. The routes are keyed the way the
#: registry keys them.
ROUTES = {
    '1': {'relation': 102388, 'name': 'Line 1 Yonge-University',
          'flag': [-79.465486, 43.754055]},
    '2': {'relation': 102386, 'name': 'Line 2 Bloor-Danforth',
          'flag': [-79.529452, 43.643698]},
}
#: A surveyed record is asked about the two candidates only when it runs
#: along one of them: this share of its vertices inside this corridor round
#: either candidate. The corridor is wide enough to admit a record beside a
#: candidate that is itself tens of metres off the track, and the share keeps
#: out the yard tracks that merely touch the corridor at one end.
CORRIDOR_M = 30.0
CORRIDOR_SHARE = 0.8
#: What "agrees with the survey" means for one vertex: inside the width of a
#: double-track subway alignment.
AGREE_M = 10.0
#: The survey prefers the relation when the relation's median offset is below
#: this and the route layer's median is above the relation's.
ACCEPT_MEDIAN_M = 5.0


class Reference:
    """Nearest-segment distance to a set of polylines, gridded for speed."""

    def __init__(self, lines, cell=0.005):
        self.cell = cell
        self.cells = {}
        for line in lines:
            for i in range(len(line) - 1):
                a, b = line[i], line[i + 1]
                for cx in range(int(min(a[0], b[0]) / cell) - 1,
                                int(max(a[0], b[0]) / cell) + 2):
                    for cy in range(int(min(a[1], b[1]) / cell) - 1,
                                    int(max(a[1], b[1]) / cell) + 2):
                        self.cells.setdefault((cx, cy), []).append([a, b])

    def distance(self, point):
        best = float('inf')
        cx, cy = int(point[0] / self.cell), int(point[1] / self.cell)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for segment in self.cells.get((cx + dx, cy + dy), ()):
                    d = geo.project_to_line(point, segment)[0]
                    if d < best:
                        best = d
        return best


def geojson_lines(path):
    with open(path, encoding='utf-8') as source:
        payload = json.load(source)
    out = []
    for feature in payload.get('features') or ():
        geometry = feature.get('geometry') or {}
        if geometry.get('type') == 'LineString':
            out.append([list(p[:2]) for p in geometry['coordinates']])
        elif geometry.get('type') == 'MultiLineString':
            out.extend([list(p[:2]) for p in part]
                       for part in geometry['coordinates'])
    return out


def relation_shapes(path):
    """The chained way geometry of every route relation in one extract."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        'na_package_builder',
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     'build-north-america-rail-package.py'))
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    return builder.load_osm_relation_shapes(os.path.dirname(path))


def summary(values):
    if not values:
        return {'n': 0}
    ordered = sorted(values)
    return {
        'n': len(ordered),
        'median': statistics.median(ordered),
        'p90': ordered[min(len(ordered) - 1, int(len(ordered) * 0.9))],
        'max': ordered[-1],
        'within': sum(1 for v in ordered if v <= AGREE_M) / len(ordered),
    }


def fmt(row):
    if not row['n']:
        return 'no vertex in reach of the survey'
    return (f"n={row['n']} median {row['median']:.1f} m, p90 {row['p90']:.1f} m, "
            f"max {row['max']:.1f} m, {row['within'] * 100:.0f}% within "
            f"{AGREE_M:.0f} m")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source-dir', required=True)
    ap.add_argument('--json', default=None,
                    help='write the measurements here as well')
    args = ap.parse_args()

    survey_path = os.path.join(args.source_dir, 'official-raw',
                               'toronto-topo-railway-subway.geojson')
    relations_path = os.path.join(args.source_dir, 'osm-routes',
                                  'ttc-subway-relations.json')
    survey_lines = geojson_lines(survey_path)
    survey = Reference(survey_lines)
    shapes = relation_shapes(relations_path)
    print(f'survey: {len(survey_lines)} subway-track records, '
          f'{sum(len(l) for l in survey_lines)} vertices (open sections only)')

    results = {}
    failures = []
    for route_id, spec in ROUTES.items():
        relation = shapes.get(spec['relation'])
        if not relation:
            failures.append(f"{route_id}: relation {spec['relation']} is not "
                            f"in {relations_path}")
            continue
        city_path = os.path.join(args.source_dir, 'official-networks',
                                 f'ttc-subway-{route_id}.geojson')
        city = geojson_lines(city_path)
        city_points = [p for line in city for p in line]
        osm_ref = Reference([relation])
        city_ref = Reference(city)

        # The surveyed records this line's two candidates could be answering
        # for: the ones that run along either of them. Their vertices are the
        # sample.
        seen = []
        records = 0
        for record in survey_lines:
            inside = sum(1 for p in record
                         if min(osm_ref.distance(p), city_ref.distance(p))
                         <= CORRIDOR_M)
            if inside >= CORRIDOR_SHARE * len(record):
                seen.extend(record)
                records += 1
        osm_row = summary([osm_ref.distance(p) for p in seen])
        city_row = summary([city_ref.distance(p) for p in seen])
        between = summary([city_ref.distance(p) for p in relation])
        flag_to_osm = osm_ref.distance(spec['flag'])
        flag_to_city = city_ref.distance(spec['flag'])

        print(f"\n{spec['name']} (route {route_id}, OSM relation "
              f"{spec['relation']}, {geo.line_length(relation) / 1000:.1f} km, "
              f"{len(relation)} vertices; City route layer "
              f"{sum(geo.line_length(l) for l in city) / 1000:.1f} km, "
              f"{len(city_points)} vertices)")
        print(f'  {records} surveyed records run along a candidate')
        print(f'  surveyed track -> OSM relation: {fmt(osm_row)}')
        print(f'  surveyed track -> City route layer: {fmt(city_row)}')
        print(f'  OSM relation -> City route layer, whole line: {fmt(between)}')
        print(f"  reviewed point {spec['flag'][1]:.6f}, {spec['flag'][0]:.6f}: "
              f'{flag_to_osm:.1f} m from the relation, {flag_to_city:.1f} m '
              'from the City route layer')
        results[route_id] = {
            'relation': spec['relation'],
            'surveyedRecords': records,
            'surveyToRelation': osm_row, 'surveyToCity': city_row,
            'relationVsCity': between,
            'reviewedPointToRelationMeters': round(flag_to_osm, 1),
            'reviewedPointToCityMeters': round(flag_to_city, 1),
        }
        if not osm_row['n']:
            failures.append(f'{route_id}: the survey reaches neither candidate')
        elif osm_row['median'] > ACCEPT_MEDIAN_M:
            failures.append(f"{route_id}: relation median {osm_row['median']:.1f} m "
                            f'exceeds {ACCEPT_MEDIAN_M:.0f} m')
        elif city_row['median'] <= osm_row['median']:
            failures.append(f'{route_id}: the survey no longer prefers the '
                            'relation over the City route layer')

    if args.json:
        with open(args.json, 'w', encoding='utf-8') as output:
            json.dump(results, output, indent=1)
            output.write('\n')
    for failure in failures:
        print('FAIL ' + failure, file=sys.stderr)
    if failures:
        return 1
    print('\nthe survey prefers the OSM relations for both lines')
    return 0


if __name__ == '__main__':
    sys.exit(main())
