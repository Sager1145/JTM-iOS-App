"""Extract published Japanese readings through retained verified station identities.

Only explicit operator reading fields are accepted. Hiragana/katakana conversion
is a Unicode script conversion of a published reading, never romanization.
"""
from collections import Counter, defaultdict
import gzip
import hashlib
import html
import json
from pathlib import Path
import re
import unicodedata


def plain(value):
    return ' '.join(html.unescape(re.sub(r'<[^>]*>', '', value)).split())


def field(document, class_name):
    m = re.search(r'<(\w+)\b[^>]*class="[^"]*\b' + re.escape(class_name) + r'\b[^"]*"[^>]*>(.*?)</\1>', document, re.S)
    return plain(m.group(2)) if m else ''


def reading_forms(value):
    """Return script variants only for kana-only published readings."""
    value = unicodedata.normalize('NFC', plain(value)).replace(' ', '')
    if not value or not re.fullmatch(r'[ぁ-ゖァ-ヶー・]+', value):
        return None
    hira = ''.join(chr(ord(c) - 0x60) if 'ァ' <= c <= 'ヶ' else c for c in value)
    kata = ''.join(chr(ord(c) + 0x60) if 'ぁ' <= c <= 'ゖ' else c for c in value)
    return hira, kata


def native_identity(value):
    # Same typography rules used by the retained private-railway verifier.
    value = re.sub(r'[\U000E0100-\U000E01EF\uFE00-\uFE0F]', '', value)
    value = re.sub(r'[(（]阪急[)）]$', '', value)
    return unicodedata.normalize('NFKC', value).replace('ヶ', 'ケ').replace('ヵ', 'カ').replace(' ', '')


def read_source(path, expected_hash=None):
    raw = path.read_bytes()
    if raw[:2] == b'\x1f\x8b':
        raw = gzip.decompress(raw)
    digest = hashlib.sha256(raw).hexdigest()
    if expected_hash and digest != expected_hash:
        raise ValueError('source hash mismatch: ' + str(path))
    return raw.decode('utf-8'), digest


