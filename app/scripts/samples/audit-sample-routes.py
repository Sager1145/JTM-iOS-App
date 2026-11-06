#!/usr/bin/env python3
"""Mechanically check every bundled example ride's DRAWN route against the displayed rail network.

The app no longer ships precomputed ride parts: an example ride is solved live on the
user-journey path and drawn exactly like a reader's own trip. The route census
(ios/RailKit/Tests/RailCoreTests/UserPathCensusTests.swift, run with
SAMPLE_DISPLAY_CENSUS=1 SAMPLE_DISPLAY_CENSUS_OUTPUT=/abs/out.json) writes one JSON record
per drawn part (plus segment:-1 records for rides with no drawn ride). This script reads
that census (--census) and the 7 bundled stores, and reports per ride:
  - Solved/legs and Projected/legs (legs = route sections the resolver considered, census legCount;
    called-stop pairs, pass_through excluded, when the census has none),
  - display lines drawn (census displayLines, in order),
  - an independent geometry check on the census's drawn coordinates: every drawn part is
    resampled every STEP metres and matched against the compact-v1 display package
    (app/public/rail/<cc>-2025.json) within TOL metres:
      off_network_m  longest run with no display line within TOL (chords / missing geometry),
      off_line_m     longest run whose display lines are all outside requestedLineNames,
      off_operator_m same for requestedOperatorNames,
    ignoring the first/last END_SKIP metres of each part; runs under FLAG_M are noise,
  - max drawn<->solved deviation (sourceToDrawnMaxM / drawnToSourceMaxM).

Census record fields read: store, ride, segment, part, from, to, projected, solved,
solvePath, displayLines, requestedLineNames, requestedOperatorNames, sourceToDrawnMaxM,
drawnToSourceMaxM, and `drawnCoordinates` ([[lon,lat],...], WGS84, the stroke the map
draws) for the independent check. A record without drawnCoordinates is marked
"no-geometry" and skipped by that check; coordinates may instead be supplied in a
separate file via --geometry (a JSON list of {ride, segment, part, drawnCoordinates}).
Old (pre-journey_*) ride ids are read from the "## Ride id map" table of
app/data/sample-trips.sources.md.

Usage: python3 -I app/scripts/samples/audit-sample-routes.py --json out.json \
         [--census census.json [--geometry geom.json] [--notes app/scripts/samples/sample-route-notes.json] --md table.md]
"""
import argparse, collections, json, math, re
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
STEP, TOL, END_SKIP = 25.0, 60.0, 450.0
STORES = [('train-store', 'data/train-store.json', 'jp'),
          ('train-store-tw', 'data/train-store-tw.json', 'tw'),
          ('train-store-hk', 'data/train-store-hk.json', 'hk'),
          ('train-store-kr', 'data/train-store-kr.json', 'kr'),
          ('train-store-mo', 'data/train-store-mo.json', 'mo'),
          ('new-year-grand-loop', 'data/special-samples/new-year-grand-loop.json', 'jp'),
          ('tokyo-limited-express-loop', 'data/special-samples/tokyo-limited-express-loop.json', 'jp')]
SOURCES_MD = APP / 'data/sample-trips.sources.md'
CELL = 0.0005  # degrees (~55 m lat)


def hav(a, b):
    lo1, la1, lo2, la2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


