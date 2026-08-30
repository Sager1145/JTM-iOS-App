import importlib.util
import hashlib
import json
import os
import tempfile
import unittest
from types import SimpleNamespace


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'build-north-america-rail-package.py'))
SPEC = importlib.util.spec_from_file_location('na_package_builder', SCRIPT)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class RouteGroupingTests(unittest.TestCase):
    def test_missing_official_colour_has_no_silent_grey_fallback(self):
        with self.assertRaisesRegex(ValueError, 'operator-published'):
            builder.display_colours(None)

    def test_operator_colour_is_preserved_as_reference(self):
        _, _, reference = builder.display_colours('009B3A')
        self.assertEqual(reference, '#009b3a')

    def test_arrival_and_departure_are_one_physical_station_name(self):
        self.assertEqual(
            builder.normalise_station_name('PENN Station Light RAIL Departure'),
            builder.normalise_station_name('PENN Station Light RAIL Arrival'))

    def test_parenthesized_in_and_out_are_one_physical_station_name(self):
        self.assertEqual(
            builder.normalise_station_name('Canal at Galvez (In)'),
            builder.normalise_station_name('Canal at Galvez (Out)'))

    def test_feed_can_declare_directional_platform_identity(self):
        stops = {
            'north': {'stop_id': 'north', 'stop_name': 'Union toward Finch',
                      'stop_lon': '0', 'stop_lat': '0'},
            'south': {'stop_id': 'south', 'stop_name': 'Union toward Vaughan',
                      'stop_lon': '0.001', 'stop_lat': '0'},
        }

        parents = builder.canonical_feed_parents(
            stops, [['south', 'north']])

        self.assertEqual(parents['south'], 'south')
        self.assertEqual(parents['north'], 'south')

    def test_feed_can_merge_differently_named_opposite_platforms_by_distance(self):
        stops = {
            'north': {'stop_id': 'north', 'stop_name': 'Canal at N. Broad',
                      'stop_lon': '0', 'stop_lat': '0'},
            'south': {'stop_id': 'south', 'stop_name': 'Canal at S. Broad',
                      'stop_lon': '0.0001', 'stop_lat': '0'},
        }

        separate = builder.canonical_feed_parents(stops)
        merged = builder.canonical_feed_parents(
            stops, coordinate_near_m=60.0)

        self.assertNotEqual(separate['north'], separate['south'])
        self.assertEqual(merged['north'], merged['south'])

    def test_declared_station_parents_are_not_merged_by_equal_name_and_distance(self):
        stops = {
            '132': {'stop_id': '132', 'stop_name': '14 St',
                    'stop_lon': '-74.000201', 'stop_lat': '40.737826',
                    'location_type': '1'},
            'A31': {'stop_id': 'A31', 'stop_name': '14 St',
                    'stop_lon': '-74.001690', 'stop_lat': '40.740893',
                    'location_type': '1'},
        }

        parents = builder.canonical_feed_parents(stops)

        self.assertEqual(parents, {'132': '132', 'A31': 'A31'})

    def test_unparented_equal_names_over_200m_are_not_guessed_as_one_station(self):
        stops = {
            'near': {'stop_id': 'near', 'stop_name': 'Gerrard at Coxwell',
                     'stop_lon': '-79.319529', 'stop_lat': '43.672761'},
            'far': {'stop_id': 'far', 'stop_name': 'Gerrard at Coxwell',
                    'stop_lon': '-79.319842', 'stop_lat': '43.675659'},
        }

        conservative = builder.canonical_feed_parents(stops)
        explicitly_reviewed = builder.canonical_feed_parents(
            stops, near_m=400.0)

        self.assertNotEqual(conservative['near'], conservative['far'])
        self.assertEqual(explicitly_reviewed['near'], explicitly_reviewed['far'])

    def test_name_only_station_cluster_cannot_exceed_reviewed_diameter(self):
        stops = {
            'centre': {'stop_id': 'centre', 'stop_name': 'Example',
                       'stop_lon': '0', 'stop_lat': '0'},
            'east': {'stop_id': 'east', 'stop_name': 'Example',
                     'stop_lon': '0.0016', 'stop_lat': '0'},
            'west': {'stop_id': 'west', 'stop_name': 'Example',
                     'stop_lon': '-0.0016', 'stop_lat': '0'},
        }

        parents = builder.canonical_feed_parents(stops)

        self.assertEqual(parents['centre'], parents['east'])
        self.assertNotEqual(parents['centre'], parents['west'])

    def test_feed_can_use_an_official_station_identity_field(self):
        stops = {
            'coaster': {
                'stop_id': 'coaster', 'stop_name': 'Oceanside Transit Center',
                'stop_lon': '-117.378350', 'stop_lat': '33.190875',
                'reference_place': 'octc',
            },
            'sprinter': {
                'stop_id': 'sprinter', 'stop_name': 'Oceanside Transit Center',
                'stop_lon': '-117.376487', 'stop_lat': '33.188560',
                'reference_place': 'octc',
            },
            'other': {
                'stop_id': 'other', 'stop_name': 'Oceanside Transit Center',
                'stop_lon': '-117.376500', 'stop_lat': '33.188570',
                'reference_place': 'not-octc',
            },
        }

        parents = builder.canonical_feed_parents(
            stops, identity_field='reference_place')

        self.assertEqual(parents['coaster'], parents['sprinter'])
        self.assertNotEqual(parents['coaster'], parents['other'])

    def test_declared_official_station_identity_field_must_exist(self):
        stops = {
            'only': {'stop_id': 'only', 'stop_name': 'Only',
                     'stop_lon': '0', 'stop_lat': '0'},
        }

        with self.assertRaisesRegex(ValueError, 'absent or empty'):
            builder.canonical_feed_parents(
                stops, identity_field='reference_place')

    def test_only_exact_via_thompson_turnaround_triple_is_approved(self):
        # Long legs arranged as a near U-turn at the middle stop.
        points = [[-97.0, 55.0], [-97.20, 55.10], [-97.01, 55.01]]

        blocked, approved = builder.partition_station_order_reversals(
            points, ['165', '503', '290'], [['165', '503', '290']])
        wrong_neighbour_blocked, wrong_neighbour_approved = (
            builder.partition_station_order_reversals(
                points, ['999', '503', '290'], [['165', '503', '290']]))

        self.assertEqual(blocked, [])
        self.assertEqual(approved, [1])
        self.assertEqual(wrong_neighbour_blocked, [1])
        self.assertEqual(wrong_neighbour_approved, [])

    def test_unlisted_long_distance_reversal_still_fails(self):
        points = [[-74.0, 41.0], [-73.0, 42.0], [-73.99, 41.01]]

        blocked, approved = builder.partition_station_order_reversals(
            points, ['croton', 'grand-central', 'beacon'], [])

        self.assertEqual(blocked, [1])
        self.assertEqual(approved, [])

    def test_mta_six_same_name_false_merges_keep_distinct_official_parents(self):
        # These are the six false station-code merges found in the MTA-only
        # package. Coordinates and parent ids are from MTA's official GTFS.
        cases = [
            [('132', '14 St', -74.000201, 40.737826),
             ('A31', '14 St', -74.001690, 40.740893)],
            [('130', '23 St', -73.995657, 40.744081),
             ('A30', '23 St', -73.998041, 40.745906),
             ('D18', '23 St', -73.992821, 40.742878)],
            [('128', '34 St-Penn Station', -73.991057, 40.750373),
             ('A28', '34 St-Penn Station', -73.993391, 40.752287)],
            [('126', '50 St', -73.983849, 40.761728),
             ('A25', '50 St', -73.985984, 40.762456)],
            [('135', 'Canal St', -74.006277, 40.722854),
             ('A34', 'Canal St', -74.005229, 40.720824)],
            [('137', 'Chambers St', -74.009266, 40.715478),
             ('A36', 'Chambers St', -74.008585, 40.714111)],
        ]
        line = {'feed': 'metropolitan-transit-authori'}

        for stations in cases:
            with self.subTest(name=stations[0][1]):
                entries = [
                    {'feedStop': sid, 'identity': sid, 'name': name,
                     'point': [lon, lat], 'line': line}
                    for sid, name, lon, lat in stations
                ]
                self.assertEqual(len(builder.group_stations(entries)),
                                 len(stations))

    def test_cross_feed_alias_rule_is_unchanged(self):
        entries = [
            {'feedStop': 'amtrak-bal', 'identity': 'amtrak-bal',
             'name': 'Baltimore Penn Station',
             'point': [-76.6157, 39.3073],
             'line': {'feed': 'amtrak'}},
            {'feedStop': 'mta-penn', 'identity': 'mta-penn',
             'name': 'Penn-North',
             'point': [-76.6156, 39.3074],
             'line': {'feed': 'maryland-transit-administrat'}},
        ]

        self.assertEqual(len(builder.group_stations(entries)), 1)

    def test_mta_six_official_transfer_complexes_share_identity_not_anchors(self):
        # Each row is one connected component in MTA's official transfers.txt.
        cases = [
            [('112', '168 St-Washington Hts', -73.940133, 40.840556),
             ('A09', '168 St', -73.939561, 40.840719)],
            [('127', 'Times Sq-42 St', -73.987495, 40.755290),
             ('902', 'Times Sq-42 St', -73.986229, 40.755983),
             ('A27', '42 St-Port Authority Bus Terminal', -73.989735, 40.757308)],
            [('132', '14 St', -74.000201, 40.737826),
             ('D19', '14 St', -73.996209, 40.738228),
             ('L02', '6 Av', -73.996786, 40.737335)],
            [('719', 'Court Sq', -73.945264, 40.747023),
             ('G22', 'Court Sq', -73.943832, 40.746554)],
            [('A31', '14 St', -74.001690, 40.740893),
             ('L01', '8 Av', -74.002578, 40.739777)],
            [('G29', 'Metropolitan Av', -73.951418, 40.712792),
             ('L10', 'Lorimer St', -73.950275, 40.714063)],
        ]
        line = {'feed': 'metropolitan-transit-authori'}

        for stations in cases:
            with self.subTest(name=stations[0][1]):
                identity = stations[0][0]
                entries = [
                    {'feedStop': sid, 'identity': identity, 'name': name,
                     'point': [lon, lat], 'line': line}
                    for sid, name, lon, lat in stations
                ]
                before = [list(entry['point']) for entry in entries]
                groups = builder.group_stations(entries)
                self.assertEqual(len(groups), 1)
                self.assertEqual([entry['point'] for entry in entries], before)

    def test_official_transfer_components_resolve_platform_parents(self):
        stops = {
            '132': {'stop_id': '132', 'location_type': '1'},
            '132N': {'stop_id': '132N', 'parent_station': '132'},
            'D19': {'stop_id': 'D19', 'location_type': '1'},
            'L02': {'stop_id': 'L02', 'location_type': '1'},
            'A31': {'stop_id': 'A31', 'location_type': '1'},
            'L01': {'stop_id': 'L01', 'location_type': '1'},
        }
        transfers = [
            {'from_stop_id': '132N', 'to_stop_id': 'D19',
             'transfer_type': '2'},
            {'from_stop_id': 'D19', 'to_stop_id': 'L02',
             'transfer_type': '2'},
            {'from_stop_id': 'A31', 'to_stop_id': 'L01',
             'transfer_type': '2'},
            {'from_stop_id': '132', 'to_stop_id': 'A31',
             'transfer_type': '3'},
        ]

        complexes = builder.official_transfer_complexes(stops, transfers)

        self.assertEqual(complexes['132'], complexes['D19'])
        self.assertEqual(complexes['132'], complexes['L02'])
        self.assertEqual(complexes['A31'], complexes['L01'])
        self.assertNotEqual(complexes['132'], complexes['A31'])

    def test_registry_can_preserve_official_route_ids(self):
        routes = [
            {'route_id': '4', 'route_short_name': '4',
             'route_long_name': 'Lexington Avenue Express', 'route_color': '00933C'},
            {'route_id': '5', 'route_short_name': '5',
             'route_long_name': 'Lexington Avenue Express', 'route_color': '00933C'},
        ]
        trips = {
            '4': [{'trip_id': 'four'}],
            '5': [{'trip_id': 'five'}],
        }
        sequences = {'four': ['a', 'b'], 'five': ['a', 'b']}
        stops = {'a': {'stop_id': 'a'}, 'b': {'stop_id': 'b'}}
        parent = lambda row: row['stop_id']

        merged = builder.group_routes(
            routes, trips, sequences, stops, parent, {},
            preserve_route_ids=False)
        preserved = builder.group_routes(
            routes, trips, sequences, stops, parent, {},
            preserve_route_ids=True)

        self.assertEqual(len(merged), 1)
        self.assertEqual(len(preserved), 2)
        self.assertEqual({g['routes'][0]['route_id'] for g in preserved}, {'4', '5'})

    def test_explicit_period_ids_merge_while_other_route_ids_are_preserved(self):
        routes = [
            {'route_id': 'old-east', 'route_long_name': 'Lakeshore East'},
            {'route_id': 'new-east', 'route_long_name': 'Lakeshore East'},
            {'route_id': 'west', 'route_long_name': 'Lakeshore West'},
        ]
        trips = {key: [{'trip_id': key}] for key in
                 ('old-east', 'new-east', 'west')}
        sequences = {key: ['union', key] for key in trips}
        stops = {key: {'stop_id': key} for key in
                 ('union', 'old-east', 'new-east', 'west')}

        groups = builder.group_routes(
            routes, trips, sequences, stops,
            lambda row: row['stop_id'], {}, preserve_route_ids=True,
            merge_route_id_groups=[['old-east', 'new-east']])

        self.assertEqual(len(groups), 2)
        self.assertEqual(
            {tuple(route['route_id'] for route in group['routes'])
             for group in groups},
            {('old-east', 'new-east'), ('west',)})

    def test_exact_official_gis_colour_replaces_blank_gtfs_colour(self):
        entry = {
            'officialColorByRouteId': {'201': 'EC3001'},
            'officialColorSourceByRouteId': {'201': 'official GIS palette'},
        }

        colour, source = builder.published_route_colour(
            entry, {'route_color': ''}, '201')

        self.assertEqual(colour, 'EC3001')
        self.assertEqual(source, 'official GIS palette')

    def test_declared_official_gis_colour_without_source_fails_closed(self):
        colour, source = builder.published_route_colour(
            {'officialColorByRouteId': {'201': 'EC3001'}},
            {'route_color': '123456'}, '201')

        self.assertEqual(colour, 'EC3001')
        self.assertIsNone(source)

    def test_exact_unverified_route_is_removed_fail_closed(self):
        routes = [{'route_id': 'RED'}, {'route_id': 'BLUE'}]

        kept, refused = builder.partition_fail_closed_routes(routes, {
            'blockedRouteIds': {
                'RED': 'independent operator/government GIS unavailable',
            },
        })

        self.assertEqual([row['route_id'] for row in kept], ['BLUE'])
        self.assertEqual(refused[0]['route'], 'RED')
        self.assertIn('fail-closed', refused[0]['why'])

    def test_same_colour_shared_corridor_does_not_merge_distinct_names(self):
        routes = [
            {'route_id': '5', 'route_short_name': 'MNBN',
             'route_long_name': 'Main/Bergen County Line',
             'route_color': 'FFD411'},
            {'route_id': '6', 'route_short_name': 'MNBNP',
             'route_long_name': 'Port Jervis Line', 'route_color': 'FFD411'},
        ]
        trips = {'5': [{'trip_id': 'main'}], '6': [{'trip_id': 'port'}]}
        sequences = {
            'main': ['a', 'b', 'c', 'd'],
            'port': ['a', 'b', 'c', 'e'],
        }
        stops = {key: {'stop_id': key} for key in 'abcde'}
        parent = lambda row: row['stop_id']

        safe = builder.group_routes(
            routes, trips, sequences, stops, parent, {})
        explicitly_directional = builder.group_routes(
            routes, trips, sequences, stops, parent, {},
            merge_route_id_groups=[['5', '6']])

        self.assertEqual(len(safe), 2)
        self.assertEqual(len(explicitly_directional), 1)

    def test_same_generic_name_does_not_merge_different_agencies(self):
        routes = [
            {'route_id': 'sle', 'agency_id': 'shore',
             'route_long_name': 'Commuter Rail'},
            {'route_id': 'marc', 'agency_id': 'marc',
             'route_long_name': 'Commuter Rail'},
        ]
        trips = {'sle': [{'trip_id': 's'}], 'marc': [{'trip_id': 'm'}]}
        sequences = {'s': ['a', 'b'], 'm': ['a', 'c']}
        stops = {key: {'stop_id': key} for key in 'abc'}
        parent = lambda row: row['stop_id']

        groups = builder.group_routes(
            routes, trips, sequences, stops, parent, {})

        self.assertEqual(len(groups), 2)

    def test_explicit_cross_agency_group_can_join_published_subroute(self):
        routes = [
            {'route_id': 'full', 'agency_id': 'amtrak',
             'route_long_name': 'Maple Leaf'},
            {'route_id': 'canada', 'agency_id': 'via',
             'route_long_name': 'Maple Leaf'},
        ]
        trips = {'full': [{'trip_id': 'f'}], 'canada': [{'trip_id': 'c'}]}
        sequences = {'f': ['a', 'b', 'c', 'd'], 'c': ['c', 'd']}
        stops = {key: {'stop_id': key} for key in 'abcd'}
        parent = lambda row: row['stop_id']

        groups = builder.group_routes(
            routes, trips, sequences, stops, parent, {},
            merge_route_id_groups=[['full', 'canada']])

        self.assertEqual(len(groups), 1)

    def test_subset_dedup_respects_preserved_source_route(self):
        long = {'lineId': 'nr', 'name': 'Broadway Local',
                'sourceRouteId': 'N', 'rank': 1,
                'stationIds': ['a', 'b', 'c']}
        short = {'lineId': 'w', 'name': 'Broadway Local',
                 'sourceRouteId': 'W', 'rank': 1,
                 'stationIds': ['a', 'b']}

        ordinary = builder.drop_subsets([long, short])
        preserved = builder.drop_subsets(
            [long, short], preserve_route_ids=True)

        self.assertEqual([line['lineId'] for line in ordinary], ['nr'])
        self.assertEqual({line['lineId'] for line in preserved}, {'nr', 'w'})

    def test_trusted_shape_fallback_requires_all_stations_in_order(self):
        patterns = [SimpleNamespace(shape_ids={'official': 10.0})]
        shapes = {'official': [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]}

        shape_id, shape = builder.trusted_shape_fallback(
            [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]],
            patterns, shapes, 100.0)
        rejected = builder.trusted_shape_fallback(
            [[0.0, 0.0], [0.01, 0.02], [0.02, 0.0]],
            patterns, shapes, 100.0)

        self.assertEqual(shape_id, 'official')
        self.assertEqual(shape, shapes['official'])
        self.assertEqual(rejected, (None, None))


