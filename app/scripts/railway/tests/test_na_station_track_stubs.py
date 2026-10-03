import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('na_station_stub_builder', Path(__file__).parents[1] / 'build-north-america-rail-package.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class StationStubTests(unittest.TestCase):
    def test_sparse_terminal_edge_is_not_published_as_a_500m_station(self):
        anchor, previous = [-123.097489, 49.273815], [-123.095, 49.270]
        actual = builder.station_track_stub(anchor, previous)
        self.assertEqual(actual[0], anchor)
        self.assertLess(builder.geo.haversine(*actual), 1.15)
        self.assertGreater(builder.geo.haversine(*actual), .85)

    def test_short_surveyed_edge_is_preserved(self):
        anchor, neighbour = [-73, 45], [-73, 45.000001]
        self.assertEqual(builder.station_track_stub(anchor, neighbour), [anchor, neighbour])


if __name__ == '__main__':
    unittest.main()
