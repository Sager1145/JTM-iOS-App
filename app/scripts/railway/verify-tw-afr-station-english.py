#!/usr/bin/env python3
"""Validate AFR's reviewed bilingual excerpts and retain original HTML evidence.

No station label is rewritten: a changed official heading or identity rejects
the update. Website page IDs remain distinct from AFR dataset station codes.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import copy
from datetime import datetime, timezone
import gzip
import hashlib
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import urlparse, urljoin

APP = Path(__file__).resolve().parents[2]
SNAPSHOT = APP / 'data/tw-station-english-afr-source.json'
SOURCES = APP / 'data/station-english-sources/tw-afr-stations'
BASELINE = SOURCES / 'reviewed-excerpts.json'
MANIFEST = SOURCES / 'manifest.json'
OPERATOR = '阿里山林業鐵路及文化資產管理處'
HOST = 'afrch.forest.gov.tw'


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def plain(value):
    return html.unescape(re.sub(r'<[^>]*>', '', value)).strip()


class PageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title, self.page_headings, self.forms, self.relations, self.links = [], [], [], [], []
        self.in_title = False
        self.current_heading = None
        self.current_link = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'title':
            self.in_title = True
        if tag == 'span' and attrs.get('aria-current') == 'page':
            self.current_heading = []
        if tag == 'form' and attrs.get('id') == 'aspnetForm':
            self.forms.append(attrs.get('action', ''))
        if tag == 'meta' and attrs.get('name', '').upper() == 'DC.RELATION':
            self.relations.append(attrs.get('content', ''))
        if tag == 'a' and attrs.get('href'):
            self.current_link = {'href': attrs['href'], 'text': []}

    def handle_data(self, data):
        if self.in_title:
            self.title.append(data)
        if self.current_heading is not None:
            self.current_heading.append(data)
        if self.current_link is not None:
            self.current_link['text'].append(data)

    def handle_endtag(self, tag):
        if tag == 'title':
            self.in_title = False
        if tag == 'span' and self.current_heading is not None:
            self.page_headings.append(''.join(self.current_heading).strip())
            self.current_heading = None
        if tag == 'a' and self.current_link is not None:
            self.links.append({'href': self.current_link['href'],
                               'text': ''.join(self.current_link['text']).strip()})
            self.current_link = None


def page(document):
    parser = PageParser()
    parser.feed(document)
    return parser


def page_id(url):
    parsed = urlparse(url)
    if parsed.scheme != 'https' or parsed.hostname != HOST:
        raise ValueError(f'non-official AFR URL: {url}')
    match = re.search(r'/(\d{7})/?$', parsed.path)
    return match[1] if match else None


def station_heading(document, station_id, expected):
    parsed = page(document)
    form_ids = {page_id('https://' + HOST + action) for action in parsed.forms}
    if form_ids != {station_id}:
        raise ValueError(f'official page ID mismatch for {station_id}: {sorted(str(v) for v in form_ids)}')
    headings = set(parsed.page_headings)
    if headings != {expected}:
        raise ValueError(f'official heading changed for {station_id}: expected {expected!r}, got {sorted(headings)!r}')
    if expected not in ''.join(parsed.title):
        raise ValueError(f'official title does not corroborate station heading: {station_id}')
    if not parsed.relations:
        raise ValueError(f'official CMS identity absent: {station_id}')
    return {'heading': expected, 'pageId': station_id, 'cmsRelations': sorted(set(parsed.relations))}


def homepage_identity(document, station_id, expected):
    parsed = page(document)
    matches = []
    for link in parsed.links:
        resolved = urljoin('https://' + HOST + '/', link['href'])
        target = urlparse(resolved)
        if target.scheme != 'https' or target.hostname != HOST:
            continue
        if page_id(resolved) == station_id and link['text'] == expected:
            matches.append(link)
    if not matches:
        raise ValueError(f'homepage does not link exact native station {expected!r} to {station_id}')
    return {'heading': expected, 'pageId': station_id, 'linkedHref': matches[0]['href'],
            'matchMethod': 'official-homepage-exact-native-anchor-and-station-page-id'}


def source_urls(excerpts):
    return sorted({row[field] for row in excerpts['byCode'].values()
                   for field in ('source', 'identitySource', 'identityAliasSource') if row.get(field)})


def refresh(workers=6, output_dir=SOURCES):
    output_dir.mkdir(parents=True, exist_ok=True)
    if not BASELINE.exists():
        original = read(SNAPSHOT)
        if any('rawSourceVerification' in row for row in original['byCode'].values()):
            raise ValueError('baseline missing but snapshot already enriched; recover original reviewed excerpts')
        write(BASELINE, original)
    excerpts = read(BASELINE)
    now = datetime.now(timezone.utc).isoformat()
    def work(url):
        page_id(url)  # Enforce the primary operator host even for the homepage.
        name = sha(url.encode())[:16] + '.html.gz'
        result = subprocess.run(['curl', '-fL', '--silent', '--show-error', '--connect-timeout', '10',
            '--max-time', '45', '--output', str(output_dir / (name + '.part')),
            '--write-out', '%{url_effective}', url], capture_output=True, text=True)
        record = {'source': url, 'retrievedAt': now}
        part = output_dir / (name + '.part')
        if result.returncode:
            record['error'] = result.stderr.strip()[:300]
            part.unlink(missing_ok=True)
        else:
            final = result.stdout.strip()
            page_id(final)
            raw = part.read_bytes()
            part.unlink()
            page(raw.decode('utf-8'))
            (output_dir / name).write_bytes(gzip.compress(raw, mtime=0))
            record.update({'finalSource': final, 'sha256': sha(raw), 'rawSource': name})
        print(url + ': ' + ('downloaded' if 'sha256' in record else record['error']), flush=True)
        return record
    with ThreadPoolExecutor(max_workers=workers) as executor:
        records = list(executor.map(work, source_urls(excerpts)))
    write(output_dir / 'manifest.json', {'schema': 'official-page-retrieval/1',
          'publisher': excerpts['operator'], 'retrievedAt': now,
          'sources': {record['source']: record for record in records}})


def load_raw(source_dir=SOURCES):
    manifest = read(source_dir / 'manifest.json')
    documents = {}
    for url, record in manifest['sources'].items():
        if record.get('error'):
            raise ValueError(f'official AFR source unavailable: {url}: {record["error"]}')
        raw = gzip.decompress((source_dir / record['rawSource']).read_bytes())
        if sha(raw) != record['sha256']:
            raise ValueError(f'AFR raw SHA mismatch: {record["rawSource"]}')
        documents[url] = raw.decode('utf-8')
    return manifest, documents


def package_identities(app=APP):
    features = read(app / 'data/stations-tw.json')['features']
    package = read(app / 'public/rail/tw-2025.json')
    sources = {}
    for feature in features:
        properties = feature['properties']
        code = properties['n02_station_code']
        if not code.startswith('AFR-'):
            continue
        identity = (properties['n02_group_code'], properties['station_name'], properties['operator'])
        if code in sources and sources[code] != identity:
            raise ValueError(f'AFR source feature identities disagree: {code}')
        sources[code] = identity
    memberships = {}
    for line in package['lines']:
        for station in line['stations']:
            if station[0].startswith('tw-official-afr-'):
                memberships.setdefault(station[0], []).append({'lineId': line['id'],
                    'operator': line['operator'], 'name': station[1]})
    return sources, memberships


def verify_row(row, source, documents, feature_identity, memberships):
    code, group = row['stationCode'], row['stationGroupCode']
    if feature_identity != (group, row['name'], OPERATOR):
        raise ValueError(f'AFR package/source code-group-native identity mismatch: {code}')
    membership_names = {row['name']}
    if row['name'] != row['zh_Hant']:
        alias_source = row.get('identityAliasSource')
        if (row['name'] not in row.get('identityAliases', []) or not alias_source
                or row['identityAliasEvidence'] not in plain(documents[alias_source])):
            raise ValueError(f'AFR native package alias unreviewed: {code}')
        membership_names.add(row['zh_Hant'])
    if not memberships or any(member['name'] not in membership_names or member['operator'] != OPERATOR
                              for member in memberships):
        raise ValueError(f'AFR compact package membership mismatch: {code}')
    station_id = row['officialStationId']
    if page_id(row['source']) != station_id:
        raise ValueError(f'AFR English URL station ID mismatch: {code}')
    expected_english = row['en'] + ' Station'
    if row['englishEvidence'] != expected_english:
        raise ValueError(f'AFR excerpt does not preserve exact English station label: {code}')
    english = station_heading(documents[row['source']], station_id, expected_english)
    if page_id(row['identitySource']) is None:
        native = homepage_identity(documents[row['identitySource']], station_id, row['chineseEvidence'])
    else:
        if page_id(row['identitySource']) != station_id:
            raise ValueError(f'AFR Chinese URL station ID mismatch: {code}')
        native = station_heading(documents[row['identitySource']], station_id, row['chineseEvidence'])
        if native['cmsRelations'] != english['cmsRelations']:
            raise ValueError(f'AFR language page CMS identities disagree: {code}')
    native_label = row['chineseEvidence'].removesuffix('車站')
    if native_label != row['zh_Hant']:
        raise ValueError(f'AFR Chinese label changed: {code}')
    alias = None
    if row['name'] != row['zh_Hant']:
        if row['name'] not in row.get('identityAliases', []):
            raise ValueError(f'AFR native package alias unreviewed: {code}')
        alias_source = row.get('identityAliasSource')
        if not alias_source or row['identityAliasEvidence'] not in plain(documents[alias_source]):
            raise ValueError(f'AFR native alias statement absent from official source: {code}')
        alias = source['sources'][alias_source]
    en_source = source['sources'][row['source']]
    zh_source = source['sources'][row['identitySource']]
    proof = {'stationPageId': station_id, 'english': {**english, **en_source},
             'chinese': {**native, **zh_source}, 'packageMemberships': memberships}
    if alias:
        proof['nativeAlias'] = {**alias, 'publishedStatement': row['identityAliasEvidence']}
    return proof


def build(app=APP, source_dir=SOURCES):
    excerpts = read(source_dir / 'reviewed-excerpts.json')
    manifest, documents = load_raw(source_dir)
    if set(manifest['sources']) != set(source_urls(excerpts)):
        raise ValueError('AFR source URL coverage is incomplete or stale')
    features, memberships = package_identities(app)
    result = copy.deepcopy(excerpts)
    for code, row in result['byCode'].items():
        if code != row['stationCode']:
            raise ValueError(f'AFR dataset station code mismatch: {code}')
        proof = verify_row(row, manifest, documents, features.get(code),
                           memberships.get(row['stationGroupCode'], []))
        row['rawSourceVerification'] = proof
        en, zh = proof['english'], proof['chinese']
        evidence = {'operator': OPERATOR, 'publisher': result['operator'],
            'stationPageId': row['officialStationId'], 'stationDatasetCode': code,
            'stationGroupCode': row['stationGroupCode'], 'zh_Hant': row['zh_Hant'], 'en': row['en'],
            'source': row['source'], 'identitySource': row['identitySource'],
            'publishedEnglishHeading': en['heading'], 'publishedChineseHeading': zh['heading'],
            'sha256': en['sha256'], 'identitySha256': zh['sha256'],
            'retrievedAt': en['retrievedAt'], 'identityRetrievedAt': zh['retrievedAt'],
            'rawSource': 'data/station-english-sources/tw-afr-stations/' + en['rawSource'],
            'identityRawSource': 'data/station-english-sources/tw-afr-stations/' + zh['rawSource'],
            'matchMethod': row['matchMethod']}
        if proof.get('nativeAlias'):
            native_alias = proof['nativeAlias']
            evidence['nativeAliasEvidence'] = {'source': row['identityAliasSource'],
                'sha256': native_alias['sha256'], 'retrievedAt': native_alias['retrievedAt'],
                'publishedStatement': row['identityAliasEvidence'],
                'rawSource': 'data/station-english-sources/tw-afr-stations/' + native_alias['rawSource']}
        row['identityEvidence'] = [evidence]
    result['snapshotKind'] = 'reviewed bilingual station-name excerpts with verified raw HTML snapshots'
    result['rawSourceManifest'] = 'data/station-english-sources/tw-afr-stations/manifest.json'
    result['rawVerification'] = {'schema': 'station-page-integrity/1',
        'stationCodes': len(result['byCode']), 'officialPages': len(documents),
        'retrievedAt': manifest['retrievedAt'], 'labelsChanged': 0,
        'reviewedExcerptSha256': sha((source_dir / 'reviewed-excerpts.json').read_bytes()),
        'manifestSha256': sha((source_dir / 'manifest.json').read_bytes())}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--workers', type=int, default=6)
    parser.add_argument('--output', type=Path, default=SNAPSHOT)
    args = parser.parse_args()
    if args.refresh:
        raise SystemExit('scratch verifier uses retained raw sources; refresh separately')
    result = build()
    if args.check:
        if read(args.output) != result:
            raise SystemExit('tw-station-english-afr-source.json raw verification is stale')
    else:
        write(args.output, result)
    print(json.dumps(result['rawVerification'], ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
