import importlib.util
import os
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-northeast2-official-networks.py'))
SPEC = importlib.util.spec_from_file_location('northeast2_official', SCRIPT)
northeast2 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(northeast2)


def feature(coordinates=None, **properties):
    return {
        'type': 'Feature',
        'properties': properties,
        'geometry': {
            'type': 'LineString',
            'coordinates': coordinates or [[-77.0, 38.9], [-77.1, 38.95]],
        },
    }


class ProvenanceStringTests(unittest.TestCase):
    """The build re-derives trust from these exact strings.

    `lib/na_provenance.verify_route_networks` matches the publisher and URL
    embedded in every written extract against its own allow-list, so a typo
    here is not a cosmetic difference: it silently removes the route from the
    package.  Pinning them in a test is what makes the registry patch and this
    normalizer one reviewed pair rather than two files that drifted apart.
    """

    def test_new_sources_carry_their_verified_publisher_and_endpoint(self):
        self.assertEqual(
            northeast2.NEW_SOURCES['dcgis-metro-lines-regional'],
            {
                'publisher': (
                    'District of Columbia Office of the Chief Technology '
                    'Officer (DC GIS) / DCGIS-DC GIS; source credit '
                    'Washington Metropolitan Area Transit Authority'),
                'url': (
                    'https://maps2.dcgis.dc.gov/dcgis/rest/services/'
                    'DCGIS_DATA/Transportation_Rail_Bus_WebMercator/'
                    'MapServer/58/query?where=1%3D1&outFields=*&outSR=4326&'
                    'returnGeometry=true&f=geojson'),
            })
        self.assertEqual(
            northeast2.NEW_SOURCES['massgis-mbta-commuter-rail-lines'],
            {
                'publisher': (
                    'MassGIS (Bureau of Geographic Information), '
                    'Commonwealth of Massachusetts EOTSS; layer credit '
                    "'MassGIS, CTPS, MBTA'"),
                'url': (
                    'https://arcgisserver.digital.mass.gov/arcgisserver/rest/'
                    'services/AGOL/MBTA_Commuter_Rail/FeatureServer/3/query?'
                    'where=1%3D1&outFields=*&outSR=4326&'
                    'returnGeometry=true&f=geojson'),
            })
        self.assertEqual(
            northeast2.NEW_SOURCES['prt-fixed-guideway-corridors'],
            {
                'publisher': 'Pittsburgh Regional Transit',
                'url': (
                    'https://services3.arcgis.com/544gNI3xxlFIWuTc/arcgis/'
                    'rest/services/PRT_Fixed_Guideway_Corridors/'
                    'FeatureServer/0/query?where=1%3D1&outFields=*&'
                    'outSR=4326&returnGeometry=true&f=geojson'),
            })

    def test_reused_sources_are_the_reviewed_ones_not_local_copies(self):
        # These four extracts are cut from layers the repository already
        # trusts.  Redefining them here would let this file trust a different
        # endpoint under a name the build recognises.
        for source_id in ('mta', 'mta-rail-branches', 'massgis-mbta-rapid',
                          'dcgis-streetcar'):
            self.assertNotIn(source_id, northeast2.NEW_SOURCES)
            self.assertIn(source_id, northeast2.SOURCES)
        self.assertEqual(
            northeast2.SOURCES['mta']['url'],
            'https://data.ny.gov/resource/s692-irgq.geojson?'
            '$select=service_name,service,geometry&$limit=100')

    def test_written_extract_embeds_the_source_signature_the_build_checks(self):
        import json
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            record = northeast2.write_group(
                directory, 'wmata-metrorail-red', [feature(NAME='red')],
                'dcgis-metro-lines-regional', 'a' * 64)
            with open(os.path.join(directory, record['file']),
                      encoding='utf-8') as written:
                payload = json.load(written)
        expected = northeast2.NEW_SOURCES['dcgis-metro-lines-regional']
        self.assertEqual(payload['sourceId'], 'wmata-metrorail-red')
        self.assertEqual(payload['source'], {
            'publisher': expected['publisher'],
            'url': expected['url'],
            'rawSha256': 'a' * 64,
        })
        self.assertEqual(record['features'], len(payload['features']))


