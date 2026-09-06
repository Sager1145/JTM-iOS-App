"""Every tests/test_*.py must actually run its tests when executed directly.

Twice on 2026-09-05 a test file reported success without having checked
anything, and both times it was invisible because the runner's exit status
was 0:

* `test_na_builder.py` had `if __name__ == '__main__': unittest.main()`
  sixteen test methods before the end of the file. Run directly it defined
  and ran 116 tests and exited 0; `python3 -m unittest` collected 132. The
  sixteen included the tests guarding a builder change that had just landed.
* `test_na_builder_surveyed_gate.py` had no main block at all. Run directly
  it printed nothing and exited 0 -- indistinguishable from a pass.

Both were found by noticing a count that disagreed with another invocation,
which is not a method anyone should have to rely on. The failure is the same
one that ran through that whole day's work: a check that reports success
without having checked. This file makes the suite able to tell "passed" from
"never ran".

Note that `python3 -m unittest discover` is unaffected by either defect --
it imports the module and collects every class regardless of where the main
block sits. So a green CI run is not evidence against this; the two
invocations genuinely disagree, and the direct one is what a person types.
"""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
MAIN_BLOCK = re.compile(r"^if __name__ == ['\"]__main__['\"]:", re.M)
DEFINES_TESTS = re.compile(r"^(class \w*Tests?\b|class Test\w*\b|    def test_)", re.M)


def test_files():
    return sorted(name for name in os.listdir(HERE)
                  if name.startswith('test_') and name.endswith('.py'))


class EveryTestFileActuallyRunsTests(unittest.TestCase):

    def test_every_test_file_has_a_main_block(self):
        missing = [name for name in test_files()
                   if not MAIN_BLOCK.search(
                       open(os.path.join(HERE, name)).read())]
        self.assertEqual(
            missing, [],
            'run directly these print nothing and exit 0, which is '
            'indistinguishable from a pass: %s' % ', '.join(missing))

    def test_no_test_is_defined_after_the_main_block(self):
        stranded = {}
        for name in test_files():
            source = open(os.path.join(HERE, name)).read()
            match = MAIN_BLOCK.search(source)
            if not match:
                continue
            tail = source[match.end():]
            count = len(re.findall(r'^    def test_', tail, re.M))
            if count or DEFINES_TESTS.search(tail):
                stranded[name] = count
        self.assertEqual(
            stranded, {},
            'these tests are never defined when the file is run directly, so '
            'they silently do not run: %s' % ', '.join(
                '%s (%d)' % item for item in sorted(stranded.items())))


if __name__ == '__main__':
    unittest.main()
