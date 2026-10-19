"""Bounded Apple Maps raster evidence, using NumPy and Pillow only.

Usage::

    result = analyze_corridor('basemap.png', bounds,
        corridor_wgs84=[[lon, lat], [lon, lat]],
        station_wgs84=[lon, lat], masks=[[left, top, right, bottom]])

``bounds`` is AX fullRegion (west/east/north/south), for a north-up,
zero-pitch screenshot. Coordinates are [longitude, latitude]. Masks and trace
points use screenshot pixels. This module returns candidates, never changes
railway data. Dark glyph pairs identify the rendered railway body, not gauge,
individual physical rails, or a surveyed platform midpoint. Unsupported trace
samples remain explicit. A broad frame cannot establish a station anchor.
The footprint palette supports the inspected dark Explore basemap only.
Bounds alone cannot verify camera orientation: callers must supply paired AX
heading/pitch when nonzero; rotated or tilted views are rejected.
"""
import math

import numpy as np
from PIL import Image


def _mercator(latitude):
    return math.log(math.tan(math.pi / 4 + math.radians(latitude) / 2))


def pixel_to_wgs84(pixel, bounds, size):
    width, height = size
    x, y = pixel
    north, south = _mercator(bounds['north']), _mercator(bounds['south'])
    m = north + (south - north) * y / height
    return [bounds['west'] + (bounds['east'] - bounds['west']) * x / width,
            math.degrees(2 * math.atan(math.exp(m)) - math.pi / 2)]


def wgs84_to_pixel(coordinate, bounds, size):
    width, height = size
    lon, lat = coordinate
    north, south = _mercator(bounds['north']), _mercator(bounds['south'])
    return [(lon - bounds['west']) / (bounds['east'] - bounds['west']) * width,
            (_mercator(lat) - north) / (south - north) * height]


def _sample(raster, points, valid):
    """Bilinear values; a mask crossing any contributing pixel invalidates it."""
    h, w = raster.shape[:2]
    x, y = points[..., 0], points[..., 1]
    inside = (x >= 0) & (x < w - 1) & (y >= 0) & (y < h - 1)
    ix = np.floor(np.clip(x, 0, w - 2)).astype(int)
    iy = np.floor(np.clip(y, 0, h - 2)).astype(int)
    fx, fy = x - ix, y - iy
    values = ((1 - fx) * (1 - fy) * raster[iy, ix]
              + fx * (1 - fy) * raster[iy, ix + 1]
              + (1 - fx) * fy * raster[iy + 1, ix]
              + fx * fy * raster[iy + 1, ix + 1])
    good = (inside & valid[iy, ix] & valid[iy + 1, ix]
            & valid[iy, ix + 1] & valid[iy + 1, ix + 1])
    return values, good


def _resample(points, step):
    points = np.asarray(points, dtype=float)
    lengths = np.linalg.norm(np.diff(points, axis=0), axis=1)
    cumulative = np.r_[0, np.cumsum(lengths)]
    if len(points) < 2 or cumulative[-1] < step:
        raise ValueError('corridor needs two distinct points spanning at least one step')
    keep = np.r_[True, lengths > 1e-8]
    points, cumulative = points[keep], cumulative[keep]
    measures = np.arange(0, cumulative[-1] + .01, step)
    samples = np.stack([np.interp(measures, cumulative, points[:, axis])
                        for axis in (0, 1)], axis=1)
    before = np.maximum(0, measures - 12)
    after = np.minimum(cumulative[-1], measures + 12)
    tangents = np.stack([np.interp(after, cumulative, points[:, axis])
                         - np.interp(before, cumulative, points[:, axis])
                         for axis in (0, 1)], axis=1)
    tangents /= np.linalg.norm(tangents, axis=1)[:, None]
    return samples, tangents


