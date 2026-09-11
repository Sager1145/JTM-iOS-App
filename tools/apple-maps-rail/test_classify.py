import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw


MODULE_PATH = Path(__file__).with_name("classify.py")
SPEC = importlib.util.spec_from_file_location("apple_maps_rail_classify", MODULE_PATH)
assert SPEC and SPEC.loader
classify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(classify)


def dark_map(size=(360, 220)):
    image = Image.new("RGB", size, "#111c2a")
    draw = ImageDraw.Draw(image)
    for y in range(18, size[1], 35):
        draw.line((0, y, size[0], y + 25), fill="#29374a", width=5)
    for x in range(25, size[0], 70):
        draw.line((x, 0, x + 22, size[1]), fill="#273548", width=4)
    return image


def save_rail(path, color="#ffb51c"):
    image = dark_map()
    draw = ImageDraw.Draw(image)
    points = [(8, 195), (75, 150), (150, 132), (235, 74), (354, 28)]
    draw.line(points, fill=color, width=6, joint="curve")
    for x, y in (points[1], points[2], points[3]):
        draw.ellipse((x - 6, y - 6, x + 6, y + 6), fill="#f6f8fb", outline=color, width=3)
    image.save(path)


class ClassifierTests(unittest.TestCase):
    def test_long_thin_transit_stroke_is_rail(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "rail.png"
            save_rail(path)
            result = classify.classify_image(path)
        self.assertEqual("rail", result["label"], result)
        self.assertGreaterEqual(result["confidence"], 0.58)
        self.assertTrue(result["line_candidates"])
        self.assertGreater(result["line_candidates"][0]["span_ratio"], 0.7)

    def test_fullscreen_one_pixel_low_contrast_transit_stroke_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fullscreen-rail.png"
            image = Image.new("RGB", (2559, 1332), "#111c2a")
            draw = ImageDraw.Draw(image)
            # Representative of the narrow blue line in the native Calgary
            # capture.  Resizing to 1400 pixels erased or fragmented this stroke.
            draw.line(
                [(2200, 80), (2200, 620), (2050, 900)],
                fill="#4a64a2",
                width=1,
            )
            image.save(path)
            result = classify.classify_image(path)

        self.assertEqual("rail", result["label"], result)
        self.assertEqual([2559, 1332], result["analyzed_size"])
        self.assertLessEqual(result["line_candidates"][0]["thickness"], 1.1)

    def test_unmatched_station_catalog_does_not_penalize_pixel_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "rail.png"
            save_rail(path)
            pixels_only = classify.classify_image(path)
            unmatched_catalog = classify.classify_image(
                path,
                {
                    "ax_descriptions": ["Unrelated map business"],
                    "known_rail_stations": ["Station absent from this local dataset"],
                },
            )

        self.assertEqual("rail", unmatched_catalog["label"], unmatched_catalog)
        self.assertEqual(
            pixels_only["rail_likelihood"],
            unmatched_catalog["rail_likelihood"],
        )

    def test_fragmented_curved_transit_stroke_is_combined(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fragmented-curve.png"
            image = Image.new("RGB", (800, 600), "#111c2a")
            draw = ImageDraw.Draw(image)
            color = "#466ab6"
            draw.line([(90, 510), (150, 460), (190, 390)], fill=color, width=2)
            draw.line([(197, 383), (255, 320), (335, 315)], fill=color, width=2)
            draw.line([(343, 316), (420, 345), (510, 285)], fill=color, width=2)
            image.save(path)
            result = classify.classify_image(path)

        self.assertEqual("rail", result["label"], result)
        self.assertIsNotNone(result["fragmented_stroke"])
        self.assertGreaterEqual(result["fragmented_stroke"]["component_count"], 2)

    def test_sparse_rail_stroke_clipping_capture_edge_is_rail(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "edge-rail.png"
            image = Image.new("RGB", (1800, 1000), "#111c2a")
            draw = ImageDraw.Draw(image)
            draw.line(
                [(1200, 100), (1300, 140), (1400, 210)],
                fill="#60589c",
                width=3,
                joint="curve",
            )
            image.save(path)
            result = classify.classify_image(path)

        self.assertEqual("rail", result["label"], result)
        self.assertTrue(result["needs_review"])
        self.assertLess(result["line_candidates"][0]["fill_ratio"], 0.03)

    def test_park_and_label_blobs_are_not_rail(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "park.png"
            image = dark_map()
            draw = ImageDraw.Draw(image)
            draw.rectangle((25, 42, 205, 150), fill="#075f4c")
            # Bright label-like glyphs are saturated, but remain short components.
            for x, width in ((232, 9), (246, 13), (264, 8), (278, 14)):
                draw.rectangle((x, 91, x + width, 101), fill="#69ae5b")
            image.save(path)
            result = classify.classify_image(path)
        self.assertEqual("no_rail", result["label"], result)
        self.assertGreater(result["confidence"], 0.7)
        self.assertTrue(result["needs_review"])

    def test_numbered_bus_evidence_overrides_green_line_and_requests_review(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "green-route.png"
            save_rail(path, color="#36d56c")
            result = classify.classify_image(
                path,
                {
                    "visible_text": ["925 Don Mills Express"],
                    "route_names": ["925 Don Mills Express"],
                    "excluded_route_names": ["925 Don Mills Express"],
                },
            )
        self.assertEqual("no_rail", result["label"], result)
        self.assertTrue(result["needs_review"])
        self.assertTrue(any("excluded route" in reason for reason in result["reasons"]))

    def test_matching_visible_station_name_strengthens_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "station.png"
            save_rail(path)
            result = classify.classify_image(
                path,
                {
                    "visible_text": ["Summerhill"],
                    "rail_station_names": ["Summerhill", "Rosedale"],
                },
            )
        self.assertEqual("rail", result["label"], result)
        self.assertTrue(any("rail station" in reason for reason in result["reasons"]))

    def test_station_names_do_not_use_unconstrained_substring_matches(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "station.png"
            save_rail(path)
            result = classify.classify_image(
                path,
                {
                    "ax_descriptions": ["Yorkville Village, Shopping"],
                    "known_rail_stations": ["York"],
                },
            )
        self.assertFalse(any("rail station" in reason for reason in result["reasons"]))

    def test_incidental_bus_stop_does_not_veto_visible_rail(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "mixed-transit.png"
            save_rail(path)
            result = classify.classify_image(
                path,
                {"ax_descriptions": ["Nearby bus stop"]},
            )
        self.assertEqual("rail", result["label"], result)
        self.assertTrue(result["needs_review"])

    def test_invalid_image_raises_decode_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "broken.png"
            path.write_bytes(b"not an image")
            with self.assertRaisesRegex(ValueError, "cannot decode image"):
                classify.classify_image(path)

    def test_sorter_avoids_overwrite_and_leaves_failed_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            rail = directory / "capture.png"
            empty = directory / "empty.png"
            broken = directory / "broken.png"
            save_rail(rail)
            Image.fromarray(np.full((180, 320, 3), 25, dtype=np.uint8)).save(empty)
            broken.write_bytes(b"not an image")
            existing_directory = directory / "rail"
            existing_directory.mkdir()
            (existing_directory / rail.name).write_bytes(b"existing")

            counts = classify.sort_directory(directory)

            self.assertEqual({"rail": 1, "no_rail": 1, "failed": 1}, counts)
            self.assertEqual(b"existing", (existing_directory / rail.name).read_bytes())
            self.assertTrue((existing_directory / "capture-1.png").is_file())
            self.assertTrue((directory / "no_rail" / "empty.png").is_file())
            self.assertTrue(broken.is_file())
            records = [
                json.loads(line)
                for line in (directory / "classification-audit.jsonl").read_text().splitlines()
            ]
            self.assertEqual(3, len(records))
            self.assertEqual("error", next(r for r in records if r["input"].endswith("broken.png"))["status"])


if __name__ == "__main__":
    unittest.main()
