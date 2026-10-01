#!/usr/bin/env python3
"""Check dated, materialized stop clocks, including exact-date overrides."""

from collections import defaultdict
from datetime import date, timedelta
import json

from train_timetable import (
    DEFAULT_CANONICAL, calendar_operates, load_dataset, load_manifest,
    materialize, service_seconds, stop_day_offset, validate_dataset, write_json,
)


def represented_dates(data, manifest):
    versions = {row["timetable_version_id"]: row for row in data["timetable_versions"]}
    calendars = {row["calendar_id"]: row for row in data["calendars"]}
    exceptions = {(row["calendar_id"], row["service_date"]): row["exception_type"]
                  for row in data["calendar_exceptions"]}
    additions = defaultdict(set)
    for row in data["calendar_exceptions"]:
        if row["exception_type"] == "add":
            additions[row["calendar_id"]].add(date.fromisoformat(row["service_date"]))
    holidays = {row["service_date"] for row in data["holiday_dates"]}
    holiday_years = {row["year"]: row["status"] for row in data["holiday_calendar_years"]}
    earliest = date.fromisoformat(manifest["first_scope_date"])
    latest = date.fromisoformat(manifest["as_of_date"]) + timedelta(days=1)
    dates = set()
    for trip in data["trips"]:
        version = versions[trip["timetable_version_id"]]
        calendar = calendars[trip["calendar_id"]]
        start = max(earliest, date.fromisoformat(version["effective_from"]),
                    date.fromisoformat(calendar["valid_from"]))
        end = min(latest, date.fromisoformat(version["effective_until"]),
                  date.fromisoformat(calendar["valid_until"]))
        if start >= end:
            continue
        if any(calendar[weekday] for weekday in (
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
        )):
            candidates = (start + timedelta(days=offset) for offset in range((end - start).days))
        else:
            candidates = additions[calendar["calendar_id"]]
        dates.update(day for day in candidates if start <= day < end and
                     calendar_operates(calendar, day, exceptions, holidays, holiday_years))
    return sorted(dates)


def main():
    manifest = load_manifest(DEFAULT_CANONICAL)
    data, origins = load_dataset(DEFAULT_CANONICAL, manifest)
    errors = validate_dataset(data, origins, manifest)
    if errors:
        raise SystemExit("\n".join(errors))
    covered_overrides = {(row["trip_id"], row["service_date"], row["stop_sequence"])
                         for row in data["trip_stop_time_overrides"]}
    findings = []
    occurrence_count = 0
    checked_clocks = 0
    applied_overrides = 0
    blank_passenger_calls = 0
    blank_by_trip = defaultdict(lambda: {"service_dates": set(), "stop_sequences": set(),
                                       "blank_calls": 0})
    dates = represented_dates(data, manifest)
    for day in dates:
        for occurrence in materialize(data, day):
            occurrence_count += 1
            previous = None
            for stop in occurrence["stop_times"]:
                key = (occurrence["trip_id"], occurrence["service_date"], stop["stop_sequence"])
                applied_overrides += key in covered_overrides
                if (stop["call_type"] == "passenger_stop" and
                    stop.get("arrival_time") is None and stop.get("departure_time") is None):
                    blank_passenger_calls += 1
                    blank = blank_by_trip[occurrence["trip_id"]]
                    blank["service_dates"].add(occurrence["service_date"])
                    blank["stop_sequences"].add(stop["stop_sequence"])
                    blank["blank_calls"] += 1
                arrival = service_seconds(stop.get("arrival_time"), stop_day_offset(stop, "arrival"),
                                          f"{key}.arrival_time")
                departure = service_seconds(stop.get("departure_time"), stop_day_offset(stop, "departure"),
                                            f"{key}.departure_time")
                if arrival is not None and departure is not None and arrival > departure:
                    findings.append({"tripId": key[0], "serviceDate": key[1],
                                     "stopSequence": key[2], "reason": "arrival_after_departure"})
                for side, current in (("arrival", arrival), ("departure", departure)):
                    if current is None:
                        continue
                    checked_clocks += 1
                    if previous is not None and current < previous:
                        findings.append({"tripId": key[0], "serviceDate": key[1],
                                         "stopSequence": key[2], "side": side,
                                         "reason": "known_clock_moves_backward"})
                    previous = current
    coverage = json.loads((DEFAULT_CANONICAL / "audits/train-timetable-coverage.json").read_text())
    if occurrence_count != coverage["dailyOccurrencesRepresented"]:
        raise SystemExit(f"Occurrence audit mismatch: {occurrence_count} versus coverage "
                         f"{coverage['dailyOccurrencesRepresented']}")
    report = {"schemaVersion": 1, "asOfDate": manifest["as_of_date"],
              "status": "structural_pass" if not findings else "structural_fail",
              "sourceTruthVerified": False, "distinctServiceDates": len(dates),
              "occurrencesChecked": occurrence_count, "knownClockCellsChecked": checked_clocks,
              "appliedOverrideStops": applied_overrides,
              "passengerCallsWithNeitherClock": blank_passenger_calls,
              "blankPassengerCallsByTrip": [
                  {"tripId": trip_id, "occurrencesWithBlankCalls": len(blank["service_dates"]),
                   "blankCalls": blank["blank_calls"],
                   "distinctStopSequences": sorted(blank["stop_sequences"]),
                   "serviceDates": sorted(blank["service_dates"])}
                  for trip_id, blank in sorted(blank_by_trip.items())
              ],
              "findings": findings}
    write_json(DEFAULT_CANONICAL / "audits/train-timetable-stop-chronology.json", report)
    print(f"Dated stop chronology: {occurrence_count} occurrences, {checked_clocks} known clocks, "
          f"{len(findings)} structural findings")
    if findings:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
