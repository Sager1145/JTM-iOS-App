#!/usr/bin/env python3
"""Merge one feed's freshly-built objects into a shipped NA rail package.

`build-north-america-rail-package.py` rebuilds every feed in the registry in
one pass, which needs every feed's raw sources on disk. When only one feed's
sources are available (for example: a single operator's GTFS plus its
official geometry, downloaded to review a fix for that operator alone), a
scoped build with ``--only <feed-slug>`` still produces a real, audited
package -- just one that only contains that feed's lines. This tool takes
that scoped candidate build and splices its objects into the shipped
multi-feed package, in place of whatever the feed shipped with before,
leaving every other feed's bytes untouched.

It identifies a feed's objects the same way the builder's own output does:

* line records carry ``sourceFeed`` (the registry slug), so a feed's lines in
  ``{region}-2025.json`` are exactly the ones with that value;
* stations (``stations-{region}.json``) and sections
  (``rail-sections-{region}.json``) are GeoJSON FeatureCollections with no
  line/feed id of their own -- only ``properties.operator``, which this tool
  confirms is exclusive to the feed's own lines before using it to select
  what to remove;
* ``station-readings-{region}.json`` is not partitionable by feed at all: its
  ``byCode``/``byName`` maps are built by ``readings_for()`` walking every
  region's station features in order and can share a slot across operators
  at a real interchange (LIRR's Jamaica and NYCT's Jamaica get the same
  ``n02_group_code``). So instead of splicing this file, the tool calls the
  builder's own ``readings_for()`` over the *merged* station feature list --
  the exact function a real rebuild would run, over the same effective input.

After splicing the four data files it refreshes the package's own derived
header fields (``geometrySource.verifiedOfficialNetworks``,
``officialGeometryComparison.byLine/lines/maxDeviationMeters``,
``syntheticConnectors``) using the same rules ``build_region()`` uses to
compute them, patches the feed's entry into ``na-2025-build-report.json``,
and then -- for a real (non-dry-run) merge -- calls this repo's own
``audit-na-package.py`` and ``make-na-line-review.py`` to regenerate
``{region}-2025.audit.json``, ``na-2025.audit.json`` and
``na-2025-line-review.{json,md}`` from the merged package, rather than
reimplementing their logic here. ``{region}-2025.audit.md`` and
``{region}-2025.sources.md`` have no such generator in this repo (they are
hand-authored prose); this tool refreshes only their numeric lead paragraph
from the freshly regenerated audit, leaving the rest of the prose alone.

Usage::

    merge-na-feed-build.py --candidate <dir> --feed lirr --region us [--dry-run]
"""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
APP_ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))

#: Short spoken names accepted for --feed, mapped to the registry slug used
#: as `sourceFeed` on every line the builder produces for that feed. Extend
#: this as more single-feed candidate builds get merged this way.
FEED_ALIASES = {
    'lirr': 'mta-long-island-rail-road',
}

#: Which other region's package/audit a region's line-review and combined
#: audit are built from, mirroring `for region in ('us', 'ca')` in the
#: builder itself.
SIBLING_REGION = {'us': 'ca', 'ca': 'us'}

#: A candidate station within this many metres of a shipped station of the
#: same operator is treated as the same physical place, regardless of what
#: name or code the fresh build assigned it.
STATION_IDENTITY_COORD_TOLERANCE_M = 15.0

#: A looser tolerance used only when the two stations' normalised names also
#: match exactly -- catches a station whose surveyed anchor moved a little
#: between builds (a corrected entrance, a re-surveyed platform centre)
#: without treating every unrelated same-named station pair as one place.
STATION_IDENTITY_NAME_TOLERANCE_M = 60.0


def resolve_feed_slug(feed_arg):
    return FEED_ALIASES.get(feed_arg, feed_arg)


# --------------------------------------------------------------------- I/O


def load_json(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def write_json_compact(path, payload):
    """Byte-for-byte match `build-north-america-rail-package.py`'s write_json.

    Same separators, same `ensure_ascii=False`, same lack of an appended
    newline, same atomic tmp-then-replace.
    """
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(', ', ': '))
    os.replace(tmp, path)
    return os.path.getsize(path)


def compact_size(payload):
    """The byte size write_json_compact would produce, without writing."""
    return len(json.dumps(payload, ensure_ascii=False,
                          separators=(', ', ': ')).encode('utf-8'))


_BUILD_MODULE = None


