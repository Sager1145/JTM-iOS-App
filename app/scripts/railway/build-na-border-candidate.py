#!/usr/bin/env python3
"""Build only the three international passenger services into private outputs.

Uses the normal strict builder, cached official geometry and operator GTFS.
It does not relax geometry gates or overwrite shipped data.
"""
import argparse
import csv
import io
import json
import hashlib
from pathlib import Path
import subprocess
import sys
import zipfile


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / 'lib'))
import na_geo
import na_osm


def reviewed_maple_seam(source_dir):
    """Accept only the pinned FRA seam that independent OSM corroborates.

    This is a sub-feature digitizing gap, not a station-to-station fallback.
    Its two endpoints are unchanged. Dense samples and a shifted negative
    control distinguish an actual reference match from an empty reference.
    """
    path = source_dir / 'official-networks/amtrak-ntad-maple-leaf.geojson'
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    expected = '13e9b79b5458c31881bf8460e037792ef8eb89fdede1880ad5b539f124e947a7'
    if digest != expected:
        raise ValueError('Maple Leaf normalized source changed; seam requires new review')
    payload = json.loads(path.read_text())
    if payload['source']['rawSha256'] != 'ea7344cfbe0f3c4f9434ed15e73b0a53e85615d722d157563add9a4207740c58':
        raise ValueError('Maple Leaf raw source changed; seam requires new review')
    first = [-79.510003000614, 43.6113059998128]
    second = [-79.509659999584, 43.611477000143]
    parts = payload['features'][0]['geometry']['coordinates']
    endpoints = [point for part in parts for point in (part[0], part[-1])]
    if first not in endpoints or second not in endpoints:
        raise ValueError('Maple Leaf seam endpoints changed')
    distance = na_geo.haversine(first, second)
    if not 33 < distance < 34:
        raise ValueError('Maple Leaf seam no longer a 33.5m digitizing gap')
    track = na_osm.Track().load_dir(str(source_dir / 'osm-geom'))
    samples = na_geo.densify([first, second], 1)
    worst = max(track.nearest(point)[0] for point in samples)
    shifted = [[point[0], point[1] + .001] for point in samples]
    control = min(track.nearest(point)[0] for point in shifted)
    if worst > 3 or control < 50:
        raise ValueError(f'independent seam validation failed: {worst=}, {control=}')
    return {'publisher': payload['source']['publisher'], 'url': payload['source']['url'],
            'rawSha256': payload['source']['rawSha256'], 'normalizedSha256': digest,
            'from': first, 'to': second, 'gapMeters': distance,
            'independentSource': 'OpenStreetMap active rail ways, cached cross-check tiles',
            'sampleSpacingMeters': 1, 'maxReferenceDeviationMeters': worst,
            'negativeControlMinDeviationMeters': control,
            'reviewedAt': '2026-09-30',
            'reason': 'One FRA MultiLineString seam; independent active track agrees along the complete 33.5m gap. No station chord, no change to either source endpoint.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--output-root', type=Path, required=True)
    parser.add_argument('--registry', type=Path, default=HERE / 'na-feeds.json')
    args = parser.parse_args()
    registry = json.loads(args.registry.read_text())
    feed = next(f for f in registry['feeds'] if f['slug'] == 'amtrak')
    with zipfile.ZipFile(args.source_dir / 'gtfs' / f'{feed["mdb"]}.zip') as archive:
        routes = list(csv.DictReader(io.TextIOWrapper(archive.open('routes.txt'), encoding='utf-8-sig')))
    selected = {'60', '95', '68', '31849'}
    found = {r['route_id'] for r in routes}
    if selected - found:
        raise ValueError(f'operator feed lacks routes {selected - found}')
    feed['excludeRoutes'] = sorted(set(feed.get('excludeRoutes') or []) | (found - selected))
    registry['feeds'] = [feed]
    seam = reviewed_maple_seam(args.source_dir)
    feed['officialNetworkEndpointJoinMetersByKey'] = {'amtrak-ntad-maple-leaf': 34}
    feed['officialNetworkEndpointJoinEvidenceByKey'] = {'amtrak-ntad-maple-leaf': seam}
    # The joint service is branded by the actual operator in each country,
    # not by whichever of the two GTFS route aliases wins pattern merging.
    expected_agencies = {'68': '51', '31849': '157'}
    if any(next(r for r in routes if r['route_id'] == rid)['agency_id'] != agency
           for rid, agency in expected_agencies.items()):
        raise ValueError('Maple Leaf operator feed changed; country branding requires review')
    feed['operatorByCountryByRouteId'] = {
        rid: {'us': 'Amtrak', 'ca': 'Via Rail Canada'} for rid in expected_agencies}
    evidence = [
        'Operator GTFS feed 11, version 20260903: Maple Leaf route 68 agency 51 Amtrak; route 31849 agency 157 VIA Rail Canada. Reviewed 2026-09-30.',
        'https://www.viarail.ca/en/plan/train-schedules/toronto-niagara-falls-new-york',
        'https://www.amtrak.com/maple-leaf-train',
    ]
    feed['operatorByCountryEvidenceByRouteId'] = {
        rid: evidence for rid in expected_agencies}
    args.output_root.mkdir(parents=True, exist_ok=True)
    registry_path = args.output_root / 'border-registry.json'
    registry_path.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + '\n')
    subprocess.run([sys.executable, str(HERE / 'build-north-america-rail-package.py'),
                    '--registry', str(registry_path), '--source-dir', str(args.source_dir),
                    '--only', 'amtrak', '--output-dir', str(args.output_root / 'public'),
                    '--data-dir', str(args.output_root / 'data'), '--cache-dir', str(args.output_root / 'cache'),
                    '--report', str(args.output_root / 'build-report.json')], check=True)
    expected_lines = {
        'us': {'amtrak-adirondack-us', 'amtrak-amtrak-cascades-us',
               'amtrak-maple-leaf-us', 'amtrak-amtrak-cascades-border1',
               'amtrak-maple-leaf-border1'},
        'ca': {'amtrak-adirondack-ca', 'amtrak-maple-leaf-ca',
               'amtrak-adirondack-border1'},
    }
    for country, expected in expected_lines.items():
        path = args.output_root / 'public' / f'{country}-2025.json'
        actual = {line['id'] for line in json.loads(path.read_text())['lines']} if path.exists() else set()
        if actual != expected:
            raise ValueError(f'{country}: incomplete international build: {expected - actual}; unexpected {actual - expected}')


if __name__ == '__main__':
    main()
