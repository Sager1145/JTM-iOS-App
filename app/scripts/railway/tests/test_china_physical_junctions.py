"""Original-node CN junction regressions, using tiny in-memory source ways."""
import copy
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    'china_physical_junctions', Path(__file__).resolve().parents[1] / 'build-china-physical-junctions.py')
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class ChinaPhysicalJunctionTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.executescript('''
          CREATE TABLE nodes(id INTEGER PRIMARY KEY,lon REAL,lat REAL,tags TEXT,version INTEGER);
          CREATE TABLE ways(id INTEGER PRIMARY KEY,nodes TEXT,tags TEXT,version INTEGER);
        ''')
        self.coordinates = {}
        self.package = {'format': 'compact-v1', 'country': 'CN', 'version': 'test', 'lines': []}
        self.sources = {'schema': 'cn-original-osm-sources/1', 'country': 'CN',
                        'packageVersion': 'test', 'byLine': {}}
        self.registry = {'format': 'jtm-physical-rail-junctions-v1', 'policy': 'Keep the original policy.',
                         'junctions': [{'id': 'jp-existing', 'region': 'jp', 'evidence': ['existing']},
                                       {'id': 'hk-existing', 'region': 'hk'},
                                       {'id': 'mo-existing', 'region': 'mo'}]}

    def tearDown(self):
        self.db.close()

    def node(self, identity, coordinate=None):
        coordinate = coordinate or [110 + identity / 1000, 30]
        self.coordinates[identity] = coordinate
        self.db.execute('INSERT INTO nodes VALUES(?,?,?,?,?)',
                        (identity, *coordinate, '{}', 7))

    def way(self, identity, nodes):
        self.db.execute('INSERT INTO ways VALUES(?,?,?,?)', (identity, json.dumps(nodes), '{}', 4))

    def line(self, identity, intervals, way):
        line = {'id': identity, 'name': identity, 'operator': 'Source operator',
                'railwayClassCode': '11', 'region': 'CN', 'sourceRef': identity,
                'segments': [[1, 0, [self.coordinates[node] for node in nodes]] for nodes in intervals]}
        self.package['lines'].append(line)
        self.sources['byLine'][identity] = {'sourceIntervals': [
            {'nodeIds': nodes, 'edgeWayIds': [way] * (len(nodes) - 1), 'wayVersions': {str(way): 4}}
            for nodes in intervals]}
        return line

    def crossing(self):
        for identity in range(1, 6):
            self.node(identity)
        self.way(10, [1, 2, 3])
        self.way(20, [4, 2, 5])
        self.line('cn-a', [[1, 2, 3]], 10)
        self.line('cn-b', [[4, 2, 5]], 20)

    def build(self):
        return BUILDER.build_junctions(self.db, self.package, self.sources, self.registry)

    def cn_rows(self, registry):
        return [row for row in registry['junctions'] if row.get('region') == 'cn']

    def test_shared_original_node_carries_each_sides_way_membership_and_versions(self):
        self.crossing()
        original = copy.deepcopy(self.registry)
        result, report = self.build()
        rows = self.cn_rows(result)
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row['kind'], 'zeroLength')
        self.assertEqual(row['from']['coordinate'], self.coordinates[2])
        self.assertEqual(row['from']['coordinate'], row['to']['coordinate'])
        self.assertEqual(row['from']['identity']['trackID'], 'cn-a')
        self.assertNotIn('sourceID', row['from']['identity'])
        proof = row['sourceTopology']
        self.assertEqual((proof['nodeId'], proof['nodeVersion']), (2, 7))
        self.assertEqual({item['wayId'] for item in proof['fromAdjacentOriginalWays']}, {10})
        self.assertEqual({item['wayId'] for item in proof['toAdjacentOriginalWays']}, {20})
        self.assertTrue(all(item['version'] == 4 for item in proof['fromAdjacentOriginalWays']))
        self.assertIn(BUILDER.SOURCE_URL, row['evidence'])
        self.assertIsNone(row['validFrom'])
        self.assertIsNone(row['validTo'])
        self.assertEqual(result['policy'], original['policy'])
        self.assertEqual(result['junctions'][:3], original['junctions'])
        self.assertEqual(self.registry, original)
        self.assertEqual(report['counts']['appendedJunctions'], 1)

    def physical_section_fixture(self):
        self.db.execute('CREATE TABLE relations(id INTEGER PRIMARY KEY,members TEXT,tags TEXT,version INTEGER)')
        for identity in range(1,6): self.node(identity)
        self.way(10,[1,2]);self.way(20,[4,5]);self.way(30,[2,3,4])
        self.db.execute('UPDATE ways SET tags=? WHERE id=30',('{"railway":"rail","usage":"branch"}',))
        self.db.execute('INSERT INTO relations VALUES(30,?,?,4)',
            (json.dumps([['w',30,'']]),json.dumps({'type':'route','route':'railway','name':'Source connector'})))
        self.line('cn-a',[[1,2]],10);self.line('cn-b',[[4,5]],20)
        return {'schema':'cn-reviewed-physical-sections/1','source':BUILDER.SOURCE_URL,'sections':[
            {'id':'cn-reviewed-physical-connector','region':'cn',
             'identity':{'trackID':'cn-physical-connector','lineName':'Source connector',
                         'operatorName':'Source operator','railwayClassCode':'11'},
             'institutionTypeCode':'2','sourceRelations':[{'id':30,'version':4}],
             'nodeIds':[2,3,4],'coordinates':[self.coordinates[n] for n in [2,3,4]],
             'nodeVersions':{'2':7,'3':7,'4':7},'edgeWayIds':[30,30],'wayVersions':{'30':4},
             'operatorEvidence':{'kind':'reviewed-official-operating-agency',
                 'urls':['https://www.nra.gov.cn/source-fixture'],
                 'support':'Explicit reviewed source operating agency; legal ownership is not asserted.'},
             'passengerEvidence':{'kind':'reviewed-official-corridor',
                 'sourceRelationIds':[30],'sourceNames':['Source connector'],
                 'urls':['https://www.12306.cn/source-fixture'],
                 'support':'Official named passenger corridor; source relation owns each retained edge.'}}]}

    def test_stationless_original_section_keeps_own_identity_and_exact_junctions(self):
        manifest=self.physical_section_fixture();before=copy.deepcopy(self.package)
        features,proofs=BUILDER.compile_reviewed_physical_sections(self.db,self.package,manifest)
        self.assertEqual(self.package,before)
        self.assertEqual(features[0]['properties']['track_id'],'cn-physical-connector')
        # Swift includes source_id in physical identity; review provenance must
        # not create a different identity from the registry's track endpoint.
        self.assertNotIn('source_id',features[0]['properties'])
        self.assertNotIn('line_id',features[0]['properties'])
        self.assertNotIn('stations',proofs['cn-reviewed-physical-connector'])
        self.assertEqual(features[0]['properties']['source_node_ids'],[['osm-node-2','osm-node-3','osm-node-4']])
        topology={**self.sources,'byPhysicalSection':proofs}
        registry,_=BUILDER.build_junctions(self.db,self.package,topology,self.registry)
        self.assertEqual({r['sourceTopology']['nodeId'] for r in self.cn_rows(registry)},{2,4})
        self.assertTrue(all('cn-physical-connector' in r['lineIDs'] for r in self.cn_rows(registry)))

    def test_stationless_review_cannot_admit_freight_or_unowned_edges(self):
        manifest=self.physical_section_fixture()
        self.db.execute('UPDATE ways SET tags=? WHERE id=30',
                        ('{"railway":"rail","railway:traffic_mode":"freight"}',))
        with self.assertRaisesRegex(ValueError,'inactive|freight'):
            BUILDER.compile_reviewed_physical_sections(self.db,self.package,manifest)
        self.db.execute('UPDATE ways SET tags=? WHERE id=30',('{"railway":"rail"}',))
        self.db.execute('UPDATE relations SET members=? WHERE id=30',('[]',))
        with self.assertRaisesRegex(ValueError,'member|inventory'):
            BUILDER.compile_reviewed_physical_sections(self.db,self.package,manifest)

    def direct_way_section_fixture(self):
        manifest=self.physical_section_fixture();row=manifest['sections'][0]
        self.db.execute('UPDATE ways SET nodes=? WHERE id=30',('[2,3]',))
        self.way(31,[3,4])
        tags={'railway':'rail','name':'Source connector','ref':'0084','operator':'Source operator'}
        self.db.execute('UPDATE ways SET tags=? WHERE id IN (30,31)',(json.dumps(tags),))
        context={'name':'Source connector','ref':'0084','operator':'Context operator'}
        self.db.execute('UPDATE relations SET tags=? WHERE id=30',(json.dumps(context),))
        row['sourceRelations']=[{'id':30,'version':4,**context}]
        row['edgeWayIds']=[30,31];row['wayVersions']={'30':4,'31':4}
        row['sourceOwnership']={'mode':'original-way-identity','ref':'0084'}
        row['operatorEvidence']['kind']='original-way-operator'
        row['passengerEvidence']['support']='Official corridor covers the exact named/ref original ways; relation is context.'
        return manifest

    def test_direct_way_identity_admits_unmembered_way_and_reports_actual_context_membership(self):
        manifest=self.direct_way_section_fixture();before=copy.deepcopy(manifest)
        features,proofs=BUILDER.compile_reviewed_physical_sections(self.db,self.package,manifest)
        self.assertEqual(features[0]['geometry']['coordinates'],[self.coordinates[n] for n in [2,3,4]])
        proof=proofs['cn-reviewed-physical-connector']
        self.assertEqual(proof['sourceOwnership'],{'mode':'original-way-identity','ref':'0084'})
        self.assertEqual(proof['sourceRelationEvidence'],[{
            'id':30,'version':4,'name':'Source connector','ref':'0084',
            'operator':'Context operator','memberPathWayIds':[30]}])
        self.assertEqual(proof['sourceWayEvidence'],[
            {'id':30,'version':4,'name':'Source connector','ref':'0084',
             'operator':'Source operator','sourceRelationIds':[30]},
            {'id':31,'version':4,'name':'Source connector','ref':'0084',
             'operator':'Source operator','sourceRelationIds':[]}])
        self.assertEqual(manifest,before)

    def test_direct_way_identity_requires_exact_name_ref_and_operator_on_every_way(self):
        manifest=self.direct_way_section_fixture()
        manifest['sections'][0]['operatorEvidence']['kind']='reviewed-official-operating-agency'
        original={'railway':'rail','name':'Source connector','ref':'0084','operator':'Source operator'}
        for way in (30,31):
            for field in ('name','ref','operator'):
                for value in (None,'Wrong identity'):
                    tags=dict(original)
                    if value is None: tags.pop(field)
                    else: tags[field]=value
                    self.db.execute('UPDATE ways SET tags=? WHERE id=?',(json.dumps(tags),way))
                    with self.subTest(way=way,field=field,value=value),self.assertRaisesRegex(ValueError,'original way identity'):
                        BUILDER.compile_reviewed_physical_sections(self.db,self.package,manifest)
                    self.db.execute('UPDATE ways SET tags=? WHERE id=?',(json.dumps(original),way))
        for value in (None,'',84):
            changed=copy.deepcopy(manifest);changed['sections'][0]['sourceOwnership']['ref']=value
            with self.subTest(ref=value),self.assertRaisesRegex(ValueError,'original way identity'):
                BUILDER.compile_reviewed_physical_sections(self.db,self.package,changed)

    def test_direct_way_identity_verifies_context_relation_identity_and_version(self):
        manifest=self.direct_way_section_fixture()
        for field,value in [('name','Wrong corridor'),('ref','Wrong ref'),
                            ('operator','Wrong context operator'),('version',5)]:
            changed=copy.deepcopy(manifest);changed['sections'][0]['sourceRelations'][0][field]=value
            with self.subTest(field=field),self.assertRaisesRegex(ValueError,'source relation.*drift'):
                BUILDER.compile_reviewed_physical_sections(self.db,self.package,changed)
        for field in ('name','ref','operator'):
            changed=copy.deepcopy(manifest);changed['sections'][0]['sourceRelations'][0].pop(field)
            with self.subTest(missing=field),self.assertRaisesRegex(ValueError,'source relation.*drift'):
                BUILDER.compile_reviewed_physical_sections(self.db,self.package,changed)

    def physical_station_fixture(self):
        manifest=self.physical_section_fixture()
        self.node(99,self.coordinates[3])
        self.db.execute('UPDATE nodes SET tags=? WHERE id=99',
                        ('{"railway":"station","name":"Source station"}',))
        self.db.execute('UPDATE relations SET members=? WHERE id=30',
                        (json.dumps([['w',30,''],['n',99,'']]),))
        manifest['sections'][0]['stationBindings']=[{
            'markerNodeId':99,'markerVersion':7,'markerCoordinate':self.coordinates[99],
            'officialTelecode':'TST','stationName':'Source station',
            'anchorNodeId':3,'anchorVersion':7}]
        official={'TST':{'telecode':'TST','name':'Source station','source':'12306-station_name.js'}}
        return manifest,official

    def physical_stations(self,manifest,official):
        _,proofs=BUILDER.compile_reviewed_physical_sections(self.db,self.package,manifest)
        return BUILDER.compile_reviewed_physical_station_bindings(self.db,manifest,proofs,official),proofs

    def test_physical_station_member_binding_uses_official_identity_and_original_track_geometry(self):
        manifest,official=self.physical_station_fixture()
        before=copy.deepcopy(manifest)
        features,proofs=self.physical_stations(manifest,official)
        self.assertEqual(len(features),1)
        properties=features[0]['properties']
        self.assertEqual(properties['station_name'],'Source station')
        self.assertEqual(properties['n02_station_code'],'CN-12306-TST')
        self.assertEqual(properties['n02_group_code'],'cn-official-12306-tst')
        self.assertEqual(properties['line_ids'],['cn-physical-connector'])
        self.assertEqual(properties['source_station_node_id'],99)
        self.assertEqual(properties['source_anchor_node_id'],3)
        self.assertEqual(properties['display_point'],self.coordinates[3])
        self.assertEqual(properties['source_node_ids'],[['osm-node-2','osm-node-3','osm-node-4']])
        self.assertNotIn('source_id',properties)
        self.assertEqual(features[0]['geometry']['coordinates'],[self.coordinates[n] for n in [2,3,4]])
        self.assertEqual(proofs[manifest['sections'][0]['id']]['stationBindings'],before['sections'][0]['stationBindings'])
        self.assertEqual(manifest,before)

    def test_physical_station_binding_rejects_wrong_official_code_and_source_drift(self):
        manifest,official=self.physical_station_fixture()
        for field,value in [('officialTelecode','BAD'),('stationName','Wrong station'),
                            ('markerVersion',8),('markerCoordinate',[0,0]),('anchorVersion',8),
                            ('anchorNodeId',1)]:
            changed=copy.deepcopy(manifest);changed['sections'][0]['stationBindings'][0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):
                self.physical_stations(changed,official)
        with self.assertRaises(ValueError):self.physical_stations(manifest,{})
        malformed=copy.deepcopy(official);malformed['TST'].pop('source')
        with self.assertRaises(ValueError):self.physical_stations(manifest,malformed)

    def test_physical_station_binding_requires_actual_member_marker_and_own_path_anchor(self):
        manifest,official=self.physical_station_fixture()
        self.db.execute('UPDATE relations SET members=? WHERE id=30',('[ ["w",30,""] ]',))
        with self.assertRaisesRegex(ValueError,'member'):
            self.physical_stations(manifest,official)
        self.db.execute('UPDATE relations SET members=? WHERE id=30',
                        (json.dumps([['w',30,''],['n',99,'']]),))
        for tags in [{'railway':'switch','name':'Source station'},
                     {'railway':'station','name':'Different station'},
                     {'railway':'station','name':'Source station','station':'freight'}]:
            self.db.execute('UPDATE nodes SET tags=? WHERE id=99',(json.dumps(tags),))
            with self.subTest(tags=tags),self.assertRaises(ValueError):
                self.physical_stations(manifest,official)

    def test_physical_station_binding_preserves_the_existing_1500m_anchor_bound(self):
        manifest,official=self.physical_station_fixture()
        far=[111,31]
        self.db.execute('UPDATE nodes SET lon=?,lat=? WHERE id=99',far)
        manifest['sections'][0]['stationBindings'][0]['markerCoordinate']=far
        with self.assertRaisesRegex(ValueError,'1500|bound'):
            self.physical_stations(manifest,official)

    def test_physical_station_cli_preserves_other_rows_and_validates_before_candidate_writes(self):
        manifest,official=self.physical_station_fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);database=root/'source.sqlite3'
            self.db.commit()
            target=sqlite3.connect(database);self.db.backup(target)
            target.execute('CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT)')
            target.executemany('INSERT INTO metadata VALUES(?,?)',[
                ('source','/pinned/china-261017.osm.pbf'),('counts','{"nodes":6,"ways":3}')])
            target.commit();target.close()
            retained={'type':'Feature','properties':{'region':'JP','station_name':'Existing'},
                      'geometry':{'type':'LineString','coordinates':[[1,1],[2,2]]}}
            old_owned={'type':'Feature','properties':{'region':'CN','source_review_id':manifest['sections'][0]['id']},
                       'geometry':{'type':'LineString','coordinates':[[3,3],[4,4]]}}
            documents={'package':self.package,'topology':self.sources,'registry':self.registry,
                       'physical':manifest,'sections':{'type':'FeatureCollection','features':[]},
                       'stations':{'type':'FeatureCollection','features':[retained,old_owned]},
                       'official':{'records':list(official.values())}}
            for name,document in documents.items():(root/(name+'.json')).write_text(json.dumps(document))
            original_stations=(root/'stations.json').read_bytes()
            args=['builder','--database',str(database),'--package',str(root/'package.json'),
                  '--source-topology',str(root/'topology.json'),'--registry',str(root/'registry.json'),
                  '--output',str(root/'candidate.json'),'--reviewed-physical-sections',str(root/'physical.json'),
                  '--sections',str(root/'sections.json'),'--sections-output',str(root/'candidate-sections.json'),
                  '--source-output',str(root/'candidate-topology.json'),'--stations',str(root/'stations.json'),
                  '--stations-output',str(root/'candidate-stations.json'),'--official-stations',str(root/'official.json')]
            with patch('sys.argv',args),redirect_stdout(io.StringIO()):BUILDER.main()
            station_features=json.loads((root/'candidate-stations.json').read_text())['features']
            self.assertEqual(station_features[0],retained)
            self.assertEqual(len(station_features),2)
            self.assertEqual(station_features[1]['properties']['source_anchor_node_id'],3)
            self.assertEqual((root/'stations.json').read_bytes(),original_stations)
            colliding=list(args);colliding[colliding.index('--output')+1]=str(root/'stations.json')
            with patch('sys.argv',colliding),redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                BUILDER.main()
            self.assertEqual((root/'stations.json').read_bytes(),original_stations)
            manifest['sections'][0]['stationBindings'][0]['officialTelecode']='BAD'
            (root/'physical.json').write_text(json.dumps(manifest))
            before={path:path.read_bytes() for path in root.glob('candidate*.json')}
            with patch('sys.argv',args),self.assertRaises(ValueError):BUILDER.main()
            self.assertEqual({path:path.read_bytes() for path in before},before)

    def test_coordinate_coincidence_between_distinct_original_nodes_never_connects(self):
        for identity in range(1, 5):
            self.node(identity, [110.02, 30] if identity in (2, 3) else None)
        self.way(10, [1, 2])
        self.way(20, [3, 4])
        self.line('cn-a', [[1, 2]], 10)
        self.line('cn-b', [[3, 4]], 20)
        result, report = self.build()
        self.assertEqual(self.cn_rows(result), [])
        self.assertEqual(report['counts']['sharedOriginalNodes'], 0)

    def test_explicit_refresh_removes_only_stale_rows_owned_by_this_source_builder(self):
        self.crossing()
        previous, _ = self.build()
        manual = {'id': 'cn-reviewed-manual', 'region': 'cn', 'evidence': ['retained review']}
        previous['junctions'].append(manual)
        self.package['lines'] = self.package['lines'][:1]
        result, report = BUILDER.build_junctions(self.db, self.package, self.sources, previous,
                                               replace_generated_cn=True)
        self.assertEqual(result['junctions'], [*self.registry['junctions'], manual])
        self.assertEqual(report['counts']['replacedGeneratedRows'], 1)
        self.assertEqual(len(previous['junctions']), 5)

    def test_nonconsecutive_way_nodes_are_withheld_instead_of_repaired(self):
        self.crossing()
        source = self.sources['byLine']['cn-b']['sourceIntervals'][0]
        source['edgeWayIds'] = [10, 10]
        source['wayVersions'] = {'10': 4}
        result, report = self.build()
        self.assertEqual(self.cn_rows(result), [])
        self.assertIn('not adjacent in original way', report['withheld'][0]['reason'])

    def test_changed_coordinate_or_way_version_withholds_the_affected_line(self):
        self.crossing()
        self.package['lines'][1]['segments'][0][2] = [[111, 31], self.coordinates[2], self.coordinates[5]]
        result, report = self.build()
        self.assertEqual(self.cn_rows(result), [])
        self.assertIn('coordinate differs from original WGS84', report['withheld'][0]['reason'])
        self.package['lines'][1]['segments'][0][2][0] = self.coordinates[4]
        self.sources['byLine']['cn-b']['sourceIntervals'][0]['wayVersions']['20'] = 5
        result, report = self.build()
        self.assertEqual(self.cn_rows(result), [])
        self.assertIn('version mismatch', report['withheld'][0]['reason'])

    def test_same_runtime_coordinate_has_two_original_nodes_on_one_identity(self):
        self.crossing()
        self.node(9, [self.coordinates[2][0] + 0.000001, 30])
        self.way(30, [1, 2, 9, 3])
        self.package['lines'].pop(0)
        self.sources['byLine'].pop('cn-a')
        self.line('cn-a', [[1, 2, 9, 3]], 30)
        result, report = self.build()
        self.assertEqual(self.cn_rows(result), [])
        ambiguity = next(item for item in report['withheld'] if item.get('nodeId') == 2)
        self.assertEqual(ambiguity['originalNodeIds'], [2, 9])

    def test_shared_runs_compress_to_interval_ends_and_original_branch_nodes(self):
        for identity in range(1, 9):
            self.node(identity)
        self.way(10, [1, 2, 3, 4, 5, 6, 7])
        self.way(20, [4, 8])
        self.line('cn-a', [[1, 2, 3], [3, 4, 5, 6, 7]], 10)
        self.line('cn-b', [[1, 2, 3, 4, 5, 6, 7]], 10)
        self.line('cn-c', [[4, 8]], 20)
        result, report = self.build()
        rows = self.cn_rows(result)
        self.assertEqual({row['sourceTopology']['nodeId'] for row in rows}, {1, 3, 4, 7})
        self.assertEqual(len([row for row in rows if row['sourceTopology']['nodeId'] == 4]), 2)
        self.assertEqual(report['counts']['sharedOriginalNodes'], 7)
        shuffled = copy.deepcopy(self.package)
        shuffled['lines'].reverse()
        again, _ = BUILDER.build_junctions(self.db, shuffled, self.sources, self.registry)
        self.assertEqual(result, again)

    def test_foreign_region_never_participates_and_repeat_output_preserves_peers(self):
        self.crossing()
        self.package['lines'][1]['region'] = 'HK'
        result, report = self.build()
        self.assertEqual(self.cn_rows(result), [])
        self.assertIn('not owned exclusively by CN', report['withheld'][0]['reason'])
        self.package['lines'][1]['region'] = 'CN'
        first, _ = self.build()
        second, report = BUILDER.build_junctions(self.db, self.package, self.sources, first)
        self.assertEqual(first, second)
        self.assertEqual(report['counts']['appendedJunctions'], 0)
        conflicting = copy.deepcopy(first)
        conflicting['junctions'][-1]['validFrom'] = '2000-01-01'
        with self.assertRaisesRegex(ValueError, 'conflicts with source candidate'):
            BUILDER.build_junctions(self.db, self.package, self.sources, conflicting)

    def test_cli_writes_a_candidate_and_report_without_changing_registry_input(self):
        self.crossing()
        self.db.commit()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / 'source.sqlite3'
            target = sqlite3.connect(path)
            self.db.backup(target)
            target.execute('CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT)')
            target.executemany('INSERT INTO metadata VALUES(?,?)', [
                ('source', '/pinned/china-261017.osm.pbf'), ('counts', '{"nodes":5,"ways":2}')])
            target.commit()
            target.close()
            for name, value in [('package', self.package), ('topology', self.sources), ('registry', self.registry)]:
                (root / (name + '.json')).write_text(json.dumps(value))
            original = (root / 'registry.json').read_bytes()
            output = root / 'candidate.json'
            arguments = ['build-china-physical-junctions.py', '--database', str(path),
                         '--package', str(root / 'package.json'), '--source-topology', str(root / 'topology.json'),
                         '--registry', str(root / 'registry.json'), '--output', str(output)]
            with patch('sys.argv', arguments), redirect_stdout(io.StringIO()):
                BUILDER.main()
            self.assertEqual((root / 'registry.json').read_bytes(), original)
            self.assertEqual(len(self.cn_rows(json.loads(output.read_text()))), 1)
            report = json.loads((root / 'candidate.report.json').read_text())
            self.assertEqual(report['counts']['appendedJunctions'], 1)

    def reviewed_fixture(self):
        for identity in range(1, 6):
            self.node(identity)
        for way, nodes in [(10, [1, 2]), (20, [4, 5]), (30, [2, 3, 4])]:
            self.way(way, nodes)
        self.db.execute('UPDATE ways SET tags=? WHERE id=30',
                        (json.dumps({'railway': 'rail', 'railway:traffic_mode': 'passenger'}),))
        first = self.line('cn-a', [[1, 2]], 10)
        second = self.line('cn-b', [[4, 5]], 20)
        self.sources['byLine']['cn-a']['sourceWayIds'] = [10, 30]
        return {'schema': 'cn-reviewed-connections/1', 'source': BUILDER.SOURCE_URL,
                'connections': [{'id': 'cn-reviewed-harbin-test', 'reviewedAt': '2026-10-18',
                    'from': {'lineId': 'cn-a', 'identity': BUILDER.endpoint_identity(first), 'nodeId': 2,
                             'segmentIndex': 0, 'vertexIndex': 1},
                    'to': {'lineId': 'cn-b', 'identity': BUILDER.endpoint_identity(second), 'nodeId': 4,
                           'segmentIndex': 0, 'vertexIndex': 0},
                    'nodeIds': [2, 3, 4], 'coordinates': [self.coordinates[n] for n in [2, 3, 4]],
                    'nodeVersions': {'2': 7, '3': 7, '4': 7}, 'edgeWayIds': [30, 30],
                    'wayVersions': {'30': 4}, 'attachMeters': {'from': 0, 'to': 0},
                    'passengerEvidence': {'urls': ['https://kyfw.12306.cn/otn/queryTrainInfo/query?fixture'],
                        'scope': 'Same-train passenger continuity; intermediate track is not specified.'},
                    'station': 'Source station', 'stationCode': 'CN-12306-TEST'}]}

    def reviewed_build(self, manifest, registry=None):
        return BUILDER.build_reviewed_connections(
            self.db, self.package, self.sources, registry or self.registry, manifest)

    def test_reviewed_original_lead_in_keeps_station_paths_and_exact_end_junction(self):
        manifest = self.reviewed_fixture()
        original = copy.deepcopy(self.package)
        result, report = self.reviewed_build(manifest)
        row = self.cn_rows(result)[0]
        self.assertEqual(row['kind'], 'osmTrack')
        self.assertEqual(row['path'], manifest['connections'][0]['coordinates'])
        self.assertEqual(row['attachMeters'], {'from': 0, 'to': 0})
        self.assertEqual(row['endJunction'], {'end': 'to', **row['to']})
        self.assertIsNone(row['validFrom'])
        self.assertEqual(row['sourceTopology']['nodeVersions']['3'], 7)
        self.assertEqual(self.package, original)
        self.assertEqual(result['junctions'][:3], self.registry['junctions'])
        self.assertEqual(report['counts']['generatedJunctions'], 1)
        again, _ = self.reviewed_build(manifest, result)
        self.assertEqual(again, result)

    def test_reviewed_source_or_attachment_drift_is_rejected(self):
        manifest = self.reviewed_fixture()
        variants = []
        for field, value in [('coordinates', [[0, 0], self.coordinates[3], self.coordinates[4]]),
                             ('nodeVersions', {'2': 7, '3': 8, '4': 7}),
                             ('wayVersions', {'30': 5}), ('edgeWayIds', [10, 30]),
                             ('attachMeters', {'from': 0, 'to': 1})]:
            changed = copy.deepcopy(manifest)
            changed['connections'][0][field] = value
            variants.append(changed)
        changed = copy.deepcopy(manifest)
        changed['connections'][0]['to']['identity']['lineName'] = 'wrong target'
        variants.append(changed)
        changed = copy.deepcopy(manifest)
        changed['connections'][0]['to']['nodeId'] = 5
        variants.append(changed)
        changed = copy.deepcopy(manifest)
        changed['connections'][0]['to']['vertexIndex'] = 1
        variants.append(changed)
        for changed in variants:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.reviewed_build(changed)

    def test_reviewed_path_accepts_explicit_passenger_lines_but_rejects_conflicting_freight(self):
        manifest = self.reviewed_fixture()
        self.db.execute('UPDATE ways SET tags=? WHERE id=30',
                        (json.dumps({'railway':'rail','passenger_lines':'2'}),))
        result, _ = self.reviewed_build(manifest)
        self.assertEqual(len(result['junctions']),len(self.registry['junctions'])+1)
        self.db.execute('UPDATE ways SET tags=? WHERE id=30',
                        (json.dumps({'railway':'rail','passenger_lines':'2','railway:traffic_mode':'freight'}),))
        with self.assertRaisesRegex(ValueError,'passenger rail tags'):
            self.reviewed_build(manifest)

    def test_reviewed_path_rejects_unknown_passenger_use_and_foreign_corridor_inventory(self):
        manifest = self.reviewed_fixture()
        self.db.execute('UPDATE ways SET tags=? WHERE id=30', ('{"railway":"rail"}',))
        with self.assertRaisesRegex(ValueError, 'passenger rail tags'):
            self.reviewed_build(manifest)
        self.db.execute('UPDATE ways SET tags=? WHERE id=30',
                        ('{"railway":"rail","railway:traffic_mode":"passenger"}',))
        self.sources['byLine']['cn-a']['sourceWayIds'] = [10]
        with self.assertRaisesRegex(ValueError, 'outside its source corridor'):
            self.reviewed_build(manifest)

    def test_reviewed_refresh_only_replaces_its_own_row_and_rejects_manual_collision(self):
        manifest = self.reviewed_fixture()
        first, _ = self.reviewed_build(manifest)
        previous = copy.deepcopy(first)
        previous['junctions'][-1]['geometryEvidence'] = 'old generated wording'
        manual = {'id': 'cn-manual', 'region': 'cn'}
        previous['junctions'].append(manual)
        refreshed, _ = self.reviewed_build(manifest, previous)
        self.assertIn(manual, refreshed['junctions'])
        self.assertEqual(self.cn_rows(refreshed)[-1], self.cn_rows(first)[0])
        previous['junctions'][-2].pop('sourceTopology')
        with self.assertRaisesRegex(ValueError, 'conflicts'):
            self.reviewed_build(manifest, previous)


if __name__ == '__main__':
    unittest.main()
