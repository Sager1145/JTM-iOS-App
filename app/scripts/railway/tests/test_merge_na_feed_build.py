import importlib.util
import copy
import json
import math
import os
import tempfile
import unittest

SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'merge-na-feed-build.py'))
SPEC = importlib.util.spec_from_file_location('na_feed_merge', SCRIPT)
merge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(merge)


def station_row(code, name, x, y):
    return [code, name, x, y, name, 3, 'America/New_York']


def station_feature(operator, feed, group_code, station_id, code, name,
                    x, y, zone='America/New_York'):
    # `code` (a short per-stop id, unused below) is kept as a parameter only
    # for call-site compatibility. The real builder always ends
    # `n02_station_code` with the *group* code, uppercased -- see
    # `station_features.append()` in build-north-america-rail-package.py --
    # and `apply_station_identity()` relies on that exact invariant to
    # rewrite a preserved station's embedded code, so the fixture has to
    # produce the same shape rather than a simplified stand-in.
    del code
    return {
        'type': 'Feature',
        'properties': {
            'railway_class_code': 1,
            'institution_type_code': 1,
            'line_name': name + ' line',
            'operator': operator,
            'station_name': name,
            'n02_station_code': 'US-%s-%s-%s-%s' % (
                feed.upper(), operator.upper().replace(' ', ''), station_id,
                group_code.upper()),
            'n02_group_code': group_code,
            'display_point': [x, y],
            'time_zone': zone,
        },
        'geometry': {'type': 'LineString', 'coordinates': [[x, y], [x, y]]},
    }


def section_feature(operator, name, coords):
    return {
        'type': 'Feature',
        'properties': {
            'railway_class_code': 1, 'institution_type_code': 1,
            'line_name': name, 'operator': operator,
        },
        'geometry': {'type': 'LineString', 'coordinates': coords},
    }


class MergeFixture:
    """A tiny two-operator shipped package plus a one-operator candidate.

    'Test Rail' (sourceFeed 'test-feed') is the feed being merged: its one
    shipped line ('test-feed-alpha') is replaced by a changed version of
    itself plus a brand-new second line ('test-feed-gamma'). 'Other Rail'
    (sourceFeed 'other-feed') is the unrelated operator that must come out
    byte-for-byte identical.
    """

    def __init__(self):
        build_module = merge.load_build_module()
        self.build_module = build_module
        skeleton = build_module.readings_for([], 'us')

        alpha_old_stations = [
            station_feature('Test Rail', 'test-feed', 'us-official-alpha-1',
                            '1', 'a1', 'Alpha One', 0.0, 0.0),
            station_feature('Test Rail', 'test-feed', 'us-official-alpha-2',
                            '2', 'a2', 'Alpha Two', 1.0, 1.0),
        ]
        beta_stations = [
            station_feature('Other Rail', 'other-feed', 'us-official-beta-1',
                            '1', 'b1', 'Beta One', 5.0, 5.0),
        ]
        self.shipped = {
            'package': {
                'format': 'compact-v1', 'version': '2026.2.0',
                'generatedAt': '2026-08-30T00:00:00.000Z', 'crs': 'WGS84',
                'country': 'US', 'timeZones': ['America/New_York'],
                'lines': [
                    {
                        'id': 'test-feed-alpha', 'name': 'Alpha', 'operator': 'Test Rail',
                        'sourceFeed': 'test-feed', 'kind': 'regional',
                        'geometrySource': 'test-feed-src-1',
                        'lengthKm': 1.0, 'rank': 1, 'color': '#ff0000',
                        'stations': [station_row('us-official-alpha-1', 'Alpha One', 0.0, 0.0),
                                    station_row('us-official-alpha-2', 'Alpha Two', 1.0, 1.0)],
                        'segments': [[1.0, 0, [[0.0, 0.0], [1.0, 1.0]]]],
                        'colorReference': '#ff0000', 'colorSource': 'gtfs',
                        'colorDark': '#ff0000',
                    },
                    {
                        'id': 'other-feed-beta', 'name': 'Beta', 'operator': 'Other Rail',
                        'sourceFeed': 'other-feed', 'kind': 'regional',
                        'geometrySource': 'narn',
                        'lengthKm': 2.0, 'rank': 2, 'color': '#00ff00',
                        'stations': [station_row('us-official-beta-1', 'Beta One', 5.0, 5.0)],
                        'segments': [[2.0, 0, [[5.0, 5.0]]]],
                        'colorReference': '#00ff00', 'colorSource': 'gtfs',
                        'colorDark': '#00ff00',
                    },
                ],
                'geometrySource': {
                    'officialOnly': 0, 'providers': {'x': 'y'}, 'license': 'CC-BY',
                    'syntheticConnectors': 0, 'osmSources': 1,
                    'verifiedOfficialNetworks': {
                        'test-feed-src-1': {'sourceId': 'test-1', 'publisher': 'p'},
                        'stale-unused-key': {'sourceId': 'stale', 'publisher': 'p'},
                    },
                    'officialGeometryComparison': {
                        'scope': 'test scope', 'lines': 2, 'maxDeviationMeters': 5.0,
                        'byLine': {
                            'test-feed-alpha': {'maxDeviationMeters': 5.0},
                            'other-feed-beta': {'maxDeviationMeters': 1.0},
                        },
                    },
                },
                'attributeSources': {'colours': 'x'},
            },
            'stations': {'type': 'FeatureCollection',
                        'features': alpha_old_stations + beta_stations},
            'sections': {'type': 'FeatureCollection', 'features': [
                section_feature('Test Rail', 'Alpha', [[0.0, 0.0], [1.0, 1.0]]),
                section_feature('Other Rail', 'Beta', [[5.0, 5.0], [6.0, 6.0]]),
            ]},
            'readings': build_module.readings_for(
                alpha_old_stations + beta_stations, 'us'),
            'build_report': {
                'generatedAt': '2026-08-30T00:00:00.000Z',
                'feeds': [
                    {'slug': 'test-feed', 'lines': 1, 'dropped': [], 'notes': [],
                     'syntheticConnectors': 0},
                    {'slug': 'other-feed', 'lines': 1, 'dropped': [], 'notes': [],
                     'syntheticConnectors': 0},
                ],
                'regions': {'us': {
                    'lines': 2, 'stationGroups': 3, 'sections': 2,
                    'zones': ['America/New_York'], 'maxDeviationMeters': 5.0,
                    'bytes': {'package': 1, 'stations': 1, 'sections': 1,
                             'readings': 1},
                }},
            },
        }
        # Sanity: readings_for's own skeleton fields must round-trip so the
        # fixture matches what merge_readings() will assert unchanged.
        assert self.shipped['readings']['note'] == skeleton['note']

        alpha_new_stations = [
            station_feature('Test Rail', 'test-feed', 'us-official-alpha-1v2',
                            '10', 'a1v2', 'Alpha One', 0.1, 0.1),
            station_feature('Test Rail', 'test-feed', 'us-official-alpha-2v2',
                            '20', 'a2v2', 'Alpha Two', 1.1, 1.1),
            station_feature('Test Rail', 'test-feed', 'us-official-alpha-3v2',
                            '30', 'a3v2', 'Alpha Three', 2.1, 2.1),
        ]
        gamma_stations = [
            station_feature('Test Rail', 'test-feed', 'us-official-gamma-1',
                            '40', 'g1', 'Gamma One', 9.0, 9.0,
                            zone='America/Los_Angeles'),
        ]
        self.candidate = {
            'package': {
                'lines': [
                    {
                        'id': 'test-feed-alpha', 'name': 'Alpha v2',
                        'operator': 'Test Rail', 'sourceFeed': 'test-feed',
                        'kind': 'regional', 'geometrySource': 'test-feed-src-1-v2',
                        'lengthKm': 1.5, 'rank': 1, 'color': '#ff1100',
                        'stations': [
                            station_row('a1v2', 'Alpha One', 0.1, 0.1),
                            station_row('a2v2', 'Alpha Two', 1.1, 1.1),
                            station_row('a3v2', 'Alpha Three', 2.1, 2.1),
                        ],
                        'segments': [[1.5, 0, [[0.1, 0.1], [1.1, 1.1], [2.1, 2.1]]]],
                        'colorReference': '#ff1100', 'colorSource': 'gtfs',
                        'colorDark': '#ff1100',
                    },
                    {
                        'id': 'test-feed-gamma', 'name': 'Gamma',
                        'operator': 'Test Rail', 'sourceFeed': 'test-feed',
                        'kind': 'regional', 'geometrySource': 'test-feed-src-2',
                        'lengthKm': 0.5, 'rank': 3, 'color': '#0011ff',
                        'stations': [station_row('g1', 'Gamma One', 9.0, 9.0)],
                        'segments': [[0.5, 0, [[9.0, 9.0]]]],
                        'colorReference': '#0011ff', 'colorSource': 'gtfs',
                        'colorDark': '#0011ff',
                    },
                ],
                'geometrySource': {
                    'verifiedOfficialNetworks': {
                        'test-feed-src-1-v2': {'sourceId': 'test-1v2', 'publisher': 'p'},
                        'test-feed-src-2': {'sourceId': 'test-2', 'publisher': 'p'},
                    },
                    'officialGeometryComparison': {'byLine': {
                        'test-feed-alpha': {'maxDeviationMeters': 3.0},
                        'test-feed-gamma': {'maxDeviationMeters': 2.0},
                    }},
                },
            },
            'stations': {'type': 'FeatureCollection',
                        'features': alpha_new_stations + gamma_stations},
            'sections': {'type': 'FeatureCollection', 'features': [
                section_feature('Test Rail', 'Alpha v2',
                                [[0.1, 0.1], [1.1, 1.1], [2.1, 2.1]]),
                section_feature('Test Rail', 'Gamma', [[9.0, 9.0], [9.1, 9.1]]),
            ]},
            'readings': None,  # unused by build_plan; candidate readings are
                                # not read (see merge_readings docstring)
            'build_report': {'feeds': [
                {'slug': 'test-feed', 'lines': 2,
                 'dropped': [{'route': 'x', 'why': 'test'}],
                 'notes': ['test-feed rebuilt'], 'syntheticConnectors': 0},
            ]},
        }