class KeyToServiceMappingTests(unittest.TestCase):
    """One output key, one published service."""

    def test_every_key_names_exactly_one_gtfs_route(self):
        keys = (
            list(northeast2.WMATA_LINES)
            + [f'mta-subway-service-{route.lower()}'
               for route in northeast2.MTA_SERVICE_UNIONS]
            + list(northeast2.LIRR_BRANCHES)
            + [northeast2.MBTA_RED_KEY]
            + list(northeast2.MBTA_COMMUTER_LINES)
            + [northeast2.DC_STREETCAR_KEY]
            + list(northeast2.PRT_CORRIDORS))
        self.assertEqual(len(keys), len(set(keys)),
                         'two services must never share an output key')
        self.assertEqual(len(keys), 56)

    def test_wmata_keys_map_to_their_published_name(self):
        self.assertEqual(northeast2.WMATA_LINES['wmata-metrorail-red'], ('red',))
        # SILVER is `silver` alone.  Adding `orange` closes the New Carrollton
        # gap and lays a second downtown corridor over the shared subway, which
        # routed 35.79 km between two stations 0.52 km apart.
        self.assertEqual(
            northeast2.WMATA_LINES['wmata-metrorail-silver'], ('silver',))

    def test_mta_keys_cover_every_registry_route_id_one_to_one(self):
        # Route ids the MTA feed maps, including the express variants that
        # share a corridor with their local: each keeps its own key so it can
        # be narrowed later without moving the other.
        self.assertEqual(
            sorted(northeast2.MTA_SERVICE_UNIONS),
            sorted(['1', '2', '3', '4', '5', '6', '6X', '7', '7X', 'A', 'B',
                    'C', 'D', 'E', 'F', 'FS', 'FX', 'G', 'GS', 'H', 'J', 'L',
                    'M', 'N', 'Q', 'R', 'SI', 'W', 'Z']))
        self.assertEqual(northeast2.MTA_SERVICE_UNIONS['6'], ('6',))
        self.assertEqual(northeast2.MTA_SERVICE_UNIONS['6X'], ('6',))
        # The two measured exceptions to "one corridor per route".
        self.assertEqual(northeast2.MTA_SERVICE_UNIONS['H'], ('SR', 'A'))
        self.assertEqual(northeast2.MTA_SERVICE_UNIONS['F'], ('F', 'M'))
        self.assertEqual(northeast2.MTA_SERVICE_UNIONS['5'], ('5', '5 Peak'))

    def test_lirr_route_11_has_no_key(self):
        # MTA Rail Branches publishes no Belmont Park feature and the operator
        # GTFS snapshot has no route 11 trips.  A key would imply otherwise.
        self.assertNotIn(
            '11', ''.join(northeast2.LIRR_BRANCHES).replace('lirr-seam-', ''))
        self.assertEqual(
            sorted(northeast2.LIRR_BRANCHES),
            ['lirr-seam-1-babylon', 'lirr-seam-10-port-jefferson',
             'lirr-seam-12-city-terminal', 'lirr-seam-2-hempstead',
             'lirr-seam-3-oyster-bay', 'lirr-seam-4-ronkonkoma',
             'lirr-seam-5-montauk', 'lirr-seam-6-long-beach',
             'lirr-seam-7-far-rockaway', 'lirr-seam-8-west-hempstead',
             'lirr-seam-9-port-washington'])

    def test_lirr_keys_cover_every_route_that_needs_the_seam_closed_trunk(self):
        # Every route that touches CITY TERMINAL ZONE gets the seam-closed
        # trunk, not just the four the older normalizer already covered — a
        # missing route here is exactly how the three-seam extract's
        # 172-176 deg reversals would come back.
        for route_id, key in (
                ('1', 'lirr-seam-1-babylon'), ('3', 'lirr-seam-3-oyster-bay'),
                ('4', 'lirr-seam-4-ronkonkoma'), ('5', 'lirr-seam-5-montauk'),
                ('6', 'lirr-seam-6-long-beach'),
                ('7', 'lirr-seam-7-far-rockaway'),
                ('10', 'lirr-seam-10-port-jefferson')):
            self.assertIn(key, northeast2.LIRR_BRANCHES, route_id)
            self.assertIn('CITY TERMINAL ZONE', northeast2.LIRR_BRANCHES[key])

    def test_prt_incline_keys_are_separate_railways(self):
        self.assertEqual(northeast2.PRT_CORRIDORS['prt-incline-duquesne'],
                         ('DUQ',))
        self.assertEqual(northeast2.PRT_CORRIDORS['prt-incline-monongahela'],
                         ('MON',))


