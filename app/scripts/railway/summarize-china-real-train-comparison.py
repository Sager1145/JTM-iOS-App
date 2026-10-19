#!/usr/bin/env python3
"""Summarize explicitly requested real-train engine outputs; never run a solver.

Geometric stop-distance checks are screening observations, not station-to-track
membership proof or a claim that either candidate is the actual train path.
"""
import argparse
import collections
import csv
import json
import math
from pathlib import Path

R=6371008.8


def length(parts):
    total=0
    for part in parts:
        for a,b in zip(part,part[1:]):
            x1,y1,x2,y2=map(math.radians,(*a,*b))
            h=math.sin((y2-y1)/2)**2+math.cos(y1)*math.cos(y2)*math.sin((x2-x1)/2)**2
            total+=2*R*math.asin(min(1,math.sqrt(h)))
    return total/1000


def station_distance(point,parts):
    """Local tangent-plane point-to-segment distance; metre-scale screening."""
    lon,lat=point;xs=math.pi/180*R*math.cos(math.radians(lat));ys=math.pi/180*R
    best=math.inf
    for part in parts:
        previous=None
        for x,y in part:
            current=((x-lon)*xs,(y-lat)*ys)
            best=min(best,current[0]**2+current[1]**2)
            if previous is not None:
                dx,dy=current[0]-previous[0],current[1]-previous[1];denom=dx*dx+dy*dy
                t=max(0,min(1,-(previous[0]*dx+previous[1]*dy)/denom)) if denom else 0
                best=min(best,(previous[0]+t*dx)**2+(previous[1]+t*dy)**2)
            previous=current
    return math.sqrt(best)


def references(package,sources):
    by_code=collections.defaultdict(dict);by_name=collections.defaultdict(dict)
    for line in package['lines']:
        for row,station in zip(line['stations'],sources['byLine'][line['sourceRef']]['sourceStations']):
            marker=station['markerNodeId'];point=station['markerCoordinate']
            by_code[station['stationCode']][marker]=point
            by_name[row[1]][marker]=point
    return by_code,by_name


def screen(case,parts,refs):
    by_code,by_name=refs;checked=[];unknown=[]
    for index,stop in enumerate(case['observedStops']):
        candidates=by_code.get('CN-12306-'+stop['code'],{}) if stop['code'] else {}
        if not candidates:
            candidates=by_name.get(stop['name'],{})
            if len(candidates)!=1:candidates={}
        if not candidates:
            unknown.append({'index':index,'name':stop['name'],'code':stop['code']});continue
        distance=min(station_distance(point,parts) for point in candidates.values())
        checked.append({'index':index,'name':stop['name'],'distanceM':round(distance,1) if math.isfinite(distance) else None,
                        'sourceMarkerNodeIds':sorted(candidates)})
    missed=[row for row in checked if row['distanceM'] is None or row['distanceM']>2000]
    return {'method':'OSM marker point to candidate polyline, local tangent-plane distance; screening only',
            'thresholdM':2000,'checked':len(checked),'unreferenced':unknown,'fartherThan2Km':missed,
            'maxDistanceM':max((row['distanceM'] for row in checked if row['distanceM'] is not None),default=None)}


def csv_screen_counts(a,b):
    """Keep unperformed geometric screens blank, distinct from measured zero."""
    return [*(len(r['stopScreen']['fartherThan2Km']) if 'stopScreen' in r else None for r in [a,b]),
            *(r['stopScreen']['checked'] if 'stopScreen' in r else None for r in [a,b]),
            *(len(r['stopScreen']['unreferenced']) if 'stopScreen' in r else None for r in [a,b])]


def native_geometry_counts(row,expected):
    """Count returned section geometry independently of engine gap accounting."""
    parts=[part for part in row['parts'] if len(part['sourceCoordinates'])>=2]
    authoritative=row.get('indicesAreAuthoritative') is True
    assigned=[part for part in parts if authoritative and type(part.get('sectionIndex')) is int
              and 0<=part['sectionIndex']<expected]
    return {'returnedGeometrySections':len({part['sectionIndex'] for part in assigned}) if authoritative else None,
            'unassignedGeometryParts':len(parts)-len(assigned),
            'physicalGapEntries':len(row['physicalGaps'])}


