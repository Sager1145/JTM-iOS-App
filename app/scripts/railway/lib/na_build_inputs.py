"""Build-time source records that survive full and scoped package builds."""
import hashlib
import os
from pathlib import Path


def digest_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def capture_inputs(registry, source_dir, scripts_dir, osm_routes=None):
    """Snapshot exact input bytes before building, not after a long run.

    Paths are relative to the repository root, matching audit --input-root.
    Raw inputs outside that root remain absolute instead of suggesting they
    can be recovered from the repository. No download or secret is recorded.
    """
    scripts = Path(scripts_dir).resolve()
    root = scripts.parents[2]
    paths = {Path(registry).resolve(), scripts / 'build-north-america-rail-package.py',
             scripts / 'na-operator-brands.json'}
    paths.update((scripts / 'lib').glob('*.py'))
    for folder in ('gtfs', 'official-networks', 'official-raw', 'official-geom',
                   'narn', 'osm-geom'):
        paths.update(p for p in (Path(source_dir) / folder).rglob('*') if p.is_file())
    for name in ('quebec-rail.geojson', 'narn-passenger.geojson'):
        path = Path(source_dir) / name
        if path.is_file():
            paths.add(path)
    if osm_routes:
        paths.update(p for p in Path(osm_routes).rglob('*') if p.is_file())
    records = {}
    for path in sorted(paths):
        if not path.is_file():
            continue
        resolved = path.resolve()
        key = str(resolved.relative_to(root)) if resolved.is_relative_to(root) else str(resolved)
        records[key] = digest_file(resolved)
    return records


def merge_inputs(shipped, candidate, feed, partial=False):
    """Never label retained lines as rebuilt from a candidate's new inputs."""
    records = dict(shipped.get('buildInputsByFeed') or {})
    previous = shipped.get('buildInputs')
    if previous:
        for line in shipped['lines']:
            if line.get('sourceFeed'):
                records.setdefault(line['sourceFeed'], previous)
    current = (candidate.get('buildInputsByFeed') or {}).get(feed)
    current = current or candidate.get('buildInputs')
    if partial:
        # One feed may now contain lines from two builds. Do not certify the
        # untouched lines with the candidate's input record.
        records.pop(feed, None)
    elif current:
        records[feed] = current
    else:
        records.pop(feed, None)
    return records
