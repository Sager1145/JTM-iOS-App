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


class DataDirGuardTests(unittest.TestCase):
    """resolve_data_dir() -- a scoped build must never default into app/data.

    Before this guard, `--data-dir` defaulted straight to the shipped
    `app/data` directory regardless of `--output-dir`, so a scoped
    `--only <feed>` review build pointed at a scratch --output-dir silently
    overwrote the checked-in stations/sections/readings files the moment its
    caller forgot an explicit --data-dir.
    """

    def test_explicit_data_dir_is_always_honoured(self):
        self.assertEqual(
            builder.resolve_data_dir('/scratch/out', '/anywhere/i/say',
                                     write_shipped_data=False),
            '/anywhere/i/say')
        # Even when that explicit path IS the shipped app/data dir.
        self.assertEqual(
            builder.resolve_data_dir('/scratch/out', builder.SHIPPED_DATA_DIR,
                                     write_shipped_data=True),
            builder.SHIPPED_DATA_DIR)

    def test_default_without_data_dir_or_flag_stays_under_output_dir(self):
        self.assertEqual(
            builder.resolve_data_dir('/scratch/out', None,
                                     write_shipped_data=False),
            os.path.join('/scratch/out', 'data'))

    def test_write_shipped_data_flag_opts_into_the_shipped_default(self):
        self.assertEqual(
            builder.resolve_data_dir('/scratch/out', None,
                                     write_shipped_data=True),
            builder.SHIPPED_DATA_DIR)


class OutputDirectoryTests(unittest.TestCase):
    def test_write_json_creates_a_missing_output_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, 'new', 'nested', 'package.json')

            size = builder.write_json(path, {'format': 'compact-v1'})

            self.assertGreater(size, 0)
            with open(path, encoding='utf-8') as source:
                self.assertEqual(json.load(source), {'format': 'compact-v1'})


class CacheFingerprintTests(unittest.TestCase):
    def test_official_manifest_change_invalidates_feed_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            gtfs_dir = os.path.join(directory, 'gtfs')
            official_dir = os.path.join(directory, 'official-networks')
            os.makedirs(gtfs_dir)
            os.makedirs(official_dir)
            with open(os.path.join(gtfs_dir, 'example.zip'), 'wb') as output:
                output.write(b'feed')
            with open(os.path.join(official_dir, 'route.geojson'), 'wb') as output:
                output.write(b'geometry')
            manifest = os.path.join(official_dir, 'manifest.json')
            with open(manifest, 'w', encoding='utf-8') as output:
                json.dump({'revision': 1}, output)
            entry = {
                'mdb': 'example',
                'officialNetworkByRouteId': {'R': 'route'},
            }

            before = builder.feed_cache_fingerprint(entry, directory)
            with open(manifest, 'w', encoding='utf-8') as output:
                json.dump({'revision': 2}, output)
            after = builder.feed_cache_fingerprint(entry, directory)

        self.assertNotEqual(before, after)


class ReviewedSharedTrackTests(unittest.TestCase):
    @staticmethod
    def line(line_id, station_ids, station_points, intervals):
        return {
            'lineId': line_id,
            'stationIds': station_ids,
            'stationPoints': station_points,
            'anchors': [list(intervals[0][0])]
                       + [list(piece[-1]) for piece in intervals],
            'intervals': intervals,
            'isLoop': False,
            'lengthKm': 0.0,
        }

    def test_members_share_canonical_spine_and_keep_real_branches(self):
        canonical = self.line(
            'trunk', ['CITY', 'MID', 'SOUTH'],
            [[0.0, 0.0], [0.0, 0.01], [0.0, 0.03]],
            [[[0.0, 0.0], [0.0, 0.01]],
             [[0.0, 0.01], [0.0, 0.02], [0.0, 0.03]]])
        forward = self.line(
            'forward', ['f-city', 'f-mid', 'f-east'],
            [[0.0001, 0.0], [0.0001, 0.01], [0.02, 0.02]],
            [[[0.0001, 0.0], [0.0001, 0.01]],
             [[0.0001, 0.01], [0.0001, 0.02], [0.02, 0.02]]])
        reverse = self.line(
            'reverse', ['r-east', 'r-mid', 'r-city'],
            [[-0.02, 0.02], [-0.0001, 0.01], [-0.0001, 0.0]],
            [[[-0.02, 0.02], [-0.0001, 0.02], [-0.0001, 0.01]],
             [[-0.0001, 0.01], [-0.0001, 0.0]]])
        policy = [{
            'slug': 'test',
            'reviewedSharedTrack': {
                'canonicalLineId': 'trunk',
                'canonicalTerminalStationId': 'CITY',
                'junction': [0.0, 0.02],
                'maxJunctionOffsetMeters': 30,
                'maxStationOffsetMeters': 30,
                'members': [
                    {'lineId': 'forward', 'terminalSide': 'start'},
                    {'lineId': 'reverse', 'terminalSide': 'end'},
                ],
                'evidence': ['https://example.test/official'],
            },
        }]

        applied = builder.apply_reviewed_shared_track_alignments(
            [canonical, forward, reverse], policy)

        self.assertEqual(len(applied), 2)
        self.assertEqual(forward['intervals'][0], canonical['intervals'][0])
        self.assertEqual(reverse['intervals'][-1],
                         list(reversed(canonical['intervals'][0])))
        self.assertEqual(forward['intervals'][-1][-1], [0.02, 0.02])
        self.assertEqual(reverse['intervals'][0][0], [-0.02, 0.02])
        self.assertEqual(builder.validate_line_chain(forward), [])
        self.assertEqual(builder.validate_line_chain(reverse), [])


