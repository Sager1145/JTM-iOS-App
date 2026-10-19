#!/usr/bin/env python3
"""Compare a reconstructed jp network with MLIT N02 snapshot geometry.

For each release year the current package plus app/data/rail-history.json is
evaluated on two probe dates. The result is a discovery report: snapshot
geometry with no reconstruction cover is missing, reconstruction geometry
active on both probes with no snapshot cover is extra, and covered geometry
whose operator or line name disagrees is an identity mismatch. Nothing here
is an exact opening or closure date.

Overlay application follows docs/rail-history.md (half-open service intervals;
a retirement stamps current features whose line and operator match and whose
every coordinate lies in the bbox; match.targets limits sections or stations).
"""

from __future__ import annotations

import argparse
import gzip
import importlib.util
import json
import math
import re
import sys
import time
import unicodedata
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[4]
DEFAULT_SECTIONS = ROOT / 'app' / 'data' / 'rail-sections.json'
DEFAULT_STATIONS = ROOT / 'app' / 'data' / 'stations.json'
DEFAULT_HISTORY = ROOT / 'app' / 'data' / 'rail-history.json'
SNAPSHOT_DIR = Path(
    '/Users/sager/Documents/GitHub/Japan-Train-Map/app/data/raw/railway/jp/history')
SNAPSHOT_N02_25 = SNAPSHOT_DIR.parent / 'N02-25_GML.zip'

DENSIFY_M = 25.0
COVER_M = 40.0
RUN_MIN_M = 300.0
IDENTITY_MIN_M = 500.0
STATION_NAME_M = 300.0
RENAME_M = 150.0
CELL_DEG = 0.001
EARTH_R = 6_371_008.8
LAT_M = EARTH_R * math.pi / 180.0
_WS = re.compile(r'\s+', re.UNICODE)
_INVENTORY = None