class OsmSourceGateTests(unittest.TestCase):
    def test_known_wrong_station_order_is_refused_not_guessed(self):
        report = {'dropped': []}
        valid = {'relation': 1, 'name': 'Verified', 'operator': 'Railway'}
        malformed = {
            'relation': 9599901,
            'name': 'Rainforest to Gold Rush',
            'operator': 'Rocky Mountaineer',
        }

        kept = builder.refuse_known_invalid([valid, malformed], report)

        self.assertEqual(kept, [valid])
        self.assertEqual(report['dropped'][0]['relation'], 9599901)
        self.assertIn('operator-published journey order',
                      report['dropped'][0]['why'])

    def test_relation_shape_can_be_loaded_without_stop_members(self):
        payload = {'elements': [
            {
                'type': 'way', 'id': 10,
                'geometry': [
                    {'lon': -80.0, 'lat': 40.0},
                    {'lon': -80.001, 'lat': 40.001},
                ],
            },
            {
                'type': 'relation', 'id': 20,
                'tags': {'type': 'route', 'route': 'funicular'},
                'members': [{'type': 'way', 'ref': 10, 'role': ''}],
            },
        ]}
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, 'relation.json')
            with open(path, 'w', encoding='utf-8') as output:
                json.dump(payload, output)

            shapes = builder.load_osm_relation_shapes(directory)

        self.assertEqual(shapes[20], [[-80.0, 40.0], [-80.001, 40.001]])