class BuildPlanTests(unittest.TestCase):
    def setUp(self):
        self.fx = MergeFixture()
        self.plan = merge.build_plan(
            self.fx.build_module, self.fx.shipped, self.fx.candidate,
            'us', 'test-feed')

    def test_existing_line_is_replaced(self):
        alpha = next(l for l in self.plan.package['lines']
                    if l['id'] == 'test-feed-alpha')
        self.assertEqual(alpha['geometrySource'], 'test-feed-src-1-v2')
        self.assertEqual(len(alpha['stations']), 3)
        self.assertEqual(alpha['name'], 'Alpha v2')

    def test_new_line_is_added(self):
        ids = [l['id'] for l in self.plan.package['lines']]
        self.assertIn('test-feed-gamma', ids)
        self.assertEqual(len(ids), 3)  # alpha (replaced) + gamma (new) + beta

    def test_unrelated_operator_untouched_byte_for_byte(self):
        beta_before = next(
            l for l in self.fx.shipped['package']['lines']
            if l['id'] == 'other-feed-beta')
        beta_after = next(
            l for l in self.plan.package['lines']
            if l['id'] == 'other-feed-beta')
        self.assertEqual(json.dumps(beta_before, sort_keys=True),
                         json.dumps(beta_after, sort_keys=True))
        # And its section/station features never moved.
        other_sections_before = [
            f for f in self.fx.shipped['sections']['features']
            if f['properties']['operator'] == 'Other Rail']
        other_sections_after = [
            f for f in self.plan.sections['features']
            if f['properties']['operator'] == 'Other Rail']
        self.assertEqual(other_sections_before, other_sections_after)
        other_stations_after = [
            f for f in self.plan.stations['features']
            if f['properties']['operator'] == 'Other Rail']
        self.assertEqual(len(other_stations_after), 1)
        self.assertEqual(
            other_stations_after[0]['properties']['n02_group_code'],
            'us-official-beta-1')

    def test_stations_and_sections_are_rekeyed_to_the_candidate(self):
        test_rail_stations = [
            f for f in self.plan.stations['features']
            if f['properties']['operator'] == 'Test Rail']
        self.assertEqual(len(test_rail_stations), 4)  # 3 alpha-v2 + 1 gamma
        codes = {f['properties']['n02_group_code'] for f in test_rail_stations}
        self.assertEqual(codes, {
            'us-official-alpha-1v2', 'us-official-alpha-2v2',
            'us-official-alpha-3v2', 'us-official-gamma-1'})
        # The old alpha station codes are gone entirely.
        all_codes = {f['properties']['n02_group_code']
                    for f in self.plan.stations['features']}
        self.assertNotIn('us-official-alpha-1', all_codes)
        self.assertNotIn('us-official-alpha-2', all_codes)

        test_rail_sections = [
            f for f in self.plan.sections['features']
            if f['properties']['operator'] == 'Test Rail']
        self.assertEqual(len(test_rail_sections), 2)
        self.assertEqual(
            {f['properties']['line_name'] for f in test_rail_sections},
            {'Alpha v2', 'Gamma'})

    def test_readings_recomputed_over_merged_stations(self):
        # 4 Test Rail stations (unique codes) + 1 Other Rail station, each
        # contributing its own n02_station_code and n02_group_code, plus
        # each station's own name in byName.
        self.assertEqual(self.plan.readings['stats']['byCode'], 5 * 2)
        self.assertEqual(self.plan.readings['stats']['byName'], 5)
        self.assertIn('Gamma One', self.plan.readings['byName'])
        self.assertIn('Beta One', self.plan.readings['byName'])
        self.assertEqual(self.plan.readings['byName']['Alpha One']['name'],
                         'Alpha One')

    def test_verified_official_networks_drops_unused_and_adds_new(self):
        verified = self.plan.package['geometrySource']['verifiedOfficialNetworks']
        self.assertIn('test-feed-src-1-v2', verified)
        self.assertIn('test-feed-src-2', verified)
        self.assertNotIn('test-feed-src-1', verified)  # no line uses it any more
        self.assertNotIn('stale-unused-key', verified)  # was already unused

    def test_by_line_and_max_deviation_recomputed(self):
        comparison = self.plan.package['geometrySource']['officialGeometryComparison']
        self.assertEqual(comparison['lines'], 3)
        self.assertEqual(set(comparison['byLine']), {
            'test-feed-alpha', 'test-feed-gamma', 'other-feed-beta'})
        self.assertEqual(comparison['byLine']['test-feed-alpha']
                         ['maxDeviationMeters'], 3.0)
        # other-feed-beta (1.0) is no longer the worst; test-feed-alpha (3.0) is.
        self.assertEqual(comparison['maxDeviationMeters'], 3.0)

    def test_time_zone_extended_not_replaced(self):
        self.assertEqual(self.plan.package['timeZones'],
                         ['America/New_York', 'America/Los_Angeles'])

    def test_build_report_feed_entry_replaced(self):
        feeds = {f['slug']: f for f in self.plan.build_report['feeds']}
        self.assertEqual(feeds['test-feed']['lines'], 2)
        self.assertEqual(feeds['test-feed']['notes'], ['test-feed rebuilt'])
        self.assertEqual(feeds['other-feed']['lines'], 1)  # untouched

    def test_region_stats_recomputed(self):
        stats = self.plan.build_report['regions']['us']
        self.assertEqual(stats['lines'], 3)
        self.assertEqual(stats['sections'], 3)  # 1 kept (Beta) + 2 candidate
        self.assertEqual(stats['stationGroups'], 5)


