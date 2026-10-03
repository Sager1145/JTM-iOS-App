#!/usr/bin/env python3
"""Add source-backed station-order direction without re-encoding package geometry.

Run without --write to inspect the finite metadata diff; --check fails until
the package contains it. The inherited physical track directions remain
unchanged, including all six unassigned pairs.
"""
import argparse
import json
import re
from pathlib import Path


def apply(package_text, registry):
    package = json.loads(package_text)
    by_id = {line['id']: line for line in package['lines']}
    updates = {}
    for family in registry['families']:
        base = by_id[family['baseLineID']]
        assert base['stations'][0][0] == family['baseFirstStationCode'], base['id']
        assert base['stations'][-1][0] == family['baseLastStationCode'], base['id']
        direction = family['stationOrderDirection']
        assert direction in ('up', 'down')
        updates[base['id']] = {'stationOrderDirection': direction}
        for pair in family['pairs']:
            row = by_id[pair['lineID']]
            assert row['alignmentOf'] == base['id'], row['id']
            assert [station[0] for station in row['stations']] == pair['stationCodes'], row['id']
            assert row['alignmentDirection'] == pair['alignmentDirection'], row['id']
            declaration = next(item for item in base['alignmentPairs'] if item['with'] == row['id'])
            assert declaration['direction'] == pair['mainAlignmentDirection'], row['id']
            indices = [next(i for i, station in enumerate(base['stations']) if station[0] == code)
                       for code in pair['stationCodes']]
            assert indices == sorted(set(indices)), row['id']
            updates[row['id']] = {'stationOrderDirection': direction}
    for pair in registry['unassignedPairs']:
        row = by_id[pair['lineID']]
        assert row['alignmentDirection'] == 'unassigned', row['id']
        assert [station[0] for station in row['stations']] == pair['stationCodes'], row['id']
    for override in registry.get('lineOverrides', []):
        row = by_id[override['lineID']]
        assert [station[0] for station in row['stations']] == override['stationCodes'], row['id']
        assert override['permittedTraversal'] in ('forward', 'reverse')
        updates.setdefault(row['id'], {})['permittedTraversal'] = override['permittedTraversal']

    # Locate each whole line object using the JSON decoder, then change only
    # its single top-level scalar metadata field. All existing coordinate and
    # station tokens remain byte-for-byte intact.
    decoder = json.JSONDecoder()
    cursor = re.search(r'"lines"\s*:\s*\[', package_text).end()
    replacements = []
    changes = []
    for line in package['lines']:
        while package_text[cursor] in ' \r\n\t,':
            cursor += 1
        row, end = decoder.raw_decode(package_text, cursor)
        block = package_text[cursor:end]
        changed = False
        for field, target in updates.get(line['id'], {}).items():
            if row.get(field) == target:
                continue
            value = json.dumps(target)
            pattern = r'("' + field + r'"\s*:\s*)"[^"]*"'
            if re.search(pattern, block):
                block = re.sub(pattern, lambda match: match[1] + value, block, count=1)
            else:
                block = block[:-1] + ',"' + field + '":' + value + '}'
            changed = True
            changes.append({'lineID': line['id'], 'field': field,
                            'before': row.get(field), 'after': target})
        if changed:
            replacements.append((cursor, end, block))
        cursor = end
    for start, end, block in reversed(replacements):
        package_text = package_text[:start] + block + package_text[end:]
    # Prove the surgical edit changes only the declared scalar fields.
    revised = json.loads(package_text)
    for original, edited in zip(package['lines'], revised['lines']):
        expected = dict(original)
        if original['id'] in updates:
            expected.update(updates[original['id']])
        assert expected == edited, original['id']
    assert {key: value for key, value in package.items() if key != 'lines'} == {
        key: value for key, value in revised.items() if key != 'lines'}
    return package_text, changes


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=root / 'public/rail/jp-2025.json')
    parser.add_argument('--registry', type=Path,
                        default=Path(__file__).with_name('jp-directional-alignment-overrides.json'))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--write', action='store_true')
    mode.add_argument('--check', action='store_true')
    args = parser.parse_args()
    text = args.package.read_text()
    updated, changes = apply(text, json.loads(args.registry.read_text()))
    print(json.dumps({'changedRows': len(changes), 'changes': changes}, ensure_ascii=False, indent=2))
    if args.write and changes:
        args.package.write_text(updated)
    if args.check and changes:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
