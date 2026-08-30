import os
import sys
import unittest


LIB = os.path.join(os.path.dirname(__file__), '..', 'lib')
sys.path.insert(0, os.path.abspath(LIB))

import na_osmlines  # noqa: E402


def route(name, points, ref=''):
    return {
        'name': name,
        'ref': ref,
        'stations': [
            {'name': f'Station {index}', 'point': list(point)}
            for index, point in enumerate(points)
        ],
    }


class DirectionFoldTests(unittest.TestCase):
    def test_reverse_destination_names_fold(self):
        forward = route('METRORail Green Line: A → B', [(0, 0), (0.01, 0)])
        reverse = route('METRORail Green Line: B → A', [(0.01, 0), (0, 0)])
        self.assertTrue(na_osmlines.same_railway(forward, reverse))

    def test_same_corridor_different_public_lines_do_not_fold(self):
        main = route('MATA Trolley Main Street Line: A → B',
                     [(0, 0), (0.001, 0)])
        riverfront = route('MATA Trolley Riverfront Loop',
                           [(0, 0), (0.001, 0)])
        self.assertFalse(na_osmlines.same_railway(main, riverfront))

    def test_same_ref_is_route_identity(self):
        forward = route('Cochrane => Moosonee', [(0, 0), (0.01, 0)], ref='PBE')
        reverse = route('Moosonee => Cochrane', [(0.01, 0), (0, 0)], ref='PBE')
        self.assertTrue(na_osmlines.same_railway(forward, reverse))

    def test_different_refs_do_not_fold(self):
        blue = route('Airport Blue Line', [(0, 0), (0.001, 0)], ref='Blue')
        green = route('Airport Green Line', [(0, 0), (0.001, 0)], ref='Green')
        self.assertFalse(na_osmlines.same_railway(blue, green))


if __name__ == '__main__':
    unittest.main()
