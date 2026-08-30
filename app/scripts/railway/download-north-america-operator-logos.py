#!/usr/bin/env python3
"""Resolve operator marks through Wikidata and download their Commons artwork.

    python3 scripts/railway/download-north-america-operator-logos.py \
        --registry scripts/railway/na-feeds.json \
        --output-dir public/rail/operator-logos/na \
        --manifest public/rail/operator-logos/na/manifest.json

Only a Wikidata item whose label/alias substantially matches the registry name,
whose description says it has something to do with transport, and whose P154
property explicitly says "logo image" is accepted. Page photos, route maps and
favicons are never substituted. Every accepted association is written to a
manifest with the Q-id, the Commons file, the source URL and the file's licence
and attribution, while unresolved operators remain unbranded and therefore fail
the package audit.

## The three things that go wrong, and what each rule here is for

**The name a feed publishes is not the name Wikidata knows.** A GTFS
``agency_name`` is a legal name, an initialism, or a legal name with the
initialism bolted on in brackets. Searching the string as published answered
"Massachusetts Bay Transportation Authority (MBTA)" with a state open-data
portal and left 32 MBTA lines unbranded. So each name is searched in three
forms — as published, with the brackets removed, and as whatever was inside
them — and the best-scoring candidate is not the only one tried: candidates are
walked in score order until one actually has a logo. Before that, the single
best match was allowed to be an operator with no P154 at all, and the feed
failed rather than falling through to the operator that had one.

**A name can match something that is not a railway.** ``CATS`` is Charlotte's
transit system and also the Andrew Lloyd Webber musical, whose logo shipped on
two light-rail lines; ``exo`` is Montreal's commuter operator and also a South
Korean boy band, whose logo shipped on five. String similarity cannot separate
those, so a candidate must also *say* it is something to do with transport.

**An operator's P154 is not always its current mark.** Wikidata records the
marks a company has used, and taking the first one shipped WeGo Public
Transit's pre-2018 Nashville MTA mark and Pittsburgh Regional Transit's
pre-2022 Port Authority mark — the predecessor-mark category the Japanese
audit in ``public/rail/operator-logos/README.md`` explicitly rejects. Claims
that are ranked deprecated, or that carry an end date, are therefore skipped,
and a claim the editors ranked preferred wins.

## When a person has to answer instead

Roughly a quarter of the continent's operators cannot be resolved by any of
that: the operator publishes no mark at all, or the only Wikidata item that
carries one is a service brand rather than the company, or the name collides
with four other agencies called some form of Metro. Those answers live in
``na-operator-brands.json`` beside this script — one row per feed, naming the
operator the mark must belong to and why the automatic answer was not usable —
so that they can be re-read and re-checked as a table without reading Python.
Feeds listed there as unbranded stay unbranded on purpose, with the reason
recorded in the manifest instead of a mark.
"""
from __future__ import annotations

import argparse
import html
import json
import os
import re
import time
import urllib.parse
import urllib.request

API = 'https://www.wikidata.org/w/api.php'
COMMONS = 'https://commons.wikimedia.org/w/api.php'
COMMONS_PAGE = 'https://commons.wikimedia.org/wiki/File:'
USER_AGENT = 'JTM-RailMap-BrandAudit/1.0 (https://github.com/Sager1145/JTM-iOS-App)'
BRANDS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      'na-operator-brands.json')
STOP = {'the', 'of', 'and', 'inc', 'llc', 'corporation', 'authority', 'system',
        'regional', 'metropolitan', 'municipal', 'county', 'city', 'transit',
        'transportation', 'commission', 'district', 'area', 'rail', 'railway'}

