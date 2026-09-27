#!/usr/bin/env python3
"""Report prerequisites for dated route audits; never treat connectivity as via proof."""
from collections import defaultdict
import json
from train_timetable import DEFAULT_CANONICAL, load_manifest, load_dataset, validate_dataset, write_json


def main():
    manifest=load_manifest(DEFAULT_CANONICAL)
    data,origins=load_dataset(DEFAULT_CANONICAL,manifest)
    errors=validate_dataset(data,origins,manifest)
    if errors: raise SystemExit('\n'.join(errors))
    stops,lines,operators=defaultdict(list),defaultdict(list),defaultdict(list)
    for row in data['stop_times']:
        if row['call_type'] in ['origin','passenger_stop','destination']: stops[row['trip_id']].append(row)
    for row in data['trip_line_segments']: lines[row['trip_id']].append(row)
    for row in data['trip_operator_segments']: operators[row['trip_id']].append(row)
    ledger=[]
    for trip in data['trips']:
        ordered=sorted(stops[trip['trip_id']],key=lambda r:r['stop_sequence'])
        ledger.append(dict(tripId=trip['trip_id'],timetableVersionId=trip['timetable_version_id'],
            calendarId=trip['calendar_id'],passengerLegs=len(ordered)-1,
            missingPrerequisites=[name for name,rows in [('ordered_route_lines',lines[trip['trip_id']]),
                                                        ('operator_segments',operators[trip['trip_id']])] if not rows],
            solverStatus='not_run',viaStatus='unverified',dateApplicabilityStatus='calendar_materialization_required',
            reason='No dated solver execution attests this trip. Explicit route constraints and independent source review are required.'))
    report=dict(schemaVersion=1,asOfDate=manifest['as_of_date'],complete=False,solverExecuted=False,
        tripTemplates=len(ledger),passengerLegs=sum(r['passengerLegs'] for r in ledger),
        passedLegs=0,unverifiedLegs=sum(r['passengerLegs'] for r in ledger),trips=ledger)
    output=DEFAULT_CANONICAL/'audits/train-timetable-routes.json'
    write_json(output,report)
    print(f'Route prerequisites reported: {report["unverifiedLegs"]} legs unverified; solver not run')


if __name__=='__main__': main()
