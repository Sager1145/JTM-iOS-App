import copy
import importlib.util
import json
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'repair-tokyo-southern-branches.py'
spec = importlib.util.spec_from_file_location('tokyo_southern_branches', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SouthernBranchEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = json.loads(module.EVIDENCE.read_text())
        cls.package = json.loads((module.ROOT/'public/rail/jp-2025.json').read_text())

    def test_source_gap_refuses_candidate(self):
        evidence = copy.deepcopy(self.evidence)
        first = str(evidence['paths']['southbound']['branch'][1])
        evidence['ways'][first]['coordinates'][0][0] += 0.00001
        with self.assertRaisesRegex(AssertionError, 'Unsurveyed gap'):
            module.reviewed_tracks(evidence)

    def test_only_existing_osaki_and_nishi_oi_memberships(self):
        result = module.repair(self.package, self.evidence)
        candidates = [l for l in result['lines'] if l['id'] in [module.BASE_ID, module.PAIR_ID]]
        self.assertEqual(len(candidates), 2)
        for line in candidates:
            self.assertEqual([(s[0], s[1]) for s in line['stations']],
                             [('004135', '大崎'), ('004235', '西大井')])
            geometry = line['segments'][0][2]
            self.assertEqual(geometry[0], line['stations'][0][2:4])
            self.assertEqual(geometry[-1], line['stations'][1][2:4])
            self.assertEqual(line['displayBranchLeadIns'][0][-1], geometry[0])
            self.assertEqual(line['displayBranchLeadIns'][0][0],
                             line['southernBranchTopology']['northJunction'])
            self.assertIn(line['southernBranchTopology']['southJunction'], geometry)
            self.assertGreater(line['segments'][0][0], 2.4)
            self.assertLess(line['segments'][0][0], 2.7)

    def test_directions_are_separate_surveys_not_a_mirror(self):
        result = module.repair(self.package, self.evidence)
        south = next(l for l in result['lines'] if l['id'] == module.BASE_ID)
        north = next(l for l in result['lines'] if l['id'] == module.PAIR_ID)
        self.assertEqual(south['permittedTraversal'], 'forward')
        self.assertEqual(north['permittedTraversal'], 'reverse')
        self.assertNotEqual(south['segments'][0][2], north['segments'][0][2])
        self.assertNotEqual(south['southernBranchTopology']['northJunction'],
                            north['southernBranchTopology']['northJunction'])
        self.assertEqual(north['alignmentOf'], module.BASE_ID)

    def test_no_shared_package_mutation_and_idempotent_repair(self):
        before = copy.deepcopy(self.package)
        once = module.repair(self.package, self.evidence)
        self.assertEqual(self.package, before)
        self.assertEqual(module.repair(once, self.evidence), once)
        existing = {l['id']: l for l in before['lines'] if l['id'] not in [module.BASE_ID, module.PAIR_ID]}
        after = {l['id']: l for l in once['lines'] if l['id'] in existing}
        self.assertEqual(existing, after)

    def test_junctions_have_exact_adjoining_running_track(self):
        evidence = self.evidence
        main = module.reviewed_freight_main(evidence)
        for track in module.reviewed_tracks(evidence):
            self.assertIn(track['northJunction'], main)
        result = module.repair(self.package, evidence)
        owner = next(row for row in result['lines'] if row['id'] == module.BASE_ID)
        shown = owner['displayBranchLeadIns'][1]
        self.assertEqual(shown[0], [139.7328, 35.61677])
        self.assertEqual(shown[-1], [139.72321, 35.62672])
        self.assertEqual(owner['displayFreightMainPolicy']['sourceVertexCount'], 99)
        self.assertLess(owner['displayFreightMainPolicy']['startAliasMeters'], 4)
        self.assertLess(owner['displayFreightMainPolicy']['endAliasMeters'], 14)
        self.assertTrue(all(point[1] < 35.628135 for point in shown))
        for track in module.reviewed_tracks(evidence):
            self.assertIn(track['northJunction'], shown)
        self.assertEqual(len(owner['stations']), 2)
        for direction, p in evidence['paths'].items():
            branch = module.concatenate(evidence, p['branch'])
            continuation = module.concatenate(evidence, p['continuation'])
            adjoining = module.concatenate(evidence, p['northAdjoining'])
            if direction == 'southbound':
                self.assertEqual(adjoining[-1], branch[0])
                self.assertEqual(branch[-1], continuation[0])
            else:
                self.assertEqual(continuation[-1], branch[0])
                self.assertEqual(branch[-1], adjoining[0])

    def test_legacy_station_schema_and_replay(self):
        path = module.ROOT/'data/stations.json'
        stations = json.loads(path.read_text())
        result = module.repair_stations(stations, self.package)
        expected = {'railway_class_code', 'institution_type_code', 'line_name',
                    'operator', 'station_name', 'n02_station_code', 'n02_group_code',
                    'display_point', 'display_line_id'}
        supplement = [f for f in result['features'] if f.get('jtm_override') == 'tokyo-southern-branches']
        self.assertEqual(len(supplement), 4)
        for feature in supplement:
            self.assertEqual(set(feature['properties']), expected)
            self.assertIn(feature['properties']['display_line_id'], (module.BASE_ID, module.PAIR_ID))
        self.assertEqual(module.repair_stations(result, self.package), result)

    def test_legacy_display_reuses_old_corridors_and_keeps_physical_intervals(self):
        original = module.repair(self.package, self.evidence)
        result = module.integrate_legacy_display(copy.deepcopy(original), self.evidence)
        rows = {l['id']: l for l in result['lines']}
        for before, after in zip(original['lines'], result['lines']):
            self.assertEqual(before['stations'], after['stations'])
            self.assertEqual(before['segments'], after['segments'])
        for name in (module.BASE_ID, module.PAIR_ID):
            row = rows[name]
            aliases = row['southernBranchTopology']['displayAliases']
            self.assertEqual(len(row['displayBranchLeadIns']), 1)
            self.assertIn(aliases['northJunction'], rows[module.JR+'山手線']['displayIntervalCoordinates']['1'])
            self.assertIn(aliases['southJunction'], rows[module.JR+'総武線-3']['displayIntervalCoordinates']['2'])
            own = row['displayIntervalCoordinates']['0']
            main = rows[module.JR+'総武線-3']['displayIntervalCoordinates']['2']
            self.assertEqual(own[own.index(aliases['southJunction']):], main[main.index(aliases['southJunction']):])
        pair = rows[module.BASE_ID]['alignmentPairs'][0]
        self.assertEqual(pair['with'], module.PAIR_ID)
        self.assertEqual(pair['direction'], 'unassigned')


if __name__ == '__main__':
    unittest.main()
