"""China passenger network compiler, retaining original OSM node adjacency.

A station identity is not a connection. Graph edges come exclusively from two
consecutive nodes of an original, active passenger-eligible member way. Missing
nodes, disconnected ways and branches are reported, never repaired by distance.
"""
from collections import defaultdict
from datetime import datetime, timezone
from functools import lru_cache
import heapq
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import sqlite3
from opencc import OpenCC

VERSION = '2026.10.18'
URBAN = {'subway', 'light_rail', 'tram', 'monorail', 'funicular'}
ROUTES = URBAN | {'train', 'railway', 'rail', 'narrow_gauge', 'tracks'}
ACTIVE_RAIL = {'rail', 'subway', 'light_rail', 'tram', 'monorail', 'narrow_gauge', 'funicular'}
GSH_NAMES = {'广深港高速铁路', '廣深港高速鐵路', '广深港客运专线', '廣深港客運專線',
             '广深港高速线', '廣深港高速線', '廣深港高速綫'}
GSH_WIKIDATA = {'Q910209', 'Q11064778'}


def distance(a, b):
    lon1, lat1, lon2, lat2 = map(math.radians, (*a, *b))
    value = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 6371008.8 * 2 * math.asin(min(1, math.sqrt(value)))


def names(tags):
    return {v.strip() for key in ('name', 'name:zh', 'name:zh-Hans', 'name:zh-Hant', 'official_name', 'short_name')
            for v in str(tags.get(key, '')).split(';') if v.strip()}


def is_gsh(tags):
    # Original national infrastructure relations use both 高速线 and 高速铁路;
    # the two source Wikidata identities cover mainland and Hong Kong sections.
    identifiers=set(re.split(r'[;\s]+',str(tags.get('wikidata',''))))
    return bool(identifiers & GSH_WIKIDATA) or any(
        token in name for name in names(tags) for token in GSH_NAMES) or bool(re.search(
        r'Guangzhou.*Shenzhen.*Hong Kong|Guangshengang Highspeed Line',
        str(tags.get('name:en','')),re.I))


def passenger_crossover(tags):
    count=str(tags.get('passenger_lines',''))
    modes=set(str(tags.get('railway:traffic_mode',tags.get('traffic_mode',''))).split(';'))
    return tags.get('passenger')=='yes' or 'passenger' in modes or (count.isdigit() and int(count)>0)


def active(tags):
    return not (tags.get('disused') == 'yes' or tags.get('abandoned') == 'yes'
                or tags.get('construction') or tags.get('proposed')
                or tags.get('service') in {'yard', 'siding', 'spur'}
                or (tags.get('service')=='crossover' and not passenger_crossover(tags))
                or tags.get('usage') in {'industrial', 'military', 'test'}
                or tags.get('railway:traffic_mode') == 'freight'
                or tags.get('traffic_mode') == 'freight'
                or tags.get('passenger') == 'no' or tags.get('train') == 'no'
                or tags.get('station') in {'yard','freight'})


# ISO 3166-1 alpha-2 ownership codes. Unknown values do not establish foreign ownership;
# arbitrary two-letter tags must not silently remove a Chinese railway.
COUNTRY_CODES = set("""AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW""".split())
FOREIGN_RAILWAY_IDENTITIES = {
    'KP': {'Q864803', '조선민주주의인민공화국 철도성', 'Korean State Railway', '朝鲜铁道省', '朝鮮鐵道省'},
    'RU': {'Q660770', 'РЖД', 'Russian Railways'},
    'KR': {'Korail', 'Korea Railroad Corporation', '한국철도공사'},
    'KZ': {'Қазақстан темір жолы', 'Kazakhstan Temir Zholy'},
    'MN': {'Ulaanbaatar Railway', 'Улаанбаатар төмөр зам'},
    'VN': {'Vietnam Railways', 'Đường sắt Việt Nam'},
    'LA': {'Lao National Railway', 'Lao-China Railway Company'},
}


def region_owner(tags):
    for key in ('ISO3166-1','ISO3166-1:alpha2','addr:country','country','is_in:country_code'):
        value=str(tags.get(key,'')).strip().upper()
        if value in COUNTRY_CODES and value!='CN': return value
    # These are exact sourced agency identities, not foreign destination names.
    agency_values={value.strip().casefold() for key,value in tags.items()
                   if key=='operator' or key.startswith('operator:') or key=='network' or key.startswith('network:')
                   for value in re.split(r'[;；]',str(value)) if value.strip()}
    for owner,identities in FOREIGN_RAILWAY_IDENTITIES.items():
        if agency_values & {value.casefold() for value in identities}: return owner
    text = ' '.join(str(tags.get(k, '')) for k in ('name','name:en','network','network:en','operator','operator:en','brand','ref','is_in'))
    if re.search(r'澳[门門]|[Mm]aca[ou]|[Mm]acao|氹仔[线線]|氹仔綫|石排[湾灣]|橫琴[线線]|横琴线|\bMLRT\b', text):
        return 'MO'
    if re.search(r'港[铁鐵]|九廣|九广|香港|[Hh]ong [Kk]ong|\bMTR\b|\bKCR\b', text):
        return 'HK'
    if re.search(r'臺灣|台灣|台湾|Taiwan|Taipei|Kaohsiung',text,re.I): return 'TW'
    return 'CN'


def normalize_closed_loop(line):
    """Use one membership per station and retain the exact sourced closing leg."""
    rows=line['stations']
    if len(rows)>2 and rows[0][0]==rows[-1][0]:
        sources=line['sourceStations'];intervals=line['sourceIntervals']
        if (len(line['segments'])!=len(rows)-1 or len(intervals)!=len(rows)-1
                or sources[0]['anchorNodeId']!=sources[-1]['anchorNodeId']
                or intervals[-1]['nodeIds'][-1]!=intervals[0]['nodeIds'][0]):
            raise ValueError('closed station membership lacks exact original closing path: '+line['id'])
        line['stations']=rows[:-1]
        line['sourceStations']=sources[:-1]
        line['isLoop']=1
    return line


def interior_owner(coordinate):
    # Conservative interior seeds classify ownership only; no coordinate ever
    # contributes a topology edge. Borders remain represented by source tags.
    lon,lat=coordinate
    if 114.08<lon<114.40 and 22.18<lat<22.45: return 'HK'
    if 113.90<lon<=114.08 and 22.18<lat<22.46: return 'HK'
    if 113.54<lon<113.61 and 22.10<lat<22.18: return 'MO'
    if 120.20<lon<121.95 and 22.10<lat<25.20: return 'TW'
    return None


def shortest(graph, start, targets=None, barrier=None):
    """Dijkstra over original node IDs; barriers stop expansion at other stations."""
    distances = {start: 0.0}
    previous = {}
    queue = [(0.0, start)]
    remaining = set(targets) if targets is not None else None
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != distances[node]:
            continue
        if remaining is not None:
            remaining.discard(node)
            if not remaining:
                break
        if barrier and node != start and node in barrier:
            continue
        for neighbor, (length, way) in graph.get(node, {}).items():
            candidate = cost + length
            if candidate < distances.get(neighbor, math.inf):
                distances[neighbor] = candidate
                previous[neighbor] = (node, way)
                heapq.heappush(queue, (candidate, neighbor))
    return distances, previous


def path_to(previous, start, end):
    if start == end:
        return [start], []
    if end not in previous:
        return None
    nodes, ways = [end], []
    while nodes[-1] != start:
        node, way = previous[nodes[-1]]
        nodes.append(node)
        ways.append(way)
    return nodes[::-1], ways[::-1]


