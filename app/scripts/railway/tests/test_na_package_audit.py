import hashlib
import importlib.util
import os
import tempfile
import unittest


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'audit-na-package.py'))
SPEC = importlib.util.spec_from_file_location('na_package_audit', SCRIPT)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def straight_line():
    return {
        'id': 'metro-red', 'name': 'Red', 'operator': 'Metro',
        'geometrySource': 'authority-red', 'smoothingProfile': 'metro',
        'colorReference': '#ff0000', 'colorSource': 'official GTFS',
        'stations': [
            ['us-a', 'A', -73.0, 40.0],
            ['us-b', 'B', -73.0, 40.01],
        ],
        'segments': [[1.111, 0, [
            [-73.0, 40.0], [-73.0, 40.005], [-73.0, 40.01],
        ]]],
    }


class PackageAuditTests(unittest.TestCase):
    def test_verified_official_straight_track_is_not_called_a_guess(self):
        findings = audit.Findings()
        audit.audit_line(straight_line(), 'US', findings, {'authority-red'})
        self.assertFalse(any(row['check'] == 'interval.straight'
                             for row in findings.rows))

    def test_unverified_straight_track_remains_an_error(self):
        findings = audit.Findings()
        audit.audit_line(straight_line(), 'US', findings)
        self.assertTrue(any(row['check'] == 'interval.straight'
                            for row in findings.rows))

    def test_colour_requires_official_source(self):
        line = straight_line()
        line.pop('colorSource')
        findings = audit.Findings()
        audit.audit_line(line, 'US', findings, {'authority-red'})
        self.assertTrue(any(row['check'] == 'colour.source'
                            for row in findings.rows))


def osm_relation_package(with_evidence=True):
    """A line drawn from an OpenStreetMap relation the build audited.

    The reference excludes OpenStreetMap as a self-reference, so it cannot
    disagree with this alignment: the deviation it reports is the distance to
    the nearest OTHER railway, and every vertex is unmatched because nothing
    independent covers the alignment at all. TTC Lines 1 and 2 are the real
    case -- 390 m to a freight subdivision, and no published survey of the
    subway tunnels.
    """
    line = straight_line()
    line['id'] = 'transit-1'
    line['geometrySource'] = 'osm'
    if with_evidence:
        line['osmRelationEvidence'] = {
            'relation': 102388,
            'evidence': 'city topographic survey',
            'validation': {'medianMeters': 0.4},
        }
    return {
        'country': 'CA',
        'lines': [line],
        'geometrySource': {'officialGeometryComparison': {'byLine': {
            'transit-1': {
                'builtFrom': 'osm',
                'maxDeviationMeters': 392.7,
                'vertices': 443,
                'unmatched': 305,
                'osmReferenceRetainedIntervals': [0, 1, 2],
            },
        }}},
    }


class OsmReferenceRetainedTests(unittest.TestCase):
    """The build writes the key; before this rung the audit never read it."""

    def _checks(self, package):
        findings = audit.Findings()
        audit.audit_package(package, findings, {'transit-1': 'metro'})
        return {row['check']: row['severity'] for row in findings.rows}

    def test_audited_relation_is_a_warning_not_an_error(self):
        checks = self._checks(osm_relation_package())
        self.assertEqual(checks.get('geometry.deviation.osmReferenceRetained'),
                         'WARN')
        self.assertEqual(checks.get('geometry.unchecked.osmReferenceRetained'),
                         'WARN')
        self.assertNotIn('geometry.deviation', checks)
        self.assertNotIn('geometry.unchecked', checks)

    def test_without_the_evidence_chain_it_is_still_an_error(self):
        # The exception is the reviewed evidence, not the word "osm". A line
        # built from a relation nobody audited must not inherit it.
        checks = self._checks(osm_relation_package(with_evidence=False))
        self.assertEqual(checks.get('geometry.deviation'), 'ERROR')
        self.assertEqual(checks.get('geometry.unchecked'), 'ERROR')
        self.assertNotIn('geometry.deviation.osmReferenceRetained', checks)

    def test_osm_is_not_promoted_to_a_verified_official_network(self):
        # The rung must not have been bought by widening provenance.
        package = osm_relation_package()
        findings = audit.Findings()
        verified = audit.verified_official_networks(package, findings)
        self.assertNotIn('osm', verified)


