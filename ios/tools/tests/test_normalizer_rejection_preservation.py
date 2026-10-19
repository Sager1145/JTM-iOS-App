"""Rejected reviewed input must leave previously accepted evidence intact."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parents[1]
BASE = ROOT / 'app/data/train-service-history'


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), TOOLS / (name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def fixture(path):
    # All copied files are small retained inputs; only the private root is writable.
    for pattern in ('manifest.json', 'normalized/**/*.jsonl', 'sources/**/*.jsonl', 'sources/candidates/*.json', 'candidates/*.json'):
        for source in BASE.glob(pattern):
            target = path / source.relative_to(BASE)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)


def evidence(path):
    return {p.relative_to(path): p.read_bytes() for area in ('normalized', 'sources')
            for p in (path / area).rglob('*.jsonl')}


class RejectionPreservationTests(unittest.TestCase):
    def test_n02_closed_research_rejects_without_publishing_completeness(self):
        for name in ('normalize-reviewed-current-n02-route-identities-20260930',
                     'normalize-reviewed-priority-current-n02-route-identities-20260930'):
            with self.subTest(normalizer=name), tempfile.TemporaryDirectory() as scratch:
                base = Path(scratch)
                fixture(base)
                normalizer = module(name)
                candidate_path = base / normalizer.DEFAULT_CANDIDATE.relative_to(BASE)
                candidate = json.loads(candidate_path.read_text())
                rail_path = ROOT / 'app/public/rail/jp-2025.json'
                if name.startswith('normalize-reviewed-priority'):
                    # This older cohort pins package metadata 2025.5.0; retained
                    # line/station membership is used unchanged in this rejection fixture.
                    package = json.loads(rail_path.read_text())
                    package['version'] = '2025.5.0'
                    rail_path = base / 'rail-fixture.json'
                    rail_path.write_text(json.dumps(package))
                trip_id = candidate['partial_route_state'][0]['trip_id']
                for path in (base / 'normalized').glob('fact-completeness*.jsonl'):
                    rows = [json.loads(line) for line in path.read_text().splitlines()]
                    for row in rows:
                        if row.get('entity_id') == trip_id and row.get('dimension') == 'route_lines':
                            row['notes'] = 'Previously accepted evidence note'
                    path.write_text(''.join(json.dumps(row, ensure_ascii=False) + '\n' for row in rows))
                for path in (base / 'normalized').glob('research-queue*.jsonl'):
                    rows = [json.loads(line) for line in path.read_text().splitlines()]
                    for row in rows:
                        if row.get('entity_id') == trip_id and row.get('missing_dimension') == 'route_lines':
                            row['status'] = 'resolved'
                    path.write_text(''.join(json.dumps(row, ensure_ascii=False) + '\n' for row in rows))
                before = evidence(base)
                with self.assertRaisesRegex(ValueError, 'route research must remain open'):
                    normalizer.normalize(base, candidate_path, rail_path)
                after = evidence(base)
                self.assertEqual([], [str(path) for path in before.keys() | after.keys()
                                      if before.get(path) != after.get(path)])

    def test_fujikawa_bad_candidate_preserves_shared_service(self):
        with tempfile.TemporaryDirectory() as scratch:
            base = Path(scratch)
            fixture(base)
            normalizer = module('normalize-reviewed-central-fujikawa2-20260930')
            normalizer.BASE = base
            path = base / 'candidates/jr-central-fujikawa2-20260930.json'
            candidate = json.loads(path.read_text())
            candidate['trip']['direction'] = 'rejected'
            path.write_text(json.dumps(candidate))
            service = base / 'normalized/services-central-fujikawa-20260930.jsonl'
            rows = [json.loads(line) for line in service.read_text().splitlines()]
            rows[0]['notes'] = 'Previously accepted service evidence'
            service.write_text(''.join(json.dumps(row) + '\n' for row in rows))
            before = evidence(base)
            with self.assertRaisesRegex(ValueError, 'direction changed'):
                normalizer.main()
            after = evidence(base)
            self.assertEqual([], [str(path) for path in before.keys() | after.keys()
                                  if before.get(path) != after.get(path)])

    def test_akagi_bad_english_url_preserves_accepted_english_evidence(self):
        with tempfile.TemporaryDirectory() as scratch:
            base = Path(scratch)
            fixture(base)
            wrapper = module('normalize-reviewed-akagi-20260930-seed')
            wrapper.normalizer.BASE = base
            wrapper.normalizer.CANDIDATE = base / 'candidates/jr-east-akagi-20260930.json'
            candidate = json.loads(wrapper.normalizer.CANDIDATE.read_text())
            candidate['english_name_source']['url_or_locator'] = 'https://example.invalid/changed'
            wrapper.normalizer.CANDIDATE.write_text(json.dumps(candidate))
            before = evidence(base)
            with self.assertRaisesRegex(ValueError, 'Akagi English name source changed'):
                wrapper.main()
            after = evidence(base)
            self.assertEqual([], [str(path) for path in before.keys() | after.keys()
                                  if before.get(path) != after.get(path)])


if __name__ == '__main__':
    unittest.main()