class RouteIsolationTests(unittest.TestCase):
    """Two services must not be able to merge into one key."""

    def test_two_wmata_lines_never_share_a_feature(self):
        red = feature(NAME='red')
        orange = feature(NAME='orange')
        silver = feature(NAME='silver')
        groups = northeast2.wmata_groups([
            red, orange, silver,
            feature(NAME='blue'), feature(NAME='green'),
            feature(NAME='yellow')])
        self.assertEqual(groups['wmata-metrorail-red'], [red])
        self.assertEqual(groups['wmata-metrorail-silver'], [silver])
        self.assertNotIn(orange, groups['wmata-metrorail-silver'])
        self.assertNotIn(red, groups['wmata-metrorail-orange'])

    def test_a_second_feature_with_the_same_published_name_is_refused(self):
        # A re-cut layer that grows a duplicate line must stop the build, not
        # quietly ship two parallel tracks under one service.
        with self.assertRaises(SystemExit):
            northeast2.wmata_groups([
                feature(NAME=name) for name in
                ('red', 'red', 'orange', 'blue', 'silver', 'green', 'yellow')])

    def test_mta_services_do_not_leak_between_keys(self):
        features = [feature(service=name) for name in
                    ('1', '2', '3', '4', '5', '5 Peak', '6', '7', 'A', 'B',
                     'C', 'D', 'E', 'F', 'G', 'J', 'L', 'M', 'N', 'Q', 'R',
                     'SF', 'SIR', 'SR', 'ST', 'W', 'Z')]
        by_service = {row['properties']['service']: row for row in features}
        groups = {}
        for route_id, corridors in northeast2.MTA_SERVICE_UNIONS.items():
            if route_id == 'SI':
                continue
            groups[route_id] = {
                row['properties']['service']
                for row in [by_service[name] for name in corridors]}
        # The N and the Q share the whole Broadway line physically, and the
        # published linework draws each of them separately; a key that held
        # both would let a shortest path change trains at Canal Street.
        self.assertEqual(groups['N'], {'N'})
        self.assertEqual(groups['Q'], {'Q'})
        self.assertFalse(groups['N'] & groups['Q'])
        # Same for the two Eastern Parkway services.
        self.assertFalse(groups['2'] & groups['3'])
        self.assertFalse(groups['4'] & groups['5'])

    def test_mbta_red_and_mattapan_cannot_merge(self):
        pin = northeast2.MBTA_RED_DUPLICATE_JUNCTION_ARC
        mattapan = feature(LINE='RED', ROUTE='Mattapan Trolley', GRADE=3)
        trunk = feature(LINE='RED', GRADE=7,
                        ROUTE='A - Ashmont B - Braintree  C - Alewife')
        ashmont = feature(LINE='RED', ROUTE='A - Ashmont  C - Alewife', GRADE=1)
        braintree = feature(LINE='RED', ROUTE='B - Braintree  C - Alewife',
                            GRADE=4)
        duplicate = feature(coordinates=[pin['start'], pin['end']],
                            LINE='RED', ROUTE=pin['route'], GRADE=pin['grade'])
        groups = northeast2.mbta_red_groups([
            mattapan, trunk, ashmont, braintree, duplicate,
            feature(LINE='BLUE', ROUTE='Bowdoin to Wonderland'),
        ])
        selected = groups[northeast2.MBTA_RED_KEY]
        self.assertIn(trunk, selected)
        self.assertIn(ashmont, selected)
        self.assertIn(braintree, selected)
        self.assertNotIn(mattapan, selected)
        self.assertNotIn(duplicate, selected)

    def test_mbta_red_refuses_a_layer_without_the_pinned_duplicate(self):
        with self.assertRaises(SystemExit):
            northeast2.mbta_red_groups([
                feature(LINE='RED', GRADE=7,
                        ROUTE='A - Ashmont B - Braintree  C - Alewife'),
            ])

    def test_dc_streetcar_takes_one_direction_track(self):
        keep = feature(DIRECTION='To Benning Rd', LINE_STATUS='Active')
        other = feature(DIRECTION='To Union Station', LINE_STATUS='Active')
        groups = northeast2.dc_streetcar_groups([keep, other])
        self.assertEqual(groups[northeast2.DC_STREETCAR_KEY], [keep])

    def test_prt_excludes_buses_and_retired_corridors(self):
        rail = feature(cor_id='BCH', mode='RAIL', fac_status='active')
        downtown = feature(cor_id='DTN', mode='RAIL', fac_status='active')
        incline = feature(cor_id='DUQ', mode='INCLINE', fac_status='active')
        busway = feature(cor_id='EBW', mode='BUS', fac_status='active')
        retired = feature(cor_id='DRK', mode='RAIL', fac_status='inactive')
        groups = northeast2.prt_groups(
            [rail, downtown, incline, busway, retired,
             feature(cor_id='OVB', mode='RAIL', fac_status='active'),
             feature(cor_id='ALT', mode='RAIL', fac_status='active'),
             feature(cor_id='LIB', mode='RAIL', fac_status='active'),
             feature(cor_id='MON', mode='INCLINE', fac_status='active')])
        self.assertEqual(groups['prt-t-red'], [rail, downtown])
        self.assertEqual(groups['prt-incline-duquesne'], [incline])
        for key, selected in groups.items():
            self.assertNotIn(busway, selected, key)
            self.assertNotIn(retired, selected, key)


