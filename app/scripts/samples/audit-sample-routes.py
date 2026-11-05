#!/usr/bin/env python3
"""Mechanically check every bundled sample ride against the displayed rail network.

For each precomputed ride (app/data/sample-data*/, *-loop-data/), every route
feature is resampled every STEP metres and each sample is matched against the
compact-v1 display package (app/public/rail/<cc>-2025.json, the geometry the
"display all rail routes" layer draws) within TOL metres. Reported per ride:
  - lines/operators the route actually runs on (display attribution),
  - off_network_m: longest run of samples with no display line within TOL
    (straight chords and missing geometry show up here),
  - off_line_m: longest run whose display lines are all outside the ride's
    preferred/required line names (wrong branch / wrong line),
  - off_operator_m: same for required/preferred operator names (wrong operator),
  - endpoint gaps are ignored for the first/last END_SKIP metres of a feature.
With --census (the JSON written by RailCoreTests/SampleTripDisplayCensusTests,
which runs the app's own RouteNetwork.precomputedDisplayParts on every leg) and
--md, one markdown row per ride is written combining both checks.
Usage: python3 -I app/scripts/samples/audit-sample-routes.py --json out.json \
         [--census census.json --md table.md]
"""
import argparse, collections, glob, json, math
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
STEP, TOL, END_SKIP = 25.0, 60.0, 450.0
DIRS = {'sample-data': 'jp', 'new-year-grand-loop-data': 'jp', 'tokyo-limited-express-loop-data': 'jp',
        'sample-data-tw': 'tw', 'sample-data-hk': 'hk', 'sample-data-kr': 'kr', 'sample-data-mo': 'mo'}
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


def audit_feature(idx, ft):
    pr = ft['properties']; g = ft['geometry']
    polys = [g['coordinates']] if g['type'] == 'LineString' else g['coordinates']
    lines_ok = set(pr.get('preferred_line_names') or []) | set(pr.get('required_line_names') or [])
    ops_ok = set(pr.get('required_operator_names') or []) | set(pr.get('preferred_operator_names') or [])
    res = {'from': pr.get('from'), 'to': pr.get('to'), 'mode': pr.get('solve_mode'), 'pref_lines': sorted(lines_ok),
           'length_m': 0.0, 'off_network_m': 0.0, 'off_line_m': 0.0, 'off_operator_m': 0.0, 'lines': collections.Counter(),
           'operators': collections.Counter()}
    for poly in polys:
        if len(poly) < 2: continue
        samples = densify(poly, STEP); total = samples[-1][1]; res['length_m'] += total
        off_net, off_line, off_op, ds = [], [], [], []
        for c, d in samples:
            interior = END_SKIP <= d <= total - END_SKIP
            hit = idx.near(c)
            for i in hit:
                res['lines'][idx.lines[i][0]] += 1; res['operators'][idx.lines[i][1]] += 1
            names = {idx.lines[i][0] for i in hit}; ops = {idx.lines[i][1] for i in hit}
            off_net.append(interior and not hit)
            off_line.append(interior and bool(hit) and bool(lines_ok) and not (names & lines_ok))
            off_op.append(interior and bool(hit) and bool(ops_ok) and not (ops & ops_ok))
            ds.append(d)
        res['off_network_m'] = max(res['off_network_m'], longest(off_net, ds))
        res['off_line_m'] = max(res['off_line_m'], longest(off_line, ds))
        res['off_operator_m'] = max(res['off_operator_m'], longest(off_op, ds))
    return res


FLAG_M = 150.0  # runs shorter than this are sampling noise at TOL


def markdown(rides, census, notes):
    by_leg = collections.defaultdict(list)
    for leg in census:
        by_leg[(leg['ride'], leg['from'], leg['to'])].append(leg)
    rows = ['| # | Store | Ride | Legs | Display lines drawn (in order) | Projected legs | Max off-network m | '
            'Max off-line m | Max off-operator m | Max drawn↔solved m | Verdict |',
            '|---|---|---|---|---|---|---|---|---|---|---|']
    for n, ride in enumerate(rides, 1):
        lines, projected, worst_dev = [], 0, 0.0
        for leg in ride['legs']:
            cs = by_leg.get((ride['id'], leg['from'], leg['to'])) or []
            for c in cs:
                projected += c['projected']
                worst_dev = max(worst_dev, c['sourceToDrawnMaxM'], c['drawnToSourceMaxM'])
                names = c['displayLines'] if c['projected'] else list(leg['lines'])[:1]
                for name in names:
                    if not lines or lines[-1] != name: lines.append(name)
        net = max((l['off_network_m'] for l in ride['legs']), default=0)
        off_line = max((l['off_line_m'] for l in ride['legs']), default=0)
        off_op = max((l['off_operator_m'] for l in ride['legs']), default=0)
        note = notes.get(ride['id'])
        if ride.get('status'): verdict = 'UNSOLVED'
        elif note: verdict = note
        elif max(net, off_line, off_op) < FLAG_M and worst_dev < FLAG_M: verdict = 'OK'
        else: verdict = 'CHECK'
        shown = ' → '.join(lines[:8]) + (' …' if len(lines) > 8 else '')
        rows.append(f"| {n} | {ride['store']} | `{ride['id']}` | {len(ride['legs'])} | {shown} | "
                    f"{projected}/{len(ride['legs'])} | {net:.0f} | {off_line:.0f} | {off_op:.0f} | {worst_dev:.0f} | {verdict} |")
    return '\n'.join(rows) + '\n'


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--json', required=True)
    ap.add_argument('--census'); ap.add_argument('--notes'); ap.add_argument('--md'); a = ap.parse_args()
    idxs = {}; rides = []
    for d, cc in DIRS.items():
        idx = idxs.setdefault(cc, Index(cc))
        for f in sorted(glob.glob(str(APP / 'data' / d / 'part-*.json'))):
            p = json.load(open(f)); t = p['train']; r = p['route']
            ride = {'store': d, 'id': t['id'], 'number': t.get('number'), 'sections': [], 'legs': []}
            for s in t.get('route_sections') or []:
                ride['sections'].append({'from': s.get('from') or s.get('from_station'), 'to': s.get('to') or s.get('to_station'),
                                         'lines': s.get('line_names') or []})
            if not r or r.get('unsolvable'):
                ride['status'] = 'UNSOLVED'; rides.append(ride); continue
            for ft in r['features']:
                leg = audit_feature(idx, ft)
                leg['lines'] = dict(leg['lines'].most_common()); leg['operators'] = dict(leg['operators'].most_common())
                ride['legs'].append(leg)
            rides.append(ride)
    json.dump(rides, open(a.json, 'w'), ensure_ascii=False, indent=1)
    print(len(rides), 'rides')
    if a.census and a.md:
        notes = json.load(open(a.notes)) if a.notes else {}
        Path(a.md).write_text(markdown(rides, json.load(open(a.census)), notes))


if __name__ == '__main__':
    main()
