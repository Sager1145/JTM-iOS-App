#!/usr/bin/env python3
"""Build an auditable English-name catalog for every shipped JP station group.

The compact package uses group codes; station-readings.json uses platform codes.
Keep the two namespaces separate rather than copying group IDs into byCode.
"""
import json
import hashlib
import re
import sys
import unicodedata
from datetime import datetime, timezone
from pathlib import Path


APP = Path(__file__).resolve().parents[2]
DATA = APP / "data"
PACKAGE = APP / "public/rail/jp-2025.json"
OUTPUT = DATA / "station-english-jp.json"
KYUSHU_SOURCE = "https://www.jrkyushu.co.jp/english/pdf/howtosearch_tips.pdf"
KYUSHU_TIMETABLE = "https://www.jrkyushu.co.jp/english/pdf/timetable_20260314_20270228.pdf"


def extract_kyushu_station_rows(pages):
    """Extract the published multilingual table, without joining romanizations.

    `pages` contains (one-based PDF page number, pypdf plain extracted text).
    English has artificial letter spacing in some PDF cells. Preserve the
    three genuine multiword names while removing those extraction spaces.
    The first table section is other companies' Shinkansen: exclude it from
    the operator-owned evidence rather than asserting JR Kyushu ownership.
    """
    rows = {}
    in_kyushu = False
    for page, text in pages:
        for line in text.splitlines():
            match = re.match(r"^([A-Z][A-Z -]+)\s*[가-힣]", line)
            if not match:
                continue
            english = re.sub(r"\s+", "", match[1])
            if english == "MOJIKO":
                in_kyushu = True
            if not in_kyushu:
                continue
            english = {"SPACEWORLD": "SPACE WORLD", "HUISTENBOSCH": "HUIS TEN BOSCH",
                       "OMURARAILYARD": "OMURA RAIL YARD"}.get(english, english)
            japanese = line.split()[-1]
            if not re.fullmatch(r"[^\x00-\x7f]+", japanese):
                raise ValueError(f"unexpected Japanese table cell on page {page}: {line}")
            row = rows.setdefault(japanese, {"ja": japanese, "en": english.title(),
                                            "publishedEn": english, "pages": []})
            if row["publishedEn"] != english:
                raise ValueError(f"conflicting JR Kyushu table rows: {japanese}")
            if page not in row["pages"]:
                row["pages"].append(page)
    return rows


def import_kyushu_pdf(path):
    # Optional import dependency only; ordinary catalog generation uses the
    # committed snapshot and remains standard-library-only/offline.
    from pypdf import PdfReader
    rows = extract_kyushu_station_rows(
        [(number, page.extract_text()) for number, page in enumerate(PdfReader(path).pages, 1)
         if number > 1])
    if len(rows) != 569:
        raise ValueError(f"JR Kyushu table extraction changed: {len(rows)} unique rows; review before importing")
    # Two exact bilingual rows were checked on page 5 of the current timetable.
    # It corrects the older SIN-OMURA typo and supplies renamed 江北; never map
    # the older 肥前山口 label to 江北 by inferred transliteration.
    superseded = rows["新大村"]
    rows["新大村"] = {"ja": "新大村", "en": "Shin-Ōmura", "publishedEn": "Shin-Ōmura",
                       "pages": [5], "source": KYUSHU_TIMETABLE,
                       "note": "Current bilingual timetable corrects the older station-list SIN-OMURA typo.",
                       "supersededEvidence": {**superseded, "source": KYUSHU_SOURCE}}
    rows["江北"] = {"ja": "江北", "en": "Kōhoku", "publishedEn": "Kōhoku",
                    "pages": [5], "source": KYUSHU_TIMETABLE,
                    "note": "Current bilingual timetable uses 江北; old 肥前山口 row remains unmatched."}
    snapshot = {
        "source": KYUSHU_SOURCE, "publisher": "Kyushu Railway Company",
        "operator": "九州旅客鉄道", "retrievedAt": datetime.now(timezone.utc).date().isoformat(),
        "sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest(),
        "description": "English and Japanese columns of the operator's multilingual station table; exact operator/Japanese-name identity joins only. Stale and misspelled Japanese rows remain in the review ledger.",
        "extraction": "pypdf plain text; English cell before Korean text; final cell is Japanese. Remove PDF letter-spacing, preserve known multiword cells, title-case display names. Duplicate route rows collapse only if both language cells agree.",
        "rebuild": "python3 app/scripts/railway/build-jp-station-english.py --import-jr-kyushu /path/to/howtosearch_tips.pdf (requires pypdf); then run builder without arguments. Two curated bilingual timetable rows retain their page/source evidence.",
        "licenseNote": "No bulk reuse license identified; short station-name facts only, with attribution.",
        "supplement": {"source": KYUSHU_TIMETABLE, "validFrom": "2026-03-14", "validUntil": "2027-02-28", "extraction": "Two bilingual station cells on PDF page 5, checked against the published PDF; not decoded through the timetable's broken embedded text font."},
        "byJapaneseName": dict(sorted(rows.items())),
    }
    destination = DATA / "jp-station-english-kyushu-source.json"
    destination.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{destination}: {len(rows)} bilingual identities")


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def name_key(value):
    # Match romanized labels only when their letters are identical after
    # macrons, case, spaces and punctuation are removed. This is deliberately
    # stricter than a fuzzy station-name match.
    ascii_name = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]", "", ascii_name.lower())


