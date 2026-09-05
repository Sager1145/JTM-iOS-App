import importlib.util
import os
import sys
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-canada-east-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
sys.path.insert(0, os.path.join(os.path.dirname(SCRIPT), 'lib'))
SPEC = importlib.util.spec_from_file_location('canada_east_official', SCRIPT)
east = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(east)


def mtq(subdivision='', user1='', user2='', operator='',
        track_class='Principale', state='Opérationnel'):
    return {'nomsubdiv1': subdivision, 'nomsubdiv2': '',
            'siguti1vo': user1, 'siguti2vo': user2, 'siglexploi': operator,
            'classvoie': track_class, 'etat': state}


def nrwn(subdivision='Weston', track_class='Main', status='Operational',
         area='Ontario'):
    return {'SUBDI1NAME': subdivision, 'SUBDI2NAME': 'None',
            'TRACKCLASS': track_class, 'STATUS': status, 'ADMINAREA': area}


class SourceProvenanceTests(unittest.TestCase):
    """The publisher and endpoint strings the release audit matches on.

    `na_provenance.verify_route_networks` compares these three fields
    character for character against its own reviewed allow-list, so a typo
    here is not a cosmetic problem: it silently un-verifies every route
    extract this normalizer writes.
    """

    def test_quebec_source_is_the_mtq_railway_inventory(self):
        source = east.SOURCES['quebec-mtq-reseau-ferroviaire']
        self.assertEqual(
            source['publisher'],
            'Ministère des Transports et de la Mobilité durable du Québec')
        self.assertEqual(source['url'], (
            'https://ws.mapserver.transports.gouv.qc.ca/swtq?service=wfs&'
            'version=2.0.0&request=getfeature&typename=ms:reseau_chfer_qc&'
            'outfile=ReseauFerroviaire&srsname=EPSG:4326&'
            'outputformat=geojson'))
        self.assertEqual(source['catalogUrl'],
                         'https://www.donneesquebec.ca/recherche/dataset/'
                         'reseau-ferroviaire')
        self.assertEqual(
            source['license'], 'Creative Commons Attribution 4.0 (CC-BY 4.0)')

    def test_ontario_source_is_the_federal_railway_network(self):
        source = east.SOURCES['nrcan-nrwn-on']
        self.assertEqual(
            source['publisher'],
            'Natural Resources Canada - GeoBase National Railway Network')
        self.assertEqual(source['url'], (
            'https://ftp.maps.canada.ca/pub/nrcan_rncan/vector/'
            'geobase_nrwn_rfn/on/nrwn_rfn_on_shp_en.zip'))
        self.assertEqual(source['license'],
                         'Open Government Licence - Canada')

    def test_toronto_track_and_route_layers_are_separate_sources(self):
        track = east.SOURCES['toronto-ttc-track']
        view = east.SOURCES['toronto-ttc-route-view']
        self.assertEqual(track['publisher'],
                         'City of Toronto - Geospatial Competency Centre')
        self.assertEqual(track['publisher'], view['publisher'])
        self.assertIn('COTGEO_TTC_TRACK/FeatureServer/0/query', track['url'])
        self.assertIn('COT_Geospatial_TTC_Streetcar_Route_view', view['url'])
        # The layer that names the route must never be the layer that draws
        # it: its attribute schema is verbatim GTFS `routes.txt`.
        self.assertNotEqual(track['url'], view['url'])
        self.assertEqual(track['license'],
                         'Open Government Licence - Toronto')


class RouteKeyMappingTests(unittest.TestCase):
    """One output key per published service, and one owning source per key."""

    def test_every_key_prefix_belongs_to_one_declared_source(self):
        self.assertEqual(
            east.KEY_PREFIXES, ('mtq-exo-', 'nrwn-on-', 'ttc-streetcar-'))
        for prefix in east.KEY_PREFIXES:
            self.assertTrue(
                any(prefix.startswith(part) for part in
                    ('mtq-', 'nrwn-', 'ttc-')), prefix)

    def test_exo_keys_cover_the_five_published_train_lines(self):
        self.assertEqual(sorted(east.MTQ_ROUTE_SUBDIVISIONS),
                         ['1', '3', '4', '5', '6'])
        keys = {f'mtq-exo-{route}' for route in east.MTQ_ROUTE_SUBDIVISIONS}
        self.assertEqual(keys, {'mtq-exo-1', 'mtq-exo-3', 'mtq-exo-4',
                                'mtq-exo-5', 'mtq-exo-6'})

    def test_ontario_keys_name_their_two_services(self):
        self.assertEqual(sorted(east.NRWN_ROUTE_SUBDIVISIONS),
                         ['nrwn-on-go-ki', 'nrwn-on-up-up'])

    def test_toronto_route_ids_map_to_their_own_keys(self):
        self.assertEqual(east.TTC_ROUTE_KEYS,
                         {'306': 'ttc-streetcar-306',
                          '501': 'ttc-streetcar-501',
                          '505': 'ttc-streetcar-505',
                          '506': 'ttc-streetcar-506'})