class MergeLinesUnitTests(unittest.TestCase):
    def test_feed_with_no_shipped_lines_appends_at_the_end(self):
        shipped = [{'id': 'x', 'sourceFeed': 'other'}]
        candidate = [{'id': 'new-feed-a', 'sourceFeed': 'new-feed'}]
        merged, removed, added = merge.merge_lines(shipped, candidate, 'new-feed')
        self.assertEqual(removed, [])
        self.assertEqual(added, ['new-feed-a'])
        self.assertEqual([l['id'] for l in merged], ['x', 'new-feed-a'])

    def test_position_is_preserved(self):
        shipped = [{'id': 'a', 'sourceFeed': 'keep'},
                  {'id': 'b', 'sourceFeed': 'feed'},
                  {'id': 'c', 'sourceFeed': 'keep'}]
        candidate = [{'id': 'b2', 'sourceFeed': 'feed'}]
        merged, removed, added = merge.merge_lines(shipped, candidate, 'feed')
        self.assertEqual([l['id'] for l in merged], ['a', 'b2', 'c'])


class FeedOperatorsSafetyTests(unittest.TestCase):
    """feed_operators() no longer raises on a collision -- see its docstring.

    `operator_collision()` is the replacement way to detect one (used by
    build_plan() to decide whether a warning is warranted); the actual
    removal-safety no longer depends on refusing the merge outright, but on
    `feed_station_removal_keys()` / `feed_section_removal_keys()` deriving
    an exact key from this feed's own shipped lines -- see
    `FeedRemovalKeysTests` and `LineIdScopedBuildPlanTests`'s collision test.
    """

    def test_shared_operator_name_across_feeds_no_longer_raises(self):
        shipped = [
            {'sourceFeed': 'feed-a', 'operator': 'Shared Co'},
            {'sourceFeed': 'feed-b', 'operator': 'Shared Co'},
        ]
        candidate = [{'sourceFeed': 'feed-a', 'operator': 'Shared Co'}]
        ops = merge.feed_operators(shipped, candidate, 'feed-a')
        self.assertEqual(ops, {'Shared Co'})
        self.assertEqual(
            merge.operator_collision(shipped, 'feed-a', ops=ops),
            {'Shared Co'})

    def test_line_id_scoping_clears_a_collision_from_an_untouched_sibling(self):
        # 'feed-a' has two lines: one whose operator ('Shared Co') already
        # collides with 'feed-b', and one whose operator ('Only Co') is its
        # own. Without scoping, operator_collision() reports the collision
        # (though feed_operators() itself never raises); scoping to just the
        # 'Only Co' line clears it -- that untouched 'Shared Co' line, same
        # feed or not, is exactly what `owns()` excludes.
        shipped = [
            {'id': 'a-shared', 'sourceFeed': 'feed-a', 'operator': 'Shared Co'},
            {'id': 'a-only', 'sourceFeed': 'feed-a', 'operator': 'Only Co'},
            {'id': 'b-shared', 'sourceFeed': 'feed-b', 'operator': 'Shared Co'},
        ]
        candidate = [
            {'id': 'a-shared', 'sourceFeed': 'feed-a', 'operator': 'Shared Co'},
            {'id': 'a-only', 'sourceFeed': 'feed-a', 'operator': 'Only Co'},
        ]
        ops = merge.feed_operators(shipped, candidate, 'feed-a')
        self.assertEqual(
            merge.operator_collision(shipped, 'feed-a', ops=ops),
            {'Shared Co'})
        ops = merge.feed_operators(shipped, candidate, 'feed-a',
                                   line_ids={'a-only'})
        self.assertEqual(ops, {'Only Co'})
        self.assertEqual(
            merge.operator_collision(shipped, 'feed-a', line_ids={'a-only'},
                                     ops=ops),
            set())


class FeedRemovalKeysTests(unittest.TestCase):
    """feed_station_removal_keys() / feed_section_removal_keys()."""

    def test_collision_case_keys_are_scoped_to_this_feeds_own_rows(self):
        # feed-a and feed-b both publish an operator named 'Shared Co' --
        # the SEPTA-style collision. The removal keys must name only
        # feed-a's own station id, not feed-b's.
        shipped = [
            {'id': 'a1', 'sourceFeed': 'feed-a', 'operator': 'Shared Co',
             'name': 'A Line',
             'stations': [['stn-a', 'A', 0.0, 0.0]]},
            {'id': 'b1', 'sourceFeed': 'feed-b', 'operator': 'Shared Co',
             'name': 'B Line',
             'stations': [['stn-b', 'B', 1.0, 1.0]]},
        ]
        self.assertEqual(
            merge.feed_station_removal_keys(shipped, 'feed-a'),
            {('Shared Co', 'stn-a')})
        self.assertEqual(
            merge.feed_section_removal_keys(shipped, 'feed-a'),
            {('Shared Co', 'A Line')})

    def test_exclusive_operator_case(self):
        shipped = [
            {'id': 'a1', 'sourceFeed': 'feed-a', 'operator': 'Only Co',
             'name': 'Only Line',
             'stations': [['stn-1', 'One', 0.0, 0.0],
                         ['stn-2', 'Two', 1.0, 1.0]]},
        ]
        self.assertEqual(
            merge.feed_station_removal_keys(shipped, 'feed-a'),
            {('Only Co', 'stn-1'), ('Only Co', 'stn-2')})
        self.assertEqual(
            merge.feed_section_removal_keys(shipped, 'feed-a'),
            {('Only Co', 'Only Line')})
        self.assertEqual(merge.operator_collision(shipped, 'feed-a'), set())

    def test_first_ship_feed_with_zero_shipped_lines_has_no_removal_keys(self):
        shipped = [
            {'id': 'x1', 'sourceFeed': 'other-feed', 'operator': 'Other Co',
             'name': 'X', 'stations': [['stn-x', 'X', 0.0, 0.0]]},
        ]
        self.assertEqual(merge.feed_station_removal_keys(shipped, 'new-feed'),
                         set())
        self.assertEqual(merge.feed_section_removal_keys(shipped, 'new-feed'),
                         set())
        self.assertEqual(
            merge.station_removal_predicate(set(), {'New Co'}, False)(
                {'properties': {'operator': 'New Co', 'n02_group_code': 'x'}}),
            False)
        self.assertEqual(
            merge.section_removal_predicate(set(), {'New Co'}, False)(
                {'properties': {'operator': 'New Co', 'line_name': 'X'}}),
            False)


