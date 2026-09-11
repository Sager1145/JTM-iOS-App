#!/usr/bin/env python3
"""Fetch supplemental local rail route geometry from public Overpass API."""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from planner import NETWORK_CACHE_FILTER_VERSION

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DEFAULT_ENDPOINT = "https://overpass-api.de/api/interpreter"
# Public global mirrors listed by the OpenStreetMap Overpass API documentation.
FALLBACK_ENDPOINT = "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
SECONDARY_ENDPOINT = "https://overpass.private.coffee/api/interpreter"
_preferred_endpoint = DEFAULT_ENDPOINT
ROUTE_KINDS = "subway|light_rail|tram|monorail|train"
FILTER_VERSION = NETWORK_CACHE_FILTER_VERSION
EXCLUDED_WORDS = re.compile(r"\b(amtrak|via rail|intercity|high.?speed|tourist|scenic|museum|excursion)\b", re.I)
COMMUTER_WORDS = re.compile(
    r"\b(commuter|suburban|regional|metro.?north|long island|lirr|nj transit|metra|go transit|exo|mbta|"
    r"sounder|marc|vre|sunrail|rail runner|caltrain|bart|ace|coaster|sprinter|texrail|trinity railway|wes|"
    r"south shore|wego|frontrunner|northstar|west coast express|shore line east|ctrail|capmetro|metrolink|"
    r"union pearson|up express|réseau express métropolitain|reseau express metropolitain|rem)\b",
    re.I,
)


def build_query(bounds: list[list[float]], timeout: int = 30) -> str:
    clauses = []
    for south, west, north, east in bounds:
        clauses.append(
            f'rel["type"="route"]["route"~"^({ROUTE_KINDS})$"]'
            f"({south},{west},{north},{east});"
        )
    return f"[out:json][timeout:{timeout}];(\n" + "\n".join(clauses) + "\n);out body geom;"


def _text(tags: dict[str, Any]) -> str:
    return " ".join(str(tags.get(key, "")) for key in
                    ("name", "short_name", "operator", "network", "ref", "service", "description"))


def route_is_eligible(tags: dict[str, Any], catalog_systems: list[str]) -> bool:
    route = str(tags.get("route", "")).casefold()
    text = _text(tags)
    inactive = {"proposed", "construction", "disused", "abandoned", "razed", "demolished"}
    if (str(tags.get("state", "")).casefold() in inactive
            or str(tags.get("status", "")).casefold() in inactive
            or any(str(tags.get(key, "")).casefold() in {"yes", "true", "1"}
                   for key in inactive)):
        return False
    if EXCLUDED_WORDS.search(text):
        return False
    if route != "train":
        return route in {"subway", "light_rail", "tram", "monorail"}
    service = str(tags.get("service", "")).casefold()
    if service in {"commuter", "suburban", "regional"} or COMMUTER_WORDS.search(text):
        return True
    normalized = re.sub(r"[^a-z0-9]+", " ", text.casefold())
    for system in catalog_systems:
        tokens = [token for token in re.sub(r"[^a-z0-9]+", " ", system.casefold()).split()
                  if len(token) >= 4 and token not in {"line", "rail", "train", "metro", "transit", "express"}]
        if tokens and any(token in normalized for token in tokens):
            return True
    return False


def relation_to_line(relation: dict[str, Any], city_id: str,
                     catalog_systems: list[str]) -> dict[str, Any] | None:
    tags = relation.get("tags", {})
    if relation.get("type") != "relation" or not route_is_eligible(tags, catalog_systems):
        return None
    segments = []
    for member in relation.get("members", []):
        if member.get("type") != "way" or member.get("role") in {"platform", "stop", "station"}:
            continue
        coordinates = []
        for point in member.get("geometry", []):
            if isinstance(point, dict) and "lat" in point and "lon" in point:
                coordinates.append([point["lon"], point["lat"]])
            else:
                if len(coordinates) >= 2:
                    segments.append([0, 0, coordinates])
                coordinates = []
        if len(coordinates) >= 2:
            segments.append([0, 0, coordinates])
    if not segments:
        return None
    route = str(tags.get("route", "")).casefold()
    kind = {"light_rail": "lightrail"}.get(route, route)
    relation_id = int(relation["id"])
    return {
        "id": f"osm-route-{relation_id}",
        "name": tags.get("name") or tags.get("ref") or f"OSM route {relation_id}",
        "operator": tags.get("operator") or tags.get("network") or "OpenStreetMap route relation",
        "kind": kind,
        "segments": segments,
        "geometrySource": "OpenStreetMap Overpass route relation (ODbL)",
        "sourceRelation": relation_id,
        "sourceCity": city_id,
        "sourceTags": {key: tags[key] for key in
                       ("route", "name", "ref", "operator", "network", "service") if key in tags},
    }


