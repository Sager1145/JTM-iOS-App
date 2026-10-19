#!/usr/bin/env python3
"""Build CN shared-node junctions and explicitly reviewed original rail lead-ins.

Every vertex and adjacent original way is checked against the pinned source
database. Reviewed lead-ins require an explicit source manifest. Coordinates,
station groups, names and passenger relationships never create geometry.
Write a separate candidate output; unrelated registry rows are preserved.
"""
import argparse
from collections import defaultdict
from functools import lru_cache
import hashlib
import json
import math
from pathlib import Path
import re
import sqlite3


SOURCE_URL = 'https://download.geofabrik.de/asia/china-261017.osm.pbf'
REVIEWED_AT = '2026-10-18'


def graph_coordinate_key(coordinate):
    """The runtime's five-decimal Math.round grid, used only to reject ambiguity."""
    return tuple(math.floor(float(value) * 100000 + 0.5) for value in coordinate)


class SourceDatabase:
    def __init__(self, connection):
        self.connection = connection

    @lru_cache(maxsize=100000)
    def node(self, identity):
        row = self.connection.execute(
            'SELECT lon,lat,version FROM nodes WHERE id=?', (identity,)).fetchone()
        if row is None:
            raise ValueError(f'missing original node {identity}')
        if not all(math.isfinite(value) for value in row[:2]) or not row[2]:
            raise ValueError(f'invalid original node {identity}')
        return (row[0], row[1]), row[2]

    @lru_cache(maxsize=8192)
    def way(self, identity):
        row = self.connection.execute(
            'SELECT nodes,version FROM ways WHERE id=?', (identity,)).fetchone()
        if row is None or not row[1]:
            raise ValueError(f'missing original way/version {identity}')
        nodes = json.loads(row[0])
        pairs = {tuple(sorted(pair)) for pair in zip(nodes, nodes[1:]) if pair[0] != pair[1]}
        return pairs, row[1]


def validate_line(line, source, database):
    identity = line['id']
    if not identity.startswith('cn-') or str(line.get('region', 'CN')).lower() != 'cn':
        raise ValueError('line is not owned exclusively by CN')
    for field in ('name', 'operator', 'railwayClassCode'):
        if not isinstance(line.get(field), str) or not line[field].strip():
            raise ValueError(f'missing published identity field {field}')
    intervals = source.get('sourceIntervals', [])
    segments = line.get('segments', [])
    if not intervals or len(intervals) != len(segments):
        raise ValueError('source/runtime interval count mismatch')
    used_nodes = set()
    for index, (interval, segment) in enumerate(zip(intervals, segments)):
        nodes, ways = interval['nodeIds'], interval['edgeWayIds']
        coordinates = segment[2]
        if len(nodes) < 2 or len(nodes) != len(coordinates) or len(ways) != len(nodes) - 1:
            raise ValueError(f'interval {index}: node/coordinate/edge count mismatch')
        if not all(type(node) is int and node > 0 for node in nodes):
            raise ValueError(f'interval {index}: invalid original node identity')
        for node, coordinate in zip(nodes, coordinates):
            original, _ = database.node(node)
            if tuple(coordinate) != original:
                raise ValueError(f'interval {index}: node {node} coordinate differs from original WGS84')
        for start, end, way in zip(nodes, nodes[1:], ways):
            if type(way) is not int or way <= 0:
                raise ValueError(f'interval {index}: invalid original way identity')
            original_pairs, version = database.way(way)
            if start == end or tuple(sorted((start, end))) not in original_pairs:
                raise ValueError(f'interval {index}: {start}/{end} are not adjacent in original way {way}')
            if interval.get('wayVersions', {}).get(str(way)) != version:
                raise ValueError(f'interval {index}: original way {way} version mismatch')
        used_nodes.update(nodes)
    return used_nodes


def endpoint_identity(line):
    return {'operatorName': line['operator'], 'lineName': line['name'],
            'railwayClassCode': line['railwayClassCode'], 'trackID': line['id']}


