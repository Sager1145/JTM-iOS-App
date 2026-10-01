#!/usr/bin/env python3
"""Build app/data/rail-history.json (jp) from older MLIT N02 releases.

Each event in jp-rail-history-events.json names a line/operator as spelled in
N02 and the last release (`year`, e.g. "15" for N02-15) that still carried the
section. That release's geometry is compared with app/data/rail-sections.json:
whatever lies more than COVER_M from current track (and from retired geometry
already emitted by a later event) becomes an overlay section with the event's
valid_to. Loose ends near existing track are joined to an exact vertex of it,
because the route graph joins lines only where 5-decimal coordinates match.

Stations of that line near the emitted geometry go into the overlay unless
the same station on the same line is still within STATION_KEEP_M; a junction
platform of the retired line is kept without its group code.

For `kind: relocation` events the current features of that line inside the
event bbox that the old release did not have receive valid_from = valid_to
through a `retirements` entry, when a bbox can select exactly them.

Events with no kind are closures. Other kinds (opening, station_opening,
station_closure, suspension, resumption, operator_transfer) are emitted only
from a release this script already reads, plus an explicit date on the event.
service_validity / infrastructure_validity are optional half-open [from, to]
pairs. The solver interval stays valid_from/valid_to; a feature that states
neither domain pair keeps those keys exactly. A lone infrastructure pair is
the service interval and is not also emitted as infrastructure.

Raw releases are local-only (see app/data/raw/README); default source dir is
the web repo's app/data/raw/railway/jp/history, fetched from
https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-YY/N02-YY_GML.zip.

Usage: python3 app/scripts/railway/build-jp-rail-history.py [--source-dir DIR]
       [--revision YYYY-MM-DD.N] [--report PATH]
"""
import argparse, datetime, io, json, math, os, sys, zipfile
from collections import defaultdict
import shapefile
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'history'))
from temporal_source import (compile_event as compile_temporal_event, normalize_stamps,
                             expand_legacy_periods, constrain_opening_predecessors)

# Events with no kind are closures. The ride solver reads the service interval
# only. A lone valid_from/valid_to pair is that interval; infrastructure_validity
# is emitted beside it only when both domains are stated.
EVENT_KINDS = (
    'opening', 'closure', 'relocation', 'station_opening', 'station_closure',
    'suspension', 'resumption', 'operator_transfer',
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
EVENTS = os.path.join(ROOT, 'app/scripts/railway/jp-rail-history-events.json')
SECTIONS = os.path.join(ROOT, 'app/data/rail-sections.json')
STATIONS = os.path.join(ROOT, 'app/data/stations.json')
OUT = os.path.join(ROOT, 'app/data/rail-history.json')
DEFAULT_SRC = os.path.expanduser('~/Documents/GitHub/Japan-Train-Map/app/data/raw/railway/jp/history')

COVER_M = 40.0          # sample within this of existing track = still there
STEP_M = 20.0           # densify step for the coverage test
SNAP_M = 200.0          # loose end within this of existing track is joined to it
BRIDGE_M = 2 * COVER_M + 2 * STEP_M  # two loose ends of one event this close are one cut track
WALK_M = 3000.0         # longest shared corridor followed into a junction station
MIN_RUN_M = 150.0       # drop shorter uncovered runs (digitising noise)
MIN_MAXD_M = 150.0      # drop runs that never stray further than this (noise)
STATION_AREA_M = 2000.0 # retired station must lie this close to the event's emitted track
STATION_KEEP_M = 300.0  # same name on the same line this close = still open
CELL = 0.004


def m_per_deg(lat):
    return 111320.0 * math.cos(math.radians(lat)), 110540.0


def dist_m(a, b):
    mx, my = m_per_deg((a[1] + b[1]) / 2)
    return math.hypot((a[0] - b[0]) * mx, (a[1] - b[1]) * my)


def length_m(pts):
    return sum(dist_m(a, b) for a, b in zip(pts, pts[1:]))


def q(p):
    return (round(p[0], 5), round(p[1], 5))


class SegIndex:
    """Grid index over segments; answers distance, nearest projection and nearest vertex."""

    def __init__(self):
        self.grid = defaultdict(list)
        self.segs = []

    def add(self, pts):
        for a, b in zip(pts, pts[1:]):
            i = len(self.segs)
            self.segs.append((tuple(a), tuple(b)))
            x0, x1 = sorted((a[0], b[0])); y0, y1 = sorted((a[1], b[1]))
            for gx in range(math.floor(x0 / CELL), math.floor(x1 / CELL) + 1):
                for gy in range(math.floor(y0 / CELL), math.floor(y1 / CELL) + 1):
                    self.grid[(gx, gy)].append(i)

    def nearest(self, p, maxd=300.0):
        """(distance, projection, segment) of the closest segment within maxd, else None."""
        mx, my = m_per_deg(p[1])
        gx, gy = math.floor(p[0] / CELL), math.floor(p[1] / CELL)
        r = int(maxd / 350) + 1
        best = None
        seen = set()
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                for i in self.grid.get((gx + dx, gy + dy), ()):
                    if i in seen:
                        continue
                    seen.add(i)
                    a, b = self.segs[i]
                    ax, ay = (a[0] - p[0]) * mx, (a[1] - p[1]) * my
                    vx, vy = (b[0] - a[0]) * mx, (b[1] - a[1]) * my
                    L = vx * vx + vy * vy
                    t = 0.0 if L == 0 else max(0.0, min(1.0, -(ax * vx + ay * vy) / L))
                    d = math.hypot(ax + t * vx, ay + t * vy)
                    if d <= maxd and (best is None or d < best[0]):
                        best = (d, (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), (a, b))
        return best

    def dist(self, p, maxd=300.0):
        n = self.nearest(p, maxd)
        return n[0] if n else math.inf


def open_release(src, year):
    normalized = os.path.join(src, f'N02-{year}.json')
    if os.path.exists(normalized):
        return json.load(open(normalized))
    for name in (f'N02-{year}_GML.zip', f'N02-{year}.zip'):
        path = os.path.join(src, name)
        if os.path.exists(path):
            return zipfile.ZipFile(path)
    sys.exit(f'missing N02-{year} under {src}')


def read_release(zf, kind):
    if isinstance(zf, dict):
        key = 'sections' if kind == 'RailroadSection' else 'stations'
        return [(f['properties'], line_coords(f)) for f in zf[key]]
    names = [n for n in zf.namelist() if n.endswith(f'{kind}.shp')]
    if not names:
        sys.exit(f'no {kind} shapefile; normalize legacy N02 fields and CRS first')
    # Prefer the Shift-JIS copy; N02-05 ships a superseded v1.0 folder too.
    names.sort(key=lambda n: ('v1.0' in n, 'UTF' in n.upper()))
    base = names[0][:-4]
    r = shapefile.Reader(shp=io.BytesIO(zf.read(base + '.shp')), dbf=io.BytesIO(zf.read(base + '.dbf')),
                         encoding='cp932')
    fields = [f[0].split('\x00')[0] for f in r.fields[1:]]
    out = []
    for sr in r.iterShapeRecords():
        props = {k: (v.strip() if isinstance(v, str) else v) for k, v in zip(fields, sr.record)}
        parts = list(sr.shape.parts) + [len(sr.shape.points)]
        for a, b in zip(parts, parts[1:]):
            pts = [tuple(p) for p in sr.shape.points[a:b]]
            if len(pts) >= 2:
                out.append((props, pts))
    return out


def densify(pts):
    """[(point, original_vertex_or_None)] every STEP_M metres, keeping original vertices."""
    out = [(pts[0], pts[0])]
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(dist_m(a, b) / STEP_M))
        for k in range(1, n + 1):
            p = b if k == n else (a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n)
            out.append((p, b if k == n else None))
    return out


