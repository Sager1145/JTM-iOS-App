#!/usr/bin/env python3
"""Normalize reviewed route evidence without inferring physical rail identities.

The input deliberately distinguishes source-backed line labels from N02 or rail
history feature identities.  Missing identity fields stay absent.  Medium route
facts remain useful in the timetable detail view but cannot unlock editor route
application, which requires high-confidence line segments.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
INPUT = BASE / "sources/candidates/reviewed-route-evidence-20260928.json"


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def write_jsonl(relative: str, rows: list[dict]) -> None:
    path = BASE / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows)
    path.write_text(text)


def update_seed_review_state() -> None:
    """Refine root seed status after the root normalizer has recreated it."""
    azusa_ids = (
        "jr-east.azusa.1.base.2026-09-18",
        "jr-east.azusa.1.selected-saturday-holiday.2026-09-19",
    )
    hitachi_id = "jr-east.hitachi.26.2026-09-18"
    tokiwa_id = "jr-east.tokiwa.55.main.2026-09-19"
    updates = {
        **{
            (trip_id, "operator"): (
                "The exact JR East train page and its service guide support JR East "
                "attribution; no train-specific operating contract is asserted."
            )
            for trip_id in azusa_ids
        },
        **{
            (trip_id, "route_lines"): (
                "Official sources support ten Chuo Main Line passenger-pair intervals "
                "through Shiojiri and one Shinonoi Line interval to Matsumoto. "
                "No current N02 physical line id or rail-history id is asserted."
            )
            for trip_id in azusa_ids
        },
        (hitachi_id, "operator"): (
            "Official JR East timetable and service pages support operator attribution, "
            "but branding alone is not promoted to high confidence."
        ),
        (hitachi_id, "route_lines"): (
            "Official sources support eleven Joban Line passenger-pair intervals from "
            "Iwaki through Ueno. Ueno-Tokyo-Shinagawa physical line identities remain "
            "unverified, and no N02 or rail-history feature id is asserted."
        ),
        (tokiwa_id, "operator"): (
            "Official JR East timetable and service pages support operator attribution, "
            "but branding alone is not promoted to high confidence."
        ),
        (tokiwa_id, "route_lines"): (
            "Official sources support six Joban Line passenger-pair intervals from Ueno "
            "through Katsuta. Shinagawa-Tokyo-Ueno physical line identities remain "
            "unverified, and no N02 or rail-history feature id is asserted."
        ),
    }
    seen: set[tuple[str, str]] = set()
    for completeness_path in sorted((BASE / "normalized").glob("fact-completeness*.jsonl")):
        completeness = read_jsonl(completeness_path)
        changed = False
        for row in completeness:
            key = (row["entity_id"], row["dimension"])
            if key in updates:
                row.update(status="partial", confidence="medium", notes=updates[key])
                seen.add(key)
                changed = True
        if changed:
            write_jsonl(str(completeness_path.relative_to(BASE)), completeness)
    if seen != set(updates):
        raise ValueError(f"missing completeness seeds: {sorted(set(updates) - seen)}")

    queue_notes = {
        **{
            (trip_id, "operator"): (
                "Partial JR East attribution is recorded. Obtain a train-specific "
                "operating-entity statement before raising confidence to verified/high."
            )
            for trip_id in azusa_ids
        },
        **{
            (trip_id, "route_lines"): (
                "Chuo Main through Shiojiri and Shinonoi to Matsumoto are supported "
                "as ordered line labels. Direct current N02 line or historical-overlay "
                "feature identities remain unverified."
            )
            for trip_id in azusa_ids
        },
        (hitachi_id, "operator"): (
            "Partial official JR East attribution is recorded. Obtain a train-specific "
            "operating-entity statement before raising operator confidence to verified/high."
        ),
        (hitachi_id, "route_lines"): (
            "Joban Line is supported only through Ueno. Obtain official physical line names "
            "and explicit current N02 line ids or historical-overlay ids for all intervals, "
            "especially Ueno-Tokyo-Shinagawa; never resolve them by name matching."
        ),
        (tokiwa_id, "operator"): (
            "Partial official JR East attribution is recorded. Obtain a train-specific "
            "operating-entity statement before raising operator confidence to verified/high."
        ),
        (tokiwa_id, "route_lines"): (
            "Joban Line is supported only from Ueno through Katsuta. Obtain official physical "
            "line names and explicit current N02 line ids or historical-overlay ids for all "
            "intervals, especially Shinagawa-Tokyo-Ueno; never resolve them by name matching."
        ),
        ("jr-central.shinano.1.2026-09-18", "route_lines"): (
            "Official material names the Chuo Main and Shinonoi lines but does not state the "
            "train-specific transition boundary or physical feature ids. Keep unnormalized "
            "until direct boundary and operator evidence is reviewed."
        ),
    }
    queue_seen: set[tuple[str, str]] = set()
    for queue_path in sorted((BASE / "normalized").glob("research-queue*.jsonl")):
        queue = read_jsonl(queue_path)
        changed = False
        for row in queue:
            key = (row["entity_id"], row["missing_dimension"])
            if key in queue_notes:
                row["notes"] = queue_notes[key]
                queue_seen.add(key)
                changed = True
        if changed:
            write_jsonl(str(queue_path.relative_to(BASE)), queue)
    if queue_seen != set(queue_notes):
        raise ValueError(f"missing research seeds: {sorted(set(queue_notes) - queue_seen)}")

    coverage_path = BASE / "normalized/coverage-declarations-root.jsonl"
    coverage = read_jsonl(coverage_path)
    coverage_id = "jr-east.2026.route_lines.seed"
    matching = [row for row in coverage if row["coverage_id"] == coverage_id]
    if len(matching) != 1:
        raise ValueError(f"expected one coverage seed: {coverage_id}")
    matching[0].update(
        status="partial",
        record_count=39,
        source_id="jr-east-kanto-route-map-202604",
        notes=(
            "Seventeen reviewed Joban Line passenger-pair intervals cover one Hitachi "
            "and one Tokiwa trip; twenty-two Chuo Main/Shinonoi intervals cover the "
            "two Azusa 1 variants. Hitachi/Tokiwa Ueno-Tokyo-Shinagawa intervals, "
            "explicit physical feature identities and the company-wide/full-year "
            "denominator remain unverified."
        ),
    )
    write_jsonl("normalized/coverage-declarations-root.jsonl", coverage)


def main() -> None:
    candidate = json.loads(INPUT.read_text())
    if candidate.get("schema_version") != 1:
        raise ValueError("unsupported route-evidence schema")

    trips = {
        row["trip_id"]
        for path in sorted((BASE / "normalized/trips").rglob("*.jsonl"))
        for row in read_jsonl(path)
    }
    stations = {
        row["station_id"]: row
        for path in sorted((BASE / "normalized").glob("station-identities*.jsonl"))
        for row in read_jsonl(path)
    }
    operators = {
        row["operator_id"]
        for row in read_jsonl(BASE / "normalized/operators-root.jsonl")
    }
    existing_sources: set[str] = set()
    for path in sorted((BASE / "sources").glob("source-registry*.jsonl")):
        if path.name == "source-registry-route-evidence.jsonl":
            continue
        existing_sources.update(row["source_id"] for row in read_jsonl(path))

    sources = candidate["sources"]
    source_ids = existing_sources | {row["source_id"] for row in sources}
    if len({row["source_id"] for row in sources}) != len(sources):
        raise ValueError("duplicate source_id in route-evidence candidate")

    operator_segments: list[dict] = []
    line_segments: list[dict] = []
    fact_sources: list[dict] = []

    for evidence in candidate["trip_evidence"]:
        trip_id = evidence["trip_id"]
        if trip_id not in trips:
            raise ValueError(f"unknown reviewed trip: {trip_id}")

        operator = evidence.get("operator_segment")
        if operator:
            operator_id = operator["operator_id"]
            if operator_id not in operators:
                raise ValueError(f"unknown operator: {operator_id}")
            if operator["confidence"] == "high":
                raise ValueError("branding-derived operator evidence must not be high confidence")
            operator_segments.append(
                {
                    "trip_id": trip_id,
                    "from_sequence": operator["from_sequence"],
                    "to_sequence": operator["to_sequence"],
                    "operator_id": operator_id,
                }
            )
            for source_id in operator["source_ids"]:
                if source_id not in source_ids:
                    raise ValueError(f"unknown source: {source_id}")
                fact_sources.append(
                    {
                        "entity_type": "trip",
                        "entity_id": trip_id,
                        "field_name": "operator_route_evidence",
                        "source_id": source_id,
                        "page_or_locator": operator["notes"],
                        "confidence": operator["confidence"],
                        "verification_status": operator["verification_status"],
                    }
                )

        defaults = evidence.get("line_segment_defaults")
        segments = evidence.get("line_segments", [])
        if segments and not defaults:
            raise ValueError(f"line segment defaults missing for {trip_id}")
        if defaults:
            if defaults["confidence"] == "high":
                raise ValueError("line labels without physical identity must not be high confidence")
            if defaults["operator_id"] not in operators:
                raise ValueError(f"unknown operator: {defaults['operator_id']}")
            if defaults["source_id"] not in source_ids:
                raise ValueError(f"unknown source: {defaults['source_id']}")
            for source_id in defaults["source_ids"]:
                if source_id not in source_ids:
                    raise ValueError(f"unknown source: {source_id}")

        previous_to: str | None = None
        for segment in segments:
            for key in ("from_station_id", "to_station_id"):
                station_id = segment[key]
                station = stations.get(station_id)
                if not station or station["reference_kind"] != "current_n02":
                    raise ValueError(f"unresolved current station identity: {station_id}")
            if previous_to is not None and segment["from_station_id"] != previous_to:
                raise ValueError(f"discontinuous reviewed line chain for {trip_id}")
            previous_to = segment["to_station_id"]
            # reference_kind/current_n02_line_id/rail_history_id are intentionally
            # absent. A line/operator spelling is not a physical feature identity.
            line_segments.append(
                {
                    "trip_id": trip_id,
                    "sequence": segment["sequence"],
                    "from_station_id": segment["from_station_id"],
                    "to_station_id": segment["to_station_id"],
                    "line_name": segment["line_name"],
                    "operator_id": defaults["operator_id"],
                    "source_id": defaults["source_id"],
                    "confidence": defaults["confidence"],
                }
            )
            for source_id in defaults["source_ids"]:
                fact_sources.append(
                    {
                        "entity_type": "trip",
                        "entity_id": trip_id,
                        "field_name": (
                            f"route_lines.segment.{segment['sequence']}.published_line_label"
                        ),
                        "source_id": source_id,
                        "page_or_locator": defaults["notes"],
                        "confidence": defaults["confidence"],
                        "verification_status": defaults["verification_status"],
                    }
                )

    write_jsonl("sources/source-registry-route-evidence.jsonl", sources)
    write_jsonl(
        "normalized/trip-operator-segments/route-evidence/reviewed.jsonl",
        operator_segments,
    )
    write_jsonl(
        "normalized/trip-lines/route-evidence/reviewed.jsonl",
        line_segments,
    )
    write_jsonl("normalized/fact-sources-route-evidence.jsonl", fact_sources)
    update_seed_review_state()
    print(
        f"Normalized {len(operator_segments)} partial operator segment, "
        f"{len(line_segments)} medium-confidence line segments and "
        f"{len(fact_sources)} provenance links"
    )


if __name__ == "__main__":
    main()
