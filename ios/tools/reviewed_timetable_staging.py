#!/usr/bin/env python3
"""Shared staging for reviewed timetable profiles.

The procedures below are the repeated main/parser/emit rules from the
Odekake single-trip scripts, the JR East coupled-column scripts, and the
Shinano exact-date scripts. Per-train facts stay in each script's
STAGING_FACTS. Single JR East columns and reviewed West batches share their
own profiles. Operator history, route evidence, and pass marks are different
verbs and do not go through these staging procedures.

Clocks are copied as printed. A later clock alone never rolls the service
date; explicitly reviewed offsets are retained by the relevant profile.
Operator and route_lines stay unknown unless the script's facts say otherwise.
JR East station resolution preserves each profile's reviewed forced-code policy.
"""

import json


def iter_jsonl(base, pattern, exclude=None):
    for path in sorted(base.glob(pattern)):
        if path == exclude:
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            if raw.strip():
                yield json.loads(raw)


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()]


def other_normalized_rows(base, pattern, target):
    return [
        json.loads(line)
        for path in sorted((base / "normalized").glob(pattern))
        if path.resolve() != target.resolve()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def emit_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    ), encoding="utf-8")


def reject_unless_pinned(candidate, pinned):
    if candidate != pinned:
        raise ValueError("Source-pinned column, calendar, seat or coupling fact changed")
    return candidate["trips"]


def load_japan_station_directory(root):
    """Read the Japan station directory once for one normalizer invocation."""
    return json.loads((root / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))


def jr_east_forced_station_ids(root, trips, aliases, forced_codes=None, package=None):
    """Resolve printed JR East names with each staging procedure's reviewed code policy."""
    if package is None:
        package = load_japan_station_directory(root)
    names = {stop[0] for trip in trips for stop in trip["stops"]}
    forced_codes = ({"東京": {"003766"}, "武蔵小杉": {"004301"}}
                    if forced_codes is None else forced_codes)
    result = {}
    for name in names:
        directory_name = aliases.get(name, name)
        codes = {station[0] for line in package["lines"] if line["operator"] == "東日本旅客鉄道"
                 for station in line["stations"] if station[1] == directory_name}
        if name in forced_codes:
            codes &= forced_codes[name]
        if len(codes) != 1:
            raise ValueError(f"Ambiguous JR East station group for {name}: {sorted(codes)}")
        result[name] = "jp.n02." + next(iter(codes))
    return result


