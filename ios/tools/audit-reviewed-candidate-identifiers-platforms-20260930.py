#!/usr/bin/env python3
"""Read-only check of reviewed September 30 train numbers, clocks and platforms.

Run after rebuilding train-service-timetable.sqlite. The check requires each
candidate's explicit trip ID to materialize on the selected day and verifies
the SQLite template plus dated platform override, without mutating either.
"""

import json
import sqlite3
from pathlib import Path
import sys
import unicodedata

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DB = BASE / "derived/train-service-timetable.sqlite"
DAY = "2026-09-30"


def selected_for_day(candidate, parent, path):
    date = candidate.get("service_date", parent.get("service_date"))
    if date is not None:
        return date == DAY
    dates = (candidate.get("service_dates") or parent.get("service_dates")
             or candidate.get("operating_dates") or parent.get("operating_dates"))
    if dates is not None:
        return DAY in dates
    return "20260930" in path.name


def candidate_items(path):
    parent = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(parent, dict):
        return
    items = [parent]
    for key in ("trip", "trips", "platforms"):
        value = parent.get(key)
        if isinstance(value, dict):
            items.append(value)
        elif isinstance(value, list):
            items.extend(row for row in value if isinstance(row, dict))
    for item in items:
        if selected_for_day(item, parent, path):
            yield parent, item


def resolve_trip_id(item, parent, path, materialized, station_names):
    if item.get("trip_id"):
        return item["trip_id"]
    number = item.get("train_number", parent.get("train_number"))
    if not number:
        return None
    operator = "-".join(path.name.split("-", 2)[:2])
    matches = [trip for trip in materialized.values()
               if trip.get("train_number") == number
               and trip["trip_id"].startswith(operator + ".")]
    service_id = (item.get("service_id") or parent.get("service_id")
                  or (parent.get("service") or {}).get("service_id"))
    if service_id:
        matches = [trip for trip in matches if trip["service_id"] == service_id]
    public_number = item.get("public_number", parent.get("public_number"))
    if public_number is not None:
        matches = [trip for trip in matches if trip.get("public_number") == str(public_number)]
    if len(matches) > 1:
        clocks = printed_clocks(item)
        if clocks:
            first_station = clocks[0][1]
            matches = [trip for trip in matches if any(
                station_key(station_names[stop["station_id"]]) == station_key(first_station)
                for stop in trip["stop_times"])]
    if len(matches) == 1:
        return matches[0]["trip_id"]
    return None


def printed_platforms(item):
    facts = list((item.get("printed_platforms") or {}).items())
    for key in ("stops", "stop_times", "passenger_calls", "passenger_stops"):
        for stop in item.get(key, []):
            if not isinstance(stop, dict) or stop.get("platform") is None:
                continue
            station = next((stop[name] for name in
                            ("station_name", "name_snapshot", "name", "station")
                            if stop.get(name)), None)
            if station:
                facts.append((station, stop["platform"]))
    if item.get("platform") is not None and item.get("station_name"):
        facts.append((item["station_name"], item["platform"]))
    return facts


def printed_clocks(item):
    for key in ("stops", "stop_times", "passenger_calls", "passenger_stops"):
        value = item.get(key)
        if not isinstance(value, list):
            continue
        facts = []
        for index, stop in enumerate(value, 1):
            if isinstance(stop, list) and len(stop) >= 3:
                facts.append((index, stop[0], stop[1], stop[2], None, None, None))
                continue
            if not isinstance(stop, dict):
                continue
            station = next((stop[name] for name in
                            ("station_name", "name_snapshot", "name", "station")
                            if stop.get(name)), None)
            if not station:
                continue
            if not any(name in stop for name in
                       ("arrival_time", "departure_time", "arrival", "departure")):
                continue
            arrival = stop.get("arrival_time", stop.get("arrival"))
            departure = stop.get("departure_time", stop.get("departure"))
            facts.append((stop.get("stop_sequence", index), station, arrival, departure,
                          stop.get("day_offset"),
                          stop.get("arrival_day_offset"), stop.get("departure_day_offset")))
        if facts:
            return facts
    return []