def load_build_module():
    """Import build-north-america-rail-package.py for its readings_for().

    Loaded the same way tests/test_na_line_review.py loads its sibling
    script: by file location, since the module's name is not a valid Python
    identifier. Reusing the builder's own readings_for() (rather than
    reimplementing it) is what keeps station-readings merges correct at
    shared interchanges -- see the readings_for docstring above.
    """
    global _BUILD_MODULE
    if _BUILD_MODULE is not None:
        return _BUILD_MODULE
    script = os.path.join(HERE, 'build-north-america-rail-package.py')
    spec = importlib.util.spec_from_file_location(
        'na_feed_merge_builder', script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    _BUILD_MODULE = module
    return module


# ------------------------------------------------------------------ lines


def merge_lines(shipped_lines, candidate_lines, feed_slug, line_ids=None):
    """Replace shipped line(s) of `feed_slug` with the candidate's lines.

    The candidate's lines are spliced in at the position of the first
    removed line (or appended, if the feed is new), so the feed's block
    stays roughly where it was instead of moving to the end of the array.

    With `line_ids` (an id set), this is a splice rather than a full-feed
    replace: only shipped lines whose own `id` is in the set are removed,
    and `candidate_lines` is expected to already be pre-filtered to that
    same set (see `scope_candidate_to_lines`). Without it, every shipped
    line of the feed is removed and every candidate line of the feed is
    inserted, as before.

    Returns (merged_lines, removed_ids, added_ids).
    """
    removed_ids = []
    insert_at = None
    kept = []
    for line in shipped_lines:
        if line.get('sourceFeed') != feed_slug:
            kept.append(line)
            continue
        if line_ids is not None and line['id'] not in line_ids:
            kept.append(line)
            continue
        removed_ids.append(line['id'])
        if insert_at is None:
            insert_at = len(kept)
    new_lines = [line for line in candidate_lines
                if line.get('sourceFeed') == feed_slug]
    added_ids = [line['id'] for line in new_lines]
    if insert_at is None:
        insert_at = len(kept)
    merged = kept[:insert_at] + new_lines + kept[insert_at:]
    return merged, removed_ids, added_ids


def scope_candidate_to_lines(candidate, feed_slug, line_ids):
    """Restrict a candidate build to exactly `line_ids`, features included.

    A scoped `--only <feed>` build still produces every line the feed owns
    -- LA Metro's B Line candidate build also contains the other five LA
    Metro lines. Splicing all of it in is safe only when none of the feed's
    operator names are shared with an already-shipped line outside the feed
    (`feed_operators` refuses otherwise, e.g. metro-transit-intercity-tran,
    whose ``Sound Transit``/``City of Seattle``/``Amtrak`` lines collide
    with lines already shipped by other feeds even though its Seattle
    Center Monorail line's own operator, unique to that one line, does
    not). This is the escape: keep only the requested line ids and only
    the station/section features whose ``properties.operator`` belongs to
    one of them, so a feed that cannot be merged whole can still have the
    one line out of it that is actually clear to ship.

    Station/section features carry no line id of their own, only
    ``properties.operator`` (see `merge_features`'s docstring) -- which is
    why this can only scope down to the *operators* the requested lines
    use, not to those lines' stations exactly. That is the same
    approximation `feed_operators`/`merge_features` already make for a
    whole-feed merge; scoping first just narrows which operators it is
    made for.
    """
    lines = [line for line in candidate['package']['lines']
            if line.get('sourceFeed') == feed_slug and line['id'] in line_ids]
    found = {line['id'] for line in lines}
    missing = set(line_ids) - found
    if missing:
        raise ValueError(
            'requested --line-id %r not found in this feed\'s candidate '
            'build' % sorted(missing))
    operators = {line.get('operator') for line in lines}
    operators.discard(None)

    def keep(features):
        return [f for f in features
               if f.get('properties', {}).get('operator') in operators]

    scoped = copy.deepcopy(candidate)
    scoped['package'] = dict(candidate['package'])
    scoped['package']['lines'] = lines
    scoped['stations'] = {
        'type': 'FeatureCollection',
        'features': keep(candidate['stations']['features']),
    }
    scoped['sections'] = {
        'type': 'FeatureCollection',
        'features': keep(candidate['sections']['features']),
    }
    return scoped


def _owns(line, feed_slug, line_ids):
    if line.get('sourceFeed') != feed_slug:
        return False
    return line_ids is None or line.get('id') in line_ids


def feed_operators(shipped_lines, candidate_lines, feed_slug, line_ids=None):
    """The operator name(s) used by this feed's lines.

    Stations and sections carry no feed id, only `properties.operator`.
    Historically this was also the removal key for merge_features() and this
    function raised the moment an operator string was shared with a line
    outside the feed (e.g. "SEPTA" naming both `septa` and
    `septa-regional-rail`). It no longer raises: `feed_station_removal_keys()`
    and `feed_section_removal_keys()` below derive an exact, collision-proof
    removal key from the feed's OWN currently-shipped lines instead, so an
    operator name collision no longer has to block a merge. Use
    `operator_collision()` to find out whether one exists (e.g. to decide
    whether a warning is warranted for a fallback path).

    With `line_ids`, "this feed's lines" narrows further to just the
    requested ids: a shipped line of the same feed that is *not* one of
    them is "outside" for this purpose too, exactly like a line from a
    different feed. This is what lets a single line be spliced out of a
    feed whose other lines share an operator with something already shipped
    elsewhere -- e.g. Seattle Center Monorail's own operator collides with
    nothing, even though its feed's Sound Transit lines collide with the
    separately-shipped `sound-transit` feed.
    """
    def owns(line):
        return _owns(line, feed_slug, line_ids)

    ops = {line.get('operator') for line in shipped_lines if owns(line)}
    ops |= {line.get('operator') for line in candidate_lines if owns(line)}
    ops.discard(None)
    return ops


def operator_collision(shipped_lines, feed_slug, line_ids=None, ops=None):
    """Operator name(s) this feed shares with a line outside it, if any.

    `ops` may be passed in (e.g. the result of `feed_operators()`) to avoid
    recomputing it; otherwise it is derived from `shipped_lines` alone.
    Returns an empty set when there is no collision.
    """
    def owns(line):
        return _owns(line, feed_slug, line_ids)

    if ops is None:
        ops = {line.get('operator') for line in shipped_lines if owns(line)}
        ops.discard(None)
    other_feed_ops = {line.get('operator') for line in shipped_lines
                      if not owns(line)}
    return ops & other_feed_ops


def station_feed_prefix(region, feed_slug):
    """The `n02_station_code` prefix build_region() assigns to `feed_slug`'s
    own station features in `region`.

    `station_features.append()` in build-north-america-rail-package.py
    builds `n02_station_code` as
    `{REGION}-{FEED}-{OPERATOR}-{stationId}-{groupCode}`, so this prefix
    identifies a feature as belonging to this feed with total certainty --
    unlike `(operator, n02_group_code)` (see `feed_station_removal_keys()`),
    which is not always enough: Amtrak's own `amtrak-shore-line-east` line
    and the separately-shipped `shore-line-east` feed both use operator
    "Shore Line East" AND the identical `us-official-new-haven` group code
    for their shared New Haven Line stop, since it genuinely is the same
    physical place. `(operator, group_code)` alone cannot tell those two
    feeds' rows apart there; requiring this prefix too can, because it is
    the one place a station feature carries its owning feed explicitly.
    """
    return '%s-%s-' % (region.upper(), feed_slug.upper())


def feed_station_removal_keys(shipped_lines, feed_slug, line_ids=None):
    """(operator, station id) pairs this feed's OWN shipped lines reference.

    This is the exact, collision-proof key for removing this feed's station
    rows from `stations-{region}.json`: it is derived from the feed's own
    line data (`sourceFeed == feed_slug`, optionally narrowed to
    `line_ids`), not from operator-string matching alone, so it stays
    correct even when this feed's operator name is also used by an
    unrelated feed (the `feed_operators()` docstring's SEPTA example).
    Pairing with the station id (rather than operator alone) also keeps a
    shared interchange safe: two different operators can publish the same
    `n02_group_code` for the same physical stop (see `_station_groups`'s
    docstring), and pairing excludes the other operator's row for that code
    -- but NOT when the two feeds also share the operator STRING itself
    (the Shore Line East case in `station_feed_prefix()`'s docstring); the
    removal predicate ANDs in `station_feed_prefix()` as well to cover that.

    Empty for a feed with no matching shipped lines yet (a first-ship feed,
    or one fully scoped away by `line_ids`) -- there is nothing to remove.
    """
    keys = set()
    for line in shipped_lines:
        if not _owns(line, feed_slug, line_ids):
            continue
        operator = line.get('operator')
        for row in line.get('stations') or ():
            keys.add((operator, row[0]))
    return keys


def feed_section_removal_keys(shipped_lines, feed_slug, line_ids=None):
    """(operator, line name) pairs this feed's OWN shipped lines reference.

    `rail-sections-{region}.json` features carry `properties.operator` and
    `properties.line_name` but no station id (see `merge_features()`'s
    docstring), so this is the analogous exact removal key for sections --
    derived from the feed's own shipped line data rather than from operator
    string alone, for the same reason as `feed_station_removal_keys()`.

    Empty for a feed with no matching shipped lines yet.
    """
    keys = set()
    for line in shipped_lines:
        if not _owns(line, feed_slug, line_ids):
            continue
        keys.add((line.get('operator'), line.get('name')))
    return keys


# ------------------------------------------------- station identity continuity


def _station_groups(features, operators, group_codes=None, feed_prefix=None):
    """(group code -> {'name', 'points'}) for one operator's stations.

    `points` keeps every member feature's own `display_point` rather than
    collapsing them into one centroid. A station's coordinate is anchored
    per LINE (each line anchors a shared station onto its own alignment --
    see `station_features.append()` in `build_region()`), so a multi-line
    complex's members can legitimately span a hundred metres or more --
    different entrances, different platforms -- and a centroid drifts
    around depending on exactly which lines happen to be members on either
    side of a rebuild. Keeping every member and matching on the CLOSEST
    pair (see `station_identity_map()`) asks the right question instead:
    "do these two groups share at least one point that is the same place",
    which is what "the shipped station is within 15 m" means for a complex
    with several surveyed entrances.

    `group_codes`, when given, additionally restricts to features whose
    `n02_group_code` is in that set. This is how `station_identity_map()`
    stays safe on the SHIPPED side when this feed's operator name collides
    with another feed's (see `feed_station_removal_keys()`): passing the
    feed's own shipped station ids here keeps a same-operator-string,
    different-feed station out of the identity match entirely, rather than
    relying on operator alone to exclude it. `feed_prefix`
    (`station_feed_prefix()`) additionally requires `n02_group_code`'s
    membership come from a feature actually built for this feed: two feeds
    can share both the operator string and, for a genuinely shared physical
    stop, the group code too (the Shore Line East case in that function's
    docstring), which `group_codes` alone cannot tell apart.
    """
    points = {}
    names = {}
    for feature in features:
        props = feature.get('properties', {})
        if props.get('operator') not in operators:
            continue
        if feed_prefix is not None and not props.get(
                'n02_station_code', '').startswith(feed_prefix):
            continue
        code = props['n02_group_code']
        if group_codes is not None and code not in group_codes:
            continue
        points.setdefault(code, []).append(tuple(props['display_point']))
        names.setdefault(code, props['station_name'])
    return {code: {'name': names[code], 'points': points[code]}
           for code in points}


def _min_distance(build_module, points_a, points_b):
    return min(build_module.geo.haversine(a, b)
              for a in points_a for b in points_b)


def station_identity_map(build_module, shipped_features, candidate_features,
                         operators, shipped_group_codes=None, feed_prefix=None,
                         coord_tolerance_m=STATION_IDENTITY_COORD_TOLERANCE_M,
                         name_tolerance_m=STATION_IDENTITY_NAME_TOLERANCE_M):
    """candidate group code -> shipped group code, for the same physical place.

    `shipped_group_codes`, when given, additionally restricts the SHIPPED
    side to this feed's own station ids (see `feed_station_removal_keys()`
    and `_station_groups()`'s docstring) -- needed when this feed's operator
    name collides with another feed's, so a same-operator-string station
    belonging to that OTHER feed is never offered as a rename candidate.
    `feed_prefix` (`station_feed_prefix()`) closes the narrower gap where
    the two feeds also share the group code, for a genuinely shared stop.

    `build_region()` assigns every station a code derived from its own
    slugified name, first-seen order (`{region}-official-{slug}[-N]`), so a
    single-feed rebuild has no way to know which of its codes match a
    station that already shipped under a different one. Left alone, a
    rebuild that renames or resequences stations -- an official inventory
    update, a dedup fix, nothing wrong with the geometry -- silently breaks
    every saved ride, reviewed corridor file (`shared-corridors.json`) and
    external link that names the old code.

    A candidate station counts as the same place as a shipped one, of the
    same operator, when either: the two are within `coord_tolerance_m` of
    each other, or their normalised names are identical and they are within
    `name_tolerance_m` (looser, so a station whose surveyed anchor moved a
    little between builds is still recognised).

    Matching is global over every shipped/candidate pair of this operator,
    not restricted to candidate codes that vanished from the shipped code
    space: two stations can carry the identical code text in both builds
    and still be different physical places, because a fresh build's codes
    are assigned by first-seen order per slug rather than being stable
    identifiers -- e.g. NYCT's "34 St-Penn Station" complex: the shipped
    package used `us-official-34-st-penn` for the 7th/8th Ave entrance and
    `us-official-new-york-penn` for the 6th/7th Ave one, and a candidate
    rebuild reused `us-official-34-st-penn` for the *other* entrance while
    calling the first one `-2`. Matching shipped-code-string to
    candidate-code-string would keep both codes pointing at the wrong
    platform; matching by coordinate swaps them back correctly. Every
    (shipped, candidate) pair within tolerance is a candidate match; the
    closest pairs are resolved first and a shipped or candidate code is
    never reused once claimed, so the result is a one-to-one map.
    """
    shipped_groups = _station_groups(shipped_features, operators,
                                     group_codes=shipped_group_codes,
                                     feed_prefix=feed_prefix)
    candidate_groups = _station_groups(candidate_features, operators)
    normalised = {}
    for group in (shipped_groups, candidate_groups):
        for info in group.values():
            if info['name'] not in normalised:
                normalised[info['name']] = build_module.normalise_station_name(
                    info['name'])

    pairs = []
    for scode, sinfo in shipped_groups.items():
        for ccode, cinfo in candidate_groups.items():
            distance = _min_distance(build_module, sinfo['points'], cinfo['points'])
            same_name = normalised[sinfo['name']] == normalised[cinfo['name']]
            if distance <= coord_tolerance_m or (
                    same_name and distance <= name_tolerance_m):
                pairs.append((distance, scode, ccode))
    # Closest first; codes as the tie-break only for determinism between
    # equidistant pairs (real coincident-point ties are rare but not
    # impossible -- adjacent entrances of one complex can share a point).
    pairs.sort(key=lambda p: (p[0], p[1], p[2]))

    used_shipped = set()
    used_candidate = set()
    rename_map = {}
    for distance, scode, ccode in pairs:
        if scode in used_shipped or ccode in used_candidate:
            continue
        used_shipped.add(scode)
        used_candidate.add(ccode)
        if ccode != scode:
            rename_map[ccode] = scode
    return rename_map


def apply_station_identity(candidate_lines, candidate_station_features,
                           feed_slug, operators, rename_map):
    """Rewrite every candidate id `station_identity_map` says to preserve.

    Touches exactly the places a station's group code appears in a scoped
    candidate build: a line's own `stations[]` rows (column 0), and a
    station feature's `n02_group_code` plus the group code embedded in its
    `n02_station_code` suffix (`{REGION}-{FEED}-{OPERATOR}-{stationId}-
    {code}`, built in `station_features.append()`). `rail-sections-*.json`
    features carry no station id at all -- see `merge_features()`'s
    docstring -- so there is nothing to rewrite there, and
    `station-readings-*.json` is derived afterwards by `readings_for()`
    walking these already-renamed station features (see `merge_readings()`),
    so it inherits the preserved codes with no separate step.

    Rows are matched by `sourceFeed` (like `merge_lines()`), features by
    `operator` (like `merge_features()` -- a feature carries no feed id).
    `rename_map`'s keys are codes computed from this candidate build's own
    stations, so in practice only this feed's own rows and features ever
    carry one; the operator/feed check is what keeps that true even if some
    other feed's code text happened to coincide, rather than assuming it.
    """
    if not rename_map:
        return candidate_lines, candidate_station_features

    new_lines = []
    for line in candidate_lines:
        if line.get('sourceFeed') != feed_slug:
            new_lines.append(line)
            continue
        line = dict(line)
        line['stations'] = [
            [rename_map.get(row[0], row[0])] + list(row[1:])
            for row in line['stations']
        ]
        new_lines.append(line)

    new_features = []
    for feature in candidate_station_features:
        props = feature.get('properties', {})
        old_code = props.get('n02_group_code')
        if props.get('operator') not in operators or old_code not in rename_map:
            new_features.append(feature)
            continue
        new_code = rename_map[old_code]
        feature = copy.deepcopy(feature)
        props = feature['properties']
        station_code = props['n02_station_code']
        old_suffix = '-' + old_code.upper()
        if not station_code.endswith(old_suffix):
            raise ValueError(
                'n02_station_code %r does not end with its own group code '
                '%r; identity rename is unsafe' % (station_code, old_code))
        props['n02_station_code'] = station_code[:-len(old_code)] + new_code.upper()
        props['n02_group_code'] = new_code
        new_features.append(feature)

    return new_lines, new_features


# ---------------------------------------------------------- feature files


def merge_features(shipped_features, candidate_features, should_remove):
    """Splice a feed's GeoJSON features (stations or sections) in place.

    Removes every shipped feature for which `should_remove(feature)` is
    true and inserts the candidate's features at that position. Returns
    (merged_features, removed_count, added_count).

    `should_remove` is normally `station_removal_predicate()` or
    `section_removal_predicate()` (below), built from this feed's own
    shipped-line data rather than raw operator matching -- see
    `feed_station_removal_keys()`'s docstring for why.
    """
    insert_at = None
    kept = []
    removed = 0
    for feature in shipped_features:
        if should_remove(feature):
            removed += 1
            if insert_at is None:
                insert_at = len(kept)
            continue
        kept.append(feature)
    if insert_at is None:
        insert_at = len(kept)
    merged = kept[:insert_at] + list(candidate_features) + kept[insert_at:]
    return merged, removed, len(candidate_features)


def station_removal_predicate(station_keys, operators, has_shipped_lines,
                              feed_prefix=None):
    """should_remove() for merge_features() over stations-{region}.json.

    Primary path: remove a feature whose (operator, n02_group_code) pair is
    in `station_keys` -- the feed's own shipped station ids from
    `feed_station_removal_keys()`, exact and collision-proof against most
    cross-feed collisions (see that function's docstring) but not the one
    `station_feed_prefix()` describes, where two feeds share both the
    operator string AND (because it is genuinely the same physical stop)
    the group code. `feed_prefix`, when given, ANDs in that check too, so
    passing it is what actually closes that gap; every legitimate match
    always satisfies it too (a feed's own feature is built with its own
    prefix), so this never excludes a row the primary key alone would have
    correctly matched.

    `station_keys` comes back empty in two different shapes that must NOT be
    treated alike: a genuine first-ship feed (`has_shipped_lines` False) has
    nothing to remove, full stop -- falling back to operator matching there
    would delete another feed's already-shipped stations that merely share
    an operator name, exactly the bug this whole mechanism exists to avoid.
    Only when `has_shipped_lines` is True (this feed already ships lines,
    but for some reason none of them yielded a key -- a shape a well-formed
    shipped line should never produce, since every shipped line carries a
    `stations` list) does this fall back to plain operator matching, and the
    caller is expected to have printed a warning before taking that path.
    """
    def has_prefix(feature):
        if feed_prefix is None:
            return True
        return feature.get('properties', {}).get(
            'n02_station_code', '').startswith(feed_prefix)

    if station_keys:
        return lambda feature: has_prefix(feature) and (
            (feature.get('properties', {}).get('operator'),
             feature.get('properties', {}).get('n02_group_code'))
            in station_keys)
    if has_shipped_lines:
        return lambda feature: has_prefix(feature) and (
            feature.get('properties', {}).get('operator') in operators)
    return lambda feature: False


def section_removal_predicate(section_keys, operators, has_shipped_lines):
    """should_remove() for merge_features() over rail-sections-{region}.json.

    Primary path: remove a feature whose (operator, line_name) pair is in
    `section_keys` -- from `feed_section_removal_keys()`, exact per this
    feed's own shipped lines. Falls back to plain operator matching (the
    pre-fix behaviour) only when `has_shipped_lines` is True but
    `section_keys` still came back empty -- see
    `station_removal_predicate()`'s docstring for why a genuine first-ship
    feed (`has_shipped_lines` False) must never take this path instead of
    simply removing nothing. Callers should print a warning when taking
    this fallback, since it is exactly the operator-string matching that is
    unsafe under an operator-name collision.
    """
    if section_keys:
        return lambda feature: (
            (feature.get('properties', {}).get('operator'),
             feature.get('properties', {}).get('line_name'))
            in section_keys)
    if has_shipped_lines:
        return lambda feature: feature.get('properties', {}).get('operator') in operators
    return lambda feature: False


def merge_readings(build_module, merged_station_features, region,
                   shipped_readings):
    """Recompute byCode/byName over the merged station features.

    Calls the builder's own readings_for() rather than trying to patch the
    shipped byCode/byName incrementally: a shared interchange's group code
    can be first claimed by either operator's feature, and while the row
    content only differs if the two operators publish different names for
    the same platform, recomputing from the merged list is what a real
    rebuild would do and needs no case analysis to trust.
    """
    fresh = build_module.readings_for(merged_station_features, region)
    merged = dict(shipped_readings)
    for key in ('note', 'country', 'languages', 'packageVersion', 'sources'):
        if key in fresh and fresh[key] != shipped_readings.get(key):
            raise ValueError(
                'station-readings %r changed unexpectedly during merge: '
                '%r -> %r' % (key, shipped_readings.get(key), fresh[key]))
    merged['stats'] = fresh['stats']
    merged['byCode'] = fresh['byCode']
    merged['byName'] = fresh['byName']
    return merged


# ------------------------------------------------------- package headers


def merge_zones(shipped_zones, merged_station_features):
    """Extend the shipped zone list with any zone the merge introduces.

    `zones` in both the package's `timeZones` and the build report's
    per-region stats is a first-seen-order list, not a sorted set (see
    `zone_of()` in build_region()). A merge never removes a zone that other
    feeds still use, so this only appends zones that are new to the region,
    in the order the merged station features introduce them.
    """
    zones = list(shipped_zones)
    seen = set(zones)
    for feature in merged_station_features:
        zone = feature.get('properties', {}).get('time_zone')
        if zone and zone not in seen:
            seen.add(zone)
            zones.append(zone)
    return zones


def recompute_geometry_source(shipped_geom, candidate_geom, merged_lines,
                              removed_ids, added_ids):
    """Refresh the parts of `geometrySource` that depend on which lines ship.

    `officialOnly`, `providers`, `license` and `osmSources` are package-wide
    build configuration, not per-feed derived values, so they are carried
    over unchanged. `verifiedOfficialNetworks`, `officialGeometryComparison`
    and `syntheticConnectors` are recomputed exactly the way
    build_region()/synthetic_total() compute them, from the merged lines.
    """
    geom = copy.deepcopy(shipped_geom)

    combined_verified = dict(shipped_geom.get('verifiedOfficialNetworks') or {})
    combined_verified.update(candidate_geom.get('verifiedOfficialNetworks') or {})
    used_sources = {line.get('geometrySource') for line in merged_lines}
    geom['verifiedOfficialNetworks'] = {
        key: value for key, value in sorted(combined_verified.items())
        if key in used_sources
    }

    comparison = dict(shipped_geom['officialGeometryComparison'])
    by_line = dict(comparison['byLine'])
    for line_id in removed_ids:
        by_line.pop(line_id, None)
    candidate_by_line = (candidate_geom.get('officialGeometryComparison') or {}
                        ).get('byLine') or {}
    for line_id in added_ids:
        if line_id in candidate_by_line:
            by_line[line_id] = candidate_by_line[line_id]
    comparison['byLine'] = by_line
    comparison['lines'] = len(merged_lines)
    deviations = [v.get('maxDeviationMeters', 0.0) for v in by_line.values()]
    comparison['maxDeviationMeters'] = (
        round(max(deviations), 2) if deviations else 0.0)
    geom['officialGeometryComparison'] = comparison

    geom['syntheticConnectors'] = sum(
        len(line.get('segments') or ())
        for line in merged_lines
        if line.get('geometrySource') == 'station-chord')

    return geom


def region_summary(merged_lines, merged_stations, merged_sections,
                   comparison, shipped_zones, byte_sizes):
    return {
        'lines': len(merged_lines),
        'stationGroups': len({
            f['properties']['n02_group_code'] for f in merged_stations}),
        'sections': len(merged_sections),
        'zones': merge_zones(shipped_zones, merged_stations),
        'maxDeviationMeters': comparison['maxDeviationMeters'],
        'bytes': byte_sizes,
    }


def merge_build_report(shipped_report, candidate_report, feed_slug, region,
                       region_stats, preserved_station_ids, line_ids=None,
                       added_ids=None):
    report = copy.deepcopy(shipped_report)
    candidate_feed = next(
        (f for f in candidate_report.get('feeds') or ()
         if f.get('slug') == feed_slug), None)
    if candidate_feed is None:
        raise ValueError(
            'candidate build-report has no feed entry for %r' % feed_slug)
    candidate_feed = dict(candidate_feed)
    # Evidence for every id the merge overrode: candidate code -> the
    # shipped code kept in its place. Always present (even empty) so a
    # reader can tell "checked, found none" from "never checked".
    candidate_feed['preservedStationIds'] = dict(preserved_station_ids)
    if line_ids is not None:
        # The candidate build-report's own `lines`/`dropped` describe the
        # WHOLE scoped `--only <feed>` build (every line the feed owns),
        # not just the ids this merge actually spliced in. Recording that
        # explicitly is what keeps a reader of the merged report from being
        # told this feed shipped lines that were never actually merged.
        candidate_feed['unscopedCandidateLines'] = candidate_feed.get('lines')
        candidate_feed['lines'] = len(added_ids or ())
        candidate_feed['scopedToLineIds'] = sorted(line_ids)
    feeds = report.setdefault('feeds', [])
    for i, feed in enumerate(feeds):
        if feed.get('slug') == feed_slug:
            feeds[i] = candidate_feed
            break
    else:
        feeds.append(candidate_feed)
    report.setdefault('regions', {})[region] = region_stats
    return report


# ------------------------------------------------------------------ plan


class MergePlan:
    """Everything computed in memory before (optionally) writing to disk."""

    def __init__(self, region, feed_slug):
        self.region = region
        self.feed_slug = feed_slug
        self.removed_ids = []
        self.added_ids = []
        self.preserved_station_ids = {}
        self.package = None
        self.stations = None
        self.sections = None
        self.readings = None
        self.build_report = None
        self.stations_removed = self.stations_added = 0
        self.sections_removed = self.sections_added = 0

    def describe(self):
        lines = [
            'feed: %s (region %s)' % (self.feed_slug, self.region),
            'lines removed (%d): %s' % (
                len(self.removed_ids), ', '.join(self.removed_ids) or '(none)'),
            'lines added (%d): %s' % (
                len(self.added_ids), ', '.join(self.added_ids)),
            'stations: -%d +%d' % (self.stations_removed, self.stations_added),
            'sections: -%d +%d' % (self.sections_removed, self.sections_added),
            'preserved station ids (%d): %s' % (
                len(self.preserved_station_ids),
                ', '.join('%s -> %s' % (new, old) for new, old in
                         sorted(self.preserved_station_ids.items()))
                or '(none)'),
            'readings.stats: %s' % (self.readings['stats'] if self.readings
                                    else '?'),
            'geometrySource.officialGeometryComparison.lines: %d' % (
                self.package['geometrySource']['officialGeometryComparison']['lines']
                if self.package else -1),
            'geometrySource.officialGeometryComparison.maxDeviationMeters: %s' % (
                self.package['geometrySource']['officialGeometryComparison']
                ['maxDeviationMeters'] if self.package else '?'),
            'verifiedOfficialNetworks keys: %s' % (
                sorted(self.package['geometrySource']
                      ['verifiedOfficialNetworks'].keys()) if self.package
                else '?'),
        ]
        return '\n'.join(lines)


def build_plan(build_module, shipped, candidate, region, feed_slug,
              line_ids=None):
    plan = MergePlan(region, feed_slug)
    if line_ids is not None:
        candidate = scope_candidate_to_lines(candidate, feed_slug, line_ids)

    shipped_lines = shipped['package']['lines']
    operators = feed_operators(
        shipped_lines, candidate['package']['lines'], feed_slug,
        line_ids=line_ids)

    has_shipped_lines = any(_owns(line, feed_slug, line_ids)
                            for line in shipped_lines)
    collision = operator_collision(shipped_lines, feed_slug,
                                   line_ids=line_ids, ops=operators)
    station_keys = feed_station_removal_keys(shipped_lines, feed_slug,
                                             line_ids=line_ids)
    section_keys = feed_section_removal_keys(shipped_lines, feed_slug,
                                             line_ids=line_ids)
    if collision:
        if station_keys or section_keys:
            print(
                'warning: feed %r shares operator name(s) %r with another '
                'feed; removing its shipped stations/sections by exact '
                '(operator, id) key instead of by operator alone' % (
                    feed_slug, sorted(collision)), file=sys.stderr)
        elif has_shipped_lines:
            print(
                'warning: feed %r shares operator name(s) %r with another '
                'feed and its own shipped lines yielded no id-derived '
                'removal key; falling back to operator-based removal '
                '(unsafe under this collision)' % (
                    feed_slug, sorted(collision)), file=sys.stderr)
        # else: a first-ship feed under a colliding operator name has
        # nothing shipped to remove; nothing to warn about.

    # Restrict the SHIPPED side of station_identity_map() to this feed's own
    # station ids whenever an operator collision makes plain operator
    # filtering unsafe -- otherwise a first-ship feed (station_keys empty,
    # nothing of its own shipped yet) could be offered another feed's
    # same-operator-string station as a rename candidate, purely because
    # both happen to share an operator name and (by coincidence or a shared
    # slug) a coordinate. An empty set here (rather than None) correctly
    # excludes every shipped station from matching, since a first-ship feed
    # has no "preserved id" case to find. Without a collision, operator
    # filtering alone is already safe (legacy behaviour, unrestricted).
    shipped_group_codes = (
        {sid for (_op, sid) in station_keys} if collision else None)
    # Always safe to require, whether or not there is an operator
    # collision: a feed's own feature always carries its own prefix, so
    # this can only narrow a match, never miss one, and closes the one gap
    # (operator, group_code) pairing alone cannot -- see
    # `station_feed_prefix()`'s docstring (the Amtrak/Shore Line East case,
    # where two feeds share both the operator string and the group code).
    feed_prefix = station_feed_prefix(region, feed_slug)

    # Identity continuity: decide, before anything else touches the
    # candidate's ids, which of them are actually a shipped station under a
    # new code/name and must ship under the old one instead. Every later
    # step (line splicing, feature splicing, readings) then works off the
    # already-corrected candidate data and needs no knowledge of the swap.
    rename_map = station_identity_map(
        build_module, shipped['stations']['features'],
        candidate['stations']['features'], operators,
        shipped_group_codes=shipped_group_codes, feed_prefix=feed_prefix)
    plan.preserved_station_ids = rename_map
    candidate_lines, candidate_station_features = apply_station_identity(
        candidate['package']['lines'], candidate['stations']['features'],
        feed_slug, operators, rename_map)

    merged_lines, removed_ids, added_ids = merge_lines(
        shipped_lines, candidate_lines, feed_slug,
        line_ids=line_ids)
    if not added_ids:
        raise ValueError(
            'candidate package has no lines with sourceFeed == %r' % feed_slug)
    plan.removed_ids, plan.added_ids = removed_ids, added_ids

    merged_stations, st_removed, st_added = merge_features(
        shipped['stations']['features'], candidate_station_features,
        station_removal_predicate(station_keys, operators, has_shipped_lines,
                                  feed_prefix=feed_prefix))
    plan.stations_removed, plan.stations_added = st_removed, st_added

    merged_sections, se_removed, se_added = merge_features(
        shipped['sections']['features'], candidate['sections']['features'],
        section_removal_predicate(section_keys, operators, has_shipped_lines))
    plan.sections_removed, plan.sections_added = se_removed, se_added

    expected_station_removals = sum(
        len(line.get('stations') or ())
        for line in shipped['package']['lines']
        if line.get('sourceFeed') == feed_slug
        and (line_ids is None or line['id'] in line_ids))
    if st_removed != expected_station_removals:
        raise ValueError(
            'removed %d station features but the %d replaced lines list '
            '%d station rows; operator-based matching may be unsafe' % (
                st_removed, len(removed_ids), expected_station_removals))

    merged_readings = merge_readings(
        build_module, merged_stations, region, shipped['readings'])

    merged_geometry = recompute_geometry_source(
        shipped['package']['geometrySource'], candidate['package']['geometrySource'],
        merged_lines, removed_ids, added_ids)

    package = dict(shipped['package'])
    package['lines'] = merged_lines
    package['geometrySource'] = merged_geometry
    package['timeZones'] = merge_zones(package['timeZones'], merged_stations)

    plan.package = package
    plan.stations = {'type': 'FeatureCollection', 'features': merged_stations}
    plan.sections = {'type': 'FeatureCollection', 'features': merged_sections}
    plan.readings = merged_readings

    region_stats = region_summary(
        merged_lines, merged_stations, merged_sections,
        merged_geometry['officialGeometryComparison'], package['timeZones'],
        byte_sizes={
            'package': compact_size(package),
            'stations': compact_size(plan.stations),
            'sections': compact_size(plan.sections),
            'readings': compact_size(merged_readings),
        })
    plan.build_report = merge_build_report(
        shipped['build_report'], candidate['build_report'], feed_slug,
        region, region_stats, plan.preserved_station_ids,
        line_ids=line_ids, added_ids=added_ids)

    return plan


# ------------------------------------------------------------- disk paths


def shipped_paths(app_root, region):
    rail = os.path.join(app_root, 'public', 'rail')
    data = os.path.join(app_root, 'data')
    return {
        'package': os.path.join(rail, '%s-2025.json' % region),
        'stations': os.path.join(data, 'stations-%s.json' % region),
        'sections': os.path.join(data, 'rail-sections-%s.json' % region),
        'readings': os.path.join(data, 'station-readings-%s.json' % region),
        'build_report': os.path.join(rail, 'na-2025-build-report.json'),
        'region_audit_json': os.path.join(rail, '%s-2025.audit.json' % region),
        'region_audit_md': os.path.join(rail, '%s-2025.audit.md' % region),
        'region_sources_md': os.path.join(rail, '%s-2025.sources.md' % region),
        'na_audit_json': os.path.join(rail, 'na-2025.audit.json'),
        'line_review_base': os.path.join(rail, 'na-2025-line-review'),
        'sibling_package': os.path.join(
            rail, '%s-2025.json' % SIBLING_REGION.get(region, '')),
        'registry': os.path.join(HERE, 'na-feeds.json'),
    }


def candidate_paths(candidate_dir, region):
    return {
        'package': os.path.join(candidate_dir, 'public', '%s-2025.json' % region),
        'stations': os.path.join(
            candidate_dir, 'data', 'stations-%s.json' % region),
        'sections': os.path.join(
            candidate_dir, 'data', 'rail-sections-%s.json' % region),
        'readings': os.path.join(
            candidate_dir, 'data', 'station-readings-%s.json' % region),
        'build_report': os.path.join(candidate_dir, 'build-report.json'),
    }


def load_shipped(paths):
    return {
        'package': load_json(paths['package']),
        'stations': load_json(paths['stations']),
        'sections': load_json(paths['sections']),
        'readings': load_json(paths['readings']),
        'build_report': load_json(paths['build_report']),
    }


def load_candidate(paths):
    return {
        'package': load_json(paths['package']),
        'stations': load_json(paths['stations']),
        'sections': load_json(paths['sections']),
        'readings': load_json(paths['readings']),
        'build_report': load_json(paths['build_report']),
    }


# ------------------------------------------------------ derived documents


def spell_small(n):
    return {0: 'zero', 1: 'one', 2: 'two'}.get(n, str(n))


def count_findings(audit_json):
    from collections import Counter
    return Counter((row['severity'], row['check'])
                  for row in audit_json['findings'])


def source_band_counts(package):
    """(official-verified, gtfs/other, narn) line counts, station-chord count.

    Matches the classification `us-2025.sources.md`'s lead paragraph states:
    a line's geometrySource is either a key the package's own
    verifiedOfficialNetworks vouches for, the literal 'narn'/'osm'/
    'station-chord', or (by elimination) an operator GTFS shape.
    """
    verified = set(package['geometrySource'].get('verifiedOfficialNetworks') or {})
    official = gtfs = narn = chord = 0
    for line in package['lines']:
        source = line.get('geometrySource')
        if source == 'narn':
            narn += 1
        elif source == 'station-chord':
            chord += 1
        elif source in verified:
            official += 1
        else:
            gtfs += 1
    return official, gtfs, narn, chord


def refresh_audit_md(path, package, audit_json, groups, sections, today):
    """Refresh only the lead paragraph's counts and the title's date.

    There is no generator for this file in the repo (unlike
    na-2025-line-review.md, which make-na-line-review.py owns) -- it is
    hand-authored prose. Everything after the lead paragraph is left
    untouched.
    """
    text = load_text(path)
    counts = count_findings(audit_json)
    # `error` is a true total: an ERROR anywhere is a release gate regardless
    # of which check raised it. `warn`/`note` are the sum of exactly the
    # seven categories this paragraph names below, not every WARN/NOTE check
    # the current audit script happens to know about -- this doc has always
    # itemized every warning and note it counts, and a check this tool does
    # not know the prose for (e.g. one a concurrent change to
    # audit-na-package.py added) should not silently inflate an unexplained
    # total here.
    error = sum(v for (sev, _c), v in counts.items() if sev == 'ERROR')
    radius = counts[('WARN', 'geometry.radius')]
    retained = counts[('WARN', 'geometry.deviation.officialRetained')]
    split = counts[('WARN', 'station.split')]
    nested = counts[('WARN', 'operator.nested')]
    spike = counts[('WARN', 'geometry.spike')]
    withheld = counts[('NOTE', 'geometry.deviation.withheld')]
    optional = sum(v for (sev, check), v in counts.items()
                  if sev == 'NOTE' and check.startswith('package.field'))
    warn = radius + retained + split + nested + spike
    note = withheld + optional

    country_names = {'US': 'United States', 'CA': 'Canada'}
    country = country_names.get(package.get('country'), package.get('country'))
    title_re = re.compile(r'^#\s+.*rail audit\s+—\s+\S+\s*$', re.M)
    new_title = '# %s rail audit — %s' % (country, today)
    text = title_re.sub(lambda _m: new_title, text, count=1)

    lead_re = re.compile(
        r'The strict generated package contains .*?optional-field notes\.\n',
        re.S)
    lines_n = len(package['lines'])
    lead = (
        'The strict generated package contains {lines} lines, {groups} station '
        'groups and\n{sections} station intervals. The compact audit reports '
        '{error} errors, {warn} warnings and\n{note} notes: {radius} '
        'curve-radius reviews, {retained} retained-official alignment '
        'reviews,\n{split} station-split warnings, {nested} nested-operator '
        'reviews, {spike_phrase},\n{withheld} display-withholding decisions '
        'and {optional_phrase} optional-field notes.\n'
    ).format(
        lines='{:,}'.format(lines_n),
        groups='{:,}'.format(groups),
        sections='{:,}'.format(sections),
        error=spell_small(error), warn=warn, note=note,
        radius=radius, retained=retained, split=split, nested=nested,
        spike_phrase=(('one geometry-spike review' if spike == 1 else
                       '%d geometry-spike reviews' % spike) if spike else
                      'no geometry-spike review'),
        withheld=withheld,
        optional_phrase=spell_small(optional))
    new_text = lead_re.sub(lambda _m: lead, text, count=1)
    return new_text


def load_text(path):
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def write_text(path, text):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        fh.write(text)
    os.replace(tmp, path)


# --------------------------------------------------------------------- CLI


def backup_before_merge(candidate_dir, paths):
    """Copy every shipped file this merge is about to rewrite into
    `<candidate>/backup-before-merge/`, before any write happens.

    Copied by basename -- every path this tool writes already has a name
    unique across the merge's output set (`us-2025.json`,
    `stations-us.json`, `na-2025-build-report.json`, etc.) -- so a merge
    that goes wrong partway through can be undone by hand from this
    directory, and a reviewer can diff exactly what a merge changed. A path
    that does not exist yet (e.g. a brand-new package for a region that has
    never shipped) is skipped rather than erroring.

    Returns the list of backup file paths actually written.
    """
    backup_dir = os.path.join(candidate_dir, 'backup-before-merge')
    os.makedirs(backup_dir, exist_ok=True)
    backed_up = []
    for path in paths:
        if not os.path.exists(path):
            continue
        dest = os.path.join(backup_dir, os.path.basename(path))
        shutil.copy2(path, dest)
        backed_up.append(dest)
    return backed_up


def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result


def regenerate_derived(app_root, region, paths):
    """Call this repo's own audit/review scripts on the merged package.

    Regenerates {region}-2025.audit.json, na-2025.audit.json and
    na-2025-line-review.{json,md} from the files already written to disk --
    the same way a full rebuild's own pipeline produces them -- instead of
    templating their content by hand.
    """
    audit_script = os.path.join(HERE, 'audit-na-package.py')
    review_script = os.path.join(HERE, 'make-na-line-review.py')
    reports = []

    region_only = run([sys.executable, audit_script,
                       '--package', paths['package'],
                       '--registry', paths['registry'],
                       '--out', paths['region_audit_json']])
    reports.append(('%s-2025.audit.json' % region, region_only))

    na_packages = [paths['package']]
    if os.path.exists(paths['sibling_package']):
        na_packages.append(paths['sibling_package'])
    na_cmd = [sys.executable, audit_script]
    for p in na_packages:
        na_cmd += ['--package', p]
    na_cmd += ['--registry', paths['registry'], '--out', paths['na_audit_json']]
    na_run = run(na_cmd)
    reports.append(('na-2025.audit.json', na_run))

    review_cmd = [sys.executable, review_script]
    for p in na_packages:
        review_cmd += ['--package', p]
    review_cmd += ['--audit', paths['na_audit_json'],
                  '--build-report', paths['build_report'],
                  '--output', paths['line_review_base']]
    review_run = run(review_cmd)
    reports.append(('na-2025-line-review.{json,md}', review_run))

    return reports


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--candidate', required=True,
                    help='directory holding public/, data/ and build-report.json '
                         'from a scoped `--only <feed>` build')
    ap.add_argument('--feed', required=True,
                    help='feed alias (e.g. lirr) or full sourceFeed slug')
    ap.add_argument('--region', required=True, choices=('us', 'ca'))
    ap.add_argument('--line-id', action='append', default=None,
                    help='merge only this candidate line id (repeatable) '
                         'instead of the whole feed. Use when the feed '
                         'cannot be merged whole because one of its '
                         'operator names is shared with an already-shipped '
                         'line outside the feed (feed_operators refuses) '
                         'but the requested line(s) use an operator name '
                         'unique to themselves -- e.g. Seattle Center '
                         'Monorail inside the Puget Sound consolidated '
                         'feed, whose other routes share Sound Transit/'
                         'City of Seattle/Amtrak with lines already shipped '
                         'from other feeds.')
    ap.add_argument('--dry-run', action='store_true',
                    help='print the merge plan; write nothing')
    ap.add_argument('--app-root', default=APP_ROOT,
                    help=argparse.SUPPRESS)  # override for tests
    args = ap.parse_args(argv)

    feed_slug = resolve_feed_slug(args.feed)
    paths = shipped_paths(args.app_root, args.region)
    cpaths = candidate_paths(args.candidate, args.region)

    shipped = load_shipped(paths)
    candidate = load_candidate(cpaths)
    build_module = load_build_module()

    line_ids = set(args.line_id) if args.line_id else None
    plan = build_plan(build_module, shipped, candidate, args.region, feed_slug,
                      line_ids=line_ids)

    print(plan.describe())

    if args.dry_run:
        print('\n(dry run: nothing written)')
        return 0

    backed_up = backup_before_merge(args.candidate, [
        paths['package'], paths['stations'], paths['sections'],
        paths['readings'], paths['build_report'],
        paths['region_audit_json'], paths['region_audit_md'],
        paths['region_sources_md'], paths['na_audit_json'],
        paths['line_review_base'] + '.json',
        paths['line_review_base'] + '.md',
    ])
    print('backed up %d file(s) to %s' % (
        len(backed_up), os.path.join(args.candidate, 'backup-before-merge')))

    write_json_compact(paths['package'], plan.package)
    write_json_compact(paths['stations'], plan.stations)
    write_json_compact(paths['sections'], plan.sections)
    write_json_compact(paths['readings'], plan.readings)
    write_json_compact(paths['build_report'], plan.build_report)
    print('\nwrote package, stations, sections, readings, build-report')

    today = dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%d')
    reports = regenerate_derived(args.app_root, args.region, paths)
    ok = True
    for name, result in reports:
        status = 'ok' if result.returncode == 0 else (
            'FAILED (exit %d)' % result.returncode)
        print('%s: %s' % (name, status))
        if result.stdout.strip():
            print(result.stdout.strip().splitlines()[-1])
        if result.returncode not in (0, 1):  # 1 == findings include ERROR
            ok = False
        if result.returncode == 1:
            print(result.stdout, file=sys.stderr)

    region_audit = load_json(paths['region_audit_json'])
    region_stats = plan.build_report['regions'][args.region]
    audit_md = refresh_audit_md(paths['region_audit_md'], plan.package,
                               region_audit, region_stats['stationGroups'],
                               region_stats['sections'], today)
    write_text(paths['region_audit_md'], audit_md)
    print('refreshed %s-2025.audit.md lead paragraph' % args.region)

    official, gtfs, narn, chord = source_band_counts(plan.package)
    sources_text = load_text(paths['region_sources_md'])
    lead_re = re.compile(
        r'`{region}-2025\.json` is a fail-closed `compact-v1` package\. '
        r'Its \d[\d,]* published lines\nuse .*?\.\n'.format(region=args.region),
        re.S)
    chord_phrase = ('no station-to-station fallback chords' if chord == 0 else
                    '%d station-to-station fallback chord%s' % (
                        chord, '' if chord == 1 else 's'))
    new_lead = (
        '`{region}-2025.json` is a fail-closed `compact-v1` package. Its '
        '{lines} published lines\nuse {official} route-isolated '
        'government/operator GIS geometries, {gtfs} official GTFS\nshapes '
        'that pass an independent track cross-check, and {narn} NARN '
        'routings. It\ncontains {chord}.\n'
    ).format(region=args.region, lines=len(plan.package['lines']),
             official=official, gtfs=gtfs, narn=narn, chord=chord_phrase)
    sources_text = lead_re.sub(lambda _m: new_lead, sources_text, count=1)
    write_text(paths['region_sources_md'], sources_text)
    print('refreshed %s-2025.sources.md lead paragraph' % args.region)

    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