def compile_reviewed_physical_sections(connection, package, manifest):
    """Publish original N02 track features, without inventing passenger stations.

    The shared solver already consumes physical sections independently of the
    compact passenger/display catalog. A separate connector keeps its own track
    identity; an extension must retain its existing published track identity.
    Official corridor reviews or explicit original passenger-service membership
    supply missing usage attributes, never missing topology.
    """
    if manifest.get('schema')!='cn-reviewed-physical-sections/1' or manifest.get('source')!=SOURCE_URL:
        raise ValueError('unsupported reviewed physical section source')
    if manifest.get('sourceSha256') and package.get('geometrySource',{}).get('sourceSha256',{}).get('china-261017.osm.pbf')!=manifest['sourceSha256']:
        raise ValueError('reviewed physical section source snapshot drift')
    database=SourceDatabase(connection)
    published={line['id']:line for line in package['lines']}
    features=[];proofs={}
    for row in manifest['sections']:
        identity=row['identity'];key=row['id'];track=identity['trackID']
        if (not key.startswith('cn-reviewed-physical-') or key in proofs or row.get('region')!='cn'
                or not track.startswith('cn-') or not all(identity.get(k) for k in ('lineName','operatorName','railwayClassCode'))):
            raise ValueError('invalid or duplicate reviewed physical identity')
        if row['institutionTypeCode'] not in {'1','2'} or identity['railwayClassCode'] not in {'11','12'}:
            raise ValueError('unsupported reviewed physical rail classification')
        if track in published and identity!=endpoint_identity(published[track]):
            raise ValueError('published physical identity drift')
        nodes,ways,coords=row['nodeIds'],row['edgeWayIds'],row['coordinates']
        if (len(nodes)<2 or len(set(nodes))!=len(nodes) or len(coords)!=len(nodes)
                or len(ways)!=len(nodes)-1 or not all(type(n) is int and n>0 for n in nodes)):
            raise ValueError('invalid reviewed original physical path')
        ownership=row.get('sourceOwnership',{'mode':'original-relation-membership'})
        ownership_mode=ownership.get('mode')
        if ownership_mode not in {'original-relation-membership','original-way-identity'}:
            raise ValueError('unsupported physical source ownership mode')
        relations={};inventory=set()
        for expected in row['sourceRelations']:
            original=connection.execute('SELECT members,tags,version FROM relations WHERE id=?',(expected['id'],)).fetchone()
            if original is None or original[2]!=expected['version']:
                raise ValueError('physical source relation version drift')
            members,tags=json.loads(original[0]),json.loads(original[1])
            if ownership_mode=='original-way-identity' and any(
                    field not in expected or expected[field]!=tags.get(field) for field in ('name','ref','operator')):
                raise ValueError('physical source relation context identity drift')
            relations[expected['id']]={'members':members,'tags':tags,'version':original[2]}
            inventory.update(ref for kind,ref,role in members if kind=='w')
        if not relations or (ownership_mode=='original-relation-membership' and not set(ways).issubset(inventory)):
            raise ValueError('physical path outside original relation member inventory')
        for node,coordinate in zip(nodes,coords):
            original,version=database.node(node)
            if tuple(coordinate)!=original or row['nodeVersions'].get(str(node))!=version:
                raise ValueError('physical original node coordinate/version drift')
        tags_by_way={}
        for start,end,way in zip(nodes,nodes[1:],ways):
            pairs,version=database.way(way)
            if tuple(sorted((start,end))) not in pairs or row['wayVersions'].get(str(way))!=version:
                raise ValueError('physical original way adjacency/version drift')
            tags=json.loads(connection.execute('SELECT tags FROM ways WHERE id=?',(way,)).fetchone()[0])
            tags_by_way[way]=tags
            country=next((str(tags[k]).upper() for k in ('ISO3166-1','addr:country','country') if tags.get(k)), 'CN')
            if (tags.get('railway')!='rail' or country!='CN' or tags.get('construction') or tags.get('proposed')
                    or tags.get('disused')=='yes' or tags.get('abandoned')=='yes'
                    or tags.get('service') in {'yard','siding','spur'}
                    or tags.get('passenger')=='no' or tags.get('train')=='no'
                    or tags.get('railway:traffic_mode')=='freight' or tags.get('traffic_mode')=='freight'):
                raise ValueError('inactive, freight or foreign original physical track')
        if ownership_mode=='original-way-identity':
            direct={'name':identity['lineName'],'ref':ownership.get('ref'),'operator':identity['operatorName']}
            if (not all(isinstance(value,str) and value.strip() for value in direct.values())
                    or any(any(tags.get(field)!=value for field,value in direct.items()) for tags in tags_by_way.values())):
                raise ValueError('physical original way identity name/ref/operator drift')
        operator=row['operatorEvidence'];passenger=row['passengerEvidence']
        for evidence in (operator,passenger):
            if not evidence.get('support') or not evidence.get('urls') or not all(u.startswith('https://') for u in evidence['urls']):
                raise ValueError('explicit reviewed operator/passenger evidence required')
        if operator['kind']=='original-way-operator':
            if any(t.get('operator')!=identity['operatorName'] for t in tags_by_way.values()):
                raise ValueError('original way operator drift')
        elif operator['kind']=='original-member-node-operating-agency':
            if len(operator.get('nodes',[]))<2: raise ValueError('two original operating-agency members required')
            members={ref for rel in relations.values() for kind,ref,role in rel['members'] if kind=='n'}
            for expected in operator['nodes']:
                actual=connection.execute('SELECT tags,version FROM nodes WHERE id=?',(expected['id'],)).fetchone()
                if (expected['id'] not in members or actual is None or actual[1]!=expected['version']
                        or json.loads(actual[0]).get('operator')!=identity['operatorName']):
                    raise ValueError('original member operating agency drift')
        elif operator['kind']=='published-identity-extension':
            if track not in published: raise ValueError('extension requires an existing published identity')
        elif operator['kind']!='reviewed-official-operating-agency':
            raise ValueError('unsupported operating-agency evidence')
        if passenger['kind']=='source-way-passenger-tags':
            if not all(t.get('railway:traffic_mode')=='passenger' or
                       (str(t.get('passenger_lines','')).isdigit() and int(t['passenger_lines'])>0)
                       for t in tags_by_way.values()):
                raise ValueError('explicit source passenger way tags required')
        elif passenger['kind']=='original-passenger-relation':
            refs=passenger['sourceRelationIds'];eligible=set()
            for ref in refs:
                rel=relations[ref];tags=rel['tags'];count=str(tags.get('passenger_lines',''))
                if not (tags.get('route')=='train' or tags.get('railway:traffic_mode')=='passenger'
                        or (count.isdigit() and int(count)>0)):
                    raise ValueError('source relation does not establish passenger use')
                eligible.update(ref for kind,ref,role in rel['members'] if kind=='w')
            if not set(ways).issubset(eligible): raise ValueError('passenger source member coverage incomplete')
        elif passenger['kind']=='reviewed-official-corridor':
            if not passenger.get('sourceNames') or not set(passenger['sourceRelationIds']).issubset(relations):
                raise ValueError('reviewed named passenger corridor required')
            if not all(relations[ref]['tags'].get('name') in passenger['sourceNames'] for ref in passenger['sourceRelationIds']):
                raise ValueError('official/source passenger corridor identity drift')
        else: raise ValueError('unsupported physical passenger evidence')
        if passenger['kind']!='original-passenger-relation' and any(
                t.get('service')=='crossover' and not (t.get('railway:traffic_mode')=='passenger'
                or (str(t.get('passenger_lines','')).isdigit() and int(t['passenger_lines'])>0))
                for t in tags_by_way.values()):
            raise ValueError('crossover requires explicit original passenger membership')
        properties={'line_name':identity['lineName'],'operator':identity['operatorName'],
                    'railway_class_code':identity['railwayClassCode'],'institution_type_code':row['institutionTypeCode'],
                    'region':'CN','track_id':track,'source_review_id':key,
                    'source_node_ids':[['osm-node-'+str(n) for n in nodes]],'source_way_ids':list(dict.fromkeys(ways))}
        if track in published: properties.update(line_id=track,line_ids=[track])
        features.append({'type':'Feature','properties':properties,'geometry':{'type':'LineString','coordinates':coords}})
        proofs[key]={**row,'sourceIntervals':[{'nodeIds':nodes,'edgeWayIds':ways,'wayVersions':row['wayVersions']}],
                     'sourceSnapshot':manifest['source'],'sourceSha256':manifest.get('sourceSha256'),
                     'sourceOwnership':dict(ownership),
                     'sourceRelationEvidence':[
                         {'id':ref,'version':rel['version'],
                          **{k:rel['tags'].get(k) for k in ('name','ref','operator')},
                          'memberPathWayIds':sorted(set(ways)&{member for kind,member,role in rel['members'] if kind=='w'})}
                         for ref,rel in relations.items()],
                     'sourceWayEvidence':[
                         {'id':way,'version':database.way(way)[1],
                          **{k:tags.get(k) for k in ('name','ref','operator')},
                          'sourceRelationIds':[ref for ref,rel in relations.items()
                                               if any(kind=='w' and member==way for kind,member,role in rel['members'])]}
                         for way,tags in tags_by_way.items()]}
    return features,proofs