class ChinaBuilder:
    def __init__(self, database, official_dir, progress=None, reviewed_stations=None):
        self.progress=progress
        self.db = database if isinstance(database, sqlite3.Connection) else sqlite3.connect(str(database))
        self.official_dir = Path(official_dir)
        self.s2t=OpenCC('s2t')
        official = json.loads((self.official_dir / '12306-national-stations.json').read_text())
        self.official = {s['telecode']: s for s in official['records']}
        self.official_names = defaultdict(list)
        for item in self.official.values():
            self.official_names[item['name']].append(item)
        corridor_file = self.official_dir / 'guangzhou-shenzhen-hongkong-stations.json'
        self.gsh = json.loads(corridor_file.read_text()) if corridor_file.exists() else None
        self.coverage = {'schema':'cn-coverage/1', 'country':'CN', 'nationalCompleteness':False,
                         'ownershipPolicy':'Explicit source ISO country or exact operator/network identity, stop-area tags and existing conservative HK/MO/TW interior seeds; known foreign or mixed sources withheld as whole; only reviewed GSH corridor may include Hong Kong HSR.',
                         'scope':'Eligible evidenced passenger paths in the pinned source; unresolved sources are withheld independently.',
                         'unresolved':[], 'passengerServiceEvidence':[], 'excludedRegionRoutes':[], 'published':[], 'counts':{}}
        self.relations = {row[0]: {'id':row[0], 'members':json.loads(row[1]), 'tags':json.loads(row[2]), 'version':row[3]}
                          for row in self.db.execute('SELECT id,members,tags,version FROM relations')}
        self.route_parents=defaultdict(list)
        for relation in self.relations.values():
            if relation['tags'].get('type')=='route_master' and relation['tags'].get('route_master') in URBAN:
                for kind,ref,role in relation['members']:
                    if kind=='r': self.route_parents[ref].append(relation)
        self.stop_areas = {}
        self.node_areas = defaultdict(set)
        for id, relation in self.relations.items():
            if relation['tags'].get('public_transport') != 'stop_area':
                continue
            refs = {int(ref) for kind, ref, role in relation['members'] if kind == 'n'}
            self.stop_areas[id] = relation
            for ref in refs:
                self.node_areas[ref].add(id)
        self.reviewed_stations={}
        self.reviewed_telecodes={}
        if reviewed_stations is not None:
            review=json.loads(Path(reviewed_stations).read_text())
            if review.get('schema')!='cn-reviewed-station-bindings/1':
                raise ValueError('unsupported reviewed station binding schema')
            if review.get('sourceSha256'):
                acquisition=acquisition_record(dict(self.db.execute('SELECT key,value FROM metadata')))
                if not acquisition or acquisition.get('sha256')!=review['sourceSha256']:
                    raise ValueError('reviewed station source snapshot drift')
            for binding in review['stations']:
                marker=self.node(binding['markerNodeId'])
                code=binding['officialTelecode']
                if (not marker or marker['version']!=binding['markerVersion']
                        or code not in self.official or self.official[code]['name'] not in names(marker['tags'])
                        or marker['tags'].get('railway') not in {'station','halt'}):
                    raise ValueError('reviewed station marker identity/version drift')
                if marker['id'] in self.reviewed_stations or code in self.reviewed_telecodes:
                    raise ValueError('duplicate reviewed station marker or telecode')
                if not binding.get('sourceRelations') or not binding.get('evidence') or not any(
                        url.startswith('https://kyfw.12306.cn/') for url in binding['evidence']):
                    raise ValueError('reviewed station requires official passenger and source membership evidence')
                for expected in binding['sourceRelations']:
                    relation=self.relations.get(expected['id'])
                    if (not relation or relation['version']!=expected['version']
                            or not any(kind=='n' and ref==marker['id'] for kind,ref,role in relation['members'])):
                        raise ValueError('reviewed station source relation membership/version drift')
                self.reviewed_stations[marker['id']]=binding
                self.reviewed_telecodes[code]=marker['id']
        self.station_nodes = {}
        for id, lon, lat, tags, version in self.db.execute("SELECT id,lon,lat,tags,version FROM nodes WHERE tags != '{}'"):
            tags = json.loads(tags)
            if tags.get('railway') in {'station','halt','stop'} or tags.get('public_transport') in {'station','stop_position'}:
                reviewed=self.reviewed_stations.get(id,{})
                eligibility=tags
                if reviewed.get('operatingStationDespiteConstructionTag'):
                    if tags.get('construction')!='station' or tags.get('train')!='yes':
                        raise ValueError('reviewed operating station construction/train tag drift')
                    eligibility={key:value for key,value in tags.items() if key!='construction'}
                if active(eligibility):
                    self.station_nodes[id] = {'id':id,'coordinate':[lon,lat],'tags':tags,'version':version}
        self.used_ways = set()
        self.claimed_way_inventory=set()
        self.identity_markers=defaultdict(dict)

    @lru_cache(maxsize=180000)
    def node(self, id):
        row = self.db.execute('SELECT lon,lat,tags,version FROM nodes WHERE id=?',(id,)).fetchone()
        if row is None:
            return None
        return {'id':id,'coordinate':[row[0],row[1]],'tags':json.loads(row[2]),'version':row[3]}

    @lru_cache(maxsize=16000)
    def way(self, id):
        row = self.db.execute('SELECT nodes,tags,version FROM ways WHERE id=?',(id,)).fetchone()
        return {'id':id,'nodes':json.loads(row[0]),'tags':json.loads(row[1]),'version':row[2]} if row else None

    def unresolved(self, source, reason, **detail):
        self.coverage['unresolved'].append({'source':source,'reason':reason, **detail})

    def expand(self, relation, seen=None):
        seen = set() if seen is None else seen
        if relation['id'] in seen:
            return []
        seen.add(relation['id'])
        result = []
        for kind, ref, role in relation['members']:
            if kind == 'w':
                result.append(int(ref))
            elif kind == 'r' and ref in self.relations:
                child = self.relations[ref]
                if child['tags'].get('route') in ROUTES:
                    result.extend(self.expand(child,seen))
        return list(dict.fromkeys(result))

    def graph(self, way_ids, source):
        graph = defaultdict(dict)
        retained = []
        for id in way_ids:
            way = self.way(id)
            if not way or way['tags'].get('railway') not in ACTIVE_RAIL or not active(way['tags']):
                if way and way['tags'].get('service')=='crossover':
                    tags=way['tags']
                    nonpassenger=tags.get('passenger')=='no' or tags.get('railway:traffic_mode')=='freight' or tags.get('traffic_mode')=='freight'
                    self.unresolved(source,'explicit non-passenger crossover withheld' if nonpassenger else 'crossover passenger usage not evidenced; original connection withheld',wayId=id)
                continue
            retained.append(id)
            for a,b in zip(way['nodes'],way['nodes'][1:]):
                left, right = self.node(a), self.node(b)
                if not left or not right:
                    self.unresolved(source,'missing original source node; edge withheld',wayId=id,nodeIds=[a,b])
                    continue
                if a == b:
                    continue
                length = distance(left['coordinate'],right['coordinate'])
                # Equal coordinates with different IDs remain distinct nodes and can
                # connect only when this very way explicitly contains that edge.
                if b not in graph[a] or length < graph[a][b][0]:
                    graph[a][b] = (length,id)
                    graph[b][a] = (length,id)
        return graph, retained

    def official_identity(self, node, allow_official):
        if not allow_official:
            return None
        tags = node['tags']
        reviewed=self.reviewed_stations.get(node['id'])
        if reviewed:
            return self.official[reviewed['officialTelecode']]
        def permitted(code):
            return code not in self.reviewed_telecodes or self.reviewed_telecodes[code]==node['id']
        for key in ('ref:12306','railway:ref:12306','ref:crs','ref:CRS','ref:telecode','ref'):
            code = str(tags.get(key,'')).upper()
            if code in self.official and permitted(code):
                return self.official[code]
        matches = {item['telecode']:item for name in names(tags) for item in self.official_names.get(name,[])
                   if permitted(item['telecode'])}
        return next(iter(matches.values())) if len(matches) == 1 else None

    def station(self, marker, anchors, evidence, allow_official, area_ids=(), official=None):
        official = official or self.official_identity(marker,allow_official)
        tags = marker['tags']
        name = official['name'] if official else tags.get('name:zh-Hans') or tags.get('name:zh') or tags.get('name')
        if not name:
            return None
        identity = ('cn-official-12306-' + official['telecode'].lower()) if official else f"cn-osm-node-{marker['id']}"
        if official: self.identity_markers[identity][marker['id']]=marker['coordinate']
        return {'id':identity,'name':name,'marker':marker,'anchors':set(anchors),'evidence':evidence,
                'areaIds':sorted(area_ids),'official':official}

    def stations(self, relation, graph, special=False):
        tags = relation['tags']
        allow_official = tags.get('route') not in URBAN
        source = f"relation/{relation['id']}"
        candidates = []
        explicit = []
        by_identity={}
        def add_station(item, ordered=False):
            if item is None: return
            identity=item['id']
            binding={'method':item['evidence'],'markerNodeId':item['marker']['id'],
                     'anchorNodeIds':sorted(item['anchors']),'stopAreaIds':item['areaIds']}
            existing=by_identity.get(identity)
            if existing is None:
                item['bindings']=[binding]
                by_identity[identity]=item;candidates.append(item)
            else:
                # Station identity equivalence retains platform alternatives; it
                # does not join their source nodes. The later ordered path must
                # choose one continuous original platform strand at each stop.
                existing['anchors'].update(item['anchors'])
                existing['areaIds']=sorted(set(existing['areaIds'])|set(item['areaIds']))
                if binding not in existing['bindings']: existing['bindings'].append(binding)
                prefer=lambda marker:(marker['tags'].get('railway') in {'station','halt'},marker['tags'].get('public_transport')=='station')
                if prefer(item['marker'])>prefer(existing['marker']): existing['marker']=item['marker']
            if ordered and identity not in explicit: explicit.append(identity)
        direct_members = [(int(ref),role) for kind,ref,role in relation['members'] if kind=='n']
        # An official corridor order binds identities even when OSM markers are
        # off track. Source marker coordinates are loaded from this PBF, never
        # from a GCJ-02 timetable or an unrelated geographic nearest neighbor.
        if special and self.gsh:
            for item in self.gsh['stations']:
                marker = self.node(item['coordinateEvidence']['osmId'])
                if marker is None:
                    self.unresolved(source,'official corridor station marker missing from original PBF',telecode=item['telecode'])
                    continue
                official = dict(self.official.get(item['telecode'],item))
                official.update({k:item[k] for k in ('nameEnglish','nameTraditional','membershipOrderSource') if k in item})
                area_ids=self.node_areas.get(marker['id'],set())
                anchors={marker['id']} if marker['id'] in graph else set()
                anchors.update(ref for aid in area_ids for kind,ref,role in self.stop_areas[aid]['members'] if kind=='n' and ref in graph)
                station = self.station(marker,anchors, 'official-corridor-membership-and-order',True,area_ids,official=official)
                if station:
                    add_station(station,True)
        else:
            for id,role in direct_members:
                marker = self.node(id)
                if marker is None:
                    continue
                if id not in self.station_nodes and not role.startswith(('stop','station','platform')):
                    continue
                # A nameless stop_position may obtain its marker identity only
                # from an actual stop_area relation sharing that exact node.
                area_ids = self.node_areas.get(id,set())
                markers = [marker] if names(marker['tags']) else []
                for aid in area_ids:
                    for kind,ref,area_role in self.stop_areas[aid]['members']:
                        if kind=='n' and ref in self.station_nodes and names(self.station_nodes[ref]['tags']):
                            markers.append(self.station_nodes[ref])
                if not markers:
                    continue
                preferred = max(markers,key=lambda n:(n['tags'].get('railway') in {'station','halt'}, n['id']==id))
                anchors = {id} if id in graph else set()
                for aid in area_ids:
                    anchors.update(ref for kind,ref,r in self.stop_areas[aid]['members'] if kind=='n' and ref in graph)
                item = self.station(preferred,anchors,'explicit-route-member',allow_official,area_ids)
                # Infrastructure relation member order is an inventory, not a
                # passenger stop sequence (e.g. national 陇海 station markers).
                is_passenger_order=tags.get('route') in (URBAN|{'train'})
                add_station(item,is_passenger_order)
            # In a physical railway relation, actual track station/stop nodes and
            # stop areas containing those nodes are identity-bearing membership.
            for id in graph:
                if id in self.station_nodes and names(self.station_nodes[id]['tags']):
                    item = self.station(self.station_nodes[id],{id},'actual-route-track-node',allow_official,self.node_areas.get(id,()))
                    add_station(item)
                for aid in self.node_areas.get(id,()):
                    area = self.stop_areas[aid]
                    members = [self.station_nodes[ref] for kind,ref,r in area['members']
                               if kind=='n' and ref in self.station_nodes and names(self.station_nodes[ref]['tags'])]
                    if not members:
                        continue
                    marker = max(members,key=lambda n:n['tags'].get('railway') in {'station','halt'})
                    anchors = {ref for kind,ref,r in area['members'] if kind=='n' and ref in graph}
                    item = self.station(marker,anchors,'stop-area-original-track-node-membership',allow_official,[aid])
                    add_station(item)
        # Pick exact source nodes. Projection is allowed only for evidenced
        # members of this relation, and cannot create a graph edge or a chord.
        graph_nodes = list(graph)
        for item in candidates:
            if not item['anchors']:
                marker_coordinate = item['marker']['coordinate']
                limit = 4000 if special else 1500 if allow_official else 800
                nearby={n for n in graph_nodes if distance(marker_coordinate,self.node(n)['coordinate'])<=limit}
                local_graph={n:{neighbor:edge for neighbor,edge in graph[n].items() if neighbor in nearby} for n in nearby}
                # Parallel platforms may connect only at a distant junction.
                # Global components collapse those distinct local source strands
                # and can force a train to run out and back to change platforms.
                local_components=self.components(local_graph)
                nearest_by_strand={}
                for n,c in local_components.items():
                    meters=distance(marker_coordinate,self.node(n)['coordinate'])
                    if c not in nearest_by_strand or (meters,n)<nearest_by_strand[c]:
                        nearest_by_strand[c]=(meters,n)
                if nearest_by_strand:
                    item['anchors'] = {value[1] for value in nearest_by_strand.values()}
                    item['projection'] = 'nearest-original-node-per-own-route-local-source-strand'
                else:
                    self.unresolved(source,'evidenced station has no own-route source-node anchor within bound',stationId=item['id'])
            else:
                item['projection'] = 'exact-member-node'
        return [item for item in candidates if item['anchors']], explicit

    @staticmethod
    def components(graph):
        component = {}
        index = 0
        for node in graph:
            if node in component:
                continue
            component[node] = index
            stack = [node]
            while stack:
                for neighbor in graph[stack.pop()]:
                    if neighbor not in component:
                        component[neighbor]=index;stack.append(neighbor)
            index += 1
        return component

    def choose_ordered_anchors(self, ordered, graph, barriers=None):
        """Choose a continuous ordered platform path without adding any edge.

        Marker distance selects candidates and breaks equal-distance path ties;
        every transition cost and reconstructed path uses original way edges.
        The initial anchor remains in the state so loops must close on that
        exact node, never an opposite platform with a co-located coordinate.
        """
        if not ordered:
            return False
        scores={(n,n):(0.0,distance(ordered[0]['marker']['coordinate'],self.node(n)['coordinate']))
                for n in ordered[0]['anchors']}
        traces=[]
        is_loop=len(ordered)>1 and ordered[0]['id']==ordered[-1]['id']
        for index,(left,right) in enumerate(zip(ordered,ordered[1:]),1):
            next_scores={};previous={};searches={}
            blocked=(barriers-left['anchors']) if barriers is not None else None
            for state,score in scores.items():
                origin,start=state
                if start not in searches:
                    searches[start]=shortest(graph,start,right['anchors'],barrier=blocked)[0]
                lengths=searches[start]
                for target in right['anchors']:
                    if target not in lengths or (is_loop and index==len(ordered)-1 and target!=origin):
                        continue
                    if start==target and left['id']!=right['id']:
                        continue
                    candidate=(score[0]+lengths[target],score[1]+distance(right['marker']['coordinate'],self.node(target)['coordinate']))
                    next_state=(origin,target)
                    if candidate<next_scores.get(next_state,(math.inf,math.inf)):
                        next_scores[next_state]=candidate;previous[next_state]=state
            if not next_scores:
                return False
            scores=next_scores;traces.append(previous)
        state=min(scores,key=lambda key:(scores[key],key))
        selected=[state[1]]
        for previous in traces[::-1]:
            state=previous[state];selected.append(state[1])
        for item,anchor in zip(ordered,selected[::-1]):
            item['anchor']=anchor
            item['anchorSelection']='joint-ordered-original-source-path'
        return True

    def anchored_paths(self, ordered, graph, barriers=None):
        paths=[]
        for left,right in zip(ordered,ordered[1:]):
            blocked=(barriers-left['anchors']) if barriers is not None else None
            _,previous=shortest(graph,left['anchor'],{right['anchor']},barrier=blocked)
            path=path_to(previous,left['anchor'],right['anchor'])
            if not path or len(path[0])<2:
                return None
            paths.append(path)
        return paths

    def continuous_chains(self, ordered, graph, source, barriers=None):
        """Publish separately evidenced intervals if platforms cannot form a chain."""
        selected=[dict(item) for item in ordered]
        if self.choose_ordered_anchors(selected,graph,barriers):
            paths=self.anchored_paths(selected,graph,barriers)
            return [(selected,paths)] if paths else []
        chains=[]
        for left,right in zip(ordered,ordered[1:]):
            pair=[dict(left),dict(right)]
            if self.choose_ordered_anchors(pair,graph,barriers):
                paths=self.anchored_paths(pair,graph,barriers)
                if paths: chains.append((pair,paths))
            else:
                self.unresolved(source,'disconnected original-node station interval',fromStation=left['id'],toStation=right['id'])
        if chains:
            self.unresolved(source,'station platforms cannot form one continuous ordered chain; verified intervals published independently',
                stationIds=[item['id'] for item in ordered])
        return chains

    def ordered_chains(self, candidates, explicit, graph, source):
        by_id={item['id']:item for item in candidates}
        ordered=[by_id[id] for id in explicit if id in by_id]
        if len(ordered)>=2:
            omitted=set(by_id)-set(explicit)
            if omitted:
                self.unresolved(source,'additional track-evidenced stations outside explicit route stop order',stationIds=sorted(omitted))
            return self.continuous_chains(ordered,graph,source)
        # Derive logical station adjacency from every evidenced platform anchor.
        # Logical identities are never graph edges: the selected chain must then
        # choose one exact, continuous original-node platform path at each stop.
        owners=defaultdict(set)
        for item in candidates:
            for anchor in item['anchors']: owners[anchor].add(item['id'])
        ambiguous={anchor for anchor,groups in owners.items() if len(groups)>1}
        for item in candidates:
            if item['anchors'] & ambiguous:
                item['anchors']=item['anchors']-ambiguous
                self.unresolved(source,'multiple station identities share candidate source anchor; ambiguous anchors withheld',stationId=item['id'])
        by_id={item['id']:item for item in candidates if item['anchors']}
        all_anchors={anchor for item in by_id.values() for anchor in item['anchors']}
        anchor_owner={anchor:item['id'] for item in by_id.values() for anchor in item['anchors']}
        adjacency=defaultdict(set)
        for start,item in sorted(by_id.items()):
            blocked=all_anchors-item['anchors']
            reached=set()
            for anchor in item['anchors']:
                lengths,_=shortest(graph,anchor,barrier=blocked)
                reached.update(anchor_owner[n] for n in all_anchors & lengths.keys() if anchor_owner[n]!=start)
            for end in reached:
                adjacency[start].add(end);adjacency[end].add(start)
        if len(by_id)>1 and not adjacency:
            self.unresolved(source,'disconnected original-node station components',stationIds=sorted(by_id))
        chains=[];used=set()
        starts=sorted(adjacency,key=lambda id:(len(adjacency[id])==2,id))
        for start in starts:
            for following in sorted(adjacency[start]):
                key=tuple(sorted((start,following)))
                if key in used: continue
                chain=[by_id[start]];left,right=start,following
                while True:
                    key=tuple(sorted((left,right)))
                    if key in used: break
                    used.add(key);chain.append(by_id[right])
                    onward=[id for id in adjacency[right] if tuple(sorted((right,id))) not in used]
                    if len(adjacency[right])!=2 or not onward or right==start: break
                    left,right=right,onward[0]
                chains.extend(self.continuous_chains(chain,graph,source,all_anchors))
        return chains

    def compile_route(self, relation, forced_ways=None, fallback=False):
        tags=relation['tags'];source=f"relation/{relation['id']}" if not fallback else f"named-way-corridor/{relation['id']}"
        special = is_gsh(tags)
        owner=region_owner(tags)
        hsr= special or tags.get('highspeed')=='yes'
        candidate_ways=forced_ways if forced_ways is not None else self.expand(relation)
        hsr=hsr or any(self.way(w) and self.way(w)['tags'].get('highspeed')=='yes' for w in candidate_ways)
        if owner!='CN' and not (owner=='HK' and special):
            self.coverage['excludedRegionRoutes'].append({'source':source,'owner':owner,'name':tags.get('name',''),'evidence':'original source country or operator/network identity; whole source withheld'})
            return []
        if not active(tags):
            self.unresolved(source,'inactive, non-passenger or service infrastructure');return []
        graph,ways=self.graph(candidate_ways,source)
        if tags.get('route')=='train':
            service_evidence={'relationId':relation['id'],'version':relation['version'],
                'members':relation['members'],'tags':tags,'wayIds':ways}
            if ways and set(ways)<=self.used_ways:
                self.coverage['passengerServiceEvidence'].append(service_evidence)
                self.unresolved(source,'duplicate physical passenger service; membership evidence retained',wayIds=ways)
                return []
            source_name=tags.get('name:zh-Hans') or tags.get('name:zh') or tags.get('name','')
            numbered=bool(re.match(r'^(?:[GDCZTKY]\d+|\d{3,5})(?:[ /:：－—-]|$)',source_name,re.I))
            if numbered:
                self.coverage['passengerServiceEvidence'].append(service_evidence)
                self.unresolved(source,'train-number service does not establish a physical railway identity',name=source_name)
                return []
            if not re.search(r'铁路|鐵路|[线線綫]|rail|express|metro|tram|subway',source_name,re.I):
                self.coverage['passengerServiceEvidence'].append(service_evidence)
                self.unresolved(source,'train service lacks sourced physical/public route name',name=source_name)
                return []
        source_owners=set()
        for w in ways:
            source_owners.add(region_owner(self.way(w)['tags']))
        for n in graph:
            node=self.node(n)
            source_owners.add(region_owner(node['tags']))
            for aid in self.node_areas.get(n,()): source_owners.add(region_owner(self.stop_areas[aid]['tags']))
            geographical_owner=interior_owner(node['coordinate'])
            if geographical_owner: source_owners.add(geographical_owner)
        foreign=source_owners-{'CN'}
        if special: foreign.discard('HK')
        if foreign:
            self.coverage['excludedRegionRoutes'].append({'source':source,'owner':sorted(foreign)[0],
                'name':tags.get('name',''),'evidence':'original source identity tags or conservative interior location','wayIds':ways})
            return []
        if not graph:
            self.unresolved(source,'no active original passenger track members');return []
        # All HSR in Hong Kong belongs to CN. Other Hong Kong/Macao sources
        # remain owned by their package and are never inserted into this graph.
        operator=tags.get('operator','').strip()
        operator_evidence={'source':'original-OSM-named-way-operator-tag' if fallback else 'original-OSM-relation-operator-tag',
                           'wayId' if fallback else 'relationId':relation['id']}
        if special and self.gsh:
            operator='中国铁路／港铁'
            operator_evidence={'source':'reviewed-official-cross-border-corridor-operator-identity',
                'urls':self.gsh.get('corridorIdentityEvidence',[]),
                'componentOperators':[{'name':'中国铁路','ownership':'mainland corridor'}, {'name':'港铁','ownership':'Hong Kong corridor'}]}
        if not operator:
            member_operators={self.way(w)['tags'].get('operator','').strip() for w in ways if self.way(w)['tags'].get('operator','').strip()}
            if len(member_operators)==1:
                operator=next(iter(member_operators))
                operator_evidence={'source':'unique-original-OSM-member-way-operator-tag',
                    'wayIds':[w for w in ways if self.way(w)['tags'].get('operator','').strip()==operator]}
        if not operator and tags.get('network','').strip():
            operator=tags['network'].strip()
            operator_evidence={'source':'original-OSM-named-way-network-tag' if fallback else 'original-OSM-route-network-tag',
                    'identityType':'network; agency operator not asserted','wayId' if fallback else 'relationId':relation['id']}
        if not operator:
            self.unresolved(source,'no sourced operator identity on route or unique member ways',network=tags.get('network'));return []
        candidates,explicit=self.stations(relation,graph,special)
        marker_owners={region_owner(item['marker']['tags']) for item in candidates}-{'CN'}
        if special: marker_owners.discard('HK')
        if marker_owners:
            self.coverage['excludedRegionRoutes'].append({'source':source,'owner':sorted(marker_owners)[0],
                'name':tags.get('name',''),'evidence':'original station marker country or operator/network identity; whole source withheld'})
            return []
        if len(candidates)<2:
            self.unresolved(source,'fewer than two evidenced passenger station identities',stationCount=len(candidates),wayIds=ways);return []
        if fallback:
            candidates=[s for s in candidates if s['official']]
            if len(candidates)<2:
                self.unresolved(source,'named ways lack two corroborated official passenger station memberships');return []
        chains=self.ordered_chains(candidates,explicit,graph,source)
        if not chains: return []
        if special:
            for station_chain,paths in chains:
                nodes=[node for index,(interval,_) in enumerate(paths) for node in (interval if index==0 else interval[1:])]
                if len(nodes)!=len(set(nodes)):
                    self.unresolved(source,'official through-corridor path repeats original source nodes; incompatible platform anchors withheld')
                    return []
        # A main-line highspeed tag on member track is classification evidence.
        hsr = hsr or any(self.way(id)['tags'].get('highspeed')=='yes' for id in ways)
        municipal=tags.get('route') in URBAN
        private=tags.get('ownership')=='private' or tags.get('operator:type')=='private'
        classification='1' if hsr else '3' if municipal else '4' if private else '2'
        name='广深港高速铁路' if special else tags.get('name:zh-Hans') or tags.get('name:zh') or tags.get('name')
        if not name:
            self.unresolved(source,'no sourced passenger line name');return []
        base='cn-guangshengan-hsr' if special else f"cn-osm-{'named' if fallback else 'relation'}-{relation['id']}"
        lines=[]
        for i,(station_chain,paths) in enumerate(chains):
            id=base if i==0 else f'{base}-branch-{i+1}'
            rows=[];source_stations=[]
            for item in station_chain:
                node=self.node(item['anchor']);official=item['official'];marker=item['marker']
                roma=(official.get('nameEnglish') or official.get('pinyin','')) if official else marker['tags'].get('name:en','')
                rows.append([item['id'],item['name'],*node['coordinate'],roma,3 if official else 1 if roma else 0])
                source_stations.append({'groupId':item['id'],'stationCode':('CN-12306-'+official['telecode']) if official else f"CN-OSM-N{marker['id']}",
                    'markerNodeId':marker['id'],'markerVersion':marker['version'],'markerCoordinate':marker['coordinate'],'markerTags':marker['tags'],
                    'anchorNodeId':item['anchor'],'anchorVersion':node['version'],'membershipEvidence':item['evidence'],
                    'anchorEvidence':item.get('projection','exact-member-node'),'anchorSelection':item.get('anchorSelection'),
                    'anchorCandidates':sorted(item['anchors']),'bindingEvidence':item.get('bindings',[]),'stopAreaIds':item['areaIds'],
                    'officialTelecode':official['telecode'] if official else None,'officialPinyin':official.get('pinyin') if official else None,
                    'nameTraditional':official.get('nameTraditional','') if official else marker['tags'].get('name:zh-Hant',''),
                    'nameEnglish':(official.get('nameEnglish','') if official else '') or marker['tags'].get('name:en',''),
                    'englishSourceType':'official-corridor' if official and official.get('nameEnglish') else 'original-OSM' if marker['tags'].get('name:en') else 'missing',
                    'englishSource':official.get('membershipOrderSource','') if official and official.get('nameEnglish') else f"https://www.openstreetmap.org/node/{marker['id']}" if marker['tags'].get('name:en') else ''})
                if marker['id'] in self.reviewed_stations:
                    source_stations[-1]['reviewedStationBinding']=self.reviewed_stations[marker['id']]
            intervals=[];segments=[]
            for nodes,edge_ways in paths:
                coords=[self.node(n)['coordinate'] for n in nodes]
                km=sum(distance(a,b) for a,b in zip(coords,coords[1:]))/1000
                segments.append([round(km,6),0,coords])
                intervals.append({'nodeIds':nodes,'edgeWayIds':edge_ways,'wayVersions':{str(w):self.way(w)['version'] for w in sorted(set(edge_ways))}})
            line={'id':id,'name':name,'nameNorm':name,'rank':1 if hsr else 3 if municipal else 2,
                  'kind':'highspeed' if hsr else 'metro' if municipal else 'conventional',
                  'n02Classification':classification,'railwayClassCode':'12' if hsr else '31' if tags.get('route')=='monorail' else '21' if tags.get('route') in {'tram','light_rail'} else '11','operator':operator,'operatorEvidence':operator_evidence,'stations':rows,'segments':segments,'sourceStations':source_stations,
                  'sourceIntervals':intervals,'sourceStopAreas':[self.stop_areas[aid] for aid in sorted({aid for item in station_chain for aid in item['areaIds']})],
                  'sourceRelation':None if fallback else {'id':relation['id'],'version':relation['version'],'members':relation['members'],'tags':relation['tags']},
                  'sourceWayIds':ways,'sourceRouteMasters':self.route_parents.get(relation['id'],[]),'color':'#D2232A' if hsr else tags.get('colour') if municipal and re.fullmatch(r'#[0-9A-Fa-f]{6}',tags.get('colour','')) else '#4B6475' if municipal else '#68737D',
                  'colorStatus':'original-OSM-colour-tag; official status not asserted' if municipal and re.fullmatch(r'#[0-9A-Fa-f]{6}',tags.get('colour','')) else 'local-display-fallback; no official colour claimed',
                  'operatorStatus':'sourced-identity',
                  'geometryStatus':'original-OSM-WGS84-node-adjacency',
                  'stationOrderEvidence':'reviewed-official-corridor-order' if special else 'original-passenger-route-stop-member-order' if len(explicit)>=2 else 'derived-original-source-track-adjacency','region':'CN'}
            if relation.get('sourceRelations'): line['sourceRelations']=relation['sourceRelations']
            if tags.get('name:en'): line['nameRoma']=tags['name:en']
            normalize_closed_loop(line)
            lines.append(line)
            self.coverage['published'].append({'lineId':id,'source':source,'stations':len(line['stations']),'intervals':len(paths),'classification':classification})
        self.used_ways.update(way for line in lines for interval in line['sourceIntervals'] for way in interval['edgeWayIds'])
        self.claimed_way_inventory.update(ways)
        return lines

    def fallback_routes(self):
        """Named original mainline ways, never name-created geographic edges."""
        groups=defaultdict(list)
        tags_by_name={}
        for id,encoded in self.db.execute('SELECT id,tags FROM ways'):
            if id in self.claimed_way_inventory: continue
            tags=json.loads(encoded)
            if tags.get('railway') not in {'rail','narrow_gauge'} or not active(tags): continue
            name=tags.get('name:zh-Hans') or tags.get('name:zh') or tags.get('name')
            if not name: continue
            named_railway=bool(re.search(r'铁路|鐵路|客运专线|客運專線|高速|城际|城際',name))
            named_main_branch=tags.get('usage') in {'main','branch'} and bool(re.search(r'[线線]$',name))
            if not (named_railway or named_main_branch): continue
            # A line name corroborates identity but contributes zero edges.
            groups[name].append(id)
            tags_by_name.setdefault(name,tags)
        for name,ways in sorted(groups.items()):
            tags=dict(tags_by_name[name]);tags.update(name=name,route='railway')
            yield {'id':min(ways),'tags':tags,'members':[['w',w,''] for w in ways],'version':None},ways

    def build(self):
        lines=[]
        routes=[r for r in self.relations.values() if r['tags'].get('route') in ROUTES]
        # Physical corridors precede train service relations. Duplicate services
        # sharing an identical sourced path and station sequence publish once.
        gsh_routes=[r for r in routes if is_gsh(r['tags'])]
        if gsh_routes:
            physical=[r for r in gsh_routes if r['tags'].get('route') in {'railway','tracks','rail'}]
            contributors=physical or gsh_routes
            merged=dict(min(contributors,key=lambda r:r['id']))
            merged['tags']={**merged['tags'],'name':'广深港高速铁路','route':'railway','highspeed':'yes'}
            merged['members']=[member for r in contributors for member in r['members']]
            merged['sourceRelations']=[{'id':r['id'],'version':r['version'],'members':r['members'],'tags':r['tags']} for r in contributors]
            routes=[r for r in routes if not is_gsh(r['tags'])]+[merged]
        routes.sort(key=lambda r:(not is_gsh(r['tags']),r['tags'].get('route') not in {'railway','tracks','rail','narrow_gauge'},r['id']))
        signatures=set()
        urban_families={}
        for route_number,relation in enumerate(routes,1):
            if self.progress and (route_number==1 or route_number%25==0):
                self.progress(f'CN route {route_number}/{len(routes)}; {len(lines)} verified lines retained')
            for line in self.compile_route(relation):
                signature=(line['operator'],tuple(s[0] for s in line['stations']),tuple(tuple(p['nodeIds']) for p in line['sourceIntervals']))
                rev=(signature[0],signature[1][::-1],tuple(nodes[::-1] for nodes in signature[2][::-1]))
                if signature in signatures or rev in signatures:
                    self.unresolved(f"relation/{relation['id']}",'duplicate passenger station alignment already published')
                    continue
                masters=line.get('sourceRouteMasters',[])
                if relation['tags'].get('route') in URBAN and masters:
                    sequence=tuple(station[0] for station in line['stations'])
                    canonical_sequence=min(sequence,sequence[::-1])
                    keys=[(master['id'],canonical_sequence) for master in masters]
                    representative=next((urban_families[key] for key in keys if key in urban_families),None)
                    if representative is not None:
                        representative.setdefault('sourceAlternativeAlignments',[]).append(line)
                        self.unresolved(f"relation/{relation['id']}",
                            'opposite urban alignment retained as explicit route-master counterpart; one representative drawn',
                            representativeLineId=representative['id'],routeMasterIds=[master['id'] for master in masters])
                        continue
                    for key in keys: urban_families[key]=line
                signatures.add(signature);lines.append(line)
        for corridor_number,(relation,ways) in enumerate(self.fallback_routes(),1):
            if self.progress and (corridor_number==1 or corridor_number%50==0):
                self.progress(f'CN named-way corridor {corridor_number}; {len(lines)} verified lines retained')
            lines.extend(self.compile_route(relation,ways,True))
        if not routes and not lines:
            self.unresolved('database','no eligible source routes')
        ambiguous=set()
        for group,markers in self.identity_markers.items():
            points=list(markers.items())
            if any(distance(a,b)>3000 for i,(_,a) in enumerate(points) for _,b in points[i+1:]):
                ambiguous.add(group)
                self.unresolved('official-identity/'+group,'official identity maps to distant original station markers; memberships withheld',
                    markerNodes=[{'id':id,'coordinate':coordinate} for id,coordinate in points])
        lines=[line for line in lines if not (ambiguous & {station[0] for station in line['stations']})]
        published_ids={line['id'] for line in lines}
        if len(published_ids)!=len(lines): raise ValueError('duplicate physical line ID; publication refused')
        self.coverage['published']=[entry for entry in self.coverage['published'] if entry['lineId'] in published_ids]
        return self.make_artifacts(lines,len(routes))

    def make_artifacts(self,lines,source_route_count):
        sections=[];stations=[];by_code={};by_name={}
        for line in lines:
            common={'line_name':line['name'],'line_id':line['id'],'line_ids':[line['id']], 'operator':line.get('operator',''),
                    'railway_class_code':line['railwayClassCode'],'institution_type_code':line['n02Classification'],'region':'CN'}
            for i,segment in enumerate(line['segments']):
                sections.append({'type':'Feature','properties':{**common,'source_node_ids':[['osm-node-'+str(n) for n in line['sourceIntervals'][i]['nodeIds']]],'track_id':line['id'],
                    'source_way_ids':list(dict.fromkeys(line['sourceIntervals'][i]['edgeWayIds']))},
                    'geometry':{'type':'LineString','coordinates':segment[2]}})
            for i,(row,source) in enumerate(zip(line['stations'],line['sourceStations'])):
                point=row[2:4]
                # A genuine track segment at the anchor satisfies the station
                # feature contract without inventing a small display stub.
                coords=line['segments'][min(i,len(line['segments'])-1)][2]
                station_geom=coords[:2] if i<len(line['segments']) else coords[-2:]
                properties={**common,'station_name':row[1],'n02_station_code':source['stationCode'],'n02_group_code':row[0],
                            'display_point':point,'source_station_node_id':source['markerNodeId'],'source_anchor_node_id':source['anchorNodeId']}
                stations.append({'type':'Feature','properties':properties,'geometry':{'type':'LineString','coordinates':station_geom}})
                entry={'name':row[1],'zh_Hans':row[1],'zh_Hant':source['nameTraditional'] or self.s2t.convert(row[1]),'en':source['nameEnglish'],
                       'ja':'','kana':'','katakana':'','romaji':'','pinyin':source['officialPinyin'] or '',
                       'identitySource':'12306-station_name.js' if source['officialTelecode'] else 'original-OSM',
                       'englishStatus':'official_verified' if source['englishSourceType']=='official-corridor' else 'osm_candidate' if source['nameEnglish'] else 'missing',
                       'englishSourceType':source['englishSourceType'],'englishSource':source['englishSource'],
                       'englishIdentityEvidence':[{'source':'original-OSM-name:en','markerNodeId':source['markerNodeId'],
                            'markerVersion':source['markerVersion']}] if source['englishSourceType']=='original-OSM' else [],
                       'traditionalStatus':'sourced' if source['nameTraditional'] else 'OpenCC s2t orthography; not official spelling'}
                for key in (source['stationCode'],row[0],f"{line['id']}:{row[0]}"):
                    by_code[key]=entry
                if row[1] not in by_name: by_name[row[1]]=entry
                elif by_name[row[1]]!=entry: by_name[row[1]]=None
        generated=datetime.now(timezone.utc).isoformat().replace('+00:00','Z')
        self.coverage['counts']={'sourceRoutes':source_route_count,'publishedLines':len(lines),'publishedStationMemberships':len(stations),
                                 'publishedIntervals':len(sections),'unresolved':len(self.coverage['unresolved'])}
        published_telecodes={station['officialTelecode'] for line in lines for station in line['sourceStations'] if station['officialTelecode']}
        self.coverage['officialIdentities']={'sourceCount':len(self.official),'publishedCount':len(published_telecodes),
            'unpublishedTelecodes':sorted(set(self.official)-published_telecodes),
            'note':'Unpublished identity does not imply a closed station; source relation/track/station evidence may be missing.'}
        metadata={key:value for key,value in self.db.execute('SELECT key,value FROM metadata')}
        acquisition=acquisition_record(metadata)
        package={'format':'compact-v1','version':VERSION,'generatedAt':generated,'crs':'WGS84','country':'CN','lines':lines,
                 'timeZones':['Asia/Shanghai'],'geometrySource':{'providers':['OpenStreetMap contributors'],'license':'ODbL-1.0',
                 'syntheticConnectors':0,'topology':'original ordered way-node adjacency only','sourceMetadata':metadata,
                 'sourceSha256':{path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in [
                    self.official_dir/'12306-national-stations.json',self.official_dir/'12306-station_name.js',
                    self.official_dir/'guangzhou-shenzhen-hongkong-stations.json'] if path.exists()}},
                 'coverage':{'nationalCompleteness':False,'report':'cn-coverage.json'},
                 'attributeSources':{'officialIdentities':'12306-station_name.js','pinyin':'12306-station_name.js',
                     'operators':'explicit route operator, unique member-way operator, labelled route network identity, or reviewed official GSH operator evidence',
                     'colours':'valid original OSM urban colour tag or explicit local UI styling fallback; no official colour inferred',
                     'english':'only explicit original OSM or reviewed official fields; Pinyin is romanization, not an invented English translation'}}
        if acquisition:
            package['geometrySource']['acquisition']=acquisition
            package['geometrySource']['sourceSha256'][acquisition['sourceFile']]=acquisition['sha256']
        readings={'schema':'station-readings/1','country':'CN','packageVersion':VERSION,'languages':['zh-Hans','zh-Hant','ja','en'],
                  'note':'Official 12306 Pinyin is a separate romanization field. Missing translations remain blank.',
                  'byCode':by_code,'byName':{k:v for k,v in by_name.items() if v is not None}}
        return {'package':package,'sections':{'type':'FeatureCollection','features':sections},
                'stations':{'type':'FeatureCollection','features':stations},'readings':readings,'names':readings,'coverage':self.coverage}


