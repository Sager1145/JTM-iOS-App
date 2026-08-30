import importlib.util
import os
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'make-na-line-review.py'))
SPEC = importlib.util.spec_from_file_location('na_line_review', SCRIPT)
review = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(review)


class LineReviewTests(unittest.TestCase):
    def test_blocked_findings_for_one_line_are_grouped(self):
        report = {'feeds': [{'slug': 'geometry-release-blockers', 'dropped': [
            {'line': 'metro-red', 'why': 'direct chord', 'intervals': [1]},
            {'line': 'metro-red', 'why': 'direct chord', 'intervals': [2]},
        ]}]}
        rows = review.blocked_rows(report)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['lineId'], 'metro-red')
        self.assertEqual(len(rows[0]['issues']), 2)

    def test_official_route_network_is_marked_as_official_spatial_geometry(self):
        package = {'country': 'US', 'geometrySource': {
            'verifiedOfficialNetworks': {'authority-red': {'sha256': 'a' * 64}},
        }, 'lines': [{
            'id': 'metro-red', 'name': 'Red', 'operator': 'Metro',
            'geometrySource': 'authority-red', 'stations': [1, 2],
            'lengthKm': 2.0, 'colorReference': '#ff0000',
            'colorSource': 'official GTFS',
        }]}
        rows = review.published_rows([package], [])
        self.assertTrue(rows[0]['officialSpatialGeometry'])
        self.assertEqual(rows[0]['review'], 'passed')


if __name__ == '__main__':
    unittest.main()
