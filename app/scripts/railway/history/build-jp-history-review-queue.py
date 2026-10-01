#!/usr/bin/env python3
"""Scan every adjacent N02 snapshot without inferring service dates.

Raw sources stay local. The committed report contains counts and source hashes;
--queue-dir optionally writes the complete candidate/match evidence for review.
"""
import argparse
import importlib.util
import json
from pathlib import Path


def module(name):
    path = Path(__file__).with_name(name + '.py')
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def snapshot_inputs(paths, source_root):
    """Resolve manifest source paths without relocating external extra inputs."""
    source_root = Path(source_root).resolve()
    result = {}
    for path in paths:
        path = Path(path).resolve()
        try:
            key = path.relative_to(source_root).as_posix()
        except ValueError:
            key = path.name
        if key in result and result[key] != path:
            raise ValueError('ambiguous snapshot source path: ' + key)
        result[key] = path
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', required=True)
    parser.add_argument('--extra-snapshot', action='append', default=[])
    parser.add_argument('--events', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--queue-dir')
    parser.add_argument('--provenance', help='Reviewed source URL/licence metadata keyed by archive filename')
    args = parser.parse_args()
    inventory = module('inventory-jp-history')
    diff = module('diff-jp-history')
    matcher = module('match-jp-history-events')
    paths = inventory.discover_inputs(args.source_dir) + [Path(p) for p in args.extra_snapshot]
    # Establish chronological order and reject duplicate releases before scanning.
    provenance = inventory.load_provenance(args.provenance)
    manifest = inventory.build_inventory(paths, args.source_dir, provenance, record_mode='manifest')
    source_root = Path(args.source_dir)
    inputs = snapshot_inputs(paths, source_root)
    by_id = {item['snapshot_id']: inputs[item['provenance']['source_path']]
             for item in manifest['snapshots']}
    events = json.loads(Path(args.events).read_text())
    output = {'schema_version': '1', 'policy': {
        'infer_day_dates_from_snapshots': False, 'auto_verify_candidates': False,
        'routing_and_display_verified': False}, 'comparisons': []}
    previous = None
    for entry in manifest['snapshots']:
        current = inventory.inventory_snapshot(by_id[entry['snapshot_id']], args.source_dir, provenance,
                                               record_mode='summary')
        if previous is not None:
            candidates = diff.diff_snapshots(previous, current)
            matches = matcher.match_candidates(candidates, events)
            comparison = {'interval': candidates['interval'],
                          'summary': candidates['summary'],
                          'sources': [previous['provenance'], current['provenance']],
                          'matching_summary': matches['summary']}
            output['comparisons'].append(comparison)
            if args.queue_dir:
                directory = Path(args.queue_dir)
                directory.mkdir(parents=True, exist_ok=True)
                stem = previous['snapshot_id'] + '--' + current['snapshot_id']
                inventory.write_json(candidates, str(directory / (stem + '.candidates.json')))
                inventory.write_json(matches, str(directory / (stem + '.matches.json')))
            print(f"{previous['snapshot_id']} -> {current['snapshot_id']}: "
                  f"{candidates['summary']['candidate_count']} candidates", flush=True)
        previous = current
    output['summary'] = {'snapshot_count': len(manifest['snapshots']),
                         'comparison_count': len(output['comparisons']),
                         'candidate_count': sum(c['summary']['candidate_count']
                                                for c in output['comparisons'])}
    inventory.write_json(output, args.output)


if __name__ == '__main__':
    main()
