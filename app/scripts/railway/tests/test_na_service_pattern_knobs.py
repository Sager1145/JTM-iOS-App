"""Tests for the service-pattern selection knobs: never-operating services,
lead-in-spur loops, ``excludeStopIdsByRouteId`` and ``excludeTripsByRouteId``.

Mirrors the fixture style of ``test_na_builder.py`` (``FeedBuild.__new__`` with
hand-set attributes) and ``test_na_lines_preferred_trunk.py`` (a bare
``na_lines.Pattern`` factory) rather than exercising a full feed build.
"""
import importlib.util
import os
import sys
import unittest

SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'build-north-america-rail-package.py'))
SPEC = importlib.util.spec_from_file_location('na_package_builder', SCRIPT)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)

LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib'))
if LIB not in sys.path:
    sys.path.insert(0, LIB)
import na_gtfs as gtfs   # noqa: E402
import na_lines as lines  # noqa: E402


def pattern(stations, weight, trips):
    p = lines.Pattern(stations, None, 'sample-trip')
    p.weight = weight
    p.trips = trips
    return p


class FakeFeed:
    """Duck-types ``na_gtfs.Feed`` far enough for ``rows()``-only methods."""

    def __init__(self, tables):
        self.tables = tables

    def rows(self, name):
        return list(self.tables.get(name, ()))


def calendar_row(service_id, days=None):
    days = days or ()
    row = {d: '0' for d in ('monday', 'tuesday', 'wednesday', 'thursday',
                             'friday', 'saturday', 'sunday')}
    row['service_id'] = service_id
    for d in days:
        row[d] = '1'
    return row


class ServiceWeightsNeverOperatingTests(unittest.TestCase):
    def test_zero_day_calendar_row_weighs_zero(self):
        feed = FakeFeed({'calendar.txt': [calendar_row('canonical')]})

        weights = gtfs.Feed.service_weights(feed)

        self.assertEqual(weights['canonical'], 0)

    def test_zero_day_row_with_a_calendar_dates_addition_earns_real_weight(self):
        feed = FakeFeed({
            'calendar.txt': [calendar_row('special-event')],
            'calendar_dates.txt': [
                {'service_id': 'special-event', 'date': '20260101',
                 'exception_type': '1'},
                {'service_id': 'special-event', 'date': '20260102',
                 'exception_type': '1'},
            ],
        })

        weights = gtfs.Feed.service_weights(feed)

        self.assertGreaterEqual(weights['special-event'], 1)

    def test_build_patterns_skips_zero_weight_trips_and_reports_the_count(self):
        weights = {'never': 0, 'weekday': 5}
        trips = [
            {'trip_id': 't-canonical', 'service_id': 'never'},
            {'trip_id': 't-real', 'service_id': 'weekday'},
        ]
        sequences = {
            't-canonical': ['A', 'B', 'C', 'D'],
            't-real': ['A', 'B'],
        }
        stops = {s: {'stop_id': s} for s in ('A', 'B', 'C', 'D')}
        dropped = {}

        patterns = lines.build_patterns(
            'R', trips, sequences, stops, lambda row: row['stop_id'], weights,
            dropped=dropped)

        self.assertEqual(dropped['never_operating_trips'], 1)
        self.assertEqual(len(patterns), 1)
        self.assertEqual(patterns[0].stations, ['A', 'B'])


class RoutePatternTypicalityTests(unittest.TestCase):
    def test_reads_typicality_by_pattern_id(self):
        feed = FakeFeed({'route_patterns.txt': [
            {'route_pattern_id': 'Green-B-812-0', 'route_pattern_typicality': '1'},
            {'route_pattern_id': 'Green-B-816-0', 'route_pattern_typicality': '3'},
        ]})

        typicality = gtfs.Feed.route_pattern_typicality(feed)

        self.assertEqual(typicality, {'Green-B-812-0': 1, 'Green-B-816-0': 3})

    def test_feed_without_the_table_returns_empty(self):
        feed = FakeFeed({})

        self.assertEqual(gtfs.Feed.route_pattern_typicality(feed), {})


