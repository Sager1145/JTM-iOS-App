#!/usr/bin/env python3
"""Normalize visually reviewed JR Hokkaido limited-express announcement rows.

The announcement publishes selected 2026 operating dates and partial timetable
details. Direction-specific official timetable pages promote Sarobetsu train
numbers, passenger calls, clocks, operator segments and Soya Main Line segments.
"""
from datetime import date, timedelta
from copy import deepcopy
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-hokuto-2026summer-north-shikoku-batch.json"
SUFFIX = "north-shikoku-batch"
SCOPE = "jr-hokkaido"
STATION_SOURCE_ID = "jtm-current-station-directory"
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
EXPECTED_DATE_COUNTS = {
    "hokuto-84-91": 12,
    "sarobetsu-3-4": 92,
    "kamui-9-26": 32,
    "kamui-15-36": 3,
    "niseko-bidirectional": 16,
    "furano-lavender-bidirectional": 57,
}


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    ))


def day_after(value):
    return (date.fromisoformat(value) + timedelta(days=1)).isoformat()


def expand_dates(group, as_of):
    values = set(group["single_dates"])
    for first, last in group["date_ranges"]:
        current = date.fromisoformat(first)
        ending = date.fromisoformat(last)
        if current > ending:
            raise ValueError(f"Backward date range in {group['group_id']}: {first}/{last}")
        while current <= ending:
            values.add(current.isoformat())
            current += timedelta(days=1)
    dates = sorted(value for value in values if value <= as_of)
    expected = EXPECTED_DATE_COUNTS[group["group_id"]]
    if len(dates) != expected:
        raise ValueError(
            f"Reviewed date expansion changed for {group['group_id']}: "
            f"expected {expected}, got {len(dates)}"
        )
    return dates


def existing_station_ids(excluded_path):
    found = set()
    for path in sorted((BASE / "normalized").glob("station-identities*.jsonl")):
        if path.resolve() == excluded_path.resolve():
            continue
        for line in path.read_text().splitlines():
            if line.strip():
                found.add(json.loads(line)["station_id"])
    return found


