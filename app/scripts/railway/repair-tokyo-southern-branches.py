#!/usr/bin/env python3
"""Replay independently sourced 大崎支線 candidates without touching package by default.

OSM supplies the retained track vertices, not official measured geometry. JRTT and
JR East establish the physical branch and its two existing passenger memberships.
Only --output writes, and callers own integration into the shared package.
"""
import argparse
import copy
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().with_name('tokyo-southern-branches-overrides.json')
BASE_ID = 'jp-東日本旅客鉄道-大崎支線'
PAIR_ID = BASE_ID + '-p1'
JR = 'jp-東日本旅客鉄道-'


def distance(a, b):
    lon1, lat1, lon2, lat2 = map(math.radians, (*a, *b))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 6371000 * 2 * math.atan2(math.sqrt(h), math.sqrt(1-h))


def length(points):
    return sum(distance(a, b) for a, b in zip(points, points[1:]))


def concatenate(evidence, way_ids):
    result = []
    for way_id in way_ids:
        way = evidence['ways'][str(way_id)]
        assert way['tags'].get('usage') == 'main', f'Non-running track {way_id}'
        assert way['tags'].get('railway') == 'rail'
        coordinates = copy.deepcopy(way['coordinates'])
        assert len(coordinates) >= 2
        if result:
            assert result[-1] == coordinates[0], f'Unsurveyed gap before way {way_id}'
            result.extend(coordinates[1:])
        else:
            result.extend(coordinates)
    return result


def project(point, coordinates):
    scale_x = 111320 * math.cos(math.radians(point[1]))
    scale_y = 111320
    best = None
    measure = 0
    for index, (a, b) in enumerate(zip(coordinates, coordinates[1:])):
        vx, vy = (b[0]-a[0])*scale_x, (b[1]-a[1])*scale_y
        wx, wy = (point[0]-a[0])*scale_x, (point[1]-a[1])*scale_y
        denominator = vx*vx + vy*vy
        t = max(0, min(1, (wx*vx+wy*vy)/denominator)) if denominator else 0
        anchor = [a[0]+t*(b[0]-a[0]), a[1]+t*(b[1]-a[1])]
        candidate = {'point': anchor, 'index': index, 't': t,
                     'measure': measure+t*distance(a, b), 'distance': distance(point, anchor)}
        if best is None or candidate['distance'] < best['distance']:
            best = candidate
        measure += distance(a, b)
    assert best is not None
    return best


def slice_between(coordinates, start, end):
    assert start['measure'] < end['measure'], 'Station order reversed'
    return [start['point']] + coordinates[start['index']+1:end['index']+1] + [end['point']]


def reviewed_tracks(evidence):
    """Return north-to-south chains with true source forks and station projections."""
    tracks = []
    for direction in ['southbound', 'northbound']:
        path = evidence['paths'][direction]
        ids = path['branch'] + path['continuation'] if direction == 'southbound' else path['continuation'] + path['branch']
        running = concatenate(evidence, ids)
        # Each branch way itself declares its physical traversal direction.
        assert all(evidence['ways'][str(i)]['tags'].get('oneway') == 'yes' for i in path['branch'])
        if direction == 'northbound':
            running.reverse()
        osaki = project(evidence['stationReferenceCoordinates']['004135'], running)
        nishi_oi = project(evidence['stationReferenceCoordinates']['004235'], running)
        assert osaki['distance'] < 90 and nishi_oi['distance'] < 15
        interval = slice_between(running, osaki, nishi_oi)
        lead_in = running[:osaki['index']+1] + [osaki['point']]
        south_junction = evidence['ways'][str(path['branch'][-1 if direction == 'southbound' else 0])]['coordinates'][-1 if direction == 'southbound' else 0]
        assert south_junction in interval, 'Lost surveyed southern junction'
        assert 2400 < length(interval) < 3300, 'Station interval is not the local 大崎支線 path'
        assert all(distance(a, b) < 500 for a, b in zip(running, running[1:])), 'Unsourced long connector'
        assert all(139.72 < p[0] < 139.733 and 35.601 < p[1] < 35.623 for p in running)
        tracks.append({'direction': direction, 'sourceWayIDs': ids, 'fullGeometry': running,
                       'intervalGeometry': interval, 'northLeadInGeometry': lead_in,
                       'northJunction': running[0], 'southJunction': south_junction,
                       'stationProjection': {'004135': osaki, '004235': nishi_oi},
                       'intervalMeters': length(interval)})
    return tracks


