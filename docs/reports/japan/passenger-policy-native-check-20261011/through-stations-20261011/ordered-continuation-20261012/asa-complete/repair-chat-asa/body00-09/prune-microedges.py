"""Remove three incidental regular supports from the saved interval-2 candidate."""
import importlib.util
import json
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("body_fit", HERE / "body-fit.py")
body = importlib.util.module_from_spec(spec)
spec.loader.exec_module(body)

REMOVED = {
    10: [133.67213195658672, 33.5702534745816],
    39: [133.67840691598815, 33.56594908344261],
    98: [133.6945143337333, 33.562700127487446],
}
AFFECTED_VIEWS = (0, 1, 2, 3, 4, 6, 7, 8)


def render(row, view_index, label):
    view_path = body.views(2)[view_index]
    view = json.loads(view_path.read_text())
    im = Image.open(view_path.parent / "basemap.png").convert("RGB")
    draw = ImageDraw.Draw(im)
    points = [tuple(body.xy(q, view)) for q in row["coordinates"]]
    draw.line(points, fill=(220, 15, 75), width=2)
    original_labels = ([8, 9, 10, 11] if view_index < 3 else
                       [38, 39, 40, 41] if view_index < 5 else
                       [96, 97, 98, 99])
    for original_index in original_labels:
        if label == "final" and original_index in REMOVED:
            continue
        index = (original_index if label == "before" else
                 original_index - sum(removed < original_index for removed in REMOVED))
        if index < len(points):
            x, y = points[index]
            if 0 <= x < 1024 and 0 <= y < 768:
                draw.ellipse((x - 3, y - 3, x + 3, y + 3), outline=(160, 0, 50))
                draw.text((x + 5, y + 4), str(original_index), fill=(160, 0, 50))
    im.save(HERE / f"microedge-{label}-v{view_path.parent.name}.png")


def main():
    path = HERE / "body-candidates.json"
    data = json.loads((HERE / "pre-microedge-candidates.json").read_text())
    row = data["intervals"][2]
    assert row["intervalIndex"] == 2
    assert len(row["coordinates"]) == len(row["controls"]) == 114
    for index, coordinate in REMOVED.items():
        assert row["coordinates"][index] == coordinate
        assert row["controls"][index]["status"] == "identified-rail-band-candidate"
    for index in AFFECTED_VIEWS:
        render(row, index, "before")
    for index in sorted(REMOVED, reverse=True):
        del row["coordinates"][index]
        del row["controls"][index]
    row["microedgeCleanup"] = {
        "removedOriginalIndices": [10, 39, 98],
        "reason": "Regular samples coincide with retained source-corner supports on the same own paired rail; no railway bend is removed.",
        "sourceCompleteCoordinatesPreserved": True,
    }
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    for index in AFFECTED_VIEWS:
        render(row, index, "final")


if __name__ == "__main__":
    main()
