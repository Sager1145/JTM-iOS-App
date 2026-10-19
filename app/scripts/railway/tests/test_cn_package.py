"""Small topology regressions; fixtures never create edges from station names."""
import json
import hashlib
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cn_package import ChinaBuilder, write_outputs, resolve_line_sources


class ChinaPackageTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.executescript('''
          CREATE TABLE nodes(id INTEGER PRIMARY KEY,lon REAL,lat REAL,tags TEXT,version INTEGER);
          CREATE TABLE ways(id INTEGER PRIMARY KEY,nodes TEXT,tags TEXT,version INTEGER);
          CREATE TABLE relations(id INTEGER PRIMARY KEY,members TEXT,tags TEXT,version INTEGER);
          CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT);
        ''')
        self.tmp = tempfile.TemporaryDirectory()
        self.official = Path(self.tmp.name)
        (self.official / '12306-national-stations.json').write_text(json.dumps({'records':[
            {'name':'甲','telecode':'AAA','pinyin':'jia'},
            {'name':'乙','telecode':'BBB','pinyin':'yi'},
            {'name':'丙','telecode':'CCC','pinyin':'bing'}]}))

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def node(self, id, x, name=None, **tags):
        if name: tags.update(name=name, railway='station', train='yes')
        self.db.execute('INSERT INTO nodes VALUES(?,?,?,?,1)', (id, x, 30, json.dumps(tags)))

    def way(self, id, nodes, **tags):
        self.db.execute('INSERT INTO ways VALUES(?,?,?,1)', (id,json.dumps(nodes),json.dumps({'railway':'rail', **tags})))

    def route(self, id, members, **tags):
        self.db.execute('INSERT INTO relations VALUES(?,?,?,1)', (id,json.dumps(members),json.dumps({'type':'route','route':'train','name':'测试铁路','operator':'测试铁路公司', **tags})))

    def build(self):
        return ChinaBuilder(self.db, self.official).build()

    def reviewed(self, **extra):
        review={'schema':'cn-reviewed-station-bindings/1','stations':[
            {'markerNodeId':1,'markerVersion':1,'officialTelecode':'AAA',
             'sourceRelations':[{'id':20,'version':1}],
             'evidence':['https://kyfw.12306.cn/otn/queryTrainInfo/query?train_no=fixture'],
             **extra}]}
        path=self.official/'reviewed-stations.json'
        path.write_text(json.dumps(review))
        return path

    def test_reviewed_station_identity_keeps_distant_homonym_local(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙')
        self.node(3,111,'甲');self.node(4,111.01,'丙')
        self.way(10,[1,2]);self.way(11,[3,4])
        self.route(20,[['n',1,''],['w',10,''],['n',2,'']],route='railway')
        self.route(21,[['n',3,''],['w',11,''],['n',4,'']],route='railway')
        result=ChinaBuilder(self.db,self.official,reviewed_stations=self.reviewed()).build()
        self.assertEqual(len(result['package']['lines']),2)
        stations=[s for l in result['package']['lines'] for s in l['sourceStations']]
        self.assertEqual([s['markerNodeId'] for s in stations if s['officialTelecode']=='AAA'],[1])
        self.assertIsNone(next(s for s in stations if s['markerNodeId']==3)['officialTelecode'])

    def test_reviewed_operating_station_retains_original_construction_tag(self):
        self.node(1,110,'甲',construction='station');self.node(2,110.01,'乙')
        self.way(10,[1,2]);self.route(20,[['n',1,''],['w',10,''],['n',2,'']],route='railway')
        self.assertEqual(self.build()['package']['lines'],[])
        result=ChinaBuilder(self.db,self.official,
            reviewed_stations=self.reviewed(operatingStationDespiteConstructionTag=True)).build()
        station=result['package']['lines'][0]['sourceStations'][0]
        self.assertEqual(station['markerTags']['construction'],'station')
        self.assertEqual(station['reviewedStationBinding']['markerNodeId'],1)
        self.assertEqual(result['package']['lines'][0]['sourceIntervals'][0]['nodeIds'],[1,2])

    def test_reviewed_station_rejects_source_marker_version_drift(self):
        self.node(1,110,'甲');self.way(10,[1,2]);self.route(20,[['n',1,''],['w',10,'']])
        path=self.reviewed();self.db.execute('UPDATE nodes SET version=2 WHERE id=1')
        with self.assertRaisesRegex(ValueError,'marker.*drift'):
            ChinaBuilder(self.db,self.official,reviewed_stations=path)

    def test_exact_original_node_path_and_official_identity(self):
        self.node(1,110,'甲');self.node(2,110.01);self.node(3,110.02,'乙')
        self.way(10,[1,2,3]);self.route(20,[['n',1,'stop'],['w',10,''],['n',3,'stop']])
        result=self.build();line=result['package']['lines'][0]
        self.assertEqual([s[0] for s in line['stations']],['cn-official-12306-aaa','cn-official-12306-bbb'])
        self.assertEqual(line['sourceIntervals'][0]['nodeIds'],[1,2,3])
        self.assertEqual(line['stations'][0][5],3)
        self.assertEqual(result['sections']['features'][0]['properties']['railway_class_code'],'11')
        self.assertEqual(result['sections']['features'][0]['properties']['institution_type_code'],'2')
        self.assertEqual(line['segments'][0][2],[[110,30],[110.01,30],[110.02,30]])
        self.assertEqual(result['stations']['features'][0]['properties']['n02_station_code'],'CN-12306-AAA')
        self.assertEqual(result['sections']['features'][0]['properties']['line_ids'],[line['id']])
        self.assertEqual(result['sections']['features'][0]['properties']['source_node_ids'],[['osm-node-1','osm-node-2','osm-node-3']])
        self.assertEqual(result['sections']['features'][0]['properties']['track_id'],line['id'])

    def test_closed_source_cycle_has_unique_memberships_and_retains_closing_path(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙');self.node(3,110.02,'丙')
        self.db.execute('UPDATE nodes SET lat=30.01 WHERE id=3')
        self.way(10,[1,2,3,1]);self.route(20,[['w',10,'']],route='railway')
        result=self.build();line=result['package']['lines'][0]
        self.assertEqual(line.get('isLoop'),1)
        self.assertEqual(len(line['stations']),3)
        self.assertEqual(len({row[0] for row in line['stations']}),3)
        self.assertEqual(len(line['sourceStations']),3)
        self.assertEqual(len(line['segments']),3)
        paths=[interval['nodeIds'] for interval in line['sourceIntervals']]
        self.assertEqual(paths[-1][-1],paths[0][0])
        self.assertEqual(len(result['stations']['features']),3)
        self.assertEqual(result['coverage']['published'][0]['stations'],3)
        self.assertEqual(len(result['sections']['features']),3)

    def test_foreign_country_and_operator_evidence_withhold_whole_source(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙')
        self.way(10,[1,2]);self.route(20,[['w',10,'']],route='railway')
        for source_tags,owner in [({'addr:country':'VN'},'VN'),
                ({'country':'US'},'US'),
                ({'operator':'조선민주주의인민공화국 철도성'},'KP'),
                ({'operator':'РЖД','operator:en':'Russian Railways'},'RU')]:
            with self.subTest(source_tags=source_tags):
                tags={'type':'route','route':'railway','name':'测试铁路','operator':'测试铁路公司',**source_tags}
                self.db.execute('UPDATE relations SET tags=? WHERE id=20',(json.dumps(tags),))
                result=self.build()
                self.assertEqual(result['package']['lines'],[])
                self.assertEqual(result['coverage']['excludedRegionRoutes'][0]['owner'],owner)

    def test_foreign_member_way_withholds_mixed_international_source(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙');self.node(3,110.02,'丙')
        self.way(10,[1,2],**{'addr:country':'CN'})
        self.way(11,[2,3],**{'addr:country':'LA'})
        self.route(20,[['w',10,''],['w',11,'']],route='railway')
        result=self.build()
        self.assertEqual(result['package']['lines'],[])
        self.assertEqual(result['coverage']['excludedRegionRoutes'][0]['owner'],'LA')

    def test_offtrack_foreign_station_marker_is_ownership_evidence(self):
        self.node(1,110);self.node(2,110.01,'乙');self.node(3,110.00001,'甲',**{'addr:country':'VN'})
        self.way(10,[1,2]);self.route(20,[['n',3,'station'],['w',10,''],['n',2,'station']],route='railway')
        result=self.build()
        self.assertEqual(result['package']['lines'],[])
        self.assertEqual(result['coverage']['excludedRegionRoutes'][0]['owner'],'VN')

    def test_foreign_destination_name_does_not_assign_foreign_ownership(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙');self.way(10,[1,2])
        self.route(20,[['w',10,'']],route='railway',name='Railway to Vietnam',operator='中国铁路',country='ZZ')
        self.assertEqual(len(self.build()['package']['lines']),1)

    def test_coincident_coordinates_never_weld_distinct_node_ids(self):
        self.node(1,110,'甲');self.node(2,110.01);self.node(3,110.01);self.node(4,110.02,'乙')
        self.way(10,[1,2]);self.way(11,[3,4]);self.route(20,[['n',1,'stop'],['w',10,''],['w',11,''],['n',4,'stop']])
        result=self.build()
        self.assertEqual(result['package']['lines'],[])
        self.assertTrue(any('disconnected' in x['reason'] for x in result['coverage']['unresolved']))

    def test_valid_interval_publishes_even_if_later_interval_is_disconnected(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙');self.node(3,111,'丙');self.node(4,111.01)
        self.way(10,[1,2]);self.way(11,[3,4]);self.route(20,[['n',1,'stop'],['n',2,'stop'],['n',3,'stop'],['w',10,''],['w',11,'']])
        result=self.build()
        self.assertEqual(len(result['package']['lines']),1)
        self.assertEqual(len(result['package']['lines'][0]['stations']),2)
        self.assertTrue(result['coverage']['unresolved'])

    def test_stop_area_actual_track_node_binds_marker_without_chord(self):
        self.node(1,110);self.node(2,110.01);self.node(3,110.02,'乙');self.node(4,110.001,'甲')
        self.way(10,[1,2,3]);self.route(20,[['w',10,'']],route='railway')
        self.db.execute('INSERT INTO relations VALUES(?,?,?,1)',(30,json.dumps([['n',1,'stop'],['n',4,'']]),json.dumps({'type':'public_transport','public_transport':'stop_area','name':'甲'})))
        result=self.build();line=result['package']['lines'][0]
        self.assertEqual(line['stations'][0][2:4],[110,30])
        self.assertEqual(line['sourceStations'][0]['markerNodeId'],4)
        self.assertEqual(line['sourceStations'][0]['stopAreaIds'],[30])

    def test_offtrack_members_choose_one_common_original_track_component(self):
        for id,x in [(1,110),(2,110.02),(3,110),(4,110.02)]: self.node(id,x)
        self.db.execute('UPDATE nodes SET lat=30.001 WHERE id IN (3,4)')
        self.node(5,110,'甲');self.node(6,110.02,'乙')
        self.db.execute('UPDATE nodes SET lat=30.001 WHERE id=6')
        self.way(10,[1,2]);self.way(11,[3,4])
        self.route(20,[['n',5,'station'],['n',6,'station'],['w',10,''],['w',11,'']])
        result=self.build()
        self.assertEqual(len(result['package']['lines']),1)
        self.assertIn(result['package']['lines'][0]['sourceIntervals'][0]['nodeIds'],[[1,2],[3,4]])

    def test_unlabelled_foreign_core_transit_excluded_by_ownership_only(self):
        for number,(lon,lat) in enumerate([(114.17,22.30),(113.57,22.15),(121.5,25.0)],1):
            left=number*10;right=left+1
            self.node(left,lon,'甲');self.node(right,lon+.001,'乙')
            self.db.execute('UPDATE nodes SET lat=? WHERE id IN (?,?)',(lat,left,right))
            self.way(number,[left,right]);self.route(number,[['n',left,'stop'],['w',number,''],['n',right,'stop']],route='subway')
        result=self.build()
        self.assertEqual(result['package']['lines'],[])
        self.assertEqual({row['owner'] for row in result['coverage']['excludedRegionRoutes']},{'HK','MO','TW'})

    def test_shenzhen_transit_stays_cn(self):
        self.node(1,114.05,'甲');self.node(2,114.051,'乙')
        self.db.execute('UPDATE nodes SET lat=22.54')
        self.way(10,[1,2]);self.route(20,[['n',1,'stop'],['w',10,''],['n',2,'stop']],route='subway')
        result=self.build()
        self.assertEqual(len(result['package']['lines']),1)
        self.assertEqual(result['package']['lines'][0]['n02Classification'],'3')

    def test_reviewed_gsh_only_hong_kong_override(self):
        self.node(1,114.17,'甲');self.node(2,114.18,'乙')
        self.db.execute('UPDATE nodes SET lat=22.3')
        self.way(10,[1,2],highspeed='yes')
        self.route(20,[['w',10,'']],name='广深港高速铁路',operator='港鐵')
        (self.official/'guangzhou-shenzhen-hongkong-stations.json').write_text(json.dumps({'stations':[
            {'name':'甲','telecode':'AAA','pinyin':'jia','coordinateEvidence':{'osmId':1}},
            {'name':'乙','telecode':'BBB','pinyin':'yi','coordinateEvidence':{'osmId':2}}]}))
        result=self.build()
        self.assertEqual(result['package']['lines'][0]['id'],'cn-guangshengan-hsr')
        self.assertEqual(result['package']['lines'][0]['operator'],'中国铁路／港铁')
        self.assertEqual(result['sections']['features'][0]['properties']['railway_class_code'],'12')
        self.db.execute('UPDATE relations SET tags=? WHERE id=20',(json.dumps({'route':'train','name':'Unreviewed HSR','operator':'MTR','highspeed':'yes'}),))
        self.assertEqual(self.build()['package']['lines'],[])

    def test_real_gsh_mainland_and_hong_kong_aliases_merge_full_seven_stops(self):
        official_dir=Path(__file__).resolve().parents[4]/'railway-sources/local/china/evidence/official-20261018'
        corridor=json.loads((official_dir/'guangzhou-shenzhen-hongkong-stations.json').read_text())
        records=[];node_ids=[]
        for index,station in enumerate(corridor['stations']):
            node=station['coordinateEvidence']['osmId'];node_ids.append(node)
            self.node(node,110+index*.01,station['name'])
            records.append({key:station[key] for key in ('name','telecode','pinyin')})
        (self.official/'12306-national-stations.json').write_text(json.dumps({'records':records}))
        (self.official/'guangzhou-shenzhen-hongkong-stations.json').write_text(json.dumps(corridor))
        self.way(10,node_ids[:5],highspeed='yes');self.way(11,node_ids[4:],highspeed='yes')
        self.route(9405634,[['w',10,'']],route='railway',name='Guangshengang Highspeed Line',
                   **{'name:zh':'广深港高速线','name:en':'Guangshengang Highspeed Line','ref':'3021','wikidata':'Q910209'})
        self.route(8707713,[['w',11,'']],route='tracks',name='Express Rail Link',operator='MTR',
                   **{'official_name':'廣深港高速鐵路香港段','wikidata':'Q11064778'})
        result=self.build();line=next(line for line in result['package']['lines'] if line['id']=='cn-guangshengan-hsr')
        self.assertEqual([station[0] for station in line['stations']],
                         ['cn-official-12306-'+station['telecode'].lower() for station in corridor['stations']])
        self.assertEqual({source['id'] for source in line['sourceRelations']},{9405634,8707713})
        self.assertEqual([interval['nodeIds'] for interval in line['sourceIntervals']],
                         [[left,right] for left,right in zip(node_ids,node_ids[1:])])
        root=self.official/'catalog-root';catalog_path=root/'app/data/station-english.json'
        catalog_path.parent.mkdir(parents=True)
        catalog_path.write_text(json.dumps({'byCountry':{'jp':{'keep':True}},'inputSha256':{}}))
        output=write_outputs(result,root,self.official/'catalog-scratch')
        cn=json.loads(Path(output['english']).read_text())['byCountry']['cn']
        verified=json.loads(Path(output['englishEvidence']).read_text())
        self.assertEqual(len(verified['byLineStation']),7)
        self.assertTrue(all(key.startswith('cn-guangshengan-hsr:cn-official-12306-') for key in verified['byLineStation']))
        self.assertTrue(all(row['operator']=='中国铁路／港铁' for row in verified['byLineStation'].values()))
        for station in corridor['stations']:
            group=cn['byCode']['cn-official-12306-'+station['telecode'].lower()]
            self.assertEqual(group['status'],'official_verified')
            self.assertEqual(group['en'],station['nameEnglish'])
            self.assertTrue(all(m['lineId']=='cn-guangshengan-hsr' for m in group['memberships']))

    def test_train_stopping_pattern_does_not_duplicate_published_physical_track(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙');self.node(3,110.02,'丙')
        self.way(10,[1,2,3]);self.route(20,[['w',10,'']],route='railway')
        self.route(21,[['n',1,'stop'],['w',10,''],['n',3,'stop']],name='G123')
        result=self.build()
        self.assertEqual(len(result['package']['lines']),1)
        self.assertEqual(result['package']['lines'][0]['id'],'cn-osm-relation-20')
        self.assertTrue(any('duplicate physical passenger service' in row['reason'] for row in result['coverage']['unresolved']))

    def test_numbered_train_service_does_not_create_unverified_physical_line(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙');self.way(10,[1,2])
        self.route(20,[['n',1,'stop'],['w',10,''],['n',2,'stop']],name='D123: 甲 → 乙')
        result=self.build()
        self.assertEqual(result['package']['lines'],[])
        self.assertTrue(any('train-number service' in row['reason'] for row in result['coverage']['unresolved']))

    def test_osm_english_on_official_identity_is_candidate_not_pinyin(self):
        self.node(1,110,'甲',**{'name:en':'Alpha'});self.node(2,110.01,'乙')
        self.way(10,[1,2]);self.route(20,[['n',1,'stop'],['w',10,''],['n',2,'stop']])
        result=self.build()
        row=result['readings']['byCode']['cn-official-12306-aaa']
        self.assertEqual(row['en'],'Alpha')
        self.assertEqual(row['englishSourceType'],'original-OSM')
        self.assertEqual(result['readings']['byCode']['cn-official-12306-bbb']['en'],'')
        root=self.official/'root';catalog_path=root/'app/data/station-english.json'
        catalog_path.parent.mkdir(parents=True)
        countries={country:{'sentinel':country,'byCode':{}} for country in ['jp','tw','hk','mo','kr']}
        catalog_path.write_text(json.dumps({'schema':'station-english/1','byCountry':countries,'inputSha256':{'existing':'retain'}}))
        output=write_outputs(result,root,self.official/'scratch')
        catalog=json.loads(Path(output['english']).read_text())
        self.assertEqual({k:v for k,v in catalog['byCountry'].items() if k!='cn'},countries)
        self.assertEqual(catalog['byCountry']['cn']['byCode']['cn-official-12306-aaa']['status'],'osm_candidate')
        self.assertIsNone(catalog['byCountry']['cn']['byCode']['cn-official-12306-bbb']['en'])
        self.assertEqual(catalog['inputSha256']['existing'],'retain')
        runtime=json.loads(Path(output['package']).read_text())
        self.assertNotIn('sourceIntervals',runtime['lines'][0])
        self.assertEqual(runtime['lines'][0]['sourceRef'],result['package']['lines'][0]['id'])
        companion=json.loads(Path(output['sources']).read_text())
        self.assertEqual(companion['byLine'][runtime['lines'][0]['id']]['sourceIntervals'][0]['nodeIds'],[1,2])
        restored=resolve_line_sources(companion,runtime['lines'][0]['id'])
        self.assertEqual(restored['sourceRelation']['members'],[['n',1,'stop'],['w',10,''],['n',2,'stop']])
        self.assertEqual(restored['sourceWayIds'],[10])
        self.assertEqual(catalog['inputSha256']['public/rail/cn-2025.json'],
                         hashlib.sha256(Path(output['package']).read_bytes()).hexdigest())
        self.assertEqual(json.loads(catalog_path.read_text())['byCountry'],countries)

    def test_explicit_route_master_selects_one_urban_direction_and_keeps_source(self):
        for id,x in [(1,110),(2,110.01),(3,110),(4,110.01)]: self.node(id,x)
        self.db.execute('UPDATE nodes SET lat=30.001 WHERE id IN (3,4)')
        self.node(5,110,'甲');self.node(6,110.01,'乙')
        for aid,members in [(100,[1,3,5]),(101,[2,4,6])]:
            self.db.execute('INSERT INTO relations VALUES(?,?,?,1)',(aid,json.dumps([['n',ref,''] for ref in members]),json.dumps({'public_transport':'stop_area'})))
        self.way(10,[1,2]);self.way(11,[3,4])
        self.route(20,[['n',1,'stop'],['w',10,''],['n',2,'stop']],route='subway')
        self.route(21,[['n',4,'stop'],['w',11,''],['n',3,'stop']],route='subway')
        self.db.execute('INSERT INTO relations VALUES(?,?,?,1)',(200,json.dumps([['r',20,''],['r',21,'']]),json.dumps({'type':'route_master','route_master':'subway','name':'测试地铁'})))
        result=self.build()
        self.assertEqual(len(result['package']['lines']),1)
        line=result['package']['lines'][0]
        self.assertEqual(line['sourceAlternativeAlignments'][0]['sourceIntervals'][0]['nodeIds'],[4,3])
        self.assertEqual(line['sourceRouteMasters'][0]['id'],200)

    def test_gsh_parallel_tracks_connected_remotely_do_not_force_platform_detours(self):
        for id,x in [(1,110),(2,110.01),(3,110.02),(4,110),(5,110.01),(6,110.02),(10,111)]:
            self.node(id,x)
        self.db.execute('UPDATE nodes SET lat=30.001 WHERE id IN (4,5,6)')
        self.node(7,110,'甲');self.node(8,110.01,'乙');self.node(9,110.02,'丙')
        self.db.execute('UPDATE nodes SET lat=30.001 WHERE id=8')
        self.way(10,[1,2,3,10]);self.way(11,[4,5,6,10])
        self.route(20,[['n',7,'stop'],['n',8,'stop'],['n',9,'stop'],['w',10,''],['w',11,'']],route='railway',name='广深港高速铁路')
        stations=[{'name':name,'telecode':code,'pinyin':pinyin,'coordinateEvidence':{'osmId':node}}
                  for name,code,pinyin,node in [('甲','AAA','jia',7),('乙','BBB','yi',8),('丙','CCC','bing',9)]]
        (self.official/'guangzhou-shenzhen-hongkong-stations.json').write_text(json.dumps({'stations':stations}))
        result=self.build();line=result['package']['lines'][0]
        paths=[interval['nodeIds'] for interval in line['sourceIntervals']]
        self.assertIn(paths,[[[1,2],[2,3]],[[4,5],[5,6]]])
        self.assertNotIn(10,{node for interval in paths for node in interval})
        self.assertTrue(all(len(interval)==2 for interval in paths))
        self.db.execute('UPDATE relations SET tags=? WHERE id=20',(json.dumps({'route':'train','name':'测试铁路','operator':'测试铁路公司'}),))
        general=self.build()['package']['lines'][0]
        self.assertIn([p['nodeIds'] for p in general['sourceIntervals']],[[[1,2],[2,3]],[[4,5],[5,6]]])
        for aid,refs in [(100,[1,4,7]),(101,[2,5,8]),(102,[3,6,9])]:
            self.db.execute('INSERT INTO relations VALUES(?,?,?,1)',(aid,json.dumps([['n',n,''] for n in refs]),json.dumps({'public_transport':'stop_area'})))
        self.db.execute('UPDATE relations SET tags=?,members=? WHERE id=20',(
            json.dumps({'route':'railway','name':'测试铁路','operator':'测试铁路公司'}),json.dumps([['w',10,''],['w',11,'']])))
        implicit=self.build()['package']['lines'][0]
        source_paths=[p['nodeIds'] for p in implicit['sourceIntervals']]
        self.assertIn(source_paths,[[[1,2],[2,3]],[[4,5],[5,6]],[[3,2],[2,1]],[[6,5],[5,4]]])
        for node,name in [(1,'甲'),(4,'甲'),(2,'乙'),(5,'乙'),(3,'丙'),(6,'丙')]:
            self.db.execute('UPDATE nodes SET tags=? WHERE id=?',(json.dumps({'name':name,'railway':'stop','train':'yes'}),node))
        self.node(11,110.005)
        self.db.execute('UPDATE ways SET nodes=? WHERE id=10',(json.dumps([1,11]),))
        self.way(12,[11,2,3,10])
        self.db.execute('UPDATE relations SET members=? WHERE id=20',(json.dumps([['w',10,''],['w',11,''],['w',12,'']]),))
        aggregated=self.build()['package']['lines']
        self.assertEqual(len(aggregated),1)
        self.assertNotIn(10,{n for path in aggregated[0]['sourceIntervals'] for n in path['nodeIds']})
        self.assertEqual(len(aggregated[0]['stations']),3)

    def test_infrastructure_station_membership_is_not_passenger_stop_order(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙');self.node(3,110.02,'丙')
        self.way(10,[1,2,3])
        self.route(20,[['n',1,''],['n',3,''],['n',2,''],['w',10,'']],route='railway')
        result=self.build();line=result['package']['lines'][0]
        self.assertIn([station[1] for station in line['stations']],[['甲','乙','丙'],['丙','乙','甲']])
        self.assertEqual(sum(len(interval['nodeIds'])-1 for interval in line['sourceIntervals']),2)

    def test_original_passenger_crossover_is_kept_but_unknown_usage_is_withheld(self):
        self.node(1,110,'甲');self.node(2,110.005);self.node(3,110.006);self.node(4,110.01,'乙')
        self.way(10,[1,2]);self.way(11,[3,4]);self.way(12,[2,3],service='crossover',passenger_lines='2')
        self.route(20,[['n',1,'stop'],['n',4,'stop'],['w',10,''],['w',11,''],['w',12,'']])
        result=self.build()
        self.assertEqual(result['package']['lines'][0]['sourceIntervals'][0]['nodeIds'],[1,2,3,4])
        self.db.execute('UPDATE ways SET tags=? WHERE id=12',(json.dumps({'railway':'rail','service':'crossover'}),))
        unknown=self.build()
        self.assertEqual(unknown['package']['lines'],[])
        self.assertTrue(any('crossover passenger usage not evidenced' in row['reason'] for row in unknown['coverage']['unresolved']))

    def test_unsourced_operator_withheld(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙');self.way(10,[1,2])
        self.route(20,[['n',1,'stop'],['w',10,''],['n',2,'stop']],operator='')
        result=self.build()
        self.assertEqual(result['package']['lines'],[])
        self.assertTrue(any('operator' in x['reason'] for x in result['coverage']['unresolved']))

    def test_other_hong_kong_and_macau_transit_excluded(self):
        self.node(1,110,'甲');self.node(2,110.01,'乙');self.way(10,[1,2])
        self.route(20,[['n',1,'stop'],['w',10,''],['n',2,'stop']],route='subway',operator='港鐵')
        self.route(21,[['n',1,'stop'],['w',10,''],['n',2,'stop']],route='light_rail',operator='澳門輕軌')
        result=self.build()
        self.assertEqual(result['package']['lines'],[])
        self.assertEqual(len(result['coverage']['excludedRegionRoutes']),2)

if __name__ == '__main__': unittest.main()
