#!/usr/bin/env python3
"""Build CN compact-v1 and N02 resources from original China OSM topology.

The default publishes to --root; --output-dir writes the identical relative
artifact layout beneath a scratch directory for review before publication.
"""
import argparse
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path
from cn_package import ChinaBuilder, write_outputs, acquisition_record


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database',type=Path,required=True)
    parser.add_argument('--official-dir',type=Path,required=True)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path)
    parser.add_argument('--reviewed-stations',type=Path)
    parser.add_argument('--reviewed-physical-sections',type=Path)
    args=parser.parse_args()
    if not args.database.is_file(): parser.error('source topology database does not exist')
    connection=sqlite3.connect('file:'+str(args.database.resolve())+'?mode=ro',uri=True)
    metadata=dict(connection.execute('SELECT key,value FROM metadata'))
    if not metadata.get('counts') or not metadata.get('source'):
        parser.error('source extraction is incomplete: final metadata counts/source required')
    counts=json.loads(metadata['counts'])
    if not counts.get('nodes') or not counts.get('ways'):
        parser.error('source topology has no completed node/way records')
    acquisition=acquisition_record(metadata)
    if not acquisition or not acquisition.get('sha256') or not acquisition.get('replicationTimestamp') or acquisition.get('crs')!='WGS84':
        parser.error('completed original-PBF acquisition/header integrity record required beside source PBF')
    reviewed=args.reviewed_stations or args.root/'railway-sources/china-reviewed-stations.json'
    builder=ChinaBuilder(connection,args.official_dir,
        reviewed_stations=reviewed if reviewed.is_file() else None,
        progress=lambda message:print(message,file=sys.stderr,flush=True))
    try:
        result=builder.build()
        if not result['package']['lines']:
            parser.error('no verified passenger lines; refusing to publish an empty CN package')
        physical=args.reviewed_physical_sections or args.root/'railway-sources/china-reviewed-physical-sections.json'
        if physical.is_file():
            spec=importlib.util.spec_from_file_location('cn_reviewed_physical',Path(__file__).with_name('build-china-physical-junctions.py'))
            module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            manifest=json.loads(physical.read_text())
            features,proofs=module.compile_reviewed_physical_sections(connection,result['package'],manifest)
            station_features=module.compile_reviewed_physical_station_bindings(connection,manifest,proofs,builder.official)
            result['sections']['features'].extend(features)
            result['stations']['features'].extend(station_features)
            result['physicalSources']=proofs
        outputs=write_outputs(result,args.root,args.output_dir)
        print(json.dumps({'counts':result['coverage']['counts'],'outputs':outputs},ensure_ascii=False))
    finally:
        builder.db.close()


if __name__=='__main__':
    main()