# --------------------------------------------------------------------------
# a colour can be well formed, officially published, and still unusable


class ColourVisibilityTests(unittest.TestCase):
    def _invisible(self, **colours):
        line = straight_line()
        line.update(colours)
        findings = audit.Findings()
        audit.audit_line(line, 'US', findings, {'authority-red'})
        return [row for row in findings.rows
                if row['check'] == 'colour.invisible']

    def test_a_white_railway_is_refused(self):
        # The Loop Trolley's GTFS publishes route_color FFFFFF verbatim, and
        # #ffffff satisfies both older colour checks: it is a six-digit hex
        # value and the feed is an official source for it.
        rows = self._invisible(colorReference='#FFFFFF', color='#FFFFFF',
                               colorDark='#FFFFFF')
        self.assertTrue(rows)
        self.assertEqual({row['severity'] for row in rows}, {'ERROR'})
        self.assertIn('colorReference', {row['field'] for row in rows})

    def test_yellow_is_not_white(self):
        # The reason the rule is colour difference and not WCAG contrast.
        # Against the light basemap pure yellow scores 1.07:1 and pure white
        # 1.00:1 -- and #ffff00 ships today as BART Yellow, the CTA Yellow
        # Line and Metra's UP-NW.
        self.assertFalse(self._invisible(colorReference='#ffff00',
                                         color='#ebeb00',
                                         colorDark='#ffff00'))

    def test_the_palest_colour_the_packages_ship_still_passes(self):
        # Caltrain publishes #dcddde and Pittsburgh's Silver Line #dbdbdb.
        # They are the two closest published colours to the light ground in
        # either package, and both are legitimate.
        for reference in ('#dcddde', '#dbdbdb'):
            self.assertFalse(self._invisible(colorReference=reference,
                                             color='#727579',
                                             colorDark=reference), reference)

    def test_each_drawn_colour_is_judged_against_its_own_theme(self):
        # TexRail publishes #000000, which is a perfectly visible colour on
        # the paper the light map is drawn on; what must not be the ground is
        # the value drawn ON the dark map.
        rows = self._invisible(colorReference='#000000', color='#000000',
                               colorDark='#0d0d0d')
        self.assertEqual([row['field'] for row in rows], ['colorDark'])
        self.assertEqual(rows[0]['theme'], 'dark')


# --------------------------------------------------------------------------
# a branch that redraws its own trunk


def station(name, km, offset_m=0.0):
    """A station row `km` kilometres north of one origin, plus an offset."""
    return ['ca-official-' + name, name,
            -79.4, 43.7 + (km * 1000.0 + offset_m) / 111_132.0]


def rail_line(line_id, stations, trunk=None):
    return {'id': line_id, 'name': 'Line 4', 'stations': stations,
            'branchOf': trunk, 'segments': []}


