#!/usr/bin/env python3
"""Verify Hokkaido/Osaka/JR Central names from operator-owned bilingual station identities."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import re
import urllib.request

APP = Path(__file__).resolve().parents[2]
SOURCES = APP / "data/station-english-sources/jp"
OUTPUT = APP / "data/station-english-verified-jp.json"
URLS = {
    "hokkaido": "https://www3.jrhokkaido.co.jp/webunkou/json/master/eki_master.json",
    "osaka-ja": "https://subway.osakametro.co.jp/station_guide/",
    "osaka-en": "https://subway.osakametro.co.jp/en/station_guide/",
    "central-ja": "https://traininfo.jr-central.co.jp/zairaisen/data/hp_eki_master_ja.json",
    "central-en": "https://traininfo.jr-central.co.jp/zairaisen/data/hp_eki_master_en.json",
}
FILES = {"hokkaido": "hokkaido-master.json", "osaka-ja": "osaka-ja.html", "osaka-en": "osaka-en.html",
    "central-ja": "central-ja.json", "central-en": "central-en.json"}
OSAKA_LINES = {"御堂筋線": "M", "谷町線": "T", "四つ橋線": "Y", "中央線": "C",
    "千日前線": "S", "堺筋線": "K", "長堀鶴見緑地線": "N", "今里筋線": "I", "南港ポートタウン線": "P"}
OSAKA_ALIASES = {"難波": "なんば", "我孫子": "あびこ", "中百舌鳥": "なかもず",
                 "四天王寺前夕陽ヶ丘": "四天王寺前夕陽ケ丘"}
CENTRAL_ALIASES = {"三ヶ根": "三ケ根", "五十鈴ヶ丘": "五十鈴ケ丘", "梅ヶ谷": "梅ケ谷",
    "醒ヶ井": "醒ケ井", "関ヶ原": "関ケ原", "駒ヶ根": "駒ケ根"}
HOKKAIDO_ALIASES = {"駒ヶ岳": "駒ケ岳", "千代ヶ岡": "千代ケ岡",
                    "細岡": "（臨）細岡", "原生花園": "（臨）原生花園"}


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def extract_osaka(text):
    rows = {}
    anchors = re.findall(r'<a\b[^>]*class="cs-stationLink"[^>]*href="([^"]+)"[^>]*>(.*?)</a>', text, re.S)
    for href, label in anchors:
        match = re.search(r"([A-Z]/[a-z]\d+)/index.php", href)
        if not match:
            continue
        station_id = match[1]
        name = html.unescape(re.sub(r"<[^>]+>", "", label)).strip()
        if station_id in rows and rows[station_id] != name:
            raise ValueError(f"conflicting official Osaka station ID: {station_id}")
        rows[station_id] = name
    if not rows:
        raise ValueError("Osaka official index has no station links")
    return rows


def build(package, raw, manifest):
    for key, filename in FILES.items():
        if hashlib.sha256(raw[key]).hexdigest() != manifest[key]["sha256"]:
            raise ValueError(f"source hash mismatch: {filename}")
    hokkaido = json.loads(raw["hokkaido"])
    counts = Counter(row["ja"] for row in hokkaido)
    hokkaido_by_name = {row["ja"]: row for row in hokkaido if counts[row["ja"]] == 1}
    ja = extract_osaka(raw["osaka-ja"].decode("utf-8"))
    en = extract_osaka(raw["osaka-en"].decode("utf-8"))
    if set(ja) != set(en):
        raise ValueError("Osaka bilingual station IDs disagree")
    central_ja = json.loads(raw["central-ja"])["lst"]
    central_en = json.loads(raw["central-en"])["lst"]
    central_key = lambda row: (row["ryokakuSenkuCd"], row["ryokakuEkiCd"])
    central_en_by_id = {central_key(row): row for row in central_en}
    if len(central_en_by_id) != len(central_en) or len({central_key(row) for row in central_ja}) != len(central_ja):
        raise ValueError("duplicate official JR Central line/station identity")
    if set(central_en_by_id) != {central_key(row) for row in central_ja}:
        raise ValueError("JR Central bilingual station IDs disagree")
    by_line_station, unresolved = {}, []
    for line in package["lines"]:
        operator = line["operator"]
        if operator not in ("北海道旅客鉄道", "Osaka Metro", "東海旅客鉄道"):
            continue
        for station in line["stations"]:
            code, name = station[:2]
            if operator == "北海道旅客鉄道":
                source_name = HOKKAIDO_ALIASES.get(name, name)
                row = hokkaido_by_name.get(source_name)
                if not row or not row.get("en"):
                    unresolved.append({"lineId": line["id"], "stationCode": code, "name": name,
                        "reason": "No unique official bilingual master identity"})
                    continue
                english = row["en"].removeprefix("(Special)")
                proof = {"operator": operator, "officialStationId": row["key"], "name": row["ja"],
                    "en": row["en"], "source": URLS["hokkaido"], "identitySource": URLS["hokkaido"],
                    "stationNumber": row.get("kigo", "") + row.get("no", ""),
                    "sha256": manifest["hokkaido"]["sha256"], "retrievedAt": manifest["hokkaido"]["retrievedAt"],
                    "matchMethod": "unique operator-scoped Japanese identity in bilingual master",
                    "transformation": "Remove exact (Special) seasonal-service marker from station label" if row["en"].startswith("(Special)") else "none"}
            elif operator == "東海旅客鉄道":
                source_name = CENTRAL_ALIASES.get(name, name)
                # Kbn=1 and 5 are the publisher's own conventional lines, as used
                # by its station-search UI; external connection/express rows are excluded.
                allowed_lines = {line["name"]}
                if line["name"] == "東海道線":
                    allowed_lines.add("美濃赤坂線")
                candidates = [row for row in central_ja if row["ekiMei"] == source_name
                    and row["ryokakuSenkuMei"] in allowed_lines and row["ryokakuSenkuKbn"] in ("1", "5")]
                identities = {(row["ryokakuEkiCd"], central_en_by_id[central_key(row)]["ekiMei"]) for row in candidates}
                if len(identities) != 1:
                    unresolved.append({"lineId": line["id"], "stationCode": code, "name": name,
                        "reason": "No unique official own-line bilingual master identity; Shinkansen evidence is handled by the legacy JR Central station-map source"})
                    continue
                row = sorted(candidates, key=central_key)[0]
                translated = central_en_by_id[central_key(row)]
                english = translated["ekiMei"]
                if not english.strip() or any(a in english for a in "<>"):
                    raise ValueError("invalid JR Central published English station label")
                proof = {"operator": operator, "officialStationId": row["ryokakuEkiCd"],
                    "officialLineIds": sorted({r["ryokakuSenkuCd"] for r in candidates}),
                    "officialLine": row["ryokakuSenkuMei"], "name": row["ekiMei"], "en": english,
                    "source": URLS["central-en"], "identitySource": URLS["central-ja"],
                    "sha256": manifest["central-en"]["sha256"], "identitySha256": manifest["central-ja"]["sha256"],
                    "retrievedAt": manifest["central-en"]["retrievedAt"],
                    "matchMethod": "operator + own conventional line + exact native identity; paired official line/station IDs"}
            else:
                letters = [letter for part, letter in OSAKA_LINES.items() if part in line["name"]]
                if len(letters) != 1:
                    raise ValueError(f"unknown official Osaka line: {line['name']}")
                source_name = OSAKA_ALIASES.get(name, name)
                ids = [key for key, value in ja.items() if value == source_name and key.startswith(letters[0] + "/")]
                if len(ids) != 1:
                    unresolved.append({"lineId": line["id"], "stationCode": code, "name": name,
                        "reason": "No unique official native identity on matching Osaka line"})
                    continue
                station_id = ids[0]
                english = en[station_id]
                proof = {"operator": operator, "officialStationId": station_id,
                    "officialLine": letters[0], "name": ja[station_id], "en": english,
                    "source": URLS["osaka-en"], "identitySource": URLS["osaka-ja"],
                    "retrievedAt": manifest["osaka-en"]["retrievedAt"],
                    "sha256": manifest["osaka-en"]["sha256"], "identitySha256": manifest["osaka-ja"]["sha256"],
                    "matchMethod": "same station page ID on official Japanese/English indexes; operator + line + native label"}
            if source_name != name:
                proof["packageName"] = name
                proof["mappingNote"] = "Explicit reviewed native spelling/kana/service-marker variant; never joined by romanization"
            key = f"{line['id']}:{code}"
            by_line_station[key] = {"country": "jp", "lineId": line["id"], "stationCode": code,
                "operator": operator, "name": name, "en": english, "source": proof["source"], "identityEvidence": [proof]}
    return {"schema": "station-english-evidence/1", "countries": ["jp"], "sources": manifest,
        "packageVersion": package["version"], "byLineStation": dict(sorted(by_line_station.items())),
        "unresolved": unresolved,
        "note": "Official published name evidence for this package inventory; not a claim every retained master station is currently operating. Other Japanese operators remain in the unified review ledger."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="refresh public raw source snapshots")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.fetch:
        SOURCES.mkdir(parents=True, exist_ok=True)
        manifest = {}
        for key, url in URLS.items():
            raw = urllib.request.urlopen(url, timeout=45).read()
            (SOURCES / FILES[key]).write_bytes(raw)
            manifest[key] = {"url": url, "filename": FILES[key],
                "sha256": hashlib.sha256(raw).hexdigest(), "retrievedAt": datetime.now(timezone.utc).isoformat()}
        (SOURCES / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    manifest = read(SOURCES / "manifest.json")
    raw = {key: (SOURCES / filename).read_bytes() for key, filename in FILES.items()}
    result = build(read(APP / "public/rail/jp-2025.json"), raw, manifest)
    text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if OUTPUT.read_text(encoding="utf-8") != text:
            raise ValueError("Japanese official verification is stale")
    else:
        OUTPUT.write_text(text, encoding="utf-8")
    print(f"JP source verification: {len(result['byLineStation'])} memberships, {len(result['unresolved'])} unresolved")


if __name__ == "__main__":
    main()
