#!/usr/bin/env python3
"""Deterministic builder and validator for JTM's historical timetable facts.

The JSONL tree is the human-reviewable source of truth.  This module validates
it before creating the indexed SQLite runtime artifact.  It never discovers or
guesses timetable facts and never upgrades missing coverage to complete.
"""

from __future__ import annotations

import argparse
import calendar as month_calendar
from collections import Counter, defaultdict
from copy import deepcopy
from datetime import date, datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CANONICAL = ROOT / "app/data/train-service-history"
DEFAULT_LEGACY = ROOT / "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"
JP_PACKAGE = ROOT / "app/public/rail/jp-2025.json"
RAIL_HISTORY = ROOT / "app/data/rail-history.json"
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
SOURCE_DATE_RE = re.compile(r"^[0-9]{4}(?:-[0-9]{2}(?:-[0-9]{2})?)?$")
TIME_RE = re.compile(r"^([0-9]{1,2}):([0-5][0-9])(?::([0-5][0-9]))?$")
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")

STATUS_VALUES = {"verified", "partial", "unknown", "conflict", "not_applicable"}
CONFIDENCE_VALUES = {"high", "medium", "low"}
FACT_COMPLETENESS_DIMENSIONS = {
    "identity", "train_number", "operator", "validity_calendar",
    "origin_destination", "stops", "times", "route_lines", "station_refs",
    "formation", "provenance",
}

