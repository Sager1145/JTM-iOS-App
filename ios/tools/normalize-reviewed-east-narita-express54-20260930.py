#!/usr/bin/env python3
"""Stage the two source-pinned Narita Express 54 branches for September 30."""

import json
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "east-narita-express54-20260930"
CANDIDATE = BASE / "candidates/jr-east-narita-express54-20260930.json"
DAY, NEXT_DAY = "2026-09-30", "2026-10-01"
SOURCE = "jr-east-narita-express54-20260930"
URL = "https://timetables.jreast.co.jp/2610/train/030/031291.html"
SERVICE = "narita-express"
STATION_NAME_ALIASES = {"空港第２ビル": "空港第2ビル"}
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED = {
    "2005M": ("大船", "成田空港", 9, "06:38", "08:36"),
    "2205M": ("新宿", "成田空港", 7, "07:07", None),
}


def read_rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude:
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line)


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


PINNED = {'candidate_id': 'jr-east-narita-express54-20260930',
 'candidate_status': 'reviewed_official_html',
 'canonical': False,
 'service_date': '2026-09-30',
 'source_id': 'jr-east-narita-express54-20260930',
 'source_url': 'https://timetables.jreast.co.jp/2610/train/030/031291.html',
 'source_locator': '2026年9月30日 td.ok; full printed numbered columns',
 'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
 'coupling_note': '成田空港－東京は2254Mを併結 / 成田空港－東京は2054Mに併結',
 'printed_operating_labels': ['１１月６日は運休 １１月７日は運休', '１１月６日は運休 １１月７日は運休'],
 'printed_remarks': ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です'],
 'trips': [{'trip_id': 'jr-east.narita-express.54.2054m.exact-2026-09-30',
            'train_number': '2054M',
            'origin': '成田空港',
            'destination': '大船',
            'stops': [['成田空港', None, '21:44', None, 'origin'],
                      ['空港第２ビル', '21:45', '21:47', None, 'passenger_stop'],
                      ['東京', '22:37', '22:39', '１', 'passenger_stop'],
                      ['品川', '22:46', '22:47', '１５', 'passenger_stop'],
                      ['武蔵小杉', '22:56', '22:57', None, 'passenger_stop'],
                      ['横浜', '23:07', '23:09', '９', 'passenger_stop'],
                      ['戸塚', '23:18', '23:19', None, 'passenger_stop'],
                      ['大船', '23:24', None, '８', 'destination']],
            'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
            'formation': None},
           {'trip_id': 'jr-east.narita-express.54.2254m.exact-2026-09-30',
            'train_number': '2254M',
            'origin': '成田空港',
            'destination': '新宿',
            'stops': [['成田空港', None, None, None, 'origin'],
                      ['空港第２ビル', None, None, None, 'passenger_stop'],
                      ['東京', None, '22:43', '１', 'passenger_stop'],
                      ['品川', None, None, None, 'pass'],
                      ['渋谷', '23:06', '23:07', None, 'passenger_stop'],
                      ['新宿', '23:12', None, '５', 'destination']],
            'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
            'formation': None}]}


def validate(candidate):
    if candidate != PINNED:
        raise ValueError('Source-pinned column, calendar, seat or coupling fact changed')
    return candidate['trips']


