"""Guard: app-control.py accepts the tapMap action and passes its lat/lon or x/y arguments through.

Run: python3 -I -m unittest discover -s ios/tools/tests -p test_app_control_tap_map.py
"""
import importlib.util
import unittest
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "app-control.py"


def load():
    spec = importlib.util.spec_from_file_location("app_control", PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TapMap(unittest.TestCase):
    def test_tap_map_is_a_known_action(self):
        self.assertIn("tapMap", load().COMMANDS)

    def test_tap_map_is_documented(self):
        self.assertIn("tapMap", load().__doc__)

    def test_both_argument_forms_parse_as_numbers(self):
        m = load()
        self.assertEqual([m.parse_value(v) for v in ("35.68", "139.76")], [35.68, 139.76])
        self.assertEqual([m.parse_value(v) for v in ("120", "340.5")], [120, 340.5])