class RouteGroupingTests(unittest.TestCase):
    def test_missing_release_policy_defaults_to_strict(self):
        self.assertEqual(builder.registry_release_policy({}), 'strict')

    def test_release_policy_rejects_unknown_values(self):
        with self.assertRaisesRegex(ValueError, 'releasePolicy'):
            builder.registry_release_policy({'releasePolicy': 'complete'})

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

    def test_reviewed_cross_feed_distinct_stop_is_not_proximity_merged(self):
        entries = [
            {'feedStop': 'LSS', 'identity': 'LSS',
             'name': 'LaSalle Street', 'point': [-87.6322, 41.8764],
             'line': {'feed': 'metra',
                      'crossFeedDistinctStopIds': ['LSS']}},
            {'feedStop': '41340', 'identity': '41340',
             'name': 'LaSalle', 'point': [-87.6317, 41.8756],
             'line': {'feed': 'cta'}},
        ]

        self.assertEqual(len(builder.group_stations(entries)), 2)

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

    def test_metro_reroute_pattern_is_not_absorbed_into_public_stop_list(self):
        def line(line_id, kind, station_ids, anchors, branch_of=None):
            return {
                'lineId': line_id, 'branchOf': branch_of, 'kind': kind,
                'rank': 1, 'stationIds': list(station_ids),
                'stationNames': list(station_ids),
                'stationZones': [''] * len(station_ids),
                'stationPoints': [list(point) for point in anchors],
                'anchors': [list(point) for point in anchors],
                'intervals': [[list(a), list(b)]
                              for a, b in zip(anchors, anchors[1:])],
                'lengthKm': 2.0,
            }

        trunk = line('subway-2', 'metro', ['A', 'C'],
                     [[0.0, 0.0], [0.02, 0.0]])
        reroute = line('subway-2-b1', 'metro', ['A', 'B', 'C'],
                       [[0.0, 0.0], [0.01, 0.0], [0.02, 0.0]],
                       'subway-2')

        kept = builder.absorb_duplicate_branches([trunk, reroute])

        self.assertEqual([row['lineId'] for row in kept],
                         ['subway-2', 'subway-2-b1'])
        self.assertEqual(trunk['stationIds'], ['A', 'C'])

    def test_commuter_flag_stop_pattern_is_still_absorbed(self):
        def line(line_id, station_ids, anchors, branch_of=None):
            return {
                'lineId': line_id, 'branchOf': branch_of, 'kind': 'commuter',
                'rank': 3, 'stationIds': list(station_ids),
                'stationNames': list(station_ids),
                'stationZones': [''] * len(station_ids),
                'stationPoints': [list(point) for point in anchors],
                'anchors': [list(point) for point in anchors],
                'intervals': [[list(a), list(b)]
                              for a, b in zip(anchors, anchors[1:])],
                'lengthKm': 2.0,
            }

        trunk = line('rail-main', ['A', 'C'],
                     [[0.0, 0.0], [0.02, 0.0]])
        flag_stops = line('rail-main-b1', ['A', 'B', 'C'],
                          [[0.0, 0.0], [0.01, 0.0], [0.02, 0.0]],
                          'rail-main')

        kept = builder.absorb_duplicate_branches([trunk, flag_stops])

        self.assertEqual([row['lineId'] for row in kept], ['rail-main'])
        self.assertEqual(trunk['stationIds'], ['A', 'B', 'C'])

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

    def test_lower_priority_short_extract_is_removed_as_spatial_subset(self):
        preferred = self.line('amtrak-cascades', 'amtrak', [
            ('Vancouver', [0.0, 0.0]), ('Seattle', [0.5, 0.0]),
            ('Tacoma', [0.7, 0.0]), ('Portland', [1.0, 0.0])])
        aggregate = self.line('puget-cascades', 'regional', [
            ('Seattle', [0.50001, 0.0]), ('Tacoma', [0.70001, 0.0])])
        reports = []

        kept = builder.drop_cross_feed_duplicates(
            [aggregate, preferred],
            {'amtrak': {'duplicatePriority': 100},
             'regional': {'duplicatePriority': 0}},
            reports)

        self.assertEqual(kept, [preferred])
        self.assertEqual(reports[0]['dropped'][0]['line'], 'puget-cascades')

    def test_lower_priority_non_subset_service_is_retained(self):
        preferred = self.line('preferred', 'operator', [
            ('Alpha', [0.0, 0.0]), ('Beta', [0.01, 0.0])])
        distinct = self.line('distinct', 'regional', [
            ('Alpha', [0.0, 0.0]), ('Gamma', [0.02, 0.0])])

        kept = builder.drop_cross_feed_duplicates(
            [preferred, distinct],
            {'operator': {'duplicatePriority': 100},
             'regional': {'duplicatePriority': 0}}, [])

        self.assertEqual(kept, [preferred, distinct])


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

    def test_reviewed_route_can_prefer_complete_operator_shape(self):
        class Official:
            called = False

            @classmethod
            def route_stations(cls, _points, max_snap_m):
                cls.called = True
                return ([[[0.0, 0.0], [0.0, 0.03], [0.01, 0.0]]],
                        {'snapMeters': [0.0, 0.0]})

        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'city-streetcar'},
            'preferOperatorShapeByRouteId': ['R'],
            'requireVerifiedOfficialNetwork': True,
        }
        self.feed.options.official_networks = {'city-streetcar': Official()}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.005, 0.001], [0.01, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.01, 0.0]], shape, [shape], 'streetcar', False,
            'R')

        self.assertFalse(Official.called)
        self.assertEqual(source, 'gtfs-shape')
        self.assertEqual(intervals, [shape])
        self.assertTrue(any('selected ahead of city-streetcar' in note
                            for note in self.feed.report['notes']))

    def test_operator_shape_preference_names_narn_when_no_gis_is_mapped(self):
        self.feed.entry = {'preferOperatorShapeByRouteId': ['R']}
        self.feed.network = None
        self.feed.options.official_networks = {}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.005, 0.001], [0.01, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.01, 0.0]], shape, [shape], 'commuter', False,
            'R')

        self.assertEqual(source, 'gtfs-shape')
        self.assertEqual(intervals, [shape])
        self.assertTrue(any('selected ahead of NARN fallback' in note
                            for note in self.feed.report['notes']))

    def test_preferred_operator_shape_fails_closed_when_schematic(self):
        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'city-streetcar'},
            'preferOperatorShapeByRouteId': ['R'],
        }
        self.feed.options.official_networks = {}
        self.feed.report = {'dropped': [], 'notes': []}

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.01, 0.0]], None, [], 'streetcar', True, 'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertEqual(
            self.feed.report['dropped'][0]['why'],
            'preferred operator alignment is unavailable or schematic')

    def test_required_official_failure_falls_back_and_says_so(self):
        """A reviewed centreline that cannot reach every station is short,
        not authoritative about the railway's absence.

        SEPTA's trolleys, SFMTA's K/L/M, Sound Transit's two Link lines and
        half of the New York City subway all failed exactly this way: the
        official layer predates an extension or omits the subway half of a
        street route, and the old rule deleted the railway rather than the
        preference. The operator's own published alignment takes over for the
        whole line, the package records which centreline it wanted, and the
        independent `geometry.deviation` check measures what shipped.
        """
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                return None, {'snapMeters': [0.0, None]}

        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'septa-t2'},
            'requireVerifiedOfficialNetwork': True,
        }
        self.feed.options.release_policy = 'completeness'
        self.feed.options.official_networks = {'septa-t2': Official()}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'R')

        self.assertIsNotNone(intervals)
        self.assertEqual(source, self.feed.SHAPE_SOURCE)
        self.assertEqual(self.feed.fallback_for('R', ''), 'septa-t2')
        self.assertTrue(any('septa-t2 could not route every station'
                            in note for note in self.feed.report['notes']))
        self.assertFalse(any('fallback forbidden' in row.get('why', '')
                             for row in self.feed.report['dropped']))

    def test_strict_official_failure_forbids_operator_shape_fallback(self):
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                return None, {'snapMeters': [0.0, None]}

        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'caltrans-sd-blue'},
            'requireVerifiedOfficialNetwork': True,
        }
        self.feed.options.release_policy = 'strict'
        self.feed.options.official_networks = {
            'caltrans-sd-blue': Official()}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        # The flag withholds the operator's own alignment; it does not cut the
        # ladder short. With no surveyed network available to this stub the
        # line still ends unpublished, but the refusal is the exhausted-ladder
        # one, and the note says which alignment was withheld and why.
        self.assertTrue(any('the operator alignment is forbidden' in note
                            for note in self.feed.report['notes']))
        self.assertTrue(any(row.get('why') == 'no usable alignment'
                            for row in self.feed.report['dropped']))

    def test_declared_official_defect_is_fail_closed_under_strict(self):
        """Under `strict`, a known bad route layer withholds the railway.

        The companion is
        `test_declared_official_defect_opens_the_ladder_under_completeness`:
        the same declaration, the other release policy. Which one a package
        wants is written once, in the registry's `releasePolicy`, and both
        are honest as long as the package says which it used.
        """
        self.feed.options.release_policy = 'strict'

        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                raise AssertionError('a defective layer must not be consulted')

        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'amtrak-ntad-zephyr'},
            'requireVerifiedOfficialNetwork': True,
            'requireOfficialMappingForAllRoutes': True,
            'forbidOfficialNetworkFallback': True,
            'officialNetworkDefectByRouteId': {
                'R': 'split into 31 disconnected official components'},
        }
        self.feed.options.official_networks = {
            'amtrak-ntad-zephyr': Official()}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False, 'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertEqual(self.feed.report['dropped'][0]['route'], 'R')
        self.assertIn('split into 31 disconnected official components',
                      self.feed.report['dropped'][0]['why'])

    def test_declared_official_defect_opens_the_ladder_under_completeness(self):
        """Under `completeness`, the defect disqualifies the LAYER only.

        The two statements were being made with one key: "this service must
        not ship" and "this extract is split / routes through a crossover no
        passenger train takes". Read as the first, the FRA NTAD component
        splits deleted most of Amtrak's long-distance network. Read as the
        second, the layer is skipped, the reason is recorded per line, and the
        next source draws the railway.
        """
        self.feed.options.release_policy = 'completeness'

        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                raise AssertionError('a defective layer must not be consulted')

        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'amtrak-ntad-zephyr'},
            'requireVerifiedOfficialNetwork': True,
            'requireOfficialMappingForAllRoutes': True,
            'forbidOfficialNetworkFallback': True,
            'officialNetworkDefectByRouteId': {
                'R': 'split into 31 disconnected official components'},
        }
        self.feed.options.official_networks = {
            'amtrak-ntad-zephyr': Official()}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False, 'R')

        self.assertIsNotNone(intervals)
        self.assertEqual(source, self.feed.SHAPE_SOURCE)
        self.assertTrue(any('is not used for this route' in note
                            for note in self.feed.report['notes']))

    def test_unresolved_geometry_review_is_fail_closed_under_strict(self):
        self.feed.options.release_policy = 'strict'
        self.feed.entry = {
            'geometryReviewByRouteId': {
                'R': 'no independent surveyed alignment is available'},
        }
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertEqual(self.feed.report['dropped'][0]['route'], 'R')
        self.assertIn('fail-closed',
                      self.feed.report['dropped'][0]['why'])

    def test_unresolved_review_ships_with_its_reason_under_completeness(self):
        """The explicit comparison policy publishes the review metadata.

        "No independent survey covers this corridor" is a statement about our
        evidence. A reader of the map cannot tell a railway that does not
        exist from one we could not double-check, so the railway ships and the
        sentence travels with it — into `geometryReview` on the line, and into
        the ledger row a reviewer works from.
        """
        self.feed.options.release_policy = 'completeness'
        self.feed.entry = {
            'geometryReviewByRouteId': {
                'R': 'no independent surveyed alignment is available'},
        }
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False, 'R')

        self.assertIsNotNone(intervals)
        self.assertEqual(source, self.feed.SHAPE_SOURCE)
        self.assertEqual(
            self.feed.geometry_reviews[('R', '')],
            'no independent surveyed alignment is available')

    def test_unlisted_route_still_fails_closed_under_review(self):
        """`acceptOperatorShapeByRouteId` is opt-in, per route.

        A registry entry that lists some other route (or no route at all)
        must not quietly rescue this one — the old fail-closed behaviour for
        an unresolved "no independent survey" review stays exactly as it was
        unless this specific route id is named.
        """
        self.feed.options.release_policy = 'strict'
        self.feed.entry = {
            'geometryReviewByRouteId': {
                'R': 'SEPTA GTFS shape is not an independent surveyed alignment'},
            'acceptOperatorShapeByRouteId': {
                'OTHER': 'evidence for a route this test does not build'},
        }
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False, 'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertEqual(self.feed.report['dropped'][0]['route'], 'R')
        self.assertIn('fail-closed', self.feed.report['dropped'][0]['why'])
        self.assertIn('SEPTA GTFS shape is not an independent surveyed '
                      'alignment', self.feed.report['dropped'][0]['why'])

    def test_listed_route_builds_from_operator_shape_as_gtfs_official(self):
        """A named route waives only the independent-survey requirement.

        The line still has to clear every other gate `geometry_for` runs —
        this test's shape/points pair is the same one
        `test_unresolved_review_ships_with_its_reason_under_completeness`
        proves clears `cut_at_stations`/`reject_detours` cleanly, so a
        failure here would mean the waiver skipped more than the one check
        it is supposed to.
        """
        self.feed.options.release_policy = 'strict'
        evidence = ('SEPTA GTFS feed 502 (2026-08-20); SEPTA publishes no '
                    'open survey centreline for Route 15 trolley service')
        self.feed.entry = {
            'geometryReviewByRouteId': {
                'R': 'SEPTA GTFS shape is not an independent surveyed alignment'},
            'acceptOperatorShapeByRouteId': {'R': evidence},
        }
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False, 'R')

        self.assertIsNotNone(intervals)
        self.assertEqual(source, 'gtfs-official')
        self.assertEqual([], self.feed.report['dropped'])
        # The evidence string is the line's provenance for this waiver, in
        # exactly the slot `geometryReview` already publishes for an
        # unresolved review under `completeness`.
        self.assertEqual(self.feed.geometry_reviews[('R', '')], evidence)
        self.assertTrue(any('independent survey requirement waived' in note
                            and evidence in note
                            for note in self.feed.report['notes']))

    def test_forbidden_fallback_still_lets_the_surveyed_network_draw(self):
        """The flag withholds the operator's shape, not the government survey.

        Amtrak's and VIA's long-distance networks are routed over the FRA and
        provincial surveys, and were drawn that way long before any per-route
        NTAD extract existed. When the extract is split or short, refusing the
        whole line deletes forty intercity railways to express a preference
        between two official sources; withholding only the operator's own
        shape expresses the preference and keeps the railway.
        """
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                return None, {'snapMeters': [0.0, None]}

        surveyed = [[[0.0, 0.0], [0.01, 0.0005], [0.02, 0.0]]]
        original = builder.narn.route_stations
        builder.narn.route_stations = (
            lambda *args, **kwargs: (list(surveyed), {'snapMeters': [1.0, 1.0],
                                                      'surveyed': [True]}))
        self.addCleanup(setattr, builder.narn, 'route_stations', original)

        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'amtrak-ntad-cardinal'},
            'requireVerifiedOfficialNetwork': True,
            'forbidOfficialNetworkFallback': True,
        }
        self.feed.options.official_networks = {
            'amtrak-ntad-cardinal': Official()}
        self.feed.options.corridor_m = 1_500.0
        self.feed.options.snap_m = 3_000.0
        self.feed.network = object()
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'intercity', False,
            'R')

        self.assertEqual(source, 'narn')
        self.assertEqual(intervals, surveyed)
        self.assertTrue(any('the operator alignment is forbidden' in note
                            for note in self.feed.report['notes']))

    def test_route_specific_official_failure_gate_has_no_collateral_routes(self):
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                return None, {'snapMeters': [0.0, None]}

        self.feed.entry = {
            'officialNetworkByRouteId': {
                'Blue': 'mbta-rapid-blue', 'Orange': 'mbta-rapid-orange'},
            'requireVerifiedOfficialNetwork': True,
            'forbidOfficialNetworkFallbackByRouteId': ['Blue'],
        }
        self.feed.options.release_policy = 'completeness'
        self.feed.options.official_networks = {
            'mbta-rapid-blue': Official(),
            'mbta-rapid-orange': Official(),
        }
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        self.feed.report = {'dropped': [], 'notes': []}
        blue, blue_source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'Blue')
        self.feed.report = {'dropped': [], 'notes': []}
        orange, orange_source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'Orange')

        self.assertIsNone(blue)
        self.assertIsNone(blue_source)
        self.assertIsNotNone(orange)
        self.assertEqual(orange_source, self.feed.SHAPE_SOURCE)

    def test_branch_only_official_gate_blocks_reroute_but_keeps_trunk_fallback(self):
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                return None, {'snapMeters': [0.0, None]}

        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'mta-subway-r'},
            'requireVerifiedOfficialNetwork': True,
            'forbidOfficialNetworkFallbackForBranches': True,
        }
        self.feed.options.release_policy = 'completeness'
        self.feed.options.official_networks = {'mta-subway-r': Official()}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        self.feed.report = {'dropped': [], 'notes': []}
        trunk, trunk_source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'R', '')
        self.feed.report = {'dropped': [], 'notes': []}
        branch, branch_source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'R', '-b1')

        self.assertIsNotNone(trunk)
        self.assertEqual(trunk_source, self.feed.SHAPE_SOURCE)
        self.assertIsNone(branch)
        self.assertIsNone(branch_source)
        self.assertTrue(any(row.get('why') ==
                            'required official branch alignment could not '
                            'route every station'
                            for row in self.feed.report['dropped']))

    def test_branch_gate_does_not_replace_failed_official_route_with_narn(self):
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                return None, {'snapMeters': [0.0, None]}

        original = builder.narn.route_stations
        builder.narn.route_stations = lambda *args, **kwargs: (
            [[[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]],
            {'snapMeters': [1.0, 1.0], 'surveyed': [True]})
        self.addCleanup(setattr, builder.narn, 'route_stations', original)
        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'mnr-harlem'},
            'requireVerifiedOfficialNetwork': True,
            'forbidOfficialNetworkFallbackForBranches': True,
        }
        self.feed.options.release_policy = 'completeness'
        self.feed.options.official_networks = {'mnr-harlem': Official()}
        self.feed.options.corridor_m = 1_500.0
        self.feed.options.snap_m = 3_000.0
        self.feed.network = object()
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'commuter', False,
            'R', '-b2')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertTrue(any(
            row.get('why') == 'required official branch alignment could not '
                              'route every station'
            for row in self.feed.report['dropped']))

    def test_unverified_official_file_falls_back_and_names_the_key(self):
        """A missing or unverifiable route extract is our plumbing failing.

        An endpoint that moved or a layer that was republished changes a hash,
        not a railway. The build says on stderr which keys failed provenance;
        the line ships from the operator's own alignment and carries the name
        of the centreline it wanted, so the gap is visible per line instead of
        as a service that silently disappeared.
        """
        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'septa-t2'},
            'requireVerifiedOfficialNetwork': True,
        }
        self.feed.options.release_policy = 'completeness'
        self.feed.options.official_networks = {}
        self.feed.report = {'dropped': [], 'notes': []}
        shape = [[0.0, 0.0], [0.01, 0.001], [0.02, 0.0]]

        intervals, source = self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], shape, [shape], 'metro', False,
            'R')

        self.assertIsNotNone(intervals)
        self.assertEqual(source, self.feed.SHAPE_SOURCE)
        self.assertEqual(self.feed.fallback_for('R', ''), 'septa-t2')
        self.assertTrue(any('failed provenance review' in note
                            for note in self.feed.report['notes']))

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

    def test_reviewed_shape_selection_cannot_borrow_unapproved_shape(self):
        approved = builder.lines.Pattern(['A', 'B'], None, 'approved-trip')
        approved.shape_ids['approved'] = 1
        defective = builder.lines.Pattern(['A', 'B'], None, 'defective-trip')
        defective.shape_ids['defective'] = 100
        shapes = {
            'approved': [[0.0, 0.0], [0.005, 0.001], [0.01, 0.0]],
            'defective': [[0.0, 0.0], [0.0, 0.03], [0.01, 0.0]],
        }

        shape_id, shape = builder.trusted_shape_fallback(
            [[0.0, 0.0], [0.01, 0.0]], [approved, defective], shapes,
            600.0, allowed_shape_ids={'approved'})

        self.assertEqual(shape_id, 'approved')
        self.assertEqual(shape, shapes['approved'])

    def test_reviewed_shape_selection_fails_when_id_is_not_on_route(self):
        pattern = builder.lines.Pattern(['A', 'B'], None, 'trip')
        pattern.shape_ids['current'] = 1

        shape_id, shape = builder.trusted_shape_fallback(
            [[0.0, 0.0], [0.01, 0.0]], [pattern],
            {'retired': [[0.0, 0.0], [0.01, 0.0]]}, 600.0,
            allowed_shape_ids={'retired'})

        self.assertIsNone(shape_id)
        self.assertIsNone(shape)

    def test_final_groom_pass_removes_endpoint_barb_without_moving_station(self):
        band = builder.profile.BANDS[0]
        piece = [[0.0, 0.0], [0.00002, 0.0], [0.00001, 0.0],
                 [0.001, 0.0]]

        groomed = builder.build.groom([piece], band)[0]

        self.assertEqual(groomed[0], piece[0])
        self.assertEqual(groomed[-1], piece[-1])
        self.assertFalse(any(
            builder.geo.turn_degrees(a, b, c) >= 150.0
            for a, b, c in zip(groomed, groomed[1:], groomed[2:])))

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

    def test_preferred_trunk_keeps_other_published_alignment_as_branch(self):
        patterns = []
        for stations, weight in (
                (['A', 'B', 'C', 'D'], 10.0),
                (['A', 'B', 'X', 'Y', 'Z', 'D'], 1.0)):
            pattern = builder.lines.Pattern(stations, None, 'trip')
            pattern.weight = weight
            pattern.trips = 1
            patterns.append(pattern)

        selected = builder.lines.select_lines(
            patterns, preferred_trunk=['A', 'B', 'C', 'D'])

        self.assertEqual(selected[0][1], ['A', 'B', 'C', 'D'])
        self.assertTrue(any('X' in row[1] for row in selected[1:]))

    def test_preferred_trunk_rejects_unpublished_station_step(self):
        pattern = builder.lines.Pattern(['A', 'B', 'C'], None, 'trip')
        pattern.weight = 1.0
        pattern.trips = 1

        selected = builder.lines.select_lines(
            [pattern], preferred_trunk=['A', 'C'])

        self.assertEqual(selected, [])

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

    def test_straight_interval_ships_when_the_survey_agrees_it_is_straight(self):
        """Market Street is straight, so the tunnel under it is straight.

        Shape alone cannot separate a guessed connector from a railway that
        really does run in a straight line, and refusing both deleted BART,
        WMATA, DART, Cleveland and the REM. The separation is an independent
        opinion: track that the source which did NOT draw this line puts along
        the whole interval, inside the band's own tolerance.
        """
        straight = builder.geo.densify([[0.0, 0.0], [0.02, 0.0]], 100)

        class Survey:
            @staticmethod
            def straight_is_surveyed(piece, geometry_source, tolerance_m,
                                     minimum_matched=0.8):
                return {'agrees': True, 'vertices': len(piece),
                        'matched': len(piece), 'maxDeviationMeters': 3.2,
                        'worstAt': [0.01, 0.0], 'toleranceMeters': tolerance_m,
                        'agreedWith': {'osm': len(piece)}}

            @staticmethod
            def measure(piece, geometry_source, sample_every=1):
                return {'vertices': len(piece[0]), 'unmatched': 0,
                        'maxDeviationMeters': 3.2,
                        'worstAt': [0.01, 0.0],
                        'agreedWith': {'osm': len(piece[0])}}

        line = {
            'lineId': 'feed-route', 'feed': 'feed', 'sourceRouteId': 'R',
            'branchOf': None, 'profile': 'metro', 'geometrySource': 'gtfs-shape',
            'anchors': [[0.0, 0.0], [0.02, 0.0]],
            'intervals': [straight],
        }
        options = SimpleNamespace(geometry_blockers=[])

        kept = builder.filter_unresolved_geometry([line], options, Survey())

        self.assertEqual(kept, [line])
        self.assertEqual(line['straightSurvey']['intervals'], [0])
        self.assertEqual(line['straightSurvey']['toleranceMeters'], 40.0)
        self.assertEqual(options.geometry_blockers, [])

    def test_straight_interval_is_still_refused_when_nothing_corroborates(self):
        straight = builder.geo.densify([[0.0, 0.0], [0.02, 0.0]], 100)

        class Survey:
            @staticmethod
            def straight_is_surveyed(piece, geometry_source, tolerance_m,
                                     minimum_matched=0.8):
                return {'agrees': False, 'vertices': len(piece), 'matched': 1,
                        'maxDeviationMeters': 260.0, 'worstAt': [0.01, 0.0],
                        'toleranceMeters': tolerance_m, 'agreedWith': {}}

        line = {
            'lineId': 'feed-route', 'feed': 'feed', 'sourceRouteId': 'R',
            'branchOf': None, 'profile': 'metro', 'geometrySource': 'gtfs-shape',
            'anchors': [[0.0, 0.0], [0.02, 0.0]],
            'intervals': [straight],
        }
        options = SimpleNamespace(geometry_blockers=[])

        kept = builder.filter_unresolved_geometry([line], options, Survey())

        self.assertEqual(kept, [])
        self.assertNotIn('straightSurvey', line)
        self.assertEqual(len(options.geometry_blockers), 1)

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