def in_bbox(p, bbox):
    return bbox is None or (bbox[0] <= p[0] <= bbox[2] and bbox[1] <= p[1] <= bbox[3])


def event_kind(ev):
    kind = ev.get('kind') or 'closure'
    if kind not in EVENT_KINDS:
        sys.exit(f"{ev.get('id', '?')}: unknown kind {kind!r}")
    return kind


def parse_day(value, label):
    if value is None:
        return None
    if not isinstance(value, str):
        sys.exit(f'{label} must be YYYY-MM-DD or null')
    try:
        datetime.date.fromisoformat(value)
    except ValueError:
        sys.exit(f'{label} is not a real Gregorian date: {value}')
    if len(value) != 10:
        sys.exit(f'{label} must be YYYY-MM-DD or null')
    return value


def parse_pair(value, label):
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        sys.exit(f'{label} must be a [from, to] pair')
    start = parse_day(value[0], label + '[0]')
    end = parse_day(value[1], label + '[1]')
    if start and end and start >= end:
        sys.exit(f'{label} from must precede to')
    return start, end


def split_domains(ev):
    """(service_from, service_to, infrastructure_or_None).

    infrastructure_or_None is None when that pair is absent, and also when it
    is the only pair — then it *is* the service interval (today's
    valid_from/valid_to). The ride solver never reads the infrastructure pair.
    """
    label = ev.get('id', '?')
    has_service = 'service_validity' in ev
    has_infra = 'infrastructure_validity' in ev
    has_legacy = 'valid_from' in ev or 'valid_to' in ev
    if has_service:
        service = parse_pair(ev['service_validity'], f'{label}.service_validity')
    elif has_legacy or not has_infra:
        if 'valid_from' in ev and ev.get('valid_from') is None:
            sys.exit(f'{label}.valid_from cannot be null')
        if 'valid_to' in ev and ev.get('valid_to') is None:
            sys.exit(f'{label}.valid_to cannot be null')
        service = (
            parse_day(ev.get('valid_from'), f'{label}.valid_from') if 'valid_from' in ev else None,
            parse_day(ev.get('valid_to'), f'{label}.valid_to') if 'valid_to' in ev else None,
        )
    else:
        service = parse_pair(ev['infrastructure_validity'], f'{label}.infrastructure_validity')
        has_infra = False
    if service[0] and service[1] and service[0] >= service[1]:
        sys.exit(f'{label} service interval from must precede to')
    if service[0] is None and service[1] is None:
        sys.exit(f'{label} needs a service interval')
    infra = parse_pair(ev['infrastructure_validity'], f'{label}.infrastructure_validity') if has_infra else None
    return service[0], service[1], infra


def write_stated_domains(props, ev):
    """Attach domain pairs only when the event states them.

    Today's closure/relocation events state neither, and this is a no-op so
    their property keys stay valid_from/valid_to alone.
    """
    if 'service_validity' not in ev and 'infrastructure_validity' not in ev:
        return
    start, end, infra = split_domains(ev)
    props.pop('valid_from', None)
    props.pop('valid_to', None)
    if start:
        props['valid_from'] = start
    if end:
        props['valid_to'] = end
    if 'service_validity' in ev:
        props['service_validity'] = [start, end]
    if infra is not None:
        props['infrastructure_validity'] = list(infra)
    kind = event_kind(ev)
    if kind not in ('closure', 'relocation'):
        props['kind'] = kind


