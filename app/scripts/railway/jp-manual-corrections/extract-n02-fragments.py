#!/usr/bin/env python3
"""Extract a small N02-25 fragment file (sections + station rows) for the JP
manual-corrections batch B topology ops. Read-only on the Japan-Train-Map
source repo; writes n02-fragments.json next to this script.

Usage:
  python3 extract-n02-fragments.py [--japan-train-map PATH]
"""
import argparse
import json
import os

SOURCE_NOTE = "国土交通省 国土数値情報 鉄道データ N02-25 (基準 2025-12-31)"

# key -> operator, line, bbox (lon_min, lon_max, lat_min, lat_max) or None for "whole line"
SECTION_SPECS = [
    ("広島電鉄", "本線", (132.465, 132.480, 34.384, 34.400)),
    ("広島電鉄", "皆実線", (132.465, 132.480, 34.384, 34.400)),
    ("東武鉄道", "伊勢崎線", (139.800, 139.830, 35.700, 35.725)),
    ("三岐鉄道", "三岐線", (136.625, 136.660, 34.998, 35.030)),
    ("三岐鉄道", "近鉄連絡線", (136.625, 136.660, 34.998, 35.030)),
    ("富山地方鉄道", "富山駅南北接続線", (137.205, 137.222, 36.694, 36.706)),
    ("富山地方鉄道", "支線", (137.205, 137.222, 36.694, 36.706)),
    ("富山地方鉄道", "本線", (137.205, 137.222, 36.694, 36.706)),
    ("富山地方鉄道", "富山港線", (137.205, 137.222, 36.694, 36.706)),
    ("神戸新交通", "ポートアイランド線", None),
    ("東京都", "12号線大江戸線", (139.685, 139.705, 35.683, 35.695)),
]

STATION_SPECS = [
    ("広島電鉄", "的場町"),
    ("広島電鉄", "段原一丁目"),
    ("広島電鉄", "稲荷町"),
    ("広島電鉄", "比治山下"),
    ("東武鉄道", "押上"),
    ("東武鉄道", "曳舟"),
    ("三岐鉄道", "近鉄富田"),
    ("三岐鉄道", "大矢知"),
    ("富山地方鉄道", "富山駅"),
    ("富山地方鉄道", "電鉄富山駅・エスタ前"),
    ("神戸新交通", "中公園"),
    ("神戸新交通", "みなとじま"),
    ("神戸新交通", "市民広場"),
    ("東京都", "新宿"),
    ("東京都", "都庁前"),
]


def in_bbox(pt, bbox):
    lon, lat = pt[0], pt[1]
    lon_min, lon_max, lat_min, lat_max = bbox
    return lon_min <= lon <= lon_max and lat_min <= lat <= lat_max


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--japan-train-map",
        default="/Users/sager/Documents/GitHub/Japan-Train-Map",
        help="path to the Japan-Train-Map checkout",
    )
    args = parser.parse_args()

    base = args.japan_train_map
    sections_path = os.path.join(base, "app", "data", "rail-sections.json")
    stations_path = os.path.join(base, "app", "data", "stations.json")

    with open(sections_path, "r", encoding="utf-8") as f:
        sections_data = json.load(f)
    with open(stations_path, "r", encoding="utf-8") as f:
        stations_data = json.load(f)

    section_key_by_pair = {(op, line): (op, line, bbox) for op, line, bbox in SECTION_SPECS}
    sections_out = {}
    for feat in sections_data["features"]:
        p = feat["properties"]
        pair = (p.get("N02_004"), p.get("N02_003"))
        if pair not in section_key_by_pair:
            continue
        op, line, bbox = section_key_by_pair[pair]
        coords = feat["geometry"]["coordinates"]
        if bbox is not None:
            if not any(in_bbox(pt, bbox) for pt in coords):
                continue
        key = f"{op}|{line}"
        sections_out.setdefault(key, []).append(coords)

    station_pairs = set(STATION_SPECS)
    stations_out = []
    for feat in stations_data["features"]:
        p = feat["properties"]
        pair = (p.get("N02_004"), p.get("N02_005"))
        if pair not in station_pairs:
            continue
        stations_out.append(
            {
                "operator": p.get("N02_004"),
                "line": p.get("N02_003"),
                "name": p.get("N02_005"),
                "code": p.get("N02_005c"),
                "group": p.get("N02_005g"),
                "display_point": p.get("display_point"),
            }
        )

    out = {
        "source": SOURCE_NOTE,
        "sections": sections_out,
        "stations": stations_out,
    }

    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "n02-fragments.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    size = os.path.getsize(out_path)
    n_sections = sum(len(v) for v in sections_out.values())
    print(f"wrote {out_path} ({size} bytes, {len(sections_out)} keys, {n_sections} section polylines, {len(stations_out)} station rows)")


if __name__ == "__main__":
    main()