def stage_odekake_single_trip(*, base, suffix, trip_id, service_date, valid_until,
                              source_id, weekdays, stops, validate, station_additions, copy):
    candidate = json.loads((base / copy["candidate_path"]).read_text())
    source = json.loads((base / f"sources/source-registry-{suffix}.jsonl").read_text())
    validate(candidate, source)
    version, calendar = trip_id + ".version", trip_id + ".calendar"
    fact_rows = {
        "identity": ("verified", "high", copy["identity_note"]),
        "train_number": ("verified", "high", copy["train_number_note"]),
        "operator": ("unknown", "low", "Ordered operator segments not established."),
        "validity_calendar": ("verified", "high", "Only September 30 is promoted."),
        "origin_destination": ("verified", "high", "Both termini printed."),
        "stops": ("verified", "high", copy["stops_note"]),
        "times": ("verified", "high", "Printed minute clocks and side blanks retained."),
        "route_lines": ("unknown", "low", "Dated physical line identities not established."),
        "station_refs": ("verified", "high", "Exact current N02 name-code matches."),
        "provenance": ("partial", "medium", "Official page is verification-only."),
    }
    station_rows = station_additions()
    outputs = {
        base / f"normalized/station-identities-{suffix}.jsonl": station_rows,
        base / f"normalized/timetable-versions-{suffix}.jsonl": [{
            "timetable_version_id": version, "operator_scope": "jr-central",
            "effective_from": service_date, "effective_until": valid_until,
            "edition_name": copy["edition_name"],
            "revision_type": "observed_date", "publication_date": None,
            "completeness": "partial", "source_ids": [source_id]}],
        base / f"normalized/calendars/{suffix}/seeds.jsonl": [{
            "calendar_id": calendar, "valid_from": service_date, "valid_until": valid_until,
            "holiday_policy": "none", **{day: 0 for day in weekdays}}],
        base / f"normalized/calendar-exceptions/{suffix}/seeds.jsonl": [{
            "calendar_id": calendar, "service_date": service_date, "exception_type": "add",
            "reason": "September 30 selected in the official dated page", "source_id": source_id}],
        base / f"normalized/trips/{suffix}/seeds.jsonl": [{
            "trip_id": trip_id, "timetable_version_id": version, "service_id": copy["service_id"],
            "calendar_id": calendar, "train_number": copy["train_number"],
            "public_number": copy["public_number"],
            "origin_station_id": copy["origin_station_id"],
            "destination_station_id": copy["destination_station_id"],
            "service_class": "limited_express",
            "notes": "Exact date only; operator and route lines unknown."}],
        base / f"normalized/stop-times/{suffix}/seeds.jsonl": [{
            "trip_id": trip_id, "stop_sequence": index, "station_id": "jp.n02." + code,
            "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
            "call_type": kind, "pickup_allowed": int(kind != "destination"),
            "dropoff_allowed": int(kind != "origin"), "platform": platform,
            "time_accuracy": "minute", "source_id": source_id,
        } for index, (_, code, arrival, departure, platform, kind) in enumerate(stops, 1)],
        base / f"normalized/fact-completeness-{suffix}.jsonl": [{
            "entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
            "status": status, "confidence": confidence, "notes": note,
        } for dimension, (status, confidence, note) in fact_rows.items()],
        base / f"normalized/fact-sources-{suffix}.jsonl": [{
            "entity_type": "trip", "entity_id": trip_id, "field_name": dimension,
            "source_id": "jtm-current-station-directory" if dimension == "station_refs" else source_id,
            "page_or_locator": note, "confidence": confidence, "verification_status": status,
        } for dimension, (status, confidence, note) in fact_rows.items()
          if dimension not in {"operator", "route_lines"}],
        base / f"normalized/research-queue-{suffix}.jsonl": [{
            "research_id": f"{trip_id}.{dimension}", "entity_type": "trip", "entity_id": trip_id,
            "missing_dimension": dimension,
            "status": "license_blocked" if dimension == "provenance" else "open",
            "notes": note,
        } for dimension, note in {
            "operator": "Obtain ordered operator segments.",
            "route_lines": "Obtain dated physical-line identities.",
            "provenance": "Resolve timetable fact redistribution permission.",
        }.items()],
    }
    for path, data in outputs.items():
        emit_jsonl(path, data)
    print(f"Staged {trip_id}{copy['summary_suffix']}")