class RoutePatternNamesTests(unittest.TestCase):
    def test_reads_names_by_pattern_id(self):
        feed = FakeFeed({'route_patterns.txt': [
            {'route_pattern_id': 'CR-Providence-8344b9b3-0',
             'route_pattern_name': 'South Station - Stoughton via Fairmount'},
            {'route_pattern_id': 'CR-Providence-C1-0',
             'route_pattern_name': 'South Station - Wickford Junction via Back Bay'},
        ]})

        names = gtfs.Feed.route_pattern_names(feed)

        self.assertEqual(names, {
            'CR-Providence-8344b9b3-0':
                'South Station - Stoughton via Fairmount',
            'CR-Providence-C1-0':
                'South Station - Wickford Junction via Back Bay',
        })

    def test_feed_without_the_table_returns_empty(self):
        feed = FakeFeed({})

        self.assertEqual(gtfs.Feed.route_pattern_names(feed), {})


class LeadInSpurLoopTests(unittest.TestCase):
    """Portland Streetcar A Loop shape: a lead-in stop before the loop."""

    def test_lead_in_spur_becomes_trunk_loop_only_when_too_short_to_keep(self):
        """A two-station lead-in (the Portland A Loop's own shape) is a
        pull-out move, not a branch: the trunk still splits into the loop,
        but no branch is emitted for the spur."""
        patterns = [
            pattern(['X', 'A', 'B', 'C', 'D'], 1.0, 1),
            pattern(['A', 'B', 'C', 'D', 'A'], 10.0, 10),
        ]

        selection = lines.select_lines(patterns, lead_in_loop=True)

        self.assertEqual(len(selection), 1)
        trunk = selection[0]
        self.assertEqual(trunk[0], '')
        self.assertEqual(trunk[1], ['A', 'B', 'C', 'D'])
        self.assertTrue(trunk[3])

    def test_three_station_lead_in_spur_is_kept_as_a_branch(self):
        patterns = [
            pattern(['W', 'X', 'A', 'B', 'C', 'D'], 1.0, 1),
            pattern(['A', 'B', 'C', 'D', 'A'], 10.0, 10),
        ]

        selection = lines.select_lines(patterns, lead_in_loop=True)

        trunk = next(row for row in selection if row[0] == '')
        self.assertEqual(trunk[1], ['A', 'B', 'C', 'D'])
        self.assertTrue(trunk[3])
        branch = next((row for row in selection if row[0] != ''), None)
        self.assertIsNotNone(branch)
        self.assertEqual(branch[1], ['W', 'X', 'A'])
        self.assertFalse(branch[3])

    def test_split_does_not_fire_without_the_lead_in_loop_knob(self):
        """Without ``lead_in_loop=True`` the split must not run at all.

        The cut edge lands on ``D -> A`` (an interior station), not on
        ``D -> trunk[0]`` (``X``), so the trunk stays the ungated
        longest_path answer and is reported as an open line — exactly the
        fallback the module's own docstring describes for a route that has
        not opted in.
        """
        patterns = [
            pattern(['X', 'A', 'B', 'C', 'D'], 1.0, 1),
            pattern(['A', 'B', 'C', 'D', 'A'], 10.0, 10),
        ]

        selection = lines.select_lines(patterns)

        self.assertEqual(len(selection), 1)
        suffix, stations, _, is_loop = selection[0]
        self.assertEqual(suffix, '')
        self.assertEqual(stations, ['X', 'A', 'B', 'C', 'D'])
        self.assertFalse(is_loop)

    def test_lead_in_split_reports_when_it_fires(self):
        patterns = [
            pattern(['X', 'A', 'B', 'C', 'D'], 1.0, 1),
            pattern(['A', 'B', 'C', 'D', 'A'], 10.0, 10),
        ]
        report = {}

        lines.select_lines(patterns, lead_in_loop=True, report=report)

        self.assertEqual(report['lead_in'],
                         {'spur': ['X', 'A'], 'stations': 2, 'kept': False})

    def test_split_bug_does_not_reappear_as_a_spurious_branch(self):
        """Regression: the split must not discard the full-trunk coverage.

        Resetting ``covered``/``position`` to the shortened trunk after the
        split let an edge from the spur station to a non-adjacent loop
        station (here ``X -> B``, published by a third pattern) reappear in
        ``remaining`` and grow into a bogus ``-b1 ['X', 'B']`` branch. The
        two-station spur ``['X', 'A']`` is itself too short to keep (a
        pull-out move, not a branch), so the correct answer is the loop
        trunk alone — with no branch at all, and in particular none for the
        ``X -> B`` edge.
        """
        patterns = [
            pattern(['X', 'A', 'B', 'C', 'D'], 1.0, 1),
            pattern(['A', 'B', 'C', 'D', 'A'], 10.0, 10),
            pattern(['X', 'B', 'C', 'D'], 2.0, 2),
        ]

        selection = lines.select_lines(patterns, lead_in_loop=True)

        trunk = next(row for row in selection if row[0] == '')
        self.assertEqual(trunk[1], ['A', 'B', 'C', 'D'])
        self.assertTrue(trunk[3])
        branches = [row for row in selection if row[0] != '']
        self.assertEqual(len(branches), 0)

    def test_short_lead_in_spur_is_dropped_below_min_branch_stations(self):
        patterns = [
            pattern(['X', 'A', 'B', 'C', 'D'], 1.0, 1),
            pattern(['A', 'B', 'C', 'D', 'A'], 10.0, 10),
        ]

        selection = lines.select_lines(
            patterns, min_branch_stations=3, lead_in_loop=True)

        self.assertEqual(len(selection), 1)
        trunk = selection[0]
        self.assertEqual(trunk[1], ['A', 'B', 'C', 'D'])
        self.assertTrue(trunk[3])

    def test_two_qualifying_cut_edges_the_smaller_k_wins(self):
        """Two cut edges can each land on an interior trunk station.

        Here the trunk is ``A, B, C, D, E, F`` and two back edges close onto
        it — ``F -> C`` (``k=2``) and ``F -> D`` (``k=3``) — because two
        separate low-weight patterns each publish a short-turn back to an
        earlier trunk station. The smaller ``k`` (the one closest to the
        front of the trunk) must win, keeping the larger loop ``C, D, E,
        F`` and the shorter lead-in ``A, B, C`` rather than shrinking the
        loop to fit the other, unrelated cut. The lead-in is three stations
        so it is kept as a branch, letting this test still observe which
        cut edge won.
        """
        patterns = [
            pattern(['A', 'B', 'C', 'D', 'E', 'F'], 10.0, 10),
            pattern(['C', 'D', 'E', 'F', 'C'], 1.0, 1),
            pattern(['D', 'E', 'F', 'D'], 2.0, 2),
        ]

        selection = lines.select_lines(patterns, lead_in_loop=True)

        trunk = next(row for row in selection if row[0] == '')
        self.assertEqual(trunk[1], ['C', 'D', 'E', 'F'])
        self.assertTrue(trunk[3])
        branches = [row for row in selection if row[0] != '']
        self.assertEqual(len(branches), 1)
        self.assertEqual(branches[0][1], ['A', 'B', 'C'])

    def test_plain_loop_still_returns_loop_true(self):
        patterns = [pattern(['A', 'B', 'C', 'D', 'A'], 10.0, 10)]

        selection = lines.select_lines(patterns)

        self.assertEqual(len(selection), 1)
        suffix, stations, _, is_loop = selection[0]
        self.assertEqual(suffix, '')
        self.assertEqual(stations, ['A', 'B', 'C', 'D'])
        self.assertTrue(is_loop)

    def test_open_line_stays_open(self):
        patterns = [pattern(['A', 'B', 'C', 'D'], 10.0, 10)]

        selection = lines.select_lines(patterns)

        self.assertEqual(len(selection), 1)
        _, stations, _, is_loop = selection[0]
        self.assertEqual(stations, ['A', 'B', 'C', 'D'])
        self.assertFalse(is_loop)