class ScopeCandidateToLinesTests(unittest.TestCase):
    def setUp(self):
        self.candidate = {
            'package': {'lines': [
                {'id': 'feed-x', 'sourceFeed': 'feed', 'operator': 'X Co'},
                {'id': 'feed-y', 'sourceFeed': 'feed', 'operator': 'Y Co'},
            ]},
            'stations': {'type': 'FeatureCollection', 'features': [
                station_feature('X Co', 'feed', 'us-official-x', '1', 'x1',
                                'X Station', 0.0, 0.0),
                station_feature('Y Co', 'feed', 'us-official-y', '1', 'y1',
                                'Y Station', 1.0, 1.0),
            ]},
            'sections': {'type': 'FeatureCollection', 'features': [
                section_feature('X Co', 'X', [[0.0, 0.0], [0.1, 0.1]]),
                section_feature('Y Co', 'Y', [[1.0, 1.0], [1.1, 1.1]]),
            ]},
            'readings': None,
            'build_report': {'feeds': [{'slug': 'feed', 'lines': 2}]},
        }

    def test_keeps_only_the_requested_line_and_its_own_operator_features(self):
        scoped = merge.scope_candidate_to_lines(
            self.candidate, 'feed', {'feed-x'})
        self.assertEqual([l['id'] for l in scoped['package']['lines']],
                         ['feed-x'])
        self.assertEqual(
            [f['properties']['operator']
            for f in scoped['stations']['features']], ['X Co'])
        self.assertEqual(
            [f['properties']['operator']
            for f in scoped['sections']['features']], ['X Co'])
        # The unscoped candidate itself must be untouched (no aliasing).
        self.assertEqual(len(self.candidate['package']['lines']), 2)

    def test_unknown_line_id_raises(self):
        with self.assertRaises(ValueError):
            merge.scope_candidate_to_lines(
                self.candidate, 'feed', {'feed-x', 'feed-nonexistent'})