def stage_jr_east_coupled_columns(*, base, root, candidate_path, suffix, day, next_day,
                                  source_id, url, service, aliases, weekdays, pinned, copy,
                                  forced_codes=None, package=None, emit=True):
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    trips = reject_unless_pinned(candidate, pinned)
    stations = jr_east_forced_station_ids(root, trips, aliases, forced_codes, package)
    known_stations = {row["station_id"] for row in iter_jsonl(
        base, "normalized/station-identities*.jsonl",
        base / f"normalized/station-identities-{suffix}.jsonl")}
    station_rows = [{"station_id": sid, "name_snapshot": aliases.get(name, name),
                     "reference_kind": "current_n02", "current_source_code": sid.removeprefix("jp.n02."),
                     "rail_history_id": None}
                    for name, sid in sorted(stations.items()) if sid not in known_stations]
    versions, trip_rows, stop_rows, calendars, exceptions = [], [], [], [], []
    completeness, facts, queue = [], [], []
    for trip in trips:
        tid, number = trip["trip_id"], trip["train_number"]
        version, calendar = tid + ".version", tid + ".calendar"
        complete = all(stop[1] or stop[2] or stop[4] == "pass" for stop in trip["stops"])
        versions.append({"timetable_version_id": version, "operator_scope": "jr-east",
                         "effective_from": day, "effective_until": next_day,
                         "edition_name": f"{copy['edition_prefix']}{number} exact 9/30",
                         "revision_type": "source_snapshot", "completeness": "partial",
                         "source_ids": [source_id]})
        trip_rows.append({"trip_id": tid, "timetable_version_id": version, "service_id": service,
                          "calendar_id": calendar, "train_number": number,
                          "public_number": copy["public_number"],
                          "origin_station_id": stations[trip["origin"]],
                          "destination_station_id": stations[trip["destination"]],
                          "service_class": "limited_express",
                          "notes": copy["coupling_note"] + (
                              "This column prints all passenger-call clocks."
                              if complete else copy["incomplete_note"])})
        for sequence, (name, arrival, departure, platform, call_type) in enumerate(trip["stops"], 1):
            stop_rows.append({"trip_id": tid, "stop_sequence": sequence, "station_id": stations[name],
                              "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
                              "call_type": call_type,
                              "pickup_allowed": int(call_type in {"origin", "passenger_stop"}),
                              "dropoff_allowed": int(call_type in {"passenger_stop", "destination"}),
                              "platform": platform,
                              "time_accuracy": "minute" if arrival or departure else "unknown",
                              "source_id": source_id})
        calendars.append({"calendar_id": calendar, "valid_from": day, "valid_until": next_day,
                          "holiday_policy": "none", **{weekday: 0 for weekday in weekdays}})
        exceptions.append({"calendar_id": calendar, "service_date": day, "exception_type": "add",
                           "reason": "September 30 current-variant calendar cell", "source_id": source_id})
        statuses = {
            "identity": ("verified", "high", copy["identity_note"]),
            "train_number": ("verified", "high", f"Official column prints {number}."),
            "validity_calendar": ("verified", "high", "September 30 uses this displayed variant."),
            "origin_destination": ("verified", "high", "Official title names both branch endpoints."),
            "stops": (("verified", "high", "All passenger calls in this column printed.") if complete else
                      ("partial", "medium", copy["partial_stops_note"])),
            "times": (("verified", "high", "All printed passenger-call clocks captured.") if complete else
                      ("partial", "medium", copy["partial_times_note"])),
            "station_refs": ("verified", "high", "Names matched to current JR East N02 station groups."),
            "operator": ("unknown", "low", "No dated ordered operator segments."),
            "route_lines": ("unknown", "low", "No dated ordered physical-line IDs."),
            "provenance": ("partial", "medium", "Official URL pinned; redistribution grant unconfirmed."),
        }
        for dimension, (status, confidence, note) in statuses.items():
            completeness.append({"entity_type": "trip", "entity_id": tid, "dimension": dimension,
                                 "status": status, "confidence": confidence, "notes": note})
            if status in {"verified", "partial"} and dimension != "provenance":
                facts.append({"entity_type": "trip", "entity_id": tid, "field_name": dimension,
                              "source_id": "jtm-current-station-directory" if dimension == "station_refs" else source_id,
                              "page_or_locator": "app/public/rail/jp-2025.json" if dimension == "station_refs" else candidate["source_locator"],
                              "confidence": confidence, "verification_status": status})
            if status != "verified":
                queue.append({"research_id": f"{tid}.{dimension}", "entity_type": "trip", "entity_id": tid,
                              "missing_dimension": dimension, "status": "open", "notes": note})
    outputs = {
        base / f"sources/source-registry-{suffix}.jsonl": [{
            "source_id": source_id, "publisher": "東日本旅客鉄道株式会社 / 株式会社交通新聞社",
            "title": copy["title"],
            "source_type": "official_train_timetable", "url_or_locator": url,
            "issue": "JR時刻表2026年10月号", "publication_date": None,
            "effective_date": day, "accessed_at": day,
            "license_status": "no_reuse_grant_identified", "redistribution_status": "verification_only",
            "automated_extraction_allowed": False,
            "notes": "September30 td.ok and full printed columns verified; unprinted cells remain unknown.",
        }],
        base / f"normalized/timetable-versions-{suffix}.jsonl": versions,
        base / f"normalized/station-identities-{suffix}.jsonl": station_rows,
        base / f"normalized/trips/{suffix}/seeds.jsonl": trip_rows,
        base / f"normalized/stop-times/{suffix}/seeds.jsonl": stop_rows,
        base / f"normalized/trip-relations/{suffix}/seeds.jsonl": copy["relations"],
        base / f"normalized/calendars/{suffix}/seeds.jsonl": calendars,
        base / f"normalized/calendar-exceptions/{suffix}/seeds.jsonl": exceptions,
        base / f"normalized/fact-completeness-{suffix}.jsonl": completeness,
        base / f"normalized/fact-sources-{suffix}.jsonl": facts,
        base / f"normalized/research-queue-{suffix}.jsonl": queue,
    }
    if emit:
        for path, rows in outputs.items():
            emit_jsonl(path, rows)
        print(copy["summary"])
    return outputs


