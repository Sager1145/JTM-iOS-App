#!/usr/bin/env python3
"""Fetch the FRA/BTS North American Rail Network.

    python3 scripts/railway/download-north-america-narn.py \
        --output-dir /private/tmp/na-rail/narn

This is the official record of where mainline track is in the United States and
Canada, published by the Federal Railroad Administration through the Bureau of
Transportation Statistics as part of the National Transportation Atlas
Database. It is what the intercity, commuter and heritage lines in both
packages are routed over, and what their geometry is checked against.

## What is downloaded, and what is left behind

The service holds a little over 300,000 segments, of which the great majority
are yard, industrial and out-of-service track that no passenger train can
reach. What is kept is:

* every segment on a **main line** (``NET='M'``), plus the branch, industrial
  and siding classes that main lines connect through — without them a route
  breaks wherever a station is on a spur;
* every segment attributed to a **passenger carrier** (``PASSNGR``), whatever
  its class, so a passenger route can never be broken by a class filter.

Each page is written as a gzipped list of ``{properties, coordinates}``, with
coordinates rounded to six decimals — about 11 cm, an order of magnitude finer
than the network's own vertex spacing and two orders finer than anything the
map draws. Pages already present are not fetched again, so an interrupted run
resumes.
"""
from __future__ import annotations

import argparse
import gzip
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import concurrent.futures as cf

SERVICE = ('https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/'
           'NTAD_North_American_Rail_Network_Lines/FeatureServer/0/query')
USER_AGENT = ('JTM-RailMap-DataBuild/1.0 '
              '(https://github.com/Sager1145/JTM-iOS-App)')
FIELDS = ('FRAARCID,FRFRANODE,TOFRANODE,STATEAB,COUNTRY,RROWNER1,TRKRGHTS1,'
          'SUBDIV,BRANCH,PASSNGR,TRACKS,NET,KM,TIMEZONE')
WHERE = ("(NET='M' OR NET='A' OR NET='I' OR NET='S' OR "
         "(PASSNGR IS NOT NULL AND PASSNGR <> ' ' AND PASSNGR <> ''))")


def post(params, tries=6, timeout=300):
    body = urllib.parse.urlencode(params).encode()
    for attempt in range(tries):
        try:
            request = urllib.request.Request(
                SERVICE, data=body,
                headers={'User-Agent': USER_AGENT,
                         'Content-Type': 'application/x-www-form-urlencoded'})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read())
        except Exception:                                   # noqa: BLE001
            if attempt == tries - 1:
                raise
            time.sleep(3 + 4 * attempt)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output-dir', required=True)
    ap.add_argument('--page', type=int, default=1000)
    ap.add_argument('--workers', type=int, default=5)
    options = ap.parse_args()
    os.makedirs(options.output_dir, exist_ok=True)

    total = post({'where': WHERE, 'returnCountOnly': 'true', 'f': 'json'})['count']
    sys.stderr.write(f'{total} segments\n')
    offsets = list(range(0, total, options.page))

    def fetch(offset):
        path = os.path.join(options.output_dir, f'page-{offset:07d}.json.gz')
        if os.path.exists(path) and os.path.getsize(path) > 100:
            return path
        data = post({'where': WHERE, 'outFields': FIELDS, 'returnGeometry': 'true',
                     'outSR': '4326', 'f': 'geojson', 'resultOffset': str(offset),
                     'resultRecordCount': str(options.page),
                     'orderByFields': 'FRAARCID'})
        slim = []
        for feature in data.get('features', ()):
            geometry = feature.get('geometry') or {}
            if geometry.get('type') != 'LineString':
                continue
            slim.append({
                'p': feature['properties'],
                'c': [[round(x, 6), round(y, 6)]
                      for x, y, *_ in geometry['coordinates']],
            })
        with open(path, 'wb') as fh:
            fh.write(gzip.compress(json.dumps(slim).encode()))
        return path

    done = 0
    with cf.ThreadPoolExecutor(options.workers) as ex:
        for _ in ex.map(fetch, offsets):
            done += 1
            if done % 20 == 0:
                sys.stderr.write(f'{done}/{len(offsets)} pages\n')
                sys.stderr.flush()
    sys.stderr.write(f'done: {done}/{len(offsets)} pages\n')


if __name__ == '__main__':
    main()