def compile_reviewed_physical_station_bindings(connection, manifest, proofs, official_records):
    """Bind real member station identities to an already validated physical path.

    These raw N02 station features do not add compact passenger records or join
    platform strands. Their geometry consists only of adjacent original nodes.
    """
    if manifest.get('schema')!='cn-reviewed-physical-sections/1' or manifest.get('source')!=SOURCE_URL:
        raise ValueError('unsupported reviewed physical station source')
    database=SourceDatabase(connection)
    features=[]
    seen=set()
    for row in manifest['sections']:
        bindings=row.get('stationBindings',[])
        if not isinstance(bindings,list): raise ValueError('physical station bindings must be a list')
        if not bindings: continue
        proof=proofs.get(row['id'])
        fields=('identity','institutionTypeCode','sourceRelations','nodeIds','nodeVersions','coordinates','stationBindings')
        if (proof is None or proof.get('sourceSnapshot')!=SOURCE_URL
                or any(proof.get(field)!=row.get(field) for field in fields)):
            raise ValueError('physical station binding requires the validated section proof')
        members=set()
        for expected in row['sourceRelations']:
            original=connection.execute('SELECT members,version FROM relations WHERE id=?',(expected['id'],)).fetchone()
            if original is None or original[1]!=expected['version']:
                raise ValueError('physical station source relation version drift')
            members.update(ref for kind,ref,role in json.loads(original[0]) if kind=='n')
        for binding in bindings:
            marker=binding.get('markerNodeId');anchor=binding.get('anchorNodeId')
            code=binding.get('officialTelecode');name=binding.get('stationName')
            official=official_records.get(code) if isinstance(official_records,dict) and isinstance(code,str) else None
            if (not isinstance(code,str) or re.fullmatch('[A-Z]{3}',code) is None
                    or not isinstance(official,dict) or official.get('telecode')!=code
                    or not isinstance(name,str) or not name or official.get('name')!=name
                    or official.get('source')!='12306-station_name.js'):
                raise ValueError('physical station exact official code/name evidence required')
            if type(marker) is not int or marker<=0 or marker not in members:
                raise ValueError('physical station marker must be an original source relation member')
            marker_coordinate,version=database.node(marker)
            original=connection.execute('SELECT tags FROM nodes WHERE id=?',(marker,)).fetchone()
            tags=json.loads(original[0])
            marker_names={tags.get(k) for k in ('name','name:zh','name:zh-Hans')}
            if (binding.get('markerVersion')!=version or binding.get('markerCoordinate')!=list(marker_coordinate)
                    or tags.get('railway') not in {'station','halt','stop'} or name not in marker_names
                    or tags.get('construction') or tags.get('proposed') or tags.get('disused')=='yes'
                    or tags.get('abandoned')=='yes' or tags.get('station') in {'yard','freight'}
                    or tags.get('railway:traffic_mode')=='freight' or tags.get('traffic_mode')=='freight'
                    or tags.get('passenger')=='no' or tags.get('train')=='no'):
                raise ValueError('physical station original active marker name/coordinate/version drift')
            if type(anchor) is not int or anchor not in row['nodeIds']:
                raise ValueError('physical station anchor must be on its validated original path')
            coordinate,anchor_version=database.node(anchor)
            index=row['nodeIds'].index(anchor)
            if (binding.get('anchorVersion')!=anchor_version or row['nodeVersions'].get(str(anchor))!=anchor_version
                    or row['coordinates'][index]!=list(coordinate)):
                raise ValueError('physical station original anchor coordinate/version drift')
            lon,lat,anchor_lon,anchor_lat=map(math.radians,(*marker_coordinate,*coordinate))
            value=math.sin((anchor_lat-lat)/2)**2+math.cos(lat)*math.cos(anchor_lat)*math.sin((anchor_lon-lon)/2)**2
            if 12742017.6*math.asin(min(1,math.sqrt(value)))>1500:
                raise ValueError('physical station anchor exceeds existing own-route 1500m bound')
            identity=row['identity'];track=identity['trackID']
            token=(track,code,anchor)
            if token in seen: raise ValueError('duplicate physical station path binding')
            seen.add(token)
            start=max(0,index-1);end=min(len(row['nodeIds']),index+2)
            path_nodes=row['nodeIds'][start:end]
            properties={'line_name':identity['lineName'],'operator':identity['operatorName'],
                        'railway_class_code':identity['railwayClassCode'],'institution_type_code':row['institutionTypeCode'],
                        'line_id':track,'line_ids':[track],'region':'CN','station_name':name,
                        'n02_station_code':'CN-12306-'+code,'n02_group_code':'cn-official-12306-'+code.lower(),
                        'display_point':list(coordinate),'source_station_node_id':marker,'source_anchor_node_id':anchor,
                        'source_review_id':row['id'],'source_node_ids':[['osm-node-'+str(n) for n in path_nodes]]}
            features.append({'type':'Feature','properties':properties,
                             'geometry':{'type':'LineString','coordinates':row['coordinates'][start:end]}})
    return features