class LineIdScopedBuildPlanTests(unittest.TestCase):
    """The Seattle Center Monorail scenario, end to end.

    'test-feed' publishes two lines sharing this fixture's candidate build:
    'test-feed-shared', whose operator is already shipped by the unrelated
    'other-feed' (so a whole-feed merge must refuse, the same way the real
    Puget Sound consolidated feed's Sound Transit lines collide with the
    separately-shipped `sound-transit` feed) and 'test-feed-solo', whose
    operator belongs to no other line anywhere. `--line-id test-feed-solo`
    must merge cleanly and touch nothing belonging to 'test-feed-shared' or
    'other-feed'.
    """

    def setUp(self):
        build_module = merge.load_build_module()
        self.build_module = build_module
        shared_before = [
            station_feature('Shared Co', 'other-feed', 'us-official-shared',
                            '1', 's1', 'Shared Station', 5.0, 5.0),
        ]
        self.shipped = {
            'package': {
                'format': 'compact-v1', 'version': '2026.2.0',
                'generatedAt': '2026-08-30T00:00:00.000Z', 'crs': 'WGS84',
                'country': 'US', 'timeZones': ['America/New_York'],
                'lines': [
                    {
                        'id': 'other-feed-shared', 'name': 'Shared',
                        'operator': 'Shared Co', 'sourceFeed': 'other-feed',
                        'kind': 'regional', 'geometrySource': 'narn',
                        'lengthKm': 1.0, 'rank': 1, 'color': '#ff0000',
                        'stations': [station_row('s1', 'Shared Station', 5.0, 5.0)],
                        'segments': [[1.0, 0, [[5.0, 5.0]]]],
                        'colorReference': '#ff0000', 'colorSource': 'gtfs',
                        'colorDark': '#ff0000',
                    },
                ],
                'geometrySource': {
                    'officialOnly': 0, 'providers': {}, 'license': 'CC-BY',
                    'syntheticConnectors': 0, 'osmSources': 1,
                    'verifiedOfficialNetworks': {},
                    'officialGeometryComparison': {
                        'scope': 'test', 'lines': 1, 'maxDeviationMeters': 1.0,
                        'byLine': {'other-feed-shared': {'maxDeviationMeters': 1.0}},
                    },
                },
                'attributeSources': {'colours': 'x'},
            },
            'stations': {'type': 'FeatureCollection', 'features': shared_before},
            'sections': {'type': 'FeatureCollection', 'features': [
                section_feature('Shared Co', 'Shared', [[5.0, 5.0], [5.1, 5.1]]),
            ]},
            'readings': build_module.readings_for(shared_before, 'us'),
            'build_report': {
                'generatedAt': '2026-08-30T00:00:00.000Z',
                'feeds': [
                    {'slug': 'other-feed', 'lines': 1, 'dropped': [],
                     'notes': [], 'syntheticConnectors': 0},
                ],
                'regions': {'us': {
                    'lines': 1, 'stationGroups': 1, 'sections': 1,
                    'zones': ['America/New_York'], 'maxDeviationMeters': 1.0,
                    'bytes': {'package': 1, 'stations': 1, 'sections': 1,
                             'readings': 1},
                }},
            },
        }
        solo_stations = [
            station_feature('Solo Co', 'test-feed', 'us-official-solo',
                            '1', 'z1', 'Solo Station', 9.0, 9.0),
        ]
        shared_candidate_stations = [
            station_feature('Shared Co', 'test-feed', 'us-official-shared',
                            '1', 's1', 'Shared Station', 5.0, 5.0),
        ]
        self.candidate = {
            'package': {'lines': [
                {
                    'id': 'test-feed-shared', 'name': 'Shared',
                    'operator': 'Shared Co', 'sourceFeed': 'test-feed',
                    'kind': 'regional', 'geometrySource': 'narn',
                    'lengthKm': 1.0, 'rank': 1, 'color': '#ff0000',
                    'stations': [station_row('s1', 'Shared Station', 5.0, 5.0)],
                    'segments': [[1.0, 0, [[5.0, 5.0]]]],
                    'colorReference': '#ff0000', 'colorSource': 'gtfs',
                    'colorDark': '#ff0000',
                },
                {
                    'id': 'test-feed-solo', 'name': 'Solo',
                    'operator': 'Solo Co', 'sourceFeed': 'test-feed',
                    'kind': 'commuter', 'geometrySource': 'gtfs-shape',
                    'lengthKm': 0.5, 'rank': 2, 'color': '#0011ff',
                    'stations': [station_row('z1', 'Solo Station', 9.0, 9.0)],
                    'segments': [[0.5, 0, [[9.0, 9.0]]]],
                    'colorReference': '#0011ff', 'colorSource': 'gtfs',
                    'colorDark': '#0011ff',
                },
            ],
            'geometrySource': {
                'verifiedOfficialNetworks': {},
                'officialGeometryComparison': {'byLine': {
                    'test-feed-shared': {'maxDeviationMeters': 1.0},
                    'test-feed-solo': {'maxDeviationMeters': 0.5},
                }},
            }},
            'stations': {'type': 'FeatureCollection',
                        'features': shared_candidate_stations + solo_stations},
            'sections': {'type': 'FeatureCollection', 'features': [
                section_feature('Shared Co', 'Shared', [[5.0, 5.0], [5.1, 5.1]]),
                section_feature('Solo Co', 'Solo', [[9.0, 9.0], [9.1, 9.1]]),
            ]},
            'readings': None,
            'build_report': {'feeds': [
                {'slug': 'test-feed', 'lines': 2,
                 'dropped': [{'route': 'x', 'why': 'test'}],
                 'notes': ['test-feed rebuilt'], 'syntheticConnectors': 0},
            ]},
        }

    def test_whole_feed_merge_succeeds_despite_operator_collision_when_feed_is_new(self):
        # 'test-feed' has never shipped before, so feed_station_removal_keys()
        # / feed_section_removal_keys() come back empty and nothing is
        # removed -- there is nothing of 'test-feed's own to remove, and
        # 'other-feed-shared's operator-string collision ('Shared Co') no
        # longer blocks the merge (see feed_operators()'s docstring). Both
        # new lines ship; 'other-feed-shared' is untouched.
        plan = merge.build_plan(self.build_module, self.shipped, self.candidate,
                                'us', 'test-feed')
        ids = [l['id'] for l in plan.package['lines']]
        self.assertIn('test-feed-shared', ids)
        self.assertIn('test-feed-solo', ids)
        self.assertIn('other-feed-shared', ids)
        self.assertEqual(sorted(plan.added_ids),
                         ['test-feed-shared', 'test-feed-solo'])
        self.assertEqual(plan.removed_ids, [])

        other_before = next(
            l for l in self.shipped['package']['lines']
            if l['id'] == 'other-feed-shared')
        other_after = next(
            l for l in plan.package['lines'] if l['id'] == 'other-feed-shared')
        self.assertEqual(json.dumps(other_before, sort_keys=True),
                         json.dumps(other_after, sort_keys=True))

        # Both the untouched shipped 'other-feed' station and the brand-new
        # 'test-feed' one ship -- 'test-feed' is first-ship, so nothing is
        # removed, even though both happen to be 'Shared Co' (that they also
        # share a group code text is this fixture's collision scenario, not
        # something this merge is responsible for deduplicating).
        shared_co_stations = [
            f for f in plan.stations['features']
            if f['properties']['operator'] == 'Shared Co']
        self.assertEqual(len(shared_co_stations), 2)
        self.assertIn(
            json.dumps(self.shipped['stations']['features'][0], sort_keys=True),
            [json.dumps(f, sort_keys=True) for f in shared_co_stations])

    def test_scoped_merge_of_the_solo_line_succeeds(self):
        plan = merge.build_plan(
            self.build_module, self.shipped, self.candidate, 'us', 'test-feed',
            line_ids={'test-feed-solo'})
        ids = [l['id'] for l in plan.package['lines']]
        self.assertIn('test-feed-solo', ids)
        self.assertIn('other-feed-shared', ids)
        self.assertNotIn('test-feed-shared', ids)
        self.assertEqual(plan.added_ids, ['test-feed-solo'])
        self.assertEqual(plan.removed_ids, [])

    def test_scoped_merge_does_not_touch_the_shared_operator_station(self):
        plan = merge.build_plan(
            self.build_module, self.shipped, self.candidate, 'us', 'test-feed',
            line_ids={'test-feed-solo'})
        shared_before = next(
            f for f in self.shipped['stations']['features']
            if f['properties']['operator'] == 'Shared Co')
        shared_after = next(
            f for f in plan.stations['features']
            if f['properties']['operator'] == 'Shared Co')
        self.assertEqual(json.dumps(shared_before, sort_keys=True),
                         json.dumps(shared_after, sort_keys=True))
        solo = [f for f in plan.stations['features']
               if f['properties']['operator'] == 'Solo Co']
        self.assertEqual(len(solo), 1)

    def test_scoped_build_report_records_the_scope_not_the_whole_candidate(self):
        plan = merge.build_plan(
            self.build_module, self.shipped, self.candidate, 'us', 'test-feed',
            line_ids={'test-feed-solo'})
        feed_report = next(f for f in plan.build_report['feeds']
                           if f['slug'] == 'test-feed')
        self.assertEqual(feed_report['lines'], 1)
        self.assertEqual(feed_report['scopedToLineIds'], ['test-feed-solo'])
        self.assertEqual(feed_report['unscopedCandidateLines'], 2)


class BackupBeforeMergeTests(unittest.TestCase):
    """backup_before_merge() -- every rewritten file is backed up first."""

    def test_existing_files_are_copied_by_basename_into_backup_dir(self):
        with tempfile.TemporaryDirectory() as candidate_dir, \
                tempfile.TemporaryDirectory() as shipped_dir:
            package_path = os.path.join(shipped_dir, 'us-2025.json')
            stations_path = os.path.join(shipped_dir, 'stations-us.json')
            with open(package_path, 'w', encoding='utf-8') as fh:
                fh.write('{"lines": []}')
            with open(stations_path, 'w', encoding='utf-8') as fh:
                fh.write('{"features": []}')

            backed_up = merge.backup_before_merge(
                candidate_dir, [package_path, stations_path])

            backup_dir = os.path.join(candidate_dir, 'backup-before-merge')
            self.assertEqual(
                sorted(os.listdir(backup_dir)),
                ['stations-us.json', 'us-2025.json'])
            self.assertEqual(len(backed_up), 2)
            with open(os.path.join(backup_dir, 'us-2025.json'),
                     encoding='utf-8') as fh:
                self.assertEqual(fh.read(), '{"lines": []}')

    def test_missing_source_file_is_skipped_not_an_error(self):
        with tempfile.TemporaryDirectory() as candidate_dir:
            backed_up = merge.backup_before_merge(
                candidate_dir, [os.path.join(candidate_dir, 'never-existed.json')])
            self.assertEqual(backed_up, [])
            # The backup directory is still created even with nothing to copy.
            self.assertTrue(os.path.isdir(
                os.path.join(candidate_dir, 'backup-before-merge')))

    def test_original_file_is_untouched_after_backup(self):
        with tempfile.TemporaryDirectory() as candidate_dir, \
                tempfile.TemporaryDirectory() as shipped_dir:
            path = os.path.join(shipped_dir, 'na-2025-build-report.json')
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write('{"feeds": []}')
            merge.backup_before_merge(candidate_dir, [path])
            with open(path, encoding='utf-8') as fh:
                self.assertEqual(fh.read(), '{"feeds": []}')