#: What a candidate has to be about before its logo is allowed onto a railway.
#: Matched against the item's English description and label, which is where
#: Wikidata says what a thing is. The list is written from the descriptions the
#: continent's operators actually carry — "transport company", "trolley
#: operator in Dallas, Texas", "automated people mover in downtown Detroit" —
#: rather than from a taxonomy, because P31 for these items ranges over
#: companies, government agencies, interstate compacts and rail systems.
TRANSPORT_TERMS = (
    'transit', 'transport', 'rail', 'metro', 'tram', 'streetcar', 'trolley',
    'subway', 'bus', 'train', 'people mover', 'monorail', 'funicular',
    'incline', 'ferry', 'commuter', 'airport', 'airline', 'shuttle',
)

#: Wikidata qualifier for "end time". A logo statement carrying one is a mark
#: the operator has stopped using, whatever order the claims come back in.
END_TIME = 'P582'


def request_json(base, params):
    url = base + '?' + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(req, timeout=25) as response:
        return json.load(response)


def plain_text(value):
    """Commons' extmetadata is HTML fragments; the manifest wants a sentence."""
    text = re.sub(r'<[^>]+>', ' ', value or '')
    return re.sub(r'\s+', ' ', html.unescape(text)).strip()


def words(value):
    return set(re.findall(r'[a-z0-9]+', (value or '').lower())) - STOP


def acronym(value):
    return ''.join(w[0] for w in re.findall(r'[a-z]+', (value or '').lower())
                   if w not in STOP)


def score(query, candidate):
    q = words(query)
    labels = [candidate.get('label') or ''] + list(candidate.get('aliases') or [])
    best = 0.0
    for label in labels:
        c = words(label)
        if q and c:
            best = max(best, len(q & c) / min(len(q), len(c)))
        compact = re.sub('[^a-z]', '', label.lower())
        if compact and compact in {acronym(query), re.sub('[^a-z]', '', query.lower())}:
            best = 1.0
    description = (candidate.get('description') or '').lower()
    if any(term in description for term in ('rail', 'transit', 'transport', 'metro')):
        best += 0.12
    return best


def about_transport(candidate):
    """Wikidata's own answer to "is this a railway company at all"."""
    text = f"{candidate.get('label') or ''} {candidate.get('description') or ''}"
    return any(term in text.lower() for term in TRANSPORT_TERMS)


def search_names(entry):
    """Every name this operator is published under, brand names included.

    The registry's ``name`` is always used, because it is the entry's own claim
    about whose feed this is. The agency names are used only when the feed
    names exactly one of them — the same condition under which the builder
    allows a feed-wide mark onto a line. A feed carrying several agencies gets
    its mark from its own name or not at all, so that a consolidated feed's
    second operator can never lend its logo to the first.
    """
    agencies = [name for name in (entry.get('agencies') or []) if name]
    sources = [entry.get('name')] + (agencies if len(agencies) == 1 else [])
    names = []
    for raw in sources:
        if not raw:
            continue
        for form in [raw,
                     re.sub(r'\([^)]*\)', ' ', raw),
                     *re.findall(r'\(([^)]*)\)', raw)]:
            form = re.sub(r'\s+', ' ', form).strip(' -')
            if form and form not in names:
                names.append(form)
    return names


def find_items(names):
    """Every plausible operator for these names, best match first."""
    candidates = {}
    for name in names:
        payload = request_json(API, {
            'action': 'wbsearchentities', 'search': name, 'language': 'en',
            'uselang': 'en', 'type': 'item', 'limit': 8, 'format': 'json',
        })
        for item in payload.get('search') or []:
            item['_score'] = max(item.get('_score', 0),
                                 candidates.get(item['id'], {}).get('_score', 0),
                                 score(name, item))
            candidates[item['id']] = item
    ranked = [item for item in candidates.values()
              if item['_score'] >= 0.72 and about_transport(item)]
    return sorted(ranked, key=lambda row: row['_score'], reverse=True)