def physical_graph_view(package, topology):
    """A validation/junction view of published physical paths, not a display package."""
    lines={line['id']:dict(line) for line in package['lines']}
    sources={key:dict(value) for key,value in topology['byLine'].items()}
    for record in topology.get('byPhysicalSection',{}).values():
        identity=record['identity'];track=identity['trackID']
        if track not in lines:
            lines[track]={'id':track,'name':identity['lineName'],'operator':identity['operatorName'],
                          'railwayClassCode':identity['railwayClassCode'],'region':'CN','segments':[]}
            sources[track]={'sourceIntervals':[]}
        elif endpoint_identity(lines[track])!=identity:
            raise ValueError('physical graph identity drift')
        line=lines[track];source=sources[line.get('sourceRef',track)]
        line['segments']=[*line['segments'],[0,0,record['coordinates']]]
        source['sourceIntervals']=[*source['sourceIntervals'],*record['sourceIntervals']]
    return {**package,'lines':list(lines.values())},{**topology,'byLine':sources}


def merge_rows(registry, rows):
    """Keep every pre-existing row and policy; repeat builds are idempotent."""
    if registry.get('format') != 'jtm-physical-rail-junctions-v1':
        raise ValueError('unsupported physical junction registry format')
    existing = {row['id']: row for row in registry['junctions']}
    appended = []
    for row in rows:
        previous = existing.get(row['id'])
        if previous is not None:
            if previous != row:
                raise ValueError(f'existing junction conflicts with source candidate: {row["id"]}')
            continue
        appended.append(row)
    return {**registry, 'junctions': [*registry['junctions'], *appended]}, len(appended)