def _platform(rgb, valid, trace, station, scale):
    if station is None:
        return {'status': 'no_anchor', 'reason': 'station_seed_not_supplied'}
    if scale > 1.25:
        return {'status': 'no_anchor', 'reason': 'insufficient_platform_resolution'}
    observed = [row for row in trace if row['supported']]
    if len(observed) < 8:
        return {'status': 'no_anchor', 'reason': 'railway_not_resolved'}
    points = np.array([row['pixel'] for row in observed])
    nearest = np.argmin(np.linalg.norm(points - station, axis=1))
    centre = points[nearest]
    low, high = max(0, nearest - 5), min(len(points) - 1, nearest + 5)
    tangent = points[high] - points[low]
    tangent /= np.linalg.norm(tangent)
    normal = np.array([-tangent[1], tangent[0]])
    h, w = rgb.shape[:2]
    radius = int(math.ceil(100 / scale))
    left, right = max(0, int(centre[0]) - radius), min(w, int(centre[0]) + radius + 1)
    top, bottom = max(0, int(centre[1]) - radius), min(h, int(centre[1]) + radius + 1)
    yy, xx = np.mgrid[top:bottom, left:right]
    delta = np.stack([xx - centre[0], yy - centre[1]], axis=-1)
    along, across = delta @ tangent, delta @ normal
    r, g, b = np.moveaxis(rgb[top:bottom, left:right], -1, 0)
    blue = ((g - r > 8) & (b - g > 5) & (r > 45) & (r < 160)
            & valid[top:bottom, left:right] & (abs(across) < 30 / scale))
    # Bridge only thin dark glyph holes; do not join blue buildings across roads.
    bridged = blue.copy()
    for dy, dx in ((0, 3), (3, 0), (0, 2), (2, 0), (0, 1), (1, 0)):
        shifted1 = np.zeros_like(blue)
        shifted2 = np.zeros_like(blue)
        if dx:
            shifted1[:, dx:] = bridged[:, :-dx]
            shifted2[:, :-dx] = bridged[:, dx:]
        else:
            shifted1[dy:] = bridged[:-dy]
            shifted2[:-dy] = bridged[dy:]
        dark_hole = (r * .2126 + g * .7152 + b * .0722 < 70)
        bridged |= (shifted1 & shifted2 & dark_hole & (abs(across) < 6 / scale)
                    & valid[top:bottom, left:right])
    visited = np.zeros_like(blue)
    candidates = []
    for sy, sx in zip(*np.nonzero(bridged & (abs(across) < 8 / scale)
                                        & (abs(along) < 35 / scale))):
        if visited[sy, sx]:
            continue
        stack, component = [(int(sy), int(sx))], []
        visited[sy, sx] = True
        while stack:
            y, x = stack.pop()
            component.append((x + left, y + top))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if (0 <= ny < blue.shape[0] and 0 <= nx < blue.shape[1]
                        and bridged[ny, nx] and not visited[ny, nx]):
                    visited[ny, nx] = True
                    stack.append((ny, nx))
        if len(component) < 50:
            continue
        vertices = np.asarray(component, float)
        offsets = vertices - centre
        a, c = offsets @ tangent, offsets @ normal
        length, width = np.ptp(a) * scale, np.ptp(c) * scale
        # A component hitting the sampling window has no independent end.
        bounded = (a.min() > -95 / scale and a.max() < 95 / scale
                   and vertices[:, 0].min() > left and vertices[:, 0].max() < right - 1
                   and vertices[:, 1].min() > top and vertices[:, 1].max() < bottom - 1)
        midpoint = (c.min() + c.max()) / 2
        axis = np.linalg.eigh(np.cov(vertices.T))[1][:, -1]
        if (bounded and 25 <= length <= 180 and 4 <= width <= 35
                and length / width >= 2.5 and abs(axis @ tangent) >= .94
                and abs(midpoint) * scale < width * .25
                and a.min() <= 0 <= a.max()):
            pixel = centre + tangent * ((a.min() + a.max()) / 2) + normal * midpoint
            corners = [centre + tangent * aa + normal * cc
                       for aa, cc in ((a.min(), c.min()), (a.max(), c.min()),
                                      (a.max(), c.max()), (a.min(), c.max()))]
            candidates.append({'pixel': pixel.tolist(), 'bounds_pixels': [p.tolist() for p in corners],
                               'length_metres': float(length), 'width_metres': float(width),
                               'confidence': 'bounded_image_footprint'})
    if len(candidates) != 1:
        return {'status': 'no_anchor', 'reason': ('ambiguous_platform_components' if candidates
                                                 else 'independent_platform_bounds_not_resolved'),
                'candidate_count': len(candidates)}
    return {'status': 'candidate', **candidates[0]}