def station_ids(trips):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    names = {stop[0] for trip in trips for stop in trip["stops"]}
    result = {}
    for name in names:
        directory_name = STATION_NAME_ALIASES.get(name, name)
        codes = {station[0] for line in package["lines"] if line["operator"] == "東日本旅客鉄道"
                 for station in line["stations"] if station[1] == directory_name}
        if name in {"東京", "武蔵小杉"}:
            codes &= {"東京": {"003766"}, "武蔵小杉": {"004301"}}[name]
        if len(codes) != 1:
            raise ValueError(f"Ambiguous JR East station group for {name}: {sorted(codes)}")
        result[name] = "jp.n02." + next(iter(codes))
    return result


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    trips = validate(candidate)
    stations = station_ids(trips)
    known_stations = {row["station_id"] for row in read_rows(
        "normalized/station-identities*.jsonl", BASE / f"normalized/station-identities-{SUFFIX}.jsonl")}
    station_rows = [{"station_id": sid, "name_snapshot": STATION_NAME_ALIASES.get(name, name),
                     "reference_kind": "current_n02", "current_source_code": sid.removeprefix("jp.n02."),
                     "rail_history_id": None} for name, sid in sorted(stations.items()) if sid not in known_stations]
    versions, trip_rows, stop_rows, calendars, exceptions = [], [], [], [], []
    completeness, facts, queue = [], [], []
    for trip in trips:
        tid, number = trip["trip_id"], trip["train_number"]
        version, calendar = tid + ".version", tid + ".calendar"
        complete = all(stop[1] or stop[2] or stop[4]=='pass' for stop in trip['stops'])
        versions.append({"timetable_version_id": version, "operator_scope": "jr-east",
                         "effective_from": DAY, "effective_until": NEXT_DAY,
                         "edition_name": f"JR時刻表2026年10月号; 成田エクスプレス54号 {number} exact 9/30",
                         "revision_type": "source_snapshot", "completeness": "partial", "source_ids": [SOURCE]})
        trip_rows.append({"trip_id": tid, "timetable_version_id": version, "service_id": SERVICE,
                          "calendar_id": calendar, "train_number": number, "public_number": "54",
                          "origin_station_id": stations[trip["origin"]],
                          "destination_station_id": stations[trip["destination"]],
                          "service_class": "limited_express",
                          "notes": '成田空港－東京は2254Mを併結 / 成田空港－東京は2054Mに併結 ' + ("This column prints all passenger-call clocks."
                          if complete else "After Tokyo this column prints no independent clock or platform; unknown cells remain null.")})
        for sequence, (name, arrival, departure, platform, call_type) in enumerate(trip["stops"], 1):
            stop_rows.append({"trip_id": tid, "stop_sequence": sequence, "station_id": stations[name],
                              "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
                              "call_type": call_type,
                              "pickup_allowed": int(call_type in {"origin", "passenger_stop"}),
                              "dropoff_allowed": int(call_type in {"passenger_stop", "destination"}),
                              "platform": platform,
                              "time_accuracy": "minute" if arrival or departure else "unknown",
                              "source_id": SOURCE})
        calendars.append({"calendar_id": calendar, "valid_from": DAY, "valid_until": NEXT_DAY,
                          "holiday_policy": "none", **{weekday: 0 for weekday in WEEKDAYS}})
        exceptions.append({"calendar_id": calendar, "service_date": DAY, "exception_type": "add",
                           "reason": "September 30 current-variant calendar cell", "source_id": SOURCE})
        statuses = {
            "identity": ("verified", "high", "Official numbered-column Narita Express 54 page."),
            "train_number": ("verified", "high", f"Official column prints {number}."),
            "validity_calendar": ("verified", "high", "September 30 uses this displayed variant."),
            "origin_destination": ("verified", "high", "Official title names both branch endpoints."),
            "stops": (("verified", "high", "All passenger calls in this column printed.") if complete else
                      ("partial", "medium", "Pre-Tokyo coupled-column cells are blank; shared calls follow coupling note.")),
            "times": (("verified", "high", "All printed passenger-call clocks captured.") if complete else
                      ("partial", "medium", "Tokyo arrival and all earlier coupled-column clocks are unprinted.")),
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
                              "source_id": "jtm-current-station-directory" if dimension == "station_refs" else SOURCE,
                              "page_or_locator": "app/public/rail/jp-2025.json" if dimension == "station_refs" else candidate["source_locator"],
                              "confidence": confidence, "verification_status": status})
            if status != "verified":
                queue.append({"research_id": f"{tid}.{dimension}", "entity_type": "trip", "entity_id": tid,
                              "missing_dimension": dimension, "status": "open", "notes": note})
    relations = [{'trip_id': 'jr-east.narita-express.54.2054m.exact-2026-09-30', 'related_trip_id': 'jr-east.narita-express.54.2254m.exact-2026-09-30', 'relation_type': 'couples_with', 'from_sequence': 1, 'to_sequence': 3, 'source_id': 'jr-east-narita-express54-20260930'}, {'trip_id': 'jr-east.narita-express.54.2254m.exact-2026-09-30', 'related_trip_id': 'jr-east.narita-express.54.2054m.exact-2026-09-30', 'relation_type': 'couples_with', 'from_sequence': 1, 'to_sequence': 3, 'source_id': 'jr-east-narita-express54-20260930'}]
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": [{
            "source_id": SOURCE, "publisher": "東日本旅客鉄道株式会社 / 株式会社交通新聞社",
            "title": "成田エクスプレス 54号 2054M / 2254M 停車駅一覧",
            "source_type": "official_train_timetable", "url_or_locator": URL,
            "issue": "JR時刻表2026年10月号", "publication_date": None,
            "effective_date": DAY, "accessed_at": DAY,
            "license_status": "no_reuse_grant_identified", "redistribution_status": "verification_only",
            "automated_extraction_allowed": False,
            "notes": "September30 td.ok and full printed columns verified; unprinted cells remain unknown.",
        }],
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_rows,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": trip_rows,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_rows,
        BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl": relations,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": facts,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": queue,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print('Staged NEX54: 2 trips')


if __name__ == "__main__":
    main()