class CrossFeedDuplicateTests(unittest.TestCase):
    @staticmethod
    def line(line_id, feed, stations):
        return {
            'lineId': line_id, 'feed': feed, 'operator': 'Example Railway',
            'name': 'Blue Line',
            'stationNames': [row[0] for row in stations],
            'stationPoints': [row[1] for row in stations],
        }

    def test_higher_priority_official_feed_wins_in_either_direction(self):
        preferred = self.line('preferred', 'operator', [
            ('Alpha', [0.0, 0.0]), ('Beta', [0.01, 0.0])])
        aggregate = self.line('aggregate', 'regional', [
            ('Beta', [0.01001, 0.0]), ('Alpha', [0.00001, 0.0])])
        reports = []

        kept = builder.drop_cross_feed_duplicates(
            [aggregate, preferred],
            {'operator': {'duplicatePriority': 100},
             'regional': {'duplicatePriority': 0}},
            reports)

        self.assertEqual(kept, [preferred])
        self.assertEqual(reports[0]['dropped'][0]['line'], 'aggregate')

    def test_equal_priority_refuses_to_guess(self):
        a = self.line('a', 'one', [
            ('Alpha', [0.0, 0.0]), ('Beta', [0.01, 0.0])])
        b = self.line('b', 'two', [
            ('Alpha', [0.0, 0.0]), ('Beta', [0.01, 0.0])])

        kept = builder.drop_cross_feed_duplicates(
            [a, b], {'one': {}, 'two': {}}, [])

        self.assertEqual(kept, [a, b])


