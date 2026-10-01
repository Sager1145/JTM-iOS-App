#!/usr/bin/env python3
"""Parse a locally obtained JR East train HTML into a review candidate only.

Calendar cells marked `ok` are the exact displayed schedule. Other cells may
link to a different daily schedule and are never inferred from their numbers.
"""
import argparse
from datetime import date
from html.parser import HTMLParser
import json
from pathlib import Path
import re


class Node:
    def __init__(self, tag='', attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def text(self):
        return ''.join(c if isinstance(c, str) else c.text() for c in self.children).strip()

    def find(self, tag, cls=None):
        result = []
        for child in self.children:
            if isinstance(child, Node):
                if child.tag == tag and (cls is None or cls in child.attrs.get('class', '').split()):
                    result.append(child)
                result.extend(child.find(tag, cls))
        return result


class Document(HTMLParser):
    VOID = {'meta', 'link', 'br', 'img', 'input', 'hr', 'source', 'area', 'wbr'}

    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root = Node()
        self.stack = [self.root]
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in self.VOID:
            self.stack.append(node)

    def handle_endtag(self, tag):
        for i in range(len(self.stack)-1, 0, -1):
            if self.stack[i].tag == tag:
                self.stack = self.stack[:i]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def parse(html, url):
    doc = Document(html).root
    fields = {}
    for row in doc.find('tr', 'train'):
        th, td = row.find('th'), row.find('td')
        if th and td:
            fields[th[0].text()] = td[0].text()
    if fields.get('列車種別') != '特急':
        raise ValueError('Expected explicitly classified conventional limited express')
    if not fields.get('列車番号') or not fields.get('列車名'):
        raise ValueError('Missing train identity')
    dates = []
    for table in doc.find('table', 'calendar-month'):
        captions = table.find('caption')
        match = re.fullmatch(r'(\d{4})年(\d{1,2})月', captions[0].text()) if captions else None
        if not match:
            raise ValueError('Unrecognized calendar month')
        for cell in table.find('td', 'ok'):
            value = cell.text()
            if not value.isdecimal():
                raise ValueError('Ambiguous calendar cell')
            dates.append(date(int(match[1]), int(match[2]), int(value)).isoformat())
    stops = []
    last_seconds = -1
    for row in doc.find('tr', 'time'):
        names, cells = row.find('th', 'time'), row.find('td', 'time')
        if len(names) != 1 or len(cells) != 1:
            raise ValueError('Malformed stop row')
        values = dict(arrival_time=None, departure_time=None)
        for clock, kind in re.findall(r'(\d{2}:\d{2})\s*(着|発)', cells[0].text()):
            hour, minute = map(int, clock.split(':'))
            seconds = hour*3600 + minute*60
            if minute > 59 or seconds < last_seconds:
                raise ValueError('Invalid or ambiguous midnight time; explicit day evidence required')
            last_seconds = seconds
            key = 'arrival_time' if kind == '着' else 'departure_time'
            if values[key] is not None:
                raise ValueError('Multiple schedule variants in one stop row')
            values[key] = clock
        if not any(values.values()):
            raise ValueError('Stop without a published time')
        platforms = row.find('td', 'platform')
        stops.append(dict(stop_sequence=len(stops)+1, name_snapshot=names[0].text(),
                          platform=platforms[0].text() or None if platforms else None, **values))
    if len(stops) < 2 or not dates:
        raise ValueError('Missing stops or explicit operating dates')
    for i, stop in enumerate(stops):
        stop['call_type'] = 'origin' if i == 0 else 'destination' if i == len(stops)-1 else 'passenger_stop'
    return dict(schema_version=1, candidate_status='needs_review', source_url=url,
                train_number=fields['列車番号'], public_name=fields['列車名'],
                operating_dates=sorted(set(dates)), stop_times=stops,
                notes='Station identities, operators, route lines and license require separate evidence. No pass records inferred.')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('html', type=Path)
    p.add_argument('--url', required=True)
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    normalized = Path(__file__).resolve().parents[2] / 'app/data/train-service-history/normalized'
    if args.output.resolve().is_relative_to(normalized.resolve()):
        p.error('Parser output must be a research candidate, not canonical normalized data')
    value = parse(args.html.read_text(), args.url)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)+'\n')


if __name__ == '__main__':
    main()
