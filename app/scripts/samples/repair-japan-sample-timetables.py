#!/usr/bin/env python3
"""Apply manually reviewed, service-date-specific timetable metadata.

No source scraping or route solving: the review sidecar records the evidence.
Use --check to validate the review, all loaded sample copies and call chronology.
"""
import argparse
import copy
import json
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
DATA = APP / "data"
REVIEW = DATA / "sample-timetable-reviews.json"
SETS = [
    ("japan", DATA / "train-store.json", DATA / "sample-data"),
    ("new_year", DATA / "special-samples/new-year-grand-loop.json", DATA / "new-year-grand-loop-data"),
    ("tokyo", DATA / "special-samples/tokyo-limited-express-loop.json", DATA / "tokyo-limited-express-loop-data"),
]


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    # Existing part payloads are compact; the canonical stores are pretty.
    compact = path.name.startswith("part-")
    path.write_text(json.dumps(value, ensure_ascii=False,
                               separators=(",", ":") if compact else None,
                               indent=None if compact else 2) + ("" if compact else "\n"))


def revise(train, review):
    result = copy.deepcopy(train)
    assert result["date"] == review["date"], result["id"]
    if "number_replacement" in review:
        before, after = review["number_replacement"]
        assert before in result["number"] or after in result["number"], result["id"]
        result["number"] = result["number"].replace(before, after)
    for name, patch in review["stop_updates"].items():
        stops = [s for s in result["stops"] if s["name"] == name]
        assert len(stops) == 1, (result["id"], name)
        stops[0].update(patch)
    boundary = review.get("section_number_boundary")
    switched = False
    for index, section in enumerate(result["route_sections"]):
        if boundary:
            if result["stops"][index]["name"] == boundary["station"]:
                switched = True
            section["number"] = boundary["after"] if switched else boundary["before"]
        else:
            section["number"] = review["operating_number"]
    if boundary:
        assert switched, result["id"]
    if "notes" in review:
        result["notes"] = review["notes"]
    return result


def validate_review(train, review):
    calls = [{k: s.get(k) for k in ("name", "arrival", "departure", "stop_type")}
             for s in train["stops"] if s.get("stop_type") != "pass_through"]
    assert calls == review["verified_passenger_calls"], train["id"]
    assert len(calls) == review["verified_passenger_call_count"], train["id"]
    if review["status"] == "ridden_timetable_verified":
        assert len(train["stops"]) == review["verified_station_count"], train["id"]
    previous = -1
    for call in calls:
        assert call["arrival"] or call["departure"], (train["id"], call)
        for key in ("arrival", "departure"):
            if call[key] is not None:
                hour, minute = map(int, call[key].split(":"))
                value = hour * 60 + minute
                assert 0 <= minute < 60 and value >= previous, (train["id"], call)
                previous = value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    reviews = {r["train_id"]: r for r in read(REVIEW)["reviews"]}
    seen = set()
    inventory = []
    changed = []
    for dataset, canonical_path, directory in SETS:
        canonical = read(canonical_path)
        full_path = directory / "sample-full.json"
        full = read(full_path)
        manifest = read(directory / "manifest.json")
        assert canonical == full, f"Canonical/full mismatch: {dataset}"
        assert len(canonical["trains"]) == manifest["total"] == len(manifest["parts"])
        dirty = False
        for train, part_name in zip(canonical["trains"], manifest["parts"]):
            train_id = train["id"]
            assert train_id not in seen, train_id
            seen.add(train_id)
            part_path = directory / (part_name + ".json")
            part = read(part_path)
            assert part["train"] == train, f"Part mismatch: {part_path}"
            review = reviews.get(train_id)
            status = "historical_timetable_unverified"
            if review:
                updated = revise(train, review)
                validate_review(updated, review)
                if updated != train:
                    assert not args.check, f"Review not applied: {train_id}"
                    # Only train metadata changes; cached geometry remains intact.
                    part["train"] = updated
                    save(part_path, part)
                    train.clear()
                    train.update(updated)
                    dirty = True
                    changed.append(train_id)
                status = review["status"]
            inventory.append({"dataset": dataset, "train_id": train_id,
                              "date": train["date"], "status": status,
                              "source_url": review["url"] if review else None})
        if dirty:
            save(canonical_path, canonical)
            save(full_path, canonical)
    assert set(reviews) <= seen, "Review references an unloaded sample"
    audit = {"format": 1, "reviewed_at": "2026-10-01",
             "scope": "Complete inventory of loaded samples; historical timetable verification only for six reviewed ridden intervals.",
             "counts": {"inventory_audited": len(inventory), "services_updated": len(reviews),
                        "full_passenger_timetable_verified": len(reviews),
                        "full_station_sequence_verified": sum(r["status"] == "ridden_timetable_verified" for r in reviews.values()),
                        "passenger_calls_verified": sum(r["verified_passenger_call_count"] for r in reviews.values()),
                        "services_with_route_gaps": sum(bool(r.get("remaining_gaps")) for r in reviews.values()),
                        "historical_timetable_unverified": len(inventory) - len(reviews)},
             "inventory": inventory}
    audit_path = DATA / "sample-timetable-audit-20261001.json"
    if args.check:
        assert read(audit_path) == audit, "Audit ledger stale"
    else:
        save(audit_path, audit)
    print(json.dumps({"changed_services": changed, **audit["counts"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
