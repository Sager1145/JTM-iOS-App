"""Coverage for the ``narn``-only unmatched-vertex exemption in
``filter_unresolved_geometry``.

Copy this file into ``app/scripts/railway/tests/`` alongside
``test_na_builder.py`` (same import shim, same module-under-test) after
``builder.patch`` has been applied.

Run against the UNPATCHED builder, every test in this file fails or errors,
because the behaviour under test does not exist yet:

  * ``test_surveyed_source_with_unmatched_vertices_under_deviation_limit_is_not_blocked``
    -- fails: pre-patch, ``unmatched > 0`` alone blocks regardless of
    ``geometrySource``, so the interval is withheld and ``kept[0]`` carries
    a ``displayBlockedIntervals`` key this test asserts is absent.
  * ``test_surveyed_source_over_the_deviation_limit_is_still_blocked`` --
    passes even pre-patch (deviation alone already blocks); kept here as a
    contract test so a future change to the deviation half of the predicate
    cannot silently exempt ``narn`` from it too.
  * ``test_non_surveyed_source_with_unmatched_vertices_is_still_blocked`` --
    passes pre-patch and post-patch alike; guards the "everything else is
    unchanged" half of the contract, exactly one of ``builder.SURVEYED_
    GEOMETRY_SOURCES`` away from the first test above.
  * The ``SURVEYED_GEOMETRY_SOURCES`` attribute itself does not exist
    pre-patch, so ``AttributeError`` is what the first two tests actually
    raise rather than an assertion failure -- both are "this file fails
    against the unpatched tree" outcomes.

After ``builder.patch`` is applied, every test in this file passes.
"""
import importlib.util
import os
import unittest
from types import SimpleNamespace


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'build-north-america-rail-package.py'))
SPEC = importlib.util.spec_from_file_location('na_package_builder', SCRIPT)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class SurveyedGeometryUnmatchedExemptionTests(unittest.TestCase):
    """``filter_unresolved_geometry`` -- ``narn`` blocks on deviation only.

    Mirrors ``DisplayAlignmentReleaseTests`` in ``test_na_builder.py``: same
    minimal line shape, same fake ``Survey.measure`` stand-in for the
    independent reference.
    """

    @staticmethod
    def line(geometry_source, profile='metro'):
        return {
            'lineId': 'feed-route', 'feed': 'feed', 'sourceRouteId': 'R',
            'branchOf': None, 'profile': profile,
            'geometrySource': geometry_source,
            'anchors': [[0.0, 0.0], [0.01, 0.0]],
            'intervals': [[[0.0, 0.0], [0.005, 0.001], [0.01, 0.0]]],
        }

    def test_surveyed_source_with_unmatched_vertices_under_deviation_limit_is_not_blocked(self):
        class Survey:
            @staticmethod
            def measure(_intervals, _source, sample_every):
                return {'vertices': 3, 'unmatched': 1,
                        'maxDeviationMeters': 10.0, 'worstAt': None}

        line = self.line('narn')
        options = SimpleNamespace(geometry_blockers=[])
        kept = builder.filter_unresolved_geometry([line], options, Survey())

        self.assertEqual(kept, [line])
        self.assertEqual(options.geometry_blockers, [])
        self.assertNotIn('displayBlockedIntervals', line['_alignmentCheck'])
        # The measurement is still recorded -- only the block is waived.
        self.assertEqual(line['_alignmentCheck']['unmatched'], 1)

    def test_surveyed_source_over_the_deviation_limit_is_still_blocked(self):
        class Survey:
            @staticmethod
            def measure(_intervals, _source, sample_every):
                return {'vertices': 3, 'unmatched': 1,
                        'maxDeviationMeters': 29.0,
                        'worstAt': [0.005, 0.001]}

        line = self.line('narn')
        options = SimpleNamespace(geometry_blockers=[])
        kept = builder.filter_unresolved_geometry([line], options, Survey())

        self.assertEqual(len(kept), 1)
        self.assertEqual(kept[0]['_alignmentCheck']['displayBlockedIntervals'],
                         [0])
        self.assertEqual(options.geometry_blockers[-1]['unmatchedVertices'], 1)
        self.assertEqual(options.geometry_blockers[-1]['maxDeviationMeters'],
                         29.0)

    def test_non_surveyed_source_with_unmatched_vertices_is_still_blocked(self):
        class Survey:
            @staticmethod
            def measure(_intervals, _source, sample_every):
                return {'vertices': 3, 'unmatched': 1,
                        'maxDeviationMeters': 0.0, 'worstAt': None}

        line = self.line('gtfs-shape')
        options = SimpleNamespace(geometry_blockers=[])
        kept = builder.filter_unresolved_geometry([line], options, Survey())

        self.assertEqual(len(kept), 1)
        self.assertEqual(kept[0]['_alignmentCheck']['displayBlockedIntervals'],
                         [0])
        self.assertEqual(options.geometry_blockers[-1]['unmatchedVertices'], 1)

    def test_surveyed_geometry_sources_is_exactly_narn(self):
        self.assertEqual(builder.SURVEYED_GEOMETRY_SOURCES, frozenset({'narn'}))


if __name__ == '__main__':
    unittest.main()
