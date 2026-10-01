"""Audit the live-confirmed issue month for selected JR Hokkaido 2026-09-30 pages."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ROOT / 'app/data/train-service-history/sources'
SECTION_IDS = {'110', '111', '130', '131', '150', '151'}


class HokkaidoIssueMonthMetadataTests(unittest.TestCase):
    def test_all_exact_date_section_sources_use_live_october_footer(self):
        matched = []
        for path in SOURCES.glob('*.jsonl'):
            for line in path.read_text(encoding='utf-8').splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                url = row.get('url_or_locator', '')
                if 'd=20260930' not in url:
                    continue
                if not any(f's={section}' in url for section in SECTION_IDS):
                    continue
                matched.append((path.name, row['source_id'], row.get('issue'), url))
        self.assertTrue(matched)
        covered_sections = {
            section for _, _, _, url in matched for section in SECTION_IDS
            if f's={section}' in url
        }
        self.assertEqual(covered_sections, SECTION_IDS)
        stale = [item for item in matched if item[2] != 'JR時刻表 令和8年10月号']
        self.assertEqual(stale, [])


if __name__ == '__main__':
    unittest.main()
