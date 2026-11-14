"""Guard: memory scoring reads app heap and the GPU row, and refuses a capture where MapKit was not
drawing (map-lock run 4: 437 MB footprint with 0.2 MB GPU was compared with run 5's 1.0 GB with 168 MB GPU).

Run: python3 -I -m unittest discover -s ios/tools/tests -p test_app_control_memory_score.py
"""
import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
HOST = TOOLS.parent / "RailMap/Diagnostics/AppControl/AppControlHost.swift"


def load():
    spec = importlib.util.spec_from_file_location("app_control", TOOLS / "app-control.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MemoryScore(unittest.TestCase):
    def test_run5_is_drawing_with_app_heap(self):
        score = load().parse_vmmap_summary((FIXTURES / "vmmap_summary_run5.txt").read_text())
        self.assertEqual(score["drawing"], "drawing")
        self.assertEqual(score["appHeapMB"], 556.0)
        self.assertEqual(score["gpuMB"], 168.1)
        self.assertEqual(score["footprintMB"], 1024.0)
        self.assertGreater(score["mapKitMB"], 150)

    def test_run4_is_not_drawing(self):
        score = load().parse_vmmap_summary((FIXTURES / "vmmap_summary_run4.txt").read_text())
        self.assertEqual(score["drawing"], "none")
        self.assertEqual(score["gpuMB"], 0.2)
        self.assertEqual(score["appHeapMB"], 342.9)

    def test_classes(self):
        m = load()
        self.assertEqual(
            [m.drawing_class(v) for v in (None, 0.5, 1, 59, 60, 400, 401)],
            ["none", "none", "hidden", "hidden", "drawing", "drawing", "backlog"])

    def test_missing_gpu_row_has_no_class(self):
        score = load().parse_vmmap_summary("Physical footprint:         100.0M\n")
        self.assertIsNone(score["gpuMB"])
        self.assertEqual(score["drawing"], "none")

    def test_cli_refuses_run4_and_accepts_run5(self):
        def run(name):
            return subprocess.run(
                [sys.executable, "-I", str(TOOLS / "app-control.py"), "memory-score", str(FIXTURES / name)],
                capture_output=True, text=True)
        refused = run("vmmap_summary_run4.txt")
        self.assertEqual(refused.returncode, 4)
        self.assertIn("error", json.loads(refused.stdout))
        accepted = run("vmmap_summary_run5.txt")
        self.assertEqual(accepted.returncode, 0)
        self.assertEqual(json.loads(accepted.stdout)["drawing"], "drawing")


class StateCarriesWindow(unittest.TestCase):
    def test_state_has_window_scene_and_application_state(self):
        text = HOST.read_text()
        self.assertIn('"window":', text)
        self.assertIn("sceneState", text)
        self.assertIn("applicationState", text)


if __name__ == "__main__":
    unittest.main()
