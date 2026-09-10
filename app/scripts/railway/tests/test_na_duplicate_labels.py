"""One station, one label -- ``resolve_colliding_station_labels``.

A station group's canonical name (``canonical_group_name``) is a property of
the PLACE, and every line calling there is renamed to it. Two DIFFERENT
stations that both fall into complexes sharing that canonical name then ship
the same label twice on one line: MTA's L carried "14 St" for both GTFS
parent L01 ("8 Av") and parent L02 ("6 Av"), 0.56 km apart.

``resolve_colliding_station_labels`` is the per-line post-pass that catches a
label shared by two distinct station codes on ONE line and puts each
station's own published GTFS name back on that line's own rows -- and only
that line's rows. A second line that also calls at one of those stations
under the shared group name, but never itself reuses the label on two
different stations, is not a collision on that line and is left alone.

Unless the published names are themselves identical, in which case the two
stations are simply two real places with the same name (NYC N/R "59 St" in
Manhattan and in Brooklyn) and nothing is rewritten. A loop's wrap or a
not-yet-folded repeated call shares a label under the SAME station code and
is not a collision at all.
"""
import importlib.util
import os
import unittest

SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', 'build-north-america-rail-package.py'))
SPEC = importlib.util.spec_from_file_location(
    'na_package_builder_duplicate_labels_test', SCRIPT)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


def make_line(line_id, station_ids, published_names):
    """A line whose station ids/published names are its own GTFS, distinct
    from whatever group naming later assigns as the display name."""
    return {'lineId': line_id, 'stationIds': list(station_ids),
            'stationNames': list(published_names)}


def make_group_world(*, lines_and_codes, group_names, published_by_code=None):
    """Build the ``group_meta``/``codes``/``names`` a real build would have
    produced by the time ``resolve_colliding_station_labels`` runs: every
    (line, index) already carries its group's canonical display name.

    ``lines_and_codes`` is ``[(line, [code, code, ...]), ...]`` in station
    order. ``group_names`` is ``{code: canonical_group_name}``.
    """
    codes = {}
    names = {}
    members_by_code = {}
    for line, line_codes in lines_and_codes:
        for i, code in enumerate(line_codes):
            codes[(id(line), i)] = code
            names[(id(line), i)] = group_names[code]
            members_by_code.setdefault(code, []).append(
                {'line': line, 'index': i})
    group_meta = [{'code': code, 'name': group_names[code], 'members': members}
                  for code, members in members_by_code.items()]
    return [line for line, _ in lines_and_codes], group_meta, codes, names