def build_kana_evidence(app):
    """Build station-kana-evidence/1 from an app directory, entirely offline."""
    app = Path(app)
    root = app / 'data/station-english-sources'
    candidates = defaultdict(list)
    input_hashes = {}

    def read_mapping(path):
        raw = path.read_bytes()
        input_hashes[path.relative_to(app).as_posix()] = hashlib.sha256(raw).hexdigest()
        return json.loads(raw)

    source_cache = {}

    def tracked_source(path, expected_hash=None):
        if path not in source_cache:
            input_hashes[path.relative_to(app).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
            source_cache[path] = read_source(path)
        document, digest = source_cache[path]
        if expected_hash and digest != expected_hash:
            raise ValueError('source hash mismatch: ' + str(path))
        return document, digest

    def append(operator, station_id, name, reading, path, digest, source, locator, line_ids=None, published_kata=None):
        forms = reading_forms(reading)
        if not forms:
            return
        if published_kata and reading_forms(published_kata) != forms:
            raise ValueError('conflicting published reading scripts: ' + str(path))
        candidates[(operator, str(station_id))].append({
            'name': name, 'kana': forms[0], 'katakana': forms[1],
            'officialStationId': str(station_id), 'source': source,
            'rawSource': path.relative_to(app).as_posix(), 'sha256': digest,
            'locator': locator, 'publishedReading': plain(reading),
            'publishedKatakana': published_kata, 'officialLineIds': line_ids,
            'transformation': 'Unicode kana script conversion only',
        })

    manifest = read_mapping(root / 'jp/manifest.json')
    for source_id in ('hokkaido', 'central-ja'):
        meta = manifest[source_id]
        path = root / 'jp' / meta['filename']
        document, digest = tracked_source(path, meta['sha256'])
        rows = json.loads(document)
        if source_id == 'hokkaido':
            for row in rows:
                append('北海道旅客鉄道', row['key'], row['ja'], row.get('hira', ''), path, digest,
                       meta['url'], 'key=' + row['key'] + '; fields=hira,kata', published_kata=row.get('kata'))
        else:
            for row in rows['lst']:
                if row['ryokakuSenkuKbn'] in ('1', '5'):
                    append('東海旅客鉄道', row['ryokakuEkiCd'], row['ekiMei'], row.get('ekiMeiYomigana', ''),
                           path, digest, meta['url'], 'ryokakuSenkuCd=' + row['ryokakuSenkuCd'] + '; ryokakuEkiCd=' + row['ryokakuEkiCd'] + '; field=ekiMeiYomigana',
                           line_ids=[row['ryokakuSenkuCd']])

    private_manifest = read_mapping(root / 'jp-private/manifest.json')
    for meta in private_manifest:
        sid = meta['id']
        if not meta.get('rawFile') or not (sid == 'kintetsu-master' or sid == 'hankyu-ja' or sid.startswith(('meitetsu-station-', 'keihan-station-', 'tokyu-station-', 'tokyu-web-'))):
            continue
        path = root / 'jp-private' / meta['rawFile']
        document, digest = tracked_source(path, meta['sha256'])
        def add(operator, station_id, name, reading, locator):
            append(operator, station_id, name, reading, path, digest, meta['source'], locator)
        if sid == 'kintetsu-master':
            for row in json.loads(document):
                if row.get('路線1') and row.get('駅名英語'):
                    add('近畿日本鉄道', str(row['駅コード']).zfill(5), row['駅名'], row.get('駅名ふりがな', ''), '駅コード=' + str(row['駅コード']) + '; field=駅名ふりがな')
        elif sid == 'hankyu-ja':
            for m in re.finditer(r'<a\b[^>]*href="/station/([^/"?]+)\.html"[^>]*>\s*<dl class="name">(.*?)</dl>', document, re.S):
                name = re.search(r'<dd class="station">(.*?)<p\b[^>]*>(.*?)</p>', m.group(2), re.S)
                if name:
                    add('阪急電鉄', m.group(1), plain(name.group(1)), plain(name.group(2)), 'station/' + m.group(1) + '.html; dd.station > p')
        elif sid.startswith('meitetsu-station-'):
            add('名古屋鉄道', sid.removeprefix('meitetsu-station-'), field(document, 'stName1'), field(document, 'stName2'), 'stName1/stName2')
        elif sid.startswith('keihan-station-'):
            add('京阪電気鉄道', sid.removeprefix('keihan-station-'), field(document, 'station-detail-heading1__title'), field(document, 'station-detail-heading1__furigana--hiragana'), 'station-detail-heading1__furigana--hiragana')
        elif sid.startswith('tokyu-station-'):
            m = re.search(r'<dt[^>]*>ふりがな</dt>\s*<dd[^>]*>(.*?)</dd>', document, re.S)
            if m:
                add('東急電鉄', sid.removeprefix('tokyu-station-'), field(document, 'portal-station__name-kanji'), plain(m.group(1)), 'portal-station__name; ふりがな dd')
        elif sid.startswith('tokyu-web-'):
            name = re.search(r'L\d+: ([^\n]+)\nL\d+: \nL\d+: 英語表記', document)
            reading = re.search(r'L\d+: ふりがな\nL\d+: +([^\n]+)', document)
            if name and reading:
                add('東急電鉄', sid.removeprefix('tokyu-web-'), name.group(1), reading.group(1), 'retained official web text; ふりがな')

    shikoku_candidates = defaultdict(list)
    shikoku_path = app / 'data/station-english-verified-jp-shikoku.json'
    if shikoku_path.exists():
        shikoku_manifest = read_mapping(root / 'jp-shikoku/raw/manifest.json')
        meta = next(m for m in shikoku_manifest if m['file'] == 'timetable-ja.html')
        path = root / 'jp-shikoku/raw' / meta['file']
        document, digest = tracked_source(path, meta['sha256'])
        native_rows = defaultdict(set)
        for href, name, reading in re.findall(r'<a[^>]*href="([^\"]+)"[^>]*>([^<（]+)（([ぁ-んー]+)）</a>', document):
            native_rows[native_identity(plain(name))].add((href, plain(name), reading))
        for name, matches in native_rows.items():
            # A native-only match is allowed solely within this full operator
            # directory when it identifies exactly one publisher station href.
            if len(matches) == 1:
                href, published_name, reading = next(iter(matches))
                append('四国旅客鉄道', href, published_name, reading, path, digest, meta['source'], 'station href=' + href + '; explicit native（kana）')
                shikoku_candidates[name] = candidates[('四国旅客鉄道', href)]

    output, unresolved = {}, []
    for cohort in ('jp', 'jp-private', 'jp-west', 'jp-east', 'jp-shikoku'):
        evidence_path = app / ('data/station-english-verified-' + cohort + '.json')
        if not evidence_path.exists():
            continue
        verified = read_mapping(evidence_path)
        for key, row in verified['byLineStation'].items():
            selected = []
            for proof in row['identityEvidence']:
                station_id = str(proof.get('officialStationId') or proof.get('stationId', ''))
                source_name = proof.get('ja') or proof.get('name') or proof.get('officialQualifiedName')
                if cohort == 'jp-shikoku':
                    selected.extend(shikoku_candidates.get(native_identity(source_name), []))
                if cohort == 'jp-east' and proof.get('japaneseRawSource'):
                    path = app / proof['japaneseRawSource']
                    document, digest = tracked_source(path, proof['japaneseSha256'])
                    pattern = r'<a[^>]*href="/timetable/list' + re.escape(station_id) + r'\.html"[^>]*>(.*?)</a>'
                    nameplate = re.search(r'<div class="estation-nameplate">\s*<h1>([^<]+)<span>([^<]+)</span></h1>', document)
                    if nameplate and ('StationCd=' + station_id) in document and native_identity(nameplate.group(1)) == native_identity(source_name):
                        append(row['operator'], station_id, nameplate.group(1), nameplate.group(2), path, digest,
                               proof['japaneseSource'], 'estation-nameplate h1 > span; StationCd=' + station_id)
                    for label in re.findall(pattern, document, re.S):
                        match = re.fullmatch(r'(.*)[（(]([ぁ-んァ-ヶー・]+)[)）]', plain(label))
                        if match and native_identity(match.group(1)) == native_identity(source_name):
                            append(row['operator'], station_id, match.group(1), match.group(2), path, digest,
                                   proof['japaneseSource'], '/timetable/list' + station_id + '.html; explicit native(kana)')
                if cohort == 'jp-west' and proof.get('rawFile'):
                    path = root / 'jp-west' / proof['rawFile']
                    document, digest = tracked_source(path, proof['sha256'])
                    name = field(document, 'ekiSignBox__name')
                    reading = field(document, 'ekiSignBox__furigana')
                    ids = set(re.findall(r'/top\?id=(\d+)', document))
                    qualified = proof.get('officialQualifiedName', '').removesuffix('（' + reading + '）')
                    if station_id in ids and native_identity(name) in {native_identity(source_name), native_identity(qualified)}:
                        append(row['operator'], station_id, source_name, reading, path, digest,
                               proof['source'], 'ekiSignBox__name/ekiSignBox__furigana; /top?id=' + station_id)
                        if candidates[(row['operator'], station_id)]:
                            candidates[(row['operator'], station_id)][-1]['publishedNativeName'] = name
                for candidate in candidates[(row['operator'], station_id)]:
                    if not source_name or native_identity(candidate['name']) != native_identity(source_name):
                        continue
                    if candidate['officialLineIds'] and not set(candidate['officialLineIds']).intersection(proof.get('officialLineIds', [])):
                        continue
                    selected.append(candidate)
            values = {(r['kana'], r['katakana']) for r in selected}
            if len(values) == 1:
                hira, kata = next(iter(values))
                unique = {json.dumps(r, ensure_ascii=False, sort_keys=True): r for r in selected}
                output[key] = {k: row[k] for k in ('country', 'lineId', 'stationCode', 'operator', 'name')}
                output[key].update(kana=hira, katakana=kata, identityEvidence=list(unique.values()),
                                   identityMapping=evidence_path.relative_to(app).as_posix())
            else:
                unresolved.append({'key': key, 'name': row['name'], 'reason': 'conflicting-published-readings' if values else 'no-explicit-retained-reading',
                                   'readings': sorted(values)})
    counts = Counter(r['operator'] for r in output.values())
    sources = {(p['rawSource'], p['sha256'], p['source']) for r in output.values() for p in r['identityEvidence']}
    return {'schema': 'station-kana-evidence/1', 'byLineStation': dict(sorted(output.items())),
            'coverage': {'verifiedMemberships': len(output), 'verifiedStationGroups': len({r['stationCode'] for r in output.values()}),
                         'byOperator': dict(sorted(counts.items())), 'unresolvedMemberships': len(unresolved)},
            'unresolved': unresolved, 'inputSha256': dict(sorted(input_hashes.items())),
            'sources': [{'rawSource': path, 'sha256': digest, 'source': url} for path, digest, url in sorted(sources)], 'method': 'Explicit retained operator kana fields joined by existing verified operator/station ID/native identity and publisher line IDs where supplied. Conflicting readings are withheld. Kana script conversion only; no reading inferred from kanji or romanization.'}
