#!/usr/bin/env python3
"""Group the NA line review into a city-by-city, line-by-line repair ledger.

The line review is ordered by line id, which is the wrong axis for repair work:
nobody fixes "every line whose id starts with m". Defects cluster by the feed
they came from, and feeds cluster by metro area, so this regroups the same
findings the way the work is actually picked up.

Usage: python3 app/scripts/railway/make-city-ledger.py [out.md]
"""
import json, collections, re, sys

import pathlib
REPO = pathlib.Path(__file__).resolve().parents[3]
REVIEW = REPO / 'app/public/rail/na-2025-line-review.json'

# feed slug prefix -> (metro, kind)
# kind: transit | intercity | airport | heritage | meta
METRO = [
    # --- major metros ---
    ('metropolitan-transit-authori', 'New York NY', 'transit'),
    ('mta-long-island-rail-road',    'New York NY', 'transit'),
    ('metro-north-railroad',         'New York NY', 'transit'),
    ('port-authority-trans-hudson',  'New York NY', 'transit'),
    ('osm-port-authority-of-new-york','New York NY', 'transit'),
    ('osm-mta',                      'New York NY', 'transit'),
    ('ttc',                          'Toronto ON', 'transit'),
    ('soci-t-de-transport-de-montr', 'Montreal QC', 'transit'),
    ('osm-soci-t-de-transport-de-mon','Montreal QC', 'transit'),
    ('rem',                          'Montreal QC', 'transit'),
    ('osm-pulsar',                   'Montreal QC', 'transit'),
    ('septa-regional-rail',          'Philadelphia PA', 'transit'),
    ('septa',                        'Philadelphia PA', 'transit'),
    ('osm-strasburg-rail-road',      'Philadelphia PA', 'heritage'),
    ('regional-transportation-dist', 'Denver CO', 'transit'),
    ('osm-denver-international-airpo','Denver CO', 'airport'),
    ('osm-denver-tramway-heritage-so','Denver CO', 'heritage'),
    ('wvu-prt',                      'Morgantown WV', 'transit'),
    ('osm-west-virginia-university-p','Morgantown WV', 'transit'),
    ('trimet-portland-streetcar',    'Portland OR', 'transit'),
    ('osm-astoria-riverfront-trolley','Portland OR', 'heritage'),
    ('san-francisco-municipal-tran', 'San Francisco CA', 'transit'),
    ('osm-sfo-airtrain',             'San Francisco CA', 'airport'),
    ('smart',                        'San Francisco CA', 'transit'),
    ('osm-pacific-locomotive-associa','San Francisco CA', 'heritage'),
    ('osm-roaring-camp-railroads',   'San Francisco CA', 'heritage'),
    ('san-diego-international-airp', 'San Diego CA', 'airport'),
    ('osm-metropolitan-transit-syste','San Diego CA', 'transit'),
    ('north-county-transit-distric', 'San Diego CA', 'transit'),
    ('dallas-area-rapid-transit-da', 'Dallas TX', 'transit'),
    ('osm-dart',                     'Dallas TX', 'airport'),
    ('osm-the-city-of-grapevine',    'Dallas TX', 'heritage'),
    ('cleveland-rta',                'Cleveland OH', 'transit'),
    ('valley-metro-vm',              'Phoenix AZ', 'transit'),
    ('metro-st-louis',               'St Louis MO', 'transit'),
    ('loop-trolley',                 'St Louis MO', 'transit'),
    ('osm-the-loop-trolley-company', 'St Louis MO', 'transit'),
    ('osm-mata',                     'Memphis TN', 'transit'),
    ('sacramento-regional-transit',  'Sacramento CA', 'transit'),
    ('osm-sierra-northern-railway',  'Sacramento CA', 'heritage'),
    ('sound-transit',                'Seattle WA', 'transit'),
    ('metro-transit-intercity-tran', 'Seattle WA', 'transit'),
    ('metropolitan-atlanta-rapid-t', 'Atlanta GA', 'transit'),
    ('osm-atlanta-department-of-avia','Atlanta GA', 'airport'),
    ('embark',                       'Oklahoma City OK', 'transit'),
    ('suntran',                      'Tucson AZ', 'transit'),
    ('calgary-transit',              'Calgary AB', 'transit'),
    ('qline-detroit',                'Detroit MI', 'transit'),
    ('osm-m-1-rail',                 'Detroit MI', 'transit'),
    ('osm-detroit-airport',          'Detroit MI', 'airport'),
    ('mbta',                         'Boston MA', 'transit'),
    ('osm-national-park-service',    'Boston MA', 'heritage'),
    ('metrolink',                    'Los Angeles CA', 'transit'),
    ('osm-fillmore-western-railway', 'Los Angeles CA', 'heritage'),
    ('metra',                        'Chicago IL', 'transit'),
    ('osm-o-hare-airport-transit-sys','Chicago IL', 'airport'),
    ('miami-dade-transit',           'Miami FL', 'transit'),
    ('south-florida-regional-trans', 'Miami FL', 'transit'),
    ('wmata',                        'Washington DC', 'transit'),
    ('dc-streetcar',                 'Washington DC', 'transit'),
    ('vre',                          'Washington DC', 'transit'),
    ('osm-metropolitan-washington-ai','Washington DC', 'airport'),
    ('maryland-transit-administrat', 'Baltimore MD', 'transit'),
    ('port-authority-of-allegheny',  'Pittsburgh PA', 'transit'),
    ('metro-transit',                'Minneapolis MN', 'transit'),
    ('osm-minnesota-streetcar-museum','Minneapolis MN', 'heritage'),
    ('houston-metro',                'Houston TX', 'transit'),
    ('osm-iah',                      'Houston TX', 'airport'),
    ('galveston-island-transit',     'Houston TX', 'transit'),
    ('new-orleans-rta',              'New Orleans LA', 'transit'),
    ('charlotte-area-transit-syste', 'Charlotte NC', 'transit'),
    ('hillsborough-area-regional-t', 'Tampa FL', 'transit'),
    ('osm-tpa',                      'Tampa FL', 'airport'),
    ('kansas-city-area-transportat', 'Kansas City MO', 'transit'),
    ('milwaukee-hop',                'Milwaukee WI', 'transit'),
    ('osm-transdev',                 'Milwaukee WI', 'transit'),
    ('kenosha-streetcar',            'Kenosha WI', 'transit'),
    ('osm-clark-county-department-of','Las Vegas NV', 'airport'),
    ('osm-las-vegas-monorail-company','Las Vegas NV', 'transit'),
    ('osm-orlando-international-airp','Orlando FL', 'airport'),
    ('osm-niagara-frontier-transport','Buffalo NY', 'transit'),
    ('hampton-roads-transit-hrt',    'Norfolk VA', 'transit'),
    ('rock-region-metro',            'Little Rock AR', 'transit'),
    ('sun-metro',                    'El Paso TX', 'transit'),
    ('rio-metro-regional-transit-d', 'Albuquerque NM', 'transit'),
    ('puerto-rico-ati',              'San Juan PR', 'transit'),
    ('south-shore-line',             'Chicago IL', 'transit'),
    ('capitol-corridor-joint-power', 'Sacramento CA', 'intercity'),
    ('osm-ctrail',                   'New Haven CT', 'transit'),
    ('osm-electric-city-trolley-muse','Scranton PA', 'heritage'),
    ('osm-chattanooga-area-regional-','Chattanooga TN', 'heritage'),
    ('osm-great-smoky-mountains-rail','Bryson City NC', 'heritage'),
    ('osm-andrews-valley-rail-tours','Andrews NC', 'heritage'),
    ('osm-edmonton-radial-railway-so','Edmonton AB', 'heritage'),
    ('osm-cn',                       'Lillooet BC', 'heritage'),
    ('osm-keewatin-railway-company', 'The Pas MB', 'intercity'),
    ('osm-ontario-northland-railway','Cochrane ON', 'intercity'),
    ('osm-transport-ferroviaire-tshi','Sept-Iles QC', 'intercity'),
    ('alaska-railroad',              'Anchorage AK', 'intercity'),
    # --- national / meta ---
    ('amtrak-san-joaquins',          '(national) Amtrak', 'intercity'),
    ('amtrak-vermonter',             '(national) Amtrak', 'intercity'),
    ('amtrak',                       '(national) Amtrak', 'intercity'),
    ('via',                          '(national) Via Rail', 'intercity'),
    ('osm-routes',                   '(unassigned) OSM route pool', 'meta'),
    ('geometry-release-blockers',    '(meta) geometry release blockers', 'meta'),
    ('cross-feed-duplicates',        '(meta) cross-feed duplicates', 'meta'),
]