class NetworkIntervalSafetyTests(unittest.TestCase):
    def setUp(self):
        self.feed = builder.FeedBuild.__new__(builder.FeedBuild)
        self.feed.options = SimpleNamespace(anchor_m=600.0)
        self.feed.report = {'dropped': []}

    def test_far_station_snap_rejects_each_touching_interval(self):
        intervals = [
            [[0.0, 0.0], [0.01, 0.0]],
            [[0.01, 0.0], [0.02, 0.0]],
        ]
        routing = {'snapMeters': [10.0, 2_600.0, 15.0]}

        result = self.feed.reject_far_snap_intervals(intervals, routing, 'R')

        self.assertEqual(result, [None, None])
        self.assertEqual(len(self.feed.report['dropped']), 2)

    def test_shape_fallback_replaces_the_complete_line(self):
        points = [[0.0, 0.0], [0.01, 0.0], [0.02, 0.0]]
        shape = [[0.0, 0.0], [0.005, 0.001], [0.01, 0.0],
                 [0.015, -0.001], [0.02, 0.0]]

        result = self.feed.patch_with_shape(
            [None, [[0.01, 0.0], [0.02, 0.0]]], points, shape, False,
            'commuter')

        self.assertEqual(len(result), 2)
        self.assertEqual(result[0][-1], result[1][0])
        self.assertGreater(len(result[1]), 2)

    def test_surveyed_official_straight_is_not_relabelled_as_gtfs(self):
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                return ([[[0.0, 0.0], [0.02, 0.0]]],
                        {'snapMeters': [0.0, 0.0]})

        self.feed.entry = {'officialNetworkByRouteId': {'R': 'cta-red'}}
        self.feed.options.official_networks = {'cta-red': Official()}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'R')

        self.assertEqual(source, 'cta-red')
        self.assertEqual(intervals, [[[0.0, 0.0], [0.02, 0.0]]])

    def test_route_specific_official_network_honours_tighter_snap_limit(self):
        class Official:
            seen_limit = None

            @classmethod
            def route_stations(cls, _points, max_snap_m):
                cls.seen_limit = max_snap_m
                return None, {'snapMeters': [0.0, None]}

        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'mta-subway-r'},
            'officialNetworkMaxSnapMeters': 125,
        }
        self.feed.options.official_networks = {'mta-subway-r': Official()}
        self.feed.report = {'dropped': [], 'notes': []}

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], None, [], 'metro', True, 'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertEqual(Official.seen_limit, 125)
        failure = self.feed.report['dropped'][0]
        self.assertEqual(failure['officialNetwork'], 'mta-subway-r')
        self.assertEqual(failure['limitMeters'], 125)

    def test_official_network_detour_is_rejected_before_publication(self):
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                return ([[[0.0, 0.0], [0.0, 0.1], [0.01, 0.0]]],
                        {'snapMeters': [0.0, 0.0]})

        self.feed.entry = {'officialNetworkByRouteId': {'R': 'mta-subway-r'}}
        self.feed.options.official_networks = {'mta-subway-r': Official()}
        self.feed.report = {'dropped': [], 'notes': []}

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.01, 0.0]], None, [], 'metro', True, 'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertTrue(any(
            row.get('why') ==
                'official route network contains an implausible interval'
            for row in self.feed.report['dropped']))

    def test_required_official_failure_forbids_gtfs_shape_fallback(self):
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                return None, {'snapMeters': [0.0, None]}

        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'septa-t2'},
            'requireVerifiedOfficialNetwork': True,
        }
        self.feed.options.official_networks = {'septa-t2': Official()}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertTrue(any('fallback forbidden' in row.get('why', '')
                            for row in self.feed.report['dropped']))

    def test_required_unverified_official_file_forbids_all_fallbacks(self):
        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'septa-t2'},
            'requireVerifiedOfficialNetwork': True,
        }
        self.feed.options.official_networks = {}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertEqual(
            self.feed.report['dropped'][0]['why'],
            'required verified official route network is unavailable')

    def test_all_routes_official_feed_forbids_unmapped_route_fallback(self):
        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'septa-t2'},
            'requireVerifiedOfficialNetwork': True,
            'requireOfficialMappingForAllRoutes': True,
        }
        self.feed.options.official_networks = {}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'unexpected-route')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertEqual(
            self.feed.report['dropped'][0]['why'],
            'required official route mapping is unavailable')

    def test_partial_official_feed_may_use_normal_gate_for_unmapped_route(self):
        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'amtrak-ntad-cascades'},
            'requireVerifiedOfficialNetwork': True,
        }
        self.feed.options.official_networks = {}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'unmapped-amtrak-route')

        self.assertIsNotNone(intervals)
        self.assertEqual(source, 'gtfs-shape')

    def test_internal_reversal_is_rejected_for_operator_shape_fallback(self):
        piece = [[-0.01, 0.0], [0.0, 0.0], [0.01, 0.0],
                 [0.0001, 0.0001], [-0.01, 0.0001]]
        result = self.feed.reject_detours(
            [piece], [[-0.01, 0.0], [-0.01, 0.0001]], None, True,
            'commuter')

        self.assertEqual(result, [None])
        self.assertIn('internal reversal', self.feed.report['dropped'][0]['why'])

    def test_station_anchor_turn_is_not_an_internal_reversal(self):
        piece = [[0.0, 0.0], [0.01, 0.0], [0.0001, 0.0001],
                 [-0.01, 0.0001]]

        self.assertIsNone(self.feed.has_internal_reversal(piece))

    def test_only_exact_shape_return_spikes_are_removed(self):
        shape = [[0.0, 0.0], [0.001, 0.0], [0.0, 0.0],
                 [0.002, 0.001], [0.003, 0.0]]

        cleaned, count = builder.remove_exact_return_spikes(shape)

        self.assertEqual(count, 1)
        self.assertEqual(cleaned, [[0.0, 0.0], [0.002, 0.001], [0.003, 0.0]])

    def test_direction_variant_cycle_needs_a_nearby_physical_closure(self):
        patterns = []
        for stations in (['A', 'B', 'C'], ['C', 'A', 'B']):
            pattern = builder.lines.Pattern(stations, None, 'trip')
            pattern.weight = 1.0
            pattern.trips = 1
            patterns.append(pattern)

        selected = builder.lines.select_lines(patterns)

        self.assertTrue(selected)
        self.assertTrue(any(row[3] for row in selected))
        self.assertFalse(builder.plausible_loop_closure(
            [[-73.9, 41.0], [-73.8, 41.1], [-73.8, 41.07]]))

    def test_long_distance_station_order_reversal_is_rejected(self):
        points = [[-73.88, 41.19], [-73.98, 40.75], [-73.98, 41.50]]

        self.assertEqual(builder.station_order_reversals(points), [1])

    def test_ordinary_curve_is_not_a_station_order_reversal(self):
        points = [[-73.98, 40.75], [-73.88, 41.19], [-73.94, 41.71]]

        self.assertEqual(builder.station_order_reversals(points), [])

    def test_equal_weight_branches_have_deterministic_station_order(self):
        patterns = []
        for stations in (['A', 'B', 'D'], ['A', 'C', 'D']):
            pattern = builder.lines.Pattern(stations, None, 'trip')
            pattern.weight = 1.0
            pattern.trips = 1
            patterns.append(pattern)

        forward = builder.lines.select_lines(patterns)
        reverse = builder.lines.select_lines(list(reversed(patterns)))

        self.assertEqual(
            [(row[0], row[1], row[3]) for row in forward],
            [(row[0], row[1], row[3]) for row in reverse])

    def test_compact_chain_refuses_anchor_gap(self):
        line = {
            'isLoop': False,
            'anchors': [[0.0, 0.0], [0.01, 0.0], [0.02, 0.0]],
            'intervals': [
                [[0.0, 0.0], [0.01, 0.0]],
                [[0.04, 0.0], [0.02, 0.0]],
            ],
        }

        faults = builder.validate_line_chain(line)

        self.assertTrue(any('endpoint gap' in fault for fault in faults))

    def test_only_rounding_scale_chain_gap_is_snapped(self):
        line = {
            'isLoop': False,
            'anchors': [[0.0, 0.0], [0.01, 0.0], [0.02, 0.0]],
            'intervals': [
                [[0.00002, 0.0], [0.01, 0.0]],
                [[0.0102, 0.0], [0.02, 0.0]],
            ],
        }

        repaired = builder.snap_tiny_chain_gaps(line)

        self.assertEqual(len(repaired), 1)
        self.assertEqual(line['intervals'][0][0], [0.0, 0.0])
        self.assertEqual(line['intervals'][1][0], [0.0102, 0.0])

    def test_solver_geometry_uses_exact_serialized_anchors(self):
        line = {
            'anchors': [[0.00000049, 0.0], [0.01000049, 0.0]],
            'intervals': [[[0.0000004, 0.0], [0.0050004, 0.001],
                           [0.0100004, 0.0]]],
        }

        intervals = builder.serialized_intervals(line)

        self.assertEqual(intervals[0][0], [0.0, 0.0])
        self.assertEqual(intervals[0][-1], [0.01, 0.0])

    def test_densified_station_chord_blocks_trunk_and_its_branches(self):
        root = {
            'lineId': 'feed-route', 'feed': 'feed', 'sourceRouteId': 'R',
            'branchOf': None, 'profile': 'metro', 'geometrySource': 'gtfs-shape',
            'anchors': [[0.0, 0.0], [0.02, 0.0]],
            'intervals': [builder.geo.densify([[0.0, 0.0], [0.02, 0.0]], 100)],
        }
        branch = {
            'lineId': 'feed-route-b1', 'feed': 'feed', 'sourceRouteId': 'R',
            'branchOf': 'feed-route', 'profile': 'metro',
            'geometrySource': 'gtfs-shape',
            'anchors': [[0.0, 0.0], [0.001, 0.001]],
            'intervals': [[[0.0, 0.0], [0.0005, 0.0007], [0.001, 0.001]]],
        }
        options = SimpleNamespace(geometry_blockers=[])

        kept = builder.filter_unresolved_geometry([root, branch], options)

        self.assertEqual(kept, [])
        self.assertEqual(len(options.geometry_blockers), 2)
        self.assertTrue(builder.piece_is_station_chord(
            root['intervals'][0], root['anchors'][0], root['anchors'][1]))

    def test_near_500_metre_chord_is_blocked_before_rounding_crosses_gate(self):
        end = [0.00449, 0.0]
        line = {
            'lineId': 'feed-short', 'feed': 'feed', 'sourceRouteId': 'S',
            'branchOf': None, 'profile': 'street',
            'geometrySource': 'gtfs-shape',
            'anchors': [[0.0, 0.0], end],
            'intervals': [builder.geo.densify([[0.0, 0.0], end], 100)],
        }

        self.assertEqual(builder.suspicious_straight_intervals(line), [0])

    def test_rounding_margin_blocks_barely_non_collinear_chord(self):
        start, end = [0.0, 0.0], [0.0046, 0.0]
        piece = [start, [0.0023, 0.0000155], end]

        self.assertGreater(builder.max_endpoint_chord_deviation(piece), 1.5)
        self.assertTrue(builder.piece_is_station_chord(piece, start, end))