class BranchDuplicateTests(unittest.TestCase):
    def _flagged(self, lines):
        findings = audit.Findings()
        audit.audit_branch_duplicates({'country': 'CA', 'lines': lines},
                                      findings)
        return {row['line'] for row in findings.rows
                if row['check'] == 'line.branchDuplicatesTrunk'}

    def test_a_branch_that_only_calls_at_the_other_platform(self):
        # ttc-4-b1: Line 4 has five stations and no branches at all, and this
        # pattern's only station the trunk "lacks" is the second id the same
        # platform arrived under.
        self.assertEqual(self._flagged([
            rail_line('ttc-4', [station('don-mills', 0), station('leslie', 1),
                                station('bessarion', 2)]),
            rail_line('ttc-4-b1', [station('don-mills', 0),
                                   station('leslie-2', 1, 230)], 'ttc-4'),
        ]), {'ttc-4-b1'})

    def test_a_branch_that_draws_its_own_railway_is_left_alone(self):
        self.assertEqual(self._flagged([
            rail_line('ttc-4', [station('don-mills', 0), station('leslie', 1),
                                station('bessarion', 2)]),
            rail_line('ttc-4-b1', [station('don-mills', 0),
                                   station('leslie', 1),
                                   station('oriole', 3)], 'ttc-4'),
        ]), set())

    def test_a_stop_of_the_route_between_the_halves_blocks_the_fold(self):
        # Toronto's two stops both called Gerrard St East at Coxwell Ave are
        # 311 m apart and are two real stops on different legs of a junction
        # the route turns through, calling at further stops inside those
        # 311 m. Distance alone would fold them; the route says no.
        self.assertEqual(self._flagged([
            rail_line('ttc-306', [station('coxwell-yard', 0),
                                  station('gerrard-at-coxwell', 1),
                                  station('coxwell-north', 1, 150),
                                  station('woodbine', 2)]),
            rail_line('ttc-306-b1', [station('coxwell-yard', 0),
                                     station('gerrard-at-coxwell-2', 1, 311)],
                      'ttc-306'),
        ]), set())

    def test_two_stations_that_are_two_stations(self):
        # Amtrak's Northeast Regional calls at New Haven Union Station and
        # New Haven State Street, 931 m apart, one route, nothing between
        # them. Only the walkable-complex ceiling keeps them apart.
        self.assertEqual(self._flagged([
            rail_line('amtrak-nec', [station('bridgeport', 0),
                                     station('new-haven', 1),
                                     station('old-saybrook', 3)]),
            rail_line('amtrak-nec-b1', [station('bridgeport', 0),
                                        station('new-haven-2', 1, 931)],
                      'amtrak-nec'),
        ]), set())

    def test_the_id_suffix_alone_is_not_evidence(self):
        # In us-2025, 91 of the 144 numbered pairs are more than 2 km apart
        # and the median is 17 km: belmont-2, hyde-park-2 and chinatown-2 are
        # different cities, not second platforms.
        self.assertEqual(self._flagged([
            rail_line('cta-red', [station('howard', 0),
                                  station('belmont', 1)]),
            rail_line('cta-red-b1', [station('howard', 0),
                                     station('belmont-2', 18)], 'cta-red'),
        ]), set())

    def test_an_official_route_id_is_not_read_as_a_branch(self):
        # SEPTA really does run a route B1. Without `branchOf`, an id is only
        # believed when the trunk it would name is in the package.
        self.assertEqual(self._flagged([
            rail_line('septa-m1', [station('69th-street', 0),
                                   station('parkview', 1),
                                   station('norristown', 2)]),
            rail_line('septa-b1', [station('69th-street', 0),
                                   station('parkview', 1)]),
        ]), set())

    def test_the_fold_only_sees_one_route(self):
        # Spadina is 357 m across with nothing between, and it must keep two
        # anchors: Line 1 calls at one platform and Line 2 at the other, so
        # no single route ever holds both. That is enforced by which stations
        # reach this function -- one route's own.
        line_one = {station('spadina', 0)[0]: (-79.4, 43.7),
                    station('st-george', 1)[0]: (-79.4, 43.709)}
        self.assertEqual(audit.fold_duplicate_stations(line_one), {})
        both = dict(line_one)
        both[station('spadina-2', 0, 357)[0]] = (-79.4, 43.7 + 357 / 111_132.0)
        self.assertEqual(audit.fold_duplicate_stations(both),
                         {'ca-official-spadina': 'ca-official-spadina',
                          'ca-official-spadina-2': 'ca-official-spadina'})

    def test_the_check_runs_as_part_of_the_package_audit(self):
        package = {'country': 'CA', 'lines': [
            rail_line('ttc-4', [station('don-mills', 0), station('leslie', 1),
                                station('bessarion', 2)]),
            rail_line('ttc-4-b1', [station('don-mills', 0),
                                   station('leslie-2', 1, 230)], 'ttc-4'),
        ]}
        findings = audit.Findings()
        audit.audit_package(package, findings, {})
        self.assertIn('line.branchDuplicatesTrunk',
                      {row['check'] for row in findings.rows})


# --------------------------------------------------------------------------
# a package that is simply old