def reviewed_freight_main(evidence):
    """Station-free main track supporting both forks; no passenger-edge inference."""
    definition = evidence['freightMain']
    reversed_ids = set(definition['reverseWayIDs'])
    result = []
    for way_id in definition['sourceWayIDs']:
        way = evidence['ways'][str(way_id)]
        assert way['tags'].get('usage') == 'main'
        assert way['tags'].get('railway') == 'rail'
        points = copy.deepcopy(way['coordinates'])
        if way_id in reversed_ids:
            points.reverse()
        if result:
            assert result[-1] == points[0], f'Unsurveyed freight-main gap before way {way_id}'
            result.extend(points[1:])
        else:
            result.extend(points)
    for track in reviewed_tracks(evidence):
        assert track['northJunction'] in result, 'North branch fork has no surveyed main track'
    assert 2500 < length(result) < 4000
    return result


def display_freight_main(package, evidence):
    """Bounded display aliases only; the 99 source vertices remain in evidence."""
    source = reviewed_freight_main(evidence)
    megurogawa = [139.7328, 35.61677]
    gotanda = [139.72321, 35.62672]
    line = next(row for row in package['lines'] if row['id'] == JR+'山手線')
    source_vertices = [point for row in line['segments'] for point in row[2]]
    assert megurogawa in source_vertices and gotanda in source_vertices
    start = project(megurogawa, source)
    assert start['distance'] < 4
    assert distance(source[-1], gotanda) < 14
    shown = [megurogawa] + source[start['index']+1:]
    shown[-1] = gotanda
    for track in reviewed_tracks(evidence):
        assert track['northJunction'] in shown
    policy = {
        'kind': 'explicit-display-only-representative-corridor',
        'sourceEvidence': 'app/scripts/railway/tokyo-southern-branches-overrides.json:freightMain',
        'sourceVertexCount': len(source),
        'sourceWayIDs': evidence['freightMain']['sourceWayIDs'],
        'displayStart': megurogawa, 'projectedSourceStart': start['point'],
        'startAliasMeters': start['distance'],
        'displayEnd': gotanda, 'sourceEnd': source[-1],
        'endAliasMeters': distance(source[-1], gotanda),
        'note': 'Only the uncovered freight main north of the displayed Megurogawa fork is shown. Both endpoints alias existing N02 Yamanote stroke vertices; source interval geometry, source graph and physical junctions are unchanged. These aliases never imply physical interchange with parallel Yamanote electric tracks.'}
    return shown, policy


def intervals(line):
    result, previous = [], None
    for row in line['segments']:
        points = ([previous] if row[1] else []) + copy.deepcopy(row[2])
        result.append(points)
        previous = points[-1]
    return result


def insert_projections(points, projections):
    """Insert reviewed fork aliases without changing the old N02 polyline."""
    result = []
    for i, point in enumerate(points):
        result.append(point[:])
        for anchor in sorted((p for p in projections if p['index'] == i), key=lambda p: p['t']):
            if anchor['point'] != result[-1] and anchor['point'] != points[i+1]:
                result.append(anchor['point'][:])
    return result


def alias_approach(points, target, start=False, meters=200):
    """Bounded display-only endpoint alias; never rewrite source geometry."""
    path = copy.deepcopy(points if start else list(reversed(points)))
    shift = [target[i]-path[0][i] for i in (0, 1)]
    measure = 0.0
    original = copy.deepcopy(path)
    for i, point in enumerate(original):
        if i:
            measure += distance(original[i-1], point)
        t = max(0.0, 1-measure/meters)
        weight = t*t*(3-2*t)
        path[i] = [point[j]+weight*shift[j] for j in (0, 1)]
    path[0] = target[:]
    return path if start else list(reversed(path))