class StationCoordinateOverrideTests(unittest.TestCase):
    def setUp(self):
        self.feed = builder.FeedBuild.__new__(builder.FeedBuild)
        self.feed.slug = 'example'
        self.feed.report = {'notes': []}

    def test_guarded_multi_source_override_corrects_known_bad_point(self):
        self.feed.entry = {'stationCoordinateOverrides': {'FAIR': {
            'published': [-149.06237, 60.60820],
            'corrected': [-147.74033, 64.85115],
            'evidence': ['station inventory', 'surveyed track'],
        }}}
        stops = {'FAIR': {'stop_name': 'Fairbanks',
                          'stop_lon': '-149.06237', 'stop_lat': '60.60820'}}

        corrected = self.feed.apply_station_coordinate_overrides(stops)

        self.assertEqual(float(corrected['FAIR']['stop_lon']), -147.74033)
        self.assertEqual(float(corrected['FAIR']['stop_lat']), 64.85115)
        self.assertIn('2-source validation', self.feed.report['notes'][0])

    def test_stale_override_is_refused_when_feed_moves_elsewhere(self):
        self.feed.entry = {'stationCoordinateOverrides': {'FAIR': {
            'published': [-149.06237, 60.60820],
            'corrected': [-147.74033, 64.85115],
            'evidence': ['station inventory', 'surveyed track'],
        }}}
        stops = {'FAIR': {'stop_name': 'Fairbanks',
                          'stop_lon': '-150.0', 'stop_lat': '65.0'}}

        with self.assertRaisesRegex(ValueError, 'stale override'):
            self.feed.apply_station_coordinate_overrides(stops)