def acquisition_record(metadata):
    source=Path(metadata.get('source',''))
    path=source.parent/(source.name.replace('.osm.pbf','')+'.acquisition.json')
    return json.loads(path.read_text()) if path.is_file() else None


def write_cn_english_catalog(result, root, outputs):
    """Refresh only CN through the existing catalog builder, preserving peers."""
    source=Path(root)/'app/data/station-english.json'
    catalog=json.loads(source.read_text())
    spec=importlib.util.spec_from_file_location('cn_existing_english_builder',Path(__file__).with_name('build-station-english.py'))
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    overrides={}
    for line in result['package']['lines']:
        for station in line['sourceStations']:
            key=f"{line['id']}:{station['groupId']}"
            if (line['id']=='cn-guangshengan-hsr' and station['englishSourceType']=='official-corridor'
                    and station['englishSource'].startswith('https://')):
                overrides[key]={'country':'cn','lineId':line['id'],'stationCode':station['groupId'],
                    'operator':line['operator'],'name':next(s[1] for s in line['stations'] if s[0]==station['groupId']),
                    'en':station['nameEnglish'],'source':station['englishSource'],
                    'identityEvidence':[{'officialTelecode':station['officialTelecode'],
                        'source':station['englishSource'],'membershipEvidence':station['membershipEvidence'],
                        'markerNodeId':station['markerNodeId'],'anchorNodeId':station['anchorNodeId']}]}
    evidence_path=outputs.get('englishEvidence',outputs['english'].with_name('station-english-verified-cn.json'))
    evidence={'schema':'station-english-evidence/1','countries':['cn'],
        'note':'Reviewed official MTR English corridor spelling, scoped to exact GSH line/station/operator memberships; no other memberships promoted.',
        'sources':[{'url':url} for url in sorted({row['source'] for row in overrides.values()})],
        'byLineStation':dict(sorted(overrides.items())),'unresolved':[]}
    evidence_path.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
    cn=module.build_region('cn',result['package'],result['readings'],member_overrides=overrides)
    catalog.setdefault('byCountry',{})['cn']=cn
    for key,relative in [('package','public/rail/cn-2025.json'),('readings','data/station-readings-cn.json')]:
        catalog.setdefault('inputSha256',{})[relative]=hashlib.sha256(outputs[key].read_bytes()).hexdigest()
    catalog.setdefault('inputSha256',{})['data/station-english-verified-cn.json']=hashlib.sha256(evidence_path.read_bytes()).hexdigest()
    outputs['english'].write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    return catalog