class DisplayAlignmentReleaseTests(unittest.TestCase):
    @staticmethod
    def line(profile='metro'):
        return {
            'lineId': 'feed-route', 'feed': 'feed', 'sourceRouteId': 'R',
            'branchOf': None, 'profile': profile,
            'geometrySource': 'gtfs-shape',
            'anchors': [[0.0, 0.0], [0.01, 0.0]],
            'intervals': [[[0.0, 0.0], [0.005, 0.001], [0.01, 0.0]]],
        }

    def test_visible_parallel_alignment_is_release_blocked(self):
        class Survey:
            @staticmethod
            def measure(_intervals, _source, sample_every):
                self.assertEqual(sample_every, 1)
                return {'vertices': 3, 'unmatched': 0,
                        'maxDeviationMeters': 29.0,
                        'worstAt': [0.005, 0.001]}

        options = SimpleNamespace(geometry_blockers=[])
        kept = builder.filter_unresolved_geometry(
            [self.line()], options, Survey())

        self.assertEqual(len(kept), 1)
        self.assertEqual(kept[0]['_alignmentCheck']['displayBlockedIntervals'],
                         [0])
        self.assertEqual(options.geometry_blockers[-1]['limitMeters'], 25.0)
        self.assertIn('withheld from display',
                      options.geometry_blockers[-1]['why'])

    def test_alignment_inside_display_limit_is_retained(self):
        class Survey:
            @staticmethod
            def measure(_intervals, _source, sample_every):
                return {'vertices': 3, 'unmatched': 0,
                        'maxDeviationMeters': 24.9, 'worstAt': None}

        line = self.line()
        options = SimpleNamespace(geometry_blockers=[])
        kept = builder.filter_unresolved_geometry([line], options, Survey())

        self.assertEqual(kept, [line])
        self.assertEqual(options.geometry_blockers, [])
        self.assertEqual(line['_alignmentCheck']['vertices'], 3)

    def test_verified_official_alignment_outvotes_visual_crosscheck(self):
        class VisualReference:
            @staticmethod
            def measure(_intervals, _source, sample_every):
                self.assertEqual(sample_every, 1)
                return {'vertices': 3, 'unmatched': 0,
                        'maxDeviationMeters': 29.0,
                        'worstAt': [0.005, 0.001]}

        line = self.line()
        line['geometrySource'] = 'authority-blue'
        options = SimpleNamespace(
            geometry_blockers=[],
            verified_official_sources={'authority-blue': {'sha256': 'a' * 64}},
        )
        kept = builder.filter_unresolved_geometry(
            [line], options, VisualReference())

        self.assertEqual(kept, [line])
        self.assertNotIn('displayBlockedIntervals', line['_alignmentCheck'])
        self.assertEqual(
            line['_alignmentCheck']['officialSourceRetainedIntervals'], [0])
        self.assertEqual(options.geometry_blockers, [])

    def test_unchecked_vertex_is_not_published_as_precise(self):
        class Survey:
            @staticmethod
            def measure(_intervals, _source, sample_every):
                return {'vertices': 3, 'unmatched': 1,
                        'maxDeviationMeters': 0.0, 'worstAt': None}

        options = SimpleNamespace(geometry_blockers=[])
        kept = builder.filter_unresolved_geometry(
            [self.line()], options, Survey())

        self.assertEqual(len(kept), 1)
        self.assertEqual(kept[0]['_alignmentCheck']['displayBlockedIntervals'],
                         [0])
        self.assertEqual(options.geometry_blockers[-1]['unmatchedVertices'], 1)