def validate_shinano_candidate(candidate, *, base, service_date, source_id, source_url,
                               expected_stops, english_source_id, english_source_url, copy):
    trip = candidate["trip"]
    source = trip["source"]
    if candidate["candidate_status"] != "reviewed_official_html":
        raise ValueError(copy["status_error"])
    if candidate["database_as_of_date"] != service_date:
        raise ValueError(copy["cutoff_error"])
    if service_date > json.loads((base / "manifest.json").read_text())["as_of_date"]:
        raise ValueError(copy["date_error"])
    if (
        trip["trip_id"], trip["service_id"], trip["service_name"],
        trip["public_number"], trip["train_number"], trip["service_date"],
    ) != (
        copy["pinned_trip_id"], "shinano", "しなの",
        copy["pinned_public_number"], copy["pinned_train_number"], service_date,
    ):
        raise ValueError(copy["identity_error"])
    if (source["source_id"], source["url_or_locator"],
            source["automated_extraction_allowed"]) != (source_id, source_url, False):
        raise ValueError(copy["source_error"])
    if trip["calendar_observation"] != {
        "month": "2026年9月", "day": 30, "cell_class": "ok", "variant_url": source_url,
    }:
        raise ValueError("Reviewed September 30 operating cell changed")
    if trip["equipment"] != ["グリーン車指定席", "普通車一部指定席"]:
        raise ValueError("Reviewed equipment labels changed")
    if trip["direction"] != copy["direction"]:
        raise ValueError("Reviewed direction changed")
    actual_stops = [(
        row["name_snapshot"], row["arrival_time"], row["departure_time"],
        row["platform"], row["call_type"],
    ) for row in trip["stop_times"]]
    expected = [(name, arrival, departure, platform, call_type)
                for name, _, arrival, departure, platform, call_type in expected_stops]
    if actual_stops != expected:
        raise ValueError(copy["stops_error"])
    if [row["stop_sequence"] for row in trip["stop_times"]] != list(range(1, copy["stop_sequence_end"])):
        raise ValueError(copy["sequence_error"])
    english = candidate["official_english_name"]
    if (english["name"], english["source_id"], english["url_or_locator"]) != (
        "Shinano", english_source_id, english_source_url,
    ):
        raise ValueError("Official English Shinano source changed")


def verify_shinano_service(base, *, english_source_id, english_source_url, service_date):
    services = {
        row["service_id"]: row
        for path in sorted((base / "normalized").glob("services*.jsonl"))
        for row in read_jsonl(path)
    }
    if services.get("shinano", {}).get("canonical_name") != "しなの":
        raise ValueError("Existing Shinano service identity is missing or conflicting")
    sources = {
        row["source_id"]: row
        for path in sorted((base / "sources").glob("source-registry*.jsonl"))
        for row in read_jsonl(path)
    }
    if sources.get(english_source_id, {}).get("url_or_locator") != english_source_url:
        raise ValueError("Official English Shinano source is missing")
    names = [
        row
        for path in sorted((base / "normalized").glob("service-name-periods*.jsonl"))
        for row in read_jsonl(path)
        if row["service_id"] == "shinano" and row["language"] == "en"
        and row["name"] == "Shinano" and row["source_id"] == english_source_id
        and row["valid_from"] <= service_date < row["valid_until"]
    ]
    if not names:
        raise ValueError("Official English Shinano name does not cover September 30")


def resolve_shinano_stations(base, root, suffix, expected_stops):
    package = json.loads((root / "app/public/rail/jp-2025.json").read_text())
    allowed_operators = {"東海旅客鉄道", "東日本旅客鉄道"}
    stations = {}
    for name, code, *_ in expected_stops:
        matches = {
            (station[0], station[1])
            for line in package["lines"] if line["operator"] in allowed_operators
            for station in line["stations"]
            if station[0] == code and station[1] == name
        }
        if matches != {(code, name)}:
            raise ValueError(f"Reviewed current station group disappeared: {(code, name)}")
        stations[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
            "rail_history_id": None,
        }
    target = base / f"normalized/station-identities-{suffix}.jsonl"
    existing = {row["station_id"]: row
                for row in other_normalized_rows(base, "station-identities*.jsonl", target)}
    additions = []
    for station in stations.values():
        prior = existing.get(station["station_id"])
        if prior and prior["name_snapshot"] != station["name_snapshot"]:
            raise ValueError(f"Station identity conflict: {station['station_id']}")
        if not prior:
            additions.append(station)
    return stations, sorted(additions, key=lambda row: row["station_id"])