def integrate_legacy_display(package, evidence):
    """Seat the supplement on the existing N02 representative, not a new main.

    Physical forks/intervals remain in southernBranchTopology and segments.
    Every displayed shared tail copies the old N02 vertices exactly. The old
    station table and paired-alignment fields remain the consumer contract.
    """
    lines = {line['id']: line for line in package['lines']}
    yamanote, sobu = lines[JR+'山手線'], lines[JR+'総武線-3']
    north = intervals(yamanote)[1]
    south = copy.deepcopy(sobu.get('displayIntervalCoordinates', {}).get('2', intervals(sobu)[2]))
    tracks = reviewed_tracks(evidence)
    north_aliases = [project(track['northJunction'], north) for track in tracks]
    south_aliases = [project(track['southJunction'], south) for track in tracks]
    assert all(anchor['distance'] < 15 for anchor in north_aliases+south_aliases)
    # Projections subdivide existing edges, so the representative shape stays
    # exactly on its old corridor even at the two newly explicit junctions.
    north_display = insert_projections(north, north_aliases)
    south_display = insert_projections(south, south_aliases)
    yamanote.setdefault('displayIntervalCoordinates', {})['1'] = north_display
    sobu.setdefault('displayIntervalCoordinates', {})['2'] = south_display
    osaki, nishi = north[0], south[-1]
    for track, north_alias, south_alias in zip(tracks, north_aliases, south_aliases):
        row = lines[BASE_ID if track['direction'] == 'southbound' else PAIR_ID]
        fork_index = track['intervalGeometry'].index(track['southJunction'])
        own = alias_approach(track['intervalGeometry'][:fork_index+1], osaki, start=True)
        own = alias_approach(own, south_alias['point'])
        own += south_display[south_display.index(south_alias['point'])+1:]
        row['displayStationCoordinates'] = {'004135': osaki[:], '004235': nishi[:]}
        row['displayIntervalCoordinates'] = {'0': own}
        row['stationCircleOwnerByCode'] = {'004135': yamanote['id'], '004235': sobu['id']}
        # Copy the old main backwards from the reviewed north fork to Osaki.
        # Both lines now paint the SAME coordinates, not two adjacent surveys.
        row['displayBranchLeadIns'] = [list(reversed(north_display[:north_display.index(north_alias['point'])+1]))]
        row.pop('displayFreightMainPolicy', None)
        row['southernBranchTopology']['displayAliases'] = {
            'northJunction': north_alias['point'], 'southJunction': south_alias['point'],
            'northOffsetMeters': north_alias['distance'], 'southOffsetMeters': south_alias['distance'],
            'policy': 'Explicit representative display aliases onto existing N02; not physical junctions or source-graph edges',
            'approachAliasMeters': 200,
        }
    lines[BASE_ID]['alignmentPairs'] = [{'with': PAIR_ID, 'from': '大崎', 'to': '西大井',
        'direction': 'unassigned', 'source': evidence['primaryTopologyEvidence'][0]['url']}]
    package['geometrySource']['manualOverrides']['tokyo-southern-branches']['displayIntegration'] = {
        'format': 'existing compact-v1 station/interval display overrides and reciprocal alignmentPairs',
        'stationFormat': 'ADR 0010 properties plus existing optional display_line_id; provenance in feature foreign member and evidence registry',
        'transformation': 'Project only display fork aliases onto old N02 within 15 m, preserve exact shared tails and station anchors; remove duplicate appended freight main',
    }
    return package


def repair(package, evidence=None):
    """Return a copy with two directional compact rows; never mutate the input."""
    evidence = evidence or json.loads(EVIDENCE.read_text())
    result = copy.deepcopy(package)
    old_lines = {row['id']: row for row in result['lines']}
    source_osaki = next(s for s in old_lines[JR+'山手線']['stations'] if s[0] == '004135')
    source_nishi = next(s for s in old_lines[JR+'総武線-3']['stations'] if s[0] == '004235')
    main_display, main_display_policy = display_freight_main(package, evidence)
    result['lines'] = [row for row in result['lines'] if row['id'] not in [BASE_ID, PAIR_ID]]
    for track in reviewed_tracks(evidence):
        forward = track['direction'] == 'southbound'
        stations = []
        for source in [source_osaki, source_nishi]:
            station = copy.deepcopy(source)
            station[2:4] = track['stationProjection'][station[0]]['point']
            stations.append(station)
        row = {key: copy.deepcopy(value) for key, value in old_lines[JR+'山手線'].items()
               if key in ['operator', 'rank', 'color', 'colorDark', 'kind', 'colorPolicy',
                          'labelPolicy', 'operatorShort', 'colorReference', 'colorSource']}
        row.update({'id': BASE_ID if forward else PAIR_ID, 'name': '大崎支線', 'nameNorm': '大崎支線',
                    'nameRoma': 'Osaki Branch', 'stations': stations,
                    'segments': [[round(track['intervalMeters']/1000, 3), 0, track['intervalGeometry']]],
                    'railwayIdentity': BASE_ID, 'permittedTraversal': 'forward' if forward else 'reverse',
                    'alignmentDirection': 'unassigned', 'geometrySource': 'tokyo-southern-branches:OSM-2026-08-18',
                    'displayBranchLeadIns': [track['northLeadInGeometry']] +
                        ([main_display] if forward else []),
                    'southernBranchTopology': {'evidence': str(EVIDENCE.relative_to(ROOT)),
                         'physicalDirection': track['direction'], 'northJunction': track['northJunction'],
                         'southJunction': track['southJunction'], 'northLeadInGeometry': track['northLeadInGeometry'],
                         'northJunctionTrackName': '山手貨物線', 'southJunctionTrackName': '東海道本線（品鶴線）',
                         'sourceWayIDs': track['sourceWayIDs'], 'northAdjoiningWayIDs': evidence['paths'][track['direction']]['northAdjoining'],
                         'note': 'Junctions are measured source vertices, not passenger stops; display integration must preserve this lead-in without deriving routing from the parallel 山手電車線.'}})
        if not forward:
            row.update({'alignmentOf': BASE_ID, 'alignmentRole': 'paired_alignment',
                        'alignmentSplitSource': evidence['primaryTopologyEvidence'][0]['url']})
        else:
            row['displayFreightMainPolicy'] = main_display_policy
        result['lines'].append(row)
    result.setdefault('geometrySource', {}).setdefault('manualOverrides', {})['tokyo-southern-branches'] = {
        'reviewedAt': evidence['reviewedAt'], 'crs': evidence['crs'],
        'script': 'app/scripts/railway/repair-tokyo-southern-branches.py',
        'evidence': 'app/scripts/railway/tokyo-southern-branches-overrides.json',
        'source': evidence['geometryEvidence'], 'primaryTopologyEvidence': evidence['primaryTopologyEvidence'],
        'transformation': 'Retain each directional survey separately; project only the two existing station anchors onto its segment; preserve source branch junctions and north lead-in in metadata.'}
    # Caller regenerates package-wide stats, display rows and fixtures after integration.
    return result


