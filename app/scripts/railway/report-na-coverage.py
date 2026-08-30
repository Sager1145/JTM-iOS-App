#!/usr/bin/env python3
"""Say which passenger railways the packages do NOT contain.

    python3 scripts/railway/report-na-coverage.py \
        --inventory /private/tmp/na-rail/osm-inventory.json \
        --package public/rail/us-2025.json --package public/rail/ca-2025.json \
        --out /private/tmp/na-rail/coverage.json

"Every passenger railway" is a claim, and the honest way to make it is to name
an independent inventory and say what is in it that is not in the packages.
The inventory here is OpenStreetMap's: every route relation in North America
tagged `route=train|subway|light_rail|tram|monorail|funicular`, which is the
only list of the continent's passenger railways that is not itself derived
from the same GTFS feeds the packages are built from.

The comparison is on the OPERATOR, not on the line, because line names are not
comparable across the two — OSM calls it "Muni Metro N Judah" and the SFMTA's
feed calls it "N". An operator that appears in the inventory and in no package
is a system this build does not have, and the report names it so that its
absence is a known quantity rather than a discovery.

The output is advisory and its matching is fuzzy by construction: it is a list
of things to look at, not a gate. What it must never do is claim coverage that
is not there, so a name it cannot match counts as MISSING.

That last sentence is the whole design, and everything below leans one way
because of it. A name this cannot match is cheap — somebody reads a row, opens
the package, and sees the system is there. A name this matches WRONGLY is
expensive, because the gap it hides is never looked at again. So the rules
here are the strict ones, and where a strict rule reports a system that is in
fact present, the fix is an entry in `OPERATOR_ALIASES` recording the evidence
someone checked — never a looser rule that would let a hundred unchecked pairs
through with it. Every row therefore carries a `via` saying HOW it matched, so
the covered list can be audited as easily as the missing one.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))

import na_attractions                # noqa: E402

#: Mexico is in the bounding box the inventory was taken over and is not in
#: either package on purpose.
OUT_OF_SCOPE = (
    'ferromex', 'ferrocarriles de cuba', 'felcuba', 'ffcc', 'opret',
    'metrorrey', 'sistema de transporte colectivo', 'siteur',
    'servicio de transportes eléctricos de la ciudad de méxico',
    'ferrocarriles suburbanos', 'fonadin', 'ferroistmo', 'olmeca-maya-mexica',
    'sintra', 'conmuter',
)

# OSM often records the contracted operator while the public timetable names
# the transport authority. These are evidence aliases, not fuzzy guesses: each
# one is here because somebody opened the packages and saw that operator's
# lines in them. The matcher below is deliberately strict, and this table —
# not a looser rule — is where a verified "yes, it really is in there" goes.
OPERATOR_ALIASES = {
    'keolis commuter services': 'Massachusetts Bay Transportation Authority',
    'keolis': 'Virginia Railway Express',
    'southern california regional rail authority': 'Metrolink Trains',
    'alstom': 'GO Transit',
    'transitamerica services': 'Caltrain',
    'transitamerica': 'North County Transit District',
    'arr': 'Alaska Railroad Corporation',
    'southeastern pennsylvania transportation authority': 'SEPTA',
    'lossan rail corridor agency': 'Amtrak',
    'denver transit partners': 'Regional Transportation District',
    'regional transportation district': 'Regional Transportation District',
    'rtd': 'Regional Transportation District',
    'rta': 'New Orleans Regional Transit Authority',
    'gcrta': 'Greater Cleveland Regional Transit Authority',
    'british columbia rapid transit company': 'TransLink',
    'intransitbc': 'TransLink',
    'pulsar': 'Réseau express métropolitain',
    'transed partners': 'Edmonton Transit Service',
    'bombardier technology': 'Florida Department of Transportation',
    'm-1 rail': 'Qline Detroit',
    'mata': 'Memphis Area Transit Authority',
    'ati': 'Autoridad de Transporte Integrado',
    'jta': 'Jacksonville Transportation Authority',
    'cotpa': 'EMBARK',
    'city and county of honolulu': 'DTS',
    'regional transportation authority of middle tennessee': 'WeGo Public Transit',
    'staten island rapid transit operating authority': 'MTA New York City Transit',
    'société de transport de montréal': 'Société de transport de Montréal',
    'pittsburgh regional transit': 'Pittsburgh Regional Transit',
    'prt': 'Pittsburgh Regional Transit',
    'n i c t d': 'Northern Indiana Commuter Transportation District',

    # Agencies whose OSM name and package name share nothing a matcher may
    # safely act on. Each was confirmed by finding the system's lines in the
    # package under the name on the right.
    'nj transit': 'NJ Transit Rail',
    'new jersey transit': 'NJ Transit Rail',
    'new jersey transit light rail operations': 'NJ Transit Rail',
    'san diego metropolitan transit system': 'MTS',
    'san joaquin regional rail commission': 'Altamont Corridor Express',
    'santa clara valley transportation authority': 'VTA',
    'union pearson express': 'UP Express',
    'kansas city streetcar authority': 'Kansas City Area Transportation Authority',
    'delaware river port authority': 'Port Authority Transit Corporation',
    'south florida regional transportation authority': 'Tri-Rail',
    'capital metropolitan transportation authority': 'Capital Metro',
    'new york city transit authority': 'MTA New York City Transit',
    # Amtrak California is Amtrak's name for the state-funded corridors and
    # the package files their lines under Amtrak.
    'amtrak california': 'Amtrak',
    # The Seattle Streetcar is King County Metro's to run and the City of
    # Seattle's to own; the package files it under the owner.
    'king county metro': 'City of Seattle',
}

# Operators deliberately NOT aliased, so that their row keeps pointing at the
# part of them the packages do not have:
#   Port Authority of New York and New Jersey — PATH is in the package, its
#     AirTrain JFK and AirTrain Newark are not.
#   Transdev — it runs the Cincinnati Bell Connector, which is in the package
#     under METRO, and Milwaukee's Hop, of which only one of three lines is.
#   Port Authority of Allegheny County — Pittsburgh's light rail is in the
#     package; the Monongahela and Duquesne Inclines are not.
# An alias on any of these would trade a real gap for a quieter report.

AMBIGUOUS_ACRONYMS = {'mata', 'rta', 'prt', 'mts', 'dart', 'ati', 'jta',
                      'tpa', 'f'}


def normalise(name):
    # A parenthesis holds a gloss on the name, not part of it — the feeds
    # write "Hampton Roads Transit (HRT)" and "McKinney Avenue Transit
    # Authority (M-Line)" where OpenStreetMap writes the name alone, and the
    # gloss is otherwise counted as two more words the names disagree about.
    text = re.sub(r'\([^)]*\)', ' ', name or '').lower()
    text = re.sub(r'\b(the|inc|llc|ltd|corporation|corp|company|co|authority|'
                  r'commission|district|agency|department|of|and|&|system|'
                  r'systems|transit|transportation|regional|metropolitan|'
                  r'municipal|county|city)\b', ' ', text)
    text = re.sub(r'[^a-z0-9]+', ' ', text)
    return ' '.join(text.split())


def tokens(name):
    return set(normalise(name).split())


def initials(name):
    """The acronym a full agency name would be abbreviated to."""
    words = [w for w in re.split(r'[^A-Za-z]+', name or '') if w]
    return ''.join(w[0] for w in words).lower()


def similar(a, b):
    """How much two operator names look like the same operator, and why.

    Returns (score, why). The score is banded rather than continuous so that
    the *reason* a match was made survives into the report: an identical name
    beats an acronym, which beats shared words, and a caller taking the best
    candidate therefore prefers the strongest evidence rather than whichever
    string happened to sort first.

    The acronym test is here because half the continent's agencies appear
    under their initials in one source and in full in the other. OpenStreetMap
    says "MARTA" and the feed says "Metropolitan Atlanta Rapid Transit
    Authority"; they share no token at all, and without this the report would
    name as missing a system the package plainly contains. It only fires when
    the initials come out exactly, which is why SEPTA — whose name yields
    "spta" — needs an alias instead: a near-acronym is a guess, and a guess
    that says "covered" is the one thing this may not do.

    The word test asks what fraction of EVERYTHING the two names say they say
    together, not what fraction of the shorter one the longer one repeats.
    That distinction is the whole of it. Scored the second way, "Orlando
    International Airport" is two thirds of "Tampa International Airport" and
    Orlando's four people movers were reported as covered by Tampa's; so were
    Strasburg Rail Road by the Long Island Rail Road, the Seashore Trolley
    Museum in Maine by the Electric City Trolley Museum in Pennsylvania, and
    the Trolley Museum of New York by the New York City subway. Every one of
    those pairs agrees only on words that say what a railway is, or on the
    name of a place two unrelated railways both sit in, and every one of them
    falls below the threshold once the words only one name uses are counted
    too. What survives is the case this test exists for: a name that is the
    whole of the other plus a qualifier, "Roaring Camp" against "Roaring Camp
    Railroads", or "VIA Rail" against "Via Rail Canada".
    """
    na, nb = normalise(a), normalise(b)
    if na and na == nb:
        return 1.0, 'identical'

    for short, long_name in ((a, b), (b, a)):
        letters = re.sub(r'[^A-Za-z]', '', short or '')
        if (2 <= len(letters) <= 6
                and letters.lower() not in AMBIGUOUS_ACRONYMS
                and letters.lower() == initials(long_name)):
            return 0.95, f'acronym {letters.lower()}'

    ta, tb = tokens(a), tokens(b)
    shared = ta & tb
    if not shared:
        return 0.0, ''
    return (min(len(shared) / float(len(ta | tb)), 0.9),
            'words ' + '+'.join(sorted(shared)))


def best_match(operator, have, slugs, threshold):
    """The package operator most likely to be this OSM operator, and why."""
    # `have` is a set; sorting it keeps the report byte-identical run to run,
    # because two package operators can score the same and whichever is
    # visited first wins.
    best = (0.0, None, '')
    for mine in sorted(have):
        score, why = similar(operator, mine)
        if score > best[0]:
            best = (score, mine, why)

    alias = OPERATOR_ALIASES.get(operator.lower())
    if alias:
        if alias in have:
            best = (1.0, alias, 'alias')
        else:
            for mine in sorted(have):
                score, _ = similar(alias, mine)
                if score > best[0]:
                    best = (score, mine, f'alias {alias}')

    if best[0] >= threshold:
        return best

    # The feed slug the line id begins with. It is the operator's own short
    # name far more often than the `operator` field is — a package line says
    # "Southeastern Pennsylvania Transportation Authority" and its id says
    # `septa`, which is what OpenStreetMap calls it.
    #
    # Only the WHOLE name and its acronym are tested against a slug. An
    # earlier version also matched a slug against any single word of the
    # operator name, and because a line id is split at its first hyphen the
    # slug set is full of bare first words — `new`, `san`, `valley`, `fort`,
    # `rio`, `capitol` — so the New Hope Railroad matched `new`, the Fort
    # Collins Municipal Railway matched `fort`, and the Capitol Subway System
    # under the US Capitol matched the Capitol Corridor in California. Every
    # one of those was a real gap reported as covered.
    # Each candidate is guarded by its own ambiguity: `mts` as a whole name is
    # San Diego's or Memphis's, and `dart` as an acronym is Dallas's or Des
    # Moines's, so neither may stand on its own even when the other could.
    letters = re.sub(r'[^A-Za-z]', '', operator).lower()
    acronym = initials(operator)
    for slug in sorted(slugs):
        if letters and letters not in AMBIGUOUS_ACRONYMS and slug == letters:
            return 1.0, slug, 'slug'
        if acronym and acronym not in AMBIGUOUS_ACRONYMS and slug == acronym:
            return 0.95, slug, f'slug acronym {acronym}'
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--inventory', required=True)
    ap.add_argument('--package', action='append', required=True)
    ap.add_argument('--out', default=None)
    ap.add_argument('--threshold', type=float, default=0.6)
    options = ap.parse_args()

    with open(options.inventory) as fh:
        inventory = json.load(fh)['elements']

    wanted = defaultdict(
        lambda: {'routes': 0, 'kinds': set(), 'examples': [], 'relations': []})
    # A relation with neither `operator` nor `network` cannot be compared
    # against an operator list at all. It used to be skipped, silently, and
    # that silence was the report's worst error: it swallowed five of
    # Montréal's métro line relations, Angel's Flight, the Durango &
    # Silverton, the Grand Canyon Railway and a hundred others, none of which
    # appeared in either list. They are reported separately now — never as
    # covered, because nothing here can show that they are.
    unattributed = []
    for element in inventory:
        tags = element.get('tags') or {}
        operator = (tags.get('operator') or tags.get('network') or '').strip()
        if not operator:
            unattributed.append({'relation': element['id'],
                                 'kind': tags.get('route'),
                                 'name': tags.get('name') or ''})
            continue
        # An attraction is not a gap. The judgement is `na_attractions`' and
        # is asked of the relation's own name as well as its operator,
        # because Fort Edmonton Park's streetcar is tagged under the Edmonton
        # Radial Railway Society, whose OTHER tramway — the High Level Bridge
        # Streetcar — is a public one this report must go on reporting.
        if na_attractions.is_attraction(operator, tags.get('name')):
            continue
        if any(word in operator.lower() for word in OUT_OF_SCOPE):
            continue
        entry = wanted[operator]
        entry['routes'] += 1
        entry['kinds'].add(tags.get('route'))
        entry['relations'].append(element['id'])
        if len(entry['examples']) < 3 and tags.get('name'):
            entry['examples'].append(tags['name'])

    have = set()
    slugs = set()
    for path in options.package:
        with open(path) as fh:
            package = json.load(fh)
        for line in package['lines']:
            if line.get('operator'):
                have.add(line['operator'])
            slugs.add((line.get('id') or '').split('-', 1)[0])
    slugs.discard('')

    covered, missing = [], []
    for operator, entry in sorted(wanted.items(), key=lambda kv: -kv[1]['routes']):
        score, matched, why = best_match(operator, have, slugs, options.threshold)
        row = {'operator': operator, 'osmRoutes': entry['routes'],
               'kinds': sorted(k for k in entry['kinds'] if k),
               'relations': entry['relations'],
               'examples': entry['examples'],
               'matched': matched if score >= options.threshold else None,
               'via': why if score >= options.threshold else None,
               'score': round(score, 2)}
        (covered if row['matched'] else missing).append(row)

    summary = {
        'inventory': {'relations': len(inventory), 'operators': len(wanted),
                      'unattributedRelations': len(unattributed)},
        'packages': {'operators': len(have)},
        'covered': len(covered),
        'missing': len(missing),
        'missingOperators': missing,
        'coveredOperators': covered,
        'unattributed': unattributed,
    }
    if options.out:
        with open(options.out, 'w') as fh:
            json.dump(summary, fh, ensure_ascii=False, indent=1)
    sys.stderr.write(f"{len(covered)} of {len(wanted)} operators covered; "
                     f"{len(missing)} not; {len(unattributed)} relations name "
                     f"no operator at all\n")
    for row in missing[:60]:
        sys.stderr.write(f"  {row['osmRoutes']:3} {','.join(row['kinds'])[:22]:22} "
                         f"{row['operator'][:52]}\n")


if __name__ == '__main__':
    main()
