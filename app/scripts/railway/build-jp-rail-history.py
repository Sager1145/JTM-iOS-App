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

Raw releases are local-only (see app/data/raw/README); default source dir is
the web repo's app/data/raw/railway/jp/history, fetched from
https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-YY/N02-YY_GML.zip.

Usage: python3 app/scripts/railway/build-jp-rail-history.py [--source-dir DIR]
       [--revision YYYY-MM-DD.N] [--report PATH]
"""
import argparse, io, json, math, os, sys, zipfile
from collections import defaultdict
import shapefile

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
    for name in (f'N02-{year}_GML.zip', f'N02-{year}.zip'):
        path = os.path.join(src, name)
        if os.path.exists(path):
            return zipfile.ZipFile(path)
    sys.exit(f'missing N02-{year} under {src}')


def read_release(zf, kind):
    names = [n for n in zf.namelist() if n.endswith(f'{kind}.shp')]
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source-dir', default=DEFAULT_SRC)
    ap.add_argument('--revision', required=True)
    ap.add_argument('--report')
    ap.add_argument('--output', default=OUT)
    args = ap.parse_args()

    spec = json.load(open(EVENTS))
    cur_sections = json.load(open(SECTIONS))['features']
    cur_stations = json.load(open(STATIONS))['features']

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
            for run in uncovered_runs(pts, snap, bbox):
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
            ok = chain_len[find(i)] >= MIN_RUN_M and chain_maxd[find(i)] >= min_maxd
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
        if ev.get('kind') == 'relocation':
            entry['valid_from'] = relocation_retirement(ev, cur_sections, cur_stations, feats, retirements)
        report.append(entry)
        print(f"{ev['id']}: {len(emitted)} runs {km:.1f} km, {joins} joins, {len(st_names)} stations "
              f"{'/'.join(st_names)}", file=sys.stderr)

    stations = list(station_by_key.values())
    retirements.extend(spec.get('retirements', []))
    out = {'schema_version': '1', 'revision': args.revision,
           'source': '国土数値情報（鉄道データ N02）2005〜2024年度版（国土交通省）を加工して作成; 廃止日は各 source を参照',
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
    retirements.append({'history_id': ev['id'].replace('.old-', '.new-'),
                        'match': {'line_name': line, 'operator': op, 'bbox': tight},
                        'valid_from': ev['valid_to'], 'source': ev['source']})
    return f"{len(new)} features, stations {'/'.join(f['properties']['station_name'] for f in st)}"


if __name__ == '__main__':
    main()