class WriteJsonCompactTests(unittest.TestCase):
    def test_matches_builder_serialisation_and_has_no_trailing_newline(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, 'out.json')
            merge.write_json_compact(path, {'b': 1, 'a': [1, 2]})
            with open(path, 'rb') as fh:
                raw = fh.read()
            self.assertEqual(raw, b'{"b": 1, "a": [1, 2]}')
            self.assertEqual(len(raw), merge.compact_size({'b': 1, 'a': [1, 2]}))


class RefreshAuditMdTests(unittest.TestCase):
    def test_lead_paragraph_numbers_and_title_date_are_replaced(self):
        text = (
            '# United States rail audit — 2026-09-01\n\n'
            'The strict generated package contains 250 lines, 2,802 station '
            'groups and\n3,559 station intervals. The compact audit reports '
            '0 errors, 134 warnings and\n19 notes: 63 curve-radius reviews, '
            '19 retained-official alignment reviews, 45\nstation-split '
            'warnings, 6 nested-operator reviews, one geometry-spike '
            'review,\n17 display-withholding decisions and two '
            'optional-field notes.\n\n'
            'See [`us-2025.audit.json`](./us-2025.audit.json) for details.\n'
        )
        path_holder = tempfile.NamedTemporaryFile(
            mode='w', suffix='.md', delete=False)
        path_holder.write(text)
        path_holder.close()
        try:
            audit_json = {'findings': [
                {'severity': 'WARN', 'check': 'geometry.radius'},
                {'severity': 'NOTE', 'check': 'package.field:logo'},
            ]}
            package = {'country': 'US', 'lines': [1, 2, 3]}
            out = merge.refresh_audit_md(
                path_holder.name, package, audit_json, 9, 12, '2026-09-02')
            self.assertIn('# United States rail audit — 2026-09-02', out)
            self.assertIn('The strict generated package contains 3 lines, '
                          '9 station groups', out)
            self.assertIn('1 curve-radius reviews', out)
            self.assertIn('no geometry-spike review', out)
            self.assertIn('one optional-field notes', out)
            self.assertIn('See [`us-2025.audit.json`]', out)  # untouched tail
        finally:
            os.unlink(path_holder.name)


def offset_point(point, north_m=0.0, east_m=0.0):
    """A point roughly `north_m`/`east_m` metres from `point`.

    Good enough for test fixtures: at these small offsets and the latitudes
    used below, the flat-earth approximation is within a few centimetres of
    `na_geo.haversine`'s great-circle answer -- far smaller than the 15 m /
    60 m identity tolerances the tests sit deliberately away from either
    side of.
    """
    lon, lat = point
    dlat = north_m / 111320.0
    dlon = east_m / (111320.0 * math.cos(math.radians(lat)) or 1.0)
    return [lon + dlon, lat + dlat]


class StationIdentityUnitTests(unittest.TestCase):
    """Direct tests of station_identity_map() / apply_station_identity()."""

    def setUp(self):
        self.build_module = merge.load_build_module()
        self.operators = {'Test Rail'}

    def test_within_coord_tolerance_is_renamed(self):
        shipped = [station_feature('Test Rail', 'test-feed',
                                   'us-official-old-name', '1', 'a',
                                   'Old Name', 0.0, 0.0)]
        moved = offset_point([0.0, 0.0], north_m=10.0)  # inside 15 m
        candidate = [station_feature('Test Rail', 'test-feed',
                                     'us-official-new-name', '1', 'a',
                                     'New Name', moved[0], moved[1])]
        rename_map = merge.station_identity_map(
            self.build_module, shipped, candidate, self.operators)
        self.assertEqual(rename_map, {'us-official-new-name': 'us-official-old-name'})

    def test_beyond_both_tolerances_with_different_name_is_new(self):
        shipped = [station_feature('Test Rail', 'test-feed',
                                   'us-official-nearby-shipped', '1', 'a',
                                   'Nearby Shipped', 20.0, 20.0)]
        far = offset_point([20.0, 20.0], north_m=100.0)  # past 15 m and 60 m
        candidate = [station_feature('Test Rail', 'test-feed',
                                     'us-official-moved-far', '1', 'a',
                                     'Totally Different Name', far[0], far[1])]
        rename_map = merge.station_identity_map(
            self.build_module, shipped, candidate, self.operators)
        self.assertEqual(rename_map, {})

    def test_same_normalised_name_within_name_tolerance_is_renamed(self):
        shipped = [station_feature('Test Rail', 'test-feed',
                                   'us-official-survey-moved', '1', 'a',
                                   'Survey Point', 40.0, 40.0)]
        moved = offset_point([40.0, 40.0], north_m=30.0)  # past 15 m, in 60 m
        candidate = [station_feature('Test Rail', 'test-feed',
                                     'us-official-renamed-far', '1', 'a',
                                     'SURVEY   point', moved[0], moved[1])]
        rename_map = merge.station_identity_map(
            self.build_module, shipped, candidate, self.operators)
        self.assertEqual(rename_map,
                         {'us-official-renamed-far': 'us-official-survey-moved'})

    def test_genuinely_new_station_is_not_matched(self):
        shipped = [station_feature('Test Rail', 'test-feed',
                                   'us-official-old-name', '1', 'a',
                                   'Old Name', 0.0, 0.0)]
        candidate = [station_feature('Test Rail', 'test-feed',
                                     'us-official-brand-new', '9', 'z',
                                     'Brand New Stop', 50.0, 50.0)]
        rename_map = merge.station_identity_map(
            self.build_module, shipped, candidate, self.operators)
        self.assertEqual(rename_map, {})

    def test_swapped_codes_resolve_by_coordinate_not_shared_code_text(self):
        """Two shipped stations whose codes a rebuild coincidentally swaps.

        Mirrors the real NYCT Penn Station case this feature guards against:
        the shipped package used `stn-a` for point A and `stn-b` for point
        B; the candidate reused `stn-a`'s *text* for point B and invented
        `stn-a-2` for point A. Matching by code string would keep both
        labels on the wrong platform; matching by coordinate must swap them
        back so each code stays on the same physical place.
        """
        shipped = [
            station_feature('Test Rail', 'test-feed', 'stn-a', '1', 'a',
                            'Complex', 0.0, 0.0),
            station_feature('Test Rail', 'test-feed', 'stn-b', '2', 'b',
                            'Complex', 1.0, 1.0),
        ]
        candidate = [
            station_feature('Test Rail', 'test-feed', 'stn-a', '10', 'a2',
                            'Complex', 1.0, 1.0),   # now sits where B was
            station_feature('Test Rail', 'test-feed', 'stn-a-2', '20', 'a3',
                            'Complex', 0.0, 0.0),    # now sits where A was
        ]
        rename_map = merge.station_identity_map(
            self.build_module, shipped, candidate, self.operators)
        self.assertEqual(rename_map, {
            'stn-a': 'stn-b',        # candidate's stn-a is really shipped B
            'stn-a-2': 'stn-a',      # candidate's stn-a-2 is really shipped A
        })

    def test_apply_station_identity_rewrites_rows_and_feature_ids(self):
        rename_map = {'us-official-new-name': 'us-official-old-name'}
        lines = [{
            'id': 'test-feed-alpha', 'sourceFeed': 'test-feed',
            'stations': [station_row('a', 'New Name', 0.0, 0.0),
                        station_row('b', 'Untouched', 1.0, 1.0)],
        }, {
            'id': 'other-feed-beta', 'sourceFeed': 'other-feed',
            'stations': [station_row('us-official-new-name', 'Should not '
                                     'move', 9.0, 9.0)],
        }]
        # The renamed code lives on the test-feed line's own first row here
        # (real candidate rows already carry the candidate's own codes, e.g.
        # 'a' would actually read 'us-official-new-name' -- rewritten below
        # to exercise the row-rewrite path directly).
        lines[0]['stations'][0][0] = 'us-official-new-name'
        features = [
            station_feature('Test Rail', 'test-feed', 'us-official-new-name',
                            '1', 'a', 'New Name', 0.0, 0.0),
            station_feature('Other Rail', 'other-feed', 'us-official-new-name',
                            '1', 'x', 'Should not move', 9.0, 9.0),
        ]
        new_lines, new_features = merge.apply_station_identity(
            lines, features, 'test-feed', self.operators, rename_map)

        alpha = next(l for l in new_lines if l['id'] == 'test-feed-alpha')
        self.assertEqual(alpha['stations'][0][0], 'us-official-old-name')
        beta = next(l for l in new_lines if l['id'] == 'other-feed-beta')
        self.assertEqual(beta['stations'][0][0], 'us-official-new-name')  # untouched

        test_rail_feature = next(
            f for f in new_features
            if f['properties']['operator'] == 'Test Rail')
        self.assertEqual(
            test_rail_feature['properties']['n02_group_code'],
            'us-official-old-name')
        self.assertTrue(
            test_rail_feature['properties']['n02_station_code']
            .endswith('-US-OFFICIAL-OLD-NAME'))
        other_rail_feature = next(
            f for f in new_features
            if f['properties']['operator'] == 'Other Rail')
        self.assertEqual(  # different feed's feature: code text coincides,
            other_rail_feature['properties']['n02_group_code'],  # but must
            'us-official-new-name')                              # not move

    def test_apply_station_identity_is_a_noop_with_an_empty_map(self):
        lines = [{'id': 'x', 'sourceFeed': 'test-feed',
                 'stations': [station_row('a', 'A', 0.0, 0.0)]}]
        features = [station_feature('Test Rail', 'test-feed', 'a', '1', 'a',
                                    'A', 0.0, 0.0)]
        new_lines, new_features = merge.apply_station_identity(
            lines, features, 'test-feed', self.operators, {})
        self.assertIs(new_lines, lines)
        self.assertIs(new_features, features)


