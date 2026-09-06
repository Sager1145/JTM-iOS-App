"""Every path a railway script or a sources file cites must outlive the machine.

A cited path is a promise that someone can go and look. `/private/tmp` and
`/tmp` cannot keep it: the directory is wiped, and once it is, the citation
says only that the data was once somewhere on somebody's laptop. That is not
a hypothetical — 52 researched OpenStreetMap line colours were cited to
`/private/tmp/jtm-na-rail/patches/`, the directory went, and the research went
with it before it was ever merged.

So the North America pipeline's documented invocations name
`data/raw/na-rail/`, which is inside the checkout (and gitignored, so nothing
downloaded becomes committable), and a package's sources file cites the
PUBLICATION a file was fetched from rather than the scratch path it was parked
at. Neither rule is enforced by the argument parsers — every one of these
arguments is required, and an explicit path outside the repository still
works, which is what a one-off fetch onto a big disk needs.
"""
import re
import unittest
from pathlib import Path


RAILWAY = Path(__file__).parents[1]
RAIL_PACKAGES = RAILWAY.parents[1] / 'public' / 'rail'
REPO = RAILWAY.parents[2]

#: The scripts whose usage examples drive the North America build, and the
#: arguments each one documents a `data/raw/na-rail` location for.
NA_PIPELINE = {
    'download-north-america-gtfs.py': ['--output-dir'],
    'download-north-america-narn.py': ['--output-dir'],
    'download-north-america-osm-crosscheck.py': ['--output-dir'],
    'download-north-america-osm-inventory.py': ['--output'],
    'download-north-america-osm-routes.py': ['--coverage', '--output-dir'],
    'crosscheck-na-stations.py': ['--tile-dir', '--out'],
    'make-na-feed-registry.py': ['--scan'],
    'report-na-coverage.py': ['--inventory', '--out'],
    'audit-na-package.py': ['--out'],
    'build-north-america-rail-package.py': ['--source-dir'],
    'build-display-network.py': ['--output'],
}

SCRATCH_ROOT = re.compile(r'(?<![\w./-])/(?:private/)?tmp/[\w./-]+')


class DocumentedScratchPathTests(unittest.TestCase):
    def test_na_pipeline_documents_paths_under_the_checkout(self):
        for name, arguments in NA_PIPELINE.items():
            doc = (RAILWAY / name).read_text()
            start = doc.index('"""')
            head = doc[start:doc.index('"""', start + 3)]
            for argument in arguments:
                cited = re.search(rf'{re.escape(argument)}\s+(\S+)', head)
                self.assertIsNotNone(cited, f'{name} {argument} is not documented')
                path = cited.group(1)
                # `build-display-network.py` is documented from the repository
                # root and the rest from `app/`, so both spellings resolve to
                # the same directory.
                self.assertRegex(
                    path, r'^(app/)?data/raw/na-rail(/|$)',
                    f'{name} {argument} cites {path}, which is not under '
                    'the checkout\'s raw-data directory')

    def test_that_directory_is_gitignored(self):
        # The point of `data/raw` is that a fetch can land in the checkout
        # without any of it becoming committable.
        ignore = (REPO / '.gitignore').read_text().splitlines()
        self.assertIn('app/data/raw/', [line.strip() for line in ignore])

    def test_no_railway_script_cites_a_wiped_scratch_directory(self):
        for script in sorted(RAILWAY.glob('*.py')):
            found = SCRATCH_ROOT.findall(script.read_text())
            self.assertEqual(found, [], f'{script.name} cites {found}')

    def test_no_sources_file_cites_a_scratch_path_as_provenance(self):
        # A sources file exists so a questionable segment can be traced to the
        # publication it came from. A scratch path traces to nothing, so where
        # one used to stand there is now either a URL or, for Macao, a written
        # statement that the source is unresolved.
        for sources in sorted(RAIL_PACKAGES.glob('*.sources.md')):
            found = SCRATCH_ROOT.findall(sources.read_text())
            self.assertEqual(found, [], f'{sources.name} cites {found}')


if __name__ == '__main__':
    unittest.main()
