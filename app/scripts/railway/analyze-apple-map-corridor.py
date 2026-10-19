#!/usr/bin/env python3
"""Build reviewable railway candidates from a flat Apple Maps screenshot.

Usage: python analyze-apple-map-corridor.py input.json --output report-directory
Input: image (relative to input.json), bounds {west,east,north,south},
corridor_wgs84 [[lon,lat],...], optional station_wgs84 and masks in image pixels.
Requires NumPy and Pillow. This artifact builder never edits railway source data.
"""
import argparse
import base64
import html
import json
from pathlib import Path

from lib.apple_map_corridor import analyze_corridor, wgs84_to_pixel


def build_report(manifest_path, output):
    manifest_path = Path(manifest_path)
    spec = json.loads(manifest_path.read_text())
    image = manifest_path.parent / spec.pop("image")
    result = analyze_corridor(image, **spec)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    (output / "analysis.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    features = []
    # Split unsupported stretches: a gap in the evidence is not a measured rail.
    segment = []
    for row in result["trace"] + [{"supported": False}]:
        if row["supported"]:
            segment.append(row["coordinate"])
        else:
            if len(segment) > 1:
                features.append({"type": "Feature", "properties": {"role": "railway_candidate"},
                                 "geometry": {"type": "LineString", "coordinates": segment}})
            segment = []
    platform = result["platform"]
    if platform.get("coordinate"):
        features.append({"type": "Feature", "properties": {"role": "platform_footprint_candidate", **platform},
                         "geometry": {"type": "Point", "coordinates": platform["coordinate"]}})
    alignment = result.get("station_alignment", {})
    if alignment.get("coordinate"):
        features.append({"type": "Feature", "properties": {"role": "station_transverse_alignment", **alignment},
                         "geometry": {"type": "Point", "coordinates": alignment["coordinate"]}})
    (output / "candidates.geojson").write_text(json.dumps({"type": "FeatureCollection", "features": features}, indent=2))
    from PIL import Image
    width, height = Image.open(image).size
    points = " ".join(f'{row["pixel"][0]:.2f},{row["pixel"][1]:.2f}' for row in result["trace"])
    dots = "".join(f'<circle cx="{r["pixel"][0]}" cy="{r["pixel"][1]}" r="2" fill="{"#00ffb7" if r["supported"] else "#ffab40"}"/>' for r in result["trace"])
    seed = spec.get("station_wgs84")
    seed_svg = ""
    if seed:
        x, y = wgs84_to_pixel(seed, spec["bounds"], (width, height))
        seed_svg = f'<circle cx="{x}" cy="{y}" r="8" fill="none" stroke="#ff5e85" stroke-width="2"/>'
    platform_svg = ""
    if platform.get("bounds_pixels"):
        polygon = " ".join(f'{x},{y}' for x, y in platform["bounds_pixels"])
        platform_svg = f'<polygon points="{polygon}" fill="#f1dd4933" stroke="#f1dd49" stroke-width="2"/>'
    if alignment.get("pixel"):
        x, y = alignment["pixel"]
        platform_svg += f'<circle cx="{x}" cy="{y}" r="5" fill="#ffffff" stroke="#00a99d" stroke-width="2"/>'
    data = base64.b64encode(image.read_bytes()).decode()
    summary = html.escape(json.dumps({k: v for k, v in result.items() if k != "trace"}, ensure_ascii=False, indent=2))
    document = f'''<!doctype html><meta charset="utf-8"><title>Apple Maps 走廊候选</title>
<style>body{{background:#161b22;color:#e6edf3;font:15px system-ui;margin:20px}}svg{{max-width:100%;height:auto}}pre{{white-space:pre-wrap}}label{{margin-right:24px}}</style>
<h1>Apple Maps 铁路与站点候选</h1><p>绿色：有图像支持的轴线；橙色：缺少支持；粉色圆：输入站点；白点：横向对齐候选；黄色：可辨认的平台轮廓。白点保留原站点的纵向位置，不代表平台中心。铁路符号间距不代表真实轨距。</p>
<label><input type="checkbox" checked onchange="document.getElementById('trace').style.display=this.checked?'':'none'">铁路候选</label>
<label><input type="checkbox" checked onchange="document.getElementById('seed').style.display=this.checked?'':'none'">原站点</label>
<label><input type="checkbox" checked onchange="document.getElementById('platform').style.display=this.checked?'':'none'">站点/站台候选</label>
<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg"><image width="{width}" height="{height}" href="data:image/png;base64,{data}"/>
<g id="trace"><polyline points="{points}" fill="none" stroke="#00ffb7" stroke-width="1" stroke-dasharray="3 3"/>{dots}</g><g id="seed">{seed_svg}</g><g id="platform">{platform_svg}</g></svg><pre>{summary}</pre>'''
    (output / "review.html").write_text(document)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = build_report(args.input, args.output)
    print(json.dumps({k: v for k, v in result.items() if k != "trace"}, ensure_ascii=False))
