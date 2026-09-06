"""Coverage for the NARN ``dropped`` diagnostics and ``snap_prefer_m``.

Copy this file into ``app/scripts/railway/tests/`` alongside
``test_na_builder.py`` (same import shim, same module-under-test) after
``builder.patch`` has been applied.

This file is importable, and every test method runs, against BOTH the
CURRENT (unpatched) builder and the patched one -- nothing here depends on
a name the patch introduces at import time, only at call time. Run against
the unpatched tree, the following fail, and only these, because the
behaviour they check for does not exist yet:

  * ``NarnSnapPreferMetersTests`` (all methods) -- ``FeedBuild`` has no
    ``snap_prefer_m`` method yet, so every call raises ``AttributeError``.
  * ``DroppedRecordStageTests.test_routed_most_but_not_all_records_the_gap``
    -- fails on ``assertTrue(...)``: ``geometry_for`` never appends a
    'NARN routed most but not all stations of this pattern' record, because
    the had_gap/patched-successfully branch does not emit one pre-patch.
  * ``DroppedRecordStageTests.test_could_not_route_enough_records_every_stage``
    -- fails the same way: no 'NARN could not route enough of this pattern'
    record is ever appended pre-patch, so the ``any(...)`` search comes back
    empty.
  * ``DroppedRecordStageTests.test_prefer_m_is_threaded_into_route_stations``
    -- fails because the unpatched call site never passes a ``prefer_m``
    keyword to ``narn.route_stations``, so the captured kwargs dict has no
    ``'prefer_m'`` key and ``.get('prefer_m')`` reads back ``None``.

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


class NarnSnapPreferMetersTests(unittest.TestCase):
    """``FeedBuild.snap_prefer_m`` -- route beats feed beats CLI beats zero."""

    def feed(self, entry, options_kwargs):
        built = builder.FeedBuild.__new__(builder.FeedBuild)
        built.entry = entry
        built.options = SimpleNamespace(**options_kwargs)
        return built

    def test_nothing_set_anywhere_is_zero(self):
        built = self.feed({}, {})
        self.assertEqual(built.snap_prefer_m('R'), 0.0)

    def test_cli_default_applies_when_nothing_else_is_set(self):
        built = self.feed({}, {'snap_prefer_m': 10.0})
        self.assertEqual(built.snap_prefer_m('R'), 10.0)

    def test_feed_level_registry_setting_beats_the_cli_default(self):
        built = self.feed({'narnSnapPreferMeters': 30.0},
                          {'snap_prefer_m': 10.0})
        self.assertEqual(built.snap_prefer_m('R'), 30.0)

    def test_route_level_registry_setting_beats_feed_level(self):
        built = self.feed({
            'narnSnapPreferMeters': 30.0,
            'narnSnapPreferMetersByRouteId': {'R': 45.0},
        }, {'snap_prefer_m': 10.0})
        self.assertEqual(built.snap_prefer_m('R'), 45.0)
        # A route this map does not name still falls through to feed-level.
        self.assertEqual(built.snap_prefer_m('OTHER'), 30.0)

    def test_explicit_zero_at_a_higher_level_still_falls_through(self):
        # `0 or feed_value` -- an explicit 0 at the route level is falsy,
        # so it is not "the route decided 0", it is "the route has nothing
        # to say" and the next level down is asked. Documented here as the
        # method's actual behaviour, not a bug: nothing in this build ever
        # needs to force a route to LESS preference than its feed default.
        built = self.feed({
            'narnSnapPreferMeters': 30.0,
            'narnSnapPreferMetersByRouteId': {'R': 0.0},
        }, {})
        self.assertEqual(built.snap_prefer_m('R'), 30.0)


class DroppedRecordStageTests(unittest.TestCase):
    """The two silent NARN exits in ``geometry_for`` now name their stage.

    Both scenarios below route four stations (three intervals) through a
    monkeypatched ``narn.route_stations`` and let the REAL
    ``reject_far_snap_intervals`` / ``reject_detours`` run over that fixed
    input, so ``stage_of`` is exercised against genuine rejections rather
    than a second layer of mocking.
    """

    def setUp(self):
        self.feed = builder.FeedBuild.__new__(builder.FeedBuild)
        self.feed.network = object()          # truthy: enters the NARN branch
        self.feed.entry = {'narnSnapPreferMeters': 30.0}
        self.feed.options = SimpleNamespace(
            anchor_m=600.0, corridor_m=1_500.0, snap_m=3_000.0,
            snap_prefer_m=0.0)
        self.feed.report = {'dropped': [], 'notes': []}
        self.points = [[0.0, 0.0], [0.01, 0.0], [0.02, 0.0], [0.03, 0.0]]
        self.calls = []

    def mock_route_stations(self, routed, routing):
        original = builder.narn.route_stations

        def fake(*args, **kwargs):
            self.calls.append(kwargs)
            return list(routed), routing

        builder.narn.route_stations = fake
        self.addCleanup(setattr, builder.narn, 'route_stations', original)

    def dropped(self, why):
        return [row for row in self.feed.report['dropped']
                if row.get('why') == why]

    def test_prefer_m_is_threaded_into_route_stations(self):
        p0, p1, p2, p3 = self.points
        seg0, seg2 = [p0, p1], [p2, p3]
        self.mock_route_stations(
            [seg0, None, seg2],
            {'snapMeters': [50.0, 50.0, 50.0, 50.0]})
        self.feed.patch_with_shape = (
            lambda intervals, points, shape, schematic, kindname:
                [seg0, [p1, p2], seg2])

        self.feed.geometry_for(self.points, None, [], 'intercity', False, 'R')

        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0].get('prefer_m'), 30.0)

    def test_routed_most_but_not_all_records_the_gap(self):
        """Covered >= 80%, one gap, the shape patches it -- and it is logged.

        Interval 1 is never routed by NARN at all; intervals 0 and 2 are
        plain two-point pieces that match the straight line exactly, so
        neither ``reject_far_snap_intervals`` nor ``reject_detours`` touches
        them. Coverage is 2 of 3, at/above the 80% gate, so the line ships --
        but the specific gap and why it failed must still be in the report.
        """
        p0, p1, p2, p3 = self.points
        seg0, seg2 = [p0, p1], [p2, p3]
        self.mock_route_stations(
            [seg0, None, seg2],
            {'snapMeters': [50.0, 50.0, 50.0, 50.0]})
        patched = [seg0, [p1, p2], seg2]
        self.feed.patch_with_shape = (
            lambda intervals, points, shape, schematic, kindname: patched)

        intervals, source = self.feed.geometry_for(
            self.points, None, [], 'intercity', False, 'R')

        self.assertEqual(intervals, patched)
        self.assertEqual(source, self.feed.SHAPE_SOURCE)
        rows = self.dropped('NARN routed most but not all stations of this '
                            'pattern')
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row['route'], 'R')
        self.assertEqual(row['covered'], 2)
        self.assertEqual(row['total'], 3)
        self.assertEqual(row['failedIntervals'], ['1:unrouted'])
        self.assertEqual(row['preferMeters'], 30.0)
        self.assertEqual(row['usedInstead'], self.feed.SHAPE_SOURCE)

    def test_could_not_route_enough_records_every_stage(self):
        """Below the 80% gate, with one failure at each of the three stages.

        Interval 0 IS routed by NARN but one of its endpoints (station 0)
        snaps 700 m away -- past the 600 m ``anchor_m`` limit -- so
        ``reject_far_snap_intervals`` throws it out: 'far-snap'. Interval 1
        is never routed at all: 'unrouted'. Interval 2 is routed and snaps
        fine, but the returned piece doubles back on itself by about 168
        degrees, which ``reject_detours`` rejects as an internal reversal:
        'detour-or-reversal'. Coverage is 0 of 3, under the gate, so the
        whole pattern is withheld -- and the report says which of the three
        ways each interval failed.
        """
        p0, p1, p2, p3 = self.points
        seg0 = [p0, p1]
        # A sharp "V": ~168 degrees at the midpoint, well past the 155
        # degree reversal threshold, on legs long enough (~5.5 km) to clear
        # the 20 m minimum-leg filter.
        detour = [p2, [0.025, 0.05], p3]
        self.mock_route_stations(
            [seg0, None, detour],
            {'snapMeters': [700.0, 50.0, 50.0, 50.0]})

        intervals, source = self.feed.geometry_for(
            self.points, None, [], 'intercity', False, 'R')

        self.assertIsNone(intervals)
        self.assertIsNone(source)
        rows = self.dropped('NARN could not route enough of this pattern')
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row['route'], 'R')
        self.assertEqual(row['covered'], 0)
        self.assertEqual(row['total'], 3)
        self.assertEqual(row['failedIntervals'],
                         ['0:far-snap', '1:unrouted', '2:detour-or-reversal'])
        self.assertEqual(row['preferMeters'], 30.0)
        self.assertEqual(row['usedInstead'], self.feed.SHAPE_SOURCE)


if __name__ == '__main__':
    unittest.main()