class BorderSplitTests(unittest.TestCase):
    def test_cross_border_halves_do_not_claim_the_neighbouring_station(self):
        class Countries:
            @staticmethod
            def code_for(lon, _lat, _fallback):
                return 'us' if lon < 0 else 'ca'

        line = {'anchors': [[-2.0, 0.0], [-1.0, 0.0],
                            [1.0, 0.0], [2.0, 0.0]]}

        runs = builder.split_line_by_country(line, Countries(), 'us')

        self.assertEqual(runs, [('us', 0, 1), ('ca', 2, 3)])

    def test_country_slice_requests_profile_recalculation(self):
        line = {
            'lineId': 'international', 'branchOf': None,
            'stationIds': ['a', 'b', 'c'],
            'stationNames': ['A', 'B', 'C'],
            'stationZones': [None, None, None],
            'stationPoints': [[0.0, 0.0], [0.01, 0.0], [0.02, 0.0]],
            'anchors': [[0.0, 0.0], [0.01, 0.0], [0.02, 0.0]],
            'intervals': [
                [[0.0, 0.0], [0.01, 0.0]],
                [[0.01, 0.0], [0.02, 0.0]],
            ],
            'isLoop': False,
        }

        piece = builder.slice_line(line, 1, 2, 'ca', '-ca')

        self.assertTrue(piece['needsRegroom'])


