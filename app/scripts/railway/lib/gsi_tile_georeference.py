"""Georeference saved GSI screenshots from observed DOM photo tile rectangles.

The URL hash can name a clamped zoom or a target that has not rendered yet.
Read loaded, fully opaque photo tiles and their browser bounding rectangles;
pass the requested coordinate separately. This module measures geography only,
never identifies a platform or accepts a railway correction.
"""
import math
import re
from dataclasses import dataclass


@dataclass(frozen=True)
class GsiTileReference:
    world_size: float
    world_x_at_screen_zero: float
    world_y_at_screen_zero: float
    world_pixels_per_screen_pixel: float

    @classmethod
    def from_observation(cls, observation, target_coordinate, tolerance_pixels=1):
        rect = observation['mapRect']
        centre = [rect['x'] + rect['width'] / 2, rect['y'] + rect['height'] / 2]
        for tile in observation['tiles']:
            match = re.search(r'/seamlessphoto/(\d+)/(\d+)/(\d+)\.jpg', tile['src'])
            if not match or not (tile['x'] <= centre[0] < tile['x'] + tile['width']
                                and tile['y'] <= centre[1] < tile['y'] + tile['height']):
                continue
            zoom, column, row = map(int, match.groups())
            if tile['width'] <= 0 or abs(tile['width'] - tile['height']) > .01:
                raise ValueError('photo tile requires its actual square screen rectangle')
            scale = 256 / tile['width']
            result = cls(256 * 2 ** zoom, column * 256 - tile['x'] * scale,
                         row * 256 - tile['y'] * scale, scale)
            target = result.wgs84_to_pixel(target_coordinate)
            if math.dist(target, centre) > tolerance_pixels:
                raise ValueError('rendered photo tiles do not match the requested target')
            return result
        raise ValueError('no observed photo tile covers the map centre')

    def pixel_to_wgs84(self, pixel):
        x = self.world_x_at_screen_zero + pixel[0] * self.world_pixels_per_screen_pixel
        y = self.world_y_at_screen_zero + pixel[1] * self.world_pixels_per_screen_pixel
        return [x / self.world_size * 360 - 180,
                math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / self.world_size))))]

    def wgs84_to_pixel(self, coordinate):
        longitude, latitude = coordinate
        x = (longitude + 180) / 360 * self.world_size
        y = (1 - math.asinh(math.tan(math.radians(latitude))) / math.pi) / 2 * self.world_size
        return [(x - self.world_x_at_screen_zero) / self.world_pixels_per_screen_pixel,
                (y - self.world_y_at_screen_zero) / self.world_pixels_per_screen_pixel]
