#!/usr/bin/env python3
"""Propose links between snapshot-diff candidates and curated JP events.

This is a review aid.  It neither edits jp-rail-history-events.json nor marks
any candidate verified.  A proposed match says only that snapshot evidence is
compatible with a curated event's identity, release label, station filter, and
bounds; a reviewer must still validate the primary source and exact date.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path


SCHEMA_VERSION = "jp-rail-history-event-match-queue-v1"


KIND_COMPATIBILITY = {
    "closure": {"section_geometry_removed"},
    "relocation": {"section_geometry_removed", "section_geometry_added"},
    "opening": {"section_geometry_added"},
    "station_opening": {"station_added"},
    "station_closure": {"station_removed"},
    "operator_transfer": {"section_identity_changed", "station_identity_changed"},
    "operator_rename": {"section_identity_changed", "station_identity_changed"},
    "line_rename": {"section_identity_changed", "station_identity_changed"},
    "station_rename": {"station_name_changed", "station_identity_changed"},
    "station_relocation": {"station_moved"},
    # N02 geometry can support a lead for these events, but cannot establish
    # whether passenger service was suspended or resumed.
    "suspension": {"section_geometry_removed"},
    "resumption": {"section_geometry_added"},
}


def event_kind(event):
    return event.get("kind") or "closure"


def record_for(candidate, side):
    evidence = candidate.get(side)
    return evidence.get("record") if evidence else None


def attrs(record):
    return (record or {}).get("attributes", {})


def intersects(a, b):
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def release_year_from_candidate(candidate, side="before"):
    evidence = candidate.get(side) or {}
    source = evidence.get("source") or {}
    label = source.get("release_label")
    if label and str(label).split("-")[-1].isdigit():
        return str(int(str(label).split("-")[-1]))
    value = (evidence.get("observation") or {}).get("value")
    if value and str(value).isdigit():
        return str(int(value) % 100)
    return None


def candidate_subject(candidate, kind):
    if kind in ("opening", "station_opening", "resumption"):
        return record_for(candidate, "after"), "after"
    return record_for(candidate, "before"), "before"


def event_station_names(event):
    if isinstance(event.get("stations"), list):
        return set(event["stations"])
    if event.get("station"):
        return {event["station"]}
    return set()


def propose_match(candidate, event):
    kind = event_kind(event)
    if candidate.get("candidate_kind") not in KIND_COMPATIBILITY.get(kind, set()):
        return None
    record, side = candidate_subject(candidate, kind)
    if not record:
        return None
    attributes = attrs(record)
    basis = [f"compatible_candidate_kind:{candidate['candidate_kind']}"]
    identity = event.get('after' if side == 'after' else 'before') or event

    if attributes.get("line_name") != identity.get("line"):
        return None
    basis.append("exact_line_name")
    if attributes.get("operator") != identity.get("operator"):
        return None
    basis.append("exact_operator")

    if kind in ('operator_transfer', 'operator_rename', 'line_rename'):
        old_attrs = attrs(record_for(candidate, "before"))
        new_attrs = attrs(record_for(candidate, "after"))
        if old_attrs.get("operator") != identity.get("operator"):
            return None
        if event.get("to_operator") and new_attrs.get("operator") != event["to_operator"]:
            return None
        if event.get('after') and any(new_attrs.get(field) != event['after'].get(key)
                for field, key in [('line_name', 'line'), ('operator', 'operator')]):
            return None
        basis.append("operator_transition")

    station_names = ({identity['station']} if identity.get('station') else event_station_names(event))
    if station_names:
        if attributes.get("station_name") not in station_names:
            return None
        basis.append("exact_station_name")

    bbox = event.get("bbox")
    if bbox:
        record_bbox = record.get("bbox")
        if not record_bbox or not intersects(record_bbox, bbox):
            return None
        basis.append("intersects_event_bbox")

    event_year = str(event.get("year", "")).lstrip("0")
    candidate_year = release_year_from_candidate(candidate, "before")
    if event_year:
        if candidate_year != event_year:
            return None
        basis.append("exact_last_release_label")
    if event.get('geometry', {}).get('release') == 'current-package' or event.get('before'):
        date = event.get('date') or event.get('valid_from')
        if not date and event.get('service_periods'):
            date = event['service_periods'][0][0]
        observations = [(candidate.get(side) or {}).get('observation', {}).get('value')
                        for side in ('before', 'after')]
        if date and all(value and str(value).isdigit() for value in observations):
            if not int(observations[0]) <= int(date[:4]) <= int(observations[1]):
                return None
            basis.append('event_year_within_snapshot_interval')

    # Scores rank compatible leads only.  They are not confidence values.
    score = 40 + 20 * ("exact_station_name" in basis) + 10 * ("intersects_event_bbox" in basis)
    score += 20 * ("exact_last_release_label" in basis) + 10 * ("operator_transition" in basis)
    return {
        "event_id": event["id"],
        "event_kind": kind,
        "ranking_score": score,
        "basis": basis,
        "subject_side": side,
        "verification": {"state": "unverified", "automatic": False},
    }


def match_candidates(diff, event_spec):
    events = event_spec.get("events", []) + event_spec.get('temporal_events', [])
    event_by_id = {event.get("id"): event for event in events}
    if None in event_by_id or len(event_by_id) != len(events):
        raise ValueError("curated events need unique non-empty ids")
    queue = []
    event_to_candidates = defaultdict(list)
    status_counts = Counter()
    for candidate in diff.get("review_queue", []):
        matches = [match for event in events if (match := propose_match(candidate, event))]
        matches.sort(key=lambda match: (-match["ranking_score"], match["event_id"]))
        status = "unmatched" if not matches else "possible_match" if len(matches) == 1 else "ambiguous"
        status_counts[status] += 1
        for match in matches:
            event_to_candidates[match["event_id"]].append(candidate["candidate_id"])
        queue.append({
            "candidate_id": candidate["candidate_id"],
            "candidate_kind": candidate["candidate_kind"],
            "match_status": status,
            "verification": {"state": "unverified", "automatic": False},
            "proposed_event_matches": matches,
        })
    queue.sort(key=lambda item: item["candidate_id"])

    event_queue = []
    for event in sorted(events, key=lambda value: value["id"]):
        candidate_ids = sorted(event_to_candidates.get(event["id"], []))
        event_queue.append({
            "event_id": event["id"],
            "event_kind": event_kind(event),
            "candidate_ids": candidate_ids,
            "snapshot_evidence_status": "candidate_links" if candidate_ids else "no_candidate_link",
            "verification": {"state": "curated_event_not_reverified_by_matcher", "automatic": False},
        })
    return {
        "schema_version": SCHEMA_VERSION,
        "source_diff_schema": diff.get("schema_version"),
        "policy": {
            "auto_verify_candidates": False,
            "infer_day_dates_from_snapshots": False,
            "curated_event_dates_are_copied_only_by_human_review": True,
        },
        "summary": {
            "candidate_count": len(queue),
            "event_count": len(events),
            "candidate_match_status": dict(sorted(status_counts.items())),
            "events_with_candidate_links": sum(bool(item["candidate_ids"]) for item in event_queue),
        },
        "candidate_queue": queue,
        "event_queue": event_queue,
    }


def write_json(value, output):
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if output == "-":
        sys.stdout.write(text)
    else:
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        with open(output, "w", encoding="utf-8") as f:
            f.write(text)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("diff", help="diff-jp-history review queue JSON")
    parser.add_argument("events", help="curated jp-rail-history-events.json")
    parser.add_argument("--output", default="-", help="output JSON path (default: stdout)")
    args = parser.parse_args(argv)
    try:
        with open(args.diff, encoding="utf-8") as f:
            diff = json.load(f)
        with open(args.events, encoding="utf-8") as f:
            events = json.load(f)
        write_json(match_candidates(diff, events), args.output)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(2, f"match-jp-history-events: {error}\n")


if __name__ == "__main__":
    main()
