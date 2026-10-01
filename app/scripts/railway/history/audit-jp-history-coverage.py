#!/usr/bin/env python3
"""Report coverage of the canonical Japan rail-history event ledger.

This audit compares the curated inputs in ``jp-rail-history-events.json`` with
the generated ``rail-history.json`` overlay.  An optional official-source
inventory may add an independent list of expected historical events.

The default mode is diagnostic and prints every gap without turning accepted
legacy gaps into a permanently red CI check.  ``--baseline-max-unresolved`` is
the structural CI gate: generated artefacts must still trace to canonical
events, every canonical event must emit something, and the declared legacy-gap
count may not grow.  ``--strict`` is the full-coverage milestone gate and fails
for any unresolved, unknown, orphaned, or unmatched record.

This script checks data compilation and availability only.  It does not run a
route solve and does not prove that either client displays the resulting path.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any, Iterable


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from temporal_source import validate as validate_source_event


ROOT = Path(__file__).resolve().parents[4]
DEFAULT_EVENTS = ROOT / "app/scripts/railway/jp-rail-history-events.json"
DEFAULT_HISTORY = ROOT / "app/data/rail-history.json"
ALLOWED_KINDS = {
    "opening",
    "closure",
    "relocation",
    "station_opening",
    "station_closure",
    "suspension",
    "resumption",
    "operator_transfer",
    "line_rename",
    "operator_rename",
    "identity_split",
    "identity_merge",
    "station_rename",
    "station_relocation",
}
IDENTITY_KINDS = {
    "line_rename",
    "operator_rename",
    "operator_transfer",
    "identity_split",
    "identity_merge",
    "station_rename",
    "station_relocation",
}
UNRESOLVED_STATUSES = {
    "unresolved",
    "unknown",
    "pending",
    "needs_review",
    "incomplete",
    "reviewed_source_only",
}
RESOLVED_STATUSES = {"matched", "resolved", "verified", "covered", "reviewed_seed"}


@dataclasses.dataclass
class Finding:
    code: str
    status: str
    message: str
    record_id: str | None = None

    def as_dict(self) -> dict[str, Any]:
        result = dataclasses.asdict(self)
        return {key: value for key, value in result.items() if value is not None}


def _read_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def _date(value: Any, label: str, findings: list[Finding], record_id: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        findings.append(Finding("INVALID_DATE", "ERROR", f"{label} is not a YYYY-MM-DD string", record_id))
        return None
    try:
        parsed = dt.date.fromisoformat(value)
    except ValueError:
        findings.append(Finding("INVALID_DATE", "ERROR", f"{label} is not a real Gregorian date", record_id))
        return None
    if parsed.isoformat() != value:
        findings.append(Finding("INVALID_DATE", "ERROR", f"{label} is not zero-padded YYYY-MM-DD", record_id))
        return None
    return value


def service_bounds(record: dict[str, Any], label: str, findings: list[Finding], record_id: str) -> tuple[str | None, str | None]:
    """Mirror app/public/app-rail-history.js railServiceBounds."""
    if "service_validity" in record:
        value = record.get("service_validity")
    elif record.get("valid_from") is None and record.get("valid_to") is None and "infrastructure_validity" in record:
        value = record.get("infrastructure_validity")
    else:
        value = [record.get("valid_from"), record.get("valid_to")]
    if not isinstance(value, list) or len(value) != 2:
        findings.append(Finding("INVALID_INTERVAL", "ERROR", f"{label} must be a [from, to] pair", record_id))
        return None, None
    start = _date(value[0], f"{label}[0]", findings, record_id)
    end = _date(value[1], f"{label}[1]", findings, record_id)
    if start and end and start >= end:
        findings.append(Finding("INVALID_INTERVAL", "ERROR", f"{label} start must precede end", record_id))
    if start is None and end is None:
        findings.append(Finding("MISSING_INTERVAL", "ERROR", f"{label} has no effective boundary", record_id))
    return start, end


def canonical_periods(
    event: dict[str, Any], findings: list[Finding], event_id: str
) -> list[tuple[str | None, str | None]]:
    """Return solver service periods, excluding a distinct legal/infra date."""
    partition = event.get("service_partition")
    if isinstance(partition, dict):
        raw = []
        for group in ("lower", "upper"):
            value = partition.get(f"{group}_periods")
            if not isinstance(value, list) or not value:
                findings.append(Finding("INVALID_PARTITION", "ERROR", f"service_partition.{group}_periods must be non-empty", event_id))
                continue
            raw.extend(value)
    else:
        raw = event.get("service_periods")
    if raw is None and (event.get("kind") or "closure") in IDENTITY_KINDS:
        transition = _date(event.get("date"), "canonical identity transition", findings, event_id)
        if transition is None:
            return []
        historical = event.get("geometry", {}).get("historical_periods")
        raw = ([period.get("service_period") for period in historical]
               if isinstance(historical, list) else [[event.get("valid_from"), transition]])
        raw = raw + [[transition, None]]
    if raw is None:
        return [service_bounds(event, "canonical service interval", findings, event_id)]
    if not isinstance(raw, list) or not raw:
        findings.append(Finding("INVALID_INTERVAL", "ERROR", "service_periods must be a non-empty array", event_id))
        return []
    result: list[tuple[str | None, str | None]] = []
    for index, pair in enumerate(raw):
        if not isinstance(pair, list) or len(pair) != 2:
            findings.append(Finding("INVALID_INTERVAL", "ERROR", f"service_periods[{index}] must be [from, to]", event_id))
            continue
        result.append(
            (
                _date(pair[0], f"service_periods[{index}][0]", findings, event_id),
                _date(pair[1], f"service_periods[{index}][1]", findings, event_id),
            )
        )
        if result[-1] == (None, None) or (result[-1][0] and result[-1][1] and result[-1][0] >= result[-1][1]):
            findings.append(Finding("INVALID_INTERVAL", "ERROR", f"service_periods[{index}] is empty", event_id))
    # The shared first period appears in both partition halves. Preserve order
    # while returning each distinct source interval once for boundary coverage.
    return list(dict.fromkeys(result))


def canonical_identity(event: dict[str, Any]) -> tuple[str | None, str | None]:
    identity = event.get("after") if isinstance(event.get("after"), dict) else event
    return identity.get("line"), identity.get("operator")


def owned_by(generated_id: str | None, canonical_id: str) -> bool:
    return generated_id == canonical_id or bool(
        generated_id and generated_id.startswith(canonical_id + ".")
    )


def _history_id(feature: dict[str, Any], category: str) -> str | None:
    if category == "retirements":
        value = feature.get("history_id")
    else:
        value = feature.get("properties", {}).get("history_id")
    return value if isinstance(value, str) and value else None


def _properties(record: dict[str, Any], category: str) -> dict[str, Any]:
    return record if category == "retirements" else record.get("properties", {})


def _identity(record: dict[str, Any], category: str) -> tuple[str | None, str | None]:
    properties = _properties(record, category)
    if category == "retirements":
        properties = record.get("match", {})
    return (
        properties.get("N02_003") or properties.get("line_name") or properties.get("line"),
        properties.get("N02_004") or properties.get("operator"),
    )


def _relocation_retirement_id(event_id: str) -> str:
    return event_id.replace(".old-", ".new-")


def _official_rows(path: Path) -> list[dict[str, Any]]:
    """Read the source agent's JSON or JSONL event inventory.

    Supported envelopes are deliberately small and explicit: a top-level list,
    or an object with ``rows``/``events``/``records``/``items``. A directory is
    an inventory scan and therefore accepts only ``rows`` envelopes; compiler
    promotion files use ``events`` and must not inflate the official inventory.
    """
    files = sorted(path.glob("*.json*")) if path.is_dir() else [path]
    rows: list[dict[str, Any]] = []
    seen_source_rows: set[str] = set()
    for item in files:
        if item.suffix == ".jsonl":
            with item.open(encoding="utf-8") as handle:
                values = [json.loads(line) for line in handle if line.strip()]
        else:
            value = _read_json(item)
            if isinstance(value, list):
                values = value
            elif isinstance(value, dict):
                keys = ("rows",) if path.is_dir() else ("rows", "events", "records", "items")
                values = next(
                    (value[key] for key in keys if isinstance(value.get(key), list)),
                    [],
                )
            else:
                values = []
        for row in values:
            if not isinstance(row, dict):
                continue
            # Promotion files repeat reviewed MLIT rows as compiler-ready
            # events. Count the official inventory row once: the raw inventory
            # uses source_row_id and its promoted event uses official_event_id.
            source_row = row.get("source_row_id") or row.get("official_event_id")
            if isinstance(source_row, str) and source_row:
                if source_row in seen_source_rows:
                    continue
                seen_source_rows.add(source_row)
            rows.append(row)
    return rows


def _official_id(row: dict[str, Any]) -> str | None:
    for key in ("canonical_event_id", "history_id", "event_id", "id", "source_row_id"):
        value = row.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _official_identity(row: dict[str, Any]) -> tuple[str | None, str | None]:
    selector = row.get("selector") if isinstance(row.get("selector"), dict) else {}
    geometry = row.get("geometry") if isinstance(row.get("geometry"), dict) else {}
    geometry_selector = geometry.get("selector") if isinstance(geometry.get("selector"), dict) else {}
    after = row.get("after") if isinstance(row.get("after"), dict) else {}
    return (
        row.get("line")
        or row.get("line_name")
        or row.get("railway")
        or row.get("railway_name")
        or row.get("official_line_name")
        or selector.get("line_name")
        or geometry_selector.get("line_name")
        or after.get("line"),
        row.get("operator")
        or row.get("operator_name")
        or row.get("official_operator_name")
        or selector.get("operator")
        or geometry_selector.get("operator")
        or after.get("operator"),
    )


def audit(events_doc: Any, history: Any, official_rows: Iterable[dict[str, Any]] | None = None) -> dict[str, Any]:
    findings: list[Finding] = []
    if not isinstance(events_doc, dict) or not isinstance(events_doc.get("events"), list):
        raise ValueError("canonical file must be an object with an events array")
    if not isinstance(history, dict):
        raise ValueError("generated history must be an object")
    for category in ("sections", "stations", "retirements"):
        if not isinstance(history.get(category), list):
            raise ValueError(f"generated history {category} must be an array")

    temporal_events = events_doc.get("temporal_events", [])
    if not isinstance(temporal_events, list):
        raise ValueError("canonical temporal_events must be an array")
    legacy_event_count = len(events_doc["events"])
    events: list[dict[str, Any]] = events_doc["events"] + temporal_events
    explicit_retirements = events_doc.get("retirements", [])
    unresolved_notes = events_doc.get("not_in_n02", [])
    if not isinstance(explicit_retirements, list) or not isinstance(unresolved_notes, list):
        raise ValueError("canonical retirements and not_in_n02 must be arrays")

    canonical_ids: set[str] = set()
    canonical_by_id: dict[str, dict[str, Any]] = {}
    canonical_by_identity: dict[tuple[str | None, str | None], list[str]] = {}
    canonical_by_official_id: dict[str, list[str]] = {}
    event_reports: list[dict[str, Any]] = []
    generated = {
        category: [(_history_id(item, category), item) for item in history[category]]
        for category in ("sections", "stations", "retirements")
    }

    for index, event in enumerate(events):
        if not isinstance(event, dict):
            findings.append(Finding("INVALID_EVENT", "ERROR", f"events[{index}] is not an object"))
            continue
        event_id = event.get("id")
        if not isinstance(event_id, str) or not event_id.strip():
            findings.append(Finding("INVALID_EVENT_ID", "ERROR", f"events[{index}] has a blank id"))
            continue
        event_id = event_id.strip()
        if event_id in canonical_ids:
            findings.append(Finding("DUPLICATE_EVENT_ID", "ERROR", "canonical event id is duplicated", event_id))
            continue
        canonical_ids.add(event_id)
        canonical_by_id[event_id] = event
        kind = event.get("kind") or "closure"
        if kind not in ALLOWED_KINDS:
            findings.append(Finding("UNKNOWN_KIND", "ERROR", f"unknown event kind {kind!r}", event_id))
        if index >= legacy_event_count or "service_periods" in event:
            # The rich compiler is the authority for reviewed evidence,
            # exact-day precision, source licensing, and interval shape. Legacy
            # ledger rows still use the established missing-kind = closure rule.
            source_event = event
            if index < legacy_event_count and event.get("kind") is None:
                source_event = {**event, "kind": "closure"}
            try:
                validate_source_event(source_event)
            except (KeyError, TypeError, ValueError) as error:
                findings.append(
                    Finding("INVALID_SOURCE_EVENT", "ERROR", str(error), event_id)
                )
        expected_periods = canonical_periods(event, findings, event_id)
        identity = canonical_identity(event)
        canonical_by_identity.setdefault(identity, []).append(event_id)
        official_event_id = event.get("official_event_id")
        if isinstance(official_event_id, str) and official_event_id:
            canonical_by_official_id.setdefault(official_event_id, []).append(event_id)

        sections = [item for item_id, item in generated["sections"] if owned_by(item_id, event_id)]
        stations = [item for item_id, item in generated["stations"] if owned_by(item_id, event_id)]
        paired_id = _relocation_retirement_id(event_id) if kind == "relocation" else None
        retirements = [
            item
            for item_id, item in generated["retirements"]
            if owned_by(item_id, event_id) or (paired_id and owned_by(item_id, paired_id))
        ]
        matches = {"sections": len(sections), "stations": len(stations), "retirements": len(retirements)}
        if not any(matches.values()):
            findings.append(Finding("MATCHED_NOTHING", "ERROR", "canonical event emitted no generated artefact", event_id))
        if kind == "relocation" and not retirements:
            findings.append(Finding("MISSING_RELOCATION_RETIREMENT", "ERROR", "relocation has no generated new-alignment retirement", event_id))

        compiled_bounds: list[tuple[str | None, str | None]] = []
        accepted_identities = {identity}
        if isinstance(event.get("before"), dict):
            accepted_identities.add(
                (event["before"].get("line"), event["before"].get("operator"))
            )
        for category, records in (("sections", sections), ("stations", stations), ("retirements", retirements)):
            for record in records:
                actual_identity = _identity(record, category)
                if actual_identity not in accepted_identities:
                    findings.append(Finding("IDENTITY_MISMATCH", "ERROR", f"{category} identity {actual_identity!r} is outside source identities {list(accepted_identities)!r}", event_id))
                record_bounds = service_bounds(_properties(record, category), f"generated {category} interval", findings, event_id)
                compiled_bounds.append(record_bounds)
        expected_boundary_set = {value for pair in expected_periods for value in pair if value}
        for opening in temporal_events:
            if event_id not in opening.get('predecessor_event_ids', []):
                continue
            opening_periods = canonical_periods(opening, findings, opening['id'])
            for start, _ in opening_periods:
                if start and any((lower is None or lower < start) and (upper is None or start < upper)
                                 for lower, upper in expected_periods[:-1]):
                    expected_boundary_set.add(start)
        if kind == 'relocation' and event.get('valid_to'):
            # A suspended old alignment and its later replacement have
            # different service boundaries. The legacy switch date stamps
            # the replacement, even when old service ended years earlier.
            expected_boundary_set.add(event['valid_to'])
        actual_boundary_set = {value for pair in compiled_bounds for value in pair if value}
        missing_boundaries = sorted(expected_boundary_set - actual_boundary_set)
        extra_boundaries = sorted(actual_boundary_set - expected_boundary_set)
        if missing_boundaries:
            findings.append(Finding("BOUNDARY_MISSING", "ERROR", f"compiled artefacts omit source service boundaries {missing_boundaries}", event_id))
        if extra_boundaries:
            findings.append(Finding("BOUNDARY_MISMATCH", "ERROR", f"compiled artefacts add non-source service boundaries {extra_boundaries}", event_id))
        partition_report: dict[str, Any] | None = None
        if isinstance(event.get("service_partition"), dict):
            partition_report = {}
            for group in ("lower", "upper"):
                expected_group = canonical_periods(
                    {"service_periods": event["service_partition"].get(f"{group}_periods")},
                    findings,
                    event_id,
                )
                group_records = [
                    (category, record)
                    for category, records in (("sections", sections), ("stations", stations))
                    for record in records
                    if _properties(record, category).get('service_partition_side') == group
                    or f".{group}" in (_history_id(record, category) or "")[len(event_id) :]
                ]
                actual_group = {
                    service_bounds(
                        _properties(record, category),
                        f"generated {group} {category} interval",
                        findings,
                        event_id,
                    )
                    for category, record in group_records
                }
                expected_group_set = set(expected_group)
                if not group_records:
                    findings.append(Finding("PARTITION_MATCHED_NOTHING", "ERROR", f"service partition {group} emitted no generated artefact", event_id))
                elif actual_group != expected_group_set:
                    findings.append(Finding("PARTITION_INTERVAL_MISMATCH", "ERROR", f"service partition {group} compiled intervals {sorted(actual_group, key=str)!r} != source {expected_group!r}", event_id))
                partition_report[group] = {
                    "source_periods": [list(pair) for pair in expected_group],
                    "generated_records": len(group_records),
                }
        event_reports.append(
            {
                "id": event_id,
                "kind": kind,
                "identity": list(identity),
                "source_service_periods": [list(pair) for pair in expected_periods],
                **({"service_partition": partition_report} if partition_report is not None else {}),
                "generated": matches,
            }
        )

    explicit_ids: set[str] = set()
    for index, expected in enumerate(explicit_retirements):
        if not isinstance(expected, dict):
            findings.append(Finding("INVALID_RETIREMENT", "ERROR", f"retirements[{index}] is not an object"))
            continue
        retirement_id = expected.get("history_id")
        if not isinstance(retirement_id, str) or not retirement_id:
            findings.append(Finding("INVALID_RETIREMENT_ID", "ERROR", f"retirements[{index}] has a blank history_id"))
            continue
        explicit_ids.add(retirement_id)
        matches = [item for item_id, item in generated["retirements"] if owned_by(item_id, retirement_id)]
        if not matches:
            findings.append(Finding("MATCHED_NOTHING", "ERROR", "canonical retirement emitted no generated retirement", retirement_id))
            continue
        expected_bounds = service_bounds(expected, "canonical retirement interval", findings, retirement_id)
        compiled_retirement_bounds: list[tuple[str | None, str | None]] = []
        for actual in matches:
            if _identity(actual, "retirements") != _identity(expected, "retirements"):
                findings.append(Finding("IDENTITY_MISMATCH", "ERROR", "generated retirement identity differs from canonical match", retirement_id))
            compiled_retirement_bounds.append(
                service_bounds(actual, "generated retirement interval", findings, retirement_id)
            )
        expected_boundaries = {value for value in expected_bounds if value}
        actual_boundaries = {
            value for pair in compiled_retirement_bounds for value in pair if value
        }
        if expected_boundaries != actual_boundaries:
            findings.append(Finding("BOUNDARY_MISMATCH", "ERROR", f"generated retirement boundaries {sorted(actual_boundaries)!r} != canonical {sorted(expected_boundaries)!r}", retirement_id))

    relocation_ids = {
        _relocation_retirement_id(event["id"])
        for event in events
        if isinstance(event, dict) and isinstance(event.get("id"), str) and (event.get("kind") or "closure") == "relocation"
    }
    known_retirement_ids = explicit_ids | relocation_ids
    for category in ("sections", "stations", "retirements"):
        for generated_id, _record in generated[category]:
            if generated_id is None:
                findings.append(Finding("MISSING_GENERATED_ID", "ERROR", f"generated {category} record has no history_id"))
                continue
            known = any(owned_by(generated_id, event_id) for event_id in canonical_ids)
            if category == "retirements":
                known = known or any(
                    owned_by(generated_id, retirement_id)
                    for retirement_id in known_retirement_ids
                )
            if not known:
                findings.append(Finding("ORPHAN_GENERATED_ID", "ERROR", f"generated {category} id has no canonical owner", generated_id))

    unresolved: list[dict[str, Any]] = []
    for index, note in enumerate(unresolved_notes):
        if not isinstance(note, str) or not note.strip():
            findings.append(Finding("INVALID_UNRESOLVED_NOTE", "ERROR", f"not_in_n02[{index}] is blank"))
            continue
        unresolved.append({"source": "canonical.not_in_n02", "detail": note})
        findings.append(Finding("DECLARED_UNRESOLVED", "INCOMPLETE", note))

    official_report: dict[str, Any] = {
        "provided": official_rows is not None,
        "records": 0,
        "explicitly_linked": 0,
        "matched": 0,
        "unresolved": 0,
        "matched_nothing": 0,
        "identity_candidates_without_reviewed_link": 0,
    }
    if official_rows is not None:
        rows = list(official_rows)
        official_report["records"] = len(rows)
        for index, row in enumerate(rows):
            row_id = _official_id(row)
            selector = row.get("selector") if isinstance(row.get("selector"), dict) else {}
            review = row.get("review") if isinstance(row.get("review"), dict) else {}
            status = str(
                row.get("coverage_status")
                or row.get("status")
                or selector.get("status")
                or review.get("status")
                or ""
            ).strip().lower()
            if status in UNRESOLVED_STATUSES:
                official_report["unresolved"] += 1
                unresolved.append({"source": "official_inventory", "id": row_id, "detail": status})
                findings.append(Finding("OFFICIAL_UNRESOLVED", "INCOMPLETE", f"official inventory status is {status}", row_id))
            elif status not in RESOLVED_STATUSES:
                official_report["unresolved"] += 1
                unresolved.append({"source": "official_inventory", "id": row_id, "detail": status or "blank status"})
                findings.append(Finding("OFFICIAL_UNKNOWN_STATUS", "INCOMPLETE", f"official inventory status is {status or 'blank'}", row_id))
            source_row_id = row.get("source_row_id")
            candidates: list[str] = list(canonical_by_official_id.get(source_row_id, []))
            explicitly_linked = bool(candidates)
            if row_id in canonical_ids and row_id not in candidates:
                candidates.append(row_id)
                explicitly_linked = True
            direct_id = next(
                (
                    row.get(key)
                    for key in ("canonical_event_id", "history_id", "event_id")
                    if isinstance(row.get(key), str) and row.get(key)
                ),
                None,
            )
            if not candidates and direct_id in canonical_ids | explicit_ids:
                candidates = [direct_id]
                explicitly_linked = True
            identity_candidates = canonical_by_identity.get(_official_identity(row), [])
            if not explicitly_linked and identity_candidates:
                official_report["identity_candidates_without_reviewed_link"] += 1
            official_kind = row.get("kind")
            if official_kind:
                candidates = [
                    candidate
                    for candidate in candidates
                    if (canonical_by_id.get(candidate, {}).get("kind") or "closure") == official_kind
                ]
            effective_date = row.get("effective_date")
            if effective_date and not explicitly_linked:
                candidates = [
                    candidate
                    for candidate in candidates
                    if effective_date
                    in {
                        boundary
                        for pair in canonical_periods(
                            canonical_by_id.get(candidate, {}), findings, candidate
                        )
                        for boundary in pair
                        if boundary
                    }
                ]
            if not candidates:
                official_report["matched_nothing"] += 1
                findings.append(Finding("OFFICIAL_MATCHED_NOTHING", "ERROR", f"official inventory record {index} matches no canonical event", row_id))
            elif len(candidates) > 1:
                official_report["unresolved"] += 1
                unresolved.append({"source": "official_inventory", "id": row_id, "detail": "ambiguous canonical match"})
                findings.append(Finding("OFFICIAL_AMBIGUOUS_MATCH", "INCOMPLETE", f"official inventory matches {len(candidates)} canonical events", row_id))
            else:
                official_report["matched"] += 1
                if explicitly_linked:
                    official_report["explicitly_linked"] += 1

    structural_errors = [finding for finding in findings if finding.status == "ERROR"]
    canonical_errors = [
        finding for finding in structural_errors if not finding.code.startswith("OFFICIAL_")
    ]
    official_errors = [
        finding for finding in structural_errors if finding.code.startswith("OFFICIAL_")
    ]
    result = {
        "result": "ERROR" if structural_errors else ("INCOMPLETE" if unresolved else "PASS"),
        "scope": {
            "canonical_events": len(events),
            "canonical_retirements": len(explicit_retirements),
            "generated_sections": len(history["sections"]),
            "generated_stations": len(history["stations"]),
            "generated_retirements": len(history["retirements"]),
        },
        "claims": {
            "canonical_ledger_compilation": "PASS" if not canonical_errors else "ERROR",
            "official_inventory_compilation": (
                "NOT_CHECKED"
                if official_rows is None
                else ("PASS" if not official_errors and not official_report["unresolved"] else "INCOMPLETE")
            ),
            "web_loader_boundaries": "NOT_EVALUATED (see jp-history-boundary-report.json)",
            "route_solver_regression": "NOT_EVALUATED (see historical-routes.json and Swift parity tests)",
            "final_display": "NOT_EVALUATED (see packaged jp.display-history.json matchReport)",
        },
        "events": event_reports,
        "official_inventory": official_report,
        "unresolved": unresolved,
        "findings": [finding.as_dict() for finding in findings],
        "counts": {
            "errors": len(structural_errors),
            "unresolved": len(unresolved),
            "matched_nothing": sum(finding.code.endswith("MATCHED_NOTHING") for finding in findings),
            "unknown": sum(
                finding.code in {"UNKNOWN_KIND", "OFFICIAL_UNKNOWN_STATUS"}
                for finding in findings
            ),
        },
    }
    return result


def _print_report(report: dict[str, Any]) -> None:
    scope = report["scope"]
    print(
        "JP history coverage: "
        f"{scope['canonical_events']} canonical events + {scope['canonical_retirements']} canonical retirements; "
        f"{scope['generated_sections']} sections, {scope['generated_stations']} stations, "
        f"{scope['generated_retirements']} retirements generated"
    )
    for finding in report["findings"]:
        record = f" [{finding['record_id']}]" if finding.get("record_id") else ""
        print(f"{finding['status']} {finding['code']}{record}: {finding['message']}")
    official = report["official_inventory"]
    if not official["provided"]:
        print("INCOMPLETE OFFICIAL_INVENTORY_NOT_PROVIDED: official inventory comparison was not requested")
    print(
        f"Result: {report['result']} (errors={report['counts']['errors']}, "
        f"unresolved={report['counts']['unresolved']}, matched_nothing={report['counts']['matched_nothing']})"
    )
    print("Scope note: this is a compilation/availability audit; it does not claim route-solver or final-display verification.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events", type=Path, default=DEFAULT_EVENTS)
    parser.add_argument("--history", type=Path, default=DEFAULT_HISTORY)
    parser.add_argument("--official-inventory", type=Path)
    parser.add_argument("--require-official-inventory", action="store_true")
    parser.add_argument("--json-report", type=Path)
    parser.add_argument("--strict", action="store_true", help="fail unless complete coverage is achieved")
    parser.add_argument(
        "--baseline-max-unresolved",
        type=int,
        help="structural CI gate: permit at most this many declared unresolved legacy gaps",
    )
    args = parser.parse_args(argv)

    try:
        official_rows = None
        if args.official_inventory is not None:
            if not args.official_inventory.exists():
                raise FileNotFoundError(args.official_inventory)
            official_rows = _official_rows(args.official_inventory)
        report = audit(_read_json(args.events), _read_json(args.history), official_rows)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR INPUT: {error}", file=sys.stderr)
        return 2

    _print_report(report)
    if args.json_report:
        args.json_report.parent.mkdir(parents=True, exist_ok=True)
        with args.json_report.open("w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2)
            handle.write("\n")

    counts = report["counts"]
    structural_failed = counts["errors"] > 0 or counts["matched_nothing"] > 0 or counts["unknown"] > 0
    if args.baseline_max_unresolved is not None:
        structural_failed = structural_failed or counts["unresolved"] > args.baseline_max_unresolved
    if args.require_official_inventory and not report["official_inventory"]["provided"]:
        structural_failed = True
    if args.strict:
        structural_failed = structural_failed or counts["unresolved"] > 0
    return 1 if structural_failed and (args.strict or args.baseline_max_unresolved is not None or args.require_official_inventory) else 0


if __name__ == "__main__":
    raise SystemExit(main())