class RouteKeyAliasTests(unittest.TestCase):
    """A registry key may name a route the way its passengers do.

    MARTA renumbered its five rail routes between the review that mapped their
    official alignments and the feed published since. Nothing about Atlanta's
    subway changed, but every reviewed mapping stopped matching, and with
    `requireOfficialMappingForAllRoutes` set the whole system left the package
    without one line in the ledger to say why.
    """

    ROUTES = [
        {'route_id': '26984', 'route_short_name': 'BLUE',
         'route_long_name': 'BLUE'},
        {'route_id': '26982', 'route_short_name': 'ATLSC',
         'route_long_name': 'Atlanta Streetcar'},
    ]

    def test_short_name_key_is_resolved_to_the_current_route_id(self):
        entry = {'officialNetworkByRouteId': {'BLUE': 'marta-blue'},
                 'preferOperatorShapeByRouteId': ['ATLSC'],
                 'officialNetworkDefectByRouteId': {
                     'ATLSC': 'reviewed streetcar alignment is defective'},
                 'geometryReviewByRouteId': {
                     'BLUE': 'local reference review remains open'},
                 'referenceValidatedGeometryByRouteId': {
                     'BLUE': 'redistributable shape checked locally'},
                 'forbidOfficialNetworkFallbackByRouteId': ['BLUE']}

        resolved = builder.resolve_route_keys(entry, self.ROUTES)

        self.assertEqual(resolved['officialNetworkByRouteId'],
                         {'26984': 'marta-blue'})
        self.assertEqual(resolved['preferOperatorShapeByRouteId'], ['26982'])
        self.assertEqual(resolved['officialNetworkDefectByRouteId'],
                         {'26982': 'reviewed streetcar alignment is defective'})
        self.assertEqual(resolved['geometryReviewByRouteId'],
                         {'26984': 'local reference review remains open'})
        self.assertEqual(resolved['referenceValidatedGeometryByRouteId'],
                         {'26984': 'redistributable shape checked locally'})
        self.assertEqual(resolved['forbidOfficialNetworkFallbackByRouteId'],
                         ['26984'])
        self.assertIn('officialNetworkByRouteId[BLUE] -> 26984',
                      resolved['_routeKeyAliases'])

    def test_an_exact_route_id_still_wins_over_a_name(self):
        entry = {'officialNetworkByRouteId': {'26984': 'marta-blue'}}

        resolved = builder.resolve_route_keys(entry, self.ROUTES)

        self.assertEqual(resolved['officialNetworkByRouteId'],
                         {'26984': 'marta-blue'})
        self.assertEqual(resolved['_routeKeyAliases'], [])

    def test_an_unmatched_key_is_left_alone_rather_than_guessed_at(self):
        entry = {'officialNetworkByRouteId': {'29226': 'marta-blue'}}

        resolved = builder.resolve_route_keys(entry, self.ROUTES)

        self.assertEqual(resolved['officialNetworkByRouteId'],
                         {'29226': 'marta-blue'})

    def test_the_registry_entry_itself_is_not_mutated(self):
        entry = {'officialNetworkByRouteId': {'BLUE': 'marta-blue'}}

        builder.resolve_route_keys(entry, self.ROUTES)

        self.assertEqual(entry['officialNetworkByRouteId'],
                         {'BLUE': 'marta-blue'})


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
    def test_sparse_official_edge_snaps_to_segment_not_distant_vertex(self):
        features = [
            {'properties': {}, 'geometry': {'type': 'LineString',
             'coordinates': [[0.0, 0.0], [0.02, 0.0]]}},
        ]
        network = builder.na_official.PassengerNetwork(features)

        intervals, report = network.route_stations(
            [[0.005, 0.0004], [0.015, 0.0004]], max_snap_m=100)

        self.assertIsNotNone(intervals)
        self.assertTrue(all(distance < 50 for distance in report['snapMeters']))
        self.assertAlmostEqual(intervals[0][0][0], 0.005, places=6)
        self.assertAlmostEqual(intervals[0][-1][0], 0.015, places=6)
        self.assertLess(builder.geo.line_length(intervals[0]), 1_200)

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
    def test_short_endpoint_projection_overshoots_are_clipped_only_at_ends(self):
        # The first and final adjacent vertices overshoot their station
        # anchors; the similar internal turn must remain untouched.
        points = [
            [0.0, 0.0], [0.00005, 0.0], [-0.001, 0.0],
            [-0.00105, 0.0], [0.0, 0.0], [-0.001, 0.0],
            [0.00005, 0.0], [0.0, 0.0],
        ]

        clipped = builder.clip_short_endpoint_overshoots(points)

        self.assertEqual(clipped[0], points[0])
        self.assertEqual(clipped[-1], points[-1])
        self.assertNotIn(points[1], clipped)
        self.assertNotIn(points[-2], clipped)
        self.assertIn(points[3], clipped)
        self.assertIn(points[4], clipped)

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