class PublishedSeamTests(unittest.TestCase):
    """Every weld is pinned to a coordinate and re-checked on each run."""

    def test_lirr_seams_are_short_and_named(self):
        for names, old, new, limit in northeast2.LIRR_PUBLISHED_SEAMS:
            self.assertTrue(names)
            gap = northeast2.distance_m(old, new)
            self.assertLessEqual(gap, limit)
            self.assertLessEqual(limit, 45.0,
                                 'a weld this long could join a second railway')

    def test_lirr_weld_refuses_a_layer_whose_seam_moved(self):
        names, old, new, _limit = northeast2.LIRR_PUBLISHED_SEAMS[0]
        with self.assertRaises(SystemExit):
            northeast2.close_lirr_measured_seams([
                feature(route_name=names[0],
                        coordinates=[[-73.0, 40.0], [-73.1, 40.1]]),
            ])

    def test_lirr_hempstead_self_seam_also_moves_port_jeffersons_copy(self):
        # The Hempstead-internal seam's old coordinate is, at 0.00 m, also
        # the published start of PORT JEFFERSON's own linework (the Floral
        # Park shared-trunk junction).  Welding only HEMPSTEAD's copy would
        # stitch the internal seam shut while stranding PORT JEFFERSON at the
        # coordinate HEMPSTEAD just vacated -- exactly the regression that
        # made routes 3, 4 and 10 stop reaching every station.  The rule must
        # name both route_names so both copies move together.
        rule = next(rule for rule in northeast2.LIRR_PUBLISHED_SEAMS
                    if 'HEMPSTEAD' in rule[0]
                    and rule[1] == [-73.70543523699996, 40.72495113900004])
        self.assertIn('PORT JEFFERSON', rule[0])
        _names, old, new, _limit = rule
        # Every OTHER rule must also find its own pinned coordinate, so build
        # one feature per rule (as the refusal test above does) plus a
        # standalone PORT JEFFERSON feature carrying only this rule's shared
        # vertex.
        features = [
            feature(route_name=other_rule[0][0],
                    coordinates=[list(other_rule[1]), list(other_rule[2])])
            for other_rule in northeast2.LIRR_PUBLISHED_SEAMS
        ]
        features.append(
            feature(route_name='PORT JEFFERSON', coordinates=[old, [-73.5, 40.8]]))
        welded = northeast2.close_lirr_measured_seams(features)
        port_jefferson = next(row for row in welded
                              if row['properties']['route_name'] == 'PORT JEFFERSON'
                              and row['geometry']['coordinates'][-1] == [-73.5, 40.8])
        self.assertEqual(port_jefferson['geometry']['coordinates'][0], new,
                         'PORT JEFFERSON must move with HEMPSTEAD, not be left behind')
        # One feature per rule, holding that rule's own published endpoints:
        # every pinned coordinate has to still be there or the run stops.
        welded = northeast2.close_lirr_measured_seams([
            feature(route_name=rule[0][0],
                    coordinates=[list(rule[1]), list(rule[2])])
            for rule in northeast2.LIRR_PUBLISHED_SEAMS
        ])
        for rule, row in zip(northeast2.LIRR_PUBLISHED_SEAMS, welded):
            self.assertEqual(row['geometry']['coordinates'][0], list(rule[2]),
                             'the seam endpoint must move onto the junction')

    def test_mbta_foxboro_junction_is_a_sub_metre_weld(self):
        old, new, limit = northeast2.MBTA_FOXBORO_MANSFIELD_JUNCTION
        self.assertLessEqual(northeast2.distance_m(old, new), limit)
        self.assertLessEqual(limit, 1.0)
        with self.assertRaises(SystemExit):
            northeast2.close_mbta_foxboro_junction([
                feature(COMM_LINE='Foxboro',
                        coordinates=[[-71.0, 42.0], [-71.1, 42.1]]),
            ])

    def test_si_terminal_vertices_must_still_be_published(self):
        with self.assertRaises(SystemExit):
            northeast2._si_single_running_track(
                feature(service='SIR',
                        coordinates=[[-74.0, 40.6], [-74.1, 40.5]]))


