#!/usr/bin/env python3
"""Stage one locally obtained JR East source for review; never write canonical facts."""
import argparse
import importlib.util
import json
from pathlib import Path
from train_timetable import DEFAULT_CANONICAL, load_manifest, load_dataset, write_json


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source_id')
    p.add_argument('html',type=Path)
    p.add_argument('--candidate-id',required=True)
    args=p.parse_args()
    if not args.candidate_id or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-' for c in args.candidate_id):
        p.error('candidate-id must be a plain identifier')
    data,_=load_dataset(DEFAULT_CANONICAL,load_manifest(DEFAULT_CANONICAL))
    source=next((s for s in data['source_documents'] if s['source_id']==args.source_id),None)
    if source is None: p.error('source_id must already be registered')
    if not source['automated_extraction_allowed']:
        p.error('registered source has no automated extraction authorization; retain manually reviewed candidate instead')
    spec=importlib.util.spec_from_file_location('jreast_trip',Path(__file__).with_name('parse-jreast-trip.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    candidate=module.parse(args.html.read_text(),source['url_or_locator'])
    candidate['source_id']=args.source_id
    output=DEFAULT_CANONICAL/'candidates'/f'{args.candidate_id}.json'
    write_json(output,candidate)
    print(f'Staged {output}; full canonical validation and human review still required')


if __name__=='__main__': main()