def inventory_module():
    global _INVENTORY
    if _INVENTORY is None:
        path = Path(__file__).with_name('inventory-jp-history.py')
        spec = importlib.util.spec_from_file_location('inventory_jp_history', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _INVENTORY = module
    return _INVENTORY


def normalize_label(value):
    """Fold full/half width and remove spaces so identity checks share a key."""
    if value is None:
        return ''
    return _WS.sub('', unicodedata.normalize('NFKC', str(value)))


def railway_class(institution, line_name):
    """Shinkansen (N02_002 == 1, or a line name that says 新幹線) vs everything else."""
    if str(institution or '').strip() == '1':
        return 'shinkansen'
    if line_name and '新幹線' in str(line_name):
        return 'shinkansen'
    return 'conventional'


def haversine(lon1, lat1, lon2, lat2):
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (math.sin(dphi / 2.0) ** 2
         + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2)
    return 2.0 * EARTH_R * math.asin(min(1.0, math.sqrt(a)))


def offset_metres(lon, lat, east_m=0.0, north_m=0.0):
    lon_scale = LAT_M * math.cos(math.radians(lat))
    return (lon + (east_m / lon_scale if lon_scale else 0.0),
            lat + north_m / LAT_M)


def line_east(lon, lat, length_m):
    end_lon, end_lat = offset_metres(lon, lat, length_m, 0.0)
    return [[float(lon), float(lat)], [end_lon, end_lat]]


def _clean_date(value):
    if value is None or value == '':
        return None
    return str(value)


def service_bounds(source):
    """Half-open service interval. service_validity wins; a lone infrastructure pair is the service interval."""
    if not isinstance(source, dict):
        return None, None
    service = source.get('service_validity') if 'service_validity' in source else None
    if isinstance(service, (list, tuple)) and len(service) == 2:
        return _clean_date(service[0]), _clean_date(service[1])
    start = _clean_date(source.get('valid_from'))
    end = _clean_date(source.get('valid_to'))
    if start is None and end is None and 'infrastructure_validity' in source:
        infra = source.get('infrastructure_validity')
        if isinstance(infra, (list, tuple)) and len(infra) == 2:
            return _clean_date(infra[0]), _clean_date(infra[1])
    return start, end


def active_on(source, day):
    """True on valid_from and false on valid_to."""
    start, end = service_bounds(source)
    if start is not None and day < start:
        return False
    if end is not None and day >= end:
        return False
    return True


def prop_line(props):
    return props.get('N02_003') or props.get('line_name') or ''


def prop_operator(props):
    return props.get('N02_004') or props.get('operator') or ''


def prop_station(props):
    return props.get('station_name') or props.get('N02_005') or ''


def iter_lonlat(geometry):
    if not geometry:
        return
    kind = geometry.get('type')
    coords = geometry.get('coordinates')
    if kind == 'Point':
        if isinstance(coords, (list, tuple)) and len(coords) >= 2 and not isinstance(coords[0], (list, tuple)):
            yield float(coords[0]), float(coords[1])
        return
    if kind == 'MultiPoint':
        for point in coords or []:
            if len(point) >= 2:
                yield float(point[0]), float(point[1])
        return
    if kind == 'LineString':
        for point in _line_points(coords):
            yield point
        return
    if kind == 'MultiLineString':
        for line in coords or []:
            for point in _line_points(line):
                yield point


def _line_points(coords):
    if not coords:
        return
    if isinstance(coords[0], (int, float)):
        coords = [coords]
    for point in coords:
        if isinstance(point, (list, tuple)) and len(point) >= 2:
            yield float(point[0]), float(point[1])


def line_parts(geometry):
    if not geometry:
        return []
    kind = geometry.get('type')
    coords = geometry.get('coordinates')
    if kind == 'LineString':
        points = list(_line_points(coords))
        return [points] if len(points) >= 2 else []
    if kind == 'MultiLineString':
        parts = []
        for line in coords or []:
            points = list(_line_points(line))
            if len(points) >= 2:
                parts.append(points)
        return parts
    return []


def _inside_bbox(geometry, bbox):
    if not bbox or len(bbox) != 4:
        return False
    min_lon, min_lat, max_lon, max_lat = bbox
    seen = False
    for lon, lat in iter_lonlat(geometry):
        seen = True
        if lon < min_lon or lon > max_lon or lat < min_lat or lat > max_lat:
            return False
    return seen


def _targets_allow(match, kind):
    targets = match.get('targets')
    if not targets:
        return True
    return kind in targets


def _feature_matches(feature, match):
    props = feature.get('properties') or {}
    if prop_line(props) != match.get('line_name'):
        return False
    if prop_operator(props) != match.get('operator'):
        return False
    if match.get('station_name') is not None and prop_station(props) != match['station_name']:
        return False
    return _inside_bbox(feature.get('geometry'), match.get('bbox'))


def _clone_feature(feature):
    return {
        'type': feature.get('type', 'Feature'),
        'properties': dict(feature.get('properties') or {}),
        'geometry': feature.get('geometry'),
    }


def _identity_variants(feature, periods, target):
    if not periods:
        return [feature]
    base_from, base_to = service_bounds(feature.get('properties') or {})

    def later(a, b):
        return max(a, b) if a is not None and b is not None else a or b

    def earlier(a, b):
        if a is None:
            return b
        if b is None:
            return a
        return min(a, b)

    def nonempty(a, b):
        return a is None or b is None or a < b

    pieces = []
    cursor = base_from
    for period in sorted(periods, key=lambda item: item.get('valid_from') or ''):
        start = later(base_from, period.get('valid_from'))
        end = earlier(base_to, period['valid_to'])
        if not nonempty(start, end):
            continue
        gap_end = earlier(base_to, start)
        if cursor != gap_end and nonempty(cursor, gap_end):
            pieces.append((cursor, gap_end, None))
        pieces.append((start, end, period))
        cursor = later(cursor, period['valid_to'])
    if cursor != base_to and nonempty(cursor, base_to):
        pieces.append((cursor, base_to, None))

    result = []
    for start, end, period in pieces:
        copy = _clone_feature(feature)
        props = copy['properties']
        props['service_validity'] = [start, end]
        props.pop('infrastructure_validity', None)
        if period:
            identity = period['as']
            if target == 'sections':
                props['N02_003'], props['N02_004'] = identity['N02_003'], identity['N02_004']
            else:
                props['line_name'], props['operator'] = identity['N02_003'], identity['N02_004']
                if identity.get('N02_005'):
                    props['station_name'] = identity['N02_005']
            props['history_id'] = period['history_id']
        result.append(copy)
    return result


def apply_overlay(sections, stations, overlay):
    """Stamp retirement intervals onto current features and append overlay features.

    Mirrors the v1 loader: a later stamp overwrites a bound it sets and leaves
    the other bound alone. valid_from also records history_id when the feature
    does not already have one.
    """
    sections = [_clone_feature(feature) for feature in sections]
    stations = [_clone_feature(feature) for feature in stations]
    unmatched = []
    for retirement in (overlay or {}).get('retirements') or []:
        match = retirement.get('match') or {}
        start, end = service_bounds(retirement)
        matched = 0
        for kind, features in (('sections', sections), ('stations', stations)):
            if not _targets_allow(match, kind):
                continue
            for feature in features:
                if not _feature_matches(feature, match):
                    continue
                matched += 1
                props = feature['properties']
                if start is not None:
                    props['valid_from'] = start
                    if not props.get('history_id') and retirement.get('history_id'):
                        props['history_id'] = retirement['history_id']
                if end is not None:
                    props['valid_to'] = end
                if 'service_validity' in retirement:
                    props['service_validity'] = retirement['service_validity']
                if 'infrastructure_validity' in retirement:
                    props['infrastructure_validity'] = retirement['infrastructure_validity']
        if matched == 0:
            unmatched.append(retirement.get('history_id'))
    identity_periods = (overlay or {}).get('identity_periods') or []
    outputs = []
    for kind, features in (('sections', sections), ('stations', stations)):
        variants = []
        for feature in features:
            matching = [period for period in identity_periods
                        if _targets_allow(period.get('match') or {}, kind)
                        and _feature_matches(feature, period.get('match') or {})]
            variants.extend(_identity_variants(feature, matching, kind))
        outputs.append(variants)
    sections, stations = outputs
    for feature in (overlay or {}).get('sections') or []:
        sections.append(_clone_feature(feature))
    for feature in (overlay or {}).get('stations') or []:
        stations.append(_clone_feature(feature))
    return sections, stations, unmatched


def _crossed_cells(ax, ay, bx, by, cell):
    """Grid cells the segment passes through (Amanatides & Woo)."""
    ix = math.floor(ax / cell)
    iy = math.floor(ay / cell)
    ix1 = math.floor(bx / cell)
    iy1 = math.floor(by / cell)
    yield ix, iy
    if ix == ix1 and iy == iy1:
        return
    dx = bx - ax
    dy = by - ay
    step_x = 1 if dx > 0 else -1 if dx < 0 else 0
    step_y = 1 if dy > 0 else -1 if dy < 0 else 0
    inf = math.inf
    tdx = abs(cell / dx) if step_x else inf
    tdy = abs(cell / dy) if step_y else inf
    if step_x > 0:
        tmax_x = ((ix + 1) * cell - ax) / dx
    elif step_x < 0:
        tmax_x = (ix * cell - ax) / dx
    else:
        tmax_x = inf
    if step_y > 0:
        tmax_y = ((iy + 1) * cell - ay) / dy
    elif step_y < 0:
        tmax_y = (iy * cell - ay) / dy
    else:
        tmax_y = inf
    # A diagonal corner step can skip one cell; querying a 3x3 neighbourhood
    # still sees a segment within COVER_M, which is smaller than one cell.
    limit = abs(ix1 - ix) + abs(iy1 - iy) + 2
    for _ in range(limit):
        if tmax_x < tmax_y:
            ix += step_x
            tmax_x += tdx
        else:
            iy += step_y
            tmax_y += tdy
        yield ix, iy
        if ix == ix1 and iy == iy1:
            return
    yield ix1, iy1


class SegmentIndex:
    """Segment grid. A query reads the point's cell and its eight neighbours."""

    def __init__(self, cell=CELL_DEG):
        self.cell = cell
        self.ax = np.empty(0, dtype=np.float64)
        self.ay = np.empty(0, dtype=np.float64)
        self.bx = np.empty(0, dtype=np.float64)
        self.by = np.empty(0, dtype=np.float64)
        self.eid = np.empty(0, dtype=np.int32)
        self.buckets = {}

    def build(self, polylines):
        """polylines: iterable of (coordinates, edge_id)."""
        ax, ay, bx, by, eid = [], [], [], [], []
        buckets = defaultdict(list)
        for coordinates, edge_id in polylines:
            for (x0, y0), (x1, y1) in zip(coordinates, coordinates[1:]):
                if x0 == x1 and y0 == y1:
                    continue
                index = len(eid)
                ax.append(x0)
                ay.append(y0)
                bx.append(x1)
                by.append(y1)
                eid.append(edge_id)
                seen = set()
                for key in _crossed_cells(x0, y0, x1, y1, self.cell):
                    if key not in seen:
                        seen.add(key)
                        buckets[key].append(index)
        self.ax = np.asarray(ax, dtype=np.float64)
        self.ay = np.asarray(ay, dtype=np.float64)
        self.bx = np.asarray(bx, dtype=np.float64)
        self.by = np.asarray(by, dtype=np.float64)
        self.eid = np.asarray(eid, dtype=np.int32)
        self.buckets = {key: np.asarray(value, dtype=np.int32) for key, value in buckets.items()}

    def nearest(self, points, limit_m=COVER_M):
        """Return an edge id per point, or -1 when nothing is within limit_m."""
        count = int(points.shape[0])
        out = np.full(count, -1, dtype=np.int32)
        if count == 0 or self.eid.size == 0:
            return out
        groups = defaultdict(list)
        cell = self.cell
        for index, (x, y) in enumerate(points):
            groups[(math.floor(float(x) / cell), math.floor(float(y) / cell))].append(index)
        for (cx, cy), members in groups.items():
            parts = []
            for ox in (-1, 0, 1):
                for oy in (-1, 0, 1):
                    hit = self.buckets.get((cx + ox, cy + oy))
                    if hit is not None and hit.size:
                        parts.append(hit)
            if not parts:
                continue
            seg_idx = np.unique(np.concatenate(parts))
            pidx = np.asarray(members, dtype=np.int32)
            self._assign_nearest(points, pidx, seg_idx, out, limit_m)
        return out

    def _assign_nearest(self, points, pidx, seg_idx, out, limit_m):
        chunk = 4096
        for start in range(0, pidx.size, chunk):
            sub = pidx[start:start + chunk]
            distances = _segment_distances(
                points[sub, 0], points[sub, 1],
                self.ax[seg_idx], self.ay[seg_idx], self.bx[seg_idx], self.by[seg_idx])
            choice = np.argmin(distances, axis=1)
            best = distances[np.arange(sub.size), choice]
            keep = best <= limit_m
            if np.any(keep):
                out[sub[keep]] = self.eid[seg_idx[choice[keep]]]


def _segment_distances(px, py, ax, ay, bx, by):
    lon_scale = LAT_M * np.cos(np.radians(py))
    pax = (px[:, None] - ax[None, :]) * lon_scale[:, None]
    pay = (py[:, None] - ay[None, :]) * LAT_M
    bax = (bx[None, :] - ax[None, :]) * lon_scale[:, None]
    bay = (by[None, :] - ay[None, :]) * LAT_M
    denom = np.maximum(bax * bax + bay * bay, 1e-12)
    t = np.clip((pax * bax + pay * bay) / denom, 0.0, 1.0)
    return np.hypot(pax - t * bax, pay - t * bay)


def densify(coordinates, step_m=DENSIFY_M):
    if not coordinates:
        return []
    first = (float(coordinates[0][0]), float(coordinates[0][1]))
    if len(coordinates) == 1:
        return [first]
    out = [first]
    for raw_a, raw_b in zip(coordinates, coordinates[1:]):
        ax, ay = float(raw_a[0]), float(raw_a[1])
        bx, by = float(raw_b[0]), float(raw_b[1])
        dist = haversine(ax, ay, bx, by)
        if dist <= step_m:
            point = (bx, by)
            if point != out[-1]:
                out.append(point)
            continue
        steps = int(math.ceil(dist / step_m))
        for step in range(1, steps + 1):
            t = step / steps
            out.append((ax + (bx - ax) * t, ay + (by - ay) * t))
    return out


def path_length(points):
    total = 0.0
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        total += haversine(ax, ay, bx, by)
    return total


def _bbox(points):
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def _round_bbox(bbox):
    return [round(float(value), 6) for value in bbox]


def _midpoint(points):
    if len(points) == 1:
        return points[0]
    target = path_length(points) / 2.0
    walked = 0.0
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        dist = haversine(ax, ay, bx, by)
        if dist > 0 and walked + dist >= target:
            t = (target - walked) / dist
            return (ax + (bx - ax) * t, ay + (by - ay) * t)
        walked += dist
    return points[-1]


def _collect_sections(features, d1, d2, dated):
    edges = []
    for feature in features:
        props = feature.get('properties') or {}
        if dated:
            on_d1 = active_on(props, d1)
            on_d2 = active_on(props, d2)
            if not on_d1 and not on_d2:
                continue
        else:
            on_d1 = on_d2 = True
        line = prop_line(props)
        operator = prop_operator(props)
        institution = props.get('N02_002', props.get('institution_type_code'))
        kind = railway_class(institution, line)
        history_id = props.get('history_id')
        for part in line_parts(feature.get('geometry')):
            edges.append({
                'operator': operator,
                'line_name': line,
                'class': kind,
                'coordinates': part,
                'active_d1': on_d1,
                'active_d2': on_d2,
                'history_id': history_id,
            })
    return edges


def _collect_stations(features, d1, d2, dated):
    rows = []
    for feature in features:
        props = feature.get('properties') or {}
        if dated:
            on_d1 = active_on(props, d1)
            on_d2 = active_on(props, d2)
            if not on_d1 and not on_d2:
                continue
        else:
            on_d1 = on_d2 = True
        points = list(iter_lonlat(feature.get('geometry')))
        if not points:
            continue
        lon = sum(point[0] for point in points) / len(points)
        lat = sum(point[1] for point in points) / len(points)
        rows.append({
            'station_name': prop_station(props),
            'operator': prop_operator(props),
            'line_name': prop_line(props),
            'lon': lon,
            'lat': lat,
            'active_d1': on_d1,
            'active_d2': on_d2,
            'history_id': props.get('history_id'),
        })
    return rows


def _build_indexes(edges):
    grouped = {'shinkansen': [], 'conventional': []}
    for edge_id, edge in enumerate(edges):
        grouped[edge['class']].append((edge['coordinates'], edge_id))
    indexes = {}
    for kind, polylines in grouped.items():
        index = SegmentIndex()
        index.build(polylines)
        indexes[kind] = index
    return indexes


def _point_array(chunks):
    """chunks: list of (edge_id, points). Returns (array, spans)."""
    spans = []
    flat = []
    for edge_id, points in chunks:
        start = len(flat)
        flat.extend(points)
        spans.append((edge_id, start, len(flat)))
    if not flat:
        return np.empty((0, 2), dtype=np.float64), spans
    return np.asarray(flat, dtype=np.float64), spans


def _uncovered_runs(points, nearest):
    runs = []
    index = 0
    count = len(points)
    while index < count:
        if nearest[index] >= 0:
            index += 1
            continue
        end = index
        while end + 1 < count and nearest[end + 1] < 0:
            end += 1
        run_points = points[index:end + 1]
        length = path_length(run_points)
        if length >= RUN_MIN_M:
            runs.append((run_points, length))
        index = end + 1
    return runs


def _aggregate_runs(runs, with_history):
    groups = {}
    for run in runs:
        key = (run['operator'], run['line_name'], run['class'])
        group = groups.get(key)
        if group is None:
            group = {
                'length': 0.0,
                'runs': [],
                'history_ids': set(),
                'sample': run['sample'],
                'sample_len': run['length_m'],
                'bbox': list(run['bbox']),
            }
            groups[key] = group
        group['length'] += run['length_m']
        group['runs'].append({
            'bbox': _round_bbox(run['bbox']),
            'length_m': round(run['length_m'], 1),
        })
        if run.get('history_id'):
            group['history_ids'].add(run['history_id'])
        if run['length_m'] > group['sample_len']:
            group['sample_len'] = run['length_m']
            group['sample'] = run['sample']
        bbox = group['bbox']
        other = run['bbox']
        bbox[0] = min(bbox[0], other[0])
        bbox[1] = min(bbox[1], other[1])
        bbox[2] = max(bbox[2], other[2])
        bbox[3] = max(bbox[3], other[3])
    rows = []
    for (operator, line_name, kind), group in groups.items():
        sample = group['sample']
        row = {
            'operator': operator,
            'line_name': line_name,
            'class': kind,
            'length_m': round(group['length'], 1),
            'bbox': _round_bbox(group['bbox']),
            'sample': [round(float(sample[0]), 6), round(float(sample[1]), 6)],
            'runs': sorted(group['runs'], key=lambda item: (-item['length_m'], item['bbox'])),
        }
        if with_history:
            history_ids = sorted(group['history_ids'])
            if len(history_ids) == 1:
                row['history_id'] = history_ids[0]
            elif history_ids:
                row['history_ids'] = history_ids
        rows.append(row)
    rows.sort(key=lambda row: (-row['length_m'], row['operator'], row['line_name'], row['class']))
    return rows


def compare_sections(snapshot_edges, reconstruction_edges):
    """Missing uses reconstruction active on either probe. Extra requires both."""
    cover_indexes = _build_indexes(reconstruction_edges)
    snapshot_indexes = _build_indexes(snapshot_edges)
    missing_runs = []
    identity = {}
    identity_names = {}
    identity_cover = {}
    identity_groups = defaultdict(list)
    for edge_id, edge in enumerate(reconstruction_edges):
        key = (edge['class'], normalize_label(edge['operator']), normalize_label(edge['line_name']))
        identity_groups[key].append((edge['coordinates'], edge_id))
    for key, polylines in identity_groups.items():
        index = SegmentIndex()
        index.build(polylines)
        identity_cover[key] = index

    by_class = defaultdict(list)
    for edge_id, edge in enumerate(snapshot_edges):
        by_class[edge['class']].append((edge_id, densify(edge['coordinates'])))
    for kind, chunks in by_class.items():
        usable = [(edge_id, points) for edge_id, points in chunks if len(points) >= 2]
        array, spans = _point_array(usable)
        nearest = cover_indexes[kind].nearest(array)
        for edge_id, start, end in spans:
            edge = snapshot_edges[edge_id]
            points = [(float(row[0]), float(row[1])) for row in array[start:end]]
            ids = nearest[start:end]
            snap_key = (normalize_label(edge['operator']), normalize_label(edge['line_name']))
            same_identity = identity_cover.get((kind, *snap_key))
            same_ids = (same_identity.nearest(array[start:end]) if same_identity is not None
                        else np.full(end - start, -1, dtype=np.int32))
            for run_points, length in _uncovered_runs(points, ids):
                sample = _midpoint(run_points)
                missing_runs.append({
                    'operator': edge['operator'],
                    'line_name': edge['line_name'],
                    'class': edge['class'],
                    'length_m': length,
                    'bbox': _bbox(run_points),
                    'sample': sample,
                })
            for index in range(len(points) - 1):
                other_id = int(ids[index])
                if other_id < 0:
                    continue
                if int(same_ids[index]) >= 0:
                    continue
                other = reconstruction_edges[other_id]
                other_key = (normalize_label(other['operator']), normalize_label(other['line_name']))
                if snap_key == other_key:
                    continue
                pair = (snap_key, other_key)
                identity[pair] = identity.get(pair, 0.0) + haversine(
                    points[index][0], points[index][1], points[index + 1][0], points[index + 1][1])
                if pair not in identity_names:
                    identity_names[pair] = (
                        edge['operator'], edge['line_name'], other['operator'], other['line_name'])

    extra_runs = []
    both = [(edge_id, densify(edge['coordinates']))
            for edge_id, edge in enumerate(reconstruction_edges)
            if edge['active_d1'] and edge['active_d2']]
    by_class = defaultdict(list)
    for edge_id, points in both:
        if len(points) >= 2:
            by_class[reconstruction_edges[edge_id]['class']].append((edge_id, points))
    for kind, chunks in by_class.items():
        array, spans = _point_array(chunks)
        nearest = snapshot_indexes[kind].nearest(array)
        for edge_id, start, end in spans:
            edge = reconstruction_edges[edge_id]
            points = [(float(row[0]), float(row[1])) for row in array[start:end]]
            ids = nearest[start:end]
            for run_points, length in _uncovered_runs(points, ids):
                extra_runs.append({
                    'operator': edge['operator'],
                    'line_name': edge['line_name'],
                    'class': edge['class'],
                    'length_m': length,
                    'bbox': _bbox(run_points),
                    'sample': _midpoint(run_points),
                    'history_id': edge.get('history_id'),
                })

    mismatches = []
    for pair, length in identity.items():
        if length < IDENTITY_MIN_M:
            continue
        snap_op, snap_line, recon_op, recon_line = identity_names[pair]
        mismatches.append({
            'snapshot': {'operator': snap_op, 'line': snap_line},
            'reconstruction': {'operator': recon_op, 'line': recon_line},
            'length_m': round(length, 1),
        })
    mismatches.sort(key=lambda row: (
        -row['length_m'], row['snapshot']['operator'], row['snapshot']['line'],
        row['reconstruction']['operator'], row['reconstruction']['line']))
    return (
        _aggregate_runs(missing_runs, with_history=False),
        _aggregate_runs(extra_runs, with_history=True),
        mismatches,
    )


def _station_row(station, include_history):
    row = {
        'station_name': station['station_name'],
        'operator': station['operator'],
        'line_name': station['line_name'],
        'location': [round(station['lon'], 6), round(station['lat'], 6)],
    }
    if include_history and station.get('history_id'):
        row['history_id'] = station['history_id']
    return row


def _full_key(station):
    return (
        normalize_label(station['station_name']),
        normalize_label(station['operator']),
        normalize_label(station['line_name']),
    )


def compare_stations(snapshot_stations, reconstruction_stations):
    present = [station for station in reconstruction_stations
               if station['active_d1'] or station['active_d2']]
    by_full = defaultdict(list)
    by_name = defaultdict(list)
    for station in present:
        by_full[_full_key(station)].append(station)
        name = normalize_label(station['station_name'])
        if name:
            by_name[name].append(station)
    snap_ok = set()
    recon_ok = set()
    for index, station in enumerate(snapshot_stations):
        hits = by_full.get(_full_key(station))
        if not hits:
            continue
        snap_ok.add(index)
        for hit in hits:
            recon_ok.add(id(hit))
    for index, station in enumerate(snapshot_stations):
        if index in snap_ok:
            continue
        name = normalize_label(station['station_name'])
        if not name:
            continue
        for hit in by_name.get(name, ()):
            if haversine(station['lon'], station['lat'], hit['lon'], hit['lat']) <= STATION_NAME_M:
                snap_ok.add(index)
                recon_ok.add(id(hit))
    snap_by_name = defaultdict(list)
    for station in snapshot_stations:
        name = normalize_label(station['station_name'])
        if name:
            snap_by_name[name].append(station)
    for station in present:
        if id(station) in recon_ok:
            continue
        name = normalize_label(station['station_name'])
        if not name:
            continue
        for other in snap_by_name.get(name, ()):
            if haversine(station['lon'], station['lat'], other['lon'], other['lat']) <= STATION_NAME_M:
                recon_ok.add(id(station))
                break

    missing = [_station_row(station, False)
               for index, station in enumerate(snapshot_stations) if index not in snap_ok]
    extra = [_station_row(station, True)
             for station in present
             if station['active_d1'] and station['active_d2'] and id(station) not in recon_ok]
    missing.sort(key=lambda row: (row['operator'], row['line_name'], row['station_name'], row['location']))
    extra.sort(key=lambda row: (row['operator'], row['line_name'], row['station_name'], row['location']))
    renamed = _rename_candidates(
        [station for index, station in enumerate(snapshot_stations) if index not in snap_ok],
        [station for station in present if id(station) not in recon_ok])
    return missing, extra, renamed


def _rename_candidates(missing, reconstruction):
    cell = 0.002
    buckets = defaultdict(list)
    for index, station in enumerate(reconstruction):
        buckets[(math.floor(station['lon'] / cell), math.floor(station['lat'] / cell))].append(index)
    proposals = []
    for snap_index, station in enumerate(missing):
        cx = math.floor(station['lon'] / cell)
        cy = math.floor(station['lat'] / cell)
        best = None
        for ox in range(-2, 3):
            for oy in range(-2, 3):
                for recon_index in buckets.get((cx + ox, cy + oy), ()):
                    other = reconstruction[recon_index]
                    if normalize_label(station['operator']) != normalize_label(other['operator']):
                        continue
                    if normalize_label(station['station_name']) == normalize_label(other['station_name']):
                        continue
                    distance = haversine(station['lon'], station['lat'], other['lon'], other['lat'])
                    if distance <= RENAME_M and (best is None or distance < best[0]):
                        best = (distance, recon_index)
        if best is not None:
            proposals.append((best[0], snap_index, best[1]))
    proposals.sort()
    used_snap, used_recon = set(), set()
    rows = []
    for distance, snap_index, recon_index in proposals:
        if snap_index in used_snap or recon_index in used_recon:
            continue
        used_snap.add(snap_index)
        used_recon.add(recon_index)
        rows.append({
            'distance_m': round(distance, 1),
            'snapshot': _station_row(missing[snap_index], False),
            'reconstruction': _station_row(reconstruction[recon_index], True),
        })
    return rows


def default_probe_dates(year):
    return (f'{int(year):04d}-01-01', f'{int(year) + 1:04d}-03-31')


def resolve_probe_dates(year, overrides):
    if overrides:
        pair = overrides.get(str(year))
        if pair:
            return pair[0], pair[1]
    return default_probe_dates(year)


def compare_on_dates(snapshot_sections, snapshot_stations, current_sections,
                     current_stations, overlay, d1, d2):
    recon_sections, recon_stations, unmatched = apply_overlay(
        current_sections, current_stations, overlay)
    missing_sections, extra_sections, mismatches = compare_sections(
        _collect_sections(snapshot_sections, d1, d2, dated=False),
        _collect_sections(recon_sections, d1, d2, dated=True))
    missing_stations, extra_stations, renamed = compare_stations(
        _collect_stations(snapshot_stations, d1, d2, dated=False),
        _collect_stations(recon_stations, d1, d2, dated=True))
    return {
        'missing_sections': missing_sections,
        'extra_sections': extra_sections,
        'identity_mismatches': mismatches,
        'missing_stations': missing_stations,
        'extra_stations': extra_stations,
        'renamed_station_candidates': renamed,
        'totals': {
            'missing_km': round(sum(row['length_m'] for row in missing_sections) / 1000.0, 3),
            'extra_km': round(sum(row['length_m'] for row in extra_sections) / 1000.0, 3),
            'identity_km': round(sum(row['length_m'] for row in mismatches) / 1000.0, 3),
            'missing_stations': len(missing_stations),
            'extra_stations': len(extra_stations),
        },
        'unmatched_retirements': [item for item in unmatched if item],
    }


def _load_feature_collection(path):
    with open(path, encoding='utf-8') as handle:
        data = json.load(handle)
    if isinstance(data, dict) and isinstance(data.get('features'), list):
        return data['features']
    if isinstance(data, list):
        return data
    raise ValueError(f'{path} is not a FeatureCollection')


def _slim_snapshot(snapshot):
    sections = []
    for record in snapshot.get('sections') or []:
        attrs = record.get('attributes') or {}
        sections.append({
            'operator': attrs.get('operator') or '',
            'line_name': attrs.get('line_name') or '',
            'institution_type_code': attrs.get('institution_type_code'),
            'coordinates': record['geometry']['coordinates'],
        })
    stations = []
    for record in snapshot.get('stations') or []:
        attrs = record.get('attributes') or {}
        stations.append({
            'operator': attrs.get('operator') or '',
            'line_name': attrs.get('line_name') or '',
            'station_name': attrs.get('station_name') or '',
            'institution_type_code': attrs.get('institution_type_code'),
            'coordinates': record['geometry']['coordinates'],
        })
    return {
        'schema': 'jp-history-snapshot-cache-v1',
        'year': int(snapshot['observation']['value']),
        'sha256': snapshot['provenance']['sha256'],
        'sections': sections,
        'stations': stations,
    }


def _features_from_slim(slim):
    sections = [{
        'type': 'Feature',
        'properties': {
            'line_name': row['line_name'],
            'operator': row['operator'],
            'institution_type_code': row.get('institution_type_code'),
        },
        'geometry': {'type': 'LineString', 'coordinates': row['coordinates']},
    } for row in slim['sections']]
    stations = [{
        'type': 'Feature',
        'properties': {
            'station_name': row['station_name'],
            'line_name': row['line_name'],
            'operator': row['operator'],
            'institution_type_code': row.get('institution_type_code'),
        },
        'geometry': {'type': 'LineString', 'coordinates': row['coordinates']},
    } for row in slim['stations']]
    return sections, stations


def snapshot_catalog():
    module = inventory_module()
    paths = list(module.discover_inputs(SNAPSHOT_DIR))
    if SNAPSHOT_N02_25.is_file():
        paths.append(SNAPSHOT_N02_25)
    chosen = {}
    for path in paths:
        year = module.release_year(path.name)
        previous = chosen.get(year)
        if previous is None or ('_GML' in path.name and '_GML' not in previous.name):
            chosen[year] = path
    return chosen


def load_snapshot(path, cache_dir):
    module = inventory_module()
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    digest = module.file_sha256(path)
    cache_path = cache_dir / f'{module.release_label(path.name)}-{digest[:16]}.json.gz'
    if cache_path.is_file():
        with gzip.open(cache_path, 'rt', encoding='utf-8') as handle:
            return json.load(handle)
    print(f'parsing {path.name}', file=sys.stderr, flush=True)
    slim = _slim_snapshot(module.inventory_snapshot(path))
    temporary = cache_path.with_suffix(cache_path.suffix + '.tmp')
    with gzip.open(temporary, 'wt', encoding='utf-8') as handle:
        json.dump(slim, handle, ensure_ascii=False, separators=(',', ':'))
    temporary.replace(cache_path)
    return slim


def format_summary(report):
    lines = [
        f'{"year":<6} {"missing_km":>10} {"extra_km":>10} {"identity_km":>11} '
        f'{"missing_st":>10} {"extra_st":>8}',
    ]
    years = sorted(report['years'], key=int)
    for year in years:
        totals = report['years'][year]['totals']
        lines.append(
            f'{year:<6} {totals["missing_km"]:10.3f} {totals["extra_km"]:10.3f} '
            f'{totals["identity_km"]:11.3f} {totals["missing_stations"]:10d} '
            f'{totals["extra_stations"]:8d}')
    for year in years:
        block = report['years'][year]
        for label, key in (('missing', 'missing_sections'), ('extra', 'extra_sections')):
            lines.append(f'{year} top {label}')
            rows = block[key][:15]
            if not rows:
                lines.append('  (none)')
                continue
            for row in rows:
                lines.append(
                    f'  {row["length_m"] / 1000.0:8.3f} km  {row["operator"]}  '
                    f'{row["line_name"]}  {row["class"]}')
    return '\n'.join(lines)


def build_report(years, cache_dir, history_path, sections_path, stations_path, overrides):
    overlay = json.loads(Path(history_path).read_text(encoding='utf-8'))
    current_sections = _load_feature_collection(sections_path)
    current_stations = _load_feature_collection(stations_path)
    catalog = snapshot_catalog()
    missing_years = [year for year in years if year not in catalog]
    if missing_years:
        known = ', '.join(str(year) for year in sorted(catalog))
        raise SystemExit(f'no N02 snapshot for {missing_years}; available: {known}')
    probe_dates = {}
    year_reports = {}
    for year in years:
        started = time.perf_counter()
        d1, d2 = resolve_probe_dates(year, overrides)
        probe_dates[str(year)] = [d1, d2]
        slim = load_snapshot(catalog[year], cache_dir)
        snap_sections, snap_stations = _features_from_slim(slim)
        del slim
        print(f'{year}: snapshot sections {len(snap_sections)} stations {len(snap_stations)}',
              file=sys.stderr, flush=True)
        block = compare_on_dates(
            snap_sections, snap_stations, current_sections, current_stations, overlay, d1, d2)
        unmatched = block.pop('unmatched_retirements', [])
        if unmatched:
            print(f'{year}: unmatched retirements {len(unmatched)}', file=sys.stderr, flush=True)
        year_reports[str(year)] = block
        totals = block['totals']
        print(
            f'{year}: done in {time.perf_counter() - started:.1f}s '
            f'missing_km={totals["missing_km"]} extra_km={totals["extra_km"]} '
            f'identity_km={totals["identity_km"]}',
            file=sys.stderr, flush=True)
    return {
        'schema_version': 1,
        'generated_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'overlay_revision': overlay.get('revision'),
        'probe_dates': probe_dates,
        'years': year_reports,
    }


def _parse_years(text, catalog):
    if not text:
        return sorted(catalog)
    years = []
    for part in text.split(','):
        part = part.strip()
        if part:
            years.append(int(part))
    return years


def _load_overrides(path):
    if not path:
        return {}
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        raise SystemExit('--probe-dates-json must be a JSON object')
    overrides = {}
    for key, value in data.items():
        if (not isinstance(value, list) or len(value) != 2
                or not all(isinstance(item, str) for item in value)):
            raise SystemExit(f'probe dates for {key} must be ["YYYY-MM-DD", "YYYY-MM-DD"]')
        overrides[str(key)] = (value[0], value[1])
    return overrides


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--years', default=None,
                        help='Comma-separated release years. Default: every available snapshot.')
    parser.add_argument('--cache-dir', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--history', default=str(DEFAULT_HISTORY))
    parser.add_argument('--sections', default=str(DEFAULT_SECTIONS))
    parser.add_argument('--stations', default=str(DEFAULT_STATIONS))
    parser.add_argument('--probe-dates-json', default=None)
    args = parser.parse_args(argv)
    started = time.perf_counter()
    catalog = snapshot_catalog()
    years = _parse_years(args.years, catalog)
    report = build_report(
        years, args.cache_dir, args.history, args.sections, args.stations,
        _load_overrides(args.probe_dates_json))
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(format_summary(report))
    print(f'elapsed_s {time.perf_counter() - started:.1f}', file=sys.stderr, flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
