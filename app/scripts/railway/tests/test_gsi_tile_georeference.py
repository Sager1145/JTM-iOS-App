import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
try:
    from gsi_tile_georeference import GsiTileReference
except ImportError:
    GsiTileReference = None


class GsiTileGeoreferenceTests(unittest.TestCase):
    def test_clamped_url_zoom_does_not_halve_aerial_distances(self):
        # Actual Omiya screenshot: URL z20, DOM photo tiles z18 at 256 CSS px.
        self.assertIsNotNone(GsiTileReference, 'DOM tile georeferencing is missing')
        observation = {
            'url': 'https://maps.gsi.go.jp/#20/35.907740/139.621900/',
            'mapRect': {'x': 0, 'y': 40, 'width': 1280, 'height': 680},
            'tiles': [{'src': '//maps.gsi.go.jp/xyz/seamlessphoto/18/232741/103023.jpg',
                       'x': 495, 'y': 329, 'width': 256, 'height': 256}],
        }
        reference = GsiTileReference.from_observation(observation, [139.6219, 35.90774])
        lon, lat = reference.pixel_to_wgs84([640, 380])
        self.assertAlmostEqual(lon, 139.6219021082, places=9)
        self.assertAlmostEqual(lat, 35.9077400321, places=9)
        east, _ = reference.pixel_to_wgs84([644, 380])
        self.assertAlmostEqual(east, 139.6219235659, places=9)

    def test_new_station_url_cannot_certify_previous_station_pixels(self):
        self.assertIsNotNone(GsiTileReference, 'DOM tile georeferencing is missing')
        # Real observed lag: Shiku URL, but Maruyama photo positions remain.
        observation = {
            'url': 'https://maps.gsi.go.jp/#19/35.991025/139.622200/',
            'mapRect': {'x': 0, 'y': 40, 'width': 1280, 'height': 680},
            'tiles': [{'src': '//maps.gsi.go.jp/xyz/seamlessphoto/18/232743/102958.jpg',
                       'x': 515, 'y': 350, 'width': 256, 'height': 256}],
        }
        with self.assertRaisesRegex(ValueError, 'target'):
            GsiTileReference.from_observation(observation, [139.6222, 35.991025])


if __name__ == '__main__':
    unittest.main()