class ReviewedStationComplexTests(unittest.TestCase):
    """`stationComplexes` as the builder applies it, on the real geometry.

    Every coordinate below is read from the shipped us-2025.json rows the
    registry entries cite in their own `packageEvidence`, so the two-circle
    case is the real one: `us-official-penn` holds LIRR's platforms at New
    York Penn AND NJ Transit's Newark Light Rail platform 14.4 km away, and
    the two go to different complexes.
    """

    #: New York Penn and Newark Penn, trimmed to the fields the merge reads.
    COMPLEXES = {
        'us-official-new-york-penn': {
            'name': 'New York Penn Station',
            'center': [-73.993171, 40.750737],
            'maxMeters': 250,
            'absorbs': ['us-official-penn',
                        'us-official-ny-moynihan-train-hall-at-penn',
                        'us-official-34-st-penn'],
        },
        'us-official-newark': {
            'center': [-74.16434, 40.734424],
            'maxMeters': 200,
            'absorbs': ['us-official-penn'],
        },
    }

    LIRR_PENN = [-73.993397, 40.750864]
    MOYNIHAN = [-73.994230, 40.750621]
    NYCT_ACE = [-73.993474, 40.752322]
    NJT_NY_PENN = [-73.992318, 40.750100]
    NEWARK_LIGHT_RAIL = [-74.163454, 40.734965]
    NEWARK_RAIL = [-74.164340, 40.734424]

    @staticmethod
    def groups(spec):
        """Build the (group_meta, codes, names) triple `build_region` holds."""
        group_meta, codes, names, lines = [], {}, {}, {}
        for code, (name, members) in spec.items():
            rows = []
            for line_id, index, point in members:
                line = lines.setdefault(line_id, {'lineId': line_id})
                rows.append({'line': line, 'index': index,
                             'point': list(point)})
                codes[(id(line), index)] = code
                names[(id(line), index)] = name
            group_meta.append({'code': code, 'name': name,
                               'point': list(rows[0]['point']),
                               'members': rows})
        return group_meta, codes, names, lines

    def scenario(self):
        return self.groups({
            'us-official-penn': ('Penn Station', [
                ('lirr-babylon', 4, self.LIRR_PENN),
                ('njt-newark-light-rail', 3, self.NEWARK_LIGHT_RAIL),
            ]),
            'us-official-ny-moynihan-train-hall-at-penn': (
                'Moynihan Train Hall At Penn Sta', [
                    ('amtrak-northeast-regional', 11, self.MOYNIHAN)]),
            'us-official-new-york-penn': ('New York Penn', [
                ('njt-northeast-corridor', 7, self.NJT_NY_PENN)]),
            'us-official-newark': ('Newark Penn Station', [
                ('amtrak-northeast-regional', 12, self.NEWARK_RAIL)]),
        })

    def test_one_code_goes_to_two_complexes_by_its_own_coordinate(self):
        group_meta, codes, names, lines = self.scenario()

        applied = builder.apply_reviewed_station_complexes(
            'us', group_meta, codes, names, self.COMPLEXES)

        # The LIRR platform is inside the New York circle; the light-rail
        # platform sharing its code is 14.4 km away and belongs to Newark.
        self.assertEqual(codes[(id(lines['lirr-babylon']), 4)],
                         'us-official-new-york-penn')
        self.assertEqual(codes[(id(lines['njt-newark-light-rail']), 3)],
                         'us-official-newark')
        self.assertEqual(codes[(id(lines['amtrak-northeast-regional']), 11)],
                         'us-official-new-york-penn')
        # The Newark rail platform already carried the surviving code.
        self.assertEqual(codes[(id(lines['amtrak-northeast-regional']), 12)],
                         'us-official-newark')
        # `us-official-penn` has no platform left, so it is no longer a
        # station group at all.
        self.assertEqual(
            sorted(row['code'] for row in group_meta),
            ['us-official-new-york-penn', 'us-official-newark'])
        self.assertEqual(
            {record['station']: dict(record['absorbed']) for record in applied},
            {'us-official-new-york-penn': {
                'us-official-penn': 1,
                'us-official-ny-moynihan-train-hall-at-penn': 1},
             'us-official-newark': {'us-official-penn': 1}})

    def test_the_reviewed_name_is_the_name_the_place_is_called_by(self):
        group_meta, codes, names, lines = self.scenario()

        builder.apply_reviewed_station_complexes(
            'us', group_meta, codes, names, self.COMPLEXES)

        for line_id, index in (('lirr-babylon', 4),
                               ('amtrak-northeast-regional', 11),
                               ('njt-northeast-corridor', 7)):
            self.assertEqual(names[(id(lines[line_id]), index)],
                             'New York Penn Station')
        # The Newark entry names no `name`, so nothing is renamed there.
        self.assertEqual(
            names[(id(lines['njt-newark-light-rail']), 3)], 'Penn Station')
        self.assertEqual(
            names[(id(lines['amtrak-northeast-regional']), 12)],
            'Newark Penn Station')

    def test_a_platform_outside_max_meters_keeps_its_own_code(self):
        # Two platforms under one absorbed code: the A/C/E box 178 m from the
        # centre, and a stop a kilometre east that the complex does not claim.
        far = [-73.980000, 40.750000]
        group_meta, codes, names, lines = self.groups({
            'us-official-34-st-penn': ('34 St-Penn Station', [
                ('nyct-a', 20, self.NYCT_ACE),
                ('nyct-a', 21, far),
            ]),
            'us-official-new-york-penn': ('New York Penn', [
                ('njt-northeast-corridor', 7, self.NJT_NY_PENN)]),
        })

        builder.apply_reviewed_station_complexes(
            'us', group_meta, codes, names, self.COMPLEXES)

        self.assertGreater(
            builder.geo.haversine(
                self.COMPLEXES['us-official-new-york-penn']['center'], far),
            self.COMPLEXES['us-official-new-york-penn']['maxMeters'])
        self.assertEqual(codes[(id(lines['nyct-a']), 20)],
                         'us-official-new-york-penn')
        self.assertEqual(codes[(id(lines['nyct-a']), 21)],
                         'us-official-34-st-penn')
        self.assertEqual(names[(id(lines['nyct-a']), 21)], '34 St-Penn Station')
        # The group survives for the platform that was left alone.
        survivor = [row for row in group_meta
                    if row['code'] == 'us-official-34-st-penn']
        self.assertEqual([member['point'] for member in survivor[0]['members']],
                         [far])

    def test_the_merge_moves_no_coordinate(self):
        group_meta, codes, names, lines = self.scenario()
        before = {(row['code'], tuple(member['point']))
                  for row in group_meta for member in row['members']}
        points_before = {row['code']: list(row['point']) for row in group_meta}

        builder.apply_reviewed_station_complexes(
            'us', group_meta, codes, names, self.COMPLEXES)

        after = {tuple(member['point'])
                 for row in group_meta for member in row['members']}
        # Every platform coordinate survives the merge unchanged, and none is
        # added: no centroid, no averaging, no anchor pulled onto another.
        self.assertEqual(after, {point for _, point in before})
        for row in group_meta:
            self.assertEqual(row['point'], points_before[row['code']])

    def test_another_region_is_left_alone(self):
        group_meta, codes, names, lines = self.scenario()
        snapshot = dict(codes)

        applied = builder.apply_reviewed_station_complexes(
            'ca', group_meta, codes, names, self.COMPLEXES)

        self.assertEqual(applied, [])
        self.assertEqual(codes, snapshot)
        self.assertEqual(len(group_meta), 4)

    def test_a_chained_complex_is_refused(self):
        group_meta, codes, names, _ = self.scenario()
        chained = dict(self.COMPLEXES)
        chained['us-official-penn'] = {
            'center': [-73.993171, 40.750737], 'maxMeters': 100,
            'absorbs': ['us-official-34-st-penn'],
        }

        with self.assertRaises(ValueError):
            builder.apply_reviewed_station_complexes(
                'us', group_meta, codes, names, chained)

    def test_the_shipped_registry_table_is_applicable(self):
        registry = os.path.join(os.path.dirname(SCRIPT), 'na-feeds.json')
        with open(registry, encoding='utf-8') as source:
            complexes = json.load(source)['stationComplexes']
        group_meta, codes, names, lines = self.scenario()

        applied = builder.apply_reviewed_station_complexes(
            'us', group_meta, codes, names, complexes)

        self.assertEqual(codes[(id(lines['lirr-babylon']), 4)],
                         'us-official-new-york-penn')
        self.assertEqual(codes[(id(lines['njt-newark-light-rail']), 3)],
                         'us-official-newark')
        self.assertEqual(len(applied), 2)