def clock(value):
    if value is None:
        return None
    hour, minute = str(value).split(":")
    return (int(hour) % 24) * 60 + int(minute)


def printed_day_offset(value, explicit):
    if explicit is not None or value is None:
        return explicit
    hour = int(str(value).split(":")[0])
    return hour // 24 if hour >= 24 else None


def station_key(value):
    return (unicodedata.normalize("NFKC", value)
            .replace("柳ケ浦", "柳ヶ浦").replace("天ケ瀬", "天ヶ瀬")
            .replace("姉ケ崎", "姉ヶ崎").replace("茅ケ崎", "茅ヶ崎"))


def main():
    manifest = timetable.load_manifest(BASE)
    data, origins = timetable.load_dataset(BASE, manifest)
    errors = timetable.validate_dataset(data, origins, manifest)
    if errors:
        raise ValueError(errors)
    materialized = {trip["trip_id"]: trip for trip in timetable.materialize(data, DAY)}
    station_names = {row["station_id"]: row["name_snapshot"]
                     for row in data["station_identities"]}
    source_urls = {row["source_id"]: row["url_or_locator"]
                   for row in data["source_documents"]}
    connection = sqlite3.connect(DB)
    connection.row_factory = sqlite3.Row
    problems = []
    checked = set()
    numbers = platforms = clocks = offsets = segments = formations = rollovers = 0
    for path in sorted((BASE / "candidates").glob("*.json")):
        for parent, item in candidate_items(path):
            number = item.get("train_number", parent.get("train_number"))
            platform_facts = printed_platforms(item)
            clock_facts = printed_clocks(item)
            if not number and not platform_facts and not clock_facts:
                continue
            trip_id = resolve_trip_id(item, parent, path, materialized, station_names)
            source = (item.get("source_url") or parent.get("source_url")
                      or source_urls.get(item.get("source_id"))
                      or (item.get("source") or {}).get("url_or_locator") or path.name)
            if trip_id is None or trip_id not in materialized:
                problems.append(f"{path.name}: {item.get('trip_id') or number} absent or "
                                f"ambiguous on {DAY}; source {source}")
                continue
            trip = materialized[trip_id]
            stored_trip = connection.execute(
                """SELECT COALESCE(o.train_number, t.train_number) AS train_number
                   FROM trips AS t
                   LEFT JOIN trip_train_number_overrides AS o
                     ON o.trip_id=t.trip_id AND o.service_date=?
                   WHERE t.trip_id=?""", (DAY, trip_id)).fetchone()
            if stored_trip is None:
                problems.append(f"{path.name}: {trip_id} absent in SQLite; source {source}")
                continue
            if number:
                key = (trip_id, "train_number", number)
                if key not in checked:
                    checked.add(key)
                    numbers += 1
                    if trip.get("train_number") != number:
                        problems.append(f"{path.name}: {trip_id} train_number {number!r} "
                                        f"vs normalized {trip.get('train_number')!r}; source {source}")
                    if stored_trip["train_number"] != number:
                        problems.append(f"{path.name}: {trip_id} train_number {number!r} "
                                        f"vs SQLite {stored_trip['train_number']!r}; "
                                        f"source {source}")
            expected_segments = item.get("train_number_segments")
            if expected_segments is not None and (trip_id, "number_segments") not in checked:
                checked.add((trip_id, "number_segments"))
                expected = sorted((row["from_sequence"], row["to_sequence"], row["train_number"])
                                  for row in expected_segments)
                normalized_segments = sorted((row["from_sequence"], row["to_sequence"], row["train_number"])
                                             for row in data["trip_number_segments"] if row["trip_id"] == trip_id)
                stored_segments = sorted(tuple(row) for row in connection.execute(
                    "SELECT from_sequence,to_sequence,train_number FROM trip_number_segments WHERE trip_id=?",
                    (trip_id,)).fetchall())
                segments += len(expected)
                if normalized_segments != expected:
                    problems.append(f"{path.name}: {trip_id} train-number segments {expected!r} "
                                    f"vs normalized {normalized_segments!r}; source {source}")
                if stored_segments != expected:
                    problems.append(f"{path.name}: {trip_id} train-number segments {expected!r} "
                                    f"vs SQLite {stored_segments!r}; source {source}")
            formation_evidence = item.get("formation_evidence") or parent.get("formation_evidence")
            if formation_evidence and (trip_id, "formation_evidence") not in checked:
                checked.add((trip_id, "formation_evidence"))
                formations += 1
                expected = (formation_evidence["vehicle_series"], formation_evidence["car_count"],
                            formation_evidence["evidence_kind"])
                normalized_formations = [row for row in data["trip_formations"]
                                         if row["trip_id"] == trip_id and row["service_date"] == DAY]
                stored_formations = connection.execute(
                    "SELECT vehicle_series,car_count,evidence_kind FROM trip_formations "
                    "WHERE trip_id=? AND service_date=?", (trip_id, DAY)).fetchall()
                for label, rows in (("normalized", normalized_formations), ("SQLite", stored_formations)):
                    actual = [(row["vehicle_series"], row["car_count"], row["evidence_kind"])
                              for row in rows]
                    if actual != [expected]:
                        problems.append(f"{path.name}: {trip_id} planned formation {expected!r} "
                                        f"vs {label} {actual!r}; source {source}")
            rollover = item.get("overnight_rollover") or parent.get("overnight_rollover")
            if rollover and (trip_id, "overnight_rollover") not in checked:
                checked.add((trip_id, "overnight_rollover"))
                rollover_stops = [(sequence, station) for sequence, station, *_ in clock_facts]
                starts = [sequence for sequence, station in rollover_stops
                          if station_key(station) == station_key(rollover["from_station"])]
                if len(starts) != 1:
                    problems.append(f"{path.name}: {trip_id} overnight start station ambiguous; source {source}")
                else:
                    start = starts[0]
                    expected_offset = rollover["day_offset"]
                    normalized_rollover = [(stop["stop_sequence"], stop.get("day_offset"))
                                           for stop in trip["stop_times"] if stop["stop_sequence"] >= start]
                    stored_rollover = [(row[0], row[1]) for row in connection.execute(
                        "SELECT stop_sequence,day_offset FROM stop_times WHERE trip_id=? "
                        "AND stop_sequence>=? ORDER BY stop_sequence", (trip_id, start))]
                    for label, rows in (("normalized", normalized_rollover), ("SQLite", stored_rollover)):
                        if not rows or any(offset != expected_offset for _, offset in rows):
                            problems.append(f"{path.name}: {trip_id} overnight offset "
                                            f"{expected_offset} vs {label} {rows!r}; source {source}")
                    rollovers += 1
            for station, expected in platform_facts:
                key = (trip_id, "platform", station, expected)
                if key in checked:
                    continue
                checked.add(key)
                platforms += 1
                normalized = [stop for stop in trip["stop_times"]
                              if station_key(station_names[stop["station_id"]]) == station_key(station)]
                if len(normalized) != 1 or normalized[0].get("platform") != expected:
                    got = [(stop["stop_sequence"], stop.get("platform"))
                           for stop in normalized]
                    problems.append(f"{path.name}: {trip_id} {station} platform {expected!r} "
                                    f"vs normalized {got}; source {source}")
                stored = connection.execute(
                    """SELECT s.stop_sequence, i.name_snapshot,
                              CASE WHEN o.platform_override_present=1
                                   THEN o.platform_override ELSE s.platform END AS platform
                       FROM stop_times AS s
                       JOIN station_identities AS i ON i.station_id=s.station_id
                       LEFT JOIN trip_stop_time_overrides AS o
                         ON o.trip_id=s.trip_id AND o.stop_sequence=s.stop_sequence
                        AND o.service_date=?
                       WHERE s.trip_id=?""",
                    (DAY, trip_id)).fetchall()
                stored = [row for row in stored
                          if station_key(row["name_snapshot"]) == station_key(station)]
                if len(stored) != 1 or stored[0]["platform"] != expected:
                    got = [(row["stop_sequence"], row["platform"]) for row in stored]
                    problems.append(f"{path.name}: {trip_id} {station} platform {expected!r} "
                                    f"vs SQLite {got}; source {source}")
            for sequence, station, arrival, departure, day_offset, arrival_offset, departure_offset in clock_facts:
                key = (trip_id, "clocks", sequence, station, arrival, departure, day_offset,
                       arrival_offset, departure_offset)
                if key in checked:
                    continue
                checked.add(key)
                clocks += 1
                normalized = [stop for stop in trip["stop_times"]
                              if stop["stop_sequence"] == sequence]
                stored = connection.execute(
                    """SELECT s.stop_sequence, s.station_id,
                              COALESCE(o.arrival_override,s.arrival_time) AS arrival_time,
                              COALESCE(o.departure_override,s.departure_time) AS departure_time,
                              CASE WHEN o.arrival_override IS NOT NULL
                                   THEN COALESCE(o.arrival_day_offset_override,
                                                 s.arrival_day_offset,s.day_offset)
                                   ELSE COALESCE(s.arrival_day_offset,s.day_offset) END
                                   AS arrival_day_offset,
                              CASE WHEN o.departure_override IS NOT NULL
                                   THEN COALESCE(o.departure_day_offset_override,
                                                 s.departure_day_offset,s.day_offset)
                                   ELSE COALESCE(s.departure_day_offset,s.day_offset) END
                                   AS departure_day_offset
                       FROM stop_times AS s
                       LEFT JOIN trip_stop_time_overrides AS o
                         ON o.trip_id=s.trip_id AND o.stop_sequence=s.stop_sequence
                        AND o.service_date=?
                       WHERE s.trip_id=? AND s.stop_sequence=?""",
                    (DAY, trip_id, sequence)).fetchall()
                for label, rows in (("normalized", normalized), ("SQLite", stored)):
                    if len(rows) != 1:
                        problems.append(f"{path.name}: {trip_id} stop {sequence} {station} expected one stop "
                                        f"vs {label} {len(rows)}; source {source}")
                        continue
                    row = rows[0]
                    actual_station = station_names[row["station_id"]]
                    if station_key(actual_station) != station_key(station):
                        problems.append(f"{path.name}: {trip_id} stop {sequence} station "
                                        f"{station!r} vs {label} {actual_station!r}; source {source}")
                    if (clock(row["arrival_time"]), clock(row["departure_time"])) != (
                            clock(arrival), clock(departure)):
                        problems.append(f"{path.name}: {trip_id} {station} arrival/departure "
                                        f"{arrival!r}/{departure!r} vs {label} "
                                        f"{row['arrival_time']!r}/{row['departure_time']!r}; "
                                        f"source {source}")
                    for side, expected_offset in (("arrival", printed_day_offset(
                            arrival, arrival_offset if arrival_offset is not None else day_offset)),
                                                  ("departure", printed_day_offset(
                            departure, departure_offset if departure_offset is not None else day_offset))):
                        if expected_offset is None or (arrival if side == "arrival" else departure) is None:
                            continue
                        offsets += 1
                        actual_offset = (timetable.stop_day_offset(row, side) if label == "normalized"
                                         else row[f"{side}_day_offset"])
                        if actual_offset != expected_offset:
                            problems.append(f"{path.name}: {trip_id} {station} {side} "
                                            f"day_offset {expected_offset} vs {label} "
                                            f"{actual_offset}; source {source}")
    connection.close()
    print(f"Reviewed {numbers} train numbers, {segments} numbered segments, "
          f"{formations} sourced formations, {platforms} printed platforms, "
          f"{clocks} stop clocks, {offsets // 2} explicit offset checks "
          f"and {rollovers} overnight rollovers "
          f"against {DB.name} for {DAY}.")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
