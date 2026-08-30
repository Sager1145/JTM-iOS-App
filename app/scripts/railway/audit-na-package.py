#!/usr/bin/env python3
"""Re-check every line in a built package, against the package's own rules.

    python3 scripts/railway/audit-na-package.py \
        --package public/rail/us-2025.json \
        --package public/rail/ca-2025.json \
        --out /private/tmp/na-rail/audit.json

The builder decides; this asks, afterwards and from the outside, whether what
it shipped is what it said it would ship. That is a different question from
"did the build succeed", and it is the one a reader of the data actually has:
the builder cannot catch a rule it applied wrongly, because it is the thing
applying it.

Nothing here reads the sources. Every check is either an internal consistency
rule of `compact-v1` (a station table and a segment table that disagree about
how many intervals a line has is a broken file, whatever the sources said) or
a policy the package states in its own `sources.md` and can therefore be held
to (`na_profile`'s chord cap, the 2.2× detour test, the country's own
bounding box). Cross-source agreement is `report-na-coverage.py`'s job and
the builder's own cross-check; this is the layer between them.

Findings are graded, because a hundred cosmetic notes and one broken polyline
in the same list is a list nobody reads:

  ERROR  the file is wrong — it will draw wrongly, or decode wrongly
  WARN   the file is intact but breaks a policy the package states
  NOTE   a difference from the Japanese and Taiwanese packages' standard
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from na_profile import (CROSSCHECK_TOLERANCE_M, median_spacing_m,   # noqa: E402
                        profile_for)
from na_provenance import SOURCES as OFFICIAL_NETWORK_SOURCES       # noqa: E402

EARTH_R = 6_371_008.8

#: Where each country's railways are. Deliberately generous compared with
#: `RegionCatalog.networkBounds`, which frames a camera: this asks whether a
#: coordinate is in the right COUNTRY, so Hawai'i, Alaska and the Arctic are
#: in, and a vertex in the Atlantic is out.
COUNTRY_BOX = {
    'US': (17.5, -179.9, 71.6, -64.5),
    'CA': (41.6, -141.1, 83.2, -52.0),
}

#: The station id prefix each package's own `sources.md` promises, and which
#: `Region.fromStationCode` on iOS depends on to file a ride without a lookup.
ID_PREFIX = {'US': 'us-', 'CA': 'ca-'}


def haversine(a, b):
    lon1, lat1 = a
    lon2, lat2 = b
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_R * math.asin(min(1.0, math.sqrt(h)))


def local_xy(origin_lat):
    """Metres per degree at a latitude, for the small-area geometry below.

    Every distance this module compares against a tolerance is under a few
    kilometres and inside one line, so a local equirectangular frame is exact
    to far better than the tolerances involved, and it makes an angle and a
    circumradius ordinary arithmetic instead of spherical trigonometry.
    """
    mlat = 111_132.92 - 559.82 * math.cos(2 * math.radians(origin_lat))
    mlon = 111_412.84 * math.cos(math.radians(origin_lat))
    return mlon, mlat


def turn_degrees(a, b, c, mlon, mlat):
    """How far the line turns at ``b``. 0° is straight on, 180° is a reversal."""
    ax, ay = (a[0] - b[0]) * mlon, (a[1] - b[1]) * mlat
    cx, cy = (c[0] - b[0]) * mlon, (c[1] - b[1]) * mlat
    na = math.hypot(ax, ay)
    nc = math.hypot(cx, cy)
    if na < 1e-9 or nc < 1e-9:
        return 0.0
    cosine = max(-1.0, min(1.0, (ax * cx + ay * cy) / (na * nc)))
    return 180.0 - math.degrees(math.acos(cosine))


def circumradius(a, b, c, mlon, mlat):
    """The radius of the arc through three consecutive vertices, in metres."""
    ax, ay = (a[0] - b[0]) * mlon, (a[1] - b[1]) * mlat
    cx, cy = (c[0] - b[0]) * mlon, (c[1] - b[1]) * mlat
    na, nc = math.hypot(ax, ay), math.hypot(cx, cy)
    ac = math.hypot(ax - cx, ay - cy)
    area2 = abs(ax * cy - ay * cx)
    if area2 < 1e-9 or na < 1e-9 or nc < 1e-9 or ac < 1e-9:
        return float('inf')
    return (na * nc * ac) / (2 * area2)


def decode_intervals(line):
    """The polyline each station pair is drawn with — `CompactPackage.decodeIntervals`.

    Ported deliberately rather than approximated: an audit that decodes the
    file differently from the two clients is auditing a third package that
    nobody ships.
    """
    stations = line['stations']
    if not stations:
        return []
    out = []
    previous_last = None
    for index, row in enumerate(line['segments']):
        _, continues, coords = row[0], row[1], row[2]
        decoded = list(coords)
        if continues:
            head = previous_last if previous_last is not None else (
                decoded[0] if decoded else None)
            decoded = ([head] if head is not None else []) + decoded
        if not decoded:
            out.append([])
            continue
        start = stations[index % len(stations)]
        end = stations[(index + 1) % len(stations)]
        decoded[0] = [start[2], start[3]]
        decoded[-1] = [end[2], end[3]]
        previous_last = decoded[-1]
        out.append(decoded)
    return out


def polyline_length(points):
    return sum(haversine(points[i], points[i + 1]) for i in range(len(points) - 1))


def max_chord_deviation(points):
    """Largest perpendicular distance from an interval's endpoint chord.

    ``densify`` inserts collinear vertices, so vertex count cannot distinguish
    surveyed track from a station-to-station chord. Measure the shape itself
    and keep the audit able to see a long connector after storage grooming
    subdivides it.
    """
    if len(points) < 3:
        return 0.0
    mlon, mlat = local_xy(sum(p[1] for p in points) / len(points))
    ax, ay = points[0][0] * mlon, points[0][1] * mlat
    bx, by = points[-1][0] * mlon, points[-1][1] * mlat
    dx, dy = bx - ax, by - ay
    denom = dx * dx + dy * dy
    if denom <= 1e-9:
        return max(haversine(points[0], p) for p in points[1:-1])
    worst = 0.0
    for point in points[1:-1]:
        px, py = point[0] * mlon, point[1] * mlat
        t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / denom))
        worst = max(worst, math.hypot(px - (ax + t * dx),
                                      py - (ay + t * dy)))
    return worst


class Findings:
    def __init__(self):
        self.rows = []

    def add(self, severity, check, country, line_id, message, **detail):
        self.rows.append({'severity': severity, 'check': check,
                          'country': country, 'line': line_id,
                          'message': message, **detail})

    def counts(self):
        return Counter((r['severity'], r['check']) for r in self.rows)


# --------------------------------------------------------------------------
# per-line checks

def verified_official_networks(package, found):
    country = package.get('country')
    declared = ((package.get('geometrySource') or {})
                .get('verifiedOfficialNetworks') or {})
    verified = set()
    for key, provenance in declared.items():
        source_id = provenance.get('sourceId')
        expected = OFFICIAL_NETWORK_SOURCES.get(source_id) or {}
        hashes_valid = all(re.fullmatch(
            r'[0-9a-f]{64}', str(provenance.get(field) or '').lower())
                           for field in ('rawSha256', 'sha256'))
        if (provenance.get('publisher') != expected.get('publisher')
                or provenance.get('url') != expected.get('url')
                or not hashes_valid):
            found.add('ERROR', 'source.provenance', country, '-',
                      'verified official network has invalid provenance',
                      geometrySource=key)
        else:
            verified.add(key)
    return verified

def audit_line(line, country, found, verified_official=()):
    lid = line.get('id', '?')
    stations = line.get('stations') or []
    segments = line.get('segments') or []

    reference_colour = line.get('colorReference')
    if not (isinstance(reference_colour, str)
            and re.fullmatch(r'#[0-9a-fA-F]{6}', reference_colour)):
        found.add('ERROR', 'colour.reference', country, lid,
                  'missing or invalid operator-published colour')
    if not line.get('colorSource'):
        found.add('ERROR', 'colour.source', country, lid,
                  'line colour has no official provenance')

    # -- structure ---------------------------------------------------------
    if len(stations) < 2:
        found.add('ERROR', 'line.stations', country, lid,
                  'a railway with fewer than two stations', stations=len(stations))
        return None
    is_loop = bool(line.get('isLoop'))
    expected = len(stations) if is_loop else len(stations) - 1
    if len(segments) != expected:
        found.add('ERROR', 'line.intervals', country, lid,
                  'segment count does not match the station table',
                  segments=len(segments), stations=len(stations), isLoop=is_loop)

    intervals = decode_intervals(line)
    lengths = [polyline_length(p) for p in intervals if len(p) > 1]
    if not lengths:
        found.add('ERROR', 'line.geometry', country, lid, 'no drawable geometry')
        return None
    total_m = sum(lengths)
    profile = profile_for(median_spacing_m(lengths), total_m)
    stored_profile = line.get('smoothingProfile')
    if stored_profile != profile.name:
        found.add('ERROR', 'line.profile', country, lid,
                  'stored smoothing profile does not match final geometry',
                  stored=stored_profile, recomputed=profile.name)

    box = COUNTRY_BOX.get(country)
    seen_ids = Counter()
    worst_chord = 0.0
    chord_breaches = 0
    spike_count = 0
    tight_corners = 0
    duplicate_vertices = 0

    for index, points in enumerate(intervals):
        if len(points) < 2:
            found.add('ERROR', 'interval.empty', country, lid,
                      'an interval with no geometry', interval=index)
            continue
        a, b = stations[index % len(stations)], stations[(index + 1) % len(stations)]
        drawn = polyline_length(points)
        if drawn <= 1.0:
            found.add('ERROR', 'interval.length', country, lid,
                      'interval is not a drawable railway section',
                      interval=index, metres=round(drawn, 3))
        direct = haversine((a[2], a[3]), (b[2], b[3]))

        # The package's own implausibility test, applied to what shipped.
        if direct > 50 and drawn > 2.2 * direct:
            found.add('WARN', 'interval.detour', country, lid,
                      'drawn %.0f m between stations %.0f m apart (%.1fx)'
                      % (drawn, direct, drawn / direct),
                      interval=index, fromStation=a[1], toStation=b[1],
                      ratio=round(drawn / direct, 2))

        # Densification must not hide a direct station connector: a line with
        # thirty collinear vertices is still one chord. This intentionally
        # also names genuinely straight railway; provenance, not visual shape,
        # is what lets a reviewer clear that warning.
        chord_deviation = max_chord_deviation(points)
        if (line.get('geometrySource') not in verified_official
                and drawn > max(500.0, profile.max_edge_m * 2.0)
                and direct > 0 and drawn <= direct * 1.005
                and chord_deviation <= 1.5):
            found.add('ERROR', 'interval.straight', country, lid,
                      'drawn as a %.0f m endpoint chord (%d collinear vertices)'
                      % (drawn, len(points)),
                      interval=index, fromStation=a[1], toStation=b[1],
                      vertices=len(points),
                      maxDeviationMetres=round(chord_deviation, 2))

        mlon, mlat = local_xy(points[0][1])
        for j in range(len(points) - 1):
            edge = haversine(points[j], points[j + 1])
            if edge < 0.05:
                duplicate_vertices += 1
            if edge > profile.max_edge_m + 1.0:
                chord_breaches += 1
                worst_chord = max(worst_chord, edge)
        for j in range(1, len(points) - 1):
            turn = turn_degrees(points[j - 1], points[j], points[j + 1], mlon, mlat)
            if turn >= profile.spike_turn_deg + 40:
                spike_count += 1
            radius = circumradius(points[j - 1], points[j], points[j + 1], mlon, mlat)
            if radius < profile.min_radius_m * 0.5:
                tight_corners += 1

        # The seam: a row that does not continue from the previous one must
        # still start where the previous one ended, or the line has a hole in
        # it that only shows when it is drawn.
        if index and segments[index][1] == 0 and intervals[index - 1]:
            gap = haversine(intervals[index - 1][-1], points[0])
            if gap > 1.0:
                found.add('ERROR', 'interval.seam', country, lid,
                          'a %.0f m hole between consecutive intervals' % gap,
                          interval=index)

        if box:
            for point in points:
                if not (box[0] <= point[1] <= box[2] and box[1] <= point[0] <= box[3]):
                    found.add('ERROR', 'geometry.country', country, lid,
                              'a vertex outside the country at %.5f,%.5f'
                              % (point[1], point[0]), interval=index)
                    break

    if chord_breaches:
        found.add('WARN', 'geometry.chord', country, lid,
                  '%d edges longer than the %s band cap of %.0f m (worst %.0f m)'
                  % (chord_breaches, profile.name, profile.max_edge_m, worst_chord),
                  band=profile.name, count=chord_breaches,
                  worstMetres=round(worst_chord))
    if spike_count:
        found.add('WARN', 'geometry.spike', country, lid,
                  '%d near-reversals the sawtooth pass left in' % spike_count,
                  band=profile.name, count=spike_count)
    if tight_corners:
        found.add('WARN', 'geometry.radius', country, lid,
                  '%d corners under half the %s band minimum radius of %.0f m'
                  % (tight_corners, profile.name, profile.min_radius_m),
                  band=profile.name, count=tight_corners)
    if duplicate_vertices:
        found.add('NOTE', 'geometry.duplicate', country, lid,
                  '%d coincident consecutive vertices' % duplicate_vertices,
                  count=duplicate_vertices)

    # -- stations ----------------------------------------------------------
    prefix = ID_PREFIX.get(country)
    for station in stations:
        sid, name = station[0], station[1]
        seen_ids[sid] += 1
        if prefix and not str(sid).startswith(prefix):
            found.add('ERROR', 'station.prefix', country, lid,
                      'station id "%s" does not name its region' % sid)
        if not str(name).strip():
            found.add('ERROR', 'station.name', country, lid,
                      'a station with no name', station=sid)
    # Japan, Taiwan and Hong Kong ship no line that calls at one station
    # twice, and neither should these: a display line is a piece of railway,
    # so a repeated station means either an out-and-back service published as
    # one pattern, or two stations that were merged into one.
    for sid, count in seen_ids.items():
        if count > 1 and not is_loop:
            found.add('ERROR', 'station.repeat', country, lid,
                      'station %s appears %d times on one line' % (sid, count),
                      station=sid, times=count)

    return {'id': lid, 'band': profile.name, 'lengthKm': round(total_m / 1000, 1),
            'stations': len(stations), 'vertices': sum(len(p) for p in intervals)}


# --------------------------------------------------------------------------
# whole-package checks

CAPS = re.compile(r'^[^a-z]*[A-Z]{4,}[^a-z]*$')


def audit_package(package, found, band_by_line):
    country = package.get('country')
    lines = package['lines']

    ids = Counter(l.get('id') for l in lines)
    for lid, count in ids.items():
        if count > 1:
            found.add('ERROR', 'package.duplicateId', country, lid,
                      'the same line id appears %d times' % count)

    # A generated branch is meaningful only beside the trunk whose alternate
    # path it describes.  Route ids such as SEPTA B1 are not branches, so the
    # check uses explicit provenance emitted by the builder; guessing from an
    # id would misclassify official route ids such as SEPTA B1.
    line_ids = set(ids)
    for line in lines:
        branch_of = line.get('branchOf')
        if branch_of and branch_of not in line_ids:
            found.add('ERROR', 'line.orphanBranch', country, line['id'],
                      'branch is present but its trunk is absent',
                      trunk=branch_of)

    # Operator identity. The packages this family is modelled on name one
    # company one way; a GTFS feed names it however its author typed it, and
    # two spellings of one operator are two operators to every consumer.
    #
    # `\w` with the Unicode flag, NOT `a-z0-9`: the first version of this
    # check folded every name to the characters in that ASCII class, which for
    # 東日本旅客鉄道 is none of them. All 172 Japanese operators collapsed to the
    # empty key and were reported as one company under 172 names — a check
    # that fires on the whole of Japan is not a check.
    operators = Counter(l.get('operator') for l in lines if l.get('operator'))
    folded = defaultdict(list)
    for name in operators:
        key = re.sub(r'[^\w]+', '', (name or '').casefold(), flags=re.UNICODE)
        if key:
            folded[key].append(name)
    for key, names in folded.items():
        if len(names) > 1:
            found.add('ERROR', 'operator.duplicate', country, '-',
                      'one operator under %d spellings: %s'
                      % (len(names), ', '.join(sorted(names))), operators=sorted(names))

    # One name containing another is the other thing a feed does: VIA Rail
    # publishes eighteen lines as "VIA Rail" and one as "Via Rail Canada", and
    # the packages then carry twelve Canadian operators where there are eleven.
    # A WARN rather than an ERROR because it is genuinely ambiguous from inside
    # the data — "Metro" and "Metro Transit" really are two operators — so this
    # names the pair and leaves the answer to the registry's
    # `operatorOverride`, which is where a human answer belongs.
    keys = sorted(folded)
    for i, short in enumerate(keys):
        for long in keys[i + 1:]:
            if len(short) >= 4 and long.startswith(short):
                found.add('WARN', 'operator.nested', country, '-',
                          'one operator may be published twice: %s / %s'
                          % (', '.join(folded[short]), ', '.join(folded[long])),
                          operators=folded[short] + folded[long])
    # Only a name of more than one word. A single all-caps word is how the
    # operator writes its own name — MBTA, SEPTA, WMATA, CATS, NORTA — and
    # "Septa" is not a tidier spelling of SEPTA but the wrong name. This is
    # the same line `title_case_operator` draws in the builder, and the two
    # must agree or the audit reports the builder's correct answers as faults.
    for name in sorted(operators):
        if len((name or '').split()) > 1 and CAPS.match(name or ''):
            found.add('WARN', 'operator.shouting', country, '-',
                      'operator name is the feed\'s own capitals: "%s"' % name,
                      operator=name, lines=operators[name])

    # Parity with the standard the family is built to. Japan carries these and
    # the two clients decode them; a package without them is not wrong, it is
    # less than the packages beside it.
    for field, severity in (('logo', 'NOTE'), ('operatorShort', 'NOTE'),
                            ('kind', 'NOTE')):
        missing = [l['id'] for l in lines if not l.get(field)]
        if missing:
            found.add(severity, 'package.field:' + field, country, '-',
                      '%d of %d lines carry no `%s`'
                      % (len(missing), len(lines), field), count=len(missing))

    # A station that two lines both call by one id is anchored onto each of
    # their alignments in turn, so the two rows are not expected to be
    # identical — Japan's package carries the same drift, and more of it. What
    # is checked is whether the disagreement has outgrown the tolerance the
    # band already allows the geometry itself: past that, the two lines are
    # drawing two different places under one name.
    where = defaultdict(list)
    for line in lines:
        band = band_by_line.get(line['id'], 'commuter')
        for station in line.get('stations') or []:
            where[station[0]].append(
                (line['id'], station[1], station[2], station[3], band))
    for sid, rows in where.items():
        if len(rows) < 2:
            continue
        base = rows[0]
        for row in rows[1:]:
            drift = haversine((base[2], base[3]), (row[2], row[3]))
            allowed = max(CROSSCHECK_TOLERANCE_M.get(base[4], 90.0),
                          CROSSCHECK_TOLERANCE_M.get(row[4], 90.0))
            if drift > allowed:
                found.add('WARN', 'station.split', country, row[0],
                          'station %s is %.0f m from where %s puts it, past '
                          'the %.0f m the band allows' % (sid, drift, base[0],
                                                          allowed),
                          station=sid, metres=round(drift))
                break
        names = {r[1] for r in rows}
        if len(names) > 1:
            found.add('NOTE', 'station.names', country, '-',
                      'station %s is named %d ways: %s'
                      % (sid, len(names), ' / '.join(sorted(names))), station=sid)


def audit_registry(registry_path, summaries, found):
    """Did every feed the registry names actually produce a railway?

    The completeness question everything else asks is "which operators are in
    an independent inventory and not in the packages", and it is answered by
    comparing operator NAMES. That comparison has a blind spot it cannot see
    out of: an operator whose feed is in the registry, and whose railways are
    in the package because OpenStreetMap supplied them, counts as covered —
    even though the feed itself built nothing.

    The Société de transport de Montréal is the case that showed this. Its
    registry entry declares four rail routes; its GTFS feed builds none,
    because the operator publishes schematic shapes the builder is right to
    refuse. All three of its lines in the package came from OpenStreetMap, so
    the operator matched by name and no report anywhere said that a feed
    naming four railways had produced nothing.

    A feed that yields nothing is exactly as absent as a feed that does not
    exist, and only the second kind gets rescued by the OpenStreetMap path —
    so this asks the question directly, of the registry rather than of an
    inventory. It is the sharper gate because it needs no name matching at
    all: a line built from a feed carries that feed's slug in its id.
    """
    try:
        with open(registry_path) as fh:
            feeds = json.load(fh)['feeds']
    except (OSError, KeyError, ValueError) as exc:
        found.add('NOTE', 'registry.unreadable', '-', '-',
                  'could not read the registry: %s' % exc)
        return
    built = defaultdict(int)
    for row in summaries:
        line_id = row['id']
        if line_id.startswith('osm-'):
            continue
        # A line's id is `<feed slug>-<route slug>`; the longest slug that
        # prefixes it is its feed, because one slug can prefix another
        # (`amtrak` and `amtrak-san-joaquins` are both feeds).
        owner = None
        for feed in feeds:
            slug = feed['slug']
            if line_id == slug or line_id.startswith(slug + '-'):
                if owner is None or len(slug) > len(owner):
                    owner = slug
        if owner:
            built[owner] += 1
    for feed in feeds:
        declared = int(feed.get('railRoutes') or 0)
        if declared and not built[feed['slug']]:
            found.add('WARN', 'registry.silentFeed', feed.get('region', '-'),
                      feed['slug'],
                      'the registry names %d rail route(s) for %s and the '
                      'build produced none' % (declared, feed['name']),
                      declared=declared, operator=feed['name'])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--package', action='append', required=True)
    ap.add_argument('--registry',
                    help='scripts/railway/na-feeds.json — enables the check '
                         'that every feed the registry names actually built '
                         'something')
    ap.add_argument('--out')
    ap.add_argument('--max-print', type=int, default=40)
    options = ap.parse_args()

    found = Findings()
    summaries = []
    for path in options.package:
        with open(path) as fh:
            package = json.load(fh)
        country = package.get('country')
        verified_official = verified_official_networks(package, found)
        sys.stderr.write('%s: %d lines\n' % (country, len(package['lines'])))
        for line in package['lines']:
            row = audit_line(line, country, found, verified_official)
            if row:
                row['country'] = country
                summaries.append(row)
        audit_package(package, found,
                      {r['id']: r['band'] for r in summaries})

    if options.registry:
        audit_registry(options.registry, summaries, found)

    order = {'ERROR': 0, 'WARN': 1, 'NOTE': 2}
    found.rows.sort(key=lambda r: (order[r['severity']], r['check'], r['line']))

    counts = Counter(r['severity'] for r in found.rows)
    print('=' * 70)
    print('%d findings: %d ERROR, %d WARN, %d NOTE'
          % (len(found.rows), counts['ERROR'], counts['WARN'], counts['NOTE']))
    print('=' * 70)
    for (severity, check), count in sorted(found.counts().items(),
                                           key=lambda kv: (order[kv[0][0]], -kv[1])):
        print('  %-5s %-28s %5d' % (severity, check, count))
    print()
    for row in found.rows[:options.max_print]:
        print('%-5s %-24s %-34s %s'
              % (row['severity'], row['check'], row['line'][:34], row['message']))
    if len(found.rows) > options.max_print:
        print('... %d more' % (len(found.rows) - options.max_print))

    if options.out:
        with open(options.out, 'w') as fh:
            json.dump({'findings': found.rows, 'lines': summaries}, fh, indent=1)
        sys.stderr.write('wrote %s\n' % options.out)
    return 1 if counts['ERROR'] else 0


if __name__ == '__main__':
    sys.exit(main())