# Canonical input field contract. timetable_versions.source_ids is expanded
# into timetable_version_sources; computed *_seconds fields are not accepted
# from source JSONL, so the textual time remains the reviewable fact.
FIELDS = {
    "source_documents": ({"source_id", "publisher", "title", "source_type", "url_or_locator", "accessed_at", "license_status", "redistribution_status", "automated_extraction_allowed"}, {"issue", "publication_date", "effective_date", "content_hash", "archive_locator", "notes"}),
    "operators": ({"operator_id", "legal_name", "display_name", "operator_type", "valid_from"}, {"valid_until", "predecessor_operator_id", "successor_operator_id"}),
    "services": ({"service_id", "canonical_name", "service_class", "historical_generation", "jr_scope"}, {"first_verified_date", "last_verified_date", "successor_region", "successor_operator_id"}),
    "service_name_periods": ({"service_id", "name", "language", "valid_from", "name_type", "source_id"}, {"valid_until"}),
    "timetable_versions": ({"timetable_version_id", "operator_scope", "effective_from", "effective_until", "edition_name", "revision_type", "completeness", "source_ids"}, {"publication_date"}),
    "holiday_calendar_years": ({"year", "status"}, {"source_id", "notes"}),
    "holiday_dates": ({"service_date", "name", "source_id"}, set()),
    "calendars": ({"calendar_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "valid_from", "valid_until", "holiday_policy"}, set()),
    "calendar_exceptions": ({"calendar_id", "service_date", "exception_type", "source_id"}, {"reason"}),
    "station_identities": ({"station_id", "name_snapshot", "reference_kind"}, {"current_source_code", "rail_history_id", "valid_from", "valid_until"}),
    "trips": ({"trip_id", "timetable_version_id", "service_id", "calendar_id", "origin_station_id", "destination_station_id", "service_class"}, {"train_number", "public_number", "direction", "operation_group_id", "notes"}),
    "stop_times": ({"trip_id", "stop_sequence", "station_id", "call_type", "source_id"}, {"arrival_time", "departure_time", "day_offset", "arrival_day_offset", "departure_day_offset", "pickup_allowed", "dropoff_allowed", "platform", "time_accuracy"}),
    "trip_timetable_symbols": ({"trip_id", "after_stop_sequence", "position", "station_name", "symbol", "source_id"}, set()),
    "trip_stop_time_overrides": ({"trip_id", "service_date", "stop_sequence", "source_id"}, {"arrival_override", "departure_override", "arrival_day_offset_override", "departure_day_offset_override", "platform_override", "platform_override_present"}),
    "trip_train_number_overrides": ({"trip_id", "service_date", "train_number", "source_id"}, set()),
    "trip_number_segments": ({"trip_id", "from_sequence", "to_sequence", "train_number"}, set()),
    "trip_formations": ({"formation_id", "trip_id", "service_date", "evidence_kind", "source_id"}, {"formation_label", "car_count", "reserved_seat_capacity", "vehicle_series", "all_reserved", "green_car_available", "notes"}),
    "trip_formation_cars": ({"formation_id", "car_sequence", "car_number", "source_id"}, {"vehicle_series", "seat_class", "reservation_type", "notes"}),
    "trip_operator_segments": ({"trip_id", "from_sequence", "to_sequence", "operator_id"}, set()),
    "trip_line_segments": ({"trip_id", "sequence", "from_station_id", "to_station_id", "line_name", "operator_id", "source_id", "confidence"}, {"reference_kind", "current_n02_line_id", "rail_history_id"}),
    "trip_relations": ({"trip_id", "related_trip_id", "relation_type", "source_id"}, {"from_sequence", "to_sequence"}),
    "fact_sources": ({"entity_type", "entity_id", "field_name", "source_id", "confidence", "verification_status"}, {"page_or_locator"}),
    "fact_completeness": ({"entity_type", "entity_id", "dimension", "status", "confidence"}, {"notes"}),
    "verified_zero_service_intervals": ({"interval_id", "operator_scope", "valid_from", "valid_until", "reason", "source_id"}, set()),
    "coverage_declarations": ({"coverage_id", "operator_scope", "year", "dimension", "status"}, {"record_count", "source_id", "notes"}),
    "research_queue": ({"research_id", "entity_type", "entity_id", "missing_dimension", "status"}, {"notes"}),
    "actual_operation_events": ({"event_id", "trip_id", "service_date", "event_type", "source_id"}, {"notes"}),
}

PRIMARY_KEYS = {
    "source_documents": ("source_id",), "operators": ("operator_id",),
    "services": ("service_id",),
    "service_name_periods": ("service_id", "language", "name_type", "valid_from", "name"),
    "timetable_versions": ("timetable_version_id",),
    "holiday_calendar_years": ("year",), "holiday_dates": ("service_date",),
    "calendars": ("calendar_id",),
    "calendar_exceptions": ("calendar_id", "service_date"),
    "station_identities": ("station_id",), "trips": ("trip_id",),
    "stop_times": ("trip_id", "stop_sequence"),
    "trip_timetable_symbols": ("trip_id", "after_stop_sequence", "position"),
    "trip_stop_time_overrides": ("trip_id", "service_date", "stop_sequence"),
    "trip_train_number_overrides": ("trip_id", "service_date"),
    "trip_number_segments": ("trip_id", "from_sequence"),
    "trip_formations": ("formation_id",),
    "trip_formation_cars": ("formation_id", "car_sequence"),
    "trip_operator_segments": ("trip_id", "from_sequence"),
    "trip_line_segments": ("trip_id", "sequence"),
    "trip_relations": ("trip_id", "related_trip_id", "relation_type"),
    "fact_sources": ("entity_type", "entity_id", "field_name", "source_id"),
    "fact_completeness": ("entity_type", "entity_id", "dimension"),
    "verified_zero_service_intervals": ("interval_id",),
    "coverage_declarations": ("coverage_id",),
    "research_queue": ("research_id",), "actual_operation_events": ("event_id",),
}

INSERT_ORDER = [
    "source_documents", "operators", "services", "service_name_periods",
    "timetable_versions", "holiday_calendar_years", "holiday_dates", "calendars",
    "calendar_exceptions", "station_identities", "trips", "stop_times", "trip_timetable_symbols",
    "trip_stop_time_overrides", "trip_train_number_overrides", "trip_number_segments", "trip_formations", "trip_formation_cars", "trip_operator_segments",
    "trip_line_segments", "trip_relations", "fact_sources", "fact_completeness",
    "verified_zero_service_intervals", "coverage_declarations", "research_queue",
    "actual_operation_events",
]


class DatasetError(Exception):
    pass


def canonical_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def strict_date(value, context):
    if not isinstance(value, str) or DATE_RE.fullmatch(value) is None:
        raise DatasetError(f"{context}: expected strict YYYY-MM-DD, found {value!r}")
    try:
        parsed = date.fromisoformat(value)
    except ValueError as exc:
        raise DatasetError(f"{context}: invalid Gregorian date {value!r}") from exc
    if parsed.isoformat() != value:
        raise DatasetError(f"{context}: non-canonical date {value!r}")
    return parsed


def parsed_date_or_none(value):
    """Parse a canonical day for dependent checks after the primary diagnostic."""
    try:
        return strict_date(value, "date")
    except DatasetError:
        return None


def interval(record, start_key, end_key, context, end_required=False):
    start = strict_date(record[start_key], f"{context}.{start_key}")
    end_value = record.get(end_key)
    if end_value is None:
        if end_required:
            raise DatasetError(f"{context}.{end_key}: required exclusive end")
        return start, None
    end = strict_date(end_value, f"{context}.{end_key}")
    if not start < end:
        raise DatasetError(f"{context}: expected {start_key} < {end_key} (exclusive)")
    return start, end


def service_seconds(value, day_offset, context):
    if value is None:
        return None
    if not isinstance(value, str):
        raise DatasetError(f"{context}: time must be a string or null")
    match = TIME_RE.fullmatch(value)
    if match is None:
        raise DatasetError(f"{context}: expected H:MM or H:MM:SS, found {value!r}")
    hour, minute, second = (int(match.group(1)), int(match.group(2)), int(match.group(3) or 0))
    if hour > 71:
        raise DatasetError(f"{context}: hour {hour} exceeds the 72-hour service-day bound")
    if not isinstance(day_offset, int) or isinstance(day_offset, bool) or day_offset < 0:
        raise DatasetError(f"{context}: day_offset must be a non-negative integer")
    if hour >= 24 and day_offset:
        raise DatasetError(f"{context}: >=24-hour notation cannot also set day_offset")
    total = hour * 3600 + minute * 60 + second + (0 if hour >= 24 else day_offset * 86400)
    if total >= 72 * 3600:
        raise DatasetError(f"{context}: resolved time must be less than 72 hours from service-day start")
    return total


def stop_day_offset(row, side):
    """Resolve an arrival/departure offset with legacy shared-offset fallback."""
    value = row.get(f"{side}_day_offset")
    return row.get("day_offset", 0) if value is None else value


def load_manifest(canonical_dir):
    path = canonical_dir / "manifest.json"
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DatasetError(f"cannot read {path}: {exc}") from exc
    for key in ("schema_version", "build_version", "as_of_date", "first_scope_date", "timezone", "schema_path", "entities"):
        if key not in manifest:
            raise DatasetError(f"manifest missing {key}")
    strict_date(manifest["as_of_date"], "manifest.as_of_date")
    strict_date(manifest["first_scope_date"], "manifest.first_scope_date")
    if manifest["timezone"] != "Asia/Tokyo":
        raise DatasetError("manifest.timezone must be Asia/Tokyo")
    unknown = set(manifest["entities"]) - set(FIELDS)
    if unknown:
        raise DatasetError(f"manifest has unknown entities: {sorted(unknown)}")
    return manifest


def entity_paths(canonical_dir, patterns):
    result = []
    for pattern in patterns:
        result.extend(canonical_dir.glob(pattern))
    return sorted({path for path in result if path.is_file()}, key=lambda p: p.as_posix())


def effective_entity_paths(canonical_dir, patterns):
    """Ignore only byte-identical numbered copies; retain differing facts."""
    result = []
    for path in entity_paths(canonical_dir, patterns):
        original_stem = re.sub(r" (?:[2-9]|[1-9][0-9]+)$", "", path.stem)
        original = path.with_name(original_stem + path.suffix)
        if original != path and original.is_file() and path.read_bytes() == original.read_bytes():
            continue
        result.append(path)
    return result


def load_dataset(canonical_dir, manifest):
    data = {entity: [] for entity in FIELDS}
    origins = {}
    for entity, patterns in manifest["entities"].items():
        for path in effective_entity_paths(canonical_dir, patterns):
            for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if not raw.strip():
                    continue
                try:
                    record = json.loads(raw)
                except json.JSONDecodeError as exc:
                    raise DatasetError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
                if not isinstance(record, dict):
                    raise DatasetError(f"{path}:{line_number}: JSONL row must be an object")
                data[entity].append(record)
                origins[(entity, len(data[entity]) - 1)] = f"{path.relative_to(canonical_dir)}:{line_number}"
    return data, origins


def known_station_references():
    current = set()
    history = set()
    package = json.loads(JP_PACKAGE.read_text(encoding="utf-8"))
    for line in package.get("lines", []):
        current.update(row[0] for row in line.get("stations", []) if row and isinstance(row[0], str))
    overlay = json.loads(RAIL_HISTORY.read_text(encoding="utf-8"))
    for feature in overlay.get("stations", []):
        value = feature.get("properties", {}).get("history_id")
        if value:
            history.add(value)
    return current, history


def _ids(data, entity, field):
    return {row[field] for row in data[entity]}


def _require_ref(errors, value, known, context):
    if value is not None and value not in known:
        errors.append(f"{context}: unknown reference {value!r}")


def validate_dataset(data, origins, manifest, rail_history=None, current_package=None):
    errors = []
    for entity, records in data.items():
        required, optional = FIELDS[entity]
        seen = set()
        for index, row in enumerate(records):
            where = origins.get((entity, index), f"{entity}[{index}]")
            missing = required - set(row)
            unknown = set(row) - required - optional
            if missing:
                errors.append(f"{where}: missing fields {sorted(missing)}")
            if unknown:
                errors.append(f"{where}: unknown fields {sorted(unknown)}")
            if missing:
                continue
            key = tuple(row.get(field) for field in PRIMARY_KEYS[entity])
            if key in seen:
                errors.append(f"{where}: duplicate canonical key {key}")
            seen.add(key)
            for field in PRIMARY_KEYS[entity]:
                value = row.get(field)
                if field.endswith("_id") and isinstance(value, str) and ID_RE.fullmatch(value) is None:
                    errors.append(f"{where}.{field}: invalid stable identifier {value!r}")

    source_ids = _ids(data, "source_documents", "source_id")
    operator_ids = _ids(data, "operators", "operator_id")
    service_ids = _ids(data, "services", "service_id")
    version_ids = _ids(data, "timetable_versions", "timetable_version_id")
    calendar_ids = _ids(data, "calendars", "calendar_id")
    station_ids = _ids(data, "station_identities", "station_id")
    trip_ids = _ids(data, "trips", "trip_id")
    operators_by_id = {row["operator_id"]: row for row in data["operators"]}
    versions_by_id = {row["timetable_version_id"]: row for row in data["timetable_versions"]}
    calendars_by_id = {row["calendar_id"]: row for row in data["calendars"]}
    stations_by_id = {row["station_id"]: row for row in data["station_identities"]}
    current_codes, history_ids = known_station_references()

    for i, row in enumerate(data["source_documents"]):
        where = origins[("source_documents", i)]
        if type(row.get("automated_extraction_allowed")) not in (bool, int) or row["automated_extraction_allowed"] not in (0, 1, False, True):
            errors.append(f"{where}.automated_extraction_allowed: must be JSON true/false or 0/1")
        for field in ("publication_date", "effective_date"):
            if row.get(field):
                value = row[field]
                if not isinstance(value, str) or SOURCE_DATE_RE.fullmatch(value) is None:
                    errors.append(f"{where}.{field}: expected ISO year, month, or date")
                elif len(value) == 10:
                    try: strict_date(value, f"{where}.{field}")
                    except DatasetError as exc: errors.append(str(exc))
                elif len(value) == 7 and not 1 <= int(value[5:7]) <= 12:
                    errors.append(f"{where}.{field}: invalid ISO month")
        accessed = row.get("accessed_at")
        try:
            if DATE_RE.fullmatch(accessed):
                strict_date(accessed, f"{where}.accessed_at")
            else:
                parsed = datetime.fromisoformat(accessed.replace("Z", "+00:00"))
                if parsed.tzinfo is None: raise ValueError("timezone required")
        except (AttributeError, ValueError, DatasetError):
            errors.append(f"{where}.accessed_at: expected ISO date or timestamp with timezone")

    for i, row in enumerate(data["operators"]):
        where = origins[("operators", i)]
        try: interval(row, "valid_from", "valid_until", where)
        except DatasetError as exc: errors.append(str(exc))
        _require_ref(errors, row.get("predecessor_operator_id"), operator_ids, where + ".predecessor_operator_id")
        _require_ref(errors, row.get("successor_operator_id"), operator_ids, where + ".successor_operator_id")
        if row.get("predecessor_operator_id") == row.get("operator_id") or row.get("successor_operator_id") == row.get("operator_id"):
            errors.append(f"{where}: operator predecessor/successor cannot reference itself")

    for i, row in enumerate(data["services"]):
        where = origins[("services", i)]
        if not isinstance(row.get("historical_generation"), int) or row["historical_generation"] < 1:
            errors.append(f"{where}.historical_generation: expected positive integer")
        if row.get("first_verified_date"):
            try: first = strict_date(row["first_verified_date"], where + ".first_verified_date")
            except DatasetError as exc: errors.append(str(exc)); first = None
        else: first = None
        if row.get("last_verified_date"):
            try: last = strict_date(row["last_verified_date"], where + ".last_verified_date")
            except DatasetError as exc: errors.append(str(exc)); last = None
        else: last = None
        if first and last and first > last:
            errors.append(f"{where}: first_verified_date must not follow last_verified_date")
        _require_ref(errors, row.get("successor_operator_id"), operator_ids, where + ".successor_operator_id")

    for entity, field in (("service_name_periods", "source_id"), ("holiday_dates", "source_id"), ("calendar_exceptions", "source_id"), ("stop_times", "source_id"), ("trip_timetable_symbols", "source_id"), ("trip_stop_time_overrides", "source_id"), ("trip_train_number_overrides", "source_id"), ("trip_formations", "source_id"), ("trip_formation_cars", "source_id"), ("trip_line_segments", "source_id"), ("trip_relations", "source_id"), ("fact_sources", "source_id"), ("verified_zero_service_intervals", "source_id"), ("actual_operation_events", "source_id")):
        for i, row in enumerate(data[entity]):
            _require_ref(errors, row.get(field), source_ids, origins[(entity, i)] + "." + field)

    for i, row in enumerate(data["service_name_periods"]):
        where = origins[("service_name_periods", i)]
        _require_ref(errors, row.get("service_id"), service_ids, where + ".service_id")
        try: interval(row, "valid_from", "valid_until", where)
        except DatasetError as exc: errors.append(str(exc))
    periods = defaultdict(list)
    for row in data["service_name_periods"]:
        start = parsed_date_or_none(row.get("valid_from"))
        end = parsed_date_or_none(row.get("valid_until")) if row.get("valid_until") else date.max
        if start is not None and end is not None:
            periods[(row["service_id"], row["language"], row["name_type"])].append((start, end, row["name"]))
    for key, rows in periods.items():
        ordered = sorted(rows)
        for left, right in zip(ordered, ordered[1:]):
            if left[1] > right[0] and left[2] != right[2]:
                errors.append(f"service_name_periods {key}: conflicting names {left[2]!r}/{right[2]!r} overlap")

    for i, row in enumerate(data["timetable_versions"]):
        where = origins[("timetable_versions", i)]
        try: interval(row, "effective_from", "effective_until", where, True)
        except DatasetError as exc: errors.append(str(exc))
        if row.get("publication_date"):
            try: strict_date(row["publication_date"], where + ".publication_date")
            except DatasetError as exc: errors.append(str(exc))
        if row.get("completeness") not in {"verified", "partial", "unknown", "conflict"}:
            errors.append(f"{where}.completeness: invalid value")
        if not isinstance(row.get("source_ids"), list) or not row["source_ids"]:
            errors.append(f"{where}.source_ids: expected a non-empty list")
        else:
            for source_id in row["source_ids"]:
                _require_ref(errors, source_id, source_ids, where + ".source_ids")

    for i, row in enumerate(data["holiday_calendar_years"]):
        where = origins[("holiday_calendar_years", i)]
        if type(row.get("year")) is not int or not 1912 <= row["year"] <= 9999:
            errors.append(f"{where}.year: expected integer from 1912 through 9999")
        if row.get("status") not in {"verified", "partial", "missing", "conflict"}:
            errors.append(f"{where}.status: invalid value")
        _require_ref(errors, row.get("source_id"), source_ids, where + ".source_id")
    for i, row in enumerate(data["holiday_dates"]):
        where = origins[("holiday_dates", i)]
        try: strict_date(row["service_date"], where + ".service_date")
        except DatasetError as exc: errors.append(str(exc))

    for i, row in enumerate(data["calendars"]):
        where = origins[("calendars", i)]
        try: start, end = interval(row, "valid_from", "valid_until", where, True)
        except DatasetError as exc: errors.append(str(exc)); start = end = None
        for day_name in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"):
            if type(row.get(day_name)) not in (bool, int) or row[day_name] not in (0, 1, False, True):
                errors.append(f"{where}.{day_name}: expected boolean or 0/1")
        if row.get("holiday_policy") not in {"none", "treat_as_sunday"}:
            errors.append(f"{where}.holiday_policy: invalid value")
        if start and end and row.get("holiday_policy") == "treat_as_sunday":
            years = {r["year"]: r["status"] for r in data["holiday_calendar_years"]}
            for year in range(start.year, (end - timedelta(days=1)).year + 1):
                if years.get(year) != "verified":
                    errors.append(f"{where}: holiday calendar {year} is not verified")

    for i, row in enumerate(data["calendar_exceptions"]):
        where = origins[("calendar_exceptions", i)]
        _require_ref(errors, row.get("calendar_id"), calendar_ids, where + ".calendar_id")
        try:
            exception_day = strict_date(row["service_date"], where + ".service_date")
        except DatasetError as exc:
            errors.append(str(exc)); exception_day = None
        if row.get("exception_type") not in {"add", "remove"}:
            errors.append(f"{where}.exception_type: expected add/remove")
        calendar_row = calendars_by_id.get(row.get("calendar_id"))
        if calendar_row is not None and exception_day is not None:
            calendar_start = parsed_date_or_none(calendar_row.get("valid_from"))
            calendar_end = parsed_date_or_none(calendar_row.get("valid_until"))
            if calendar_start is not None and calendar_end is not None and not calendar_start <= exception_day < calendar_end:
                errors.append(f"{where}: exception lies outside calendar's half-open validity")

    for i, row in enumerate(data["station_identities"]):
        where = origins[("station_identities", i)]
        kind = row.get("reference_kind")
        if kind == "current_n02":
            code = row.get("current_source_code")
            if code not in current_codes:
                errors.append(f"{where}: current sourceCode {code!r} is not in jp-2025")
            if row.get("rail_history_id") is not None:
                errors.append(f"{where}: current_n02 cannot also carry rail_history_id")
        elif kind == "historical_overlay":
            history_id = row.get("rail_history_id")
            if history_id not in history_ids:
                errors.append(f"{where}: history_id {history_id!r} is not in rail-history.json")
            if row.get("current_source_code") is not None:
                errors.append(f"{where}: historical_overlay cannot invent current_source_code")
        else:
            errors.append(f"{where}.reference_kind: invalid value")
        if row.get("valid_from"):
            try: interval(row, "valid_from", "valid_until", where)
            except DatasetError as exc: errors.append(str(exc))
        elif row.get("valid_until"):
            errors.append(f"{where}: valid_until requires valid_from")

    trips = {row["trip_id"]: row for row in data["trips"]}
    def operation_bounds(trip):
        if trip is None: return None
        version = versions_by_id.get(trip.get("timetable_version_id"))
        calendar_row = calendars_by_id.get(trip.get("calendar_id"))
        if version is None or calendar_row is None: return None
        starts = (parsed_date_or_none(version.get("effective_from")), parsed_date_or_none(calendar_row.get("valid_from")))
        ends = (parsed_date_or_none(version.get("effective_until")), parsed_date_or_none(calendar_row.get("valid_until")))
        if None in starts or None in ends: return None
        start, end = max(starts), min(ends)
        return (start, end) if start < end else None

    stops_by_trip = defaultdict(list)
    for row in data["stop_times"]:
        stops_by_trip[row["trip_id"]].append(row)
    stop_keys = {(row["trip_id"], row["stop_sequence"]) for row in data["stop_times"]}
    for i, row in enumerate(data["trip_timetable_symbols"]):
        where = origins[("trip_timetable_symbols", i)]
        if row.get("trip_id") not in trips:
            errors.append(f"{where}.trip_id: unknown trip")
        if (row.get("trip_id"), row.get("after_stop_sequence")) not in stop_keys:
            errors.append(f"{where}.after_stop_sequence: expected an existing trip stop")
        if row.get("symbol") not in {"レ", "||"}:
            errors.append(f"{where}.symbol: expected レ or ||")
        if not isinstance(row.get("station_name"), str) or not row["station_name"].strip():
            errors.append(f"{where}.station_name: expected a nonempty station name")
        if type(row.get("position")) is not int or row["position"] < 0:
            errors.append(f"{where}.position: expected a nonnegative integer")
    for i, row in enumerate(data["trips"]):
        where = origins[("trips", i)]
        _require_ref(errors, row.get("timetable_version_id"), version_ids, where + ".timetable_version_id")
        _require_ref(errors, row.get("service_id"), service_ids, where + ".service_id")
        _require_ref(errors, row.get("calendar_id"), calendar_ids, where + ".calendar_id")
        _require_ref(errors, row.get("origin_station_id"), station_ids, where + ".origin_station_id")
        _require_ref(errors, row.get("destination_station_id"), station_ids, where + ".destination_station_id")
        version = versions_by_id.get(row.get("timetable_version_id"))
        calendar_row = calendars_by_id.get(row.get("calendar_id"))
        if version and calendar_row:
            version_start = parsed_date_or_none(version.get("effective_from"))
            version_end = parsed_date_or_none(version.get("effective_until"))
            calendar_start = parsed_date_or_none(calendar_row.get("valid_from"))
            calendar_end = parsed_date_or_none(calendar_row.get("valid_until"))
            if None in (version_start, version_end, calendar_start, calendar_end):
                operation_start = operation_end = None
            else:
                operation_start = max(version_start, calendar_start)
                operation_end = min(version_end, calendar_end)
            if operation_start is not None and operation_start >= operation_end:
                errors.append(f"{where}: timetable version and calendar do not overlap")
            elif operation_start is not None:
                for stop in stops_by_trip.get(row["trip_id"], []):
                    station = stations_by_id.get(stop.get("station_id"))
                    if station is None: continue
                    station_start = parsed_date_or_none(station.get("valid_from")) if station.get("valid_from") else None
                    station_end = parsed_date_or_none(station.get("valid_until")) if station.get("valid_until") else None
                    if station_start and station_start > operation_start:
                        errors.append(f"{where}: station {station['station_id']} begins after the trip operation interval")
                    if station_end and station_end < operation_end:
                        errors.append(f"{where}: station {station['station_id']} ends before the trip operation interval")
        stops = sorted(stops_by_trip.get(row["trip_id"], []), key=lambda x: x["stop_sequence"])
        if len(stops) < 2:
            errors.append(f"{where}: a trip requires at least origin and destination stop_times")
            continue
        sequences = [stop["stop_sequence"] for stop in stops]
        if any(type(value) is not int for value in sequences) or any(a >= b for a, b in zip(sequences, sequences[1:])):
            errors.append(f"{where}: stop_sequence must be strictly increasing integers")
        if stops[0].get("station_id") != row["origin_station_id"] or stops[0].get("call_type") != "origin":
            errors.append(f"{where}: first stop must be the declared origin with call_type origin")
        if stops[-1].get("station_id") != row["destination_station_id"] or stops[-1].get("call_type") != "destination":
            errors.append(f"{where}: last stop must be the declared destination with call_type destination")
        previous = None
        for stop in stops:
            stop_where = f"{where}.stop_times[{stop.get('stop_sequence')}]"
            arrival_offset = stop_day_offset(stop, "arrival")
            departure_offset = stop_day_offset(stop, "departure")
            if stop.get("arrival_day_offset") is not None and stop.get("arrival_time") is None:
                errors.append(f"{stop_where}: arrival_day_offset requires arrival_time")
            if stop.get("departure_day_offset") is not None and stop.get("departure_time") is None:
                errors.append(f"{stop_where}: departure_day_offset requires departure_time")
            try:
                arrival = service_seconds(stop.get("arrival_time"), arrival_offset, stop_where + ".arrival_time")
                departure = service_seconds(stop.get("departure_time"), departure_offset, stop_where + ".departure_time")
            except DatasetError as exc:
                errors.append(str(exc)); continue
            if arrival is not None and departure is not None and arrival > departure:
                errors.append(f"{stop_where}: arrival follows departure")
            for current in (arrival, departure):
                if current is not None and previous is not None and current < previous:
                    errors.append(f"{stop_where}: known times move backwards within the service day")
                if current is not None: previous = current

    formations = {row["formation_id"]: row for row in data["trip_formations"]}
    cars_by_formation = defaultdict(list)
    for i, row in enumerate(data["trip_formations"]):
        where = origins[("trip_formations", i)]
        _require_ref(errors, row.get("trip_id"), trip_ids, where + ".trip_id")
        try:
            day = strict_date(row.get("service_date"), where + ".service_date")
            bounds = operation_bounds(trips.get(row.get("trip_id")))
            if bounds and not bounds[0] <= day < bounds[1]:
                errors.append(f"{where}: formation date is outside the trip's operation bounds")
            if day > strict_date(manifest["as_of_date"], "manifest.as_of_date"):
                errors.append(f"{where}: formation date exceeds dataset as-of date")
        except DatasetError as exc:
            errors.append(str(exc))
        if row.get("evidence_kind") not in {"planned", "actual"}:
            errors.append(f"{where}.evidence_kind: expected planned or actual")
        for field in ("car_count", "reserved_seat_capacity"):
            value = row.get(field)
            if value is not None and (type(value) is not int or value < (1 if field == "car_count" else 0)):
                errors.append(f"{where}.{field}: invalid count")
        for field in ("all_reserved", "green_car_available"):
            value = row.get(field)
            if value is not None and (type(value) not in (bool, int) or value not in (0, 1, False, True)):
                errors.append(f"{where}.{field}: expected 0/1 or boolean")
        if not any(row.get(field) is not None for field in
                   ("formation_label", "car_count", "reserved_seat_capacity", "vehicle_series",
                    "all_reserved", "green_car_available")):
            errors.append(f"{where}: formation has no known facts")
    for i, row in enumerate(data["trip_formation_cars"]):
        where = origins[("trip_formation_cars", i)]
        _require_ref(errors, row.get("formation_id"), formations, where + ".formation_id")
        if type(row.get("car_sequence")) is not int or row["car_sequence"] < 1:
            errors.append(f"{where}.car_sequence: expected positive integer")
        if not isinstance(row.get("car_number"), str) or not row["car_number"].strip():
            errors.append(f"{where}.car_number: expected nonempty text")
        cars_by_formation[row.get("formation_id")].append(row)
    for formation_id, cars in cars_by_formation.items():
        formation = formations.get(formation_id)
        if formation and formation.get("car_count") is not None and len(cars) > formation["car_count"]:
            errors.append(f"{formation_id}: more car rows than documented car count")
        if len({car.get("car_number") for car in cars}) != len(cars):
            errors.append(f"{formation_id}: duplicate car number")

    for i, row in enumerate(data["stop_times"]):
        where = origins[("stop_times", i)]
        _require_ref(errors, row.get("trip_id"), trip_ids, where + ".trip_id")
        _require_ref(errors, row.get("station_id"), station_ids, where + ".station_id")
        if row.get("call_type") not in {"origin", "passenger_stop", "destination", "pass", "operational_stop", "unknown"}:
            errors.append(f"{where}.call_type: invalid value")
        if row.get("time_accuracy", "unknown") not in {"exact", "minute", "approximate", "unknown"}:
            errors.append(f"{where}.time_accuracy: invalid value")
        if row.get("call_type") in {"pass", "operational_stop", "unknown"}:
            if row.get("pickup_allowed", 0) not in (0, False) or row.get("dropoff_allowed", 0) not in (0, False):
                errors.append(f"{where}: non-passenger call cannot allow pickup/dropoff")

    stops_by_key = {(r["trip_id"], r["stop_sequence"]): r for r in data["stop_times"]}
    stop_keys = set(stops_by_key)
    for i, row in enumerate(data["trip_stop_time_overrides"]):
        where = origins[("trip_stop_time_overrides", i)]
        if (row.get("trip_id"), row.get("stop_sequence")) not in stop_keys:
            errors.append(f"{where}: override does not reference a stop_time")
        try:
            strict_date(row["service_date"], where + ".service_date")
            base_stop = stops_by_key.get((row.get("trip_id"), row.get("stop_sequence")))
            base_arrival_offset = stop_day_offset(base_stop, "arrival") if base_stop else 0
            base_departure_offset = stop_day_offset(base_stop, "departure") if base_stop else 0
            arrival_offset = row.get("arrival_day_offset_override")
            departure_offset = row.get("departure_day_offset_override")
            if arrival_offset is None: arrival_offset = base_arrival_offset
            if departure_offset is None: departure_offset = base_departure_offset
            service_seconds(row.get("arrival_override"), arrival_offset, where + ".arrival_override")
            service_seconds(row.get("departure_override"), departure_offset, where + ".departure_override")
        except DatasetError as exc: errors.append(str(exc))
        if row.get("arrival_day_offset_override") is not None and row.get("arrival_override") is None:
            errors.append(f"{where}: arrival_day_offset_override requires arrival_override")
        if row.get("departure_day_offset_override") is not None and row.get("departure_override") is None:
            errors.append(f"{where}: departure_day_offset_override requires departure_override")
        platform_present = row.get("platform_override_present", 0)
        if type(platform_present) not in (bool, int) or platform_present not in (0, 1):
            errors.append(f"{where}.platform_override_present: expected 0/1")
        if row.get("platform_override") is not None and (platform_present != 1 or not isinstance(row["platform_override"], str) or not row["platform_override"].strip()):
            errors.append(f"{where}.platform_override: requires present=1 and nonempty text")
        if row.get("arrival_override") is None and row.get("departure_override") is None and platform_present != 1:
            errors.append(f"{where}: override changes neither arrival, departure nor platform")

    for i, row in enumerate(data["trip_train_number_overrides"]):
        where = origins[("trip_train_number_overrides", i)]
        _require_ref(errors, row.get("trip_id"), trip_ids, where + ".trip_id")
        try: strict_date(row["service_date"], where + ".service_date")
        except DatasetError as exc: errors.append(str(exc))
        if not isinstance(row.get("train_number"), str) or not row["train_number"].strip():
            errors.append(f"{where}.train_number: expected nonempty text")

    for entity in ("trip_number_segments", "trip_operator_segments"):
        by_trip = defaultdict(list)
        for i, row in enumerate(data[entity]):
            where = origins[(entity, i)]
            _require_ref(errors, row.get("trip_id"), trip_ids, where + ".trip_id")
            if entity == "trip_operator_segments":
                _require_ref(errors, row.get("operator_id"), operator_ids, where + ".operator_id")
                trip = trips.get(row.get("trip_id"))
                operator = operators_by_id.get(row.get("operator_id"))
                if trip and operator:
                    version = versions_by_id.get(trip["timetable_version_id"])
                    calendar_row = calendars_by_id.get(trip["calendar_id"])
                    if version and calendar_row:
                        starts = (parsed_date_or_none(version.get("effective_from")), parsed_date_or_none(calendar_row.get("valid_from")))
                        ends = (parsed_date_or_none(version.get("effective_until")), parsed_date_or_none(calendar_row.get("valid_until")))
                        operator_start = parsed_date_or_none(operator.get("valid_from"))
                        operator_end = parsed_date_or_none(operator.get("valid_until")) if operator.get("valid_until") else None
                        operation_start = max(starts) if None not in starts else None
                        operation_end = min(ends) if None not in ends else None
                        if operation_start is not None and operation_end is not None and operator_start is not None and (operator_start > operation_start or (operator_end and operator_end < operation_end)):
                            errors.append(f"{where}: operator {operator['operator_id']} is not valid for the trip operation interval")
            if type(row.get("from_sequence")) is not int or type(row.get("to_sequence")) is not int or row["from_sequence"] > row["to_sequence"]:
                errors.append(f"{where}: invalid inclusive sequence range")
            else:
                by_trip[row.get("trip_id")].append((row["from_sequence"], row["to_sequence"], where))
        for trip_id, ranges in by_trip.items():
            ordered = sorted(ranges)
            trip_sequences = sorted(stop["stop_sequence"] for stop in stops_by_trip.get(trip_id, []) if type(stop.get("stop_sequence")) is int)
            if trip_sequences:
                valid_sequences = set(trip_sequences)
                for start, end, range_where in ordered:
                    if start not in valid_sequences or end not in valid_sequences:
                        errors.append(f"{range_where}: {entity} boundaries must reference stop_sequence values")
                if ordered[0][0] != trip_sequences[0] or ordered[-1][1] != trip_sequences[-1]:
                    errors.append(f"{ordered[0][2]}: {entity} must cover the trip from first through last stop_sequence")
            for left, right in zip(ordered, ordered[1:]):
                if left[1] > right[0]:
                    errors.append(f"{right[2]}: overlapping {entity} for {trip_id}")
                elif left[1] < right[0]:
                    errors.append(f"{right[2]}: gap between {entity} ranges for {trip_id}")

    for i, row in enumerate(data["trip_line_segments"]):
        where = origins[("trip_line_segments", i)]
        _require_ref(errors, row.get("trip_id"), trip_ids, where + ".trip_id")
        _require_ref(errors, row.get("from_station_id"), station_ids, where + ".from_station_id")
        _require_ref(errors, row.get("to_station_id"), station_ids, where + ".to_station_id")
        _require_ref(errors, row.get("operator_id"), operator_ids, where + ".operator_id")
        if row.get("confidence") not in CONFIDENCE_VALUES:
            errors.append(f"{where}.confidence: invalid value")
        reference_kind = row.get("reference_kind")
        current_line_id = row.get("current_n02_line_id")
        history_id = row.get("rail_history_id")
        if reference_kind is None:
            if current_line_id is not None or history_id is not None:
                errors.append(f"{where}: route identity ids require reference_kind")
        elif reference_kind == "current_n02":
            if not current_line_id or history_id is not None:
                errors.append(f"{where}: current_n02 requires only current_n02_line_id")
        elif reference_kind == "historical_overlay":
            if not history_id or current_line_id is not None:
                errors.append(f"{where}: historical_overlay requires only rail_history_id")
        else:
            errors.append(f"{where}.reference_kind: invalid value")
        bounds = operation_bounds(trips.get(row.get("trip_id")))
        if bounds:
            operation_start, operation_end = bounds
            for station_field in ("from_station_id", "to_station_id"):
                station = stations_by_id.get(row.get(station_field))
                if station is None: continue
                station_start = parsed_date_or_none(station.get("valid_from")) if station.get("valid_from") else None
                station_end = parsed_date_or_none(station.get("valid_until")) if station.get("valid_until") else None
                if station_start and station_start > operation_start:
                    errors.append(f"{where}: line endpoint station {station['station_id']} begins after the trip operation interval")
                if station_end and station_end < operation_end:
                    errors.append(f"{where}: line endpoint station {station['station_id']} ends before the trip operation interval")
            operator = operators_by_id.get(row.get("operator_id"))
            if operator:
                operator_start = parsed_date_or_none(operator.get("valid_from"))
                operator_end = parsed_date_or_none(operator.get("valid_until")) if operator.get("valid_until") else None
                if operator_start and (operator_start > operation_start or (operator_end and operator_end < operation_end)):
                    errors.append(f"{where}: line operator {operator['operator_id']} is not valid for the trip operation interval")
    line_rows = defaultdict(list)
    for row in data["trip_line_segments"]: line_rows[row["trip_id"]].append(row)
    verified_route_trips = {
        row["entity_id"] for row in data["fact_completeness"]
        if row.get("entity_type") == "trip"
        and row.get("dimension") == "route_lines"
        and row.get("status") == "verified"
    }
    for trip_id, rows in line_rows.items():
        ordered = sorted(rows, key=lambda row: row["sequence"])
        trip = trips.get(trip_id)
        if trip and ordered:
            if trip_id in verified_route_trips and ordered[0]["from_station_id"] != trip["origin_station_id"]:
                errors.append(f"trip_line_segments {trip_id}: first segment does not start at trip origin")
            if trip_id in verified_route_trips and ordered[-1]["to_station_id"] != trip["destination_station_id"]:
                errors.append(f"trip_line_segments {trip_id}: last segment does not end at trip destination")
            forms_chain = all(
                left["to_station_id"] == right["from_station_id"]
                for left, right in zip(ordered, ordered[1:]))
            if not forms_chain:
                errors.append(f"trip_line_segments {trip_id}: ordered line segments do not form a chain")
            station_sequences = defaultdict(list)
            for stop in stops_by_trip.get(trip_id, []):
                station_sequences[stop["station_id"]].append(stop["stop_sequence"])
            if not forms_chain:
                continue

            chain_station_ids = [ordered[0]["from_station_id"]] + [
                row["to_station_id"] for row in ordered]
            if (not station_sequences.get(chain_station_ids[0])
                    or not station_sequences.get(chain_station_ids[-1])):
                errors.append(
                    f"trip_line_segments {trip_id}: route-only stations may only be internal "
                    "line-boundary nodes between timetable stops")
                continue

            previous_sequence = None
            anchors_in_order = True
            for station_id in chain_station_ids:
                candidates = sorted(station_sequences.get(station_id, []))
                if not candidates:
                    continue
                sequence = next(
                    (candidate for candidate in candidates
                     if previous_sequence is None or candidate > previous_sequence),
                    None)
                if sequence is None:
                    anchors_in_order = False
                    break
                previous_sequence = sequence
            if not anchors_in_order:
                errors.append(
                    f"trip_line_segments {trip_id}: timetable-stop anchors do not follow "
                    "the ordered line-segment chain")

            for index, station_id in enumerate(chain_station_ids[1:-1], start=1):
                if station_sequences.get(station_id):
                    continue
                left = ordered[index - 1]
                right = ordered[index]
                left_identity = left.get("current_n02_line_id")
                right_identity = right.get("current_n02_line_id")
                if (left.get("reference_kind") != "current_n02"
                        or right.get("reference_kind") != "current_n02"
                        or not left_identity or not right_identity
                        or left_identity == right_identity):
                    errors.append(
                        f"trip_line_segments {trip_id}:{right['sequence']}: route-only boundary "
                        f"station {station_id!r} requires distinct explicit current_n02 route identities")

    for i, row in enumerate(data["trip_relations"]):
        where = origins[("trip_relations", i)]
        _require_ref(errors, row.get("trip_id"), trip_ids, where + ".trip_id")
        _require_ref(errors, row.get("related_trip_id"), trip_ids, where + ".related_trip_id")
        if row.get("trip_id") == row.get("related_trip_id"):
            errors.append(f"{where}: a trip cannot relate to itself")

    # A trip id plus service date is the occurrence key, but two unrelated
    # templates with the same published identity must not both materialize on
    # one date. Adjacent, non-overlapping snapshots remain valid.
    relation_pairs = {
        frozenset((row["trip_id"], row["related_trip_id"])) for row in data["trip_relations"]
    }
    duplicate_groups = defaultdict(list)
    for trip in data["trips"]:
        duplicate_groups[trip["service_id"]].append(trip)
    exception_map = {(row["calendar_id"], row["service_date"]): row["exception_type"] for row in data["calendar_exceptions"]}
    holiday_set = {row["service_date"] for row in data["holiday_dates"]}
    holiday_year_map = {row["year"]: row["status"] for row in data["holiday_calendar_years"]}
    for service_id, rows in duplicate_groups.items():
        for left_index, left in enumerate(rows):
            for right in rows[left_index + 1:]:
                left_numbers = {value for value in (left.get("train_number"), left.get("public_number")) if value}
                right_numbers = {value for value in (right.get("train_number"), right.get("public_number")) if value}
                shared_numbers = left_numbers & right_numbers
                same_unnumbered_logical_trip = (
                    not left_numbers and not right_numbers
                    and left.get("origin_station_id") == right.get("origin_station_id")
                    and left.get("destination_station_id") == right.get("destination_station_id")
                    and left.get("direction") == right.get("direction")
                )
                if not shared_numbers and not same_unnumbered_logical_trip:
                    continue
                if frozenset((left["trip_id"], right["trip_id"])) in relation_pairs:
                    continue
                if left.get("operation_group_id") and left.get("operation_group_id") == right.get("operation_group_id"):
                    continue
                left_bounds, right_bounds = operation_bounds(left), operation_bounds(right)
                if left_bounds is None or right_bounds is None:
                    continue
                left_calendar, right_calendar = calendars_by_id[left["calendar_id"]], calendars_by_id[right["calendar_id"]]
                overlap_start = max(left_bounds[0], right_bounds[0])
                overlap_end = min(left_bounds[1], right_bounds[1])
                current = overlap_start
                while current < overlap_end:
                    if calendar_operates(left_calendar, current, exception_map, holiday_set, holiday_year_map) and calendar_operates(right_calendar, current, exception_map, holiday_set, holiday_year_map):
                        identity = sorted(shared_numbers) if shared_numbers else [service_id, left.get("origin_station_id"), left.get("destination_station_id"), left.get("direction")]
                        errors.append(f"trips {left['trip_id']}/{right['trip_id']}: ambiguous duplicate {identity} on {current.isoformat()}")
                        break
                    current += timedelta(days=1)

    for entity in ("fact_sources", "fact_completeness"):
        for i, row in enumerate(data[entity]):
            where = origins[(entity, i)]
            if row.get("confidence") not in CONFIDENCE_VALUES:
                errors.append(f"{where}.confidence: invalid value")
            if entity == "fact_sources" and row.get("verification_status") not in STATUS_VALUES:
                errors.append(f"{where}.verification_status: invalid value")
            if entity == "fact_completeness" and row.get("status") not in STATUS_VALUES:
                errors.append(f"{where}.status: invalid value")
            if entity == "fact_completeness" and row.get("dimension") not in FACT_COMPLETENESS_DIMENSIONS:
                errors.append(f"{where}.dimension: invalid value")
    entity_ids = {
        "operator": operator_ids, "service": service_ids, "timetable_version": version_ids,
        "calendar": calendar_ids, "station": station_ids, "trip": trip_ids,
        "zero_service_interval": _ids(data, "verified_zero_service_intervals", "interval_id"),
    }
    entity_ids["stop_time"] = {f"{trip_id}:{sequence}" for trip_id, sequence in stop_keys}
    for entity in ("fact_sources", "fact_completeness"):
        for i, row in enumerate(data[entity]):
            known = entity_ids.get(row["entity_type"])
            if known is None:
                errors.append(f"{origins[(entity, i)]}.entity_type: unsupported type {row['entity_type']!r}")
            elif row["entity_id"] not in known:
                errors.append(f"{origins[(entity, i)]}.entity_id: unknown {row['entity_type']} {row['entity_id']!r}")
    verified_sources = {
        (row["entity_type"], row["entity_id"], row["field_name"])
        for row in data["fact_sources"] if row["verification_status"] == "verified"
    }
    for i, row in enumerate(data["fact_completeness"]):
        if row["status"] == "verified" and (row["entity_type"], row["entity_id"], row["dimension"]) not in verified_sources:
            errors.append(f"{origins[('fact_completeness', i)]}: verified completeness requires a matching verified fact_source for the same dimension")
    route_claims = [
        (i, row) for i, row in enumerate(data["fact_completeness"])
        if row.get("entity_type") == "trip"
        and row.get("dimension") == "route_lines"
        and row.get("status") == "verified"
    ]
    attestations = None
    if data["trip_line_segments"] or route_claims:
        attestations = route_attestations(
            data, manifest, rail_history=rail_history, current_package=current_package)
        line_origins = {
            (row["trip_id"], row["sequence"]): origins[("trip_line_segments", index)]
            for index, row in enumerate(data["trip_line_segments"])
        }
        for verdict in attestations.values():
            for segment in verdict["segments"]:
                if segment["status"] == "error":
                    where = line_origins.get(
                        (segment["tripId"], segment["segmentSequence"]),
                        f"trip_line_segments {segment['tripId']}:{segment['segmentSequence']}")
                    errors.append(
                        f"{where}: route identity/date attestation failed "
                        f"({segment['reason']})")
    if route_claims:
        for index, row in route_claims:
            verdict = attestations.get(row["entity_id"])
            if verdict is None or not verdict["canPublishRouteLines"]:
                status = verdict["status"] if verdict else "missing"
                reason = verdict["reason"] if verdict else "trip_not_audited"
                errors.append(
                    f"{origins[('fact_completeness', index)]}: route_lines verified requires "
                    f"dated direct-identity attestation; found {status} ({reason})")

    zero_intervals = []
    for i, row in enumerate(data["verified_zero_service_intervals"]):
        where = origins[("verified_zero_service_intervals", i)]
        try:
            zero_intervals.append((row["operator_scope"], *interval(row, "valid_from", "valid_until", where, True)))
        except DatasetError as exc: errors.append(str(exc))
    for i, row in enumerate(data["coverage_declarations"]):
        where = origins[("coverage_declarations", i)]
        count = row.get("record_count", 0)
        if type(count) is not int or count < 0:
            errors.append(f"{where}.record_count: expected non-negative integer")
        if row.get("status") == "verified" and count == 0:
            errors.append(f"{where}: empty coverage cannot be verified")
        if row.get("status") == "verified" and not row.get("source_id"):
            errors.append(f"{where}: verified coverage requires a source_id")
        year = row.get("year")
        if type(year) is not int or not 1912 <= year <= 9999:
            errors.append(f"{where}.year: expected integer from 1912 through 9999")
        if row.get("status") == "verified_no_service" and type(year) is int and 1 <= year < 9999:
            year_start, year_end = date(row["year"], 1, 1), date(row["year"] + 1, 1, 1)
            if not any(scope == row["operator_scope"] and start <= year_start and end >= year_end for scope, start, end in zero_intervals):
                errors.append(f"{where}: verified_no_service lacks a full-year verified zero-service interval")
        _require_ref(errors, row.get("source_id"), source_ids, where + ".source_id")

    for i, row in enumerate(data['research_queue']):
        if row['status'] not in {'open', 'source_unavailable', 'license_blocked', 'not_digitized', 'resolved'}:
            errors.append(f"{origins[('research_queue', i)]}.status: unsupported research status {row['status']!r}")

    for i, row in enumerate(data["actual_operation_events"]):
        where = origins[("actual_operation_events", i)]
        _require_ref(errors, row.get("trip_id"), trip_ids, where + ".trip_id")
        try: strict_date(row["service_date"], where + ".service_date")
        except DatasetError as exc: errors.append(str(exc))

    return sorted(set(errors))


def source_fingerprint(canonical_dir, manifest):
    digest = hashlib.sha256()
    paths = [canonical_dir / "manifest.json", canonical_dir / manifest["schema_path"]]
    for patterns in manifest["entities"].values():
        paths.extend(effective_entity_paths(canonical_dir, patterns))
    for path in sorted(set(paths), key=lambda p: p.as_posix()):
        relative = path.relative_to(canonical_dir).as_posix().encode("utf-8")
        payload = path.read_bytes()
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        digest.update(len(payload).to_bytes(8, "big"))
        digest.update(payload)
    # Station identity validation depends on these repository-owned datasets.
    # Include them in the build identity so changing either cannot leave a
    # falsely current timetable artifact with the same build id.
    for label, path in (("repository:jp-2025.json", JP_PACKAGE), ("repository:rail-history.json", RAIL_HISTORY)):
        payload = path.read_bytes()
        encoded = label.encode("utf-8")
        digest.update(len(encoded).to_bytes(4, "big"))
        digest.update(encoded)
        digest.update(len(payload).to_bytes(8, "big"))
        digest.update(payload)
    return digest.hexdigest()


def files_fingerprint(paths):
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda p: p.as_posix()):
        digest.update(path.name.encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepared_row(entity, row):
    result = deepcopy(row)
    if entity == "source_documents":
        result["automated_extraction_allowed"] = int(result["automated_extraction_allowed"])
    if entity == "calendars":
        for field in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"):
            result[field] = int(result[field])
    if entity == "stop_times":
        result.setdefault("day_offset", 0)
        result.setdefault("pickup_allowed", 1)
        result.setdefault("dropoff_allowed", 1)
        result.setdefault("time_accuracy", "unknown")
        result["arrival_seconds"] = service_seconds(
            result.get("arrival_time"), stop_day_offset(result, "arrival"), "stop_times.arrival_time")
        result["departure_seconds"] = service_seconds(
            result.get("departure_time"), stop_day_offset(result, "departure"), "stop_times.departure_time")
    if entity == "trip_stop_time_overrides":
        result.setdefault("platform_override_present", 0)
        legacy_base = result.pop("_base_day_offset", 0)
        base_arrival = result.pop("_base_arrival_day_offset", legacy_base)
        base_departure = result.pop("_base_departure_day_offset", legacy_base)
        if result.get("arrival_override") is not None:
            arrival_offset = result.get("arrival_day_offset_override")
            if arrival_offset is None: arrival_offset = base_arrival
            result["arrival_day_offset_override"] = arrival_offset
            result["arrival_seconds_override"] = service_seconds(
                result["arrival_override"], arrival_offset, "override.arrival")
        else:
            result.pop("arrival_day_offset_override", None)
            result["arrival_seconds_override"] = None
        if result.get("departure_override") is not None:
            departure_offset = result.get("departure_day_offset_override")
            if departure_offset is None: departure_offset = base_departure
            result["departure_day_offset_override"] = departure_offset
            result["departure_seconds_override"] = service_seconds(
                result["departure_override"], departure_offset, "override.departure")
        else:
            result.pop("departure_day_offset_override", None)
            result["departure_seconds_override"] = None
    if entity == "coverage_declarations":
        result.setdefault("record_count", 0)
    return result


def insert_rows(connection, table, rows):
    if not rows:
        return
    table_columns = [row[1] for row in connection.execute(f"PRAGMA table_info({table})")]
    for source in sorted(rows, key=canonical_json):
        row = prepared_row(table, source)
        columns = [column for column in table_columns if column in row]
        placeholders = ",".join("?" for _ in columns)
        names = ",".join(columns)
        connection.execute(
            f"INSERT INTO {table} ({names}) VALUES ({placeholders})",
            [row[column] for column in columns],
        )


def build_database(canonical_dir, output=None):
    manifest = load_manifest(canonical_dir)
    data, origins = load_dataset(canonical_dir, manifest)
    errors = validate_dataset(data, origins, manifest)
    if errors:
        raise DatasetError("canonical timetable validation failed:\n" + "\n".join(f"- {error}" for error in errors))
    uses_default_output = output is None
    output = output or canonical_dir / manifest["database_path"]
    output.parent.mkdir(parents=True, exist_ok=True)
    source_hash = source_fingerprint(canonical_dir, manifest)
    history = json.loads(RAIL_HISTORY.read_text(encoding="utf-8"))
    metadata = {
        "schema_version": manifest["schema_version"],
        "build_version": manifest["build_version"],
        "build_id": f"{manifest['build_version']}:{source_hash[:20]}",
        "source_hash": source_hash,
        "as_of_date": manifest["as_of_date"],
        "first_scope_date": manifest["first_scope_date"],
        "timezone": manifest["timezone"],
        "service_day_time_semantics": manifest["service_day_time_semantics"],
        "rail_history_revision": str(history.get("revision", "unknown")),
        "rail_history_hash": file_sha256(RAIL_HISTORY),
        "station_package_hash": file_sha256(JP_PACKAGE),
        "solver_version": str(manifest.get("solver_version", "unknown")),
    }
    fd, temporary_name = tempfile.mkstemp(prefix=output.name + ".", suffix=".tmp", dir=output.parent)
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        connection = sqlite3.connect(temporary)
        try:
            connection.execute("PRAGMA page_size = 4096")
            connection.execute("PRAGMA journal_mode = OFF")
            connection.execute("PRAGMA synchronous = OFF")
            connection.execute("PRAGMA temp_store = MEMORY")
            connection.executescript((canonical_dir / manifest["schema_path"]).read_text(encoding="utf-8"))
            connection.execute("PRAGMA application_id = 0x4A544D54")
            connection.execute("PRAGMA user_version = 1")
            connection.execute("BEGIN")
            insert_rows(connection, "metadata", [{"key": key, "value": value} for key, value in sorted(metadata.items())])
            for entity in INSERT_ORDER:
                rows = data[entity]
                if entity == "trip_stop_time_overrides":
                    offsets = {
                        (row["trip_id"], row["stop_sequence"]):
                            (stop_day_offset(row, "arrival"), stop_day_offset(row, "departure"))
                        for row in data["stop_times"]
                    }
                    rows = [dict(
                        row,
                        _base_arrival_day_offset=offsets[(row["trip_id"], row["stop_sequence"])][0],
                        _base_departure_day_offset=offsets[(row["trip_id"], row["stop_sequence"])][1],
                    ) for row in rows]
                insert_rows(connection, entity, rows)
                if entity == "timetable_versions":
                    joins = []
                    for row in data[entity]:
                        joins.extend({"timetable_version_id": row["timetable_version_id"], "source_id": source_id} for source_id in row["source_ids"])
                    insert_rows(connection, "timetable_version_sources", joins)
            from rail_interval_codes import populate_interval_tables
            populate_interval_tables(connection, json.loads(JP_PACKAGE.read_text(encoding="utf-8")), data)
            foreign_errors = connection.execute("PRAGMA foreign_key_check").fetchall()
            if foreign_errors:
                raise DatasetError(f"SQLite foreign-key check failed: {foreign_errors}")
            connection.commit()
            connection.execute("VACUUM")
        finally:
            connection.close()
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()
    if uses_default_output and canonical_dir.resolve() == DEFAULT_CANONICAL.resolve() and manifest.get("runtime_database_path"):
        runtime_output = (canonical_dir / manifest["runtime_database_path"]).resolve()
        runtime_output.parent.mkdir(parents=True, exist_ok=True)
        runtime_temporary = runtime_output.with_suffix(runtime_output.suffix + ".tmp")
        shutil.copyfile(output, runtime_temporary)
        os.replace(runtime_temporary, runtime_output)
    return output, data, manifest


def calendar_operates(calendar_row, service_date, exceptions, holidays, holiday_years):
    calendar_id = calendar_row["calendar_id"]
    exception = exceptions.get((calendar_id, service_date.isoformat()))
    if exception is not None:
        return exception == "add"
    start = strict_date(calendar_row["valid_from"], calendar_id + ".valid_from")
    end = strict_date(calendar_row["valid_until"], calendar_id + ".valid_until")
    if not start <= service_date < end:
        return False
    weekday = service_date.weekday()
    if calendar_row["holiday_policy"] == "treat_as_sunday" and service_date.isoformat() in holidays:
        if holiday_years.get(service_date.year) != "verified":
            raise DatasetError(f"holiday calendar {service_date.year} is not verified")
        weekday = 6
    field = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")[weekday]
    return bool(calendar_row[field])


def materialize(data, service_day):
    if isinstance(service_day, str):
        service_day = strict_date(service_day, "service_date")
    day_text = service_day.isoformat()
    versions = {row["timetable_version_id"]: row for row in data["timetable_versions"]}
    calendars = {row["calendar_id"]: row for row in data["calendars"]}
    exceptions = {(row["calendar_id"], row["service_date"]): row["exception_type"] for row in data["calendar_exceptions"]}
    holidays = {row["service_date"] for row in data["holiday_dates"]}
    holiday_years = {row["year"]: row["status"] for row in data["holiday_calendar_years"]}
    stops = defaultdict(list)
    for row in data["stop_times"]:
        stops[row["trip_id"]].append(prepared_row("stop_times", row))
    stop_offsets = {
        (row["trip_id"], row["stop_sequence"]):
            (stop_day_offset(row, "arrival"), stop_day_offset(row, "departure"))
        for row in data["stop_times"]
    }
    overrides = {}
    for row in data["trip_stop_time_overrides"]:
        base_arrival, base_departure = stop_offsets[(row["trip_id"], row["stop_sequence"])]
        candidate = dict(row, _base_arrival_day_offset=base_arrival,
                         _base_departure_day_offset=base_departure)
        overrides[(row["trip_id"], row["service_date"], row["stop_sequence"])] = prepared_row("trip_stop_time_overrides", candidate)
    number_overrides = {(row["trip_id"], row["service_date"]): row["train_number"]
                        for row in data.get("trip_train_number_overrides", [])}
    occurrences = []
    for trip in sorted(data["trips"], key=lambda row: row["trip_id"]):
        version = versions.get(trip["timetable_version_id"])
        calendar_row = calendars.get(trip["calendar_id"])
        if version is None or calendar_row is None:
            continue
        if not strict_date(version["effective_from"], "version.from") <= service_day < strict_date(version["effective_until"], "version.until"):
            continue
        if not calendar_operates(calendar_row, service_day, exceptions, holidays, holiday_years):
            continue
        occurrence_stops = []
        for base in sorted(stops[trip["trip_id"]], key=lambda row: row["stop_sequence"]):
            stop = deepcopy(base)
            override = overrides.get((trip["trip_id"], day_text, stop["stop_sequence"]))
            if override:
                if override.get("arrival_override") is not None:
                    stop["arrival_time"] = override["arrival_override"]
                    stop["arrival_seconds"] = override["arrival_seconds_override"]
                    stop["arrival_day_offset"] = override["arrival_day_offset_override"]
                if override.get("departure_override") is not None:
                    stop["departure_time"] = override["departure_override"]
                    stop["departure_seconds"] = override["departure_seconds_override"]
                    stop["departure_day_offset"] = override["departure_day_offset_override"]
                if override["platform_override_present"] == 1:
                    stop["platform"] = override.get("platform_override")
            occurrence_stops.append(stop)
        occurrence = deepcopy(trip)
        if (trip["trip_id"], day_text) in number_overrides:
            occurrence["train_number"] = number_overrides[(trip["trip_id"], day_text)]
        occurrence["service_date"] = day_text
        occurrence["occurrence_key"] = f"{trip['trip_id']}@{day_text}"
        occurrence["stop_times"] = occurrence_stops
        occurrences.append(occurrence)
    return occurrences


def _full_year_or_scope_part(year, scope_start, scope_end):
    start = max(date(year, 1, 1), scope_start)
    end = min(date(year + 1, 1, 1), scope_end)
    return start, end


def _base_calendar_operates(calendar_row, service_day, holidays):
    weekday = service_day.weekday()
    if calendar_row["holiday_policy"] == "treat_as_sunday" and service_day.isoformat() in holidays:
        weekday = 6
    field = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")[weekday]
    return bool(calendar_row[field])


def _operating_day_count(calendar_row, version_row, lower_bound, upper_bound, exceptions, holidays):
    calendar_start = parsed_date_or_none(calendar_row.get("valid_from"))
    calendar_end = parsed_date_or_none(calendar_row.get("valid_until"))
    version_start = parsed_date_or_none(version_row.get("effective_from"))
    version_end = parsed_date_or_none(version_row.get("effective_until"))
    if None in (calendar_start, calendar_end, version_start, version_end):
        return 0
    start = max(lower_bound, calendar_start, version_start)
    end = min(upper_bound, calendar_end, version_end)
    if start >= end:
        return 0
    flags = [bool(calendar_row[name]) for name in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")]
    days = (end - start).days
    weeks, remainder = divmod(days, 7)
    count = weeks * sum(flags)
    count += sum(flags[(start.weekday() + offset) % 7] for offset in range(remainder))
    if calendar_row["holiday_policy"] == "treat_as_sunday":
        for value in holidays:
            holiday = parsed_date_or_none(value)
            if holiday is None:
                continue
            if start <= holiday < end and holiday.weekday() != 6:
                count += int(flags[6]) - int(flags[holiday.weekday()])
    for row in exceptions.get(calendar_row["calendar_id"], []):
        exception_day = parsed_date_or_none(row.get("service_date"))
        if exception_day is None:
            continue
        if not start <= exception_day < end:
            continue
        base = _base_calendar_operates(calendar_row, exception_day, holidays)
        if row["exception_type"] == "add" and not base:
            count += 1
        elif row["exception_type"] == "remove" and base:
            count -= 1
    return count


def rail_history_service_interval(properties, context="rail-history feature"):
    """Return the half-open service interval consumed by the route solver.

    `service_validity` is authoritative when present.  Legacy valid_from/
    valid_to values are next; a lone infrastructure_validity pair is the
    compatibility fallback used by app-rail-history.js.
    """
    service = properties.get("service_validity")
    infrastructure = properties.get("infrastructure_validity")
    has_legacy = "valid_from" in properties or "valid_to" in properties
    if isinstance(service, (list, tuple)) and len(service) == 2:
        values = service
        label = "service_validity"
    elif has_legacy:
        values = [properties.get("valid_from"), properties.get("valid_to")]
        label = "valid_from/valid_to"
    elif isinstance(infrastructure, (list, tuple)) and len(infrastructure) == 2:
        values = infrastructure
        label = "infrastructure_validity"
    else:
        values = [None, None]
        label = "unbounded"
    if not isinstance(values, (list, tuple)) or len(values) != 2:
        raise DatasetError(f"{context}.{label}: expected a two-element interval")
    # RouteGraph.RailValidity treats an empty-string bound as unbounded.  The
    # rail-history schema rejects it, but this helper also audits independently
    # constructed snapshots and must preserve runtime selection semantics.
    start = strict_date(values[0], f"{context}.{label}[0]") if values[0] not in (None, "") else None
    end = strict_date(values[1], f"{context}.{label}[1]") if values[1] not in (None, "") else None
    if start is not None and end is not None and start >= end:
        raise DatasetError(f"{context}.{label}: expected start < exclusive end")
    return start, end, label


def whole_current_line_service_bounds(line, rail_history):
    """Read only retirement constraints that cover an entire compact N02 line.

    A partial bbox cannot identify which part of a trip uses that line. Match
    the overlay's exact line/operator and all-coordinate rule, and replay its
    ordered bound stamps. These bounds can disprove a trip date, but cannot by
    themselves prove the complete historical route.
    """
    runs = line.get("segments") or []
    if not runs or any(len(run) <= 2 or not run[2] for run in runs):
        return None
    points = [point for run in runs for point in run[2]]
    if any(len(point) < 2 for point in points):
        return None
    valid_from = valid_until = None
    matched_ids = []
    for stamp in rail_history.get("retirements", []):
        match = stamp.get("match") or {}
        targets = match.get("targets")
        bbox = match.get("bbox")
        if (targets and "sections" not in targets
                or match.get("line_name") != line.get("name")
                or match.get("operator") != line.get("operator")
                or not isinstance(bbox, list) or len(bbox) != 4):
            continue
        west, south, east, north = bbox
        if not all(west <= point[0] <= east and south <= point[1] <= north
                   for point in points):
            continue
        start, end, _ = rail_history_service_interval(
            stamp, f"rail-history retirement {stamp.get('history_id')}")
        if start is not None:
            valid_from = start
        if end is not None:
            valid_until = end
        matched_ids.append(stamp.get("history_id"))
    return (valid_from, valid_until, matched_ids) if matched_ids else None


def route_attestations(data, manifest, rail_history=None, current_package=None):
    """Return dated route identity verdicts without inferring identifiers.

    Historical segments are attestable only through an explicit overlay
    history_id. Current N02 segments use the existing jp-2025 line id plus
    their endpoint station identities. A whole-line retirement stamp can
    reject an impossible operating day, but cannot establish complete route
    coverage, so an in-range current segment remains temporally unverified.
    """
    if rail_history is None:
        rail_history = json.loads(RAIL_HISTORY.read_text(encoding="utf-8"))
    if current_package is None:
        current_package = json.loads(JP_PACKAGE.read_text(encoding="utf-8"))

    exceptions_by_calendar = defaultdict(list)
    for row in data["calendar_exceptions"]:
        exceptions_by_calendar[row["calendar_id"]].append(row)
    holiday_dates = {row["service_date"] for row in data["holiday_dates"]}
    stations = {row["station_id"]: row for row in data["station_identities"]}
    operators = {row["operator_id"]: row for row in data["operators"]}
    lines_by_trip = defaultdict(list)
    for row in data["trip_line_segments"]:
        lines_by_trip[row["trip_id"]].append(row)

    history_sections = defaultdict(list)
    for feature in rail_history.get("sections", []):
        properties = feature.get("properties", {})
        if properties.get("history_id"):
            history_sections[properties["history_id"]].append(properties)
    current_lines = defaultdict(list)
    for line in current_package.get("lines", []):
        if line.get("id"):
            current_lines[line["id"]].append(line)
    versions = {row["timetable_version_id"]: row for row in data["timetable_versions"]}
    calendars = {row["calendar_id"]: row for row in data["calendars"]}

    trips = {}
    for trip in sorted(data["trips"], key=lambda row: row["trip_id"]):
        version, calendar_row, lower, upper = _trip_occurrence_context(
            data, trip, versions=versions, calendars=calendars)
        occurrence_count = _operating_day_count(
            calendar_row, version, lower, upper, exceptions_by_calendar, holiday_dates)
        segment_verdicts = []
        segments = sorted(lines_by_trip[trip["trip_id"]], key=lambda row: row["sequence"])
        for segment in segments:
            base = {
                "tripId": trip["trip_id"],
                "segmentSequence": segment["sequence"],
                "fromStationId": segment["from_station_id"],
                "toStationId": segment["to_station_id"],
                "lineName": segment["line_name"],
                "operatorId": segment["operator_id"],
                "referenceKind": segment.get("reference_kind"),
                "currentN02LineId": segment.get("current_n02_line_id"),
                "railHistoryId": segment.get("rail_history_id"),
                "occurrenceCount": occurrence_count,
            }
            if occurrence_count == 0:
                segment_verdicts.append(dict(
                    base, status="unverified", reason="no_calendar_occurrences_to_attest"))
                continue
            kind = segment.get("reference_kind")
            if kind is None:
                operator = operators.get(segment.get("operator_id"))
                operator_names = ({operator["display_name"], operator["legal_name"]}
                                  if operator is not None else set())
                candidates = sorted({
                    history_id for history_id, rows in history_sections.items()
                    if any(
                        (row.get("N02_003") or row.get("line_name")) == segment["line_name"]
                        and (row.get("N02_004") or row.get("operator")) in operator_names
                        for row in rows
                    )
                })
                segment_verdicts.append(dict(
                    base, status="unverified", reason="missing_explicit_route_identity",
                    candidateHistoryIds=candidates))
                continue
            operator = operators.get(segment.get("operator_id"))
            operator_names = ({operator["display_name"], operator["legal_name"]}
                              if operator is not None else set())
            if kind == "current_n02":
                line_id = segment.get("current_n02_line_id")
                candidates = current_lines.get(line_id, [])
                if len(candidates) != 1:
                    reason = "current_n02_line_not_found" if not candidates else "current_n02_line_id_not_unique"
                    segment_verdicts.append(dict(base, status="error", reason=reason))
                    continue
                line = candidates[0]
                if line.get("name") != segment["line_name"] or line.get("operator") not in operator_names:
                    segment_verdicts.append(dict(
                        base, status="error", reason="current_n02_line_metadata_mismatch"))
                    continue
                endpoint_codes = []
                endpoint_error = False
                for station_id in (segment["from_station_id"], segment["to_station_id"]):
                    station = stations.get(station_id)
                    if station is None or station.get("reference_kind") != "current_n02":
                        endpoint_error = True
                        break
                    endpoint_codes.append(station.get("current_source_code"))
                line_codes = {row[0] for row in line.get("stations", []) if row}
                if endpoint_error or any(code not in line_codes for code in endpoint_codes):
                    segment_verdicts.append(dict(
                        base, status="error", reason="current_n02_line_endpoint_mismatch"))
                    continue
                try:
                    stamped = whole_current_line_service_bounds(line, rail_history)
                except DatasetError as exc:
                    segment_verdicts.append(dict(
                        base, status="error", reason="invalid_rail_history_service_interval",
                        detail=str(exc)))
                    continue
                if stamped:
                    valid_from, valid_until, history_ids = stamped
                    _, _, invalid_count = _occurrence_alignment(
                        calendar_row, version, lower, upper, valid_from, valid_until,
                        exceptions_by_calendar, holiday_dates)
                    if invalid_count:
                        segment_verdicts.append(dict(
                            base, status="error",
                            reason="route_occurrences_outside_history_service_validity",
                            identityVerified=True, temporalCoverageVerified=False,
                            constraintHistoryIds=history_ids,
                            invalidOccurrenceCount=invalid_count))
                        continue
                segment_verdicts.append(dict(
                    base,
                    status="unverified",
                    reason="current_n02_snapshot_has_no_validity_interval",
                    identityVerified=True,
                    temporalCoverageVerified=False,
                    **({"constraintHistoryIds": stamped[2]} if stamped else {}),
                ))
                continue
            if kind != "historical_overlay":
                segment_verdicts.append(dict(
                    base, status="error", reason="invalid_route_reference_kind"))
                continue
            history_id = segment.get("rail_history_id")
            features = history_sections.get(history_id, [])
            if not features:
                segment_verdicts.append(dict(
                    base, status="error", reason="rail_history_section_not_found"))
                continue
            mismatched = [row for row in features
                          if (row.get("N02_003") or row.get("line_name")) != segment["line_name"]
                          or (row.get("N02_004") or row.get("operator")) not in operator_names]
            if mismatched:
                segment_verdicts.append(dict(
                    base, status="error", reason="rail_history_section_metadata_mismatch"))
                continue
            intervals = []
            invalid_interval = None
            for index, properties in enumerate(features):
                try:
                    valid_from, valid_until, _ = rail_history_service_interval(
                        properties, f"rail-history section {history_id}[{index}]")
                except DatasetError as exc:
                    invalid_interval = str(exc)
                    break
                start = max(lower, valid_from) if valid_from is not None else lower
                end = min(upper, valid_until) if valid_until is not None else upper
                if start < end:
                    intervals.append((start, end))
            if invalid_interval:
                segment_verdicts.append(dict(
                    base, status="error", reason="invalid_rail_history_service_interval",
                    detail=invalid_interval))
                continue
            merged = []
            for start, end in sorted(intervals):
                if merged and start <= merged[-1][1]:
                    merged[-1] = (merged[-1][0], max(merged[-1][1], end))
                else:
                    merged.append((start, end))
            aligned_count = sum(
                _operating_day_count(
                    calendar_row, version, start, end,
                    exceptions_by_calendar, holiday_dates)
                for start, end in merged
            )
            invalid_count = occurrence_count - aligned_count
            segment_verdicts.append(dict(
                base,
                status="aligned" if invalid_count == 0 else "error",
                reason=("all_occurrences_within_history_service_validity"
                        if invalid_count == 0 else "route_occurrences_outside_history_service_validity"),
                identityVerified=True,
                temporalCoverageVerified=invalid_count == 0,
                alignedOccurrenceCount=aligned_count,
                invalidOccurrenceCount=invalid_count,
            ))

        complete_chain = bool(segments) and (
            segments[0]["from_station_id"] == trip["origin_station_id"]
            and segments[-1]["to_station_id"] == trip["destination_station_id"]
            and all(left["to_station_id"] == right["from_station_id"]
                    for left, right in zip(segments, segments[1:]))
        )
        if not segments:
            status, reason = "unverified", "missing_trip_line_segments"
        elif any(row["status"] == "error" for row in segment_verdicts):
            status, reason = "error", "one_or_more_route_segments_failed"
        elif any(row["status"] != "aligned" for row in segment_verdicts):
            status, reason = "unverified", "one_or_more_route_segments_unverified"
        elif not complete_chain:
            status, reason = "unverified", "route_segments_do_not_cover_complete_trip"
        else:
            status, reason = "aligned", "all_route_segments_dated_and_attested"
        trips[trip["trip_id"]] = {
            "tripId": trip["trip_id"],
            "status": status,
            "reason": reason,
            "occurrenceCount": occurrence_count,
            "canPublishRouteLines": status == "aligned",
            "segments": segment_verdicts,
        }
    return trips


def _trip_occurrence_context(data, trip, versions=None, calendars=None):
    versions = versions or {row["timetable_version_id"]: row for row in data["timetable_versions"]}
    calendars = calendars or {row["calendar_id"]: row for row in data["calendars"]}
    version = versions[trip["timetable_version_id"]]
    calendar_row = calendars[trip["calendar_id"]]
    starts = (
        parsed_date_or_none(version.get("effective_from")),
        parsed_date_or_none(calendar_row.get("valid_from")),
    )
    ends = (
        parsed_date_or_none(version.get("effective_until")),
        parsed_date_or_none(calendar_row.get("valid_until")),
    )
    if None in starts or None in ends:
        return version, calendar_row, date.min, date.min
    lower = max(starts)
    upper = min(ends)
    return version, calendar_row, lower, upper


def _occurrence_alignment(calendar_row, version_row, lower, upper, valid_from, valid_until,
                          exceptions_by_calendar, holiday_dates):
    total = _operating_day_count(
        calendar_row, version_row, lower, upper, exceptions_by_calendar, holiday_dates)
    aligned_lower = max(lower, valid_from) if valid_from is not None else lower
    aligned_upper = min(upper, valid_until) if valid_until is not None else upper
    aligned = 0 if aligned_lower >= aligned_upper else _operating_day_count(
        calendar_row, version_row, aligned_lower, aligned_upper,
        exceptions_by_calendar, holiday_dates)
    return total, aligned, total - aligned


def _sample_invalid_occurrences(calendar_row, lower, upper, valid_from, valid_until,
                                exception_lookup, holiday_dates, holiday_years, limit=5):
    ranges = []
    if valid_from is not None and lower < min(upper, valid_from):
        ranges.append((lower, min(upper, valid_from)))
    if valid_until is not None and max(lower, valid_until) < upper:
        ranges.append((max(lower, valid_until), upper))
    samples = []
    for start, end in ranges:
        service_day = start
        while service_day < end and len(samples) < limit:
            if calendar_operates(calendar_row, service_day, exception_lookup, holiday_dates, holiday_years):
                samples.append(service_day.isoformat())
            service_day += timedelta(days=1)
        if len(samples) == limit:
            break
    return samples


def audit_history_alignment(data, manifest, rail_history):
    """Audit canonical occurrences against rail-history without inferring routes.

    A timetable occurrence keeps its Asia/Tokyo service date at every stop,
    including stops whose clock time has a positive day_offset.  Direct
    historical station identities can therefore be checked conclusively.
    A trip line can be proven only by its explicit history/current reference;
    name/operator matches remain non-authoritative candidates.
    """
    exceptions_by_calendar = defaultdict(list)
    exception_lookup = {}
    for row in data["calendar_exceptions"]:
        exceptions_by_calendar[row["calendar_id"]].append(row)
        exception_lookup[(row["calendar_id"], row["service_date"])] = row["exception_type"]
    holiday_dates = {row["service_date"] for row in data["holiday_dates"]}
    holiday_years = {row["year"]: row["status"] for row in data["holiday_calendar_years"]}
    stations = {row["station_id"]: row for row in data["station_identities"]}
    stops_by_trip = defaultdict(list)
    for row in data["stop_times"]:
        stops_by_trip[row["trip_id"]].append(row)
    route_verdicts = route_attestations(data, manifest, rail_history=rail_history)

    history_stations = {}
    for feature in rail_history.get("stations", []):
        properties = feature.get("properties", {})
        history_id = properties.get("history_id")
        if history_id:
            history_stations[history_id] = properties

    findings = []
    occurrence_total = 0
    trips_with_occurrences = 0
    station_checks = 0
    line_checks = 0
    versions = {row["timetable_version_id"]: row for row in data["timetable_versions"]}
    calendars = {row["calendar_id"]: row for row in data["calendars"]}
    for trip in sorted(data["trips"], key=lambda row: row["trip_id"]):
        version, calendar_row, lower, upper = _trip_occurrence_context(
            data, trip, versions=versions, calendars=calendars)
        trip_occurrences = _operating_day_count(
            calendar_row, version, lower, upper, exceptions_by_calendar, holiday_dates)
        occurrence_total += trip_occurrences
        if trip_occurrences == 0:
            continue
        trips_with_occurrences += 1

        seen_station_ids = set()
        for stop in sorted(stops_by_trip[trip["trip_id"]], key=lambda row: row["stop_sequence"]):
            station = stations[stop["station_id"]]
            if station["station_id"] in seen_station_ids or station["reference_kind"] != "historical_overlay":
                continue
            seen_station_ids.add(station["station_id"])
            station_checks += 1
            history_id = station.get("rail_history_id")
            properties = history_stations.get(history_id)
            base = {
                "kind": "station",
                "tripId": trip["trip_id"],
                "stationId": station["station_id"],
                "railHistoryId": history_id,
                "occurrenceCount": trip_occurrences,
            }
            if properties is None:
                findings.append(dict(base, status="error", reason="rail_history_station_not_found"))
                continue
            valid_from, valid_until, source_field = rail_history_service_interval(
                properties, f"rail-history station {history_id}")
            total, aligned, invalid = _occurrence_alignment(
                calendar_row, version, lower, upper, valid_from, valid_until,
                exceptions_by_calendar, holiday_dates)
            detail = dict(
                base,
                status="aligned" if invalid == 0 else "error",
                reason="all_occurrences_within_service_validity" if invalid == 0 else "historical_station_outside_service_validity",
                alignedOccurrenceCount=aligned,
                invalidOccurrenceCount=invalid,
                validitySource=source_field,
                validFrom=valid_from.isoformat() if valid_from else None,
                validUntil=valid_until.isoformat() if valid_until else None,
            )
            if invalid:
                detail["sampleInvalidServiceDates"] = _sample_invalid_occurrences(
                    calendar_row, lower, upper, valid_from, valid_until,
                    exception_lookup, holiday_dates, holiday_years)
            findings.append(detail)

        route_verdict = route_verdicts[trip["trip_id"]]
        segments = route_verdict["segments"]
        if not segments:
            findings.append({
                "kind": "route",
                "tripId": trip["trip_id"],
                "status": route_verdict["status"],
                "reason": route_verdict["reason"],
                "occurrenceCount": trip_occurrences,
                "canPublishRouteLines": False,
            })
            continue
        for segment_verdict in segments:
            line_checks += 1
            findings.append(dict(
                segment_verdict,
                kind="route",
                canPublishRouteLines=segment_verdict["status"] == "aligned",
            ))

    status_counts = Counter(row["status"] for row in findings)
    return {
        "schemaVersion": manifest["schema_version"],
        "asOfDate": manifest["as_of_date"],
        "timezone": manifest["timezone"],
        "serviceDateSemantics": "Asia/Tokyo operating day; stop day_offset does not change the service date",
        "intervalSemantics": "[validFrom, validUntil)",
        "railHistoryRevision": rail_history.get("revision"),
        "tripTemplates": len(data["trips"]),
        "tripTemplatesWithOccurrences": trips_with_occurrences,
        "dailyOccurrencesChecked": occurrence_total,
        "historicalStationChecks": station_checks,
        "lineSegmentChecks": line_checks,
        "publishableRouteTrips": sum(
            1 for row in route_verdicts.values() if row["canPublishRouteLines"]),
        "alignedChecks": status_counts.get("aligned", 0),
        "unverifiedChecks": status_counts.get("unverified", 0),
        "errorChecks": status_counts.get("error", 0),
        "complete": bool(findings) and not status_counts.get("unverified", 0) and not status_counts.get("error", 0),
        "routeAttestations": [route_verdicts[key] for key in sorted(route_verdicts)],
        "findings": findings,
    }


def coverage_report(canonical_dir, database_path=None):
    manifest = load_manifest(canonical_dir)
    data, origins = load_dataset(canonical_dir, manifest)
    errors = validate_dataset(data, origins, manifest)
    if errors:
        raise DatasetError("canonical timetable validation failed:\n" + "\n".join(f"- {error}" for error in errors))
    database_path = database_path or canonical_dir / manifest["database_path"]
    declarations = {(r["operator_scope"], r["year"], r["dimension"]): r for r in data["coverage_declarations"]}
    versions_by_id = {row["timetable_version_id"]: row for row in data["timetable_versions"]}
    trips_by_id = {row["trip_id"]: row for row in data["trips"]}
    stops_by_trip = defaultdict(list)
    lines_by_trip = defaultdict(list)
    facts_by_entity = defaultdict(list)
    for row in data["stop_times"]: stops_by_trip[row["trip_id"]].append(row)
    for row in data["trip_line_segments"]: lines_by_trip[row["trip_id"]].append(row)
    for row in data["fact_sources"]: facts_by_entity[(row["entity_type"], row["entity_id"])].append(row)

    def observed_count(scope_name, year, dimension):
        year_start, year_end = date(year, 1, 1), date(year + 1, 1, 1)
        relevant = []
        for trip in data["trips"]:
            version = versions_by_id.get(trip["timetable_version_id"])
            if version is None or version["operator_scope"] != scope_name:
                continue
            if strict_date(version["effective_from"], "version.from") < year_end and strict_date(version["effective_until"], "version.until") > year_start:
                relevant.append(trip)
        if dimension == "inventory": return len(relevant)
        if dimension == "train_number": return sum(1 for trip in relevant if trip.get("train_number") or trip.get("public_number"))
        if dimension == "calendar": return len({trip["calendar_id"] for trip in relevant})
        if dimension == "stops": return sum(len(stops_by_trip[trip["trip_id"]]) for trip in relevant)
        if dimension == "times": return sum(1 for trip in relevant for stop in stops_by_trip[trip["trip_id"]] if stop.get("arrival_time") is not None or stop.get("departure_time") is not None)
        if dimension == "route_lines": return sum(len(lines_by_trip[trip["trip_id"]]) for trip in relevant)
        if dimension == "station_refs": return len({stop["station_id"] for trip in relevant for stop in stops_by_trip[trip["trip_id"]]})
        if dimension == "provenance":
            return sum(len(facts_by_entity[("trip", trip["trip_id"])]) + sum(len(facts_by_entity[("stop_time", f"{trip['trip_id']}:{stop['stop_sequence']}")]) for stop in stops_by_trip[trip["trip_id"]]) for trip in relevant)
        return 0
    zeroes = [(r["operator_scope"], strict_date(r["valid_from"], "zero.from"), strict_date(r["valid_until"], "zero.until")) for r in data["verified_zero_service_intervals"]]
    matrix = []
    for scope in manifest["expected_coverage_scopes"]:
        scope_start = strict_date(scope["valid_from"], "scope.from")
        scope_end = strict_date(scope["valid_until"], "scope.until")
        for year in range(scope_start.year, (scope_end - timedelta(days=1)).year + 1):
            part_start, part_end = _full_year_or_scope_part(year, scope_start, scope_end)
            for dimension in manifest["coverage_dimensions"]:
                declaration = declarations.get((scope["operator_scope"], year, dimension))
                if declaration:
                    declared_status = declaration["status"]
                    declared_count = declaration.get("record_count", 0)
                    observed = observed_count(scope["operator_scope"], year, dimension)
                    # A declaration is a claim, not proof.  It can only become
                    # effective verified coverage when the canonical rows can
                    # substantiate at least its claimed count and cite a source.
                    if declared_status == "verified" and (not declaration.get("source_id") or observed < declared_count or observed == 0):
                        status = "partial"
                    else:
                        status = declared_status
                    count = observed
                elif any(name == scope["operator_scope"] and start <= part_start and end >= part_end for name, start, end in zeroes):
                    status, count = "verified_no_service", 0
                else:
                    status, count = "missing", 0
                matrix.append({"operatorScope": scope["operator_scope"], "year": year, "dimension": dimension, "status": status, "recordCount": count, "declaredStatus": declaration["status"] if declaration else None})
    per_operator = {}
    for scope in manifest["expected_coverage_scopes"]:
        rows = [row for row in matrix if row["operatorScope"] == scope["operator_scope"]]
        per_operator[scope["operator_scope"]] = dict(sorted(Counter(row["status"] for row in rows).items()))
    per_year = {}
    for year in range(strict_date(manifest["first_scope_date"], "first_scope_date").year, strict_date(manifest["as_of_date"], "as_of_date").year + 1):
        rows = [row for row in matrix if row["year"] == year]
        statuses = Counter(row["status"] for row in rows)
        per_year[str(year)] = {"statusCounts": dict(sorted(statuses.items())), "complete": bool(rows) and set(statuses) <= {"verified", "verified_no_service"}}
    versions = data["timetable_versions"]
    counts = {entity: len(data[entity]) for entity in FIELDS}
    occurrence_count = 0
    first = strict_date(manifest["first_scope_date"], "first_scope_date")
    last = strict_date(manifest["as_of_date"], "as_of_date")
    calendars_by_id = {row["calendar_id"]: row for row in data["calendars"]}
    exceptions_by_calendar = defaultdict(list)
    for row in data["calendar_exceptions"]: exceptions_by_calendar[row["calendar_id"]].append(row)
    holiday_dates = {row["service_date"] for row in data["holiday_dates"]}
    occurrence_cache = {}
    exception_lookup = {(row['calendar_id'], row['service_date']): row['exception_type']
                        for row in data['calendar_exceptions']}
    holiday_years = {row['year']: row['status'] for row in data['holiday_calendar_years']}
    evidence_days = defaultdict(set)
    evidence_days_by_trip = defaultdict(list)
    for trip in data["trips"]:
        key = (trip["timetable_version_id"], trip["calendar_id"])
        if key not in occurrence_cache:
            calendar_row = calendars_by_id[trip['calendar_id']]
            version = versions_by_id[trip['timetable_version_id']]
            start = max(first, date.fromisoformat(calendar_row['valid_from']),
                        date.fromisoformat(version['effective_from']))
            end = min(last + timedelta(days=1), date.fromisoformat(calendar_row['valid_until']),
                      date.fromisoformat(version['effective_until']))
            days = set()
            # Explicit-date calendars need no scan across the edition envelope.
            if not any(calendar_row[name] for name in
                       ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')):
                candidates = (date.fromisoformat(row['service_date'])
                              for row in exceptions_by_calendar[calendar_row['calendar_id']]
                              if row['exception_type'] == 'add')
            else:
                candidates = (start + timedelta(days=offset) for offset in range(max(0, (end-start).days)))
            for day in candidates:
                if start <= day < end and calendar_operates(calendar_row, day, exception_lookup, holiday_dates, holiday_years):
                    days.add(day)
            occurrence_cache[key] = days
        days = occurrence_cache[key]
        scope_name = versions_by_id[trip['timetable_version_id']]['operator_scope']
        evidence_days[scope_name].update(days)
        evidence_days_by_trip[scope_name].append(days)
        occurrence_count += len(days)
    all_evidence_days = set().union(*evidence_days.values()) if evidence_days else set()
    per_operator_evidence = {}
    for scope in manifest['expected_coverage_scopes']:
        name = scope['operator_scope']
        start = max(first, date.fromisoformat(scope['valid_from']))
        end = min(last + timedelta(days=1), date.fromisoformat(scope['valid_until']))
        scoped_days = {day for day in evidence_days[name] if start <= day < end}
        days = sorted(scoped_days)
        scoped_trip_days = [trip_days.intersection(scoped_days) for trip_days in evidence_days_by_trip[name]]
        ranges = []
        for day in days:
            if ranges and ranges[-1]['validUntil'] == day.isoformat():
                ranges[-1]['validUntil'] = (day + timedelta(days=1)).isoformat()
            else:
                ranges.append({'validFrom': day.isoformat(), 'validUntil': (day + timedelta(days=1)).isoformat()})
        per_operator_evidence[name] = {
            'tripTemplatesWithOccurrences': sum(bool(trip_days) for trip_days in scoped_trip_days),
            'dailyOccurrencesRepresented': sum(len(trip_days) for trip_days in scoped_trip_days),
            'distinctServiceDatesWithEvidence': len(days),
            'scopeServiceDates': max(0, (end-start).days),
            'firstServiceDateWithEvidence': days[0].isoformat() if days else None,
            'lastServiceDateWithEvidence': days[-1].isoformat() if days else None,
            'serviceDateRangesWithEvidence': ranges,
            'completeDailyInventory': False,
        }
    source_paths = entity_paths(canonical_dir, manifest["entities"]["source_documents"])
    history = json.loads(RAIL_HISTORY.read_text(encoding="utf-8"))
    try:
        import subprocess
        commit_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip()
    except Exception:
        commit_sha = "unknown"
    missing = sum(1 for row in matrix if row["status"] == "missing")
    partial = sum(1 for row in matrix if row["status"] in {"partial", "source_gap", "license_blocked", "conflict"})
    jr_scope_names = [scope["operator_scope"] for scope in manifest["expected_coverage_scopes"] if scope["operator_scope"] != "jr-ancestral-national-railways"]
    last_covered_until = max((row["effective_until"] for row in versions), default=None)
    return {
        "schemaVersion": manifest["schema_version"],
        "commitSHA": commit_sha,
        "asOfDate": manifest["as_of_date"],
        "databaseHash": file_sha256(database_path) if database_path.exists() else None,
        "sourceRegistryHash": files_fingerprint(source_paths),
        "canonicalSourceHash": source_fingerprint(canonical_dir, manifest),
        "railHistoryRevision": history.get("revision"),
        "railHistoryHash": file_sha256(RAIL_HISTORY),
        "stationPackageHash": file_sha256(JP_PACKAGE),
        "solverVersion": manifest.get("solver_version"),
        "routeAuditStatus": "not_run",
        "operatorsExpected": len(jr_scope_names),
        "operatorsCovered": sum(1 for name in jr_scope_names
                                if per_operator[name] and set(per_operator[name]) <= {'verified', 'verified_no_service'}),
        "expectedCoverageScopes": len(manifest["expected_coverage_scopes"]),
        "serviceFamilies": counts["services"],
        "timetableVersions": counts["timetable_versions"],
        "tripTemplates": counts["trips"],
        "dailyOccurrencesRepresented": occurrence_count,
        "calendarRules": counts["calendars"],
        "calendarExceptions": counts["calendar_exceptions"],
        "stopTimes": counts["stop_times"],
        "firstCoveredDate": min(all_evidence_days).isoformat() if all_evidence_days else None,
        "lastCoveredUntil": last_covered_until,
        "lastCoveredDate": max(all_evidence_days).isoformat() if all_evidence_days else None,
        "firstTimetableEffectiveDate": min((row['effective_from'] for row in versions), default=None),
        "dailyEvidenceSemantics": "Dates attest at least one represented planned trip, not a complete daily inventory or actual operation. Ranges are half-open.",
        "perOperatorDailyEvidence": per_operator_evidence,
        "verifiedZeroServiceIntervals": data["verified_zero_service_intervals"],
        "unresolvedSources": sum(1 for row in data["research_queue"] if row["missing_dimension"] in {"source", "timetable_issue"} and row["status"] != "resolved"),
        "unresolvedStations": sum(1 for row in data["research_queue"] if row["missing_dimension"] == "station_refs" and row["status"] != "resolved"),
        "unresolvedRoutes": sum(1 for row in data["research_queue"] if row["missing_dimension"] == "route_lines" and row["status"] != "resolved"),
        "conflicts": sum(1 for row in data["fact_completeness"] if row["status"] == "conflict"),
        "licenseBlockedSources": [row["source_id"] for row in data["source_documents"] if row["license_status"] in {"license_blocked", "explicit_reproduction_and_processing_prohibition"} or row["redistribution_status"] in {"prohibited", "license_blocked"}],
        "verificationOnlySources": [row["source_id"] for row in data["source_documents"] if row["redistribution_status"] == "verification_only"],
        "perOperatorCoverage": per_operator,
        "perYearCoverage": per_year,
        "coverageMatrix": matrix,
        "missingCoverageCells": missing,
        "partialOrBlockedCoverageCells": partial,
        "coverageComplete": counts["trips"] > 0 and missing == 0 and partial == 0,
    }


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def build_projection(canonical_dir, legacy_path=DEFAULT_LEGACY, output=None, audit_output=None):
    manifest = load_manifest(canonical_dir)
    data, origins = load_dataset(canonical_dir, manifest)
    errors = validate_dataset(data, origins, manifest)
    if errors:
        raise DatasetError("canonical timetable validation failed:\n" + "\n".join(f"- {error}" for error in errors))
    services = {row["service_id"]: row for row in data["services"]}
    stations = {row["station_id"]: row for row in data["station_identities"]}
    versions = {row["timetable_version_id"]: row for row in data["timetable_versions"]}
    names = defaultdict(list)
    for row in data["service_name_periods"]:
        names[row["service_id"]].append(row)
    stops = defaultdict(list)
    lines = defaultdict(list)
    operator_segments = defaultdict(list)
    operators = {row["operator_id"]: row for row in data["operators"]}
    completeness = {(row["entity_type"], row["entity_id"], row["dimension"]): row for row in data["fact_completeness"]}
    for row in data["stop_times"]: stops[row["trip_id"]].append(row)
    for row in data["trip_line_segments"]: lines[row["trip_id"]].append(row)
    for row in data["trip_operator_segments"]: operator_segments[row["trip_id"]].append(row)
    groups = {}
    for trip in data["trips"]:
        ordered_stops = sorted(stops[trip["trip_id"]], key=lambda row: row["stop_sequence"])
        passenger = [row for row in ordered_stops if row["call_type"] in {"origin", "passenger_stop", "destination"}]
        ordered_lines = sorted(lines[trip["trip_id"]], key=lambda row: row["sequence"])
        version = versions[trip["timetable_version_id"]]
        # The effective interval is part of the signature.  Separate revisions
        # and gaps must never be bridged into one apparently continuous pattern.
        signature = (trip["service_id"], trip["origin_station_id"], trip["destination_station_id"], tuple(row["station_id"] for row in passenger), tuple((row["line_name"], row["operator_id"]) for row in ordered_lines), version["effective_from"], version["effective_until"])
        groups.setdefault(signature, []).append(trip)
    derived = []
    for signature, trips in sorted(groups.items(), key=lambda item: canonical_json(item[0])):
        sample = sorted(trips, key=lambda row: row["trip_id"])[0]
        version_rows = [versions[row["timetable_version_id"]] for row in trips]
        valid_from = signature[5]
        valid_until = signature[6]
        digest = hashlib.sha256(canonical_json(signature).encode("utf-8")).hexdigest()[:12]
        service = services[sample["service_id"]]
        applicable_names = [row for row in names[sample["service_id"]] if row["valid_from"] <= valid_from and (row.get("valid_until") is None or valid_from < row["valid_until"])]
        name = sorted(applicable_names, key=lambda row: (row["name_type"] != "official", row["language"] != "ja", row["name"]))[0]["name"] if applicable_names else service["canonical_name"]
        passenger_ids = signature[3]
        def station_ref(station_id):
            station = stations[station_id]
            result = {"name": station["name_snapshot"]}
            if station["reference_kind"] == "current_n02": result["sourceCode"] = station["current_source_code"]
            else: result["historyId"] = station["rail_history_id"]
            return result
        refs = [station_ref(value) for value in passenger_ids]
        trip_ids = sorted(row["trip_id"] for row in trips)
        operator_ids = []
        for trip_id in trip_ids:
            operator_ids.extend(row["operator_id"] for row in sorted(operator_segments[trip_id], key=lambda row: row["from_sequence"]))
        legal_names = []
        for operator_id in operator_ids:
            if operator_id in operators:
                legal_name = operators[operator_id]["legal_name"]
                if legal_name not in legal_names: legal_names.append(legal_name)
        def projected_level(dimension, has_rows=True):
            statuses = [completeness.get(("trip", trip_id, dimension), {}).get("status", "unknown") for trip_id in trip_ids]
            if has_rows and statuses and all(status == "verified" for status in statuses): return "complete"
            if has_rows and any(status in {"verified", "partial"} for status in statuses): return "partial"
            return "missing"
        derived.append({
            "patternId": f"tt-{sample['service_id']}-{digest}", "serviceId": sample["service_id"],
            "name": name, "company": "/".join(legal_names) if legal_names else "未解決",
            "label": f"{refs[0]['name']}〜{refs[-1]['name']}", "origin": refs[0]["name"],
            "destination": refs[-1]["name"], "stops": refs, "optionalStops": [], "via": [],
            "lines": [item[0] for item in signature[4]], "validFrom": valid_from,
            "validUntil": valid_until, "completeness": {"stops": projected_level("stops", bool(passenger_ids)), "lines": projected_level("route_lines", bool(signature[4])), "validity": "partial"},
            "confidence": "medium", "source": "generated:train-service-history",
            "_derivation": {"status": "canonical_trip_projection", "tripIds": trip_ids, "warning": "Legacy Pattern cannot express operating calendars or exact service dates; query the timetable database for date-correct trips."},
        })
    fallback = []
    if legacy_path and legacy_path.exists():
        for row in json.loads(legacy_path.read_text(encoding="utf-8")):
            copy = deepcopy(row)
            copy["_derivation"] = {"status": "legacy_unverified_fallback", "reason": "canonical timetable coverage is not yet sufficient for this service"}
            fallback.append(copy)
    result = sorted(derived + fallback, key=lambda row: row["patternId"])
    output = output or canonical_dir / manifest["projection_path"]
    audit_output = audit_output or canonical_dir / manifest["projection_audit_path"]
    write_json(output, result)
    write_json(audit_output, {
        "schemaVersion": manifest["schema_version"], "asOfDate": manifest["as_of_date"],
        "canonicalSourceHash": source_fingerprint(canonical_dir, manifest),
        "canonicalPatternCount": len(derived), "legacyUnverifiedFallbackCount": len(fallback),
        "safeToReplaceBundledLegacyCatalog": bool(derived) and not fallback,
        "outputHash": file_sha256(output),
    })
    return output, audit_output


def normalize_candidate(entity, input_path, output_path=None):
    if entity not in FIELDS:
        raise DatasetError(f"unknown entity {entity!r}")
    raw = input_path.read_text(encoding="utf-8")
    try:
        parsed = json.loads(raw)
        rows = parsed if isinstance(parsed, list) else [parsed]
    except json.JSONDecodeError:
        rows = [json.loads(line) for line in raw.splitlines() if line.strip()]
    required, optional = FIELDS[entity]
    failures = []
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            failures.append(f"row {index}: expected object"); continue
        if required - set(row): failures.append(f"row {index}: missing {sorted(required - set(row))}")
        if set(row) - required - optional: failures.append(f"row {index}: unknown {sorted(set(row) - required - optional)}")
    if failures:
        raise DatasetError("candidate shape validation failed:\n" + "\n".join(failures))
    text = "".join(canonical_json(row) + "\n" for row in sorted(rows, key=canonical_json))
    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--canonical-dir", type=Path, default=DEFAULT_CANONICAL)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate")
    build = subparsers.add_parser("build")
    build.add_argument("--output", type=Path)
    audit = subparsers.add_parser("audit-coverage")
    audit.add_argument("--database", type=Path)
    audit.add_argument("--output", type=Path)
    day = subparsers.add_parser("materialize")
    day.add_argument("service_date")
    projection = subparsers.add_parser("build-patterns")
    projection.add_argument("--legacy", type=Path, default=DEFAULT_LEGACY)
    projection.add_argument("--output", type=Path)
    projection.add_argument("--audit-output", type=Path)
    normalize = subparsers.add_parser("normalize")
    normalize.add_argument("entity", choices=sorted(FIELDS))
    normalize.add_argument("input", type=Path)
    normalize.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        manifest = load_manifest(args.canonical_dir)
        if args.command == "validate":
            data, origins = load_dataset(args.canonical_dir, manifest)
            errors = validate_dataset(data, origins, manifest)
            if errors: raise DatasetError("canonical timetable validation failed:\n" + "\n".join(f"- {error}" for error in errors))
            print(f"Validated {sum(map(len, data.values()))} canonical timetable records.")
        elif args.command == "build":
            output, _, _ = build_database(args.canonical_dir, args.output)
            print(f"Built {output} ({file_sha256(output)}).")
        elif args.command == "audit-coverage":
            report = coverage_report(args.canonical_dir, args.database)
            output = args.output or args.canonical_dir / manifest["coverage_report_path"]
            write_json(output, report)
            print(f"Wrote {output}; coverageComplete={report['coverageComplete']} missing={report['missingCoverageCells']}.")
        elif args.command == "materialize":
            data, origins = load_dataset(args.canonical_dir, manifest)
            errors = validate_dataset(data, origins, manifest)
            if errors: raise DatasetError("canonical timetable validation failed:\n" + "\n".join(errors))
            print(json.dumps(materialize(data, args.service_date), ensure_ascii=False, sort_keys=True, indent=2))
        elif args.command == "build-patterns":
            output, audit_output = build_projection(args.canonical_dir, args.legacy, args.output, args.audit_output)
            print(f"Wrote {output} and {audit_output}.")
        elif args.command == "normalize":
            normalize_candidate(args.entity, args.input, args.output)
        return 0
    except (DatasetError, OSError, sqlite3.Error, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


def wrapper_main(command, argv=None):
    """Entry point for the small command-specific scripts in this directory."""
    argv = list(sys.argv[1:] if argv is None else argv)
    prefix = []
    if "--canonical-dir" in argv:
        index = argv.index("--canonical-dir")
        if index + 1 >= len(argv):
            print("error: --canonical-dir requires a value", file=sys.stderr)
            return 2
        prefix = argv[index:index + 2]
        del argv[index:index + 2]
    return main(prefix + [command] + argv)


if __name__ == "__main__":
    sys.exit(main())