def write_cn_name_resources(result, root, outputs, catalog):
    """Use the shared regional projectors and preserve peer coverage records."""
    def module(filename, name):
        spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(filename))
        value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
        return value
    def retained(relative, fallback):
        path=Path(root)/relative
        return json.loads(path.read_text()) if path.exists() else fallback
    english=module('build-station-english.py','cn_english_coverage')
    names=module('build-station-names.py','cn_name_projection')
    table, name_report=names.build_region('cn',result['package'],result['readings'],
        catalog['byCountry']['cn'],result['stations'])
    outputs['names'].write_text(json.dumps(table,ensure_ascii=False,separators=(',',':'))+'\n')
    coverage=retained('app/data/station-english-coverage.json',
        {'schema':'station-english-coverage/1','regions':{},'unresolved':[],'unresolvedMemberships':[]})
    cn=english.build_coverage({'cn':catalog['byCountry']['cn']})
    coverage['regions']['cn']=cn['regions']['cn']
    for field in ('unresolved','unresolvedMemberships'):
        coverage[field]=[row for row in coverage[field] if row['country'].lower()!='cn']+cn[field]
    coverage['allStationsHaveEnglish']=all(row['withEnglish']==row['stations'] for row in coverage['regions'].values())
    coverage['allStationsOfficialVerified']=not coverage['unresolved']
    outputs['englishCoverage'].write_text(json.dumps(coverage,ensure_ascii=False,indent=2)+'\n')
    coverage=retained('app/data/station-names-coverage.json',{'schema':'station-names-coverage/1','regions':{},'inputSha256':{}})
    coverage['regions']['cn']=name_report
    for kind in ('package','readings','stations','english'):
        relative=str(outputs[kind].relative_to(outputs['package'].parents[2]))
        coverage['inputSha256'][relative]=hashlib.sha256(outputs[kind].read_bytes()).hexdigest()
    outputs['namesCoverage'].write_text(json.dumps(coverage,ensure_ascii=False,indent=2)+'\n')


