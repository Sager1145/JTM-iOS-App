#!/usr/bin/env python3
"""One Overpass client for every downloader that needs one.

The three OpenStreetMap steps — the inventory, the per-line cross-check and
the route fetch for railways no operator publishes a feed for — each had their
own copy of ``ENDPOINT = 'https://overpass-api.de/api/interpreter'`` and their
own retry loop. That was fine until the main instance went down for most of a
build window and the cross-check came back with 7 of its 140 tiles, which is
how the package came to admit an unconfirmed 15 % that was absence rather than
disagreement.

So the endpoint is a LIST, and it is here rather than in three files.

## Why a list rather than a better single address

Overpass is a volunteer service with no availability promise, and the
instances are not interchangeable: several of the public addresses serve a
regional extract rather than the planet, and one of those answers a North
American query with a valid, empty, 200. A downloader that treated that as an
answer would write an empty tile and report success — the exact failure this
module exists to make impossible.

The planet probe is therefore not optional politeness: a mirror is not used
until it has answered a question whose answer is known and non-empty, over
track on the other side of the world from wherever the mirror is.
"""
from __future__ import annotations

import gzip
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = ('JTM-RailMap-DataBuild/1.0 '
              '(https://github.com/Sager1145/JTM-iOS-App)')

#: In preference order. The first that proves it holds the planet is used, and
#: the rest are what a failed request falls to rather than giving up on a tile.
MIRRORS = (
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    'https://overpass.osm.jp/api/interpreter',
    'https://overpass.osm.ch/api/interpreter',
)

#: Chicago's Loop. Five CTA route relations have been there for fifteen years
#: and will answer any planet instance; a regional extract of anywhere else
#: answers nothing. Kept small so the probe costs a mirror almost nothing.
PROBE = ('[out:json][timeout:40];'
         'relation(41.87,-87.65,41.90,-87.62)'
         '[route~"^(subway|light_rail|tram|train|monorail|funicular)$"];'
         'out tags 5;')

#: HTTP codes that mean "not now" rather than "not ever". Overpass answers 429
#: when a client has used its slot allowance and 504 when a query outran the
#: instance's own timeout; both come back from the same address a minute
#: later. An early version of this module retired three working mirrors by
#: probing all six inside two seconds and believing the answer.
TRANSIENT = frozenset((429, 502, 503, 504))


def _post(endpoint, query, timeout):
    request = urllib.request.Request(
        endpoint,
        data=urllib.parse.urlencode({'data': query}).encode(),
        headers={'User-Agent': USER_AGENT, 'Accept-Encoding': 'gzip'})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read()
        if response.headers.get('Content-Encoding') != 'gzip':
            body = gzip.compress(body)
    json.loads(gzip.decompress(body))                  # refuse a truncated body
    return body


class Overpass:
    """A pool of Overpass instances, ordered by which of them answers.

    Holds no connection and no session — the state is which mirrors proved
    they hold the planet, and which one answered last, so that a long run does
    not re-probe a dead address once per tile.
    """

    def __init__(self, mirrors=MIRRORS, log=sys.stderr, probe_pause=4.0):
        self._candidates = list(mirrors)
        self._live = None
        self._preferred = None
        self._log = log
        self._probe_pause = probe_pause

    def _write(self, text):
        self._log.write(text)
        self._log.flush()

    def _probe(self, endpoint):
        """Does this address hold the planet? ``False`` when it plainly does
        not, ``None`` when it will not say."""
        for attempt in range(2):
            try:
                body = _post(endpoint, PROBE, timeout=90)
            except urllib.error.HTTPError as exc:
                if exc.code in TRANSIENT and attempt == 0:
                    time.sleep(self._probe_pause * 3)
                    continue
                self._write('  overpass %s refused the probe (HTTP %s)\n'
                            % (endpoint, exc.code))
                return None
            except Exception as exc:                   # noqa: BLE001
                self._write('  overpass %s unreachable (%s)\n'
                            % (endpoint, type(exc).__name__))
                return None
            elements = json.loads(gzip.decompress(body)).get('elements', [])
            if not elements:
                # A 200 with nothing in it. Somewhere in this instance's
                # extract is not North America.
                self._write('  overpass %s is a regional extract '
                            '(probe empty) — not used\n' % endpoint)
                return False
            self._write('  overpass %s holds the planet (%d probe hits)\n'
                        % (endpoint, len(elements)))
            return True
        return None

    @property
    def live(self):
        """The mirrors that answered the probe with the planet's own data."""
        if self._live is None:
            self._live = []
            for index, endpoint in enumerate(self._candidates):
                if index:
                    # Six probes in two seconds is itself the thing that gets
                    # a client rate-limited off a mirror it could have used.
                    time.sleep(self._probe_pause)
                if self._probe(endpoint):
                    self._live.append(endpoint)
            if not self._live:
                self._write('  NO Overpass mirror answered the planet probe\n')
        return self._live

    def get(self, query, tries=3, timeout=420, pause=8.0):
        """Run one query, over every live mirror, ``tries`` times each.

        Returns the gzipped response body, or ``None`` when every mirror
        refused it — never a partial or an empty answer dressed as success.
        The caller decides what an empty result set means, because for the
        cross-check an empty tile is a real answer (there is no track there)
        and for the inventory it is not.
        """
        mirrors = self.live
        if not mirrors:
            return None
        # Start at whichever answered last: a long run should not pay the
        # first mirror's timeout once per tile after it has started failing.
        start = mirrors.index(self._preferred) if self._preferred in mirrors else 0
        order = mirrors[start:] + mirrors[:start]
        for attempt in range(tries):
            for endpoint in order:
                try:
                    body = _post(endpoint, query, timeout=timeout)
                except Exception as exc:               # noqa: BLE001
                    detail = getattr(exc, 'code', None) or type(exc).__name__
                    self._write('  retry %s %s\n'
                                % (endpoint.split('/')[2], detail))
                    time.sleep(2.0)
                    continue
                self._preferred = endpoint
                return body
            time.sleep(pause + pause * attempt)
        return None