class SupplementalOfficialNetworkTests(unittest.TestCase):
    def test_routes_only_operator_tagged_official_segments(self):
        features = [
            {'properties': {'etat': 'Opérationnel', 'siguti1vo': 'VIA'},
             'geometry': {'type': 'LineString', 'coordinates': [
                 [0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]}},
            # A shorter nearby freight-only chord must not enter the graph.
            {'properties': {'etat': 'Opérationnel', 'siguti1vo': 'Aucun'},
             'geometry': {'type': 'LineString', 'coordinates': [
                 [0.0, 0.0], [0.02, 0.0]]}},
        ]
        network = builder.na_official.PassengerNetwork(features, ('VIA',))

        intervals, report = network.route_stations(
            [[0.0, 0.0], [0.02, 0.0]], max_snap_m=100)

        self.assertEqual(report['snapMeters'], [0.0, 0.0])
        self.assertEqual(intervals[0],
                         [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]])


class OfficialNetworkProvenanceTests(unittest.TestCase):
    def test_septa_keys_use_exact_reviewed_layer_not_a_prefix_guess(self):
        exact = builder.na_provenance.KEY_SOURCE_EXACT
        self.assertEqual(exact['septa-b1'], 'septa-high-speed')
        self.assertEqual(exact['septa-t2'], 'septa-trolley')
        self.assertNotIn('septa-', builder.na_provenance.KEY_SOURCE_PREFIXES)

    def make_extract(self, directory, key='cta-red', tamper=False,
                     official_source=True):
        expected = builder.na_provenance.SOURCES['cta']
        source = {
            'publisher': expected['publisher'] if official_source else 'Example',
            'url': expected['url'] if official_source else 'https://example.test/gis',
            'rawSha256': 'a' * 64,
        }
        payload = {
            'type': 'FeatureCollection', 'sourceId': key, 'source': source,
            'features': [{'type': 'Feature', 'properties': {}, 'geometry': {
                'type': 'LineString', 'coordinates': [[0, 0], [1, 0]]}}],
        }
        encoded = json.dumps(payload, separators=(',', ':')).encode()
        path = os.path.join(directory, f'{key}.geojson')
        with open(path, 'wb') as output:
            output.write(encoded + (b' ' if tamper else b''))
        manifest = {
            'schemaVersion': 1,
            'sources': {'cta': {**expected, 'rawSha256': 'a' * 64}},
            'files': {key: {
                'file': f'{key}.geojson', 'features': 1,
                'sha256': hashlib.sha256(encoded).hexdigest(),
            }},
        }
        with open(os.path.join(directory, 'manifest.json'), 'w') as output:
            json.dump(manifest, output)

    def test_verified_official_extract_can_exempt_surveyed_straight_track(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_extract(directory)
            verified, diagnostics = builder.na_provenance.verify_route_networks(
                directory, {'cta-red'})
        self.assertFalse(diagnostics)
        self.assertIn('cta-red', verified)

        line = {
            'lineId': 'cta-red', 'feed': 'cta', 'sourceRouteId': 'Red',
            'branchOf': None, 'profile': 'metro', 'geometrySource': 'cta-red',
            'anchors': [[0.0, 0.0], [0.02, 0.0]],
            'intervals': [builder.geo.densify([[0.0, 0.0], [0.02, 0.0]], 100)],
        }
        options = SimpleNamespace(
            geometry_blockers=[], verified_official_sources=verified)
        self.assertEqual(builder.filter_unresolved_geometry([line], options), [line])

    def test_tampered_normalized_extract_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_extract(directory, tamper=True)
            verified, diagnostics = builder.na_provenance.verify_route_networks(
                directory, {'cta-red'})
        self.assertEqual(verified, {})
        self.assertTrue(any('mismatch' in row for row in diagnostics))

    def test_manifest_with_unreviewed_publisher_and_url_is_not_trusted(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_extract(directory, official_source=False)
            verified, diagnostics = builder.na_provenance.verify_route_networks(
                directory, {'cta-red'})
        self.assertEqual(verified, {})
        self.assertTrue(any('payload provenance' in row for row in diagnostics))

    def test_route_specific_network_may_join_nearby_feature_endpoints(self):
        features = [
            {'properties': {}, 'geometry': {'type': 'LineString',
             'coordinates': [[0.0, 0.0], [0.01, 0.0]]}},
            {'properties': {}, 'geometry': {'type': 'LineString',
             'coordinates': [[0.010001, 0.0], [0.02, 0.0]]}},
        ]
        network = builder.na_official.PassengerNetwork(
            features, endpoint_join_m=1.0)

        intervals, report = network.route_stations(
            [[0.0, 0.0], [0.02, 0.0]], max_snap_m=100)

        self.assertIsNotNone(intervals)
        self.assertEqual(len(network.joined_endpoints), 1)
        self.assertLess(network.joined_endpoints[0]['meters'], 1.0)
        self.assertEqual(report['snapMeters'], [0.0, 0.0])

    def test_endpoint_join_is_opt_in_and_never_joins_midline_points(self):
        features = [
            {'properties': {}, 'geometry': {'type': 'LineString',
             'coordinates': [[0.0, 0.0], [0.01, 0.0]]}},
            # Its endpoint is near the first feature's interior, not endpoint.
            {'properties': {}, 'geometry': {'type': 'LineString',
             'coordinates': [[0.005, 0.000001], [0.005, 0.01]]}},
        ]
        network = builder.na_official.PassengerNetwork(
            features, endpoint_join_m=10.0)

        self.assertEqual(network.joined_endpoints, [])
        self.assertEqual(len(set(network.components.values())), 2)


class PostBranchGroomingTests(unittest.TestCase):
    def test_station_topology_change_recomputes_profile_and_chord_cap(self):
        # Ten 1.5 km intervals make the final display line metro-scale, while
        # the deliberately stale profile says commuter.
        intervals = []
        stations = []
        for i in range(11):
            stations.append(f's{i}')
            if i:
                intervals.append([[0.014 * (i - 1), 0.0], [0.014 * i, 0.0]])
        line = {
            'needsRegroom': True, 'intervals': intervals,
            'stationIds': stations, 'profile': 'commuter', 'isLoop': False,
        }

        changed = builder.regroom_after_station_edits(line)

        self.assertTrue(changed)
        self.assertEqual(line['profile'], 'metro')
        self.assertTrue(all(
            builder.geo.haversine(piece[i], piece[i + 1]) <= 161
            for piece in line['intervals'] for i in range(len(piece) - 1)))


if __name__ == '__main__':
    unittest.main()