def build_reviewed_connections(connection, package, topology, registry, manifest):
    """Compile only explicitly reviewed original-node lead-ins; never find paths."""
    if (manifest.get('schema') != 'cn-reviewed-connections/1' or manifest.get('source') != SOURCE_URL
            or package.get('format') != 'compact-v1' or package.get('country') != 'CN'
            or topology.get('schema') != 'cn-original-osm-sources/1'
            or topology.get('country') != 'CN' or topology.get('packageVersion') != package.get('version')):
        raise ValueError('reviewed connection source/package ownership mismatch')
    lines = {line['id']: line for line in package['lines']}
    if len(lines) != len(package['lines']):
        raise ValueError('duplicate published line identity')
    database = SourceDatabase(connection)
    if (manifest.get('sourceSha256') is not None
            and package.get('geometrySource', {}).get('sourceSha256', {}).get('china-261017.osm.pbf')
            != manifest['sourceSha256']):
        raise ValueError('reviewed connection pinned source SHA256 mismatch')
    rows, seen = [], set()
    for review in manifest['connections']:
        identity = review['id']
        if not identity.startswith('cn-reviewed-') or identity in seen:
            raise ValueError('missing or duplicate reviewed connection identity')
        seen.add(identity)
        if review.get('attachMeters') != {'from': 0, 'to': 0}:
            raise ValueError(f'{identity}: reviewed attachment must be exactly zero')
        nodes, ways, coordinates = review['nodeIds'], review['edgeWayIds'], review['coordinates']
        if (len(nodes) < 2 or len(set(nodes)) != len(nodes) or len(coordinates) != len(nodes)
                or len(ways) != len(nodes) - 1
                or not all(type(node) is int and node > 0 for node in nodes)):
            raise ValueError(f'{identity}: invalid original path or repeated node')
        endpoints, source_records = {}, {}
        for side, node in [('from', nodes[0]), ('to', nodes[-1])]:
            expected = review[side]
            line = lines[expected['lineId']]
            source = topology['byLine'][line.get('sourceRef', line['id'])]
            used = validate_line(line, source, database)
            if (expected['identity'] != endpoint_identity(line) or expected['nodeId'] != node
                    or node not in used):
                raise ValueError(f'{identity}: {side} published identity/vertex drift')
            if 'segmentIndex' in expected or 'vertexIndex' in expected:
                interval = source['sourceIntervals'][expected['segmentIndex']]
                if interval['nodeIds'][expected['vertexIndex']] != node:
                    raise ValueError(f'{identity}: {side} expected source vertex drift')
            if 'sourceStation' in expected:
                pinned = expected['sourceStation']
                matches = [station for station in source.get('sourceStations', [])
                           if station.get('groupId') == pinned['groupId']]
                if not any(all(station.get(key) == value for key, value in pinned.items())
                           for station in matches):
                    raise ValueError(f'{identity}: {side} station source anchor drift')
            # The coordinate runtime would attach must identify this original node alone.
            key = graph_coordinate_key(database.node(node)[0])
            collocated = {other for interval in source['sourceIntervals'] for other in interval['nodeIds']
                          if graph_coordinate_key(database.node(other)[0]) == key}
            if collocated != {node}:
                raise ValueError(f'{identity}: {side} runtime coordinate has ambiguous original nodes')
            endpoints[side] = {'identity': endpoint_identity(line), 'coordinate': list(database.node(node)[0])}
            source_records[side] = source
        owner = source_records['from']
        inventory = owner.get('sourceWayIds')
        if inventory is None:
            collection, key = owner['sourceWayInventoryRef'].split('/', 1)
            inventory = topology[collection][key]
        if not set(ways).issubset(set(inventory)):
            raise ValueError(f'{identity}: lead-in way is outside its source corridor inventory')
        for node, coordinate in zip(nodes, coordinates):
            original, version = database.node(node)
            if tuple(coordinate) != original or review['nodeVersions'].get(str(node)) != version:
                raise ValueError(f'{identity}: original node {node} coordinate/version drift')
        for start, end, way in zip(nodes, nodes[1:], ways):
            pairs, version = database.way(way)
            if (tuple(sorted((start, end))) not in pairs
                    or review['wayVersions'].get(str(way)) != version):
                raise ValueError(f'{identity}: original way {way} adjacency/version drift')
            tags = json.loads(connection.execute('SELECT tags FROM ways WHERE id=?', (way,)).fetchone()[0])
            passenger_lines=str(tags.get('passenger_lines',''))
            explicit_passenger=(tags.get('railway:traffic_mode')=='passenger'
                                or (passenger_lines.isdigit() and int(passenger_lines)>0))
            excluded=(tags.get('passenger')=='no' or tags.get('train')=='no'
                      or tags.get('railway:traffic_mode')=='freight' or tags.get('traffic_mode')=='freight'
                      or tags.get('construction') or tags.get('proposed')
                      or tags.get('disused')=='yes' or tags.get('abandoned')=='yes'
                      or tags.get('service') in {'yard','siding','spur'})
            if tags.get('railway') != 'rail' or not explicit_passenger or excluded:
                raise ValueError(f'{identity}: original way {way} lacks reviewed passenger rail tags')
        for relation, version in review.get('relationVersions', {}).items():
            original = connection.execute('SELECT version FROM relations WHERE id=?', (int(relation),)).fetchone()
            if original is None or original[0] != version:
                raise ValueError(f'{identity}: original relation {relation} version drift')
        if 'ownerRelationId' in review:
            relation = review['ownerRelationId']
            members = connection.execute('SELECT members FROM relations WHERE id=?', (relation,)).fetchone()
            if (str(relation) not in review.get('relationVersions', {}) or members is None
                    or not set(ways).issubset({ref for kind, ref, role in json.loads(members[0]) if kind == 'w'})):
                raise ValueError(f'{identity}: original owner relation member-way drift')
        passenger = review['passengerEvidence']
        urls = passenger['urls']
        if not urls or not all(url.startswith(('https://kyfw.12306.cn/', 'https://search.12306.cn/')) for url in urls):
            raise ValueError(f'{identity}: reviewed official passenger evidence required')
        way_ids = sorted(set(ways))
        rows.append({
            'id': identity, 'kind': 'osmTrack', 'region': 'cn',
            'station': review['station'], 'stationCode': review['stationCode'],
            'lineIDs': [review[side]['lineId'] for side in ('from', 'to')],
            **endpoints, 'path': coordinates, 'attachMeters': {'from': 0, 'to': 0},
            'endJunction': {'end': 'to', **endpoints['to']},
            'source': {'provider': 'OpenStreetMap', 'license': 'ODbL-1.0', 'ways': way_ids,
                       'retrieved': manifest.get('sourceRetrievedAt', REVIEWED_AT),
                       'cache': 'railway-sources/local/china/osm/china-261017-rail.sqlite3'},
            'sourceTopology': {'schema': 'cn-reviewed-original-node-path/1', 'source': SOURCE_URL,
                'reviewId': identity, 'nodeIds': nodes, 'nodeVersions': review['nodeVersions'],
                'edgeWayIds': ways, 'wayVersions': review['wayVersions'],
                'relationVersions': review.get('relationVersions', {}),
                'ownerRelationId': review.get('ownerRelationId'),
                'publishedBindings': {side: review[side] for side in ('from', 'to')},
                'sourceSha256': manifest.get('sourceSha256'), 'passengerEvidence': passenger},
            'evidence': [*urls, SOURCE_URL, *[f'https://www.openstreetmap.org/way/{way}' for way in way_ids]],
            'geometryEvidence': 'Exact consecutive original OSM nodes and way versions supply this passenger '
                'rail lead-in. Both attachments are existing published source vertices with zero stubs. '
                'The path stays on its source corridor identity until the named to-end junction. '
                'Official same-train evidence supports passenger continuity, not a unique intermediate '
                'track assignment. Station anchors and member order are unchanged.',
            'reviewedAt': review['reviewedAt'], 'validFrom': None, 'validTo': None,
            'temporalEvidence': 'Review and source snapshot dates are not opening dates. '
                'Opening and closing dates are unknown; no historical validity is inferred.'})
    retained, replaced = [], 0
    for row in registry['junctions']:
        proof = row.get('sourceTopology', {})
        owned = (row['id'] in seen and row.get('region') == 'cn'
                 and proof.get('schema') == 'cn-reviewed-original-node-path/1'
                 and proof.get('source') == SOURCE_URL and proof.get('reviewId') == row['id'])
        if owned:
            replaced += 1
        else:
            retained.append(row)
    merged, appended = merge_rows({**registry, 'junctions': retained}, rows)
    return merged, {'schema': 'cn-reviewed-connection-build/1', 'source': SOURCE_URL,
                    'counts': {'generatedJunctions': len(rows), 'appendedJunctions': appended,
                               'replacedGeneratedRows': replaced}}