def metro_of(feed):
    best = None
    for pref, city, kind in METRO:
        if feed == pref or feed.startswith(pref):
            if best is None or len(pref) > len(best[0]):
                best = (pref, city, kind)
    return (best[1], best[2]) if best else ('(unmapped) ' + feed, 'transit')


def norm_why(w):
    w = re.sub(r'\d+(\.\d+)?', 'N', w)
    return re.split(r'[:;]', w)[0].strip()[:70]


def main():
    d = json.load(open(REVIEW))
    lines = d['lines']
    cities = collections.defaultdict(lambda: {
        'blocked': [], 'published': 0, 'warned': 0, 'kinds': set()})
    for l in lines:
        feed = l.get('sourceFeed') or '?'
        city, kind = metro_of(feed)
        c = cities[city]
        c['kinds'].add(kind)
        if l['status'] == 'published':
            c['published'] += 1
            if l.get('review') == 'warning':
                c['warned'] += 1
        else:
            c['blocked'].append(l)

    # rank: real transit metros with the most blocked lines first
    def rank(kv):
        city, c = kv
        meta = city.startswith('(')
        return (meta, -len(c['blocked']), city)

    out = []
    s = d['summary']
    out.append('# North America rail — city-by-city repair ledger\n')
    out.append(f"Regenerate with `python3 app/scripts/railway/make-city-ledger.py`. Source: `na-2025-line-review.json` ({d['generatedAt']}).\n")
    out.append(f"**{s['published']} published · {s['blocked']} blocked · "
               f"{s['warnings']} warnings · {s['publishedErrors']} errors in published lines**\n")

    for city, c in sorted(cities.items(), key=rank):
        nb = len(c['blocked'])
        if nb == 0:
            continue
        kinds = ','.join(sorted(c['kinds']))
        out.append(f"\n## {city}  — {nb} blocked / {c['published']} published  ({kinds})\n")
        whys = collections.Counter()
        for l in c['blocked']:
            for i in (l.get('issues') or []):
                whys[norm_why(i.get('why', '?'))] += 1
        for w, n in whys.most_common(6):
            out.append(f"- _{n}×_ {w}")
        out.append('')
        out.append('| line | operator | feed | geometry | why |')
        out.append('|---|---|---|---|---|')
        for l in sorted(c['blocked'], key=lambda x: str(x.get('name') or x.get('sourceRouteId') or '')):
            name = l.get('name') or l.get('sourceRouteId') or '—'
            op = l.get('operator') or '—'
            gs = l.get('geometrySource') or ('official' if l.get('officialSpatialGeometry') else '—')
            iss = l.get('issues') or []
            why = norm_why(iss[0].get('why', '—')) if iss else '—'
            out.append(f"| {str(name)[:34]} | {op[:26]} | {l.get('sourceFeed','')[:24]} | {gs[:18]} | {why} |")
    text = '\n'.join(out) + '\n'
    if len(sys.argv) > 1:
        pathlib.Path(sys.argv[1]).write_text(text)
    else:
        sys.stdout.write(text)


if __name__ == '__main__':
    main()
