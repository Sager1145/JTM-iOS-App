"""Image evidence tests; no network, native app, or geometry mutation."""
import importlib.util
from pathlib import Path
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
PATH = ROOT / 'app/scripts/railway/lib/apple_map_corridor.py'
SPEC = importlib.util.spec_from_file_location('apple_map_corridor', PATH)
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)
FRAMES = ROOT / 'docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/keiyo/west-long-review'
BOUNDS = {'west': 139.919907, 'east': 139.925387,
          'north': 35.668096, 'south': 35.664915}


class AppleMapCorridorTests(unittest.TestCase):
    def test_mercator_georeferencing_round_trips_and_matches_edges(self):
        for pixel in ([0, 0], [1211, 865], [827, 440]):
            coordinate = mod.pixel_to_wgs84(pixel, BOUNDS, (1211, 865))
            actual = mod.wgs84_to_pixel(coordinate, BOUNDS, (1211, 865))
            np.testing.assert_allclose(actual, pixel, atol=1e-7)
        np.testing.assert_allclose(mod.pixel_to_wgs84([0, 0], BOUNDS, (1211, 865)),
                                   [BOUNDS['west'], BOUNDS['north']])

    def test_real_shiohama_dark_pair_corrects_an_east_biased_seed(self):
        result = mod.analyze_corridor(
            FRAMES / 'main-shiohama-detail-basemap.png', BOUNDS,
            corridor_wgs84=[[139.924119, 35.667547], [139.92314, 35.66555]],
            station_wgs84=[139.923651, 35.666478],
            masks=[[0, 0, 1211, 31], [0, 420, 430, 865], [1140, 570, 1211, 865]])
        supported = [row for row in result['trace'] if row['supported']]
        self.assertGreater(result['support_fraction'], .65)
        self.assertEqual(result['station_alignment']['status'], 'candidate')
        self.assertEqual(result['station_alignment']['kind'], 'transverse_railway_alignment_only')
        self.assertEqual(result['platform']['status'], 'no_anchor')
        for y, low, high in [(480, 788, 798), (520, 770, 783)]:
            sample = min(supported, key=lambda row: abs(row['pixel'][1] - y))
            self.assertLess(abs(sample['pixel'][1] - y), 4)
            self.assertGreaterEqual(sample['pixel'][0], low)
            self.assertLessEqual(sample['pixel'][0], high)
            self.assertGreater(abs(sample['offset_pixels']), 5)

    def test_context_image_abstains_from_platform_anchor(self):
        result = mod.analyze_corridor(
            FRAMES / 'main-long-context-basemap.png',
            {'west': 139.895312, 'east': 139.959257,
             'north': 35.69717, 'south': 35.660069},
            corridor_wgs84=[[139.922, 35.664], [139.938, 35.679]],
            station_wgs84=[139.923651, 35.666478])
        self.assertEqual(result['platform']['status'], 'no_anchor')
        self.assertEqual(result['platform']['reason'], 'insufficient_platform_resolution')

    def test_featureless_blue_warehouse_is_not_a_rail_or_platform(self):
        raster = Image.fromarray(np.full((160, 200, 3), [79, 111, 144], dtype=np.uint8))
        result = mod.analyze_corridor(raster,
            {'west': 139, 'east': 139.0008, 'north': 35.0006, 'south': 35},
            corridor_pixels=[[100, 10], [100, 150]], station_wgs84=[139.0004, 35.0003])
        self.assertEqual(result['support_fraction'], 0)
        self.assertEqual(result['platform']['status'], 'no_anchor')

    def test_masked_rail_has_no_observed_support(self):
        raster = np.full((160, 200, 3), [80, 100, 130], dtype=np.uint8)
        raster[:, 96:98] = 20
        raster[:, 103:105] = 20
        result = mod.analyze_corridor(Image.fromarray(raster),
            {'west': 139, 'east': 139.0008, 'north': 35.0006, 'south': 35},
            corridor_pixels=[[100, 10], [100, 150]], masks=[[60, 0, 140, 160]])
        self.assertEqual(result['support_fraction'], 0)

    def test_bounded_central_platform_footprint_can_produce_a_candidate(self):
        raster = np.full((180, 200, 3), [50, 60, 65], dtype=np.uint8)
        raster[30:150, 80:120] = [79, 111, 144]
        raster[:, 96:98] = 20
        raster[:, 103:105] = 20
        result = mod.analyze_corridor(Image.fromarray(raster),
            {'west': 139, 'east': 139.00088, 'north': 35.00072, 'south': 35},
            corridor_pixels=[[100, 5], [100, 175]], station_wgs84=[139.00044, 35.00036])
        self.assertEqual(result['platform']['status'], 'candidate')
        np.testing.assert_allclose(result['platform']['pixel'], [99.5, 89.5], atol=1.5)
        self.assertGreater(result['platform']['length_metres'], 40)
        self.assertGreater(result['platform']['width_metres'], 12)

    def test_rotated_or_tilted_georeference_is_rejected(self):
        raster = Image.new('RGB', (100, 100))
        for orientation in ({'heading': 20}, {'pitch': 30}):
            with self.assertRaisesRegex(ValueError, 'north-up'):
                mod.analyze_corridor(raster, BOUNDS,
                                     corridor_pixels=[[50, 0], [50, 99]], **orientation)


if __name__ == '__main__':
    unittest.main()