def write(directory, name, text):
    path = os.path.join(directory, name)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)
    return path


def digest_of(path):
    with open(path, 'rb') as handle:
        return hashlib.sha256(handle.read()).hexdigest()


class FreshnessTests(unittest.TestCase):
    def _rows(self, package, registry=None, root='.', networks=None):
        findings = audit.Findings()
        audit.audit_freshness(package, registry, root, networks, findings)
        return findings.rows

    def test_a_package_built_from_what_is_on_disk_says_nothing(self):
        with tempfile.TemporaryDirectory() as root:
            registry = write(root, 'na-feeds.json', '{"feeds": []}')
            package = {'country': 'CA',
                       'buildInputs': {'na-feeds.json': digest_of(registry)}}
            self.assertEqual(self._rows(package, registry, root), [])

    def test_a_registry_that_changed_after_the_build_is_an_error(self):
        # TTC Lines 1 and 2: the registry carried their OpenStreetMap
        # relations and the builder knew what to do with them, and the
        # package that shipped had been built before either was true.
        with tempfile.TemporaryDirectory() as root:
            registry = write(root, 'na-feeds.json', '{"feeds": []}')
            package = {'country': 'CA',
                       'buildInputs': {'na-feeds.json': digest_of(registry)}}
            write(root, 'na-feeds.json', '{"feeds": [{"slug": "ttc"}]}')
            rows = self._rows(package, registry, root)
            self.assertEqual([row['check'] for row in rows], ['package.stale'])
            self.assertEqual(rows[0]['severity'], 'ERROR')

    def test_a_package_that_records_nothing_cannot_be_vouched_for(self):
        with tempfile.TemporaryDirectory() as root:
            registry = write(root, 'na-feeds.json', '{"feeds": []}')
            rows = self._rows({'country': 'CA'}, registry, root)
            self.assertEqual([(row['severity'], row['check']) for row in rows],
                             [('WARN', 'package.freshness')])

    def test_a_manifest_that_covers_everything_but_the_registry(self):
        with tempfile.TemporaryDirectory() as root:
            registry = write(root, 'na-feeds.json', '{"feeds": []}')
            other = write(root, 'stations-ca.json', '{}')
            package = {'country': 'CA',
                       'buildInputs': {'stations-ca.json': digest_of(other)}}
            rows = self._rows(package, registry, root)
            self.assertEqual([(row['severity'], row['check']) for row in rows],
                             [('WARN', 'package.freshness')])

    def test_a_digest_that_is_not_one_is_refused(self):
        with tempfile.TemporaryDirectory() as root:
            registry = write(root, 'na-feeds.json', '{"feeds": []}')
            package = {'country': 'CA',
                       'buildInputs': {'na-feeds.json': 'not-a-digest'}}
            checks = [(row['severity'], row['check'])
                      for row in self._rows(package, registry, root)]
            self.assertIn(('ERROR', 'package.buildInputs'), checks)

    def test_a_renormalised_official_network_is_stale(self):
        # This half needs no builder change: the package already records the
        # SHA-256 `verify_route_networks` took of the extract it routed from.
        with tempfile.TemporaryDirectory() as networks:
            extract = write(networks, 'ttc-subway-1.geojson', '{"type": "F"}')
            package = {'country': 'CA', 'geometrySource': {
                'verifiedOfficialNetworks': {
                    'ttc-subway-1': {'sha256': digest_of(extract)}}}}
            self.assertEqual(self._rows(package, networks=networks), [])
            write(networks, 'ttc-subway-1.geojson', '{"type": "FeatureColl"}')
            rows = self._rows(package, networks=networks)
            self.assertEqual([row['check'] for row in rows], ['package.stale'])
            self.assertEqual(rows[0]['geometrySource'], 'ttc-subway-1')

    def test_the_official_network_check_is_opt_in(self):
        package = {'country': 'CA', 'geometrySource': {
            'verifiedOfficialNetworks': {'ttc-subway-1': {'sha256': 'a' * 64}}}}
        self.assertEqual(self._rows(package), [])


if __name__ == '__main__':
    unittest.main()