def station_names(ev):
    if 'stations' in ev:
        names = ev['stations']
        if not isinstance(names, list) or not names or not all(isinstance(n, str) and n for n in names):
            sys.exit(f"{ev.get('id', '?')}: stations must be a non-empty list of names")
        return list(names)
    if 'station' in ev:
        name = ev['station']
        if not isinstance(name, str) or not name:
            sys.exit(f"{ev.get('id', '?')}: station must be a name")
        return [name]
    return None


def line_coords(feature):
    coords = feature['geometry']['coordinates']
    if coords and isinstance(coords[0], (int, float)):
        return [coords]
    return coords


def features_of(features, line, operator, line_key, op_key):
    return [f for f in features
            if f['properties'].get(line_key) == line and f['properties'].get(op_key) == operator]


def retirement_for(ev, chosen, universe, line, operator, line_key, op_key):
    """A retirement whose bbox selects exactly `chosen`, or a skip reason."""
    if not chosen:
        return None
    xs = [c[0] for f in chosen for c in line_coords(f)]
    ys = [c[1] for f in chosen for c in line_coords(f)]
    tight = [round(min(xs) - 1e-5, 5), round(min(ys) - 1e-5, 5),
             round(max(xs) + 1e-5, 5), round(max(ys) + 1e-5, 5)]
    same = features_of(universe, line, operator, line_key, op_key)
    selected = [f for f in same if all(in_bbox(c, tight) for c in line_coords(f))]
    chosen_ids = {id(f) for f in chosen}
    if len(selected) != len(chosen) or any(id(f) not in chosen_ids for f in selected):
        return f'skipped: bbox would also select {len(selected) - len(chosen)} other features'
    start, end, infra = split_domains(ev)
    entry = {
        'history_id': ev['id'],
        'match': {'line_name': line, 'operator': operator, 'bbox': tight},
        'source': ev['source'],
        'kind': event_kind(ev),
    }
    if start:
        entry['valid_from'] = start
    if end:
        entry['valid_to'] = end
    if 'service_validity' in ev:
        entry['service_validity'] = [start, end]
    if infra is not None:
        entry['infrastructure_validity'] = list(infra)
    return entry