class PrimaryRouteIdTests(unittest.TestCase):
    """A merged group is named after the route that carries its identity.

    Toronto lists the 3xx Blue Night streetcars before the 5xx day routes
    they share a name and a track with, so King shipped as ``304`` in the
    night network's blue. ``primaryRouteIds`` moves the day routes to the
    front before grouping; which routes merge does not change.
    """

    @staticmethod
    def fixture():
        routes = [
            {'route_id': '304', 'route_short_name': '304',
             'route_long_name': 'King', 'route_color': '0054A6',
             'agency_id': '1'},
            {'route_id': '504', 'route_short_name': '504',
             'route_long_name': 'King', 'route_color': 'ED1C24',
             'agency_id': '1'},
        ]
        trips = {'304': [{'trip_id': 'night'}], '504': [{'trip_id': 'day'}]}
        sequences = {'night': ['a', 'b'], 'day': ['a', 'b', 'c']}
        stops = {key: {'stop_id': key} for key in 'abc'}
        return routes, trips, sequences, stops, (lambda row: row['stop_id'])

    def test_feed_order_names_the_group_by_default(self):
        routes, trips, sequences, stops, parent = self.fixture()

        groups = builder.group_routes(routes, trips, sequences, stops, parent, {})

        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]['routes'][0]['route_id'], '304')
        self.assertEqual(groups[0]['colour'], '0054A6')
        self.assertEqual(groups[0]['slug'], '304')

    def test_primary_route_names_colours_and_numbers_the_group(self):
        routes, trips, sequences, stops, parent = self.fixture()

        groups = builder.group_routes(routes, trips, sequences, stops, parent,
                                      {}, primary_route_ids=['504'])

        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]['routes'][0]['route_id'], '504')
        self.assertEqual({r['route_id'] for r in groups[0]['routes']},
                         {'304', '504'})
        self.assertEqual(groups[0]['colour'], 'ED1C24')
        self.assertEqual(groups[0]['slug'], '504')
        self.assertEqual(groups[0]['name'], 'King')

    def test_replacement_bus_trips_are_left_out_by_headsign(self):
        trips = [
            {'trip_id': 'a',
             'trip_headsign': 'East - 506 Carlton towards Main Street Station'},
            {'trip_id': 'b', 'trip_headsign':
             'West - 506B Carlton Replacement Bus towards Spadina Station'},
            {'trip_id': 'c'},
        ]

        kept, excluded = builder.exclude_trips_by_headsign(
            trips, 'Replacement Bus')

        self.assertEqual([t['trip_id'] for t in kept], ['a', 'c'])
        self.assertEqual(excluded, 1)
        self.assertEqual(builder.exclude_trips_by_headsign(trips, None),
                         (trips, 0))


