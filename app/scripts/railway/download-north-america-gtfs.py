#!/usr/bin/env python3
"""Download every operator feed the registry names.

    python3 scripts/railway/download-north-america-gtfs.py \
        --registry scripts/railway/na-feeds.json \
        --output-dir /private/tmp/na-rail/gtfs

The operator's OWN url is tried first and the MobilityData mirror second, and
which one answered is recorded beside the file. That order matters for what the
package is allowed to claim: a feed fetched from the operator is the operator's
statement about its railway on the day it was fetched, and one fetched from a
mirror is a copy of that statement whose age is the mirror's. Both are usable;
only the first is first-hand, and the sources note says which each line was
built from.

Each download is verified as a readable zip before it replaces what is there,
so an interrupted run leaves the previous feed intact rather than a truncated
file that the builder would read as an operator with no railways.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import threading
import time
import zipfile
import concurrent.futures as cf

USER_AGENT = ('JTM-RailMap-DataBuild/1.0 '
              '(https://github.com/Sager1145/JTM-iOS-App)')


def fetch(url, destination, timeout=90, resume_key='source'):
    # `urlopen(timeout=…)` does not bound every DNS/TLS phase on macOS and a
    # dead operator host used to occupy a worker for ten minutes. curl's
    # connect and whole-transfer deadlines do, which lets the mirror actually
    # be tried while the build is still running.
    part = destination + f'.{resume_key}.part'
    subprocess.run([
        'curl', '-fL', '--silent', '--show-error', '--connect-timeout', '10',
        '--max-time', str(timeout), '--user-agent', USER_AGENT,
        '--continue-at', '-', '--output', part, url,
    ], check=True)
    validate_zip(part)
    os.replace(part, destination)


def validate_zip(path):
    """Validate directory, required GTFS members, and every member CRC."""
    with zipfile.ZipFile(path) as archive:
        names = {n.rsplit('/', 1)[-1] for n in archive.namelist()}
        if 'routes.txt' not in names or 'stops.txt' not in names:
            raise ValueError('not a GTFS feed')
        corrupt = archive.testzip()
        if corrupt:
            raise ValueError(f'corrupt zip member: {corrupt}')


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--registry', required=True)
    ap.add_argument('--output-dir', required=True)
    ap.add_argument('--workers', type=int, default=6)
    ap.add_argument('--timeout', type=int, default=90,
                    help='seconds per operator or mirror attempt')
    ap.add_argument('--force', action='store_true')
    ap.add_argument('--manifest', default=None)
    options = ap.parse_args()

    with open(options.registry) as fh:
        registry = json.load(fh)
    os.makedirs(options.output_dir, exist_ok=True)

    lock = threading.Lock()
    manifest = {}
    done = [0]

    def work(entry):
        destination = os.path.join(options.output_dir, f"{entry['mdb']}.zip")
        if os.path.exists(destination) and not options.force:
            try:
                validate_zip(destination)
            except Exception as exc:                     # noqa: BLE001
                record = {'slug': entry['slug'], 'error':
                          f'cache: {type(exc).__name__}: {str(exc)[:120]}'}
            else:
                record = {'slug': entry['slug'], 'from': 'cache',
                          'bytes': os.path.getsize(destination),
                          'sha256': sha256(destination)}
        else:
            record = None
        if record is None or record.get('error'):
            for label, url in (('operator', entry.get('url')),
                               ('mirror', entry.get('mirror'))):
                if not url:
                    continue
                try:
                    fetch(url, destination, timeout=options.timeout,
                          resume_key=label)
                except Exception as exc:                     # noqa: BLE001
                    record = {'slug': entry['slug'], 'error':
                              f'{label}: {type(exc).__name__}: {str(exc)[:120]}'}
                    continue
                record = {'slug': entry['slug'], 'from': label, 'url': url,
                          'bytes': os.path.getsize(destination),
                          'sha256': sha256(destination)}
                break
        with lock:
            manifest[entry['mdb']] = record
            done[0] += 1
            state = record.get('from') or record.get('error', '?')
            sys.stderr.write(f"{done[0]}/{len(registry['feeds'])} "
                             f"{entry['slug']}: {state}\n")
            sys.stderr.flush()

    started = time.time()
    with cf.ThreadPoolExecutor(options.workers) as ex:
        list(ex.map(work, registry['feeds']))
    ok = sum(1 for r in manifest.values() if r and not r.get('error'))
    sys.stderr.write(f'{ok}/{len(manifest)} feeds available '
                     f'({time.time() - started:.0f}s)\n')
    if options.manifest:
        with open(options.manifest, 'w') as fh:
            json.dump(manifest, fh, ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