def closed_station_rows(ev, station_rows, cur_station_pos):
    """Stations of this line/operator in an old release that are not still open."""
    names = station_names(ev)
    if names is None:
        sys.exit(f"{ev['id']}: station_closure needs station or stations")
    wanted = set(names)
    out = []
    for props, pts in station_rows:
        if props['N02_003'] != ev['line'] or props['N02_004'] != ev['operator']:
            continue
        name = props['N02_005']
        if name not in wanted:
            continue
        mid = pts[len(pts) // 2]
        if not in_bbox(mid, ev.get('bbox')):
            continue
        nearby = [line for line, c in cur_station_pos.get(name, ()) if dist_m(mid, c) <= STATION_KEEP_M]
        if ev['line'] in nearby:
            continue
        out.append((props, pts))
    return out


def overlay_section_feature(ev, props, pts):
    coords = []
    for p in pts:
        if not coords or q(p) != tuple(coords[-1]):
            coords.append(list(q(p)))
    if len(coords) < 2:
        return None
    fprops = {
        'history_id': ev['id'], 'kind': event_kind(ev),
        'N02_001': props['N02_001'], 'N02_002': props['N02_002'],
        'N02_003': props['N02_003'], 'N02_004': props['N02_004'],
        'source': f"N02-{ev['year']}; {ev['source']}",
    }
    write_stated_domains(fprops, ev)
    if 'valid_from' not in fprops and 'valid_to' not in fprops:
        start, end, _ = split_domains(ev)
        if start:
            fprops['valid_from'] = start
        if end:
            fprops['valid_to'] = end
    return {'type': 'Feature', 'properties': fprops,
            'geometry': {'type': 'LineString', 'coordinates': coords}}


def overlay_station_feature(ev, props, pts):
    name = props['N02_005']
    sprops = {
        'history_id': f"{ev['id']}.{name}", 'kind': event_kind(ev),
        'station_name': name, 'line_name': ev['line'], 'operator': ev['operator'],
        'railway_class_code': props['N02_001'], 'institution_type_code': props['N02_002'],
        'source': f"N02-{ev['year']}",
    }
    for k, dst in (('N02_005c', 'n02_station_code'), ('N02_005g', 'n02_group_code')):
        if props.get(k):
            sprops[dst] = props[k]
    write_stated_domains(sprops, ev)
    if 'valid_from' not in sprops and 'valid_to' not in sprops:
        start, end, _ = split_domains(ev)
        if start:
            sprops['valid_from'] = start
        if end:
            sprops['valid_to'] = end
    return {'type': 'Feature', 'properties': sprops, 'geometry': {
        'type': 'LineString', 'coordinates': [list(q(p)) for p in pts]}}


def uncovered_runs(pts, cover, bbox):
    """Runs of the polyline farther than COVER_M from `cover` and inside bbox.

    Each run keeps the original vertices it contains plus its first/last
    densified samples, so the output stays at the source's vertex density.
    """
    samples = densify(pts)
    runs, cur = [], []
    for p, orig in samples:
        free = in_bbox(p, bbox) and cover.dist(p, COVER_M + 1) > COVER_M
        if free:
            cur.append((p, orig))
        elif cur:
            runs.append(cur); cur = []
    if cur:
        runs.append(cur)
    out = []
    for run in runs:
        keep = [p for i, (p, orig) in enumerate(run) if orig is not None or i in (0, len(run) - 1)]
        dedup = []
        for p in keep:
            if not dedup or q(p) != q(dedup[-1]):
                dedup.append(p)
        if len(dedup) >= 2:
            out.append(dedup)
    return out


def join_end(end, cover):
    """Path from a loose end onto an exact vertex of existing track, or None."""
    near = cover.nearest(end, SNAP_M)
    if not near:
        return None
    d, proj, (a, b) = near
    vertex = a if dist_m(proj, a) <= dist_m(proj, b) else b
    path = [end]
    if dist_m(proj, vertex) > 5 and dist_m(proj, end) > 5:
        path.append(proj)
    path.append(vertex)
    return path


def walk_to_junction(end, feats, snap, junctions):
    """Old-line path from a loose end, through track it shared a corridor with
    (within COVER_M of existing track), to a junction station's platform.

    Where the retired line ran beside an open one into the junction (屋代線
    beside しなの鉄道, 江差線 beside 海峡線), the coverage test cuts it short
    of the station; a ride naming the retired line then has no edge of that
    line at its endpoint. Returns the vertices to append, or None.
    """
    if not junctions:
        return None
    import heapq
    adj = defaultdict(list)
    for _, pts in feats:
        for a, b in zip(pts, pts[1:]):
            d = dist_m(a, b)
            adj[q(a)].append((q(b), d)); adj[q(b)].append((q(a), d))
    covered = {}
    def ok(v):
        if v not in covered:
            covered[v] = snap.dist(v, COVER_M + 1) <= COVER_M
        return covered[v]
    heap = [(dist_m(end, v), v) for v in adj if dist_m(end, v) <= 60 and ok(v)]
    heapq.heapify(heap)
    prev, best = {v: None for _, v in heap}, {v: d for d, v in heap}
    while heap:
        d, v = heapq.heappop(heap)
        if d > best.get(v, math.inf) or d > WALK_M:
            continue
        if any(dist_m(v, j) <= 100 for j in junctions):
            path = []
            while v is not None:
                path.append(v); v = prev[v]
            return list(reversed(path))
        for w, L in adj[v]:
            if ok(w) and d + L < best.get(w, math.inf):
                best[w] = d + L; prev[w] = v
                heapq.heappush(heap, (d + L, w))
    return None


def emit_extended(ev, release, cur_sections, cur_stations, cur_station_pos,
                  sections, station_by_key, retirements, cover, joinable, retired_geometry):
    """Kinds other than closure/relocation. Geometry comes only from a release
    the builder already reads, or from the current package. No match emits nothing
    invented: the event fails closed instead.
    """
    kind = event_kind(ev)
    start, end, _infra = split_domains(ev)
    if kind in ('opening', 'station_opening', 'resumption') and not start:
        sys.exit(f"{ev['id']}: {kind} needs a service start (valid_from or service_validity)")
    if kind in ('station_closure', 'suspension', 'operator_transfer') and not end:
        sys.exit(f"{ev['id']}: {kind} needs a service end (valid_to or service_validity)")
    if kind == 'operator_transfer' and not ev.get('to_operator'):
        sys.exit(f"{ev['id']}: operator_transfer needs to_operator")
    secs, stas = release(ev['year'])
    old_secs = [(p, pts) for p, pts in secs if p['N02_003'] == ev['line'] and p['N02_004'] == ev['operator']
                and all(in_bbox(c, ev.get('bbox')) for c in pts)]
    old_stas = [(p, pts) for p, pts in stas if p['N02_003'] == ev['line'] and p['N02_004'] == ev['operator']
                and all(in_bbox(c, ev.get('bbox')) for c in pts)]
    def in_event(feature):
        bbox = ev.get('bbox')
        return bbox is None or all(in_bbox(c, bbox) for c in line_coords(feature))

    current_secs = [f for f in features_of(
        cur_sections, ev['line'], ev['operator'], 'N02_003', 'N02_004') if in_event(f)]
    note = None
    emitted_coords = []
    station_names_out = []

    def remember_section(feature):
        if feature is None:
            return
        sections.append(feature)
        emitted_coords.append(feature['geometry']['coordinates'])

    def remember_station(feature):
        name = feature['properties']['station_name']
        key = (name, ev['line'], ev['operator'])
        prev = station_by_key.get(key)
        if prev and prev['properties'].get('valid_to') and feature['properties'].get('valid_to') \
                and prev['properties']['valid_to'] >= feature['properties']['valid_to']:
            return
        station_by_key[key] = feature
        station_names_out.append(name)

    if kind == 'station_closure':
        if not old_stas:
            sys.exit(f"{ev['id']}: no {ev['line']}/{ev['operator']} stations in N02-{ev['year']}")
        rows = closed_station_rows(ev, old_stas, cur_station_pos)
        if not rows:
            sys.exit(f"{ev['id']}: no closed station in N02-{ev['year']}")
        for props, pts in rows:
            feature = overlay_station_feature(ev, props, pts)
            mid = pts[len(pts) // 2]
            other = [line for line, c in cur_station_pos.get(props['N02_005'], ())
                     if dist_m(mid, c) <= STATION_KEEP_M]
            if other:
                feature['properties'].pop('n02_group_code', None)
            remember_station(feature)
    elif kind == 'station_opening':
        names = station_names(ev)
        if names is None:
            sys.exit(f"{ev['id']}: station_opening needs station or stations")
        old_names = {p['N02_005'] for p, _ in old_stas}
        missing = [name for name in names if name not in old_names]
        if missing:
            sys.exit(f"{ev['id']}: N02-{ev['year']} has no station {'/'.join(missing)}")
        chosen = features_of(cur_stations, ev['line'], ev['operator'], 'line_name', 'operator')
        chosen = [f for f in chosen if f['properties'].get('station_name') in names and in_event(f)]
        if len(chosen) != len(names):
            have = {f['properties'].get('station_name') for f in chosen}
            sys.exit(f"{ev['id']}: current package has no station {'/'.join(n for n in names if n not in have)}")
        entry = retirement_for(ev, chosen, cur_stations, ev['line'], ev['operator'], 'line_name', 'operator')
        if not isinstance(entry, dict):
            sys.exit(f"{ev['id']}: {entry or 'no current station'}")
        entry['match']['targets'] = ['stations']
        retirements.append(entry)
        note = f"stations {'/'.join(names)}"
    elif kind in ('opening', 'suspension', 'resumption'):
        if current_secs:
            entry = retirement_for(
                ev, current_secs, cur_sections, ev['line'], ev['operator'], 'N02_003', 'N02_004')
            if not isinstance(entry, dict):
                sys.exit(f"{ev['id']}: {entry or 'no current features'}")
            retirements.append(entry)
            note = f"{len(current_secs)} current features"
        elif old_secs and kind != 'resumption':
            for props, pts in old_secs:
                remember_section(overlay_section_feature(ev, props, pts))
            for props, pts in old_stas:
                remember_station(overlay_station_feature(ev, props, pts))
            if not emitted_coords:
                sys.exit(f"{ev['id']}: no geometry in N02-{ev['year']}")
        else:
            sys.exit(f"{ev['id']}: no {ev['line']}/{ev['operator']} in N02-{ev['year']} or the current package")
    elif kind == 'operator_transfer':
        if not old_secs:
            sys.exit(f"{ev['id']}: no {ev['line']}/{ev['operator']} in N02-{ev['year']}")
        for props, pts in old_secs:
            remember_section(overlay_section_feature(ev, props, pts))
        for props, pts in old_stas:
            remember_station(overlay_station_feature(ev, props, pts))
        successor = [f for f in features_of(
            cur_sections, ev.get('to_line', ev['line']), ev['to_operator'], 'N02_003', 'N02_004') if in_event(f)]
        if successor:
            # Old service ends where the successor's service starts (half-open).
            stamped = {
                'id': ev['id'] + '.to', 'kind': kind, 'source': ev['source'],
                'service_validity': [end or start, None],
            }
            if 'infrastructure_validity' in ev:
                stamped['infrastructure_validity'] = ev['infrastructure_validity']
            entry = retirement_for(
                stamped, successor, cur_sections, ev.get('to_line', ev['line']), ev['to_operator'], 'N02_003', 'N02_004')
            if not isinstance(entry, dict):
                sys.exit(f"{ev['id']}: {entry}")
            retirements.append(entry)
            note = f"to {ev['to_operator']}: {len(successor)} features"
    else:
        sys.exit(f"{ev['id']}: unhandled kind {kind}")

    for coords in emitted_coords:
        cover.add(coords)
        joinable.add(coords)
        retired_geometry.append(coords)
    return {
        'id': ev['id'], 'kind': kind, 'year': ev['year'],
        'valid_from': start, 'valid_to': end,
        'runs': len(emitted_coords), 'stations': station_names_out, 'note': note,
    }


def source_event_geometry(event, release):
    """Materialize explicit old-release selectors for rich source events.

    Snapshot identity/coordinates are preserved. Current geometry is never
    silently presented as an old surveyed alignment.
    """
    geometry = event.get('geometry', {})
    historical_periods = geometry.get('historical_periods')
    if historical_periods is not None:
        if not isinstance(historical_periods, list) or not historical_periods:
            raise ValueError(f"{event.get('id', '?')}: historical_periods must be a non-empty list")
        import copy
        event = copy.deepcopy(event)
        for index, period in enumerate(event['geometry']['historical_periods']):
            if not isinstance(period, dict) or not isinstance(period.get('selector'), dict):
                raise ValueError(f"{event.get('id', '?')}: historical period {index} needs a selector")
            label = period.get('release', '')
            if period.get('source') != 'N02' or not label.startswith('N02-'):
                raise ValueError(f"{event.get('id', '?')}: historical period {index} needs N02 release")
            identity = period.get('historical_identity', {})
            selector = period.get('selector', {})
            bbox = selector.get('historical_bbox', selector.get('bbox', event.get('bbox')))
            names = selector.get('historical_stations')
            rows, station_rows = release(label[4:])
            period['historical_sections'] = _historical_sections(rows, identity, bbox)
            period['historical_stations'] = _historical_stations(station_rows, identity, bbox, names)
        return event
    label = geometry.get('release', '')
    if geometry.get('source') != 'N02' or not label.startswith('N02-'):
        return event
    import copy
    event = copy.deepcopy(event)
    identity = geometry.get('historical_identity') or event.get('before') or event
    selector = geometry.get('selector', {})
    bbox = selector.get('historical_bbox', selector.get('bbox', event.get('bbox')))
    names = selector.get('historical_stations')
    if not names and event.get('before', {}).get('station'):
        names = [event['before']['station']]
    rows, station_rows = release(label[4:])
    event['geometry']['historical_sections'] = _historical_sections(rows, identity, bbox)
    event['geometry']['historical_stations'] = _historical_stations(station_rows, identity, bbox, names)
    return event


def _historical_sections(rows, identity, bbox):
    return [{'type': 'Feature', 'properties': dict(props),
             'geometry': {'type': 'LineString', 'coordinates': [list(q(c)) for c in points]}}
            for props, points in rows
            if props['N02_003'] == identity.get('line') and props['N02_004'] == identity.get('operator')
            and all(in_bbox(c, bbox) for c in points)]


def _historical_stations(rows, identity, bbox, names=None):
    result = []
    for props, points in rows:
        if props['N02_003'] != identity.get('line') or props['N02_004'] != identity.get('operator') \
                or not all(in_bbox(c, bbox) for c in points) or names and props['N02_005'] not in names:
            continue
        feature = {'type': 'Feature', 'properties': {
            'line_name': props['N02_003'], 'operator': props['N02_004'],
            'station_name': props['N02_005'], 'railway_class_code': props['N02_001'],
            'institution_type_code': props['N02_002']}, 'geometry': {
                'type': 'LineString', 'coordinates': [list(q(c)) for c in points]}}
        for field, key in [('N02_005c', 'n02_station_code'), ('N02_005g', 'n02_group_code')]:
            if props.get(field):
                feature['properties'][key] = props[field]
        result.append(feature)
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source-dir', default=DEFAULT_SRC)
    ap.add_argument('--revision', required=True)
    ap.add_argument('--report')
    ap.add_argument('--output', default=OUT)
    ap.add_argument('--events', default=EVENTS)
    ap.add_argument('--sections', default=SECTIONS)
    ap.add_argument('--stations', default=STATIONS)
    args = ap.parse_args()

    spec = json.load(open(args.events))
    cur_sections = json.load(open(args.sections))['features']
    cur_stations = json.load(open(args.stations))['features']
    event_ids = [e.get('id') for e in spec['events'] + spec.get('temporal_events', [])]
    if any(not i for i in event_ids) or len(set(event_ids)) != len(event_ids):
        sys.exit('source events require unique non-empty ids')
    for event in spec['events']:
        mode = event.get('geometry_mode')
        if mode not in (None, 'identity'):
            sys.exit(event['id'] + ': unsupported geometry_mode')
        if mode == 'identity' and event.get('review', {}).get('status') != 'verified':
            sys.exit(event['id'] + ': identity geometry requires verified review')

    cover = SegIndex()          # current track + retired geometry emitted so far
    joinable = SegIndex()       # what a loose end may join: no 新幹線
    retired_geometry = []
    vertex_lines = defaultdict(set)
    for f in cur_sections:
        for c in f['geometry']['coordinates']:
            vertex_lines[q(c)].add(f['properties']['N02_003'])
    for f in cur_sections:
        cover.add(f['geometry']['coordinates'])
        if f['properties']['N02_002'] != '1':
            joinable.add(f['geometry']['coordinates'])
    cur_station_pos = defaultdict(list)     # name -> [(line, midpoint)]
    for f in cur_stations:
        c = f['geometry']['coordinates']
        cur_station_pos[f['properties']['station_name']].append(
            (f['properties']['line_name'], c[len(c) // 2] if isinstance(c[0], list) else c))

    releases = {}
    def release(year):
        if year not in releases:
            zf = open_release(args.source_dir, year)
            releases[year] = (read_release(zf, 'RailroadSection'), read_release(zf, 'Station'))
        return releases[year]

    sections, retirements, report = [], [], []
    station_by_key = {}
    events = sorted(enumerate(spec['events']), key=lambda ie: (-int(ie[1]['year']), ie[0]))
    for _, ev in events:
        kind = event_kind(ev)
        if kind not in ('closure', 'relocation'):
            entry = emit_extended(
                ev, release, cur_sections, cur_stations, cur_station_pos,
                sections, station_by_key, retirements, cover, joinable, retired_geometry)
            report.append(entry)
            print(f"{ev['id']}: {kind} {entry.get('note') or ''} "
                  f"{entry['runs']} runs, {len(entry['stations'])} stations", file=sys.stderr)
            continue
        secs, stas = release(ev['year'])
        feats = [(p, pts) for p, pts in secs if p['N02_003'] == ev['line'] and p['N02_004'] == ev['operator']]
        if not feats:
            sys.exit(f"{ev['id']}: no {ev['line']}/{ev['operator']} in N02-{ev['year']}")
        bbox = ev.get('bbox')
        min_maxd = ev.get('min_maxd_m', MIN_MAXD_M)
        # A relocation's old track is measured against, and joined to, only
        # track that existed alongside it: the new alignment is dated
        # valid_from = valid_to, so its vertices are no junction for old rides.
        snap, join_to = cover, joinable
        if ev.get('kind') == 'relocation':
            fresh = {id(f) for f in new_alignment(ev, cur_sections, feats)}
            snap, join_to = SegIndex(), SegIndex()
            for f in cur_sections:
                if id(f) not in fresh:
                    snap.add(f['geometry']['coordinates'])
                    if f['properties']['N02_002'] != '1':
                        join_to.add(f['geometry']['coordinates'])
            for c in retired_geometry:
                snap.add(c); join_to.add(c)
        runs = []
        for props, pts in feats:
            if ev.get('geometry_mode') == 'identity':
                # Reviewed old identity is authoritative even on current track.
                # Never cut a partial feature by an approximate bbox.
                candidates = [pts] if all(in_bbox(p, bbox) for p in pts) else []
            else:
                candidates = uncovered_runs(pts, snap, bbox)
            for run in candidates:
                runs.append((props, run))
        # N02 splits a line into short features, so judge noise per connected
        # chain of runs: keep a chain that is long enough and strays far enough.
        parent = list(range(len(runs)))
        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]; i = parent[i]
            return i
        by_end = defaultdict(list)
        for i, (_, run) in enumerate(runs):
            by_end[q(run[0])].append(i); by_end[q(run[-1])].append(i)
        for ids in by_end.values():
            for j in ids[1:]:
                parent[find(j)] = find(ids[0])
        chain_len, chain_maxd = defaultdict(float), defaultdict(float)
        for i, (_, run) in enumerate(runs):
            chain_len[find(i)] += length_m(run)
            chain_maxd[find(i)] = max(chain_maxd[find(i)], max(snap.dist(p, 3000) for p in run))
        kept, dropped = [], []
        for i, (props, run) in enumerate(runs):
            ok = ev.get('geometry_mode') == 'identity' or (chain_len[find(i)] >= MIN_RUN_M and chain_maxd[find(i)] >= min_maxd)
            (kept if ok else dropped).append((props, run, chain_len[find(i)], chain_maxd[find(i)]))
        # Loose ends: endpoints not shared with another kept run of this event.
        ends = defaultdict(int)
        for _, run, _, _ in kept:
            ends[q(run[0])] += 1; ends[q(run[-1])] += 1
        # Old platforms of this line at stations still open on other lines.
        junctions = []
        for sp, spts in release(ev.get('station_year', ev['year']))[1]:
            if sp['N02_003'] == ev['line'] and sp['N02_004'] == ev['operator']:
                mid = spts[len(spts) // 2]
                near = [line for line, c in cur_station_pos.get(sp['N02_005'], ()) if dist_m(mid, c) <= STATION_KEEP_M]
                if near and ev['line'] not in near:
                    junctions.append(mid)
        emitted, joins, km = [], 0, 0.0
        geoms = [list(run) for _, run, _, _ in kept]
        loose = [(i, at_start) for i, g in enumerate(geoms) for at_start in (True, False)
                 if ends[q(g[0] if at_start else g[-1])] == 1]
        # Where the old line passed within COVER_M of a line it crosses on a
        # bridge, the run was cut in two: rejoin the halves to each other
        # rather than to the crossing line.
        pairs = sorted((dist_m(geoms[i][0 if a else -1], geoms[j][0 if b else -1]), (i, a), (j, b))
                       for n, (i, a) in enumerate(loose) for (j, b) in loose[n + 1:] if i != j)
        bridged = set()
        for d, (i, a), (j, b) in pairs:
            if d > BRIDGE_M or (i, a) in bridged or (j, b) in bridged:
                continue
            target = geoms[j][0 if b else -1]
            geoms[i] = [target] + geoms[i] if a else geoms[i] + [target]
            bridged |= {(i, a), (j, b)}
        joined = []
        for n, ((props, run, L, maxd), geom) in enumerate(zip(kept, geoms)):
            for at_start in (True, False):
                end = geom[0] if at_start else geom[-1]
                if (n, at_start) not in loose or (n, at_start) in bridged or not ev.get('join', True):
                    continue
                walk = walk_to_junction(end, feats, snap, junctions) if ev.get('join', True) else None
                if walk:
                    geom = list(reversed(walk)) + geom if at_start else geom + walk
                    end = geom[0] if at_start else geom[-1]
                path = join_end(end, join_to)
                if path:
                    joins += 1
                    joined.append('/'.join(sorted(vertex_lines.get(q(path[-1]), {'(retired)'}))))
                    geom = list(reversed(path[1:])) + geom if at_start else geom + path[1:]
            coords = []
            for p in geom:
                if not coords or q(p) != tuple(coords[-1]):
                    coords.append(list(q(p)))
            if len(coords) < 2:
                continue
            emitted.append(coords)
            km += length_m(coords) / 1000
            fprops = {'history_id': ev['id'], 'N02_001': props['N02_001'], 'N02_002': props['N02_002'],
                      'N02_003': props['N02_003'], 'N02_004': props['N02_004'], 'valid_to': ev['valid_to'],
                      'source': f"N02-{ev['year']}; {ev['source']}"}
            write_stated_domains(fprops, ev)
            sections.append({'type': 'Feature', 'properties': fprops,
                             'geometry': {'type': 'LineString', 'coordinates': coords}})
        # Stations on the emitted geometry.
        on = SegIndex()
        for c in emitted:
            on.add(c)
        st_names = []
        if ev.get('station_year'):
            stas = release(ev['station_year'])[1]
        for props, pts in stas:
            if props['N02_003'] != ev['line'] or props['N02_004'] != ev['operator']:
                continue
            mid = pts[len(pts) // 2]
            # Near this event's retired track (a platform beside parallel
            # current track can sit off the emitted runs) and not still open.
            if not in_bbox(mid, bbox) or on.dist(mid, STATION_AREA_M) > STATION_AREA_M:
                continue
            name = props['N02_005']
            nearby = [line for line, c in cur_station_pos.get(name, ()) if dist_m(mid, c) <= STATION_KEEP_M]
            if ev['line'] in nearby:
                continue
            # A junction (屋代, 木古内) keeps the retired line's own platform so a
            # ride naming that line finds an endpoint on it, but without the
            # group code: it must not join the open lines' transfer group.
            junction = bool(nearby)
            if name in st_names:
                continue
            # A station shared by two events (留萌, 槙峰) closed with the later one.
            key = (name, ev['line'], ev['operator'])
            prev = station_by_key.get(key)
            if prev and prev['properties']['valid_to'] >= ev['valid_to']:
                continue
            st_names.append(name)
            sprops = {'history_id': f"{ev['id']}.{name}", 'station_name': name, 'line_name': ev['line'],
                      'operator': ev['operator'], 'railway_class_code': props['N02_001'],
                      'institution_type_code': props['N02_002']}
            for k, dst in (('N02_005c', 'n02_station_code'), ('N02_005g', 'n02_group_code')):
                if props.get(k) and not (junction and k == 'N02_005g'):
                    sprops[dst] = props[k]
            sprops.update({'valid_to': ev['valid_to'], 'source': f"N02-{ev['year']}"})
            write_stated_domains(sprops, ev)
            station_by_key[key] = {'type': 'Feature', 'properties': sprops, 'geometry': {
                'type': 'LineString', 'coordinates': [list(q(p)) for p in pts]}}
        for c in emitted:
            cover.add(c)
            joinable.add(c)
            retired_geometry.append(c)
        entry = {'id': ev['id'], 'year': ev['year'], 'valid_to': ev['valid_to'], 'runs': len(emitted),
                 'dropped_runs': len(dropped), 'dropped_km': round(sum(length_m(r[1]) for r in dropped) / 1000, 2),
                 'km': round(km, 2),
                 'joins': joins, 'joined_lines': joined, 'stations': st_names}
        if not emitted:
            sys.exit(f"{ev['id']}: matched no historical geometry; use reviewed identity selection or resolve source gap")
        if ev.get('kind') == 'relocation':
            entry['valid_from'] = relocation_retirement(ev, cur_sections, cur_stations, feats, retirements)
        report.append(entry)
        print(f"{ev['id']}: {len(emitted)} runs {km:.1f} km, {joins} joins, {len(st_names)} stations "
              f"{'/'.join(st_names)}", file=sys.stderr)

    stations = list(station_by_key.values())
    try:
        sections, stations = expand_legacy_periods(spec['events'], sections, stations)
    except ValueError as error:
        sys.exit(str(error))
    for event in spec.get('temporal_events', []):
        try:
            event = source_event_geometry(event, release)
            compiled = compile_temporal_event(event, cur_sections, cur_stations)
        except (ValueError, KeyError) as error:
            sys.exit(f"{event.get('id', '?')}: {error}")
        sections.extend(compiled['sections'])
        stations.extend(compiled['stations'])
        retirements.extend(compiled['retirements'])
        report.append({'id': event['id'], 'kind': event['kind'],
                       'runs': len(compiled['sections']),
                       'stations': [s['properties']['station_name'] for s in compiled['stations']],
                       'retirements': [r['history_id'] for r in compiled['retirements']]})
    retirements.extend(spec.get('retirements', []))
    try:
        sections, stations = constrain_opening_predecessors(
            spec.get('temporal_events', []), sections, stations, cur_sections, cur_stations)
        retirements = normalize_stamps(retirements, cur_sections, cur_stations)
    except ValueError as error:
        sys.exit(str(error))
    out = {'schema_version': '1', 'revision': args.revision,
           'source': '国土数値情報（鉄道データ N02）2005〜2025年度版（国土交通省）を加工して作成; 正確な運行日は各 source を参照',
           'sections': sections, 'stations': stations, 'retirements': retirements}
    with open(args.output, 'w') as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(',', ':'))
        fh.write('\n')
    if args.report:
        json.dump(report, open(args.report, 'w'), ensure_ascii=False, indent=1)
    print(f'{len(sections)} sections, {len(stations)} stations, {len(retirements)} retirements -> {args.output}',
          file=sys.stderr)


def new_alignment(ev, cur_sections, old_feats):
    """Current features of the event's line inside its bbox that stray from the old release."""
    old = SegIndex()
    for _, pts in old_feats:
        old.add(pts)
    line, op = ev['line'], ev['operator']
    return [f for f in cur_sections
            if f['properties']['N02_003'] == line and f['properties']['N02_004'] == op
            and all(in_bbox(c, ev['bbox']) for c in f['geometry']['coordinates'])
            and max(old.dist(tuple(c), 300) for c in f['geometry']['coordinates']) > COVER_M * 2]


def relocation_retirement(ev, cur_sections, cur_stations, old_feats, retirements):
    """valid_from for the new alignment when a bbox can select exactly its features."""
    old = SegIndex()
    for _, pts in old_feats:
        old.add(pts)
    line, op = ev['line'], ev['operator']
    mine = [f for f in cur_sections if f['properties']['N02_003'] == line and f['properties']['N02_004'] == op]
    new = new_alignment(ev, cur_sections, old_feats)
    if not new:
        return 'skipped: no new-alignment features'
    xs = [c[0] for f in new for c in f['geometry']['coordinates']]
    ys = [c[1] for f in new for c in f['geometry']['coordinates']]
    tight = [round(min(xs) - 1e-5, 5), round(min(ys) - 1e-5, 5), round(max(xs) + 1e-5, 5), round(max(ys) + 1e-5, 5)]
    selected = [f for f in mine if all(in_bbox(c, tight) for c in f['geometry']['coordinates'])]
    if len(selected) != len(new) or any(f not in new for f in selected):
        return f'skipped: bbox would also select {len(selected) - len(new)} unchanged features'
    st = [f for f in cur_stations if f['properties']['line_name'] == line and f['properties']['operator'] == op
          and all(in_bbox(c, tight) for c in f['geometry']['coordinates'])]
    unmoved = [f['properties']['station_name'] for f in st
               if min(old.dist(tuple(c), 300) for c in f['geometry']['coordinates']) <= COVER_M * 2]
    if unmoved:
        return f"skipped: bbox would date unmoved stations {'/'.join(unmoved)}"
    # The new alignment opens on the switch day. Domain pairs, when an event
    # states them, are written onto the retired geometry only — this stamp
    # stays valid_from = valid_to so an event without domains is unchanged.
    retirements.append({'history_id': ev['id'].replace('.old-', '.new-'),
                        'match': {'line_name': line, 'operator': op, 'bbox': tight},
                        'valid_from': ev['valid_to'], 'source': ev['source']})
    return f"{len(new)} features, stations {'/'.join(f['properties']['station_name'] for f in st)}"


if __name__ == '__main__':
    main()