def stage_shinano_exact_date(*, base, candidate_path, suffix, service_date, valid_until,
                             source_id, weekdays, station_source_id, copy,
                             validate_candidate, verify_existing_service_and_english_name,
                             resolve_stations):
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    validate_candidate(candidate)
    verify_existing_service_and_english_name()
    stations, new_stations = resolve_stations()
    trip = candidate["trip"]
    source = trip["source"]
    trip_id = trip["trip_id"]
    version_id = trip_id + ".version"
    calendar_id = trip_id + ".calendar"
    dimensions = {
        "identity": ("verified", "high", copy["identity_note"]),
        "train_number": ("verified", "high", copy["train_number_note"]),
        "operator": ("unknown", "low", "Publisher identity is not ordered operator-segment evidence."),
        "validity_calendar": ("verified", "high", copy["calendar_note"]),
        "origin_destination": ("verified", "high", "First and last timed passenger calls are printed."),
        "stops": ("verified", "high", copy["stops_note"]),
        "times": ("verified", "high", "All printed arrival/departure minute clocks are retained."),
        "route_lines": ("unknown", "low", "No ordered physical-line evidence is promoted."),
        "station_refs": ("verified", "high", "Names and pinned codes match current JR Central/East groups."),
        "provenance": ("partial", "medium", "Official page is verification-only; redistribution grant unresolved."),
    }
    outputs = {
        base / f"sources/source-registry-{suffix}.jsonl": [source],
        base / f"normalized/station-identities-{suffix}.jsonl": new_stations,
        base / f"normalized/timetable-versions-{suffix}.jsonl": [{
            "timetable_version_id": version_id,
            "operator_scope": "jr-central",
            "effective_from": service_date,
            "effective_until": valid_until,
            "edition_name": copy["edition_name"],
            "revision_type": "source_snapshot",
            "completeness": "partial",
            "source_ids": [source_id],
        }],
        base / f"normalized/calendars/{suffix}/seeds.jsonl": [{
            "calendar_id": calendar_id,
            "valid_from": service_date,
            "valid_until": valid_until,
            "holiday_policy": "none",
            **{weekday: 0 for weekday in weekdays},
        }],
        base / f"normalized/calendar-exceptions/{suffix}/seeds.jsonl": [{
            "calendar_id": calendar_id,
            "service_date": service_date,
            "exception_type": "add",
            "reason": copy["exception_reason"],
            "source_id": source_id,
        }],
        base / f"normalized/trips/{suffix}/seeds.jsonl": [{
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": "shinano",
            "calendar_id": calendar_id,
            "train_number": copy["train_number"],
            "public_number": copy["public_number"],
            "origin_station_id": stations[copy["origin_name"]]["station_id"],
            "destination_station_id": stations[copy["destination_name"]]["station_id"],
            "service_class": "limited_express",
            "direction": trip["direction"],
            "notes": copy["trip_notes"],
        }],
        base / f"normalized/stop-times/{suffix}/seeds.jsonl": [{
            "trip_id": trip_id,
            "stop_sequence": row["stop_sequence"],
            "station_id": stations[row["name_snapshot"]]["station_id"],
            "arrival_time": row["arrival_time"],
            "departure_time": row["departure_time"],
            "day_offset": 0,
            "call_type": row["call_type"],
            "pickup_allowed": 0 if row["call_type"] == "destination" else 1,
            "dropoff_allowed": 0 if row["call_type"] == "origin" else 1,
            "platform": row["platform"],
            "time_accuracy": "minute",
            "source_id": source_id,
        } for row in trip["stop_times"]],
        base / f"normalized/fact-completeness-{suffix}.jsonl": [{
            "entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
            "status": status, "confidence": confidence, "notes": notes,
        } for dimension, (status, confidence, notes) in dimensions.items()],
        base / f"normalized/fact-sources-{suffix}.jsonl": [{
            "entity_type": "trip", "entity_id": trip_id, "field_name": dimension,
            "source_id": station_source_id if dimension == "station_refs" else source_id,
            "page_or_locator": (
                "app/public/rail/jp-2025.json; exact pinned (code, name) match"
                if dimension == "station_refs" else note
            ),
            "confidence": confidence,
            "verification_status": status,
        } for dimension, (status, confidence, note) in dimensions.items()
          if dimension not in {"operator", "route_lines"}],
        base / f"normalized/research-queue-{suffix}.jsonl": [{
            "research_id": f"{trip_id}.{dimension}",
            "entity_type": "trip", "entity_id": trip_id,
            "missing_dimension": dimension,
            "status": "license_blocked" if dimension == "provenance" else "open",
            "notes": notes,
        } for dimension, notes in {
            "operator": "Obtain explicit ordered JR Central / JR East operator-boundary evidence.",
            "route_lines": "Obtain dated ordered physical-line identities and transition boundaries.",
            "provenance": "Resolve permission to redistribute transcribed official timetable facts.",
        }.items()],
    }
    for path, rows in outputs.items():
        emit_jsonl(path, rows)
    print(f"{copy['summary_prefix']}{len(trip['stop_times'])} passenger calls")