def build_junctions(connection, package, topology, registry, replace_generated_cn=False):
    if (package.get('format') != 'compact-v1' or package.get('country') != 'CN'
            or topology.get('schema') != 'cn-original-osm-sources/1'
            or topology.get('country') != 'CN'
            or topology.get('packageVersion') != package.get('version')):
        raise ValueError('CN package/source schema, ownership or version mismatch')
    display_line_count=len(package['lines'])
    package,topology=physical_graph_view(package,topology)
    database = SourceDatabase(connection)
    lines, sources, owners = {}, {}, {}
    withheld = []
    line_ids = [line.get('id') for line in package['lines']]
    if not all(isinstance(identity, str) for identity in line_ids) or len(set(line_ids)) != len(line_ids):
        raise ValueError('missing or duplicate published line identity')
    for line in sorted(package['lines'], key=lambda item: item['id']):
        identity = line['id']
        try:
            source = topology['byLine'][line.get('sourceRef', identity)]
            nodes = validate_line(line, source, database)
        except (KeyError, IndexError, TypeError, ValueError) as error:
            withheld.append({'lineId': identity, 'reason': str(error)})
            continue
        lines[identity], sources[identity] = line, source
        for node in nodes:
            previous = owners.get(node)
            if previous is None:
                owners[node] = identity
            elif isinstance(previous, str):
                owners[node] = {previous, identity}
            else:
                previous.add(identity)

    shared = {node for node, membership in owners.items() if isinstance(membership, set)}
    neighbors = defaultdict(set)
    edge_owners = defaultdict(set)
    adjacent = defaultdict(set)
    boundaries = set()
    ambiguous = set()
    for identity, source in sources.items():
        intervals = source['sourceIntervals']
        own_shared = {node for interval in intervals for node in interval['nodeIds'] if node in shared}
        wanted_keys = {graph_coordinate_key(database.node(node)[0]) for node in own_shared}
        coordinate_nodes = defaultdict(set)
        for interval in intervals:
            nodes, ways = interval['nodeIds'], interval['edgeWayIds']
            boundaries.update((nodes[0], nodes[-1]))
            for node in nodes:
                key = graph_coordinate_key(database.node(node)[0])
                if key in wanted_keys:
                    coordinate_nodes[key].add(node)
            for start, end, way in zip(nodes, nodes[1:], ways):
                for node, other in ((start, end), (end, start)):
                    if node in own_shared:
                        neighbors[node].add(other)
                        edge_owners[node, other].add(identity)
                        adjacent[identity, node].add((way, other))
        for node in sorted(own_shared):
            same_coordinate = coordinate_nodes[graph_coordinate_key(database.node(node)[0])]
            if len(same_coordinate) > 1:
                ambiguous.add((identity, node))
                withheld.append({'lineId': identity, 'nodeId': node,
                                 'reason': 'multiple original nodes at one runtime five-decimal coordinate',
                                 'originalNodeIds': sorted(same_coordinate)})

    selected = []
    for node in sorted(shared):
        membership = owners[node]
        if (node in boundaries or len(neighbors[node]) != 2
                or any(edge_owners[node, other] != membership for other in neighbors[node])):
            selected.append(node)

    def proof(identity, node):
        return [{'wayId': way, 'version': database.way(way)[1],
                 'nodeIds': [node, other], 'url': f'https://www.openstreetmap.org/way/{way}'}
                for way, other in sorted(adjacent[identity, node])]

    rows = []
    for node in selected:
        membership = sorted(identity for identity in owners[node] if (identity, node) not in ambiguous)
        if len(membership) < 2:
            continue
        coordinate, version = database.node(node)
        # One deterministic star has the same connectivity as all pairings.
        for other in membership[1:]:
            first = membership[0]
            from_proof, to_proof = proof(first, node), proof(other, node)
            if not from_proof or not to_proof:
                raise ValueError(f'node {node}: shared membership has no original adjacent way')
            token = hashlib.sha256((first + '\0' + other).encode()).hexdigest()[:16]
            way_ids = sorted({entry['wayId'] for entry in from_proof + to_proof})
            rows.append({
                'id': f'cn-osm-node-{node}-{token}', 'kind': 'zeroLength', 'region': 'cn',
                'lineIDs': [first, other],
                'from': {'identity': endpoint_identity(lines[first]), 'coordinate': list(coordinate)},
                'to': {'identity': endpoint_identity(lines[other]), 'coordinate': list(coordinate)},
                'evidence': [SOURCE_URL, f'https://www.openstreetmap.org/node/{node}',
                             *[f'https://www.openstreetmap.org/way/{way}' for way in way_ids]],
                'sourceTopology': {'schema': 'cn-original-node-junction/1', 'source': SOURCE_URL,
                                   'nodeId': node, 'nodeVersion': version,
                                   'fromAdjacentOriginalWays': from_proof,
                                   'toAdjacentOriginalWays': to_proof},
                'geometryEvidence': (
                    f'Original OSM node {node} version {version} appears on both published CN paths at '
                    'the identical source WGS84 vertex. Each endpoint retains verified consecutive '
                    'original-way node membership and versions in sourceTopology. Names, passenger '
                    'groups and coordinate coincidence do not establish this junction.'),
                'reviewedAt': REVIEWED_AT, 'validFrom': None, 'validTo': None,
                'temporalEvidence': 'Opening and closing dates are unknown; no historical opening date is asserted.',
            })
    replaced = 0
    if replace_generated_cn:
        retained=[]
        for row in registry['junctions']:
            proof=row.get('sourceTopology', {})
            owned=(row.get('region')=='cn' and row['id'].startswith('cn-osm-node-')
                   and proof.get('schema')=='cn-original-node-junction/1'
                   and proof.get('source')==SOURCE_URL)
            if owned: replaced+=1
            else: retained.append(row)
        registry={**registry,'junctions':retained}
    merged, appended = merge_rows(registry, rows)
    report = {'schema': 'cn-physical-junction-build/1', 'source': SOURCE_URL,
              'reviewedAt': REVIEWED_AT,
              'degreeScope': 'Union of verified original-node adjacency on published CN paths only.',
              'counts': {'publishedLines': display_line_count, 'validatedLines': len(lines),
                         'publishedPhysicalSupplementPaths':len(topology.get('byPhysicalSection',{})),
                         'sharedOriginalNodes': len(shared), 'selectedOriginalNodes': len(selected),
                         'generatedJunctions': len(rows), 'appendedJunctions': appended,
                         'withheld': len(withheld), 'replacedGeneratedRows': replaced}, 'withheld': withheld}
    return merged, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('database', 'package', 'source-topology', 'registry', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--reviewed-connections', type=Path,
                        help='explicit reviewed original-node lead-in manifest')
    parser.add_argument('--reviewed-physical-sections',type=Path,
                        help='reviewed original physical tracks and optional evidenced raw N02 station bindings')
    parser.add_argument('--sections',type=Path)
    parser.add_argument('--sections-output',type=Path)
    parser.add_argument('--source-output',type=Path)
    parser.add_argument('--stations',type=Path)
    parser.add_argument('--stations-output',type=Path)
    parser.add_argument('--official-stations',type=Path,
                        help='original 12306-national-stations.json used for exact code/name bindings')
    parser.add_argument('--reviewed-only', action='store_true',
                        help='compile reviewed lead-ins only, preserving all other existing rows')
    parser.add_argument('--replace-generated-cn', action='store_true',
                        help='refresh only rows owned by this pinned CN source builder; preserve manual and other-region rows')
    args = parser.parse_args()
    if args.reviewed_only and not args.reviewed_connections:
        parser.error('--reviewed-only requires --reviewed-connections')
    if args.reviewed_physical_sections and not all((args.sections,args.sections_output,args.source_output)):
        parser.error('--reviewed-physical-sections requires --sections, --sections-output and --source-output')
    if args.reviewed_physical_sections and (args.sections_output.resolve()==args.sections.resolve()
            or args.source_output.resolve()==args.source_topology.resolve()):
        parser.error('physical section outputs must be separate candidate files')
    station_args=(args.stations,args.stations_output,args.official_stations)
    if any(station_args) and (not all(station_args) or not args.reviewed_physical_sections):
        parser.error('station candidates require --reviewed-physical-sections, --stations, --stations-output and --official-stations')
    if args.stations_output:
        protected=[args.stations,args.official_stations,args.package,args.source_topology,args.registry,
                   args.reviewed_physical_sections,args.sections,args.reviewed_connections,args.database]
        outputs=[args.output,args.sections_output,args.source_output,args.stations_output,
                 args.report or args.output.with_suffix('.report.json')]
        output_paths=[path.resolve() for path in outputs]
        if (len(set(output_paths))!=len(output_paths)
                or set(output_paths)&{path.resolve() for path in protected if path}):
            parser.error('station, section, source and registry outputs must be separate candidate files')
    if args.output.resolve() == args.registry.resolve():
        parser.error('--output must be a separate candidate file; the registry input is preserved')
    connection = sqlite3.connect(args.database.resolve().as_uri() + '?mode=ro', uri=True)
    try:
        metadata = dict(connection.execute('SELECT key,value FROM metadata'))
        counts = json.loads(metadata.get('counts', '{}'))
        if (Path(metadata.get('source', '')).name != 'china-261017.osm.pbf'
                or not counts.get('nodes') or not counts.get('ways')):
            raise ValueError('completed pinned china-261017 original topology metadata required')
        package, topology, registry = (json.loads(path.read_text())
                                       for path in (args.package, args.source_topology, args.registry))
        physical_outputs=None;station_output=None
        if args.reviewed_physical_sections:
            manifest=json.loads(args.reviewed_physical_sections.read_text())
            features,proofs=compile_reviewed_physical_sections(connection,package,manifest)
            if any(row.get('stationBindings') for row in manifest['sections']) and not all(station_args):
                parser.error('physical station bindings require --stations, --stations-output and --official-stations')
            if all(station_args):
                official_document=json.loads(args.official_stations.read_text())
                official=official_document.get('records') if isinstance(official_document,dict) else None
                if (not isinstance(official,list) or any(not isinstance(r,dict) or not isinstance(r.get('telecode'),str) for r in official)
                        or len({r['telecode'] for r in official})!=len(official)):
                    raise ValueError('original official station records required')
                station_features=compile_reviewed_physical_station_bindings(connection,manifest,proofs,
                    {r['telecode']:r for r in official})
                stations=json.loads(args.stations.read_text())
                if stations.get('type')!='FeatureCollection' or not isinstance(stations.get('features'),list):
                    raise ValueError('raw N02 station FeatureCollection required')
                owned=set(topology.get('byPhysicalSection',{}))|set(proofs)
                station_output={**stations,'features':[f for f in stations['features']
                    if not (f.get('properties',{}).get('region')=='CN'
                        and f.get('properties',{}).get('source_review_id') in owned)]+station_features}
            sections=json.loads(args.sections.read_text())
            owned=set(topology.get('byPhysicalSection',{}))|set(proofs)
            sections={**sections,'features':[f for f in sections['features']
                if (f.get('properties',{}).get('source_review_id') or
                    f.get('properties',{}).get('source_id')) not in owned]+features}
            topology={**topology,'byPhysicalSection':proofs}
            physical_outputs=(sections,topology)
        if args.reviewed_only:
            merged, report = build_reviewed_connections(connection, package, topology, registry,
                                                       json.loads(args.reviewed_connections.read_text()))
        else:
            merged, report = build_junctions(connection, package, topology, registry,
                                           replace_generated_cn=args.replace_generated_cn)
            if args.reviewed_connections:
                merged, reviewed = build_reviewed_connections(connection, package, topology, merged,
                                                              json.loads(args.reviewed_connections.read_text()))
                report['reviewedConnections'] = reviewed
    finally:
        connection.close()
    report_path = args.report or args.output.with_suffix('.report.json')
    if report_path.resolve() in {args.registry.resolve(), args.output.resolve()}:
        parser.error('report must not overwrite the registry or candidate')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + '\n')
    if physical_outputs:
        for path,document in zip((args.sections_output,args.source_output),physical_outputs):
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(document,ensure_ascii=False,separators=(',',':'))+'\n')
    if station_output is not None:
        args.stations_output.parent.mkdir(parents=True,exist_ok=True)
        args.stations_output.write_text(json.dumps(station_output,ensure_ascii=False,separators=(',',':'))+'\n')
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'report': str(report_path), 'counts': report['counts']}))


if __name__ == '__main__':
    main()