def current_logo(qid):
    """The mark the operator uses now, not every mark it has ever used."""
    payload = request_json(API, {
        'action': 'wbgetentities', 'ids': qid, 'props': 'claims', 'format': 'json',
    })
    claims = payload.get('entities', {}).get(qid, {}).get('claims', {}).get('P154') or []
    usable = []
    for claim in claims:
        value = (((claim.get('mainsnak') or {}).get('datavalue') or {}).get('value'))
        if not value or claim.get('rank') == 'deprecated':
            continue
        if END_TIME in (claim.get('qualifiers') or {}):
            continue
        usable.append((claim.get('rank') == 'preferred', value))
    for preferred in (True, False):
        for is_preferred, value in usable:
            if is_preferred == preferred:
                return value
    return None


def image_info(filename):
    """The 512-pixel rendering of a Commons file, and who to credit for it."""
    payload = request_json(COMMONS, {
        'action': 'query', 'titles': f'File:{filename}', 'prop': 'imageinfo',
        'iiprop': 'url|mime|extmetadata', 'iiurlwidth': 512, 'format': 'json',
    })
    pages = (payload.get('query') or {}).get('pages') or {}
    info = next(iter(pages.values())).get('imageinfo') or []
    if not info:
        return None
    row = info[0]
    meta = row.get('extmetadata') or {}

    def field(key):
        return plain_text((meta.get(key) or {}).get('value'))

    return {
        'commonsFile': filename,
        'commonsPage': COMMONS_PAGE + urllib.parse.quote(filename.replace(' ', '_')),
        'license': field('LicenseShortName') or field('UsageTerms') or 'unstated',
        'licenseUrl': field('LicenseUrl') or None,
        'attribution': field('Artist') or None,
        'credit': field('Credit') or None,
        # Commons records "trademarked" separately from the copyright licence,
        # and for a company mark it is the term that actually governs reuse.
        'restrictions': field('Restrictions') or None,
        'source': row.get('thumburl') or row.get('url'),
    }


def fetch_asset(url, base):
    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(req, timeout=90) as response:
        body = response.read()
    if body.startswith(b'\x89PNG\r\n\x1a\n'):
        ext = '.png'
    elif body.startswith(b'\xff\xd8\xff'):
        ext = '.jpg'
    elif body.startswith((b'GIF87a', b'GIF89a')):
        ext = '.gif'
    elif b'<svg' in body[:1000].lower():
        ext = '.svg'
    else:
        raise ValueError('Commons response is not a supported image')
    path = base + ext
    with open(path + '.part', 'wb') as fh:
        fh.write(body)
    os.replace(path + '.part', path)
    return path