class ResolveCollidingStationLabelsTests(unittest.TestCase):
    def test_collision_relabels_only_the_exposing_line(self):
        # MTA L: parent L01 "8 Av" and parent L02 "6 Av", both group-named
        # "14 St" because their complexes share that label -- a collision on
        # the L. A second line (the A) also calls at the SAME merged
        # complex code but at a genuinely DIFFERENT raw GTFS stop id
        # ("A20", its own platform, distinct from the L's raw "L01") and
        # never itself reuses "14 St" on two different stations, so it is
        # not a collision on the A and must be left exactly as it was --
        # the fix reaches a platform's other callers only when they share
        # the exposing line's own raw stop id.
        l_train = make_line('mta-l', ['L01', 'X', 'L02'], ['8 Av', 'Mid', '6 Av'])
        a_train = make_line('mta-a', ['A20'], ['8 Av'])
        region_lines, group_meta, codes, names = make_group_world(
            lines_and_codes=[(l_train, ['us-official-14st-1', 'us-official-mid',
                                        'us-official-14st-2']),
                             (a_train, ['us-official-14st-1'])],
            group_names={'us-official-14st-1': '14 St', 'us-official-mid': 'Mid',
                         'us-official-14st-2': '14 St'})

        notes = builder.resolve_colliding_station_labels(
            region_lines, group_meta, codes, names)

        self.assertEqual(names[(id(l_train), 0)], '8 Av')
        self.assertEqual(names[(id(l_train), 2)], '6 Av')
        # The A calls a different raw stop of the same merged complex code
        # and never had a collision of its own -- its row keeps the group
        # name it had before the L's collision was resolved.
        self.assertEqual(names[(id(a_train), 0)], '14 St')
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0]['line'], 'mta-l')
        self.assertEqual(notes[0]['label'], '14 St')

    def test_collision_propagates_to_other_callers_of_the_same_raw_stop(self):
        # MTA "59 St" complex code holds three genuinely different
        # platforms merged behind one interchange code. The N exposes a
        # collision at raw stop "R11" (BMT's own platform); the R also
        # calls that SAME raw stop "R11" under the same stale group name
        # and must be corrected too, since it is truly the one platform
        # the label was ambiguous about.
        n_train = make_line('mta-n', ['R11', 'R20'], ['59 St', '4 Av'])
        r_train = make_line('mta-r', ['R11'], ['59 St'])
        region_lines, group_meta, codes, names = make_group_world(
            lines_and_codes=[(n_train, ['us-official-59st-complex',
                                        'us-official-4av-complex']),
                             (r_train, ['us-official-59st-complex'])],
            group_names={'us-official-59st-complex': '4 Av-59 St',
                         'us-official-4av-complex': '4 Av-59 St'})

        notes = builder.resolve_colliding_station_labels(
            region_lines, group_meta, codes, names)

        self.assertEqual(names[(id(n_train), 0)], '59 St')
        # The R shares the N's exact raw stop id "R11" -- same platform,
        # so it takes the same corrected name.
        self.assertEqual(names[(id(r_train), 0)], '59 St')

    def test_single_occurrence_complex_label_never_touched(self):
        # W's single "59 St" call is one station under one code -- there is
        # no second station on the W sharing that label, so it is not a
        # collision even though other lines' "59 St" collides.
        w_train = make_line('mta-w', ['R41'], ['59 St'])
        region_lines, group_meta, codes, names = make_group_world(
            lines_and_codes=[(w_train, ['us-official-59st-brooklyn'])],
            group_names={'us-official-59st-brooklyn': '59 St'})

        notes = builder.resolve_colliding_station_labels(
            region_lines, group_meta, codes, names)

        self.assertEqual(names[(id(w_train), 0)], '59 St')
        self.assertEqual(notes, [])

    def test_identical_published_names_left_untouched(self):
        # NYC N/R "59 St": Manhattan and Brooklyn are genuinely two
        # different stations that are really both called "59 St".
        n_train = make_line('mta-n', ['R11', 'R41'], ['59 St', '59 St'])
        region_lines, group_meta, codes, names = make_group_world(
            lines_and_codes=[(n_train, ['us-official-59st-manhattan',
                                        'us-official-59st-brooklyn'])],
            group_names={'us-official-59st-manhattan': '59 St',
                         'us-official-59st-brooklyn': '59 St'})

        notes = builder.resolve_colliding_station_labels(
            region_lines, group_meta, codes, names)

        self.assertEqual(names[(id(n_train), 0)], '59 St')
        self.assertEqual(names[(id(n_train), 1)], '59 St')
        self.assertEqual(notes, [])

    def test_loop_wrap_is_not_a_collision(self):
        # A loop's closing station repeats the SAME code as the opener --
        # same station, not two stations sharing a label.
        loop = make_line('loop-a', ['S', 'M', 'S'], ['Start', 'Mid', 'Start'])
        region_lines, group_meta, codes, names = make_group_world(
            lines_and_codes=[(loop, ['us-official-start', 'us-official-mid',
                                     'us-official-start'])],
            group_names={'us-official-start': 'Start', 'us-official-mid': 'Mid'})

        notes = builder.resolve_colliding_station_labels(
            region_lines, group_meta, codes, names)

        self.assertEqual(names[(id(loop), 0)], 'Start')
        self.assertEqual(names[(id(loop), 2)], 'Start')
        self.assertEqual(notes, [])

    def test_non_colliding_labels_are_untouched(self):
        line = make_line('line-x', ['A', 'B', 'C'], ['A', 'B', 'C'])
        region_lines, group_meta, codes, names = make_group_world(
            lines_and_codes=[(line, ['us-official-a', 'us-official-b',
                                     'us-official-c'])],
            group_names={'us-official-a': 'A', 'us-official-b': 'B',
                         'us-official-c': 'C'})

        notes = builder.resolve_colliding_station_labels(
            region_lines, group_meta, codes, names)

        self.assertEqual(names[(id(line), 0)], 'A')
        self.assertEqual(names[(id(line), 1)], 'B')
        self.assertEqual(names[(id(line), 2)], 'C')
        self.assertEqual(notes, [])


if __name__ == '__main__':
    unittest.main()
