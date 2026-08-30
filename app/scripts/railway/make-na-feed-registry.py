#!/usr/bin/env python3
"""Turn a scan of every United States and Canadian GTFS feed into the registry.

    python3 scripts/railway/make-na-feed-registry.py \
        --scan /private/tmp/na-rail/feed-scan.json \
        --out scripts/railway/na-feeds.json

## Why the registry is generated rather than written by hand

"Every passenger railway" is a claim, and a hand-written list of operators is
a claim nobody can check — the next system to open is missing from it and
nothing says so. So the list is derived: MobilityData's source catalogue names
every GTFS feed published in the two countries, each feed's own ``routes.txt``
says whether it carries a railway, and a feed that does is in the registry
whether or not anybody remembered it.

## What is left out, and on what evidence

* **Not a public railway.** A ride inside a paid attraction — a theme park, a
  zoo, a resort — is a fairground ride that happens to run on rails. There is
  no field in GTFS that says "this is not transport", so the test is on the
  names, and the names are in `lib/na_attractions.py` because this script is
  one of three places that has to make that decision. The other two are
  `report-na-coverage.py` and the OpenStreetMap path in the builder; they
  used to disagree, and `ca-2025.json` shipped a streetcar inside Fort
  Edmonton Park because none of the three lists named it.
* **A duplicate of a better feed.** Several operators appear more than once:
  their own feed, a regional aggregator's copy, and a third party's. The
  operator's own (``is_official``) wins, then the one carrying more rail
  routes.

Everything dropped is written to the report with the rule that dropped it, so
a mistake here is visible rather than silent.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))

import na_attractions                # noqa: E402


def slugify(text, fallback='feed'):
    out = re.sub(r'[^a-z0-9]+', '-', (text or '').lower()).strip('-')
    return out or fallback


SLUG_OVERRIDES = {
    'amtrak': 'amtrak',
    'via-rail-canada': 'via',
    'bay-area-rapid-transit-bart': 'bart',
    'massachusetts-bay-transportation-authority-mbta': 'mbta',
    'metropolitan-transportation-authority-mta': 'mta',
    'southeastern-pennsylvania-transportation-authority-septa': 'septa',
    'washington-metropolitan-area-transit-authority-wmata': 'wmata',
    'chicago-transit-authority-cta': 'cta',
    'toronto-transit-commission-ttc': 'ttc',
    'societe-de-transport-de-montreal-stm': 'stm',
    'translink-vancouver': 'translink',
}


def choose(rows):
    """One feed per operator: their own, then the fullest."""
    return sorted(rows, key=lambda r: (
        0 if str(r.get('official')).lower() in ('true', '1') else 1,
        -int(r.get('n_rail') or 0),
        r.get('mdb'),
    ))[0]


def attraction_term(row):
    """The attraction term this feed's provider or name contains, if any."""
    return na_attractions.matched_term(row.get('provider'), row.get('name'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--scan', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--report', default=None)
    ap.add_argument('--min-rail-routes', type=int, default=1)
    options = ap.parse_args()

    # JSONL or JSON: the scanner writes one object per line as each feed
    # answers, so a scan of nine hundred feeds is never lost to the last one
    # that hangs. A whole-file JSON scan is still accepted.
    with open(options.scan) as fh:
        text = fh.read()
    stripped = text.lstrip()
    if stripped.startswith('['):
        scan = json.loads(stripped)
    else:
        scan = [json.loads(line) for line in text.splitlines() if line.strip()]

    kept, dropped = [], []
    for row in scan:
        if not row.get('n_rail'):
            continue
        if int(row['n_rail']) < options.min_rail_routes:
            continue
        term = attraction_term(row)
        if term:
            dropped.append({'mdb': row['mdb'], 'provider': row['provider'],
                            'why': f'attraction, not public transport: {term!r}'})
            continue
        kept.append(row)

    by_provider = defaultdict(list)
    for row in kept:
        by_provider[slugify(row['provider'])].append(row)

    feeds = []
    used = set()
    for provider, rows in sorted(by_provider.items()):
        row = choose(rows)
        for other in rows:
            if other is not row:
                dropped.append({'mdb': other['mdb'], 'provider': other['provider'],
                                'why': f"duplicate of {row['mdb']}"})
        slug = SLUG_OVERRIDES.get(provider, provider)
        if len(slug) > 28:
            slug = slug[:28].rstrip('-')
        base, n = slug, 1
        while slug in used:
            n += 1
            slug = f'{base}-{n}'
        used.add(slug)
        feeds.append({
            'slug': slug,
            'mdb': row['mdb'],
            'region': 'ca' if row['country'] == 'CA' else 'us',
            'name': row['provider'],
            'url': row.get('direct') or row.get('url'),
            'mirror': row.get('url'),
            'railRoutes': row.get('n_rail'),
            'agencies': [a.get('name') for a in (row.get('agencies') or [])][:6],
        })

    registry = {
        'note': ('Generated by scripts/railway/make-na-feed-registry.py from the '
                 "MobilityData source catalogue. Every entry names an operator's "
                 'own published GTFS feed; see the module docstring for what is '
                 'left out and on what evidence.'),
        'providers': [
            'Federal Railroad Administration / Bureau of Transportation Statistics '
            '— North American Rail Network (NTAD)',
            'Operator-published GTFS feeds (one per registry entry)',
            'OpenStreetMap contributors',
        ],
        'license': ("US federal open data (public domain) for NTAD; each operator's "
                    'own open-data terms for its GTFS; ODbL 1.0 for OpenStreetMap '
                    'track geometry'),
        'feeds': feeds,
    }
    with open(options.out, 'w') as fh:
        json.dump(registry, fh, ensure_ascii=False, indent=1)
    if options.report:
        with open(options.report, 'w') as fh:
            json.dump({'kept': len(feeds), 'dropped': dropped}, fh,
                      ensure_ascii=False, indent=1)
    print(f'{len(feeds)} feeds, {len(dropped)} dropped', file=sys.stderr)


if __name__ == '__main__':
    main()
