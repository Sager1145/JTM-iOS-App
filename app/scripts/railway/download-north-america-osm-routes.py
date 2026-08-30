#!/usr/bin/env python3
"""Fetch the OpenStreetMap route relations for railways no operator publishes.

    python3 scripts/railway/download-north-america-osm-routes.py \
        --coverage /private/tmp/na-rail/coverage.json \
        --output-dir /private/tmp/na-rail/osm-routes

Most of the continent's passenger railways publish a GTFS feed and are built
from it. A long tail does not: the Alaska Railroad, the heritage and tourist
railways, most airport people movers, several inclines, and a handful of
transit systems whose feed could not be fetched. They are still passenger
railways, and a package that left them out because their operator has no
open-data programme would be a package of the operators that do.

So for those — and ONLY for those — OpenStreetMap is the source rather than
the cross-check. Which ones is not decided here: it is whatever
`report-na-coverage.py` says is in the inventory and in neither package, so a
system moves from this path to the GTFS path the day its operator publishes a
feed, without anybody editing a list.

Each relation is fetched with its members and their geometry — the ways for
the alignment, the nodes for the stops — because a route relation without its
stop nodes is a line with no stations, and a station list is the half of a
display line that geometry cannot supply.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from na_overpass import Overpass                        # noqa: E402


def fetch(client, relation_ids, path, tries=3):
    query = ('[out:json][timeout:300];'
             f'rel(id:{",".join(str(r) for r in relation_ids)});'
             'out body;'
             '(._;>;);'
             'out geom;')
    body = client.get(query, tries=tries, timeout=420)
    if body is None:
        return False
    with open(path, 'wb') as fh:
        fh.write(body)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--coverage', required=True)
    ap.add_argument('--output-dir', required=True)
    ap.add_argument('--batch', type=int, default=4)
    ap.add_argument('--max-routes-per-operator', type=int, default=40)
    ap.add_argument('--skip-operators-over', type=int, default=0,
                    help='skip operators with more than this many OSM routes; '
                         'a system that large publishes a feed, and a coverage '
                         'report run before every feed is downloaded will name '
                         'it as missing when it is only not built yet')
    ap.add_argument('--include-unattributed', action='store_true',
                    help='also fetch the route relations that name no '
                         'operator, which no missing-operator row can reach')
    options = ap.parse_args()

    with open(options.coverage) as fh:
        coverage = json.load(fh)
    os.makedirs(options.output_dir, exist_ok=True)

    relations = []
    for row in coverage['missingOperators']:
        if (options.skip_operators_over
                and row['osmRoutes'] > options.skip_operators_over):
            continue
        relations += row['relations'][:options.max_routes_per_operator]
    named = len(set(relations))

    # The coverage report compares OPERATORS, so a relation that names no
    # operator can never appear in a missing-operator row — it belongs to
    # nobody, so nobody can be missing it. Following only those rows therefore
    # skipped a set of railways that were invisible twice over: absent from the
    # packages and absent from the report of what is absent.
    #
    # It is not a small set. Montréal's ligne verte and ligne jaune are in it,
    # in both directions — two of the STM's four métro lines, while the package
    # carries the orange and the blue — and so are the White Pass & Yukon
    # Route, the Durango & Silverton, the Grand Canyon Railway and Angel's
    # Flight.
    #
    # Off by default because the same list holds relations outside the two
    # countries (Guadeloupe's plantation railways among them) and relations
    # that name nothing at all; what to do with each is the builder's
    # judgement, and this only puts them within reach of it.
    if options.include_unattributed:
        unattributed = [row['relation'] for row in coverage.get('unattributed', [])]
        relations += unattributed
        sys.stderr.write(f'{named} relations from missing operators, '
                         f'{len(set(unattributed))} attributed to nobody\n')
    relations = sorted(set(relations))
    sys.stderr.write(f'{len(relations)} relations to fetch\n')

    batches = [relations[i:i + options.batch]
               for i in range(0, len(relations), options.batch)]
    client = Overpass()
    done = 0
    for index, batch in enumerate(batches):
        digest = hashlib.sha256(','.join(str(value) for value in batch)
                                .encode('ascii')).hexdigest()[:10]
        path = os.path.join(options.output_dir,
                            f'rel-{batch[0]:010d}-{digest}.json.gz')
        if os.path.exists(path) and os.path.getsize(path) > 100:
            done += 1
            continue
        if fetch(client, batch, path):
            done += 1
        sys.stderr.write(f'{index + 1}/{len(batches)} ({done} present)\n')
        sys.stderr.flush()
        time.sleep(1)
    sys.stderr.write(f'done: {done}/{len(batches)}\n')
    if done < len(batches):
        sys.stderr.write(
            f'INCOMPLETE: {len(batches) - done} batches unanswered — the '
            f'railways in them stay absent from the packages rather than '
            f'being built from a partial answer\n')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main() or 0)