def densify(cs, step):
    out = [(cs[0], 0.0)]
    acc = 0.0
    for a, b in zip(cs, cs[1:]):
        d = hav(a, b); n = max(1, int(d // step))
        for i in range(1, n + 1):
            t = i / n
            out.append(((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), acc + d * t))
        acc += d
    return out


def walk_coords(obj):
    """Yield polylines from a compact-v1 segments list (nested [len, flag, coords] items)."""
    if isinstance(obj, list) and obj and isinstance(obj[0], (int, float)) and len(obj) == 2:
        return
    if isinstance(obj, list) and obj and isinstance(obj[0], list) and obj[0] and isinstance(obj[0][0], (int, float)) and len(obj[0]) == 2:
        yield obj; return
    if isinstance(obj, list):
        for x in obj:
            yield from walk_coords(x)


class Index:
    def __init__(self, cc):
        pkg = json.load(open(APP / f'public/rail/{cc}-2025.json'))
        self.lines = [(l['name'], l.get('operator') or '') for l in pkg['lines']]
        self.cells = collections.defaultdict(list)  # cell -> [(lon,lat,line_idx)]
        for i, l in enumerate(pkg['lines']):
            for poly in walk_coords(l.get('segments') or []):
                if len(poly) < 2: continue
                for c, _ in densify(poly, 20.0):
                    self.cells[(int(c[0] // CELL), int(c[1] // CELL))].append((c[0], c[1], i))

    def near(self, c):
        cx, cy = int(c[0] // CELL), int(c[1] // CELL); hit = set()
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                for x, y, i in self.cells.get((cx + dx, cy + dy), ()):
                    if i not in hit and hav(c, (x, y)) <= TOL: hit.add(i)
        return hit


def longest(flags, dists):
    best = run_start = 0.0; inrun = False
    for f, d in zip(flags, dists):
        if f and not inrun: inrun, run_start = True, d
        if inrun: best = max(best, d - run_start + STEP)
        if not f: inrun = False
    return 0.0 if best == 0 else best


def audit_coords(idx, poly, lines_ok, ops_ok):
    """Independent check of one drawn polyline ([[lon,lat],...])."""
    res = {'length_m': 0.0, 'off_network_m': 0.0, 'off_line_m': 0.0, 'off_operator_m': 0.0,
           'lines': collections.Counter()}
    if len(poly) < 2:
        return res
    samples = densify([tuple(c[:2]) for c in poly], STEP); total = samples[-1][1]; res['length_m'] = total
    off_net, off_line, off_op, ds = [], [], [], []
    for c, d in samples:
        interior = END_SKIP <= d <= total - END_SKIP
        hit = idx.near(c)
        for i in hit:
            res['lines'][idx.lines[i][0]] += 1
        names = {idx.lines[i][0] for i in hit}; ops = {idx.lines[i][1] for i in hit}
        off_net.append(interior and not hit)
        off_line.append(interior and bool(hit) and bool(lines_ok) and not (names & lines_ok))
        off_op.append(interior and bool(hit) and bool(ops_ok) and not (ops & ops_ok))
        ds.append(d)
    res['off_network_m'] = longest(off_net, ds)
    res['off_line_m'] = longest(off_line, ds)
    res['off_operator_m'] = longest(off_op, ds)
    return res


FLAG_M = 150.0  # runs shorter than this are sampling noise at TOL


def load_id_map():
    """old id -> new id from the '## Ride id map' table."""
    out = {}
    if not SOURCES_MD.exists():
        return out
    in_map = False
    for line in SOURCES_MD.read_text(encoding='utf-8').splitlines():
        if line.startswith('## '):
            in_map = line.strip() == '## Ride id map'; continue
        if in_map and line.startswith('|'):
            cells = [c.strip().strip('`') for c in line.strip().strip('|').split('|')]
            if len(cells) >= 3 and cells[2].startswith('journey_'):
                out[cells[0]] = cells[2]
    return out


def load_rides():
    old_of = {new: old for old, new in load_id_map().items()}
    rides = []
    for store, rel, cc in STORES:
        for t in json.load(open(APP / rel, encoding='utf-8'))['trains']:
            called = [s for s in t.get('stops') or [] if s.get('stop_type') != 'pass_through']
            legs = [{'from': a.get('name'), 'to': b.get('name')} for a, b in zip(called, called[1:])]
            rides.append({'store': store, 'region': 'jp' if cc == 'jp' else cc, 'id': t['id'],
                          'old_id': old_of.get(t['id']), 'number': t.get('number'), 'legs': legs})
    return rides


def audit_ride(ride, records, idxs, geom):
    """Attach census records and the independent geometry audit to a ride."""
    ride['unsolved_ride'] = any(r.get('segment', 0) < 0 for r in records)
    drawn = [r for r in records if r.get('segment', -1) >= 0 and r.get('solved')]
    ride['solved_legs'] = len({r['segment'] for r in drawn})
    ride['projected_legs'] = len({r['segment'] for r in drawn if r.get('projected')})
    ride['has_census'] = bool(records)
    # Legs = the route sections the resolver considered (census legCount), which can exceed
    # the called-stop pairs; fall back to the called-stop pairs when the census has none.
    ride['census_legs'] = max([r.get('legCount', 0) for r in records] or [0])
    ride['parts'] = []
    if ride['region'] not in idxs: idxs[ride['region']] = Index(ride['region'])
    idx = idxs[ride['region']]
    for r in drawn:
        key = (r['ride'], r['segment'], r.get('part', 0))
        coords = r.get('drawnCoordinates') or geom.get(key)
        part = {'segment': r['segment'], 'part': r.get('part', 0), 'from': r.get('from'), 'to': r.get('to'),
                'solvePath': r.get('solvePath'), 'displayLines': r.get('displayLines') or [],
                'deviation_m': max(r.get('sourceToDrawnMaxM') or 0.0, r.get('drawnToSourceMaxM') or 0.0)}
        if coords:
            a = audit_coords(idx, coords, set(r.get('requestedLineNames') or []),
                             set(r.get('requestedOperatorNames') or []))
            a['lines'] = dict(a['lines'].most_common())
            part.update(a); part['status'] = 'checked'
        else:
            part['status'] = 'no-geometry'
        ride['parts'].append(part)
    return ride


def markdown(rides, notes):
    rows = ['| # | Store | Ride (old id<br>new id) | Legs | Display lines drawn | Solved/legs | Projected/legs | '
            'Max off-network m | Max off-line m | Max off-operator m | Max drawn↔solved m | Verdict |',
            '|---|---|---|---|---|---|---|---|---|---|---|---|']
    for n, ride in enumerate(rides, 1):
        lines = []
        for p in ride['parts']:
            for name in p['displayLines']:
                if not lines or lines[-1] != name: lines.append(name)
        checked = [p for p in ride['parts'] if p['status'] == 'checked']
        def mx(k): return max((p[k] for p in checked), default=0.0)
        net, off_line, off_op = mx('off_network_m'), mx('off_line_m'), mx('off_operator_m')
        dev = max((p['deviation_m'] for p in ride['parts']), default=0.0)
        nlegs = ride.get('census_legs') or len(ride['legs'])
        note = notes.get(ride['id'])
        all_solved = ride['has_census'] and not ride['unsolved_ride'] and ride['solved_legs'] >= nlegs
        if not all_solved: verdict = 'UNSOLVED'
        elif note: verdict = note
        elif ride['parts'] and not checked: verdict = 'CHECK (no-geometry)'
        elif max(net, off_line, off_op) < FLAG_M and dev < FLAG_M and len(checked) == len(ride['parts']): verdict = 'OK'
        else: verdict = 'CHECK'
        fmt = (lambda v: f'{v:.0f}') if checked else (lambda v: 'no-geometry')
        shown = ' → '.join(lines[:8]) + (' …' if len(lines) > 8 else '')
        rid = f"`{ride['old_id'] or '-'}`<br>`{ride['id']}`"
        rows.append(f"| {n} | {ride['store']} | {rid} | {nlegs} | {shown} | {ride['solved_legs']}/{nlegs} | "
                    f"{ride['projected_legs']}/{nlegs} | {fmt(net)} | {fmt(off_line)} | {fmt(off_op)} | {dev:.0f} | {verdict} |")
    return '\n'.join(rows) + '\n'


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--json', required=True)
    ap.add_argument('--census'); ap.add_argument('--geometry'); ap.add_argument('--notes'); ap.add_argument('--md')
    a = ap.parse_args()
    census = json.load(open(a.census, encoding='utf-8')) if a.census else []
    geom = {}
    if a.geometry:
        for g in json.load(open(a.geometry, encoding='utf-8')):
            geom[(g['ride'], g['segment'], g.get('part', 0))] = g.get('drawnCoordinates')
    by_ride = collections.defaultdict(list)
    for r in census: by_ride[r['ride']].append(r)
    idxs = {}; rides = load_rides()
    for ride in rides:
        audit_ride(ride, by_ride.get(ride['id'], []), idxs, geom)
    json.dump(rides, open(a.json, 'w'), ensure_ascii=False, indent=1)
    print(len(rides), 'rides')
    if a.census and a.md:
        notes = json.load(open(a.notes, encoding='utf-8')) if a.notes else {}
        Path(a.md).write_text(markdown(rides, notes), encoding='utf-8')


if __name__ == '__main__':
    main()