def main():
    candidate = json.loads(CANDIDATE.read_text())
    as_of = json.loads((BASE / "manifest.json").read_text())["as_of_date"]
    source = candidate["source"]
    source_id = source["source_id"]
    furano_time_source = candidate["furano_time_source"]
    furano_time_source_id = furano_time_source["source_id"]
    sarobetsu_sources = {
        row["source_id"]: row for row in candidate["sarobetsu_timetable_sources"]
    }
    kamui_sources = {
        row["source_id"]: row for row in candidate["kamui_timetable_sources"]
    }
    number_sources = {
        row["source_id"]: row for row in candidate["other_number_sources"]
    }
    groups = candidate["service_groups"]

    if not source["url_or_locator"].startswith(
        "https://www.jrhokkaido.co.jp/CM/Info/press/pdf/"
    ):
        raise ValueError("Candidate must retain the reviewed official JR Hokkaido PDF URL")
    if furano_time_source["url_or_locator"] != (
        "https://www.jrhokkaido.co.jp/CM/Info/press/pdf/260325_KO_Furano-Biei.pdf"
    ):
        raise ValueError("Furano stop clocks require the reviewed official JR Hokkaido PDF")
    if set(sarobetsu_sources) != {
        "jr-hokkaido-soya-down-20260930", "jr-hokkaido-soya-up-20260930"
    } or any(
        row["effective_date"] != "2026-09-30"
        or not row["url_or_locator"].startswith("https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&")
        for row in sarobetsu_sources.values()
    ):
        raise ValueError("Sarobetsu details require the reviewed 2026-09-30 JR Hokkaido timetable pages")
    if set(kamui_sources) != {
        "jr-hokkaido-kamui-down-20260927", "jr-hokkaido-kamui-up-20260927"
    } or any(
        row["effective_date"] != "2026-09-27"
        or not row["url_or_locator"].startswith("https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260927&")
        for row in kamui_sources.values()
    ):
        raise ValueError("Kamui details require the retrievable 2026-09-27 JR Hokkaido timetable pages")
    if set(number_sources) != {
        "jr-hokkaido-hokuto-84-20260920",
        "jr-hokkaido-hokuto-91-20260920",
        "jr-hokkaido-niseko-sapporo-20260923",
        "jr-hokkaido-niseko-hakodate-20260926",
        "jr-hokkaido-hokuto-84-20260919",
        "jr-hokkaido-hokuto-91-20260919",
        "jr-hokkaido-niseko-sapporo-20260927",
        "jr-hokkaido-niseko-hakodate-20260927",
        "jr-hokkaido-niseko-sapporo-20260922",
        "jr-hokkaido-niseko-hakodate-20260922",
    } or any(
        not row["url_or_locator"].startswith("https://jrhokkaidonorikae.com/vtime/vtime.php?d=")
        for row in number_sources.values()
    ):
        raise ValueError("Hokuto and Niseko train numbers require reviewed dated official timetable pages")
    if {group["group_id"] for group in groups} != set(EXPECTED_DATE_COUNTS):
        raise ValueError("Reviewed group inventory changed")
    if any(group["service_id"] == "kamui" and group["emit_service"] for group in groups):
        raise ValueError("Kamui must reuse the existing service row")

    dates_by_group = {group["group_id"]: expand_dates(group, as_of) for group in groups}
    niseko = next(group for group in groups if group["group_id"] == "niseko-bidirectional")
    niseko_stops = {trip["direction"]: trip["intermediate_stops"] for trip in niseko["trips"]}
    if (
        "大沼公園" in niseko_stops["sapporo_to_hakodate"]
        or "大沼公園" not in niseko_stops["hakodate_to_sapporo"]
    ):
        raise ValueError("Niseko direction-specific Onuma-Koen stop review changed")

    station_names = set()
    for group in groups:
        for trip in group["trips"]:
            station_names.update([trip["origin"], trip["destination"]])
            station_names.update(trip["intermediate_stops"] or [])
            station_names.update(stop["station"] for stop in trip.get("detailed_stops", []))

    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    operator = candidate["operator_name_for_station_match"]
    stations = {}
    for name in sorted(station_names):
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == operator
            for station in line["stations"]
            if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(
                f"Station must resolve to one sourceCode for ({operator}, {name}): {sorted(codes)}"
            )
        code = next(iter(codes))
        stations[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
            "rail_history_id": None,
        }

    target_station_path = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    already_defined = existing_station_ids(target_station_path)
    new_station_rows = sorted(
        (station for station in stations.values() if station["station_id"] not in already_defined),
        key=lambda row: row["station_id"],
    )

    service_dates = {}
    service_metadata = {}
    for group in groups:
        service_dates.setdefault(group["service_id"], set()).update(
            dates_by_group[group["group_id"]]
        )
        service_metadata[group["service_id"]] = group

    services = []
    service_names = []
    for service_id, dates_set in sorted(service_dates.items()):
        group = service_metadata[service_id]
        dates = sorted(dates_set)
        if group["emit_service"]:
            services.append({
                "service_id": service_id,
                "canonical_name": group["service_name"],
                "service_class": "limited_express",
                "historical_generation": 1,
                "first_verified_date": dates[0],
                "last_verified_date": dates[-1],
                "jr_scope": "jr",
            })
        service_names.append({
            "service_id": service_id,
            "name": group["service_name"],
            "language": "ja",
            "valid_from": dates[0],
            "valid_until": day_after(dates[-1]),
            "name_type": "display",
            "source_id": source_id,
        })

    timetable_versions = []
    calendars = []
    exceptions = []
    trips = []
    stop_times = []
    fact_sources = []
    fact_completeness = []
    research_queue = []
    operator_segments = []
    line_segments = []

    for group in groups:
        group_dates = dates_by_group[group["group_id"]]
        reviewed_trips = []
        for original_trip in group["trips"]:
            source_dates = original_trip.get("source_dates", [])
            extra_dates = original_trip.get("additional_date_sources", [])
            all_dated = source_dates + [row["service_date"] for row in extra_dates]
            if (len(all_dated) != len(set(all_dated)) or
                not set(all_dated).issubset(group_dates) or
                any(row["source_id"] not in number_sources for row in extra_dates)):
                raise ValueError(f"Dated evidence outside operating calendar: {group['group_id']}")
            if source_dates and len(source_dates) != 1:
                raise ValueError(f"Only a single exact dated source is reviewed per trip: {group['group_id']}")
            if all_dated:
                base = deepcopy(original_trip)
                base_dates = [value for value in group_dates if value not in all_dated]
                base.pop("train_number", None)
                base.pop("number_source_id", None)
                base.pop("detail_source_id", None)
                base.pop("detailed_stops", None)
                if group["service_id"] in {"kamui", "sarobetsu"}:
                    base["intermediate_stops"] = None
                if group["service_id"] == "sarobetsu":
                    base.pop("operator_id", None)
                    base.pop("route_line", None)
                if base_dates:
                    reviewed_trips.append((base, base_dates))
                for dated_day, number_source in (
                    [(source_dates[0], original_trip.get("number_source_id"))] if source_dates else []
                ) + [(row["service_date"], row["source_id"]) for row in extra_dates]:
                    dated = deepcopy(original_trip)
                    dated["source_dates"] = [dated_day]
                    if number_source is not None:
                        dated["number_source_id"] = number_source
                    else:
                        dated.pop("number_source_id", None)
                    dated["trip_id_component"] += "-dated-" + dated_day.replace("-", "")
                    reviewed_trips.append((dated, [dated_day]))
            else:
                reviewed_trips.append((original_trip, group_dates))
        for reviewed_trip, operating_dates in reviewed_trips:
            valid_from = operating_dates[0]
            valid_until = day_after(operating_dates[-1])
            trip_id = (
                f"{SCOPE}.{group['service_id']}."
                f"{reviewed_trip['trip_id_component']}.{valid_from}"
            )
            version_id = trip_id + ".version"
            calendar_id = trip_id + ".calendar"
            timetable_versions.append({
                "timetable_version_id": version_id,
                "operator_scope": SCOPE,
                "effective_from": valid_from,
                "effective_until": valid_until,
                "publication_date": source["publication_date"],
                "edition_name": f"JR Hokkaido 2026 summer announcement; {group['group_id']}",
                "revision_type": "planned_exception",
                "completeness": "partial",
                "source_ids": [
                    source_id,
                    *([reviewed_trip["detail_source_id"]] if reviewed_trip.get("detail_source_id") else []),
                    *([reviewed_trip["number_source_id"]] if reviewed_trip.get("number_source_id") else []),
                ],
            })
            calendars.append({
                "calendar_id": calendar_id,
                "valid_from": valid_from,
                "valid_until": valid_until,
                "holiday_policy": "none",
                **{weekday: 0 for weekday in WEEKDAYS},
            })
            exceptions.extend({
                "calendar_id": calendar_id,
                "service_date": service_date,
                "exception_type": "add",
                "reason": (
                    f"PDF p.{group['page']} operating-date cell for {group['group_id']}; "
                    f"source text: {group['date_cell_text']}"
                ),
                "source_id": source_id,
            } for service_date in operating_dates)

            intermediate = reviewed_trip["intermediate_stops"]
            stops_complete = intermediate is not None
            detailed_stops = reviewed_trip.get("detailed_stops")
            sarobetsu_detailed = group["group_id"] == "sarobetsu-3-4" and bool(detailed_stops)
            kamui_detailed = group["service_id"] == "kamui" and bool(detailed_stops)
            source_detailed = sarobetsu_detailed or kamui_detailed
            published_clocks = reviewed_trip.get("published_intermediate_clocks")
            times_complete = group["group_id"] == "furano-lavender-bidirectional"
            if times_complete:
                if not isinstance(published_clocks, list) or [
                    clock["station"] for clock in published_clocks
                ] != intermediate:
                    raise ValueError(f"Incomplete Furano stop clocks for {trip_id}")
                if any(
                    ("arrival_time" in clock) == ("departure_time" in clock)
                    for clock in published_clocks
                ):
                    raise ValueError(f"Ambiguous Furano stop clock side for {trip_id}")
            ordered_names = [
                reviewed_trip["origin"],
                *(intermediate or []),
                reviewed_trip["destination"],
            ]
            if source_detailed:
                if [stop["station"] for stop in detailed_stops or []] != ordered_names:
                    raise ValueError(f"Incomplete official stop matrix for {trip_id}")
                allowed = sarobetsu_sources if sarobetsu_detailed else kamui_sources
                if reviewed_trip["detail_source_id"] not in allowed:
                    raise ValueError(f"Unknown official detail source for {trip_id}")
            detail_source_id = reviewed_trip.get("detail_source_id", source_id)
            number_source_id = reviewed_trip.get("number_source_id", detail_source_id)
            number_verified = source_detailed or number_source_id in number_sources
            if reviewed_trip.get("number_source_id") and number_source_id not in number_sources:
                raise ValueError(f"Unknown train-number source for {trip_id}")
            trip = {
                "trip_id": trip_id,
                "timetable_version_id": version_id,
                "service_id": group["service_id"],
                "calendar_id": calendar_id,
                "train_number": reviewed_trip.get("train_number"),
                "public_number": reviewed_trip["public_number"],
                "origin_station_id": stations[ordered_names[0]]["station_id"],
                "destination_station_id": stations[ordered_names[-1]]["station_id"],
                "service_class": "limited_express",
                "notes": (
                    "Official announcement and direction-specific timetable. "
                    if source_detailed else
                    "Official announcement and published stop clocks. "
                    if times_complete else "Official announcement; endpoint times only. "
                ) + (
                    "The complete printed passenger-stop list is recorded. "
                    if stops_complete
                    else "Intermediate passenger stops are not published and are omitted. "
                ) + (
                    (
                        "Published clocks preserve blank arrival or departure cells."
                        if source_detailed
                        else "Operator segments and route lines remain unknown."
                        if number_verified
                        else "Internal train number, operator segments and route lines remain unknown."
                    )
                ),
            }
            if reviewed_trip["direction"] is not None:
                trip["direction"] = reviewed_trip["direction"]
            trips.append(trip)

            for sequence, name in enumerate(ordered_names, start=1):
                is_origin = sequence == 1
                is_destination = sequence == len(ordered_names)
                published_clock = (
                    detailed_stops[sequence - 1]
                    if source_detailed else
                    published_clocks[sequence - 2]
                    if times_complete and not is_origin and not is_destination else {}
                )
                arrival = published_clock.get("arrival_time") if source_detailed else reviewed_trip["arrival_time"] if is_destination else published_clock.get("arrival_time")
                departure = published_clock.get("departure_time") if source_detailed else reviewed_trip["departure_time"] if is_origin else published_clock.get("departure_time")
                stop_times.append({
                    "trip_id": trip_id,
                    "stop_sequence": sequence,
                    "station_id": stations[name]["station_id"],
                    "arrival_time": arrival,
                    "departure_time": departure,
                    "day_offset": 0,
                    "call_type": "origin" if is_origin else "destination" if is_destination else "passenger_stop",
                    "pickup_allowed": 0 if is_destination else 1,
                    "dropoff_allowed": 0 if is_origin else 1,
                    "time_accuracy": "minute" if arrival or departure else "unknown",
                    "source_id": detail_source_id if source_detailed else furano_time_source_id if times_complete else source_id,
                })

            if sarobetsu_detailed:
                operator_segments.append({
                    "trip_id": trip_id,
                    "from_sequence": 1,
                    "to_sequence": len(ordered_names),
                    "operator_id": reviewed_trip["operator_id"],
                })
                line_segments.extend({
                    "trip_id": trip_id,
                    "sequence": sequence,
                    "from_station_id": stations[left]["station_id"],
                    "to_station_id": stations[right]["station_id"],
                    "line_name": reviewed_trip["route_line"],
                    "operator_id": reviewed_trip["operator_id"],
                    "source_id": detail_source_id,
                    "confidence": "high",
                } for sequence, (left, right) in enumerate(zip(ordered_names, ordered_names[1:]), start=1))

            completeness = {
                "identity": ("verified", "high", "The reviewed row prints the service identity and any public number."),
                "train_number": (
                    "verified" if number_verified else "unknown",
                    "high" if number_verified else "low",
                    "The selected official timetable column prints the internal train number."
                    if number_verified else "No internal train number is published; unnumbered services also keep public_number null.",
                ),
                "operator": (
                    "verified" if sarobetsu_detailed else "unknown",
                    "high" if sarobetsu_detailed else "low",
                    "JR Hokkaido's official network page links the branded timetable service covering the full route."
                    if sarobetsu_detailed else "Publisher identity is not promoted as operator-segment evidence.",
                ),
                "validity_calendar": ("verified", "high", group["date_cell_interpretation"]),
                "origin_destination": ("verified", "high", "Both endpoints are printed in the row."),
                "stops": (
                    "verified" if stops_complete else "partial",
                    "high",
                    "The complete intermediate-stop line is printed."
                    if stops_complete
                    else "The table publishes endpoints but no intermediate-stop list.",
                ),
                "times": (
                    "verified" if times_complete else "partial",
                    "high",
                    "Every listed passenger stop has the published directional clock; the opposite side is not printed."
                    if times_complete else
                    "All passenger calls and published clocks are recorded; several intermediate arrival cells are blank."
                    if source_detailed else "Only origin departure and destination arrival are printed.",
                ),
                "route_lines": (
                    "partial" if sarobetsu_detailed else "unknown",
                    "high" if sarobetsu_detailed else "low",
                    "The direction-specific timetable heading identifies the complete route as 宗谷本線; no direct N02 line identity is asserted."
                    if sarobetsu_detailed else "No ordered railway-line evidence is promoted.",
                ),
                "station_refs": ("verified", "high", "Every recorded station uniquely matches one sourceCode under 北海道旅客鉄道."),
                "provenance": ("partial", "medium", "Official URLs are recorded; page snapshots and redistribution authorization are unavailable."),
            }
            for dimension, (status, confidence, notes) in completeness.items():
                fact_completeness.append({
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "dimension": dimension,
                    "status": status,
                    "confidence": confidence,
                    "notes": notes,
                })

            locator = reviewed_trip["source_locator"]
            for field_name in ["identity", "validity_calendar", "origin_destination"]:
                fact_sources.append({
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": field_name,
                    "source_id": source_id,
                    "page_or_locator": locator,
                    "confidence": "high",
                    "verification_status": "verified",
                })
            fact_sources.extend([
                {
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": "stops",
                    "source_id": detail_source_id if source_detailed else source_id,
                    "page_or_locator": "Dated selected train column; passing rows omitted" if source_detailed else locator,
                    "confidence": "high",
                    "verification_status": "verified" if stops_complete else "partial",
                },
                {
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": "times",
                    "source_id": detail_source_id if source_detailed else furano_time_source_id if times_complete else source_id,
                    "page_or_locator": (
                        "Dated selected train column; blank arrival/departure cells preserved"
                        if source_detailed else
                        "PDF physical p.5 section 2(2), both directional Furano Lavender Express rows"
                        if times_complete else locator + "; endpoint times only"
                    ),
                    "confidence": "high",
                    "verification_status": "verified" if times_complete else "partial",
                },
                {
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": "station_refs",
                    "source_id": STATION_SOURCE_ID,
                    "page_or_locator": "app/public/rail/jp-2025.json; exact (operator, station name) sourceCode match",
                    "confidence": "high",
                    "verification_status": "verified",
                },
                {
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": "provenance",
                    "source_id": source_id,
                    "page_or_locator": "Official PDF URL, publication date and reviewed SHA-256",
                    "confidence": "medium",
                    "verification_status": "partial",
                },
            ])
            if number_verified and not sarobetsu_detailed:
                fact_sources.append({
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": "train_number",
                    "source_id": number_source_id,
                    "page_or_locator": "Dated selected train column",
                    "confidence": "high",
                    "verification_status": "verified",
                })
            if sarobetsu_detailed:
                for field_name in ["train_number", "operator", "route_lines"]:
                    fact_sources.append({
                        "entity_type": "trip",
                        "entity_id": trip_id,
                        "field_name": field_name,
                        "source_id": detail_source_id,
                        "page_or_locator": "2026-09-30 selected column and 宗谷本線 direction heading",
                        "confidence": "high",
                        "verification_status": "partial" if field_name == "route_lines" else "verified",
                    })
                fact_sources.append({
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": "operator",
                    "source_id": "jr-hokkaido-network-2026",
                    "page_or_locator": "Official JR Hokkaido railway portal links jrhokkaidonorikae.com timetable search and names Kotsu Shimbunsha as provider",
                    "confidence": "high",
                    "verification_status": "verified",
                })

            queue_notes = {
                "train_number": "Obtain an official internal train-number source; do not invent one from public numbering or direction.",
                "operator": "Obtain explicit operator-segment evidence.",
                "route_lines": "Obtain explicit ordered line references valid for every listed operating date.",
                "provenance": "Resolve timetable fact redistribution authorization.",
            }
            if number_verified:
                queue_notes.pop("train_number")
            if sarobetsu_detailed:
                queue_notes.pop("operator")
                queue_notes["route_lines"] = "Map the official 宗谷本線 name to a dated direct physical-line identity."
            if not times_complete:
                queue_notes["times"] = "Obtain arrival/departure times for every passenger stop."
            if not stops_complete:
                queue_notes["stops"] = "Obtain the complete intermediate passenger-stop list."
            research_queue.extend({
                "research_id": f"{trip_id}.{dimension}",
                "entity_type": "trip",
                "entity_id": trip_id,
                "missing_dimension": dimension,
                "status": "open",
                "notes": notes,
            } for dimension, notes in queue_notes.items())

    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": [source, furano_time_source, *sarobetsu_sources.values(), *kamui_sources.values(), *number_sources.values()],
        BASE / f"normalized/services-{SUFFIX}.jsonl": services,
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": service_names,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": timetable_versions,
        target_station_path: new_station_rows,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": fact_completeness,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": research_queue,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": trips,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_times,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl": operator_segments,
        BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl": line_segments,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)

    print(
        f"Normalized {len(trips)} limited-express templates, {len(stop_times)} recorded stops, "
        f"{len(exceptions)} explicit occurrences, and {len(new_station_rows)} new station identities."
    )
    print("Manifest-selected outputs:")
    for path, rows in outputs.items():
        print(f"  {path.relative_to(BASE)} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