def resolve(entry, pin):
    """The item and file this feed's mark comes from, and how it was decided.

    A pinned Q-id skips the search entirely; a pinned Commons file skips
    Wikidata entirely, because the operator has no item that carries its mark.
    Everything else walks the ranked candidates and takes the first that has a
    current logo — a candidate that scores well but publishes nothing is not a
    reason to leave the feed unbranded.
    """
    if pin and pin.get('commonsFile'):
        return None, pin['commonsFile'], 'brand-table'
    if pin and pin.get('qid'):
        return ({'id': pin['qid'], 'label': pin.get('operator'), '_score': 1.0},
                current_logo(pin['qid']), 'brand-table')
    for item in find_items(search_names(entry)):
        filename = current_logo(item['id'])
        if filename:
            return item, filename, 'wikidata-search'
    return None, None, 'wikidata-search'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--registry', required=True)
    ap.add_argument('--output-dir', required=True)
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--brands', default=BRANDS,
                    help='the audited per-operator answers; see its own note')
    ap.add_argument('--refresh', action='store_true',
                    help='re-resolve every feed instead of keeping cached assets')
    ap.add_argument('--only', action='append',
                    help='limit the pass to these slugs (repeatable)')
    options = ap.parse_args()
    with open(options.registry, encoding='utf-8') as fh:
        registry = json.load(fh)
    with open(options.brands, encoding='utf-8') as fh:
        brands = json.load(fh)
    pins = brands.get('brands') or {}
    unbranded = brands.get('unbranded') or {}
    os.makedirs(options.output_dir, exist_ok=True)
    # public/rail/operator-logos/na -> public, which is what the registry's
    # leading-slash asset paths are relative to.
    public_root = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(options.output_dir))))
    try:
        with open(options.manifest, encoding='utf-8') as fh:
            manifest = json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError):
        manifest = {}

    def checkpoint():
        with open(options.registry + '.tmp', 'w', encoding='utf-8') as fh:
            json.dump(registry, fh, ensure_ascii=False, indent=1)
            fh.write('\n')
        os.replace(options.registry + '.tmp', options.registry)
        with open(options.manifest + '.tmp', 'w', encoding='utf-8') as fh:
            json.dump(manifest, fh, ensure_ascii=False, indent=1)
            fh.write('\n')
        os.replace(options.manifest + '.tmp', options.manifest)

    def cached(prior, pin):
        """Whether the recorded answer still stands without asking again.

        A row written before this script recorded licences is not cached, so
        that the whole set is re-resolved once and every shipped file ends up
        with its attribution beside it. A row that disagrees with a pin the
        table has since gained is not cached either — that is how a corrected
        answer reaches the asset.
        """
        if options.refresh or not prior.get('asset') or 'license' not in prior:
            return False
        if pin and pin.get('qid') and prior.get('qid') != pin['qid']:
            return False
        if pin and pin.get('commonsFile') \
                and prior.get('commonsFile') != pin['commonsFile']:
            return False
        return os.path.isfile(os.path.join(public_root, prior['asset'].lstrip('/')))

    feeds = [e for e in registry['feeds']
             if not options.only or e['slug'] in options.only]
    for index, entry in enumerate(feeds, 1):
        slug = entry['slug']
        prefix = f'{index}/{len(feeds)} {slug}:'
        if entry.get('logoRestricted'):
            entry.pop('operatorLogo', None)
            manifest[slug] = {
                'error': 'operator terms reserve logo use; no distributable asset'
            }
            checkpoint()
            print(f'{prefix} RESTRICTED', flush=True)
            continue
        if slug in unbranded:
            entry.pop('operatorLogo', None)
            manifest[slug] = {
                'operator': unbranded[slug].get('operator'),
                'error': 'no operator mark in the checked sources',
                'why': unbranded[slug].get('why'),
            }
            checkpoint()
            print(f'{prefix} UNBRANDED (recorded)', flush=True)
            continue
        pin = pins.get(slug)
        prior = manifest.get(slug) or {}
        if cached(prior, pin):
            entry['operatorLogo'] = prior['asset']
            print(f'{prefix} cached', flush=True)
            continue
        try:
            item, filename, decided_by = resolve(entry, pin)
            info = filename and image_info(filename)
            if not (filename and info and info['source']):
                raise LookupError('no sufficiently matched Wikidata P154 logo')
            base = os.path.join(options.output_dir, slug)
            path = fetch_asset(info['source'], base)
            rel = '/rail/operator-logos/na/' + os.path.basename(path)
            entry['operatorLogo'] = rel
            row = {'operator': (pin or {}).get('operator')
                   or (item or {}).get('label'), 'decidedBy': decided_by}
            if item:
                row['qid'] = item['id']
                row['matchedLabel'] = item.get('label')
                row['matchScore'] = round(item['_score'], 2)
            row.update({k: v for k, v in info.items() if v})
            row['asset'] = rel
            manifest[slug] = row
            state = f"{item['id'] if item else filename} ({decided_by})"
        except Exception as exc:  # unresolved is deliberately visible
            entry.pop('operatorLogo', None)
            manifest[slug] = {'error': f'{type(exc).__name__}: {exc}'}
            state = 'UNRESOLVED'
        checkpoint()
        print(f'{prefix} {state}', flush=True)
        time.sleep(0.1)
    checkpoint()


if __name__ == '__main__':
    main()