# The two procedures below are the shared mains for scripts that were
# already migrated onto this module: JR East single flat columns, and
# JR West Odekake EXPECTED batches. They stay separate from the three
# cluster procedures above.




def stage_jr_east_single_trip(*, base, candidate_path, suffix, trip_id, day, until, source_id, weekdays, platforms, validate, station_ids, rows, write, statuses, copy, extra_outputs=None, clock_fields=None):
    """Stage one reviewed flat column after its script-owned facts are validated."""
    c = json.loads(candidate_path.read_text(encoding='utf-8'))
    validate(c)
    stations = station_ids(c['stops'])
    known = {r['station_id'] for r in rows('normalized/station-identities*.jsonl', base / f'normalized/station-identities-{suffix}.jsonl')}
    station_rows = [{
        'station_id': sid,
        'name_snapshot': name,
        'reference_kind': 'current_n02',
        'current_source_code': sid.removeprefix('jp.n02.'),
        'rail_history_id': None,
    } for (name, sid) in sorted(stations.items()) if sid not in known]
    (vid, cid) = (trip_id + '.version', trip_id + '.calendar')
    stops = []
    for (sequence, (name, arrival, departure)) in enumerate(c['stops'], 1):
        call_type = 'origin' if sequence == 1 else 'destination' if sequence == len(c['stops']) else 'passenger_stop'
        clock_values = clock_fields(arrival, departure) if clock_fields else {
            'arrival_time': arrival,
            'departure_time': departure,
            'day_offset': 0,
        }
        stops.append({
            'trip_id': trip_id,
            'stop_sequence': sequence,
            'station_id': stations[name],
            'arrival_time': clock_values['arrival_time'],
            'departure_time': clock_values['departure_time'],
            'day_offset': clock_values['day_offset'],
            'call_type': call_type,
            'pickup_allowed': int(call_type != 'destination'),
            'dropoff_allowed': int(call_type != 'origin'),
            'platform': platforms.get(name),
            'time_accuracy': 'minute',
            'source_id': source_id,
        })
    completeness = [{
        'entity_type': 'trip',
        'entity_id': trip_id,
        'dimension': dim,
        'status': status,
        'confidence': confidence,
        'notes': note,
    } for (dim, (status, confidence, note)) in statuses.items()]
    facts = [{
        'entity_type': 'trip',
        'entity_id': trip_id,
        'field_name': dim,
        'source_id': 'jtm-current-station-directory' if dim == 'station_refs' else source_id,
        'page_or_locator': 'app/public/rail/jp-2025.json' if dim == 'station_refs' else c['source_locator'],
        'confidence': confidence,
        'verification_status': status,
    } for (dim, (status, confidence, _)) in statuses.items() if status == 'verified']
    queue = [{
        'research_id': f'{trip_id}.{dim}',
        'entity_type': 'trip',
        'entity_id': trip_id,
        'missing_dimension': dim,
        'status': 'open',
        'notes': note,
    } for (dim, (status, _, note)) in statuses.items() if status != 'verified']
    outputs = {
        base / f'sources/source-registry-{suffix}.jsonl': [copy['source_record']],
        base / f'normalized/timetable-versions-{suffix}.jsonl': [
            {
                'timetable_version_id': vid,
                'operator_scope': 'jr-east',
                'effective_from': day,
                'effective_until': until,
                'edition_name': copy['edition_name'],
                'revision_type': 'source_snapshot',
                'completeness': 'partial',
                'source_ids': [source_id],
            },
        ],
        base / f'normalized/station-identities-{suffix}.jsonl': station_rows,
        base / f'normalized/trips/{suffix}/seeds.jsonl': [dict(
            copy['trip_fields'],
            trip_id=trip_id,
            timetable_version_id=vid,
            calendar_id=cid,
            origin_station_id=stations[c['origin']],
            destination_station_id=stations[c['destination']],
        )],
        base / f'normalized/stop-times/{suffix}/seeds.jsonl': stops,
        base / f'normalized/calendars/{suffix}/seeds.jsonl': [
            {
                'calendar_id': cid,
                'valid_from': day,
                'valid_until': until,
                'holiday_policy': 'none',
                **({day: 0 for day in weekdays}),
            },
        ],
        base / f'normalized/calendar-exceptions/{suffix}/seeds.jsonl': [
            {
                'calendar_id': cid,
                'service_date': day,
                'exception_type': 'add',
                'reason': 'September 30 current-variant calendar cell',
                'source_id': source_id,
            },
        ],
        base / f'normalized/fact-completeness-{suffix}.jsonl': completeness,
        base / f'normalized/fact-sources-{suffix}.jsonl': facts,
        base / f'normalized/research-queue-{suffix}.jsonl': queue,
    }
    outputs.update(extra_outputs(c) if extra_outputs else {})
    for (path, records) in outputs.items():
        write(path, records)
    print(copy['summary'])