def fetch_overpass(query: str, endpoint: str = DEFAULT_ENDPOINT, retries: int = 2,
                   request_timeout: int = 45) -> dict[str, Any]:
    global _preferred_endpoint
    body = urllib.parse.urlencode({"data": query}).encode()
    last_error: Exception | None = None
    candidates = (list(dict.fromkeys([_preferred_endpoint,FALLBACK_ENDPOINT,DEFAULT_ENDPOINT,SECONDARY_ENDPOINT]))
                  if endpoint == DEFAULT_ENDPOINT else [endpoint])
    for attempt in range(retries + 1):
        current_endpoint=candidates[min(attempt,len(candidates)-1)]
        request = urllib.request.Request(current_endpoint, data=body,
                                         headers={"User-Agent": "JTM-Apple-Maps-coverage-audit/1.0"})
        try:
            with urllib.request.urlopen(request, timeout=request_timeout) as response:
                payload = json.loads(response.read().decode("utf-8"))
                if payload.get("remark"):
                    raise ValueError(f"Overpass returned an incomplete result: {payload['remark']}")
                payload["_fetchEndpoint"] = current_endpoint
                if endpoint == DEFAULT_ENDPOINT:
                    _preferred_endpoint = current_endpoint
                return payload
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError) as error:
            last_error = error
            if attempt < retries:
                time.sleep(30 if isinstance(error, urllib.error.HTTPError) and error.code in (429,406) else 2 ** attempt)
    raise RuntimeError(f"Overpass request failed after {retries + 1} attempts: {last_error}")


def fetch_city(city_id: str, entry: dict[str, Any], output: Path, endpoint: str,
               force: bool = False) -> dict[str, Any]:
    query = build_query(entry.get("bounds", []))
    if output.exists() and not force:
        cached = json.loads(output.read_text(encoding="utf-8"))
        if (cached.get("query") == query and cached.get("catalogSystems") == entry.get("systems", [])
                and cached.get("filterVersion") == FILTER_VERSION and cached.get("lines")):
            return cached
    payload = fetch_overpass(query, endpoint=endpoint)
    lines = []
    seen = set()
    for relation in payload.get("elements", []):
        line = relation_to_line(relation, city_id, entry.get("systems", []))
        if line and line["id"] not in seen:
            seen.add(line["id"]); lines.append(line)
    result = {
        "format": "compact-v1-supplement",
        "city": city_id,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "crs": "EPSG:4326",
        "source": payload.get("_fetchEndpoint",endpoint),
        "sourceLicense": "OpenStreetMap ODbL 1.0",
        "filterVersion": FILTER_VERSION,
        "query": query,
        "catalogSystems": entry.get("systems", []),
        "lines": sorted(lines, key=lambda line: line["id"]),
    }
    if not lines:
        raise RuntimeError(f"Overpass returned no eligible rail route relations for {city_id}")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(output)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--extents", type=Path, default=HERE / "network-extents.json")
    parser.add_argument("--out", type=Path, default=REPO / "outputs/apple-maps-rail/network-cache")
    parser.add_argument("--cities", help="comma-separated city ids; default is every extent city")
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--delay", type=float, default=1.0)
    args = parser.parse_args()
    catalog = json.loads((HERE / "cities.json").read_text(encoding="utf-8"))["cities"]
    entries = {city["id"]: {"bounds": city.get("bounds", []), "systems": city.get("systems", [])}
               for city in catalog}
    extents = json.loads(args.extents.read_text(encoding="utf-8"))["cities"] if args.extents.exists() else {}
    for city_id, extent in extents.items():
        entry = entries.setdefault(city_id, {"bounds": [], "systems": []})
        entry["bounds"] = entry["bounds"] + [bounds for bounds in extent.get("bounds", [])
                                               if bounds not in entry["bounds"]]
        entry["systems"] = entry["systems"] + [system for system in extent.get("systems", [])
                                                 if system not in entry["systems"]]
    city_ids = args.cities.split(",") if args.cities else list(entries)
    unknown = [city_id for city_id in city_ids if city_id not in entries]
    if unknown:
        parser.error(f"unknown extent cities: {', '.join(unknown)}")
    summary = {}
    failures = {}
    for index, city_id in enumerate(city_ids):
        print(f"[{index + 1}/{len(city_ids)}] {city_id}", flush=True)
        cache_path=args.out / f"{city_id}.json"
        previous_mtime=cache_path.stat().st_mtime_ns if cache_path.exists() else None
        try:
            result = fetch_city(city_id, entries[city_id], args.out / f"{city_id}.json",
                                args.endpoint, args.force)
            summary[city_id] = len(result.get("lines", []))
        except Exception as error:
            failures[city_id] = str(error)
            print(f"  failed: {error}", flush=True)
        used_network = city_id in failures or previous_mtime is None or cache_path.stat().st_mtime_ns != previous_mtime
        if used_network and index + 1 < len(city_ids) and args.delay:
            time.sleep(args.delay)
    result = {"cities_requested": len(city_ids), "cities_succeeded": len(summary),
              "line_counts": summary, "failures": failures, "output": str(args.out)}
    args.out.mkdir(parents=True, exist_ok=True)
    summary_path = args.out / "fetch-summary.json"
    temporary = summary_path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(summary_path)
    print(json.dumps(result, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
