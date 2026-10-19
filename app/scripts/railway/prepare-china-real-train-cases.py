#!/usr/bin/env python3
"""Prepare explicit real-train comparison inputs from retained official schedules.

This builder downloads nothing and runs neither engine. Partial stop lists and
same-service public-number aliases remain labelled, never silently completed.
"""
import argparse
import json
from pathlib import Path


def build(records):
    cases=[];trains=[];seen=set()
    for record in records:
        number=record['trainNumber'];day=record['serviceDate']
        identity=f"CN-REAL-{number.replace('/', '_')}-{day.replace('-', '')}"
        if identity in seen: raise ValueError('duplicate public train/date: '+identity)
        seen.add(identity)
        if not record['sourceURLs'] or len(record['stops'])<2:
            raise ValueError('official source and observed ordered stops required')
        stops=[{'name':stop['name'],'code':stop.get('code') or stop.get('telecode')}
               for stop in record['stops']]
        references=[stop['code'] or stop['name'] for stop in stops]
        cases.append({'id':identity,'trainNumber':number,'trainNo':record['trainNo'],
            'serviceDate':day,'completeness':record['completeness'],
            'sourceURLs':record['sourceURLs'],'from':references[0],'to':references[-1],
            'knownStops':references,'observedStops':stops})
        for mode,selected in [('endpoint-only',[stops[0],stops[-1]]),('forced-known-stops',stops)]:
            def endpoint(stop,prefix):
                value={prefix:stop['name']}
                if stop['code']: value[prefix+'_n02_station_code']='CN-12306-'+stop['code']
                return value
            train_stops=[]
            for index,stop in enumerate(selected):
                row={'name':stop['name'],'arrival':None,'departure':None,
                     'stop_type':'origin' if index==0 else 'destination' if index==len(selected)-1 else 'passenger_stop',
                     'ride_segment':True}
                if stop['code']: row['n02_station_code']='CN-12306-'+stop['code']
                train_stops.append(row)
            trains.append({'id':identity+'-'+mode,'date':day,'region':'cn','number':number,
                'train_type':'高铁' if number.startswith('G') else '动车' if number.startswith(('D','C')) else '普速',
                'company':'','origin':selected[0]['name'],'destination':selected[-1]['name'],
                'direction':'down','visible':True,'style':{'color':'#D2232A'},
                'route_policy':{'mode':'single_primary_route','jr_only':False,'allow_alternatives':False,
                    'allow_browser_straight_line_fallback':False,'allowed_institution_type_codes':[],
                    'preferred_line_names':[],'preferred_operator_names':[],'institution_filter_mode':'soft'},
                'route_sections':[{**endpoint(left,'from'),**endpoint(right,'to')}
                                  for left,right in zip(selected,selected[1:])],
                'stops':train_stops})
    return {'schema':'china-real-train-cases/1','cases':cases}, {'schema_version':'1.3','trains':trains}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources',type=Path,nargs='+',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists(): parser.error('use a new output directory to preserve prior evidence')
    records=[record for path in args.sources for record in json.loads(path.read_text())['records']]
    cases,native=build(records)
    args.output.mkdir(parents=True)
    for name,data in [('cases.json',cases),('native-journeys.json',native)]:
        (args.output/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'publicTrainNumbers':len(cases['cases']),
        'uniqueInternalServices':len({case['trainNo'] for case in cases['cases']}),
        'observedStops':sum(len(case['observedStops']) for case in cases['cases']),
        'nativeJourneys':len(native['trains']),
        'nativeRequestedSections':sum(len(train['route_sections']) for train in native['trains'])}))
