import json
import os
import unittest


REGISTRY = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'na-feeds.json'))


class GalvestonDirectionalRouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            feeds = json.load(source)['feeds']
        cls.feed = next(row for row in feeds
                        if row['slug'] == 'galveston-island-transit')

    def test_two_shape_loop_is_fail_closed_until_edges_keep_shape_provenance(self):
        self.assertEqual(set(self.feed['geometryReviewByRouteId']), {'Rail'})
        reason = self.feed['geometryReviewByRouteId']['Rail']
        self.assertIn('Rail-A-OB', reason)
        self.assertIn('Rail-A-IB', reason)
        self.assertIn('89% self-overlap', reason)
        self.assertNotIn('stationOrderByRouteId', self.feed)
        self.assertNotIn('officialShapeIdByRouteId', self.feed)


if __name__ == '__main__':
    unittest.main()