class AcceptedOsmRelationTests(unittest.TestCase):
    """An audited OSM relation with evidence draws a route ahead of its shape.

    Toronto's Line 1 and Line 2: the City's route layer and the TTC's GTFS
    shape are one schematic geometry, and the City's own topographic survey
    prefers the OSM relation wherever it can see the track.
    """

    RELATION = [[0.0, 0.0], [0.005, 0.0008], [0.01, 0.001],
                [0.015, 0.0008], [0.02, 0.0]]
    SHAPE = [[0.0, 0.0], [0.01, 0.003], [0.02, 0.0]]

    def setUp(self):
        class Official:
            @staticmethod
            def route_stations(_points, max_snap_m):
                raise AssertionError('a defective layer must not be consulted')

        self.feed = builder.FeedBuild.__new__(builder.FeedBuild)
        self.feed.options = SimpleNamespace(
            anchor_m=600.0, release_policy='strict',
            official_networks={'city-subway-1': Official()},
            osm_relation_shapes={20: self.RELATION})
        self.feed.report = {'dropped': [], 'notes': []}
        self.feed.entry = {
            'officialNetworkByRouteId': {'R': 'city-subway-1'},
            'requireVerifiedOfficialNetwork': True,
            'forbidOfficialNetworkFallback': True,
            'officialNetworkDefectByRouteId': {'R': 'schematic route layer'},
            'osmRelationByRouteId': {'R': 20},
            'osmRelationEvidenceByRouteId': {
                'R': 'the City survey prefers the relation'},
        }

    def geometry(self):
        return self.feed.geometry_for(
            [[0.0, 0.0], [0.02, 0.0]], self.SHAPE, [self.SHAPE], 'metro',
            False, 'R')

    def test_accepted_relation_draws_a_route_whose_layer_is_defective(self):
        intervals, source = self.geometry()

        self.assertEqual(source, 'osm')
        self.assertEqual(len(intervals), 1)
        self.assertGreater(len(intervals[0]), 2)
        self.assertEqual(self.feed.osm_relation_evidence[('R', '')],
                         {'relation': 20,
                          'evidence': 'the City survey prefers the relation'})
        self.assertEqual(self.feed.report['dropped'], [])
        self.assertTrue(any('audited OSM relation 20' in note
                            for note in self.feed.report['notes']))

    def test_relation_without_evidence_stays_fail_closed(self):
        del self.feed.entry['osmRelationEvidenceByRouteId']

        intervals, source = self.geometry()

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertIn('schematic route layer',
                      self.feed.report['dropped'][0]['why'])

    def test_missing_extract_keeps_the_defect_fail_closed(self):
        self.feed.options.osm_relation_shapes = {}

        intervals, source = self.geometry()

        self.assertIsNone(intervals)
        self.assertIn('schematic route layer',
                      self.feed.report['dropped'][0]['why'])
        self.assertTrue(any('not in the --osm-routes extracts' in note
                            for note in self.feed.report['notes']))

    def test_relation_that_misses_a_station_is_refused_not_patched(self):
        self.feed.options.osm_relation_shapes = {
            20: [[0.0, 0.0], [0.005, 0.0008], [0.01, 0.001]]}

        intervals, source = self.geometry()

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        self.assertIn('could not be cut at every station',
                      self.feed.report['dropped'][0]['why'])


