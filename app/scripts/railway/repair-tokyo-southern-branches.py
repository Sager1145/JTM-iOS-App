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
DISPLAY_REVIEWED_AT = '2026-10-11'
OSAKI_PLATFORM_REFERENCE = 'docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/osaki/sources/jrtt-osaki-chapter4.pdf'


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
    existing = {tuple(point) for point in points}
    for i, point in enumerate(points):
        result.append(point[:])
        for anchor in sorted((p for p in projections if p['index'] == i), key=lambda p: p['t']):
            if tuple(anchor['point']) not in existing and anchor['point'] != result[-1] and anchor['point'] != points[i+1]:
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
    """Replay the passenger display policy (the historical entry point is kept).

    Osaki's Saikyo/Rinkai family is separate from the Yamanote electric family.
    Only the reviewed southern representative tail aliases the Sobu corridor;
    none of these display coordinates add physical edges or traversal rights.
    """
    lines = {line['id']: line for line in package['lines']}
    yamanote, sobu = lines[JR+'山手線'], lines[JR+'総武線-3']
    tracks = reviewed_tracks(evidence)
    north = intervals(yamanote)[1]
    # Retire only the two projections inserted by this owning script. Keep
    # other interval overrides and every original electric-line support.
    legacy_north_keys = {tuple(project(track['northJunction'], north)['point']) for track in tracks}
    electric_overrides = yamanote.get('displayIntervalCoordinates', {})
    if '1' in electric_overrides:
        restored = [point for point in electric_overrides['1']
                    if tuple(point) not in legacy_north_keys or point in north]
        if restored == north:
            electric_overrides.pop('1')
        else:
            electric_overrides['1'] = restored
    south = copy.deepcopy(sobu.get('displayIntervalCoordinates', {}).get('2', intervals(sobu)[2]))
    south_aliases = [project(track['southJunction'], south) for track in tracks]
    assert all(anchor['distance'] < 15 for anchor in south_aliases)
    # Reprojection onto an already-inserted vertex can differ by a final
    # floating-point bit. Keep that exact canonical support / native ruler.
    for anchor in south_aliases:
        existing = next((point for point in south if distance(point, anchor['point']) < 0.000001), None)
        if existing is not None:
            anchor['point'] = existing[:]
    south_display = insert_projections(south, south_aliases)
    sobu.setdefault('displayIntervalCoordinates', {})['2'] = south_display
    # A cartographic centre of the retained passenger-direction anchors, not
    # a surveyed new track. JRTT chapter 4 p207 identifies the shared Saikyo /
    # Rinkai platforms separately from the Yamanote electric platforms.
    osaki = [sum(track['stationProjection']['004135']['point'][i] for track in tracks)/2
             for i in (0, 1)]
    nishi = south[-1]
    for track, south_alias in zip(tracks, south_aliases):
        row = lines[BASE_ID if track['direction'] == 'southbound' else PAIR_ID]
        fork_index = track['intervalGeometry'].index(track['southJunction'])
        own = alias_approach(track['intervalGeometry'][:fork_index+1], osaki, start=True)
        own = alias_approach(own, south_alias['point'])
        own += south_display[south_display.index(south_alias['point'])+1:]
        row['displayStationCoordinates'] = {'004135': osaki[:], '004235': nishi[:]}
        row['displayIntervalCoordinates'] = {'0': own}
        row['stationCircleOwnerByCode'] = {'004135': BASE_ID, '004235': sobu['id']}
        # Bound the platform transition by this short lead-in's own length,
        # so its exact physical fork remains fixed. Known compact parts meet
        # at the same station coordinate; no electric-line alias is involved.
        lead_in = alias_approach(track['northLeadInGeometry'], osaki,
                                 meters=min(200, length(track['northLeadInGeometry'])))
        lead_in[0] = track['northJunction'][:]
        row['displayBranchLeadIns'] = [lead_in]
        row.pop('displayFreightMainPolicy', None)
        topology = row['southernBranchTopology']
        topology['displayAliases'] = {
            'southJunction': south_alias['point'], 'southOffsetMeters': round(south_alias['distance'], 8),
            'policy': 'Reviewed southern shared representative only; not a physical junction or routing edge',
            'approachAliasMeters': 200,
        }
        topology['displaySharedTail'] = {
            'canonicalLineId': sobu['id'], 'canonicalIntervalIndex': 2,
            'branchPartIndex': 0, 'fromCoordinate': south_alias['point'][:],
            'toCoordinate': nishi[:],
            'branchFromMeters': length(own[:own.index(south_alias['point'])+1]),
            'branchToMeters': length(own),
            'canonicalIntervalFromMeters': length(south_display[:south_display.index(south_alias['point'])+1]),
            'canonicalIntervalToMeters': length(south_display),
            'lanePolicy': 'inherit-canonical-shared-span', 'routing': False,
            'evidence': topology['evidence'], 'reviewedAt': DISPLAY_REVIEWED_AT,
            'geometryReviewedAt': evidence['reviewedAt'],
        }
        topology['displayNorthJoin'] = {
            'leadInPartIndex': 1, 'bodyPartIndex': 0, 'coordinate': osaki[:],
            'leadInAtEnd': True, 'bodyAtEnd': False, 'routing': False,
        }
    # User-reviewed local station representation: two southern JR approaches
    # share one continuous station/north stroke. This is a display alias only;
    # the source direction tracks, junctions and passenger memberships remain.
    electric_south = intervals(yamanote)[0]
    station = electric_south[-1][:]
    merge = [139.7295, 35.6183]
    assert merge in electric_south
    shared = list(reversed(electric_south[electric_south.index(merge):]))
    for id in (BASE_ID, PAIR_ID):
        row = lines[id]
        own = row['displayIntervalCoordinates']['0']
        anchor = project(merge, own)
        remainder = [anchor['point']] + own[anchor['index']+1:]
        # A 200 m transition keeps the west approach and the exact downstream
        # shared-tail supports. The common stem itself uses existing supports.
        remainder = alias_approach(remainder, merge, start=True, meters=200)
        row['displayIntervalCoordinates']['0'] = shared + remainder[1:]
        row['displayStationCoordinates']['004135'] = station[:]
        row['stationCircleOwnerByCode']['004135'] = yamanote['id']
        row['displayBranchLeadIns'] = []
        topology = row['southernBranchTopology']
        topology.pop('displayNorthJoin', None)
        topology['displayStationStem'] = {
            'canonicalLineId': yamanote['id'], 'fromCoordinate': station[:],
            'toCoordinate': merge[:], 'policy': 'User-requested local JR representative: two south, one station, one north',
            'routing': False, 'reviewedAt': '2026-10-12',
        }
        tail = topology['displaySharedTail']
        updated = row['displayIntervalCoordinates']['0']
        tail['branchFromMeters'] = length(updated[:updated.index(tail['fromCoordinate'])+1])
        tail['branchToMeters'] = length(updated)
    # Both directions already share one JR family representative in Main.
    # Give that representative one actual path/ruler: a linear follow between
    # two different directional rulers otherwise hands over at two south cuts
    # 8 m apart, moving the ride/fallback stroke away from the shared junction.
    # Physical directional tracks and traversal rights remain in segments and
    # southernBranchTopology's original junction fields.
    representative = lines[BASE_ID]
    paired = lines[PAIR_ID]
    paired['displayIntervalCoordinates']['0'] = copy.deepcopy(representative['displayIntervalCoordinates']['0'])
    paired_topology = paired['southernBranchTopology']
    paired_topology['displaySharedTail'] = copy.deepcopy(representative['southernBranchTopology']['displaySharedTail'])
    cut = paired_topology['displaySharedTail']['fromCoordinate']
    paired_topology['displayAliases']['southJunction'] = cut[:]
    paired_topology['displayAliases']['southOffsetMeters'] = round(distance(paired_topology['southJunction'], cut), 8)
    paired_topology['displayAliases']['policy'] = 'One reviewed JR directional-family display path/ruler; original physical directional junction retained'
    # Rinkai is a separate company at the same through-running platform
    # family. Keep its member/circle identity and its independently sourced
    # approach; a bounded terminal transition supplies the shared centre.
    rinkai = lines.get('jp-東京臨海高速鉄道-臨海副都心線')
    if rinkai is not None:
        assert rinkai['stations'][0][0] == '004135'
        rinkai_source = intervals(rinkai)[0]
        assert distance(rinkai_source[0], osaki) < 15
        rinkai.setdefault('displayStationCoordinates', {})['004135'] = osaki[:]
        rinkai.setdefault('displayIntervalCoordinates', {})['0'] = alias_approach(rinkai_source, osaki, start=True)
        rinkai.get('stationCircleOwnerByCode', {}).pop('004135', None)
    lines[BASE_ID]['alignmentPairs'] = [{'with': PAIR_ID, 'from': '大崎', 'to': '西大井',
        'direction': 'unassigned', 'source': evidence['primaryTopologyEvidence'][0]['url']}]
    package['geometrySource']['manualOverrides']['tokyo-southern-branches']['displayIntegration'] = {
        'reviewedAt': '2026-10-12',
        'format': 'compact-v1 local station representative and explicit shared-stem/tail owners',
        'transformation': 'User-requested local two-south / one-station / one-north JR display; both directions use one reviewed representative path/ruler; retain physical directional forks; Yamanote supplies the continuous station/north stroke; retire capped display leads',
        'platformReference': 'JRTT Rinkai project chapter 4 p207: separate Yamanote electric and Saikyo/Rinkai platforms',
        'platformReferenceURL': evidence['primaryTopologyEvidence'][0]['url'],
        'localPlatformReference': OSAKI_PLATFORM_REFERENCE,
        'localPlatformPlan': OSAKI_PLATFORM_REFERENCE.replace('jrtt-osaki-chapter4.pdf', 'jrtt-osaki-plan-page207.png'),
        'stationCentrePolicy': 'User-requested display-only common JR station anchor; physical anchors and separate Rinkai representative retained',
        'stationCentre': station,
    }
    return package