def stage_odekake_expected_batch(*, base, root, suffix, day, until, expected, load_manifest, rows, write, equipment, source_count, trip_count_error, validate_sources=None):
    """Validate an exact-date Odekake batch completely before emitting its records."""
    candidate = json.loads((base / f'candidates/jr-{suffix}.json').read_text(encoding='utf-8'))
    if (candidate['candidate_status'], candidate['canonical'], candidate['service_date']) != ('visually_reviewed_official_train_pages', False, day):
        raise ValueError('Batch date/status drift')
    if day > load_manifest(base)['as_of_date']:
        raise ValueError('Batch exceeds dataset as-of date')
    selected = {trip['trip_id']: trip for trip in candidate['trips']}
    if len(candidate['trips']) != len(expected) or set(selected) != set(expected):
        raise ValueError(trip_count_error)
    source_path = base / f'sources/source-registry-{suffix}.jsonl'
    sources = {row['source_id']: row for row in (json.loads(line) for line in source_path.read_text(encoding='utf-8').splitlines() if line)}
    if len(sources) != source_count or any((source_id in {row['source_id'] for row in rows('sources/source-registry*.jsonl')} for source_id in sources)):
        raise ValueError('Source registry collision or omission')
    if validate_sources:
        validate_sources(candidate, sources)
    existing_trip_ids = {row['trip_id'] for row in rows('normalized/trips/**/*.jsonl')}
    if existing_trip_ids & set(selected):
        raise ValueError('Trip id collision')
    existing_services = {row['service_id'] for row in rows('normalized/services*.jsonl')}
    package = json.loads((root / 'app/public/rail/jp-2025.json').read_text(encoding='utf-8'))
    station_codes = {(station[0], station[1]) for line in package['lines'] for station in line.get('stations', [])}
    existing_stations = {row.get('current_source_code'): row for row in rows('normalized/station-identities*.jsonl')}
    existing_stations.update({row.get('current_source_code'): row for row in rows('normalized/station-identities/**/*.jsonl')})
    station_additions = []
    (versions, calendars, exceptions, trips, stops, formations) = ([], [], [], [], [], [])
    (fact_rows, completeness, research) = ([], [], [])
    for (tid, spec) in expected.items():
        item = selected[tid]
        (service, public, number, label, page) = spec['identity']
        source_id = f'jr-west-odekake-{service}{public}-{number.lower()}-20260930'
        url = f'https://timetable.jr-odekake.net/train-timetable/{page}?date=20260930'
        if (item['service_id'], item['public_number'], item['train_number'], item['operation_label'], item['source_id'], item['source_url'], item['printed_equipment']) != (service, public, number, label, source_id, url, spec['equipment']):
            raise ValueError(f'Train identity/equipment drift: {tid}')
        if (sources[source_id]['url_or_locator'], sources[source_id]['effective_date'], sources[source_id]['redistribution_status']) != (url, day, 'verification_only'):
            raise ValueError(f'Official source drift: {tid}')
        if service not in existing_services:
            raise ValueError(f'Service identity missing: {service}')
        calls = [(stop['name'], stop['code'], stop['arrival'], stop['departure'], stop['platform']) for stop in item['stops']]
        if calls != spec['calls'] or [stop['call_type'] for stop in item['stops']] != ['origin'] + ['passenger_stop'] * (len(calls) - 2) + ['destination']:
            raise ValueError(f'Printed passenger calls drift: {tid}')
        for (name, code, *_) in calls:
            if (code, name) not in station_codes:
                raise ValueError(f'N02 station mismatch: {name}')
            prior = existing_stations.get(code)
            if prior and prior['name_snapshot'] != name:
                raise ValueError(f'Conflicting station identity: {name}')
            if prior is None:
                station_additions.append({
                    'station_id': 'jp.n02.' + code,
                    'name_snapshot': name,
                    'reference_kind': 'current_n02',
                    'current_source_code': code,
                })
                existing_stations[code] = station_additions[-1]
        (version, calendar) = (tid + '.version', tid + '.calendar')
        versions.append({
            'timetable_version_id': version,
            'operator_scope': 'jr-west',
            'effective_from': day,
            'effective_until': until,
            'edition_name': f'JR Odekake {day} {service} {public}',
            'revision_type': 'observed_date',
            'completeness': 'partial',
            'source_ids': [source_id],
        })
        calendars.append({
            'calendar_id': calendar,
            'valid_from': day,
            'valid_until': until,
            'holiday_policy': 'none',
            **({day: 0 for day in ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')}),
        })
        exceptions.append({
            'calendar_id': calendar,
            'service_date': day,
            'exception_type': 'add',
            'reason': 'Selected exact-date official variant',
            'source_id': source_id,
        })
        trips.append({
            'trip_id': tid,
            'timetable_version_id': version,
            'service_id': service,
            'calendar_id': calendar,
            'train_number': number,
            'public_number': public,
            'origin_station_id': 'jp.n02.' + calls[0][1],
            'destination_station_id': 'jp.n02.' + calls[-1][1],
            'service_class': 'limited_express',
            'notes': 'Only selected date staged; physical route and train operator remain unresolved.',
        })
        stops.extend(({
            'trip_id': tid,
            'stop_sequence': index,
            'station_id': 'jp.n02.' + code,
            'arrival_time': arrival,
            'departure_time': departure,
            'day_offset': 0,
            'platform': platform,
            'call_type': kind,
            'pickup_allowed': int(kind != 'destination'),
            'dropoff_allowed': int(kind != 'origin'),
            'time_accuracy': 'minute',
            'source_id': source_id,
        } for (index, (name, code, arrival, departure, platform)) in enumerate(calls, 1) for kind in [item['stops'][index - 1]['call_type']]))
        (formation, equipment_facts) = equipment(item, tid, source_id)
        formations.append(formation)
        verified = {
            'identity': 'Named exact-date train',
            'train_number': number,
            'validity_calendar': 'Selected September 30 variant',
            'origin_destination': 'Printed termini',
            'stops': f'{len(calls)} timed passenger calls',
            'times': 'Printed minute clocks',
            'station_refs': 'Current N02 station identities',
        }
        fact_rows.extend(({
            'entity_type': 'trip',
            'entity_id': tid,
            'field_name': field,
            'source_id': 'jtm-current-station-directory' if field == 'station_refs' else source_id,
            'page_or_locator': locator,
            'confidence': 'high',
            'verification_status': 'verified',
        } for (field, locator) in verified.items()))
        fact_rows.extend(equipment_facts)
        completeness.extend(({
            'entity_type': 'trip',
            'entity_id': tid,
            'dimension': field,
            'status': 'verified',
            'confidence': 'high',
            'notes': locator,
        } for (field, locator) in verified.items()))
        completeness.extend(({
            'entity_type': 'trip',
            'entity_id': tid,
            'dimension': dimension,
            'status': status,
            'confidence': confidence,
            'notes': note,
        } for (dimension, status, confidence, note) in [('formation', 'partial', 'high', 'Planned seat categories only.'), ('route_lines', 'unknown', 'low', 'Daily physical route unverified.'), ('operator', 'unknown', 'low', 'Train-operation segments unverified.')]))
        research.extend(({
            'research_id': f'{tid}.{dimension}',
            'entity_type': 'trip',
            'entity_id': tid,
            'missing_dimension': dimension,
            'status': 'open',
            'notes': note,
        } for (dimension, note) in [('route_lines', 'Confirm exact-day physical route.'), ('operator', 'Confirm train-operation company segments.')]))
    outputs = {
        f'normalized/station-identities-{suffix}.jsonl': station_additions,
        f'normalized/timetable-versions-{suffix}.jsonl': versions,
        f'normalized/calendars/{suffix}/seeds.jsonl': calendars,
        f'normalized/calendar-exceptions/{suffix}/seeds.jsonl': exceptions,
        f'normalized/trips/{suffix}/seeds.jsonl': trips,
        f'normalized/stop-times/{suffix}/seeds.jsonl': stops,
        f'normalized/trip-formations/{suffix}/seeds.jsonl': formations,
        f'normalized/fact-sources-{suffix}.jsonl': fact_rows,
        f'normalized/fact-completeness-{suffix}.jsonl': completeness,
        f'normalized/research-queue-{suffix}.jsonl': research,
    }
    for (path, records) in outputs.items():
        write(base / path, records)
    print(f'Staged {len(trips)} exact-date trips with {len(stops)} passenger calls')
