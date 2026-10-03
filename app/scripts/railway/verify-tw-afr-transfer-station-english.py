#!/usr/bin/env python3
"""Verify AFR's membership at shared Chiayi separately from TRA's evidence."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re

APP = Path(__file__).resolve().parents[2]
RAW = APP / "data/station-english-sources/tw-afr"
OUTPUT = APP / "data/station-english-verified-tw-afr.json"


def build(package, raw, manifest):
    for language, value in raw.items():
        if hashlib.sha256(value).hexdigest() != manifest[language]["sha256"]:
            raise ValueError("AFR Chiayi source hash mismatch")
    en = raw["en"].decode("utf-8")
    zh = raw["zh"].decode("utf-8")
    label = lambda text: [html.unescape(re.sub(r"<[^>]+>", "", s)).strip()
        for s in re.findall(r'<span\s+aria-current="page"[^>]*>(.*?)</span>', text, re.S)]
    if label(en) != ["Chiayi Station"] or label(zh) != ["嘉義車站"]:
        raise ValueError("AFR Chiayi bilingual page identity changed")
    if 'action="/En/0000081"' not in en or 'action="/0000081"' not in zh:
        raise ValueError("AFR bilingual station page IDs disagree")
    rows = [(line, station) for line in package["lines"] for station in line["stations"]
        if line["id"] == "tw-alsr-alishan" and station[0] == "tw-official-tra-4080"]
    if len(rows) != 1:
        raise ValueError("AFR Chiayi package membership changed")
    line, station = rows[0]
    if station[1] != "嘉義" or line["operator"] != "阿里山林業鐵路及文化資產管理處":
        raise ValueError("AFR Chiayi package identity changed")
    proof = {"operator": line["operator"], "officialStationId": "0000081", "name": "嘉義車站",
        "en": "Chiayi Station", "source": manifest["en"]["url"], "identitySource": manifest["zh"]["url"],
        "sha256": manifest["en"]["sha256"], "identitySha256": manifest["zh"]["sha256"],
        "retrievedAt": manifest["en"]["retrievedAt"],
        "matchMethod": "same bilingual operator station page ID; explicit AFR line/group/native identity",
        "transformation": "Remove generic Station/車站 suffix; preserve proper name",
        "mappingNote": "Operator page explicitly describes its north first-platform boarding site in the shared TRA station"}
    key = line["id"] + ":" + station[0]
    return {"schema": "station-english-evidence/1", "countries": ["tw"], "sources": manifest,
        "byLineStation": {key: {"country": "tw", "lineId": line["id"], "stationCode": station[0],
            "operator": line["operator"], "name": station[1], "en": "Chiayi",
            "source": proof["source"], "identityEvidence": [proof]}}, "unresolved": []}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    manifest = json.loads((RAW / "manifest.json").read_text())
    raw = {language: (RAW / item["filename"]).read_bytes() for language, item in manifest.items()}
    result = build(json.loads((APP / "public/rail/tw-2025.json").read_text()), raw, manifest)
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if OUTPUT.read_text() != encoded:
            raise SystemExit("AFR shared station evidence needs regeneration")
    else:
        OUTPUT.write_text(encoded)
    print("AFR Chiayi shared-station membership verified")


if __name__ == "__main__":
    main()
