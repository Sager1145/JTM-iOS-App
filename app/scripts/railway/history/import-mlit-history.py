#!/usr/bin/env python3
"""Import MLIT's official railway opening/closure tables without guessing selectors.

The two Railway Bureau PDFs are the authoritative row inventories.  This tool
extracts their table cells, converts Japanese era dates to ISO exact-day dates,
and writes review inputs under app/data/jp-history-sources/.  Every new row is
deliberately `unresolved`: an official name is not proof that the current N02
operator/line identity or its geometry selector has been reviewed.

The importer does not consume N05.  MLIT labels N05 noncommercial and says it
incorporates JTB's ``停車場変遷大辞典``.  The source registry records that
restriction, but N05 data must not be bundled into this app.

Requires pypdf >= 6 for PDF import.  Schema/check-only validation has no third
party dependency.

Examples:
  python3 app/scripts/railway/history/import-mlit-history.py \
    --openings-pdf /tmp/openings.pdf --closures-pdf /tmp/closures.pdf
  python3 app/scripts/railway/history/import-mlit-history.py --check
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import json
import re
import sys
import tempfile
import urllib.request
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
DEFAULT_OUTPUT = ROOT / "app/data/jp-history-sources"
DEFAULT_REVIEW_LEDGER = DEFAULT_OUTPUT / "reviewed-mlit-row-selectors.json"

OPENINGS_URL = "https://www.mlit.go.jp/statistics/details/content/001884569.pdf"
CLOSURES_URL = "https://www.mlit.go.jp/statistics/details/content/001737586.pdf"
STATISTICS_URL = "https://www.mlit.go.jp/statistics/details/tetsudo_list.html"
AS_OF = "2026-04-01"

TABLES = {
    "openings": {
        "title": "鉄軌道開業一覧（平成5年度以降）",
        "kind": "opening",
        "url": OPENINGS_URL,
        "filename": "mlit-openings.json",
        "expected_rows": 121,
        "inventory_sha256": "52681e7b91b2c6e2c42cff960d737fe69878d93be61d780a7a96aaaf5ffcfce5",
        # x positions in the PDF's unscaled table coordinate system.
        "bounds": (45, 130, 215, 283, 365, 405),
    },
    "closures": {
        "title": "鉄軌道の廃止実績（平成5年度以降）",
        "kind": "closure",
        "url": CLOSURES_URL,
        "filename": "mlit-closures.json",
        "expected_rows": 78,
        "inventory_sha256": "cddef0d6dba9df5308511b70e0488efc8b3610b3f59400d49b4bd1ff5747d575",
        "bounds": (50, 140, 220, 295, 380, 415),
    },
}

ERA_DATE = re.compile(r"^(平|令)(\d+)\.(\d+)\.(\d+)$")
ERA_DATE_SEARCH = re.compile(r"(?:平|令)(?:元|\d+)\.\d+\.\d+")
FISCAL_YEAR = re.compile(r"^(平成|令和)(\d+|元)年度$")
SCHEMA_VERSION = "1"


def fail(message: str) -> None:
    raise SystemExit(message)


def compact(value: str) -> str:
    return re.sub(r"[\s\u3000]+", "", value or "")


def era_day(value: str) -> str:
    value = compact(value).replace("元", "1")
    match = ERA_DATE.fullmatch(value)
    if not match:
        fail(f"unrecognized Japanese era date: {value!r}")
    era, year, month, day = match.groups()
    western = int(year) + (1988 if era == "平" else 2018)
    return dt.date(western, int(month), int(day)).isoformat()


def fiscal_year(value: str) -> int:
    value = compact(value)
    match = FISCAL_YEAR.fullmatch(value)
    if not match:
        fail(f"unrecognized Japanese fiscal year: {value!r}")
    era, year = match.groups()
    ordinal = 1 if year == "元" else int(year)
    return ordinal + (1988 if era == "平成" else 2018)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


INVENTORY_FINGERPRINT_KEYS = (
    "source_row_id", "source_page", "fiscal_year", "official_line_name",
    "official_operator_name", "from_station_name", "to_station_name",
    "length_km", "effective_date", "kind", "source_cells",
)


def inventory_fingerprint(rows) -> str:
    """Hash the ordered official row identities, independent of review fields."""
    identities = [{key: row.get(key) for key in INVENTORY_FINGERPRINT_KEYS} for row in rows]
    encoded = json.dumps(
        identities, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def selector_status_counts(rows) -> dict[str, int]:
    return dict(sorted(Counter(row["selector"]["status"] for row in rows).items()))


def reviewed_selector(review) -> dict:
    """Materialize one ledger decision into an inventory-row selector."""
    selector = copy.deepcopy(review["selector"])
    selector["review_event_id"] = review["event_id"]
    selector["review_source_row_id"] = review["source_row_id"]
    selector["evidence_references"] = [item["reference"] for item in review["evidence"]]
    return selector


def validate_selector_review_ledger(payload, inventories, label="reviewed MLIT row selectors"):
    """Validate explicit review decisions against exact official source rows.

    An official-event link alone is deliberately insufficient. Every resolved
    row must be named in this ledger with verified status, primary exact-day
    evidence, and an explicit reviewed geometry selector.
    """
    if payload.get("schema_version") != SCHEMA_VERSION:
        fail(f"{label}: unsupported schema_version")
    official = {
        row["source_row_id"]: row
        for rows in inventories.values()
        for row in rows
    }
    reviews = payload.get("reviews")
    if not isinstance(reviews, list) or not reviews:
        fail(f"{label}: non-empty reviews required")
    seen_rows = set()
    seen_events = set()
    allowed_scopes = {
        "whole_identity", "legacy_release_geometry", "isolated_historical_segment",
        "isolated_current_segment",
    }
    for review in reviews:
        source_row_id = review.get("source_row_id")
        event_id = review.get("event_id")
        if not source_row_id or source_row_id in seen_rows:
            fail(f"{label}: source row ids must be present and unique")
        if not event_id or event_id in seen_events:
            fail(f"{label}: event ids must be present and unique")
        seen_rows.add(source_row_id)
        seen_events.add(event_id)
        row = official.get(source_row_id)
        if row is None:
            fail(f"{label}: {event_id} references unknown official row {source_row_id}")
        if review.get("kind") != row["kind"]:
            fail(f"{label}: {event_id} kind does not match {source_row_id}")
        if review.get("official_effective_date") != row["effective_date"]:
            fail(f"{label}: {event_id} date does not match {source_row_id}")
        if review.get("review", {}).get("status") != "verified":
            fail(f"{label}: {event_id} is not verified")
        evidence = review.get("evidence")
        if (not isinstance(evidence, list) or not evidence
                or not all(item.get("authority") and item.get("reference")
                           and item.get("date_precision") == "exact_day"
                           for item in evidence)):
            fail(f"{label}: {event_id} needs primary exact-day evidence")
        selector = review.get("selector")
        if not isinstance(selector, dict) or selector.get("status") != "resolved":
            fail(f"{label}: {event_id} needs a resolved selector")
        if selector.get("scope") not in allowed_scopes:
            fail(f"{label}: {event_id} has unsupported selector scope")
        if not selector.get("line_name") or not selector.get("operator"):
            fail(f"{label}: {event_id} selector needs N02 line/operator identity")
        if selector["scope"] != "whole_identity" and not selector.get("release"):
            fail(f"{label}: {event_id} isolated selector needs a source release")
    return reviews


def apply_selector_review_ledger(inventories, payload) -> None:
    """Replay reviewed selectors without promoting any unlisted source row."""
    reviews = validate_selector_review_ledger(payload, inventories)
    official = {
        row["source_row_id"]: row
        for rows in inventories.values()
        for row in rows
    }
    for review in reviews:
        official[review["source_row_id"]]["selector"] = reviewed_selector(review)
    for rows in inventories.values():
        for row in rows:
            if row["selector"]["status"] == "resolved" and row["source_row_id"] not in {
                    review["source_row_id"] for review in reviews}:
                fail(f"unreviewed row was resolved: {row['source_row_id']}")


def reconcile_selector_reviews(inventories, payload, label="reviewed MLIT row selectors") -> None:
    """Require checked-in resolved rows to equal the review ledger exactly."""
    reviews = validate_selector_review_ledger(payload, inventories, label)
    expected = {review["source_row_id"]: reviewed_selector(review) for review in reviews}
    actual = {
        row["source_row_id"]: row["selector"]
        for rows in inventories.values()
        for row in rows
        if row["selector"]["status"] == "resolved"
    }
    if set(actual) != set(expected):
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        fail(f"{label}: resolved row set differs; missing={missing}, extra={extra}")
    for source_row_id, selector in expected.items():
        if actual[source_row_id] != selector:
            fail(f"{label}: {source_row_id} selector differs from reviewed decision")


def download(url: str, path: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "JTM-MLIT-history-import/1"})
    with urllib.request.urlopen(request, timeout=60) as response:  # nosec: official fixed URLs
        if response.status != 200:
            fail(f"{url}: HTTP {response.status}")
        path.write_bytes(response.read())


def pypdf_lines(path: Path):
    """Yield (one-based page, y, [{tx,text}, ...]) using rendered coordinates."""
    try:
        from pypdf import PdfReader
        from pypdf._page import ContentStream
        from pypdf._text_extraction import _layout_mode
    except ImportError:
        fail("PDF import requires pypdf >= 6 (`python3 -m pip install pypdf`)")

    reader = PdfReader(str(path))
    for page_number, page in enumerate(reader.pages, 1):
        fonts = page._layout_mode_fonts()
        operations = iter(ContentStream(page["/Contents"].get_object(), page.pdf, "bytes").operations)
        text_ops = _layout_mode.text_show_operations(operations, fonts, True, None)
        groups = _layout_mode.y_coordinate_groups(text_ops, None)
        for y, group in groups.items():
            yield page_number, y, sorted(group, key=lambda item: item["tx"])


def split_cells(group, bounds):
    line_end, operator_end, from_end, separator_end, to_end, km_end = bounds
    cells = {name: [] for name in ("fiscal", "line", "operator", "from", "to", "km", "date")}
    for item in group:
        x = float(item["tx"])
        text = compact(item["text"])
        if not text or text == "～":
            continue
        if x < line_end:
            key = "fiscal"
        elif x < operator_end:
            key = "line"
        elif x < from_end:
            key = "operator"
        elif x < separator_end:
            key = "from"
        elif x < to_end:
            key = "to"
        elif x < km_end:
            key = "km"
        else:
            key = "date"
        cells[key].append(text)
    return {key: "".join(value) for key, value in cells.items()}


def append_continuation(row, cells):
    for key in ("line", "operator", "from", "to"):
        if cells[key]:
            row[key] += cells[key]


def parse_table(path: Path, table_name: str, retrieved_at: str):
    spec = TABLES[table_name]
    raw_rows = []
    active = None
    active_page = None
    page_counts = Counter()
    dated_source_rows_seen = 0

    def finish():
        nonlocal active
        if active is not None:
            raw_rows.append(active)
            page_counts[active["source_page"]] += 1
            active = None

    for page, _y, group in pypdf_lines(path):
        if active_page is not None and page != active_page:
            finish()
        active_page = page
        group_text = compact("".join(item["text"] for item in group))
        dates_in_group = ERA_DATE_SEARCH.findall(group_text)
        if len(dates_in_group) > 1:
            fail(f"{table_name} page {page}: multiple effective dates in one rendered row")
        cells = split_cells(group, spec["bounds"])
        date_text = compact(cells["date"]).replace("元", "1")
        is_source_row = ERA_DATE.fullmatch(date_text) is not None
        if dates_in_group:
            dated_source_rows_seen += 1
            if not is_source_row:
                fail(
                    f"{table_name} page {page}: date-bearing source row was not "
                    "captured in the date column"
                )
        if is_source_row:
            finish()
            active = {
                "source_page": page,
                "fiscal": cells["fiscal"],
                "line": cells["line"],
                "operator": cells["operator"],
                "from": cells["from"],
                "to": cells["to"],
                "km": cells["km"],
                "date": date_text,
            }
            continue
        if active is not None and any(cells[key] for key in ("line", "operator", "from", "to")):
            # Titles, headers, and notes either precede a source row or start in the
            # fiscal-year column. Only the four data columns extend an active row.
            append_continuation(active, cells)
    finish()

    if len(raw_rows) != spec["expected_rows"]:
        fail(f"{table_name}: extracted {len(raw_rows)} rows; expected {spec['expected_rows']}")
    if dated_source_rows_seen != spec["expected_rows"]:
        fail(
            f"{table_name}: saw {dated_source_rows_seen} date-bearing source rows; "
            f"expected {spec['expected_rows']}"
        )

    rows = []
    current_fiscal = None
    previous_operator = None
    for ordinal, raw in enumerate(raw_rows, 1):
        if raw["fiscal"]:
            current_fiscal = fiscal_year(raw["fiscal"])
        if current_fiscal is None:
            fail(f"{table_name} row {ordinal}: missing fiscal year context")
        operator_raw = compact(raw["operator"])
        operator = previous_operator if operator_raw == "〃" else operator_raw
        if not operator:
            fail(f"{table_name} row {ordinal}: missing operator")
        previous_operator = operator
        official_line_raw = compact(raw["line"])
        official_line = official_line_raw.removeprefix("※")
        if not all((official_line, raw["from"], raw["to"], raw["km"])):
            fail(f"{table_name} row {ordinal}: incomplete extracted cells: {raw}")
        try:
            length_km = float(raw["km"])
        except ValueError:
            fail(f"{table_name} row {ordinal}: bad operating km {raw['km']!r}")
        source_row_id = f"mlit-{table_name}-{AS_OF.replace('-', '')}:{ordinal:03d}"
        rows.append({
            "source_row_id": source_row_id,
            "source_page": raw["source_page"],
            "fiscal_year": current_fiscal,
            "official_line_name": official_line,
            "official_operator_name": operator,
            "from_station_name": compact(raw["from"]),
            "to_station_name": compact(raw["to"]),
            "length_km": length_km,
            "effective_date": era_day(raw["date"]),
            "kind": spec["kind"],
            "source_cells": {
                "line_name": official_line_raw,
                "operator_name": operator_raw,
                "date": raw["date"],
            },
            "selector": {
                "status": "unresolved",
                "line_name": official_line,
                "operator": operator,
                "reason": "Official row inventoried; canonical N02 identity and geometry scope require review.",
            },
        })

    validate_rows(rows, table_name)
    return {
        "schema_version": SCHEMA_VERSION,
        "source": {
            "source_id": f"mlit-{table_name}-{AS_OF.replace('-', '')}",
            "title": spec["title"],
            "publisher": "国土交通省 鉄道局 都市鉄道政策課",
            "landing_page_url": STATISTICS_URL,
            "url": spec["url"],
            "as_of": AS_OF,
            "retrieved_at": retrieved_at,
            "sha256": sha256(path),
            "extraction": "PDF table text cells grouped by rendered x/y coordinates with pypdf",
        },
        "inventory": {
            "row_count": len(rows),
            "date_bearing_source_row_count": dated_source_rows_seen,
            "row_identity_sha256": inventory_fingerprint(rows),
            "page_row_counts": {str(page): page_counts[page] for page in sorted(page_counts)},
            "selector_status_counts": selector_status_counts(rows),
        },
        "rows": rows,
    }


def validate_rows(rows, table_name):
    seen = set()
    for row in rows:
        required = (
            "source_row_id", "source_page", "fiscal_year", "official_line_name",
            "official_operator_name", "from_station_name", "to_station_name",
            "length_km", "effective_date", "kind", "selector",
        )
        missing = [key for key in required if key not in row]
        if missing:
            fail(f"{table_name}: {row.get('source_row_id', '?')} missing {missing}")
        if row["source_row_id"] in seen:
            fail(f"{table_name}: duplicate {row['source_row_id']}")
        seen.add(row["source_row_id"])
        try:
            dt.date.fromisoformat(row["effective_date"])
        except (TypeError, ValueError):
            fail(f"{table_name}: {row['source_row_id']} has invalid exact-day date")
        if row["selector"].get("status") not in {"unresolved", "resolved", "out_of_scope"}:
            fail(f"{table_name}: {row['source_row_id']} has unknown selector status")


def registry(retrieved_at: str):
    return {
        "schema_version": SCHEMA_VERSION,
        "retrieved_at": retrieved_at,
        "sources": [
            {
                "source_id": "mlit-railway-statistics",
                "publisher": "国土交通省 鉄道局",
                "url": STATISTICS_URL,
                "role": "Official index for opening and closure tables.",
                "licence_url": "https://www.mlit.go.jp/link.html",
                "licence": "PDL-1.0",
                "licence_note": "MLIT website content terms apply; derived rows retain source URLs and state that they were extracted.",
            },
            {
                "source_id": "mlit-n02-legacy-1996",
                "publisher": "国土交通省 国土計画局",
                "url": "https://nlftp.mlit.go.jp/ksj/old/datalist/old_KsjTmplt-N02.html",
                "metadata_url": "https://nlftp.mlit.go.jp/ksj/old/meta/N02/N02-07L/KS-META-N02-07L-2K.htm",
                "publication_date": "1996-12-31",
                "labelled_year": "平成7年",
                "downloads": [
                    {
                        "crs": "Tokyo Datum / geographic",
                        "version": "1.0",
                        "filename": "N02-07L-48-01.0.zip",
                        "url": "https://nlftp.mlit.go.jp/ksj/old/data/N02/N02-07L/N02-07L-48-01.0.zip",
                        "sha256": "17c00ca41e36b54af0437fbb15191895ebf7ffca6245d82bfc496ba5ebaabbfc",
                    },
                    {
                        "crs": "JGD2000 / geographic",
                        "version": "1.0a",
                        "filename": "N02-07L-48-01.1a.zip",
                        "url": "https://nlftp.mlit.go.jp/ksj/old/data/N02/N02-07L/N02-07L-48-01.1a.zip",
                        "sha256": "106509ab37025656fda7d8f9357fe8a20d2fcdb653fe5bf9f4c6ebd066aa07fa",
                    },
                ],
                "licence_url": "https://nlftp.mlit.go.jp/ksj/other/agreement_02.html",
                "licence_faq_url": "https://nlftp.mlit.go.jp/ksj/other/faq.html",
                "licence": "old-nlni-terms",
                "commercial_use_status": "not_asserted",
                "licence_note": "Legacy unified-format text: old National Land Numerical Information terms apply. The download page does not label this package CC BY 4.0; do not infer the current N02 licence.",
                "bundle_status": "not_bundled",
            },
            {
                "source_id": "mlit-n02-current-licence",
                "publisher": "国土交通省",
                "url": "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html",
                "licence_url": "https://nlftp.mlit.go.jp/ksj/other/agreement.html",
                "licence": "CC-BY-4.0 (2020 and later); commercial-use-allowed (earlier current-series releases)",
                "licence_note": "MLIT states CC BY 4.0 for 2020 and later N02 releases and commercial use allowed for earlier releases on this current-series page.",
            },
            {
                "source_id": "mlit-n05-railway-timeseries",
                "publisher": "国土交通省",
                "url": "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N05-2025.html",
                "licence_url": "https://nlftp.mlit.go.jp/ksj/other/agreement_02.html",
                "licence": "noncommercial",
                "licence_note": "MLIT explicitly restricts N05 to noncommercial use because JTB's 停車場変遷大辞典 is an underlying source.",
                "bundle_status": "prohibited_by_project_policy",
            },
        ],
    }


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def validate_checked_in(output_dir: Path) -> None:
    inventories = {}
    for table_name, spec in TABLES.items():
        path = output_dir / spec["filename"]
        if not path.exists():
            fail(f"missing checked-in inventory: {path}")
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("schema_version") != SCHEMA_VERSION:
            fail(f"{path}: unsupported schema_version")
        rows = payload.get("rows")
        if not isinstance(rows, list) or len(rows) != spec["expected_rows"]:
            fail(f"{path}: expected {spec['expected_rows']} rows")
        validate_rows(rows, table_name)
        recorded = payload.get("inventory", {}).get("row_count")
        if recorded != len(rows):
            fail(f"{path}: inventory row_count does not match rows")
        dated = payload.get("inventory", {}).get("date_bearing_source_row_count")
        if dated != spec["expected_rows"]:
            fail(f"{path}: date-bearing source-row count is incomplete")
        actual_fingerprint = inventory_fingerprint(rows)
        recorded_fingerprint = payload.get("inventory", {}).get("row_identity_sha256")
        if recorded_fingerprint != actual_fingerprint:
            fail(f"{path}: recorded row identity fingerprint does not match rows")
        if actual_fingerprint != spec["inventory_sha256"]:
            fail(f"{path}: official row inventory differs from the reviewed complete inventory")
        recorded_statuses = payload.get("inventory", {}).get("selector_status_counts")
        if recorded_statuses != selector_status_counts(rows):
            fail(f"{path}: selector_status_counts does not match rows")
        inventories[table_name] = rows
    registry_path = output_dir / "source-registry.json"
    payload = json.loads(registry_path.read_text(encoding="utf-8"))
    ids = {source["source_id"] for source in payload.get("sources", [])}
    needed = {"mlit-railway-statistics", "mlit-n02-legacy-1996", "mlit-n05-railway-timeseries"}
    if not needed <= ids:
        fail(f"{registry_path}: missing source records {sorted(needed - ids)}")
    reviewed_path = output_dir / "reviewed-identity-events.json"
    if reviewed_path.exists():
        validate_reviewed_identity_ledger(reviewed_path)
    openings_path = output_dir / "reviewed-opening-events.json"
    if openings_path.exists():
        validate_reviewed_opening_ledger(openings_path, inventories["openings"])
    stations_path = output_dir / "reviewed-station-events.json"
    if stations_path.exists():
        validate_reviewed_station_ledger(stations_path)
    station_changes_path = output_dir / 'reviewed-station-renames-2019.json'
    if station_changes_path.exists():
        station_changes = json.loads(station_changes_path.read_text(encoding='utf-8'))
        validate_reviewed_station_ledger(station_changes_path,
                                        primary_source_ids=station_changes.get('primary_source_ids', []))
    partial_openings_path = output_dir / 'reviewed-partial-opening-events.json'
    if partial_openings_path.exists():
        validate_reviewed_opening_ledger(partial_openings_path, inventories['openings'],
                                        selector_scope='isolated_current_segment')
    review_path = output_dir / DEFAULT_REVIEW_LEDGER.name
    if not review_path.exists():
        fail(f"missing checked-in review ledger: {review_path}")
    review_payload = json.loads(review_path.read_text(encoding="utf-8"))
    reconcile_selector_reviews(inventories, review_payload, str(review_path))


def validate_reviewed_identity_ledger(path: Path) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != SCHEMA_VERSION:
        fail(f"{path}: unsupported schema_version")
    source_ids = {source.get("source_id") for source in payload.get("sources", [])}
    rows = payload.get("rows")
    if not isinstance(rows, list) or not rows:
        fail(f"{path}: non-empty rows required")
    seen = set()
    allowed_review = {"reviewed_seed", "reviewed_source_only"}
    allowed_geometry = {
        "ready_whole_identity", "ready_current_station",
        "ready_isolated_segment", "ready_historical_station",
        "unresolved_segment_selector", "unresolved_historical_geometry",
    }
    for row in rows:
        row_id = row.get("id")
        if not row_id or row_id in seen:
            fail(f"{path}: row ids must be present and unique")
        seen.add(row_id)
        try:
            dt.date.fromisoformat(row.get("effective_date", ""))
        except (TypeError, ValueError):
            fail(f"{path}: {row_id} needs an exact-day effective_date")
        if row.get("date_precision") != "exact_day":
            fail(f"{path}: {row_id} needs date_precision exact_day")
        if row.get("review", {}).get("status") not in allowed_review:
            fail(f"{path}: {row_id} has unknown review status")
        geometry = row.get("geometry", {})
        geometry_status = geometry.get("status")
        if geometry_status not in allowed_geometry:
            fail(f"{path}: {row_id} has unknown geometry status")
        if row["review"]["status"] == "reviewed_seed":
            if not geometry_status.startswith("ready_"):
                fail(f"{path}: {row_id} reviewed seed needs a ready selector")
        elif not geometry_status.startswith("unresolved_"):
            fail(f"{path}: {row_id} source-only review must remain unresolved")
        if geometry_status in {"ready_isolated_segment", "ready_historical_station"}:
            if not row.get("canonical_event_id") or not row.get("basis"):
                fail(f"{path}: {row_id} promoted surveyed selector needs canonical event and basis")
            selector = geometry.get("selector", {})
            if geometry_status == "ready_isolated_segment" and selector.get("scope") not in {
                    "isolated_current_segment", "isolated_historical_segment"}:
                fail(f"{path}: {row_id} isolated selector scope is not explicit")
            if geometry_status == "ready_historical_station" and selector.get("scope") != "historical_station":
                fail(f"{path}: {row_id} historical station selector scope is not explicit")
        evidence = row.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            fail(f"{path}: {row_id} needs evidence")
        unknown = {item.get("source_id") for item in evidence} - source_ids
        if unknown:
            fail(f"{path}: {row_id} references unknown sources {sorted(unknown)}")


def validate_reviewed_opening_ledger(path: Path, official_rows, selector_scope='whole_identity') -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != SCHEMA_VERSION:
        fail(f"{path}: unsupported schema_version")
    official = {row["source_row_id"]: row for row in official_rows}
    events = payload.get("events")
    if not isinstance(events, list) or not events:
        fail(f"{path}: non-empty events required")
    ids = set()
    source_ids = set()
    for event in events:
        event_id = event.get("id")
        source_id = event.get("official_event_id")
        if not event_id or event_id in ids or not source_id or source_id in source_ids:
            fail(f"{path}: event and official row ids must be present and unique")
        ids.add(event_id)
        source_ids.add(source_id)
        row = official.get(source_id)
        if row is None:
            fail(f"{path}: {event_id} references unknown official row {source_id}")
        if event.get("kind") != "opening":
            fail(f"{path}: {event_id} is not an opening")
        if event.get("date_precision") != "exact_day":
            fail(f"{path}: {event_id} needs exact-day precision")
        if event.get("service_periods") != [[row["effective_date"], None]]:
            fail(f"{path}: {event_id} date does not match the official row")
        if event.get("segment") != {
            "from_station": row["from_station_name"],
            "to_station": row["to_station_name"],
        }:
            fail(f"{path}: {event_id} termini do not match the official row")
        if event.get("expected", {}).get("business_km") != row["length_km"]:
            fail(f"{path}: {event_id} business km does not match the official row")
        if event.get("official_line_name", event.get("line")) != row["official_line_name"]:
            fail(f"{path}: {event_id} official line spelling does not match the official row")
        if event.get("operator") != row["official_operator_name"]:
            fail(f"{path}: {event_id} operator does not match the official row")
        if event.get("review", {}).get("status") != "verified":
            fail(f"{path}: {event_id} is not verified")
        selector = event.get('geometry', {}).get('selector', {})
        if selector.get('scope') != selector_scope:
            fail(f"{path}: {event_id} is not a {selector_scope} selector")
        if selector_scope == 'isolated_current_segment':
            bbox = selector.get('bbox')
            if (not isinstance(bbox, list) or len(bbox) != 4
                    or not all(isinstance(value, (int, float)) for value in bbox)
                    or bbox[0] >= bbox[2] or bbox[1] >= bbox[3]
                    or not selector.get('stations')):
                fail(f"{path}: {event_id} needs an isolated bbox and explicit newly opened stations")
        if not any(item.get("reference") == OPENINGS_URL for item in event.get("evidence", [])):
            fail(f"{path}: {event_id} lacks the official MLIT opening-table reference")


def validate_reviewed_station_ledger(path: Path, primary_source_ids=None) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != SCHEMA_VERSION:
        fail(f"{path}: unsupported schema_version")
    sources = {source.get("source_id"): source for source in payload.get("sources", [])}
    events = payload.get("events")
    if not isinstance(events, list) or not events:
        fail(f"{path}: non-empty events required")
    legacy = primary_source_ids is None
    primary_source_ids = ['keikyu-six-station-renames-2020'] if legacy else primary_source_ids
    if (not isinstance(primary_source_ids, list) or not primary_source_ids
            or not all(isinstance(value, str) and value for value in primary_source_ids)):
        fail(f'{path}: primary source ids required')
    required_sources = {*primary_source_ids, 'mlit-n02-19'}
    if not required_sources <= sources.keys():
        fail(f"{path}: missing source records {sorted(required_sources - sources.keys())}")

    official_references = {sources[source_id].get('reference') for source_id in primary_source_ids}
    if None in official_references or '' in official_references:
        fail(f'{path}: primary sources need reference URLs')
    seen = {'id': set(), 'membership_id': set(), 'current_n02_station_code': set()}
    if legacy:
        seen.update(station_entity_id=set(), official_station_number=set())
    entities = {}
    for event in events:
        event_id = event.get("id") or "?"
        for key in seen:
            value = event.get(key)
            if not value or value in seen[key]:
                fail(f"{path}: {key} values must be present and unique")
            seen[key].add(value)
        if event.get("kind") != "station_rename":
            fail(f"{path}: {event_id} is not a station rename")
        try:
            dt.date.fromisoformat(event.get("date", ""))
        except (TypeError, ValueError):
            fail(f"{path}: {event_id} needs an exact-day date")
        if event.get("date_precision") != "exact_day":
            fail(f"{path}: {event_id} needs date_precision exact_day")
        if event.get("review", {}).get("status") != "verified":
            fail(f"{path}: {event_id} is not verified")

        before, after = event.get("before"), event.get("after")
        if not isinstance(before, dict) or not isinstance(after, dict):
            fail(f"{path}: {event_id} needs before and after station identities")
        if before.get("line") != after.get("line") or before.get("operator") != after.get("operator"):
            fail(f"{path}: {event_id} changes more than the station name")
        if not before.get("station") or not after.get("station") or before["station"] == after["station"]:
            fail(f"{path}: {event_id} needs distinct old and current station names")
        entity_id, station_number = event.get('station_entity_id'), event.get('official_station_number')
        if not entity_id or not station_number:
            fail(f'{path}: {event_id} needs stable station entity and official station number')
        entity = (station_number, before['station'], after['station'], after['operator'])
        if entity_id in entities and entities[entity_id] != entity:
            fail(f'{path}: {event_id} shared station entity has inconsistent identity')
        entities[entity_id] = entity

        geometry = event.get("geometry", {})
        release = geometry.get('release')
        if (geometry.get('source') != 'N02' or geometry.get('licence_status') != 'redistributable'
                or not isinstance(release, str) or not re.fullmatch(r'N02-\d{2}', release)
                or legacy and release != 'N02-19'
                or not legacy and 'mlit-' + release.lower() not in sources):
            fail(f"{path}: {event_id} needs a declared redistributable N02 geometry release")
        if geometry.get("selector", {}).get("stations") != [after["station"]]:
            fail(f"{path}: {event_id} selector must name exactly the current station")
        historical = geometry.get("historical_stations")
        if not isinstance(historical, list) or not historical or legacy and len(historical) != 1:
            fail(f"{path}: {event_id} needs reviewed historical station features")
        expected_properties = {
            "line_name": before["line"], "operator": before["operator"],
            "station_name": before["station"], "source_release": release,
        }
        for feature in historical:
            properties = feature.get('properties', {})
            if any(properties.get(key) != value for key, value in expected_properties.items()):
                fail(f"{path}: {event_id} historical identity does not match before")
            coordinates = feature.get('geometry', {}).get('coordinates')
            if (feature.get('type') != 'Feature'
                    or feature.get('geometry', {}).get('type') != 'LineString'
                    or not isinstance(coordinates, list) or len(coordinates) < 2):
                fail(f"{path}: {event_id} needs non-empty N02 LineString geometry")
        evidence = event.get("evidence")
        if (not isinstance(evidence, list) or not evidence
                or not any(item.get("reference") in official_references
                           and item.get("date_precision") == "exact_day"
                           for item in evidence)):
            fail(f"{path}: {event_id} lacks primary exact-day operator evidence")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--openings-pdf", type=Path)
    parser.add_argument("--closures-pdf", type=Path)
    parser.add_argument("--download", action="store_true", help="download both fixed official PDF URLs")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--retrieved-at", default=dt.date.today().isoformat())
    parser.add_argument("--check", action="store_true", help="validate checked-in inventories only")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        dt.date.fromisoformat(args.retrieved_at)
    except ValueError:
        fail("--retrieved-at must be YYYY-MM-DD")
    if args.check:
        if args.download or args.openings_pdf or args.closures_pdf:
            fail("--check cannot be combined with PDF import options")
        validate_checked_in(args.output_dir)
        print(f"PASS: validated MLIT history inventories in {args.output_dir}")
        return

    if args.download and (args.openings_pdf or args.closures_pdf):
        fail("--download cannot be combined with explicit PDF paths")
    if not args.download and (args.openings_pdf is None or args.closures_pdf is None):
        fail("provide both --openings-pdf and --closures-pdf, or use --download")

    if args.download:
        temp = tempfile.TemporaryDirectory(prefix="jtm-mlit-history-")
        base = Path(temp.name)
        openings_pdf = base / "openings.pdf"
        closures_pdf = base / "closures.pdf"
        download(OPENINGS_URL, openings_pdf)
        download(CLOSURES_URL, closures_pdf)
    else:
        temp = None
        openings_pdf = args.openings_pdf
        closures_pdf = args.closures_pdf
    try:
        if not DEFAULT_REVIEW_LEDGER.is_file():
            fail(f"missing review ledger: {DEFAULT_REVIEW_LEDGER}")
        review_payload = json.loads(DEFAULT_REVIEW_LEDGER.read_text(encoding="utf-8"))
        inventories = {}
        for name, pdf in (("openings", openings_pdf), ("closures", closures_pdf)):
            if not pdf.is_file():
                fail(f"missing PDF: {pdf}")
            inventories[name] = parse_table(pdf, name, args.retrieved_at)
        apply_selector_review_ledger(
            {name: payload["rows"] for name, payload in inventories.items()},
            review_payload,
        )
        for name, payload in inventories.items():
            payload["inventory"]["selector_status_counts"] = selector_status_counts(payload["rows"])
            write_json(args.output_dir / TABLES[name]["filename"], payload)
        write_json(args.output_dir / DEFAULT_REVIEW_LEDGER.name, review_payload)
        write_json(args.output_dir / "source-registry.json", registry(args.retrieved_at))
        validate_checked_in(args.output_dir)
    finally:
        if temp is not None:
            temp.cleanup()
    print(f"PASS: wrote complete MLIT opening/closure row inventories to {args.output_dir}")


if __name__ == "__main__":
    main()
