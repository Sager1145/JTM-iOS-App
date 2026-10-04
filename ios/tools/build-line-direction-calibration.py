#!/usr/bin/env python3
"""Calibrate which package station-index sign means 下り.

Reads the bundled timetable (trips.direction up/down, including Japanese
上り/下り) and the JP compact package. Consecutive trip stops that both lie
on a line cast one vote: sign of the station-index change, times the trip's
direction label, is the index sign that means 下り. A line is written only
when at least 3 trips vote and at least 90% of the pair votes agree.

Stop N02 codes are mapped to the package's station ids through
app/data/stations.json n02_group_code. A trip has one direction label, so
its pairs vote only for the line (or tied lines) that contain the most of
its stops. A one-interval step onto another railway does not calibrate that
railway. The SQLite file is opened read-only.
"""
import json
import sqlite3
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "app/public/rail/jp-2025.json"
STATIONS = ROOT / "app/data/stations.json"
DATABASE = ROOT / "ios/RailKit/Sources/RailCore/Resources/train-service-timetable.sqlite"
OUTPUT = ROOT / "ios/RailKit/Sources/RailCore/Resources/line-direction-calibration.json"

JR_OPERATORS = (
    "北海道旅客鉄道",
    "東日本旅客鉄道",
    "東海旅客鉄道",
    "西日本旅客鉄道",
    "四国旅客鉄道",
    "九州旅客鉄道",
)
MIN_TRIPS = 3
MIN_AGREEMENT_NUMERATOR = 9
MIN_AGREEMENT_DENOMINATOR = 10


def norm_code(value):
    if value is None:
        return ""
    text = str(value).strip()
    if text.isdigit() and len(text) < 6:
        return text.zfill(6)
    return text


def direction_factor(raw):
    """+1 when the trip is 下り, -1 when it is 上り, else None."""
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    lowered = text.lower()
    if lowered in {"down", "up"}:
        return 1 if lowered == "down" else -1
    has_down = "下り" in text or text == "下" or text == "くだり"
    has_up = "上り" in text or text == "上" or text == "のぼり"
    if has_down == has_up:
        return None
    return 1 if has_down else -1


def load_group_map(stations_path, package_ids):
    """Map an N02 station code to the group code the package stores."""
    payload = json.loads(stations_path.read_text())
    mapping = {}
    conflicts = set()
    for feature in payload["features"]:
        props = feature.get("properties") or {}
        code = norm_code(props.get("n02_station_code"))
        group = norm_code(props.get("n02_group_code"))
        if not code or not group:
            continue
        previous = mapping.get(code)
        if previous is None:
            mapping[code] = group
        elif previous != group:
            conflicts.add(code)
    for code in conflicts:
        mapping.pop(code, None)
    for code in package_ids:
        mapping.setdefault(code, code)
    return mapping


def load_lines(package_path):
    package = json.loads(package_path.read_text())
    lines = []
    for line in package["lines"]:
        positions = {}
        for index, station in enumerate(line["stations"]):
            group = norm_code(station[0])
            if group in positions:
                positions[group] = None
            else:
                positions[group] = index
        lines.append({
            "id": line["id"],
            "operator": line.get("operator") or "",
            "positions": positions,
        })
    return lines


def group_index():
    """group code -> line ids that contain it exactly once."""
    lines = load_lines(PACKAGE)
    package_ids = set()
    owners = defaultdict(list)
    for line in lines:
        for group, index in line["positions"].items():
            package_ids.add(group)
            if index is not None:
                owners[group].append(line["id"])
    by_id = {line["id"]: line for line in lines}
    return lines, by_id, owners, package_ids


def resolve_group(source_code, station_id, group_map):
    code = norm_code(source_code)
    if not code and station_id and str(station_id).startswith("jp.n02."):
        code = norm_code(str(station_id).split(".")[-1])
    if not code:
        return None
    return group_map.get(code)


