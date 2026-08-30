#!/usr/bin/env python3
"""Write the line-by-line release ledger for North American rail packages."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from collections import defaultdict


def load(path):
    with open(path, encoding='utf-8') as source:
        return json.load(source)


def published_rows(packages, audits):
    findings = defaultdict(list)
    for audit in audits:
        for item in audit.get('findings') or ():
            findings[item.get('line')].append(item)
    rows = []
    for package in packages:
        country = package.get('country')
        verified = set(
            ((package.get('geometrySource') or {})
             .get('verifiedOfficialNetworks') or {}).keys())
        # Québec is filtered directly from the operator-tagged provincial
        # survey rather than from a route-specific normalized manifest.
        verified.add('quebec-mtq-via')
        for line in package.get('lines') or ():
            issues = findings.get(line['id'], [])
            severity = ('error' if any(x.get('severity') == 'ERROR' for x in issues)
                        else 'warning' if issues else 'passed')
            source = line.get('geometrySource')
            rows.append({
                'lineId': line['id'],
                'country': country,
                'status': 'published',
                'review': severity,
                'operator': line.get('operator'),
                'name': line.get('name'),
                'sourceFeed': line.get('sourceFeed'),
                'sourceRouteId': None,
                'geometrySource': source,
                'officialSpatialGeometry': source in verified,
                'colorReference': line.get('colorReference'),
                'colorSource': line.get('colorSource'),
                'stationCount': len(line.get('stations') or ()),
                'lengthKm': line.get('lengthKm'),
                'issues': [{key: value for key, value in issue.items()
                            if key not in ('country', 'line')}
                           for issue in issues],
            })
    return rows


def blocked_rows(report):
    grouped = {}
    for feed in report.get('feeds') or ():
        slug = feed.get('slug')
        for item in feed.get('dropped') or ():
            route = item.get('route') or item.get('relation')
            line = item.get('line')
            why = item.get('why') or 'not published'
            suffix = item.get('suffix') or ''
            identity = (('line', line) if line else
                        ('route', slug, str(route), suffix) if route is not None else
                        ('unattributed', slug, why))
            row = grouped.setdefault(identity, {
                'lineId': line,
                'country': None,
                'status': 'blocked',
                'review': 'error',
                'operator': None,
                'name': item.get('name'),
                'sourceFeed': slug,
                'sourceRouteId': route,
                'geometrySource': item.get('geometrySource'),
                'officialSpatialGeometry': False,
                'colorReference': None,
                'colorSource': None,
                'stationCount': None,
                'lengthKm': None,
                'issues': [],
            })
            issue = {key: value for key, value in item.items()
                     if key not in ('line', 'route', 'relation', 'name')}
            if issue not in row['issues']:
                row['issues'].append(issue)
    return list(grouped.values())


def write_json(path, payload):
    with open(path + '.tmp', 'w', encoding='utf-8') as target:
        json.dump(payload, target, ensure_ascii=False, indent=2)
        target.write('\n')
    os.replace(path + '.tmp', path)


def write_markdown(path, payload):
    summary = payload['summary']
    with open(path + '.tmp', 'w', encoding='utf-8') as target:
        target.write('# North America line-by-line review\n\n')
        target.write(f"Generated {payload['generatedAt']}. ")
        target.write(f"Published: {summary['published']}; blocked findings: ")
        target.write(f"{summary['blocked']}; warnings: {summary['warnings']}; ")
        target.write(f"errors among published lines: {summary['publishedErrors']}.\n\n")
        target.write('| Status | Country | Feed / line | Name | Geometry | Colour | Findings |\n')
        target.write('|---|---|---|---|---|---|---|\n')
        for row in payload['lines']:
            identity = row.get('lineId') or (
                f"{row.get('sourceFeed')}:{row.get('sourceRouteId')}")
            issues = '; '.join(str(x.get('why') or x.get('message') or
                                   x.get('check') or 'review required')
                               for x in row.get('issues') or ())
            target.write('| %s | %s | %s | %s | %s | %s | %s |\n' % (
                row['status'], row.get('country') or '', identity or '',
                (row.get('name') or '').replace('|', '\\|'),
                row.get('geometrySource') or '',
                row.get('colorReference') or '', issues.replace('|', '\\|')))
    os.replace(path + '.tmp', path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', action='append', required=True)
    parser.add_argument('--audit', action='append', default=[])
    parser.add_argument('--build-report', required=True)
    parser.add_argument('--output', required=True,
                        help='output basename; .json and .md are added')
    args = parser.parse_args()

    rows = published_rows([load(path) for path in args.package],
                          [load(path) for path in args.audit])
    rows.extend(blocked_rows(load(args.build_report)))
    rows.sort(key=lambda row: (row['status'] != 'published',
                              row.get('country') or '',
                              row.get('lineId') or '',
                              row.get('sourceFeed') or '',
                              str(row.get('sourceRouteId') or '')))
    payload = {
        'schemaVersion': 1,
        'generatedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
        'summary': {
            'published': sum(row['status'] == 'published' for row in rows),
            'blocked': sum(row['status'] == 'blocked' for row in rows),
            'warnings': sum(row['review'] == 'warning' for row in rows),
            'publishedErrors': sum(row['status'] == 'published'
                                   and row['review'] == 'error' for row in rows),
        },
        'lines': rows,
    }
    write_json(args.output + '.json', payload)
    write_markdown(args.output + '.md', payload)
    print(json.dumps(payload['summary'], ensure_ascii=False))


if __name__ == '__main__':
    main()
