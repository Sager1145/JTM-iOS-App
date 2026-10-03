#!/usr/bin/env python3
"""Build the seven-region English catalog without treating attribution as verification."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
REGIONS = ("jp", "tw", "hk", "mo", "kr", "us", "ca")
VERIFIED_STATUSES = {"official_verified", "multiple_official_names"}


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolve_reading(readings, line_id, code):
    # A physical transfer group can have different names on different lines.
    # Never overwrite a line's identified station with a group/name fallback.
    by_code = readings.get("byCode", {})
    for key in (f"{line_id}:{code}", code):
        row = by_code.get(key)
        if row and row.get("en", "").strip():
            return row["en"].strip(), key
    return None, None


def build_region(region, package, readings, jp_catalog=None, overrides=None, feeds=None, member_overrides=None):
    grouped = {}
    for line in package["lines"]:
        for seq, station in enumerate(line["stations"]):
            code, name = station[:2]
            english, reading_key = resolve_reading(readings, line["id"], code)
            source = f"data/station-readings{'-' + region if region != 'jp' else ''}.json"
            status = "official_dataset_candidate" if english else "missing"
            evidence = []
            if region == "jp":
                row = jp_catalog["byCode"][code]
                if row["ja"] != name:
                    raise ValueError(f"stale Japanese identity: {code}")
                english, source, status = row["en"], row["source"], row["status"]
                evidence = [entry for entry in row.get("identityEvidence", [])
                            if entry.get("operator") == line["operator"]]
                if status == "official_verified":
                    verified_evidence = [entry for entry in evidence if not entry.get("reviewNote")]
                    if verified_evidence:
                        selected_evidence = verified_evidence[0]
                        english = selected_evidence["en"].split("<", 1)[0].split("(", 1)[0].split("[", 1)[0].strip()
                        source = selected_evidence["source"]
                    else:
                        # A reviewed spelling for one operator does not prove
                        # another operator's label at a shared station group.
                        status = "official_spelling_candidate"
            elif not english and len(station) > 4 and station[4]:
                english = station[4]
                status = "package_unverified"
                source = f"public/rail/{region}-2025.json:nameRoma"
            override = (overrides or {}).get(code)
            if override:
                if name not in override.get("names", [override["name"]]):
                    raise ValueError(f"stale official identity: {region}:{code} {name}")
                if not override.get("en", "").strip() or not override.get("source", "").startswith("https://"):
                    raise ValueError(f"invalid official evidence: {region}:{code}")
                english, source = override["en"], override["source"]
                status = "official_verified"
                evidence = override.get("identityEvidence", [override])
            member_key = f"{line['id']}:{code}"
            member_override = (member_overrides or {}).get(member_key)
            if member_override:
                if (member_override["lineId"] != line["id"] or
                        member_override["stationCode"] != code or
                        member_override["operator"] != line["operator"] or
                        member_override["country"].lower() != region or
                        name not in member_override.get("names", [member_override["name"]])):
                    raise ValueError(f"stale verified line identity: {region}:{member_key}")
                if (not member_override.get("en", "").strip() or
                        not member_override.get("source", "").startswith(("https://", "http://")) or
                        not member_override.get("identityEvidence")):
                    raise ValueError(f"missing verified line evidence: {region}:{member_key}")
                english, source = member_override["en"], member_override["source"]
                status = "official_verified"
                evidence = member_override["identityEvidence"]
            member = {"lineId": line["id"], "seq": seq, "operator": line["operator"],
                      "name": name, "en": english, "status": status,
                      "translationMayBeWrong": status != "official_verified",
                      "source": source, "readingKey": reading_key}
            if evidence:
                member["identityEvidence"] = evidence
            if line.get("sourceFeed"):
                feed = (feeds or {}).get(line["sourceFeed"], {})
                member["datasetEvidence"] = {"feed": line["sourceFeed"],
                    "url": feed.get("url"), "field": "stops.txt:stop_name",
                    "note": "Retained builder output; original stop label and identity require source verification."}
            grouped.setdefault(code, []).append(member)
    result = {}
    unknown_overrides = set(overrides or {}) - set(grouped)
    if unknown_overrides:
        raise ValueError(f"official source contains unknown groups: {region}:{sorted(unknown_overrides)}")
    known_memberships = {f"{row['lineId']}:{code}" for code, rows in grouped.items() for row in rows}
    if set(member_overrides or {}) - known_memberships:
        raise ValueError(f"verified source contains unknown memberships: {region}")
    for code, members in sorted(grouped.items()):
        names = sorted({row["name"] for row in members})
        variants = sorted({row["en"] for row in members if row["en"]})
        counts = Counter(row["en"] for row in members if row["en"])
        english = counts.most_common(1)[0][0] if counts else None
        selected = next((row for row in members if row["en"] == english), members[0])
        # Group verification requires every membership to agree; the original
        # per-line labels and evidence remain independently queryable.
        status = selected["status"]
        if any(row["en"] is None for row in members):
            status = "missing"
        elif len(variants) > 1:
            status = "multiple_official_names" if all(row["status"] == "official_verified" for row in members) else "identity_review"
        elif status == "official_verified" and any(row["status"] != "official_verified" for row in members):
            status = "official_dataset_candidate"
        result[code] = {"name": Counter(row["name"] for row in members).most_common(1)[0][0],
                        "nameVariants": names, "en": english, "enVariants": variants,
                        "status": status, "translationMayBeWrong": status not in VERIFIED_STATUSES,
                        "source": selected["source"], "memberships": members}
        if selected.get("identityEvidence"):
            result[code]["identityEvidence"] = selected["identityEvidence"]
    return {"country": region.upper(), "packageVersion": package["version"], "byCode": result}


def build(app=APP):
    inputs = {}
    def tracked(relative):
        path = app / relative
        inputs[relative] = digest(path)
        return read(path)
    jp = tracked("data/station-english-jp.json")
    for filename in ("jp-station-english-official.json", "jp-station-english-toei-source.json",
                     "jp-station-english-metro-source.json", "jp-station-english-jre-source.json",
                     "jp-station-english-kyushu-source.json", "jp-station-english-manual.json"):
        tracked(f"data/{filename}")
    registry = tracked("scripts/railway/na-feeds.json")
    feeds = {row["slug"]: row for row in registry["feeds"]}
    overrides = {region: {} for region in REGIONS}
    member_overrides = {region: {} for region in REGIONS}
    review_reasons = {}
    for suffix in ("na", "tw", "tw-afr", "kr", "jp", "jp-private", "jp-east", "jp-west", "jp-nankai", "jp-private-extra", "jp-shikoku", "jp-fukuoka", "next-official", "kr-second-pass"):
        relative = f"data/station-english-verified-{suffix}.json"
        if not (app / relative).exists():
            continue
        snapshot = tracked(relative)
        if snapshot["schema"] != "station-english-evidence/1":
            raise ValueError(f"invalid official verification schema: {relative}")
        for key, row in snapshot["byLineStation"].items():
            region = row["country"].lower()
            if region not in member_overrides or key in member_overrides[region]:
                raise ValueError(f"invalid/duplicate official verification identity: {region}:{key}")
            member_overrides[region][key] = row
        for row in snapshot.get("unresolved", []):
            region = row.get("country", snapshot["countries"][0]).lower()
            code = row.get("group", row.get("stationCode"))
            if code and row.get("lineId"):
                review_reasons[(region, row["lineId"], code)] = row.get("reason", "Official identity needs review")
    # Reviewed snapshots are optional during development, never inferred from
    # the package's romaSource=3 marker.
    snapshot_path = app / "data/hk-mo-station-english-official.json"
    if snapshot_path.exists():
        snapshot = tracked("data/hk-mo-station-english-official.json")
        for region in ("hk", "mo"):
            overrides[region].update(snapshot["byCountry"][region]["byCode"])
    afr_path = app / "data/tw-station-english-afr-source.json"
    if afr_path.exists():
        snapshot = tracked("data/tw-station-english-afr-source.json")
        overrides["tw"].update({row["stationGroupCode"]: {
            **row, "names": sorted({row["name"], row["zh_Hant"], *row.get("identityAliases", [])})
        } for row in snapshot["byCode"].values()})
    by_country = {}
    for region in REGIONS:
        package = tracked(f"public/rail/{region}-2025.json")
        readings = tracked(f"data/station-readings{'-' + region if region != 'jp' else ''}.json")
        if region == "jp" and jp["packageVersion"] != package["version"]:
            raise ValueError("Japan English catalog is stale")
        by_country[region] = build_region(region, package, readings, jp, overrides[region], feeds, member_overrides[region])
    catalog = {"schema": "station-english/1", "note":
        "All shipped station groups and line memberships. official_verified and multiple_official_names have reviewed station-specific official evidence for every membership. Multiple official names retain the operator-specific spellings. Dataset attribution and English coverage alone do not prove official correctness.",
        "inputSha256": inputs, "byCountry": by_country}
    report = {"schema": "station-english-coverage/1", "regions": {}, "unresolved": [], "unresolvedMemberships": []}
    for region, country in by_country.items():
        rows = country["byCode"]
        stats = {"stations": len(rows), "withEnglish": sum(bool(row["en"]) for row in rows.values()),
                 "statuses": dict(sorted(Counter(row["status"] for row in rows.values()).items())),
                 "lineMemberships": sum(len(row["memberships"]) for row in rows.values()),
                 "officialVerifiedGroups": sum(row["status"] in VERIFIED_STATUSES for row in rows.values()),
                 "officialVerifiedMemberships": sum(m["status"] == "official_verified" for row in rows.values() for m in row["memberships"]),
                 "operatorCoverage": {}}
        report["regions"][region] = stats
        for code, row in rows.items():
            if row["status"] not in VERIFIED_STATUSES:
                report["unresolved"].append({"country": region.upper(), "code": code,
                    "name": row["name"], "en": row["en"], "status": row["status"],
                    "source": row["source"]})
            by_operator = defaultdict(list)
            for member in row["memberships"]:
                by_operator[member["operator"]].append(member)
                if member["status"] != "official_verified":
                    report["unresolvedMemberships"].append({"country": region.upper(), "code": code,
                        **{key: member[key] for key in ("lineId", "seq", "operator", "name", "en", "status", "source")},
                        "reason": review_reasons.get((region, member["lineId"], code),
                            "No reviewed operator-specific official English identity for this membership")})
            for operator, memberships in by_operator.items():
                coverage = stats["operatorCoverage"].setdefault(operator, {"stationGroups": 0,
                    "fullyVerifiedStationGroups": 0, "lineMemberships": 0, "verifiedLineMemberships": 0})
                coverage["stationGroups"] += 1
                coverage["fullyVerifiedStationGroups"] += all(m["status"] == "official_verified" for m in memberships)
                coverage["lineMemberships"] += len(memberships)
                coverage["verifiedLineMemberships"] += sum(m["status"] == "official_verified" for m in memberships)
    report["allStationsHaveEnglish"] = all(s["withEnglish"] == s["stations"] for s in report["regions"].values())
    report["allStationsOfficialVerified"] = not report["unresolved"]
    return catalog, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check exact freshness and all region coverage")
    parser.add_argument("--require-english", action="store_true", help="fail if any station membership lacks English")
    parser.add_argument("--require-official", action="store_true", help="fail until every station has official evidence")
    args = parser.parse_args()
    catalog, report = build()
    for filename, data in (("station-english.json", catalog), ("station-english-coverage.json", report)):
        path = APP / "data" / filename
        text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                raise ValueError(f"{filename} is stale; rebuild it")
        else:
            path.write_text(text, encoding="utf-8")
    for region, stats in report["regions"].items():
        print(f"{region}: {stats['withEnglish']}/{stats['stations']} English; {stats['statuses']}")
    if args.require_english and any(row["status"] == "missing" for row in report["unresolved"]):
        raise SystemExit("INCOMPLETE: station memberships without English remain")
    if args.require_official and not report["allStationsOfficialVerified"]:
        raise SystemExit(f"INCOMPLETE: {len(report['unresolved'])} station groups still require official verification")


if __name__ == "__main__":
    main()