class StationIdentityFixture:
    """A shipped/candidate pair built to exercise identity continuity.

    'Test Rail' (sourceFeed 'test-feed') ships one line calling at three
    stations. The candidate rebuild renames one of them a few metres away
    (`old-name` -> `new-name`), moves another's survey point 30 m under an
    equivalent normalised name (`survey-moved` -> `renamed-far`), and adds a
    station 100 m from a third shipped stop under an unrelated name
    (`nearby-shipped` stays put; `moved-far` is unrelated and new). A fourth
    candidate station, `brand-new`, has no shipped counterpart at all.
    """

    def __init__(self):
        build_module = merge.load_build_module()
        self.build_module = build_module

        old_name_moved = offset_point([0.0, 0.0], north_m=10.0)
        survey_moved = offset_point([40.0, 40.0], north_m=30.0)
        nearby_moved_far = offset_point([20.0, 20.0], north_m=100.0)

        shipped_stations = [
            station_feature('Test Rail', 'test-feed', 'us-official-old-name',
                            '1', 'a', 'Old Name', 0.0, 0.0),
            station_feature('Test Rail', 'test-feed',
                            'us-official-nearby-shipped', '2', 'b',
                            'Nearby Shipped', 20.0, 20.0),
            station_feature('Test Rail', 'test-feed',
                            'us-official-survey-moved', '3', 'c',
                            'Survey Point', 40.0, 40.0),
        ]
        self.shipped = {
            'package': {
                'format': 'compact-v1', 'version': '2026.2.0',
                'generatedAt': '2026-08-30T00:00:00.000Z', 'crs': 'WGS84',
                'country': 'US', 'timeZones': ['America/New_York'],
                'lines': [{
                    'id': 'test-feed-x', 'name': 'X', 'operator': 'Test Rail',
                    'sourceFeed': 'test-feed', 'kind': 'regional',
                    'geometrySource': 'test-feed-src-1',
                    'lengthKm': 1.0, 'rank': 1, 'color': '#ff0000',
                    'stations': [
                        station_row('us-official-old-name', 'Old Name', 0.0, 0.0),
                        station_row('us-official-nearby-shipped',
                                   'Nearby Shipped', 20.0, 20.0),
                        station_row('us-official-survey-moved',
                                   'Survey Point', 40.0, 40.0),
                    ],
                    'segments': [[1.0, 0, [[0.0, 0.0], [20.0, 20.0],
                                          [40.0, 40.0]]]],
                    'colorReference': '#ff0000', 'colorSource': 'gtfs',
                    'colorDark': '#ff0000',
                }],
                'geometrySource': {
                    'officialOnly': 0, 'providers': {'x': 'y'}, 'license': 'CC-BY',
                    'syntheticConnectors': 0, 'osmSources': 1,
                    'verifiedOfficialNetworks': {
                        'test-feed-src-1': {'sourceId': 'test-1', 'publisher': 'p'},
                    },
                    'officialGeometryComparison': {
                        'scope': 'test scope', 'lines': 1, 'maxDeviationMeters': 5.0,
                        'byLine': {'test-feed-x': {'maxDeviationMeters': 5.0}},
                    },
                },
                'attributeSources': {'colours': 'x'},
            },
            'stations': {'type': 'FeatureCollection', 'features': shipped_stations},
            'sections': {'type': 'FeatureCollection', 'features': [
                section_feature('Test Rail', 'X', [[0.0, 0.0], [40.0, 40.0]]),
            ]},
            'readings': build_module.readings_for(shipped_stations, 'us'),
            'build_report': {
                'generatedAt': '2026-08-30T00:00:00.000Z',
                'feeds': [{'slug': 'test-feed', 'lines': 1, 'dropped': [],
                          'notes': [], 'syntheticConnectors': 0}],
                'regions': {'us': {
                    'lines': 1, 'stationGroups': 3, 'sections': 1,
                    'zones': ['America/New_York'], 'maxDeviationMeters': 5.0,
                    'bytes': {'package': 1, 'stations': 1, 'sections': 1,
                             'readings': 1},
                }},
            },
        }

        candidate_stations = [
            station_feature('Test Rail', 'test-feed', 'us-official-new-name',
                            '10', 'a2', 'New Name',
                            old_name_moved[0], old_name_moved[1]),
            station_feature('Test Rail', 'test-feed',
                            'us-official-moved-far', '20', 'b2',
                            'Totally Different Name',
                            nearby_moved_far[0], nearby_moved_far[1]),
            station_feature('Test Rail', 'test-feed',
                            'us-official-renamed-far', '30', 'c2',
                            'SURVEY   point', survey_moved[0], survey_moved[1]),
            station_feature('Test Rail', 'test-feed', 'us-official-brand-new',
                            '40', 'd2', 'Brand New Stop', 50.0, 50.0),
        ]
        self.candidate = {
            'package': {
                'lines': [{
                    'id': 'test-feed-x', 'name': 'X v2', 'operator': 'Test Rail',
                    'sourceFeed': 'test-feed', 'kind': 'regional',
                    'geometrySource': 'test-feed-src-1-v2',
                    'lengthKm': 1.5, 'rank': 1, 'color': '#ff1100',
                    'stations': [
                        station_row('us-official-new-name', 'New Name',
                                   old_name_moved[0], old_name_moved[1]),
                        station_row('us-official-moved-far',
                                   'Totally Different Name',
                                   nearby_moved_far[0], nearby_moved_far[1]),
                        station_row('us-official-renamed-far', 'SURVEY   point',
                                   survey_moved[0], survey_moved[1]),
                        station_row('us-official-brand-new', 'Brand New Stop',
                                   50.0, 50.0),
                    ],
                    'segments': [[1.5, 0, [[old_name_moved[0], old_name_moved[1]],
                                          [nearby_moved_far[0], nearby_moved_far[1]],
                                          [survey_moved[0], survey_moved[1]],
                                          [50.0, 50.0]]]],
                    'colorReference': '#ff1100', 'colorSource': 'gtfs',
                    'colorDark': '#ff1100',
                }],
                'geometrySource': {
                    'verifiedOfficialNetworks': {
                        'test-feed-src-1-v2': {'sourceId': 'test-1v2', 'publisher': 'p'},
                    },
                    'officialGeometryComparison': {'byLine': {
                        'test-feed-x': {'maxDeviationMeters': 3.0},
                    }},
                },
            },
            'stations': {'type': 'FeatureCollection', 'features': candidate_stations},
            'sections': {'type': 'FeatureCollection', 'features': [
                section_feature('Test Rail', 'X v2',
                                [[old_name_moved[0], old_name_moved[1]],
                                 [50.0, 50.0]]),
            ]},
            'readings': None,
            'build_report': {'feeds': [
                {'slug': 'test-feed', 'lines': 1, 'dropped': [],
                 'notes': ['test-feed rebuilt'], 'syntheticConnectors': 0},
            ]},
        }


