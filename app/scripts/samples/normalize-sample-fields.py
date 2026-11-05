#!/usr/bin/env python3
"""Normalize bundled sample rides to the fields the iOS ride editor writes.

Inputs are the sample stores (train-store*.json, special-samples/*.json); the
precomputed sample directories are derived and must be regenerated afterwards
with scripts/build/precompute-train-parts.mjs.

Field rules (see app/data/sample-data/SOURCES.md):
- `number` holds the local service name, plus the operating number in
  full-width brackets when known. A romanized gloss moves to `number_en`;
  provenance asides (時刻推定, 車号不明, 臨時と推定) move to `notes`.
- `direction` is the editor's word, `up` or `down`, from RailCore's
  TravelDirection inference (input `--directions`, a {train_id: "up|line|km"}
  dump). Where inference has no vote, an existing up/down or loop word
  (内回り/外回り) is retained. Otherwise the key is dropped,
  as the editor leaves it empty; `unknown` and terminus names are not kept.
- Every stop carries `platform_number` (null when unknown), as the editor writes.
- `--overrides` JSON {train_id: {train fields..., "stops": {name: {...}}}} applies
  source-reviewed values (see SOURCES.md); stop entries may set arrival,
  departure, platform_number or stop_type of an existing stop only.

Usage (the 2026-11-05 inputs are kept beside this script):
  I=app/scripts/samples/normalize-sample-fields.inputs
  python3 -I app/scripts/samples/normalize-sample-fields.py --directions $I/directions.json \
    --english $I/number-en.json --overrides $I/overrides.json [--check]
directions.json was dumped from RailCore TravelDirection.infer against app/public/rail/<cc>-2025.json.
"""
import argparse
import json
import re
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
DATA = APP / 'data'
STORES = ['train-store.json', 'train-store-tw.json', 'train-store-hk.json', 'train-store-kr.json',
          'train-store-mo.json', 'special-samples/new-year-grand-loop.json',
          'special-samples/tokyo-limited-express-loop.json']
GROUP = re.compile(r'（([^（）]*)）')
OPNUM = re.compile(r'[0-9]+[A-Za-z]*')
GLOSS = re.compile(r"[A-Za-z0-9ĀāĒēĪīŌōŪū:'’ .()/&,\-–α-ω!]+")
ASIDES = {
    '時刻推定': '時刻は乗車記録からの推定値で、公式時刻表では未確認。',
    '車号不明・時刻推定': '列車番号は不明。時刻は乗車記録からの推定値で、公式時刻表では未確認。',
    '臨時と推定': '臨時列車と推定（公式時刻表では未確認）。',
}
LOOP_WORDS = {'内回り', '外回り'}
TIME = re.compile(r'([01][0-9]|2[0-9]|3[0-5]):[0-5][0-9]')
STOP_TYPES = {'origin', 'passenger_stop', 'pass_through', 'operational_stop', 'destination'}


def split_number(number):
    gloss, notes, keep = None, [], number
    for group in GROUP.findall(number):
        if group in ASIDES:
            notes.append(ASIDES[group])
        elif GLOSS.fullmatch(group) and not OPNUM.fullmatch(group):
            gloss = gloss or group.strip()
        else:
            continue
        keep = keep.replace(f'（{group}）', '', 1)
    return re.sub(r'\s+', ' ', keep).strip(), gloss, notes


def append_note(train, note):
    current = train.get('notes') or ''
    if note not in current:
        train['notes'] = (current + note) if current else note


def normalize(train, directions, english, override):
    stop_overrides = dict(override.pop('stops', {}))
    for key, value in override.items():
        if value is None:
            train.pop(key, None)
        else:
            train[key] = value
    number, gloss, notes = split_number(train['number'])
    train['number'] = number
    if not train.get('number_en'):
        value = english.get(train['id']) or gloss
        if value:
            train['number_en'] = value
    for note in notes:
        append_note(train, note)
    inferred = (directions.get(train['id']) or 'nil').split('|')[0]
    if inferred in ('up', 'down'):
        train['direction'] = inferred
    elif train.get('direction') not in LOOP_WORDS | {'up', 'down'}:
        train.pop('direction', None)
    for stop in train['stops']:
        stop.setdefault('platform_number', None)
    for stop in train['stops']:
        for key, value in stop_overrides.pop(stop['name'], {}).items():
            stop[key] = value
    if stop_overrides:
        raise ValueError(f"{train['id']}: override names unknown stops {sorted(stop_overrides)}")
    validate(train)
    return train


def validate(train):
    stops = train['stops']
    if len(stops) < 2:
        raise ValueError(f"{train['id']}: fewer than two stops")
    for index, stop in enumerate(stops):
        if stop['stop_type'] not in STOP_TYPES:
            raise ValueError(f"{train['id']}: stop_type {stop['stop_type']}")
        for key in ('arrival', 'departure'):
            if stop[key] is not None and not TIME.fullmatch(stop[key]):
                raise ValueError(f"{train['id']} {stop['name']}: {key} {stop[key]!r}")
    if stops[0]['arrival'] and stops[0]['departure'] or stops[-1]['arrival'] and stops[-1]['departure']:
        raise ValueError(f"{train['id']}: an endpoint carries both times")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directions', required=True)
    parser.add_argument('--english', required=True)
    parser.add_argument('--overrides')
    parser.add_argument('--check', action='store_true', help='report changes without writing')
    args = parser.parse_args()
    directions = json.loads(Path(args.directions).read_text())
    english = json.loads(Path(args.english).read_text())
    overrides = json.loads(Path(args.overrides).read_text()) if args.overrides else {}
    unused = set(overrides)
    for name in STORES:
        path = DATA / name
        text = path.read_text()
        compact = not text.startswith('{\n')
        store = json.loads(text)
        before = json.dumps(store, ensure_ascii=False)
        for train in store['trains']:
            unused.discard(train['id'])
            normalize(train, directions, english, json.loads(json.dumps(overrides.get(train['id'], {}))))
        changed = json.dumps(store, ensure_ascii=False) != before
        print(f"{name}: {len(store['trains'])} rides, {'changed' if changed else 'unchanged'}")
        if changed and not args.check:
            path.write_text(json.dumps(store, ensure_ascii=False, separators=(',', ':')) if compact
                            else json.dumps(store, ensure_ascii=False, indent=2) + '\n')
    if unused:
        raise SystemExit(f'overrides for unknown rides: {sorted(unused)}')


if __name__ == '__main__':
    main()