class AcceptedOsmRelationDisplayTests(unittest.TestCase):
    """A straight interval on an audited relation is measured, not waved through.

    The relation cannot corroborate its own straight track — that is why
    `CrossCheck.straight_is_surveyed` refuses to consult OSM for a line OSM
    drew. What the builder can still establish, and what the whole-line skip
    hid, is whether the straightness is the source's own statement: slice the
    relation back out between the interval's endpoints and measure it.
    """

    RELATION = [[-0.001, 0.0], [0.0, 0.0], [0.003, 0.0],
                [0.007, 0.0], [0.01, 0.0], [0.011, 0.0]]

    class Survey:
        @staticmethod
        def measure(_intervals, _source, sample_every):
            return {'vertices': 3, 'unmatched': 2,
                    'maxDeviationMeters': 0.0, 'worstAt': None}

        @staticmethod
        def straight_is_surveyed(piece, _source, tolerance_m,
                                 minimum_matched=0.8):
            # Nothing independent surveys a subway tunnel.
            return {'agrees': False, 'vertices': len(piece), 'matched': 0,
                    'maxDeviationMeters': 0.0, 'worstAt': None,
                    'toleranceMeters': tolerance_m, 'agreedWith': {}}

    def line(self):
        return {
            'lineId': 'ttc-1', 'feed': 'ttc', 'sourceRouteId': '1',
            'branchOf': None, 'profile': 'metro', 'geometrySource': 'osm',
            'osmRelationEvidence': {
                'relation': 20, 'evidence': 'checked',
                'validation': {'validator': 'validate-ttc-subway-osm.py',
                               'reference': 'COTGEO_TOPO_RAILWAY 2005'},
            },
            'stationNames': ['Woodbine Station', 'Main Street Station'],
            'anchors': [[0.0, 0.0], [0.01, 0.0]],
            'intervals': [[[0.0, 0.0], [0.005, 0.0], [0.01, 0.0]]],
        }

    def options(self, relation=None, reviewed=None):
        return SimpleNamespace(
            geometry_blockers=[], verified_official_sources={},
            osm_relation_shapes={20: list(relation or self.RELATION)},
            reviewed_straight_intervals=reviewed or {})

    def test_accepted_relation_is_retained_where_no_survey_reaches(self):
        line = self.line()
        options = self.options()

        kept = builder.filter_unresolved_geometry([line], options, self.Survey())

        self.assertEqual(kept, [line])
        self.assertEqual(line['_alignmentCheck']['osmReferenceRetainedIntervals'],
                         [0])
        self.assertNotIn('displayBlockedIntervals', line['_alignmentCheck'])
        self.assertEqual(options.geometry_blockers, [])

    def test_straight_interval_records_what_was_measured(self):
        line = self.line()

        kept = builder.filter_unresolved_geometry(
            [line], self.options(), self.Survey())

        self.assertEqual(kept, [line])
        survey = line['straightSurvey']
        self.assertEqual(survey['intervals'], [0])
        record, = survey['records']
        self.assertEqual(record['interval'], 0)
        self.assertEqual(record['basis'], 'audited-relation')
        self.assertEqual(record['relation'], 20)
        self.assertEqual(record['fromStation'], 'Woodbine Station')
        self.assertEqual(record['toStation'], 'Main Street Station')
        self.assertGreater(record['chordMeters'], 1000.0)
        # Two relation nodes lie inside the interval and neither leaves the
        # chord: the source says this track is straight.
        self.assertEqual(record['sourceInteriorVertices'], 2)
        self.assertLess(record['sourceMaxDeviationMeters'], 0.01)
        self.assertEqual(record['validatedBy'], 'validate-ttc-subway-osm.py')
        self.assertEqual(record['validatedAgainst'], 'COTGEO_TOPO_RAILWAY 2005')
        # The relation is not written as its own corroborating source.
        self.assertEqual(survey['corroboratedBy'], {})
        self.assertNotIn('reviewedException', record)

    def test_interval_with_no_interior_node_says_so(self):
        line = self.line()

        builder.filter_unresolved_geometry(
            [line], self.options(relation=[[0.0, 0.0], [0.01, 0.0]]),
            self.Survey())

        record, = line['straightSurvey']['records']
        self.assertEqual(record['sourceInteriorVertices'], 0)
        self.assertNotIn('reviewedException', record)

    def test_reviewed_exception_travels_with_the_interval_it_reviews(self):
        line = self.line()
        reviewed = {'ttc-1': [{'from': 'Woodbine Station',
                               'to': 'Main Street Station',
                               'sagittaBoundMeters': 2.23,
                               'why': 'no interior node on either track'}]}

        builder.filter_unresolved_geometry(
            [line],
            self.options(relation=[[0.0, 0.0], [0.01, 0.0]], reviewed=reviewed),
            self.Survey())

        record, = line['straightSurvey']['records']
        self.assertEqual(record['sourceInteriorVertices'], 0)
        self.assertEqual(record['reviewedException']['sagittaBoundMeters'], 2.23)
        self.assertNotIn('from', record['reviewedException'])

    def test_reviewed_exception_for_another_station_pair_is_not_applied(self):
        line = self.line()
        reviewed = {'ttc-1': [{'from': 'Chester Station', 'to': 'Pape Station',
                               'sagittaBoundMeters': 0.99}]}

        builder.filter_unresolved_geometry(
            [line],
            self.options(relation=[[0.0, 0.0], [0.01, 0.0]], reviewed=reviewed),
            self.Survey())

        record, = line['straightSurvey']['records']
        self.assertNotIn('reviewedException', record)

    def test_relation_that_curves_here_refuses_the_flattened_interval(self):
        """The exemption is a measurement, so it can fail.

        A relation that bends between these two stations and a shipped
        interval that does not means the shape was lost on the way to the
        package. That is the defect the straight-interval gate exists for, and
        the old line-wide skip could not see it.
        """
        line = self.line()
        curved = [[0.0, 0.0], [0.005, 0.00005], [0.01, 0.0]]

        kept = builder.filter_unresolved_geometry(
            [line], self.options(relation=curved), self.Survey())

        self.assertEqual(kept, [])
        self.assertNotIn('straightSurvey', line)
        self.assertEqual(len(builder.suspicious_straight_intervals(line)), 1)

    def test_missing_relation_extract_refuses_rather_than_exempts(self):
        line = self.line()
        options = self.options()
        options.osm_relation_shapes = {}

        kept = builder.filter_unresolved_geometry([line], options, self.Survey())

        self.assertEqual(kept, [])
        self.assertNotIn('straightSurvey', line)


class CrosscheckOnlySurveyTests(unittest.TestCase):
    """A validation-only survey reaches the cross-check and nothing else.

    `na_provenance` registers the City of Toronto topographic subway-track
    layer as a validation reference, never a build input. The independent
    cross-check IS validation: it only ever measures geometry somebody else
    already drew, so admitting the survey there corroborates the intervals it
    can actually see instead of exempting them.
    """

    SURVEY = {
        'type': 'FeatureCollection',
        'features': [
            {'type': 'Feature', 'properties': {'SUBTYPE_CODE': 2005},
             'geometry': {'type': 'LineString',
                          'coordinates': [[-79.3, 43.7], [-79.29, 43.7]]}},
            {'type': 'Feature', 'properties': {},
             'geometry': {'type': 'MultiLineString',
                          'coordinates': [[[-79.28, 43.7], [-79.27, 43.7]]]}},
            {'type': 'Feature', 'properties': {},
             'geometry': {'type': 'Point', 'coordinates': [-79.26, 43.7]}},
        ],
    }

    def test_registered_survey_is_read_from_official_raw(self):
        name, = builder.CROSSCHECK_ONLY_SURVEYS
        with tempfile.TemporaryDirectory() as sources:
            raw = os.path.join(sources, 'official-raw')
            os.makedirs(raw)
            with open(os.path.join(raw, name), 'w') as handle:
                json.dump(self.SURVEY, handle)

            index, files, lines = builder.load_official_geometry(sources)

        self.assertEqual(files, 1)
        self.assertEqual(lines, 2)
        distance, tag = index.nearest([-79.295, 43.7], 2)
        self.assertLess(distance, 1.0)
        self.assertEqual(tag, builder.CROSSCHECK_ONLY_SURVEYS[name])

    def test_unregistered_raw_file_is_not_admitted(self):
        with tempfile.TemporaryDirectory() as sources:
            raw = os.path.join(sources, 'official-raw')
            os.makedirs(raw)
            with open(os.path.join(raw, 'some-other-layer.geojson'),
                      'w') as handle:
                json.dump(self.SURVEY, handle)

            _index, files, lines = builder.load_official_geometry(sources)

        self.assertEqual((files, lines), (0, 0))


if __name__ == '__main__':
    unittest.main()