def analyze_corridor(image, bounds, *, corridor_wgs84=None, corridor_pixels=None,
                     station_wgs84=None, masks=(), search_metres=40, step_pixels=4,
                     heading=0, pitch=0):
    """Extract a continuous dark railway-glyph pair and optional station footprint.

    Confidence is image support, not a claim of physical track identity.
    A rough corridor and explicit UI masks should come from the paired frame.
    """
    if corridor_pixels is None and corridor_wgs84 is None:
        raise ValueError('provide corridor_pixels or corridor_wgs84')
    if abs(heading) > .01 or abs(pitch) > .01:
        raise ValueError('north-up, zero-pitch AX fullRegion is required')
    if not (-85 < bounds['south'] < bounds['north'] < 85
            and -180 <= bounds['west'] < bounds['east'] <= 180):
        raise ValueError('bounds must be ordered, finite Mercator coordinates')
    if step_pixels <= 0 or search_metres <= 0:
        raise ValueError('step and search range must be positive')
    raster = image if isinstance(image, Image.Image) else Image.open(image)
    rgb = np.asarray(raster.convert('RGB'), dtype=float)
    h, w = rgb.shape[:2]
    valid = np.ones((h, w), bool)
    for left, top, right, bottom in masks:
        valid[max(0, int(top)):min(h, int(bottom)), max(0, int(left)):min(w, int(right))] = False
    latitude = (bounds['north'] + bounds['south']) / 2
    scale = ((bounds['east'] - bounds['west']) * 111320
             * math.cos(math.radians(latitude)) / w)
    points = (corridor_pixels if corridor_pixels is not None else
              [wgs84_to_pixel(p, bounds, (w, h)) for p in corridor_wgs84])
    centres, tangents = _resample(points, step_pixels)
    normals = np.stack([-tangents[:, 1], tangents[:, 0]], axis=1)
    offsets = np.arange(-math.ceil(search_metres / scale), math.ceil(search_metres / scale) + 1)
    luminance = rgb @ np.array([.2126, .7152, .0722])
    scores = np.full((len(centres), len(offsets)), -1e4)
    contrasts = np.zeros_like(scores)
    separations = np.zeros_like(scores)
    for spacing in range(2, 21):
        at = centres[:, None, :] + normals[:, None, :] * offsets[None, :, None]
        values, good = [], []
        for displacement in (-spacing / 2, spacing / 2, -spacing / 2 - 2,
                             spacing / 2 + 2, 0):
            samples, support = [], []
            for longitudinal in (-3, -1, 1, 3):
                sample, ok = _sample(luminance, at + normals[:, None, :] * displacement
                                     + tangents[:, None, :] * longitudinal, valid)
                samples.append(sample)
                support.append(ok)
            values.append(np.mean(samples, axis=0))
            good.append(np.logical_and.reduce(support))
        left, right, outer_left, outer_right, middle = values
        contrast = np.minimum(outer_left - left, outer_right - right)
        contrast = np.minimum(contrast, middle - np.maximum(left, right))
        score = contrast - .05 * abs(left - right) - .01 * abs(offsets)[None, :]
        supported = np.logical_and.reduce(good) & (np.maximum(left, right) < 70)
        score = np.where(supported, score, -1e4)
        better = score > scores
        scores[better], contrasts[better], separations[better] = score[better], contrast[better], spacing
    # Unsupported samples carry no image reward; continuity bridges them only
    # as a explicitly marked proposal, never observed evidence.
    rewards = np.maximum(scores, 0)
    dp = rewards[0] - .01 * abs(offsets)
    back = np.zeros(scores.shape, int)
    transition = .22 * abs(offsets[:, None] - offsets[None, :])
    for i in range(1, len(centres)):
        spacing_penalty = .08 * abs(separations[i - 1, :, None] - separations[i, None, :])
        spacing_penalty *= ((contrasts[i - 1, :, None] >= 4) & (contrasts[i, None, :] >= 4))
        previous = dp[:, None] - transition - spacing_penalty
        back[i] = previous.argmax(axis=0)
        dp = previous.max(axis=0) + rewards[i]
    chosen = np.empty(len(centres), int)
    chosen[-1] = dp.argmax()
    for i in range(len(centres) - 1, 0, -1):
        chosen[i - 1] = back[i, chosen[i]]
    trace = []
    for i, index in enumerate(chosen):
        point = centres[i] + normals[i] * offsets[index]
        contrast = float(contrasts[i, index])
        rivals = scores[i, abs(offsets - offsets[index]) > 10]
        rival = max(0., float(rivals.max())) if len(rivals) else 0.
        supported = bool(contrast >= 4 and scores[i, index] > -100)
        trace.append({'pixel': point.tolist(), 'coordinate': pixel_to_wgs84(point, bounds, (w, h)),
                      'offset_pixels': float(offsets[index]), 'pair_spacing_pixels': float(separations[i, index]),
                      'contrast': contrast, 'supported': supported,
                      'ambiguity': float(max(0., rival / max(contrast, 1e-6)))})
    support = sum(row['supported'] for row in trace) / len(trace)
    observed = [row for row in trace if row['supported']]
    median_ambiguity = float(np.median([r['ambiguity'] for r in observed])) if observed else 1.
    station = (None if station_wgs84 is None else
               np.array(wgs84_to_pixel(station_wgs84, bounds, (w, h))))
    platform = _platform(rgb, valid, trace, station, scale)
    alignment = {'status': 'no_candidate', 'reason': 'station_seed_not_supplied'}
    if station is not None:
        normal = normals[np.argmin(np.linalg.norm(centres - station, axis=1))]
        candidates = []
        for a, b in zip(trace, trace[1:]):
            if not (a['supported'] and b['supported'] and a['ambiguity'] < .8 and b['ambiguity'] < .8):
                continue
            start, end = np.array(a['pixel']), np.array(b['pixel'])
            segment = end - start
            cross = segment[0] * normal[1] - segment[1] * normal[0]
            if abs(cross) < 1e-8:
                continue
            delta = station - start
            fraction = (delta[0] * normal[1] - delta[1] * normal[0]) / cross
            if 0 <= fraction <= 1:
                point = start + fraction * segment
                displacement = float((point - station) @ normal * scale)
                if abs(displacement) <= search_metres:
                    candidates.append((abs(displacement), point, displacement, a, b))
        alignment = {'status': 'no_candidate', 'reason': 'local_supported_trace_not_resolved'}
        if candidates:
            _, point, displacement, a, b = min(candidates, key=lambda c: c[0])
            alignment = {'status': 'candidate', 'kind': 'transverse_railway_alignment_only',
                         'pixel': point.tolist(), 'coordinate': pixel_to_wgs84(point, bounds, (w, h)),
                         'transverse_displacement_metres': displacement,
                         'support_pixels': [a['pixel'], b['pixel']],
                         'contrast': min(a['contrast'], b['contrast']),
                         'ambiguity': max(a['ambiguity'], b['ambiguity'])}
    if platform['status'] == 'candidate':
        platform['coordinate'] = pixel_to_wgs84(platform['pixel'], bounds, (w, h))
        platform['bounds_wgs84'] = [pixel_to_wgs84(p, bounds, (w, h)) for p in platform['bounds_pixels']]
    return {'trace': trace, 'support_fraction': support,
            'median_contrast': float(np.median([r['contrast'] for r in observed])) if observed else 0.,
            'median_ambiguity': median_ambiguity,
            'rail_confidence': ('insufficient_image_support' if support < .65 else
                                'ambiguous_image_trace' if median_ambiguity >= .8 else
                                'supported_image_trace'),
            'scale_metres_per_pixel': float(scale), 'platform': platform,
            'station_alignment': alignment}