class StationIdentityContinuityTests(unittest.TestCase):
    def setUp(self):
        self.fx = StationIdentityFixture()
        self.plan = merge.build_plan(
            self.fx.build_module, self.fx.shipped, self.fx.candidate,
            'us', 'test-feed')

    def _codes(self):
        alpha = next(l for l in self.plan.package['lines']
                    if l['id'] == 'test-feed-x')
        return [row[0] for row in alpha['stations']]

    def test_renamed_station_keeps_its_shipped_code(self):
        self.assertIn('us-official-old-name', self._codes())
        self.assertNotIn('us-official-new-name', self._codes())
        self.assertEqual(
            self.plan.preserved_station_ids['us-official-new-name'],
            'us-official-old-name')

    def test_name_matched_moved_station_keeps_its_shipped_code(self):
        self.assertIn('us-official-survey-moved', self._codes())
        self.assertEqual(
            self.plan.preserved_station_ids['us-official-renamed-far'],
            'us-official-survey-moved')

    def test_station_moved_past_tolerance_with_different_name_is_new(self):
        self.assertIn('us-official-moved-far', self._codes())
        self.assertNotIn('us-official-moved-far',
                         self.plan.preserved_station_ids)
        # And the shipped station it did NOT match still simply disappears
        # with the rest of the replaced feed, rather than being force-kept.
        self.assertNotIn('us-official-nearby-shipped', self._codes())

    def test_genuinely_new_station_keeps_its_new_code(self):
        self.assertIn('us-official-brand-new', self._codes())
        self.assertNotIn('us-official-brand-new',
                         self.plan.preserved_station_ids)

    def test_preserved_ids_recorded_in_build_report(self):
        feed_report = next(f for f in self.plan.build_report['feeds']
                           if f['slug'] == 'test-feed')
        self.assertEqual(feed_report['preservedStationIds'], {
            'us-official-new-name': 'us-official-old-name',
            'us-official-renamed-far': 'us-official-survey-moved',
        })

    def test_station_features_carry_the_preserved_code_and_station_code(self):
        renamed_feature = next(
            f for f in self.plan.stations['features']
            if f['properties']['station_name'] == 'New Name')
        self.assertEqual(
            renamed_feature['properties']['n02_group_code'],
            'us-official-old-name')
        self.assertTrue(
            renamed_feature['properties']['n02_station_code']
            .endswith('-US-OFFICIAL-OLD-NAME'))

    def test_readings_are_keyed_by_the_preserved_code(self):
        self.assertIn('us-official-old-name', self.plan.readings['byCode'])
        self.assertNotIn('us-official-new-name', self.plan.readings['byCode'])

    def test_merging_the_same_candidate_twice_is_idempotent(self):
        # Re-run the merge with the freshly-merged package standing in as
        # "shipped" -- the second pass sees its own preserved codes back on
        # disk, matches the candidate to itself at ~0 m, and must reproduce
        # exactly the same package rather than drifting.
        shipped_again = {
            'package': self.plan.package,
            'stations': self.plan.stations,
            'sections': self.plan.sections,
            'readings': self.plan.readings,
            'build_report': self.plan.build_report,
        }
        plan2 = merge.build_plan(
            self.fx.build_module, shipped_again, self.fx.candidate,
            'us', 'test-feed')
        self.assertEqual(
            json.dumps(plan2.package, sort_keys=True),
            json.dumps(self.plan.package, sort_keys=True))
        self.assertEqual(
            json.dumps(plan2.stations, sort_keys=True),
            json.dumps(self.plan.stations, sort_keys=True))
        self.assertEqual(plan2.preserved_station_ids,
                         self.plan.preserved_station_ids)


if __name__ == '__main__':
    unittest.main()