class ManifestMergeTests(unittest.TestCase):
    """A partial run must not delete the records it did not rebuild."""

    def test_one_input_only_drops_that_source_s_own_keys(self):
        import json
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            manifest = {
                'schemaVersion': 1,
                'sources': {},
                'files': {
                    # another authority's key, and four of this file's own
                    'mbta-commuter-cr-fitchburg': {'file': 'x', 'sha256': 'y',
                                                   'features': 1},
                    'wmata-metrorail-red': {'file': 'x', 'sha256': 'y',
                                            'features': 1},
                    'mta-subway-service-1': {'file': 'x', 'sha256': 'y',
                                             'features': 1},
                    'prt-t-red': {'file': 'x', 'sha256': 'y', 'features': 1},
                    'lirr-seam-2-hempstead': {'file': 'stale', 'sha256': 'y',
                                              'features': 1},
                },
            }
            with open(os.path.join(directory, 'manifest.json'), 'w',
                      encoding='utf-8') as target:
                json.dump(manifest, target)
            source = os.path.join(directory, 'branches.geojson')
            seams = northeast2.LIRR_PUBLISHED_SEAMS
            # Every published branch name any LIRR_BRANCHES key selects, not
            # just the ones a seam touches — `select_exact` refuses a key
            # whose branches are not all present.
            names = {name for names in northeast2.LIRR_BRANCHES.values()
                     for name in names}
            features = []
            for name in sorted(names):
                line = []
                for rule in seams:
                    if name in rule[0]:
                        line.extend([list(rule[1]), list(rule[2])])
                if len(line) < 2:
                    line = [[-73.9, 40.7], [-73.8, 40.71]]
                features.append(feature(route_name=name, coordinates=line))
            with open(source, 'w', encoding='utf-8') as target:
                json.dump({'type': 'FeatureCollection',
                           'features': features}, target)

            northeast2.normalize(
                directory, {'mta_rail_branches_input': source})

            with open(os.path.join(directory, 'manifest.json'),
                      encoding='utf-8') as written:
                after = json.load(written)

        files = after['files']
        # Rebuilt, so replaced rather than kept:
        self.assertNotEqual(files['lirr-seam-2-hempstead']['file'], 'stale')
        # Not rebuilt, so untouched — a blanket purge would drop all four:
        for key in ('mbta-commuter-cr-fitchburg', 'wmata-metrorail-red',
                    'mta-subway-service-1', 'prt-t-red'):
            self.assertIn(key, files, key)


if __name__ == '__main__':
    unittest.main()
