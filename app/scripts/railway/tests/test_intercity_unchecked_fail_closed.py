import json
import os
import unittest


REGISTRY = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'na-feeds.json'))


class IntercityUncheckedFailClosedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            cls.feeds = {row['slug']: row
                         for row in json.load(source)['feeds']}

    def test_amtrak_strict_routes_are_blocked_by_exact_gtfs_id(self):
        blocked = self.feeds['amtrak']['officialNetworkDefectByRouteId']
        expected = {
            '40751': 'Acela',
            '77': 'Auto Train',
            '42992': 'Berkshire Flyer',
            '42956': 'Blue Water',
            '42951': 'Lincoln Service',
            '55': 'Pere Marquette',
            '78': 'Pacific Surfliner',
        }
        for route_id, name in expected.items():
            self.assertIn(route_id, blocked)
            self.assertIn(name, blocked[route_id])
            self.assertIn('independent', blocked[route_id])

    def test_gold_runner_block_suppresses_trunk_and_generated_branches(self):
        feed = self.feeds['amtrak-san-joaquins']
        self.assertEqual(set(feed['geometryReviewByRouteId']), {'13510'})
        reason = feed['geometryReviewByRouteId']['13510']
        self.assertIn('222 of 339', reason)
        self.assertIn('alternate branch', reason)

    def test_cross_border_via_route_is_blocked_before_country_slicing(self):
        via = self.feeds['via']
        self.assertIn('119-120', via['officialNetworkDefectByRouteId'])
        reason = via['officialNetworkDefectByRouteId']['119-120']
        self.assertIn('US slice', reason)
        self.assertIn('351 of 546', reason)
        self.assertNotIn('119-120', via['officialNetworkByRouteId'])

    def test_quebec_montreal_is_withheld_until_reference_coverage_is_complete(self):
        via = self.feeds['via']
        reason = via['officialNetworkDefectByRouteId']['628-226']
        self.assertIn('163 of 190', reason)
        self.assertIn('complete service', reason)


if __name__ == '__main__':
    unittest.main()