def make_feed():
    feed = builder.FeedBuild.__new__(builder.FeedBuild)
    feed.slug = 'testfeed'
    feed.report = {'notes': []}
    return feed


def stop_row(stop_id, parent_station='', location_type=''):
    return {'stop_id': stop_id, 'parent_station': parent_station,
            'location_type': location_type, 'stop_name': stop_id}


TWO_EVIDENCE = ['some evidence', 'a second, independent source']


class ExcludeStopIdsByRouteIdTests(unittest.TestCase):
    def setUp(self):
        self.feed = make_feed()
        self.parent = lambda row: gtfs.parent_of(row, self.stops)
        self.stops = {
            'A': stop_row('A'),
            'PASS': stop_row('PASS'),
            'B': stop_row('B'),
        }
        self.route_trips = [
            {'trip_id': 't1', 'route_id': 'R'},
            {'trip_id': 't2', 'route_id': 'R'},
        ]
        self.sequences = {
            't1': ['A', 'PASS', 'B'],
            't2': ['A', 'B'],
        }

    def test_removes_the_station_from_the_built_pattern(self):
        self.feed.entry = {
            'excludeStopIdsByRouteId': {'R': ['PASS']},
            'excludeStopEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }

        filtered = self.feed.apply_excluded_stops(
            'R', ['R'], self.route_trips, self.sequences, self.stops,
            self.parent)

        self.assertEqual(filtered['t1'], ['A', 'B'])
        self.assertEqual(filtered['t2'], ['A', 'B'])
        self.assertTrue(any('PASS' in n for n in self.feed.report['notes']))

    def test_missing_evidence_raises(self):
        self.feed.entry = {'excludeStopIdsByRouteId': {'R': ['PASS']}}

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_stops(
                'R', ['R'], self.route_trips, self.sequences, self.stops,
                self.parent)

    def test_single_evidence_record_raises(self):
        self.feed.entry = {
            'excludeStopIdsByRouteId': {'R': ['PASS']},
            'excludeStopEvidenceByRouteId': {'R': ['only one source']},
        }

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_stops(
                'R', ['R'], self.route_trips, self.sequences, self.stops,
                self.parent)

    def test_unknown_stop_id_raises(self):
        self.feed.entry = {
            'excludeStopIdsByRouteId': {'R': ['NOPE']},
            'excludeStopEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_stops(
                'R', ['R'], self.route_trips, self.sequences, self.stops,
                self.parent)

    def test_parent_station_id_is_accepted(self):
        stops = {
            'A': stop_row('A'),
            'STATION': stop_row('STATION', location_type='1'),
            'PASS': stop_row('PASS', parent_station='STATION'),
            'B': stop_row('B'),
        }
        parent = lambda row: gtfs.parent_of(row, stops)
        self.feed.entry = {
            'excludeStopIdsByRouteId': {'R': ['STATION']},
            'excludeStopEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        sequences = {
            't1': ['A', 'PASS', 'B'],
            't2': ['A', 'B'],
        }

        filtered = self.feed.apply_excluded_stops(
            'R', ['R'], self.route_trips, sequences, stops, parent)

        self.assertEqual(filtered['t1'], ['A', 'B'])

    def test_rule_scoped_to_its_own_route_id_not_the_whole_merged_group(self):
        """A stop only a sibling route in the merge visits is stale for R."""
        route_trips = [
            {'trip_id': 't1', 'route_id': 'R'},
            {'trip_id': 't2', 'route_id': 'R'},
            {'trip_id': 'sibling-1', 'route_id': 'SIBLING'},
        ]
        sequences = {
            't1': ['A', 'B'],
            't2': ['A', 'B'],
            'sibling-1': ['A', 'PASS', 'B'],
        }
        self.feed.entry = {
            'excludeStopIdsByRouteId': {'R': ['PASS']},
            'excludeStopEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_stops(
                'R', ['R', 'SIBLING'], route_trips, sequences, self.stops,
                self.parent)

    def test_never_operating_trip_does_not_count_as_visiting(self):
        """A stop only a zero-weight service visits is stale, not real."""
        route_trips = [
            {'trip_id': 't1', 'route_id': 'R', 'service_id': 'never'},
            {'trip_id': 't2', 'route_id': 'R', 'service_id': 'weekday'},
        ]
        sequences = {
            't1': ['A', 'PASS', 'B'],
            't2': ['A', 'B'],
        }
        weights = {'never': 0, 'weekday': 5}
        self.feed.entry = {
            'excludeStopIdsByRouteId': {'R': ['PASS']},
            'excludeStopEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_stops(
                'R', ['R'], route_trips, sequences, self.stops, self.parent,
                weights)


class ExcludeTripsByRouteIdTests(unittest.TestCase):
    def setUp(self):
        self.feed = make_feed()

    def test_typicality_filter_drops_the_atypical_pattern(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {'R': {'routePatternTypicalityAtLeast': 3}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [
            {'trip_id': 't1', 'route_id': 'R', 'route_pattern_id': 'typical-1'},
            {'trip_id': 't2', 'route_id': 'R', 'route_pattern_id': 'atypical-3'},
        ]
        typicality = {'typical-1': 1, 'atypical-3': 3}

        kept = self.feed.apply_excluded_trips('R', ['R'], route_trips, typicality)

        self.assertEqual([t['trip_id'] for t in kept], ['t1'])

    def test_headsign_pattern_filter(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {'R': {'headsignPattern': 'via Fairmount'}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [
            {'trip_id': 't1', 'route_id': 'R',
             'trip_headsign': 'South Station via Back Bay'},
            {'trip_id': 't2', 'route_id': 'R',
             'trip_headsign': 'South Station via Fairmount'},
        ]

        kept = self.feed.apply_excluded_trips('R', ['R'], route_trips, {})

        self.assertEqual([t['trip_id'] for t in kept], ['t1'])

    def test_route_pattern_name_pattern_filter(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {
                'R': {'routePatternNamePattern': 'via Fairmount'}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [
            {'trip_id': 't1', 'route_id': 'R', 'route_pattern_id': 'back-bay',
             'trip_headsign': 'Stoughton'},
            {'trip_id': 't2', 'route_id': 'R', 'route_pattern_id': 'fairmount',
             'trip_headsign': 'Stoughton'},
        ]
        pattern_names = {
            'back-bay': 'South Station - Stoughton via Back Bay',
            'fairmount': 'South Station - Stoughton via Fairmount',
        }

        kept = self.feed.apply_excluded_trips(
            'R', ['R'], route_trips, {}, pattern_names)

        self.assertEqual([t['trip_id'] for t in kept], ['t1'])

    def test_route_pattern_name_pattern_matching_no_trips_raises(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {
                'R': {'routePatternNamePattern': 'via Nowhere'}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [{'trip_id': 't1', 'route_id': 'R',
                        'route_pattern_id': 'p1'}]
        pattern_names = {'p1': 'South Station - Stoughton via Back Bay'}

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_trips(
                'R', ['R'], route_trips, {}, pattern_names)

    def test_route_pattern_name_pattern_without_route_patterns_table_raises(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {
                'R': {'routePatternNamePattern': 'via Fairmount'}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [{'trip_id': 't1', 'route_id': 'R',
                        'route_pattern_id': 'p1'}]

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_trips('R', ['R'], route_trips, {}, {})

    def test_typicality_knob_without_route_patterns_table_raises(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {'R': {'routePatternTypicalityAtLeast': 3}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [{'trip_id': 't1', 'route_id': 'R',
                        'route_pattern_id': 'p1'}]

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_trips('R', ['R'], route_trips, {})

    def test_single_evidence_record_raises(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {'R': {'headsignPattern': 'via Fairmount'}},
            'excludeTripsEvidenceByRouteId': {'R': ['only one source']},
        }
        route_trips = [{'trip_id': 't1', 'route_id': 'R',
                        'trip_headsign': 'South Station via Fairmount'}]

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_trips('R', ['R'], route_trips, {})

    def test_headsign_pattern_matching_no_trips_raises(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {'R': {'headsignPattern': 'via Nowhere'}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [{'trip_id': 't1', 'route_id': 'R',
                        'trip_headsign': 'South Station via Back Bay'}]

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_trips('R', ['R'], route_trips, {})

    def test_route_pattern_ids_matching_no_trips_raises(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {'R': {'routePatternIds': ['nope']}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [{'trip_id': 't1', 'route_id': 'R',
                        'route_pattern_id': 'p1'}]

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_trips('R', ['R'], route_trips, {})

    def test_typicality_matching_no_trips_raises(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {'R': {'routePatternTypicalityAtLeast': 3}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [{'trip_id': 't1', 'route_id': 'R',
                        'route_pattern_id': 'typical-1'}]
        typicality = {'typical-1': 1}

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_trips('R', ['R'], route_trips, typicality)

    def test_typicality_knob_without_any_route_pattern_id_raises(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {'R': {'routePatternTypicalityAtLeast': 3}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [{'trip_id': 't1', 'route_id': 'R'}]
        typicality = {'some-other-pattern': 1}

        with self.assertRaises(ValueError):
            self.feed.apply_excluded_trips('R', ['R'], route_trips, typicality)

    def test_rule_scoped_to_its_own_route_id_not_the_whole_merged_group(self):
        self.feed.entry = {
            'excludeTripsByRouteId': {'R': {'headsignPattern': 'via Fairmount'}},
            'excludeTripsEvidenceByRouteId': {'R': TWO_EVIDENCE},
        }
        route_trips = [
            {'trip_id': 't1', 'route_id': 'R',
             'trip_headsign': 'South Station via Fairmount'},
            {'trip_id': 'sibling-1', 'route_id': 'SIBLING',
             'trip_headsign': 'South Station via Fairmount'},
        ]

        kept = self.feed.apply_excluded_trips(
            'R', ['R', 'SIBLING'], route_trips, {})

        self.assertEqual([t['trip_id'] for t in kept], ['sibling-1'])


if __name__ == '__main__':
    unittest.main()
