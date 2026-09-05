import json
import os
import unittest


REGISTRY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..',
                                        'na-feeds.json'))
BUILD_REPORT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', '..', '..', 'public', 'rail',
    'na-2025-build-report.json'))
US_PACKAGE = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', '..', '..', 'public', 'rail',
    'us-2025.json'))


class SouthMidwestStrictGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            cls.feeds = {row['slug']: row
                         for row in json.load(source)['feeds']}

    def test_miami_outer_loop_and_airport_mover_are_blocked(self):
        feed = self.feeds['miami-dade-transit']
        self.assertTrue(feed['forbidOfficialNetworkFallback'])
        self.assertEqual(set(feed['officialNetworkDefectByRouteId']), {'14456'})
        self.assertEqual(set(feed['geometryReviewByRouteId']), {'14458'})

    def test_embark_geometry_failures_are_exactly_blocked(self):
        # The operator's own shape is the only alignment these loops have and
        # it reverses on itself, so there is nothing left to draw them from:
        # a real block, not a preference between two sources.
        feed = self.feeds['embark']
        self.assertEqual(set(feed['blockedRouteIds']),
                         {'rt-B1-SC', 'rt-D1-SC', 'rt-TSL'})

    def test_cta_brown_pink_purple_no_longer_flagged_as_official_spikes(self):
        # Brn, Pink and P (Purple) used to be excluded here because their
        # official-network alignment near-reversed on itself. na_official.py's
        # drop_junction_stubs() now trims that kind of junction-throat stub
        # before the reversal check runs, so the operator GTFS geometry these
        # three routes actually ship on no longer trips the defect gate --
        # there is nothing left in officialNetworkDefectByRouteId to name
        # them for. requireOfficialMappingForAllRoutes stays on: any *other*
        # route CTA adds still has to clear the same official-network check.
        feed = self.feeds['cta']
        self.assertTrue(feed['requireOfficialMappingForAllRoutes'])
        self.assertFalse(
            {'Brn', 'Pink', 'P'} & set(feed.get('officialNetworkDefectByRouteId', {})),
            'Brn/Pink/P should no longer be flagged as official-network '
            'defects now that drop_junction_stubs() removes the spike')

        # And the routes are not just un-flagged on paper -- they actually
        # build: the feed's build-report entry drops nothing for them, and
        # their lines ship in the compact package.
        with open(BUILD_REPORT, encoding='utf-8') as source:
            report = json.load(source)
        cta_report = next(f for f in report['feeds'] if f['slug'] == 'cta')
        self.assertEqual(cta_report['dropped'], [])
        built_routes = {note.split(':', 1)[0].strip()
                        for note in cta_report['notes']}
        self.assertTrue({'Brn', 'Pink', 'P'} <= built_routes)

        with open(US_PACKAGE, encoding='utf-8') as source:
            package = json.load(source)
        line_ids = {line['id'] for line in package['lines']
                   if line.get('sourceFeed') == 'cta'}
        self.assertEqual(
            {'cta-brown-line', 'cta-pink-line', 'cta-purple-line'} & line_ids,
            {'cta-brown-line', 'cta-pink-line', 'cta-purple-line'})

    def test_metra_strict_fallback_and_cross_feed_identity_exceptions(self):
        feed = self.feeds['metra']
        self.assertTrue(feed['forbidOfficialNetworkFallback'])
        self.assertEqual(set(feed['crossFeedDistinctStopIds']),
                         {'LSS', '35TH'})

    def test_lakeshore_prefers_the_post_double_track_operator_alignment(self):
        # NICTD's current shape includes the rebuilt Hammond Gateway approach;
        # the older NARN path is 49 m off the independent track reference and
        # causes that station interval to be withheld from display.
        feed = self.feeds['south-shore-line']
        self.assertEqual(feed['preferOperatorShapeByRouteId'], ['so_shore'])

    def test_south_shore_uses_reviewed_metra_track_to_kensington(self):
        policy = self.feeds['south-shore-line']['reviewedSharedTrack']
        self.assertEqual(policy['canonicalLineId'], 'metra-me')
        self.assertEqual(policy['canonicalTerminalStationId'], 'MILLENNIUM')
        self.assertEqual(
            {(member['lineId'], member['terminalSide'])
             for member in policy['members']},
            {('south-shore-line-lakeshore', 'start'),
             ('south-shore-line-monon', 'end')})
        self.assertGreaterEqual(len(policy['evidence']), 2)

    def test_repaired_routes_require_verified_official_networks(self):
        dart = self.feeds['dallas-area-rapid-transit-da']
        self.assertEqual(len(dart['officialNetworkByRouteId']), 8)
        self.assertTrue(dart['requireVerifiedOfficialNetwork'])
        self.assertTrue(dart['requireOfficialMappingForAllRoutes'])
        self.assertEqual(len(self.feeds['cleveland-rta']['geometryReviewByRouteId']),
                         4)
        self.assertEqual(set(self.feeds['charlotte-area-transit-syste']
                             ['officialNetworkDefectByRouteId']), {'501'})
        self.assertEqual(set(self.feeds['charlotte-area-transit-syste']
                             ['blockedRouteIds']), {'510'})
        self.assertTrue(self.feeds['houston-metro']
                        ['forbidOfficialNetworkFallback'])

    def test_bart_publishes_its_six_lines_rather_than_none(self):
        """BART's twelve routes are six lines published twice, by direction.

        Excluding all twelve to express "the operator KMZ is unavailable"
        deleted the fifth-busiest rapid transit system in the United States
        and left nothing in the ledger to say so — the exclusion list is
        applied before the direction merge, so the merge had nothing to fold.
        The KMZ is still unavailable; BART's own GTFS alignment draws the
        lines, and the independent cross-check measures what shipped.
        """
        feed = self.feeds['bart']
        self.assertNotIn('excludeRoutes', feed)
        self.assertEqual(
            [set(group) for group in feed['mergeRouteIdGroups']],
            [{'1', '2'}, {'3', '4'}, {'5', '6'},
             {'7', '8'}, {'11', '12'}, {'19', '20'}])


if __name__ == '__main__':
    unittest.main()