def resolve_line_sources(topology,line_id):
    """Expand shared provenance records; interval/station arrays remain direct."""
    def expand(record):
        result=dict(record)
        def relation(row):
            if row and row.get('recordRef'):
                return topology['relationsById'][row['recordRef'].split('/')[-1]]
            return row
        if 'sourceRelation' in result: result['sourceRelation']=relation(result['sourceRelation'])
        for key in ('sourceRelations','sourceStopAreas','sourceRouteMasters'):
            if key in result: result[key]=[relation(row) for row in result[key]]
        if result.get('sourceWayInventoryRef'):
            result['sourceWayIds']=topology['wayInventoriesById'][result['sourceWayInventoryRef'].split('/')[-1]]
        if 'sourceAlternativeAlignments' in result:
            result['sourceAlternativeAlignments']=[expand(row) for row in result['sourceAlternativeAlignments']]
        return result
    return expand(topology['byLine'][line_id])


def factor_source_records(sources):
    """Intern repeated source inventories, retaining exact original records."""
    relations={};inventories={}
    def reference(row):
        if row is None: return None
        key=str(row['id'])
        if key in relations and relations[key]!=row:
            raise ValueError('conflicting original relation records: '+key)
        relations[key]=row
        return {**{field:row[field] for field in ('id','version','tags') if field in row},'recordRef':'relationsById/'+key}
    def factor(record):
        result=dict(record)
        # A GSH union has several genuine contributors; its copied minimum ID
        # is not a new original relation and must not overwrite that contributor.
        if result.get('sourceRelations'): result['sourceRelation']=None
        if 'sourceRelation' in result: result['sourceRelation']=reference(result['sourceRelation'])
        for key in ('sourceRelations','sourceStopAreas','sourceRouteMasters'):
            if key in result: result[key]=[reference(row) for row in result[key]]
        if 'sourceWayIds' in result:
            ways=result.pop('sourceWayIds')
            key=hashlib.sha256(json.dumps(ways,separators=(',',':')).encode()).hexdigest()[:20]
            if key in inventories and inventories[key]!=ways: raise ValueError('source inventory reference collision')
            inventories[key]=ways;result['sourceWayInventoryRef']='wayInventoriesById/'+key
        if 'sourceAlternativeAlignments' in result:
            result['sourceAlternativeAlignments']=[factor(row) for row in result['sourceAlternativeAlignments']]
        return result
    sources['byLine']={id:factor(record) for id,record in sources['byLine'].items()}
    sources['relationsById']=relations;sources['wayInventoriesById']=inventories
    sources['sharedRecordFormat']='relationsById and wayInventoriesById; sourceIntervals/sourceStations remain direct byLine arrays'
    return sources