def repair(package, evidence=None):
    """Return a copy with two directional compact rows; never mutate the input."""
    evidence = evidence or json.loads(EVIDENCE.read_text())
    result = copy.deepcopy(package)
    old_lines = {row['id']: row for row in result['lines']}
    source_osaki = next(s for s in old_lines[JR+'山手線']['stations'] if s[0] == '004135')
    source_nishi = next(s for s in old_lines[JR+'総武線-3']['stations'] if s[0] == '004235')
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
                    'displayBranchLeadIns': [track['northLeadInGeometry']],
                    'southernBranchTopology': {'evidence': str(EVIDENCE.relative_to(ROOT)),
                         'physicalDirection': track['direction'], 'northJunction': track['northJunction'],
                         'southJunction': track['southJunction'], 'northLeadInGeometry': track['northLeadInGeometry'],
                         'northJunctionTrackName': '山手貨物線', 'southJunctionTrackName': '東海道本線（品鶴線）',
                         'sourceWayIDs': track['sourceWayIDs'], 'northAdjoiningWayIDs': evidence['paths'][track['direction']]['northAdjoining'],
                         'note': 'Junctions are measured source vertices, not passenger stops; display integration must preserve this lead-in without deriving routing from the parallel 山手電車線.'}})
        if not forward:
            row.update({'alignmentOf': BASE_ID, 'alignmentRole': 'paired_alignment',
                        'alignmentSplitSource': evidence['primaryTopologyEvidence'][0]['url']})
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
    parser.add_argument('--legacy-display', action='store_true', help='replay the passenger-family display policy (historical flag name)')
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