class SelectionIsolationTests(unittest.TestCase):
    def test_quebec_rejects_yards_car_floats_and_dead_track(self):
        for properties in (mtq('Vaudreuil', track_class='Triage'),
                           mtq('Vaudreuil', track_class='Transbordeur'),
                           mtq('Vaudreuil', state='Abandonné'),
                           mtq('Vaudreuil', state='Inexploité')):
            self.assertFalse(east.mtq_selects(properties, '1'))

    def test_quebec_admits_a_named_exo_record_off_the_subdivision_list(self):
        # Mascouche: exo owns the northern half outright and MTQ leaves the
        # subdivision name empty there, naming EXO as operator instead.
        self.assertTrue(east.mtq_selects(mtq(user1='EXO', operator='EXO'), '6'))

    def test_ontario_rejects_another_province_and_dead_track(self):
        self.assertFalse(east.nrwn_selects(
            nrwn(area='Manitoba'), 'nrwn-on-up-up'))
        self.assertFalse(east.nrwn_selects(
            nrwn(status='Discontinued'), 'nrwn-on-up-up'))

    def test_ontario_admits_union_station_yard_track(self):
        # NRWN classifies the Union Station Rail Corridor as yard track.
        # Refusing yard refuses the platforms every Kitchener train ends on.
        self.assertTrue(east.nrwn_selects(
            nrwn(track_class='Yard'), 'nrwn-on-go-ki'))


class ServicesDoNotMergeTests(unittest.TestCase):
    """Two services sharing a corridor must not share a route extract.

    This is the failure that matters most here, because both pairs below run
    over the same rails for part of their length: if the published attribute
    did not separate them, one line's extract would quietly contain the
    other's branch and the package would draw a train down a track it never
    takes.
    """

    def test_hudson_and_candiac_do_not_merge(self):
        # exo 1 runs west to Hudson over the M & O subdivision; exo 5 runs
        # south to Candiac over Adirondack.  They share the Westmount
        # approach into downtown Montréal, and each rejects the other's outer
        # subdivision outright — no corridor test involved.
        hudson = mtq('M & O', user1='EXO')
        adirondack = mtq('Adirondack', user1='EXO')
        shared = mtq('Westmount', user1='EXO')
        self.assertTrue(east.mtq_selects(hudson, '1'))
        self.assertFalse(east.mtq_selects(hudson, '5'))
        self.assertTrue(east.mtq_selects(adirondack, '5'))
        self.assertFalse(east.mtq_selects(adirondack, '1'))
        # The shared downtown approach is admitted by both, which is correct:
        # both trains really do run over it.
        self.assertTrue(east.mtq_selects(shared, '1'))
        self.assertTrue(east.mtq_selects(shared, '5'))

    def test_up_express_and_go_kitchener_do_not_merge(self):
        # Both leave Union over Weston.  UP then turns onto the airport spur,
        # which NRWN names `Pearson`; Kitchener carries on over Guelph.  That
        # published name is the whole reason UP is buildable at all.
        pearson = nrwn('Pearson')
        guelph = nrwn('Guelph')
        weston = nrwn('Weston')
        self.assertTrue(east.nrwn_selects(pearson, 'nrwn-on-up-up'))
        self.assertFalse(east.nrwn_selects(pearson, 'nrwn-on-go-ki'))
        self.assertTrue(east.nrwn_selects(guelph, 'nrwn-on-go-ki'))
        self.assertFalse(east.nrwn_selects(guelph, 'nrwn-on-up-up'))
        self.assertTrue(east.nrwn_selects(weston, 'nrwn-on-up-up'))
        self.assertTrue(east.nrwn_selects(weston, 'nrwn-on-go-ki'))

    def test_the_two_carlton_services_keep_separate_keys(self):
        self.assertNotEqual(east.TTC_ROUTE_KEYS['306'],
                            east.TTC_ROUTE_KEYS['506'])
        self.assertEqual(len(set(east.TTC_ROUTE_KEYS.values())),
                         len(east.TTC_ROUTE_KEYS))


class PayloadIntegrityTests(unittest.TestCase):
    def test_a_truncated_arcgis_page_is_refused(self):
        payload = ('{"type":"FeatureCollection","exceededTransferLimit":true,'
                   '"features":[{"type":"Feature","properties":'
                   '{"TRACK_ID":1},"geometry":{"type":"LineString",'
                   '"coordinates":[[-79.4,43.6],[-79.3,43.7]]}}]}')
        with self.assertRaises(SystemExit):
            east.read_geojson_lines(payload.encode(), 'City track',
                                    {'TRACK_ID'})

    def test_a_complete_page_is_read(self):
        payload = ('{"type":"FeatureCollection","features":'
                   '[{"type":"Feature","properties":{"TRACK_ID":1},'
                   '"geometry":{"type":"LineString",'
                   '"coordinates":[[-79.4,43.6],[-79.3,43.7]]}}]}')
        features = east.read_geojson_lines(payload.encode(), 'City track',
                                           {'TRACK_ID'})
        self.assertEqual(len(features), 1)
        self.assertEqual(features[0][0]['TRACK_ID'], 1)


if __name__ == '__main__':
    unittest.main()