def aggregate_counts(results,field):
    """Unknown coverage/model support is null, with any known subtotal explicit."""
    known=[row[field] for row in results if row[field] is not None]
    subtotal=sum(known) if known else None
    return {field:subtotal if len(known)==len(results) else None,
            field+'KnownSubtotal':subtotal,field+'UnknownCases':len(results)-len(known)}


def summarize(cases,original,native,package,sources):
    old={r['id']:r for r in original['cases']};new={r['id']:r for r in native['rows']}
    if len(old)!=len(cases) or len(new)!=2*len(cases):raise ValueError('missing/duplicate engine cases')
    refs=references(package,sources);rows=[]
    for case in cases:
        for mode in ['endpoint-only','forced-known-stops']:
            a=old[case['id']]['modes'][mode];b=new[case['id']+'-'+mode]
            expected=1 if mode=='endpoint-only' else len(case['observedStops'])-1
            if len(a['legs'])!=expected or b['expectedSectionCount']!=expected:raise ValueError('scope mismatch: '+case['id'])
            a_parts=[leg['geometry']['coordinates'] for leg in a['legs'] if leg.get('ok') and leg.get('geometry')
                     and len(leg['geometry']['coordinates'])>=2]
            b_parts=[part['sourceCoordinates'] for part in b['parts']]
            geometry_counts=native_geometry_counts(b,expected)
            complete=(b.get('indicesAreAuthoritative') is True and b.get('resolvedSectionCount')==expected
                      and geometry_counts['returnedGeometrySections']==expected
                      and geometry_counts['unassignedGeometryParts']==0
                      and not b['physicalGaps'] and not b['unresolvedSections'])
            old_result={'complete':a['allLegsOk'] and len(a_parts)==expected,
                'resolvedSections':sum(bool(leg.get('ok')) for leg in a['legs']),
                'returnedGeometrySections':len(a_parts),'unassignedGeometryParts':0,'physicalGapEntries':None,
                'geometryKm':round(length(a_parts),3),'errors':[leg.get('error') for leg in a['legs'] if not leg.get('ok')],
                'ferryLegs':sum(bool(leg.get('ferry',{}).get('hasFerry')) for leg in a['legs'])}
            new_result={'complete':complete,'resolvedSections':b.get('resolvedSectionCount'),
                **geometry_counts,
                'indicesAreAuthoritative':b.get('indicesAreAuthoritative'),'status':b['status'],
                'geometryKm':round(length(b_parts),3),'gaps':b['physicalGaps'],'unresolvedSections':b['unresolvedSections'],
                'lineIDs':sorted({line['lineID'] for part in b['parts'] for line in (part.get('physicalSelection') or {}).get('lines',[])})}
            if old_result['complete']:old_result['stopScreen']=screen(case,a_parts,refs)
            if complete:new_result['stopScreen']=screen(case,b_parts,refs)
            rows.append({'id':case['id'],'trainNumber':case['trainNumber'],'trainNo':case['trainNo'],'mode':mode,
                'completeness':case['completeness'],'expectedSections':expected,'sourceURLs':case['sourceURLs'],
                'original':old_result,'railmap':new_result,
                'geometryKmDifference':round(new_result['geometryKm']-old_result['geometryKm'],3) if complete and old_result['complete'] else None})
    def mode_stats(selected):
        stats={}
        for engine in ['original','railmap']:
            results=[row[engine] for row in selected]
            stats[engine]={'complete':sum(row['complete'] for row in results),'cases':len(results),
                **aggregate_counts(results,'resolvedSections'),
                **aggregate_counts(results,'returnedGeometrySections'),
                **aggregate_counts(results,'physicalGapEntries'),
                'unassignedGeometryParts':sum(row['unassignedGeometryParts'] for row in results),
                'expectedSections':sum(row['expectedSections'] for row in selected),
                'completeCasesWithAnyReference':sum(row.get('stopScreen',{}).get('checked',0)>0 for row in results),
                'referencedStopObservations':sum(row.get('stopScreen',{}).get('checked',0) for row in results),
                'unreferencedStopObservations':sum(len(row.get('stopScreen',{}).get('unreferenced',[])) for row in results),
                'completeCasesWithStopOver2Km':sum(bool(row.get('stopScreen',{}).get('fartherThan2Km')) for row in results)}
        return stats
    summary={};full_unique={};families={}
    for mode in ['endpoint-only','forced-known-stops']:
        selected=[row for row in rows if row['mode']==mode]
        summary[mode]=mode_stats(selected)
        seen=set();unique=[]
        for row in selected:
            if row['completeness']!='full' or row['trainNo'] in seen:continue
            seen.add(row['trainNo']);unique.append(row)
        full_unique[mode]=mode_stats(unique)
        families[mode]={family:mode_stats([row for row in unique if (row['trainNumber'][0] if row['trainNumber'][0].isalpha() else 'numbered')==family])
                        for family in sorted({row['trainNumber'][0] if row['trainNumber'][0].isalpha() else 'numbered' for row in unique})}
    return {'schema':'china-real-train-engine-comparison/1','publicTrainNumbers':len(cases),
            'uniqueInternalServices':len({case['trainNo'] for case in cases}),
            'nativePhase':native['phase'],'summary':summary,'fullUniqueSummary':full_unique,
            'fullUniqueByTrainFamily':families,'rows':rows,
            'metricDefinitions':{
                'resolvedSections':{
                    'original':'Original API legs with ok=true; this does not require geometry or a physical-gap model.',
                    'railmap':'Native engine-reported resolvedSectionCount; authoritative partial results count distinct drawn section indices after excluding indices named by physical gaps. Duplicate gap entries do not imply repeated subtraction. This is neither original API success nor returned geometry coverage.'},
                'returnedGeometrySections':{
                    'original':'Original API legs with ok=true and a returned polyline of at least two points.',
                    'railmap':'Distinct authoritative integer sectionIndex values in the requested range with a returned part of at least two points; multipart sections count once. Null when indices are not authoritative.'},
                'physicalGapEntries':'Native physicalGaps entry count, including boundary entries; original is null because its API has no equivalent model, not proof of zero gaps.',
                'unassignedGeometryParts':'Returned geometry parts without an authoritative in-range section index; these cannot establish requested-section coverage.',
                'aggregateUnknowns':'A count total is null when any selected case is unknown; KnownSubtotal and UnknownCases retain its available scope.'},
            'limitations':['Solver returnability is not actual train-path accuracy.',
                'Reported native resolved counts and original API ok counts have different semantics; compare returnedGeometrySections separately from native physical-gap entries.',
                'Station sequences do not uniquely specify intermediate railway tracks.',
                'OSM marker distance is a geometric screening observation, not a physical membership/junction rule.',
                'OSM references also supply Railmap station inputs; forced-stop screening is not independent external accuracy validation.',
                'Original station coordinate transport uses the unchanged pinned offline snapshot; live probe failed.',
                'Alias train numbers and partial official stop lists are labelled; use unique-service/full subsets for conclusions.',
                'Both geometry lengths use the same spherical radius; no target-distance tuning or speed benchmark.']}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['cases','original','native','package','sources','output']:parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();load=lambda p:json.loads(p.read_text())
    result=summarize(load(args.cases)['cases'],load(args.original),load(args.native),load(args.package),load(args.sources))
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'comparison.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    with (args.output/'comparison.csv').open('w',newline='') as stream:
        writer=csv.writer(stream);writer.writerow(['train','mode','source_completeness','sections','original_complete','railmap_complete','original_resolved','railmap_reported_resolved','original_returned_geometry_sections','railmap_returned_geometry_sections','railmap_physical_gap_entries','railmap_unassigned_geometry_parts','original_available_geometry_km','railmap_available_geometry_km','km_difference','original_stops_farther_2km','railmap_stops_farther_2km','original_stops_checked','railmap_stops_checked','original_stops_unreferenced','railmap_stops_unreferenced'])
        for row in result['rows']:
            a,b=row['original'],row['railmap'];writer.writerow([row['trainNumber'],row['mode'],row['completeness'],row['expectedSections'],a['complete'],b['complete'],a['resolvedSections'],b['resolvedSections'],a['returnedGeometrySections'],b['returnedGeometrySections'],b['physicalGapEntries'],b['unassignedGeometryParts'],a['geometryKm'],b['geometryKm'],row['geometryKmDifference'],*csv_screen_counts(a,b)])
    print(json.dumps(result['summary'],ensure_ascii=False))
