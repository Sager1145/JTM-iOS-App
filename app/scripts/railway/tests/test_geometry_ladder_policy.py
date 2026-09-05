"""The one rule the three registry gates have to keep between them.

The North America build has three ways to say something is wrong with a
railway, and they used to be one:

``blockedRouteIds``
    this SERVICE must not ship — it is a replacement bus this season, an
    ambiguous feed route with no published identity, a temporary event
    shuttle, a station pattern that is several services wearing one id;

``officialNetworkDefectByRouteId``
    that reviewed CENTRELINE is wrong for this route — split into
    disconnected components, routed through a crossover no passenger train
    takes, missing half the corridor. Strict releases withhold the route;
    explicit comparison builds may skip the layer and inspect the next source;

``geometryReviewByRouteId``
    this route has an unresolved alignment question — no independent survey
    covers the corridor, the second opinion disagrees inside the band, or the
    operator layer has no surveyed lineage. Strict releases withhold it;
    explicit comparison builds carry the question into their output.

Collapsing the second and third into the first is how BART, WMATA, DART,
Cleveland, the Montréal métro, the REM, exo, most of Amtrak's long-distance
network and the whole of VIA's came to be absent from a package whose own
acceptance document said it aimed at national completeness. Each was refused
for a statement about our verification, not about the railway — and a reader
of the map cannot tell the difference between a railway that does not exist
and one we could not double-check.

So this holds the boundary in the place the repository states its rules: a
block has to name something about the SERVICE. If a route's problem is that
nobody surveyed it, or that two sources disagree about where it is, it goes
in one of the other two keys so the ledger preserves the exact evidence gap;
the current strict release still withholds that route.
"""
from __future__ import annotations

import json
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REGISTRY = os.path.abspath(os.path.join(HERE, '..', 'na-feeds.json'))

#: Phrases that describe the state of our EVIDENCE rather than the state of
#: the railway. Every one of these was, at some point, the whole reason a real
#: passenger service was missing from the packages.
EVIDENCE_TALK = re.compile(
    r'(?i)\b('
    r'unavailable|unverified|not verified|no independent|not independent|'
    r'no second|no accepted|no surveyed|no verified|no reproducible|'
    r'deviates|disagrees|lacks a|generalized|derived from|'
    r'cannot reach every|split into|leaves \d+ of \d+|'
    r'sampled vertices'
    r')\b')

#: The exceptions, each with the sentence that makes it a statement about the
#: service. They are listed here rather than pattern-matched because an
#: exception nobody had to write down is an exception nobody reviewed.
REVIEWED_BLOCKS = {
    ('embark', 'rt-B1-SC'): 'the operator\'s own loop shape reverses on itself '
                            'and no other alignment exists for it',
    ('embark', 'rt-D1-SC'): 'the operator\'s own loop shape reverses on itself '
                            'and no other alignment exists for it',
    ('embark', 'rt-TSL'): 'an event shuttle, not a scheduled railway',
    ('mta-long-island-rail-road', '11'): 'Belmont Park has no trips in the '
                                         'published feed and no branch of its '
                                         'own in the official layer',
}


def registry():
    with open(REGISTRY, encoding='utf-8') as source:
        return json.load(source)


class GeometryLadderPolicyTests(unittest.TestCase):
    def feeds(self):
        return registry()['feeds']

    def test_a_block_names_the_service_not_our_evidence(self):
        offenders = []
        for feed in self.feeds():
            for route, reason in (feed.get('blockedRouteIds') or {}).items():
                if (feed['slug'], route) in REVIEWED_BLOCKS:
                    continue
                if EVIDENCE_TALK.search(str(reason)):
                    offenders.append(f'{feed["slug"]}:{route} — {reason}')
        self.assertEqual(offenders, [], '\n'.join(
            ['these refuse a railway for a gap in our evidence; move them to '
             'officialNetworkDefectByRouteId (that layer is wrong for this '
             'route) or geometryReviewByRouteId (the strict release withholds '
             'it while preserving the question):'] + offenders))

    def test_the_three_gates_do_not_claim_the_same_route(self):
        for feed in self.feeds():
            blocked = set(feed.get('blockedRouteIds') or ())
            defective = set(feed.get('officialNetworkDefectByRouteId') or ())
            review = set(feed.get('geometryReviewByRouteId') or ())
            for first, second, names in ((blocked, defective, 'blocked/defect'),
                                         (blocked, review, 'blocked/review'),
                                         (defective, review, 'defect/review')):
                self.assertEqual(
                    first & second, set(),
                    f'{feed["slug"]}: {names} disagree about the same route')

    def test_every_gate_gives_a_reason_somebody_can_act_on(self):
        for feed in self.feeds():
            for key in ('blockedRouteIds', 'officialNetworkDefectByRouteId',
                        'geometryReviewByRouteId'):
                for route, reason in (feed.get(key) or {}).items():
                    self.assertIsInstance(reason, str, f'{feed["slug"]}:{route}')
                    self.assertGreaterEqual(
                        len(reason.strip()), 20,
                        f'{feed["slug"]}:{route} in {key} has no usable reason')

    def test_a_feed_requiring_official_mappings_has_some_to_require(self):
        """`requireOfficialMappingForAllRoutes` with no mapping deletes a feed.

        WMATA carried exactly that pair: the flag said every route must name a
        reviewed centreline, the feed named none, and all six Metrorail lines
        were dropped by a rule that could never have been satisfied.
        """
        for feed in self.feeds():
            if feed.get('requireOfficialMappingForAllRoutes'):
                self.assertTrue(
                    feed.get('officialNetworkByRouteId')
                    or feed.get('officialNetwork'),
                    f'{feed["slug"]} requires an official mapping for every '
                    'route and declares none')


if __name__ == '__main__':
    unittest.main()