def load_directed_trips(group_map):
    """trip id -> (direction factor, [group code or None])."""
    uri = DATABASE.as_uri() + "?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    rows = connection.execute(
        """
        SELECT t.trip_id, t.direction, si.current_source_code, si.station_id
        FROM trips t
        JOIN stop_times st ON st.trip_id = t.trip_id
        JOIN station_identities si ON si.station_id = st.station_id
        ORDER BY t.trip_id, st.stop_sequence
        """
    )
    trips = {}
    order = []
    for trip_id, direction, source_code, station_id in rows:
        factor = direction_factor(direction)
        if factor is None:
            continue
        if trip_id not in trips:
            trips[trip_id] = (factor, [])
            order.append(trip_id)
        group = resolve_group(source_code, station_id, group_map)
        trips[trip_id][1].append(group)
    connection.close()
    return [(trip_id, trips[trip_id][0], trips[trip_id][1]) for trip_id in order]


def stops_on_line(groups, positions):
    count = 0
    for group in groups:
        if group and positions.get(group) is not None:
            count += 1
    return count


def collect_votes(by_id, owners, group_map):
    """line id -> votes for downSign +1, votes for downSign -1, trip ids.

    The trip's single up/down label is applied to the line that contains the
    most of its stops. Tied lines all receive the pairs that lie on them.
    """
    plus = defaultdict(int)
    minus = defaultdict(int)
    trips = defaultdict(set)
    line_ids = list(by_id)
    for trip_id, factor, groups in load_directed_trips(group_map):
        coverage = {
            line_id: stops_on_line(groups, by_id[line_id]["positions"])
            for line_id in line_ids
        }
        best = max(coverage.values(), default=0)
        if best < 2:
            continue
        primary = {line_id for line_id, count in coverage.items() if count == best}
        previous = None
        for group in groups:
            if previous and group and previous != group:
                shared = set(owners.get(previous, [])) & set(owners.get(group, []))
                for line_id in shared & primary:
                    start = by_id[line_id]["positions"].get(previous)
                    end = by_id[line_id]["positions"].get(group)
                    if start is None or end is None or start == end:
                        continue
                    sign = 1 if end > start else -1
                    vote = sign * factor
                    if vote > 0:
                        plus[line_id] += 1
                    else:
                        minus[line_id] += 1
                    trips[line_id].add(trip_id)
            previous = group
    return plus, minus, trips


def build():
    lines, by_id, owners, package_ids = group_index()
    group_map = load_group_map(STATIONS, package_ids)
    plus, minus, trips = collect_votes(by_id, owners, group_map)
    emitted = {}
    for line_id in sorted(by_id):
        trip_count = len(trips.get(line_id, ()))
        if trip_count < MIN_TRIPS:
            continue
        positive = plus[line_id]
        negative = minus[line_id]
        total = positive + negative
        if total == 0 or positive == negative:
            continue
        winning = max(positive, negative)
        if winning * MIN_AGREEMENT_DENOMINATOR < total * MIN_AGREEMENT_NUMERATOR:
            continue
        emitted[line_id] = {
            "downSign": 1 if positive > negative else -1,
            "votes": total,
            "agreement": round(winning / total, 4),
        }
    OUTPUT.write_text(json.dumps(emitted, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    report(lines, emitted)


def is_jr(operator):
    return any(name in operator for name in JR_OPERATORS)


def report(lines, emitted):
    by_operator = defaultdict(lambda: [0, 0])
    jr_cal = jr_total = other_cal = other_total = 0
    for line in lines:
        operator = line["operator"] or "(none)"
        counts = by_operator[operator]
        counts[1] += 1
        calibrated = line["id"] in emitted
        if calibrated:
            counts[0] += 1
        if is_jr(operator):
            jr_total += 1
            jr_cal += int(calibrated)
        else:
            other_total += 1
            other_cal += int(calibrated)
    print(f"calibrated {len(emitted)} / {len(lines)}")
    print(f"JR {jr_cal} / {jr_total}")
    print(f"other {other_cal} / {other_total}")
    for operator, (calibrated, total) in sorted(by_operator.items(), key=lambda item: (-item[1][0], item[0])):
        if calibrated:
            print(f"  {calibrated}/{total}\t{operator}")
    private = [line_id for line_id, row in emitted.items() if not is_jr(by_id_operator(lines, line_id))]
    print(f"private lines {len(private)}")
    for line_id in private[:12]:
        row = emitted[line_id]
        print(f"  {line_id} downSign={row['downSign']} votes={row['votes']} agreement={row['agreement']}")


def by_id_operator(lines, line_id):
    for line in lines:
        if line["id"] == line_id:
            return line["operator"]
    return ""


if __name__ == "__main__":
    build()