def repair_sections(sections, evidence=None):
    """Optional source-graph supplement, with explicit provenance and line identity."""
    evidence = evidence or json.loads(EVIDENCE.read_text())
    result = copy.deepcopy(sections)
    result['features'] = [f for f in result['features'] if f.get('properties', {}).get('jtm_override') != 'tokyo-southern-branches']
    for track in reviewed_tracks(evidence):
        # Station-to-station graph edge only. The native source topology keeps
        # full fork geometry in the committed evidence, not inferred station links.
        result['features'].append({'type': 'Feature', 'properties': {
            'N02_001': '11', 'N02_002': '2', 'N02_003': '大崎支線', 'N02_004': '東日本旅客鉄道',
            'jtm_override': 'tokyo-southern-branches', 'geometry_crs': 'WGS84',
            'source': 'OpenStreetMap contributors, 2026-08-18, ODbL 1.0',
            'physical_direction': track['direction'],
            'source_way_ids': track['sourceWayIDs']},
            'geometry': {'type': 'LineString', 'coordinates': track['intervalGeometry']}})
    return result


def repair_stations(stations, package, evidence=None):
    """Optional memberships for existing station codes, not invented branch stops."""
    evidence = evidence or json.loads(EVIDENCE.read_text())
    result = copy.deepcopy(stations)
    result['features'] = [f for f in result['features']
        if f.get('jtm_override', f.get('properties', {}).get('jtm_override')) != 'tokyo-southern-branches']
    for row in repair(package, evidence)['lines']:
        if row['id'] not in [BASE_ID, PAIR_ID]:
            continue
        for station in row['stations']:
            result['features'].append({'type': 'Feature', 'jtm_override': 'tokyo-southern-branches', 'properties': {
                'railway_class_code': '11', 'institution_type_code': '2', 'line_name': '大崎支線',
                'operator': '東日本旅客鉄道', 'station_name': station[1],
                'n02_station_code': station[0], 'n02_group_code': station[0], 'display_point': station[2:4],
                'display_line_id': row['id']},
                'geometry': {'type': 'Point', 'coordinates': station[2:4]}})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=ROOT/'public/rail/jp-2025.json')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--check', action='store_true', help='validate committed evidence without modifying the package')
    parser.add_argument('--legacy-display', action='store_true', help='integrate against existing N02 representative display corridors')
    args = parser.parse_args()
    evidence = json.loads(EVIDENCE.read_text())
    tracks = reviewed_tracks(evidence)
    freight_main = reviewed_freight_main(evidence)
    candidate = repair(json.loads(args.package.read_text()), evidence)
    if args.legacy_display:
        candidate = integrate_legacy_display(candidate, evidence)
    if args.output:
        assert args.output.resolve() != args.package.resolve(), 'Write a reviewable candidate to a different path'
        args.output.write_text(json.dumps(candidate, ensure_ascii=False, separators=(',', ':')))
    for track in tracks:
        print(f"{track['direction']}: {len(track['intervalGeometry'])} station-interval vertices; {track['intervalMeters']:.1f} m; north junction {track['northJunction']}; south junction {track['southJunction']}")
    print(f'Station-free freight main: {len(freight_main)} vertices, {length(freight_main):.1f} m; both north forks have exact source support')
    print('Validated two independently directed 大崎支線 candidates; shared package unchanged')


if __name__ == '__main__':
    main()
