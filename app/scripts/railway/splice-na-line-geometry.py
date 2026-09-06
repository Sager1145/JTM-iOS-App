#!/usr/bin/env python3
"""Splice ONE line's geometry from a candidate NA build into the shipped package.

Why this exists, and when to use it instead of ``merge-na-feed-build.py``
------------------------------------------------------------------------

``merge-na-feed-build.py`` merges a whole *feed*: it replaces every line the
feed owns, plus that feed's station features, its solver sections and the
region's station readings. That is the right tool when the fresh build is
authoritative for the feed as a whole -- including which stations exist,
what they are called and where their anchors sit.

It is the wrong tool when a rebuild improved only the *drawn track* and, as
a side effect, also re-derived station identity: a fresh build that renames
a station complex ("Boston" -> "South Station"), collapses two ids into one
("us-official-ny-moynihan-train-hall-at-penn" ->
"us-official-new-york-penn"), re-snaps a station anchor onto a different
reference network, or emits the line in the opposite direction. Accepting
those would change identity that other shipped artefacts (station readings,
saved journeys, the city ledger, the shared-corridor tables) are keyed on.

This tool does a strictly narrower thing: a **geometry-only splice**. It
copies the candidate's drawn track for a named line and nothing else. It
refuses -- loudly, per line -- to touch any line whose candidate station
list is not identical to the shipped one, id for id, in order, with
coordinates equal to within ``COORD_TOLERANCE_DEG``. That guard is not
cosmetic: a package line's segments are a chain anchored on its own station
coordinates (see the anchor check below), so candidate geometry can only be
laid under shipped stations when the two builds agree on where those
stations are. A candidate that moved an anchor by 40 m has, by definition,
drawn a line between different endpoints.

What it copies, per accepted line
---------------------------------

In ``app/public/rail/{region}-2025.json``:

* ``segments``, ``lengthKm``, ``geometrySource``, ``smoothingProfile``
* ``straightIntervals``, ``geometryReview``, ``extraSegments`` -- mirrored
  from the candidate, which means *removed* from the shipped line when the
  candidate does not carry them; a stale straight-interval survey or
  divergence row would describe track that is no longer drawn.
* ``geometrySource.officialGeometryComparison.byLine[<line id>]`` -- the
  candidate's measurement record replaces the shipped one, and the
  package-level ``maxDeviationMeters`` is recomputed as the max over the
  resulting ``byLine``.

In ``app/data/rail-sections-{region}.json``:

* the LineString geometry of the rows the route solver uses for this line.
  ``build-north-america-rail-package.py`` emits one section Feature per
  package interval, in interval order, in the same per-line pass that
  appends the package line -- so a line's sections are a contiguous run.
  This tool does not trust that ordering blindly: it locates the run by
  matching ``(line_name, operator)`` *and* requiring every geometry in the
  run to equal the shipped line's own decoded intervals exactly, then
  requires the candidate to supply the same number of rows. Properties are
  never touched, and every other row in the file stays byte-identical.

What it never touches
---------------------

``app/data/stations-{region}.json`` and
``app/data/station-readings-{region}.json``. Station identity, names, codes
and readings are out of scope by construction. If a candidate build should
also change those, it is a feed merge, not a geometry splice -- use
``merge-na-feed-build.py``.

It also regenerates nothing. ``merge-na-feed-build.py`` re-runs
``audit-na-package.py`` and ``make-na-line-review.py`` after writing; this
tool leaves that to the caller, so a batch of ``--line-id`` splices can be
audited once at the end rather than once per line.

Usage::

    splice-na-line-geometry.py --candidate <build dir> --region us \\
        --line-id amtrak-crescent --line-id amtrak-palmetto [--dry-run]

``<build dir>`` is a ``build-north-america-rail-package.py`` output tree:
``<dir>/public/{region}-2025.json`` and ``<dir>/data/rail-sections-{region}.json``.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_APP_ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))

#: Station coordinates are shipped rounded to 6 decimals, so this tolerance
#: is "equal at the precision the package stores", with a hair of slack for
#: float round-tripping -- not a spatial tolerance. Anything a build
#: actually moved fails it, which is the point.
COORD_TOLERANCE_DEG = 1e-7

#: Geometry-describing fields mirrored from the candidate line: present in
#: the candidate -> copied; absent -> removed from the shipped line.
MIRRORED_OPTIONAL_FIELDS = ('straightIntervals', 'geometryReview',
                            'extraSegments')

#: Geometry-describing fields that every line carries and that are always
#: copied across.
COPIED_REQUIRED_FIELDS = ('segments', 'lengthKm', 'geometrySource',
                          'smoothingProfile')


# --------------------------------------------------------------------- I/O


def load_json(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def write_json_compact(path, payload):
    """Byte-for-byte match the builder's own ``write_json``.

    Same separators, same ``ensure_ascii=False``, same absence of a trailing
    newline, same atomic tmp-then-replace. Verified against the shipped
    files: re-serialising an untouched package or sections file this way
    reproduces it byte for byte.
    """
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(', ', ': '))
    os.replace(tmp, path)
    return os.path.getsize(path)


# ------------------------------------------------------------- geometry


def decode_intervals(segments):
    """The full per-interval polylines a compact-v1 ``segments`` list encodes.

    A row is ``[km, continuesFromPrevious, coordinates]``. A row with
    ``continuesFromPrevious == 1`` omits the vertex it shares with the
    previous row, so decoding prepends the previous interval's last vertex.
    A degenerate interval ships as ``[0.0, flag, []]`` and decodes to an
    empty list.
    """
    intervals = []
    previous_end = None
    for row in segments:
        coords = [list(point) for point in row[2]]
        if not coords:
            intervals.append([])
            continue
        if row[1] and previous_end is not None:
            coords = [list(previous_end)] + coords
        intervals.append(coords)
        previous_end = coords[-1]
    return intervals


def check_anchor_coincidence(line):
    """Every station anchor must be an interval endpoint of its own chain.

    Returns a list of human-readable problems; empty means the line's
    decoded geometry starts and ends each interval exactly on the station
    rows that bound it.
    """
    stations = line.get('stations') or []
    intervals = decode_intervals(line.get('segments') or [])
    problems = []
    count = len(stations)
    if count < 2:
        return problems
    expected = count if line.get('isLoop') else count - 1
    if len(intervals) != expected:
        problems.append(
            f'{len(intervals)} intervals for {count} stations '
            f'(expected {expected})')
        return problems
    for index, interval in enumerate(intervals):
        if not interval:
            continue
        start_station = stations[index]
        end_station = stations[(index + 1) % count]
        for label, point, station in (
                ('start', interval[0], start_station),
                ('end', interval[-1], end_station)):
            if (abs(point[0] - station[2]) > COORD_TOLERANCE_DEG or
                    abs(point[1] - station[3]) > COORD_TOLERANCE_DEG):
                problems.append(
                    f'interval #{index} {label} {point} does not sit on '
                    f'{station[0]} {[station[2], station[3]]}')
    return problems


def stations_match(shipped_line, candidate_line):
    """None when the two lines describe the same stations, else the reason."""
    a = shipped_line.get('stations') or []
    b = candidate_line.get('stations') or []
    if len(a) != len(b):
        return (f'station count differs: shipped {len(a)}, '
                f'candidate {len(b)}')
    for index, (x, y) in enumerate(zip(a, b)):
        if x[0] != y[0]:
            return (f'station #{index} id differs: shipped {x[0]!r} '
                    f'({x[1]!r}), candidate {y[0]!r} ({y[1]!r})')
    for index, (x, y) in enumerate(zip(a, b)):
        if (abs(x[2] - y[2]) > COORD_TOLERANCE_DEG or
                abs(x[3] - y[3]) > COORD_TOLERANCE_DEG):
            return (f'station #{index} {x[0]!r} moved: shipped '
                    f'[{x[2]}, {x[3]}], candidate [{y[2]}, {y[3]}]')
    return None


# -------------------------------------------------------------- sections


def section_geometries(line):
    """The section LineStrings the builder emits for one package line."""
    return [interval for interval in decode_intervals(line.get('segments') or [])
            if len(interval) >= 2]


def find_section_run(features, line, geometries):
    """Index of the contiguous run of section rows belonging to ``line``.

    Matched on the builder's own key -- ``(line_name, operator)`` -- plus
    exact geometry equality against the line's decoded intervals, so a run
    is only accepted when it really is this line's track and not another
    line that happens to share a name.

    Returns ``(start_index, error)``: exactly one of the two is None.
    """
    key = (line.get('name'), line.get('operator'))
    want = len(geometries)
    if not want:
        return None, 'line decodes to no drawable interval'
    matches = []
    for start in range(0, len(features) - want + 1):
        window = features[start:start + want]
        if any((f['properties'].get('line_name'),
                f['properties'].get('operator')) != key for f in window):
            continue
        if all(f['geometry']['coordinates'] == geometry
               for f, geometry in zip(window, geometries)):
            matches.append(start)
    if not matches:
        return None, (f'no run of {want} section rows for '
                      f'{key[0]!r} / {key[1]!r} matches the shipped geometry')
    if len(matches) > 1:
        return None, (f'{len(matches)} runs of section rows match '
                      f'{key[0]!r} / {key[1]!r} ambiguously')
    return matches[0], None


# ----------------------------------------------------------------- splice


def plan_line(line_id, shipped_lines, candidate_lines,
              shipped_sections, candidate_sections):
    """Validate one line and return what applying it would change.

    Returns ``(plan, skip_reason)``; exactly one is None. Nothing is
    mutated: the anchor check runs against a copy, so a line that would
    produce a broken chain is skipped rather than half-applied.
    """
    shipped = shipped_lines.get(line_id)
    candidate = candidate_lines.get(line_id)
    if shipped is None:
        return None, 'not in the shipped package'
    if candidate is None:
        return None, 'not in the candidate package'

    reason = stations_match(shipped, candidate)
    if reason is not None:
        return None, reason

    spliced = copy.deepcopy(shipped)
    for field in COPIED_REQUIRED_FIELDS:
        if field not in candidate:
            return None, f'candidate line has no {field!r}'
        spliced[field] = copy.deepcopy(candidate[field])
    removed = []
    for field in MIRRORED_OPTIONAL_FIELDS:
        if field in candidate:
            spliced[field] = copy.deepcopy(candidate[field])
        elif field in spliced:
            del spliced[field]
            removed.append(field)

    problems = check_anchor_coincidence(spliced)
    if problems:
        return None, 'anchor check failed: ' + '; '.join(problems[:3])

    shipped_geometries = section_geometries(shipped)
    candidate_geometries = section_geometries(candidate)
    start, error = find_section_run(shipped_sections, shipped,
                                    shipped_geometries)
    if error is not None:
        return None, f'shipped sections: {error}'
    if len(candidate_geometries) != len(shipped_geometries):
        return None, (f'section count differs: shipped '
                      f'{len(shipped_geometries)}, candidate '
                      f'{len(candidate_geometries)}')
    candidate_start, error = find_section_run(candidate_sections, candidate,
                                              candidate_geometries)
    if error is not None:
        return None, f'candidate sections: {error}'

    return {
        'lineId': line_id,
        'spliced': spliced,
        'removedFields': removed,
        'sectionStart': start,
        'sectionGeometries': candidate_geometries,
        'before': {
            'vertices': sum(len(interval) for interval in shipped_geometries),
            'km': shipped.get('lengthKm'),
            'source': shipped.get('geometrySource'),
        },
        'after': {
            'vertices': sum(len(interval)
                            for interval in candidate_geometries),
            'km': candidate.get('lengthKm'),
            'source': candidate.get('geometrySource'),
        },
    }, None


def splice_region(region, candidate_dir, line_ids, app_root, dry_run):
    package_path = os.path.join(app_root, 'public', 'rail',
                                f'{region}-2025.json')
    sections_path = os.path.join(app_root, 'data',
                                f'rail-sections-{region}.json')
    candidate_package_path = os.path.join(candidate_dir, 'public',
                                          f'{region}-2025.json')
    candidate_sections_path = os.path.join(candidate_dir, 'data',
                                           f'rail-sections-{region}.json')

    package = load_json(package_path)
    sections = load_json(sections_path)
    candidate_package = load_json(candidate_package_path)
    candidate_sections = load_json(candidate_sections_path)

    shipped_lines = {line['id']: line for line in package['lines']}
    candidate_lines = {line['id']: line for line in candidate_package['lines']}
    shipped_features = sections['features']
    candidate_features = candidate_sections['features']

    comparison = (package.get('geometrySource', {})
                  .get('officialGeometryComparison') or {})
    by_line = comparison.get('byLine')
    candidate_by_line = (candidate_package.get('geometrySource', {})
                         .get('officialGeometryComparison', {})
                         .get('byLine') or {})

    plans, skips = [], []
    claimed = {}
    for line_id in line_ids:
        plan, reason = plan_line(line_id, shipped_lines, candidate_lines,
                                 shipped_features, candidate_features)
        if reason is not None:
            skips.append((line_id, reason))
            continue
        # Two lines must never resolve to the same section rows; if they do,
        # the run match was not as unique as it looked.
        span = range(plan['sectionStart'],
                     plan['sectionStart'] + len(plan['sectionGeometries']))
        clash = next((claimed[i] for i in span if i in claimed), None)
        if clash is not None:
            skips.append((line_id,
                          f'section rows already claimed by {clash}'))
            continue
        for index in span:
            claimed[index] = line_id
        plans.append(plan)

    print(f'== {region} ==')
    print(f'  package: {package_path}')
    print(f'  sections: {sections_path}')
    print(f'  candidate: {candidate_dir}')
    print(f'  requested: {len(line_ids)}  spliced: {len(plans)}  '
          f'skipped: {len(skips)}')
    for plan in plans:
        before, after = plan['before'], plan['after']
        note = ''
        if plan['removedFields']:
            note = '  removed ' + ','.join(plan['removedFields'])
        print(f"  SPLICE  {plan['lineId']}: "
              f"{before['vertices']}->{after['vertices']} vertices, "
              f"{before['km']}->{after['km']} km, "
              f"{before['source']}->{after['source']}{note}")
    for line_id, reason in skips:
        print(f'  SKIP    {line_id}: {reason}')

    if dry_run:
        print(f'  (dry run: {package_path} and {sections_path} untouched)')
        return len(plans), skips

    for plan in plans:
        line_id = plan['lineId']
        index = next(i for i, line in enumerate(package['lines'])
                     if line['id'] == line_id)
        package['lines'][index] = plan['spliced']
        for offset, geometry in enumerate(plan['sectionGeometries']):
            shipped_features[plan['sectionStart'] + offset]['geometry'][
                'coordinates'] = geometry
        if by_line is not None:
            if line_id in candidate_by_line:
                by_line[line_id] = copy.deepcopy(candidate_by_line[line_id])
            elif line_id in by_line:
                del by_line[line_id]
                print(f'  note: {line_id} has no candidate geometry '
                      f'comparison record; removed the shipped one')

    if plans and by_line is not None:
        worst = max((record.get('maxDeviationMeters', 0.0)
                     for record in by_line.values()), default=0.0)
        previous = comparison.get('maxDeviationMeters')
        comparison['maxDeviationMeters'] = round(worst, 2)
        print(f"  officialGeometryComparison.maxDeviationMeters: "
              f"{previous} -> {comparison['maxDeviationMeters']}")

    if plans:
        print(f'  wrote {package_path} '
              f'({write_json_compact(package_path, package)} bytes)')
        print(f'  wrote {sections_path} '
              f'({write_json_compact(sections_path, sections)} bytes)')
    else:
        print('  nothing to write')
    return len(plans), skips


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--candidate', required=True,
                        help='candidate build directory (with public/ and data/)')
    parser.add_argument('--region', required=True, choices=('us', 'ca'))
    parser.add_argument('--line-id', action='append', required=True,
                        dest='line_ids', help='line id to splice (repeatable)')
    parser.add_argument('--dry-run', action='store_true',
                        help='report what would change, write nothing')
    parser.add_argument('--app-root', default=DEFAULT_APP_ROOT,
                        help='repo app/ directory (default: this script\'s)')
    args = parser.parse_args(argv)

    spliced, skips = splice_region(args.region, args.candidate,
                                   args.line_ids, args.app_root, args.dry_run)
    return 0 if spliced or not skips else 1


if __name__ == '__main__':
    sys.exit(main())