def build():
    package = read(PACKAGE)
    official = read(DATA / "jp-station-english-official.json")
    toei = read(DATA / "jp-station-english-toei-source.json")
    metro = read(DATA / "jp-station-english-metro-source.json")
    jr_east = read(DATA / "jp-station-english-jre-source.json")
    manual = read(DATA / "jp-station-english-manual.json")
    if (len(official["byCode"]) != 34 or len(toei["byNumber"]) != 106 or
            len(metro["names"]) != 144 or len(set(metro["names"])) != 144 or
            len(jr_east["names"]) != 131 or len(set(jr_east["names"])) != 131 or
            len(metro["byStationId"]) != 144 or len(jr_east["byEnglishName"]) != 131):
        raise ValueError("official source snapshot changed; review its extraction")
    stations = {}
    toei_codes_by_name = {}
    metro_codes_by_roma = {}
    jr_east_codes_by_roma = {}
    codes_by_operator_name = {}
    for line in package["lines"]:
        for code, name, _lon, _lat, roma, *_ in line["stations"]:
            previous = stations.setdefault(code, (name, roma or ""))
            if previous != (name, roma or ""):
                raise ValueError(f"conflicting station group {code}: {previous} / {(name, roma)}")
            codes_by_operator_name.setdefault((line["operator"], name), set()).add(code)
            if line["operator"] == "東京都":
                toei_codes_by_name.setdefault(name, set()).add(code)
            if line["operator"] == "東京メトロ" and roma:
                metro_codes_by_roma.setdefault(name_key(roma), set()).add(code)
            if line["operator"] == "東日本旅客鉄道" and roma:
                jr_east_codes_by_roma.setdefault(name_key(roma), set()).add(code)

    verified_by_code = {
        code: (row["ja"], row["en"], official["source"], "official_verified")
        for code, row in official["byCode"].items()
    }
    evidence_by_code = {
        code: [{"operator": "東海旅客鉄道", "ja": row["ja"], "en": row["en"],
                "source": official["source"],
                "identitySource": row.get("identitySource", official["source"]),
                "mapping": "reviewed group code override", "retrievedAt": official["retrievedAt"]}]
        for code, row in official["byCode"].items()
    }
    for station_number, row in toei["byNumber"].items():
        candidates = toei_codes_by_name.get(row["ja"], set())
        if len(candidates) != 1:
            raise ValueError(f"Toei station {station_number} has {len(candidates)} package matches")
        code = next(iter(candidates))
        existing = verified_by_code.get(code)
        # The site appends [Tokyo Metropolitan Government] to E28 as a place
        # hint; the station name itself is Tochomae.
        english_name = row["en"].split("[", 1)[0].strip()
        candidate = (row["ja"], english_name, toei["source"], "official_verified")
        if existing and (existing[0] != candidate[0] or name_key(existing[1]) != name_key(candidate[1])):
            raise ValueError(f"conflicting official spellings for {code}: {existing} / {candidate}")
        verified_by_code.setdefault(code, candidate)
        evidence_by_code.setdefault(code, []).append({
            "operator": "東京都", "stationNumber": station_number,
            "ja": row["ja"], "en": row["en"], "source": toei["source"],
            "japaneseSource": toei["japaneseSource"], "identitySource": toei["japaneseSource"],
            "retrievedAt": toei["retrievedAt"],
        })
    identity_review = []
    for operator, snapshot, records in [
        ("東京メトロ", metro, metro["byStationId"]),
        ("東日本旅客鉄道", jr_east, jr_east["byEnglishName"]),
    ]:
        for source_id, row in records.items():
            package_name = row.get("packageJa", row["ja"])
            english_name = row["en"].split("<", 1)[0].split("(", 1)[0].strip()
            candidates = codes_by_operator_name.get((operator, package_name), set())
            if len(candidates) != 1 or row.get("reviewNote"):
                identity_review.append({
                    "operator": operator, "sourceId": source_id,
                    "stationId": row.get("stationId", source_id),
                    "ja": row["ja"], "en": english_name,
                    "packageCodes": sorted(candidates),
                    "reason": row.get("reviewNote") or "Non-unique operator/Japanese-name mapping",
                })
                if len(candidates) != 1:
                    continue
            code = next(iter(candidates))
            source = row.get("source") or f"https://www.tokyometro.jp/lang_en/station/{source_id}/index.html"
            identity_source = row.get("identitySource") or f"https://www.tokyometro.jp/station/{source_id}/index.html"
            candidate = (package_name, english_name, source,
                         "official_spelling_candidate" if row.get("reviewNote") else "official_verified")
            existing = verified_by_code.get(code)
            if existing and (existing[0] != candidate[0] or name_key(existing[1]) != name_key(candidate[1])):
                raise ValueError(f"conflicting official spellings for {code}: {existing} / {candidate}")
            verified_by_code.setdefault(code, candidate)
            evidence_by_code.setdefault(code, []).append({
                "operator": operator,
                "stationId": row.get("stationId", source_id),
                "ja": row["ja"], "en": row["en"],
                "source": source, "identitySource": identity_source,
                "retrievedAt": snapshot["retrievedAt"],
                **({"numbers": row["numbers"]} if "numbers" in row else {}),
                **({"mappingNote": row["mappingNote"]} if "mappingNote" in row else {}),
                **({"note": row["note"]} if "note" in row else {}),
                **({"reviewNote": row["reviewNote"]} if "reviewNote" in row else {}),
            })
    metro_matched = 0
    for display_name in metro["names"]:
        # Angle-bracketed phrases are landmarks, not part of the name. Their
        # published spelling is excluded if the core name cannot match exactly.
        english_name = display_name.split("<", 1)[0].strip()
        candidates = metro_codes_by_roma.get(name_key(english_name), set())
        if len(candidates) != 1:
            continue
        code = next(iter(candidates))
        candidate = (stations[code][0], english_name, metro["source"],
                     "official_spelling_candidate")
        existing = verified_by_code.get(code)
        if existing and (existing[0] != candidate[0] or name_key(existing[1]) != name_key(candidate[1])):
            raise ValueError(f"conflicting official spellings for {code}: {existing} / {candidate}")
        verified_by_code.setdefault(code, candidate)
        metro_matched += 1
    if metro_matched < 130:
        raise ValueError(f"Tokyo Metro official matching regressed: {metro_matched}")
    jr_east_matched = 0
    for display_name in jr_east["names"]:
        # Parentheses identify airport terminal aliases on the page.
        english_name = display_name.split("(", 1)[0].strip()
        candidates = jr_east_codes_by_roma.get(name_key(english_name), set())
        if len(candidates) != 1:
            continue
        code = next(iter(candidates))
        candidate = (stations[code][0], english_name, jr_east["source"],
                     "official_spelling_candidate")
        existing = verified_by_code.get(code)
        if existing and (existing[0] != candidate[0] or name_key(existing[1]) != name_key(candidate[1])):
            raise ValueError(f"conflicting official spellings for {code}: {existing} / {candidate}")
        verified_by_code.setdefault(code, candidate)
        jr_east_matched += 1
    if jr_east_matched < 90:
        raise ValueError(f"JR East official matching regressed: {jr_east_matched}")

    kyushu = read(DATA / "jp-station-english-kyushu-source.json")
    if len(kyushu["byJapaneseName"]) != 570:
        raise ValueError("JR Kyushu source snapshot changed; review its extraction")
    for source_id, row in kyushu["byJapaneseName"].items():
        candidates = codes_by_operator_name.get((kyushu["operator"], row["ja"]), set())
        source = row.get("source", kyushu["source"])
        if len(candidates) != 1:
            identity_review.append({
                "operator": kyushu["operator"], "sourceId": source_id,
                "stationId": source_id, "ja": row["ja"], "en": row["en"],
                "packageCodes": sorted(candidates), "source": source,
                "pages": row["pages"],
                "reason": "No exact current operator/Japanese-name match (source may be stale or contain a typo)"
                if not candidates else "Non-unique operator/Japanese-name mapping",
            })
            continue
        code = next(iter(candidates))
        candidate = (row["ja"], row["en"], source, "official_verified")
        existing = verified_by_code.get(code)
        if existing and (existing[0] != candidate[0] or name_key(existing[1]) != name_key(candidate[1])):
            raise ValueError(f"conflicting official spellings for {code}: {existing} / {candidate}")
        verified_by_code.setdefault(code, candidate)
        evidence_by_code.setdefault(code, []).append({
            "stationId": source_id, "operator": kyushu["operator"],
            "ja": row["ja"], "en": row["publishedEn"],
            "source": source, "identitySource": source, "pages": row["pages"],
            "retrievedAt": kyushu["retrievedAt"],
            **({"note": row["note"]} if "note" in row else {}),
            **({"supersededEvidence": row["supersededEvidence"]} if "supersededEvidence" in row else {}),
        })

    unknown_official = set(verified_by_code) - set(stations)
    unknown_manual = set(manual["byCode"]) - set(stations)
    # The manual list covers missing package romanizations. Official bilingual
    # evidence may now resolve such a group; the verified record takes priority.
    if unknown_official or unknown_manual:
        raise ValueError(f"unknown codes: {unknown_official}, {unknown_manual}")
    missing_package_names = {code for code, (_name, roma) in stations.items() if not roma}
    if set(manual["byCode"]) != missing_package_names:
        raise ValueError("manual candidate list must cover exactly the stations without package nameRoma")

    result = {}
    for code, (name, roma) in sorted(stations.items()):
        if code in verified_by_code:
            verified_ja, english, source, status = verified_by_code[code]
            if verified_ja != name:
                raise ValueError(f"official name override has a stale station: {code}")
        elif roma:
            english = roma
            status = "community_unverified"
            source = "public/rail/jp-2025.json:nameRoma (OSM-derived)"
        else:
            candidate = manual["byCode"].get(code)
            if candidate and candidate["ja"] != name:
                raise ValueError(f"manual name override has a stale station: {code}")
            english = candidate["en"] if candidate else None
            status = "manual_unverified"
            source = "data/jp-station-english-manual.json"
        if not english or not english.strip():
            raise ValueError(f"no English candidate for {code} {name}")
        if status == "manual_unverified" and roma:
            raise ValueError(f"manual translation shadows package nameRoma: {code}")
        result[code] = {
            "ja": name,
            "en": english,
            "status": status,
            "translationMayBeWrong": status != "official_verified",
            "source": source,
        }
        if code in evidence_by_code:
            result[code]["identityEvidence"] = evidence_by_code[code]

    from collections import Counter
    operator_coverage = {}
    for operator in sorted({line["operator"] for line in package["lines"]}):
        codes = {code for (owner, _name), members in codes_by_operator_name.items()
                 if owner == operator for code in members}
        counts = Counter(result[code]["status"] for code in codes)
        operator_coverage[operator] = {"stationGroups": len(codes),
                                       "officialVerified": counts["official_verified"],
                                       "unresolved": len(codes) - counts["official_verified"]}
    catalog = {
        "schema": "station-english-jp/1",
        "packageVersion": package["version"],
        "note": "Keyed by compact-package station GROUP code. Unverified names are provisional; translation or romanization may be wrong. English names alone do not prove an official operator translation.",
        "byCode": result,
        "identityReview": identity_review,
        "coverage": {"stationGroups": len(result), "statusCounts": dict(Counter(row["status"] for row in result.values())),
                     "operatorCoverage": operator_coverage},
    }
    output = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
    if "--check" in sys.argv[1:]:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != output:
            raise ValueError("station-english-jp.json is stale; rebuild it")
    elif len(sys.argv) == 1:
        OUTPUT.write_text(output, encoding="utf-8")
    else:
        raise ValueError("usage: build-jp-station-english.py [--check]")
    print(f"{OUTPUT}: {len(result)} stations; {dict(Counter(row['status'] for row in result.values()))}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--import-jr-kyushu":
        import_kyushu_pdf(Path(sys.argv[2]))
    else:
        build()