def write_outputs(result, root, output_dir=None):
    root=Path(root)
    base=Path(output_dir) if output_dir else root
    outputs={'package':base/'app/public/rail/cn-2025.json','sections':base/'app/data/rail-sections-cn.json',
             'stations':base/'app/data/stations-cn.json','readings':base/'app/data/station-readings-cn.json',
             'names':base/'app/data/station-names-cn.json','coverage':base/'app/public/rail/cn-coverage.json',
             'englishCoverage':base/'app/data/station-english-coverage.json','namesCoverage':base/'app/data/station-names-coverage.json',
             'english':base/'app/data/station-english.json','englishEvidence':base/'app/data/station-english-verified-cn.json','sources':base/'app/public/rail/cn-2025.sources.json'}
    if len({line['id'] for line in result['package']['lines']})!=len(result['package']['lines']):
        raise ValueError('duplicate physical line ID; source companion would overwrite records')
    source_fields=('sourceStations','sourceIntervals','sourceRelation','sourceRelations','sourceStopAreas','sourceWayIds',
                   'sourceRouteMasters','sourceAlternativeAlignments')
    runtime_package={**result['package'],'sourcesFile':'cn-2025.sources.json','lines':[]}
    sources={'schema':'cn-original-osm-sources/1','country':'CN','packageVersion':result['package']['version'],'byLine':{}}
    for line in result['package']['lines']:
        sources['byLine'][line['id']]={key:line[key] for key in source_fields if key in line}
        runtime_package['lines'].append({**{key:value for key,value in line.items() if key not in source_fields},'sourceRef':line['id']})
    sources=factor_source_records(sources)
    if result.get('physicalSources'):
        sources['byPhysicalSection']=result['physicalSources']
    for kind,path in outputs.items():
        if kind in {'english','englishEvidence','englishCoverage','namesCoverage'}: continue
        path.parent.mkdir(parents=True,exist_ok=True)
        value=runtime_package if kind=='package' else sources if kind=='sources' else result[kind]
        path.write_text(json.dumps(value,ensure_ascii=False,separators=(',',':'))+'\n')
    catalog=write_cn_english_catalog(result,root,outputs)
    write_cn_name_resources(result,root,outputs,catalog)
    return {key:str(path) for key,path in outputs.items()}
