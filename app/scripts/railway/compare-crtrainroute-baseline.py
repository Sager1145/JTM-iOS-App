#!/usr/bin/env python3
"""Replay bounded real-train cases through the pinned, unchanged CRTrainRoute engine.

This is an explicit comparative research tool, not a production data loader.
Input: {"cases": [{"id": "...", "from": "IZQ", "to": "IOQ",
                    "knownStops": ["IZQ", "QSK", "IOQ"]}]}.
No target distance is accepted. Each result retains the complete upstream response.
"""
import argparse
import collections
import contextlib
import hashlib
import importlib.util
import json
import pickle
import pickletools
import subprocess
import sys
import time
import types
from pathlib import Path

COMMIT = "d75307df9c812abf1259b86b75202ba7b0048679"
FILES = ("server.py", "build_graph.py", "data/rail_graph.pkl", "data/stations.json",
         "data/station_names.json", "data/station_lanes.json", "LICENSE")
# No object construction, global lookup, persistence, extensions or reductions.
PRIMITIVE_OPS = frozenset("PROTO FRAME STOP MARK POP POP_MARK DUP NONE NEWTRUE NEWFALSE "
    "INT BININT BININT1 BININT2 LONG LONG1 LONG4 FLOAT BINFLOAT STRING BINSTRING "
    "SHORT_BINSTRING UNICODE BINUNICODE SHORT_BINUNICODE BINUNICODE8 BINBYTES "
    "SHORT_BINBYTES BINBYTES8 EMPTY_LIST LIST APPEND APPENDS EMPTY_TUPLE TUPLE "
    "TUPLE1 TUPLE2 TUPLE3 EMPTY_DICT DICT SETITEM SETITEMS EMPTY_SET ADDITEMS "
    "FROZENSET PUT BINPUT LONG_BINPUT GET BINGET LONG_BINGET MEMOIZE".split())


class PrimitiveUnpickler(pickle.Unpickler):
    def find_class(self, module, name):
        raise pickle.UnpicklingError("All globals are forbidden")

    def persistent_load(self, pid):
        raise pickle.UnpicklingError("Persistent references are forbidden")


def primitive_load(stream):
    """Reject executable opcodes before any deserialization; never use pickle.load."""
    start = stream.tell()
    counts = collections.Counter()
    for op, _, _ in pickletools.genops(stream):
        if op.name not in PRIMITIVE_OPS:
            raise pickle.UnpicklingError("Forbidden opcode: " + op.name)
        counts[op.name] += 1
    if stream.read(1):
        raise pickle.UnpicklingError("Trailing data after pickle STOP")
    stream.seek(start)
    value = PrimitiveUnpickler(stream).load()
    primitive_load.opcode_counts = dict(counts)
    return value


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def acquire_manifest(root):
    if git(root, "rev-parse", "HEAD") != COMMIT:
        raise ValueError("Original source checkout must be exactly " + COMMIT)
    records = []
    for name in FILES:
        path = root / name
        expected = git(root, "rev-parse", COMMIT + ":" + name)
        actual = git(root, "hash-object", "--", str(path))
        if actual != expected:
            raise ValueError("Modified original input: " + name)
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        records.append({"path": name, "bytes": path.stat().st_size,
                        "gitBlob": actual, "sha256": digest.hexdigest()})
    if (root / "data/rail_graph.pkl").stat().st_size > 200 * 1024 * 1024:
        raise ValueError("Graph exceeds bounded comparative loader size")
    return {"repository": "https://github.com/Laide140/CRTrainRoute", "commit": COMMIT,
            "sourceRoot": str(root), "files": records,
            "graphMode": "original-committed-pickle-primitive-only",
            "stationMode": "offline-retained-stations-json-raw-values",
            "coordinateTreatment": "No datum conversion; original raw coordinates retained",
            "targetKm": None,
            "stationTransportDifference": "Original API fetches 12306 live. Replay uses the "
                "same commit's stations.json, mapping addr to address; no coordinate repairs.",
            "originalLiveEndpoint": "https://mobile.12306.cn/wxxcx/wechat/bigScreen/getStationAddress",
            "originalLiveRequest": {"method": "POST", "form": {"stationCode": "<telecode>"},
                "responseLongitudeKey": "longitute"},
            "limitations": ["Geometric shortest path is not evidence of actual train service",
                "Original nearest-main-component snapping and guessed island/ferry links remain",
                "Original nearby station inference and cache behavior remain",
                "Forced known-stop mode concatenates independent original API calls; it is not "
                "an upstream train-service or via-station API"]}


def load_original(root):
    spec = importlib.util.spec_from_file_location("crtrainroute_original", root / "server.py")
    original = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(original)
    # Substitute the data transport only; original RailGraph/RailService methods are untouched.
    original.pickle = types.SimpleNamespace(load=primitive_load)
    snapshot = json.loads((root / "data/stations.json").read_text())

    class FrozenStations(original.StationClient):
        def get(self, code):
            code = code.upper().strip()
            row = snapshot.get(code)
            if not row or row.get("lat") is None or row.get("lon") is None:
                return None, "retained-stations-json"
            return {"code": code, "name": row.get("name") or self.name_of(code) or code,
                    "lat": row["lat"], "lon": row["lon"], "city": row.get("city"),
                    "address": row.get("addr")}, "retained-stations-json"

    start = time.monotonic()
    service = original.RailService()
    service.stations = FrozenStations()
    graph = service.graph
    stats = {"loadAndIndexSeconds": round(time.monotonic() - start, 3),
             "coordinateNodes": len(graph.lats), "skeletonNodes": len(graph.adj),
             "directedSkeletonEdges": sum(map(len, graph.adj.values())),
             "stationNodes": len(graph.station_nodes), "graphStations": len(graph.stations),
             "ferryEdges": graph.ferry_edges, "primitiveOpcodes": primitive_load.opcode_counts}
    return service, stats


def case_stops(case):
    stops = case.get("knownStops", [])
    if not isinstance(stops, list) or not all(isinstance(s, str) and s for s in stops):
        raise ValueError("knownStops must be an ordered list of station codes or names")
    if not stops:
        return []
    if stops[0] != case["from"]:
        stops = [case["from"], *stops]
    if stops[-1] != case["to"]:
        stops = [*stops, case["to"]]
    return stops


def run_case(service, case, modes):
    def request(frm, to):
        try:
            return service.route(frm, to)
        except Exception as exc:
            # Match original Handler's API error response, preserving batch progress.
            return {"ok": False, "error": "内部错误: %s" % exc}

    row = {"id": case["id"], "input": case, "modes": {}}
    if "endpoint-only" in modes:
        row["modes"]["endpoint-only"] = {"legs": [request(case["from"], case["to"])]}
    if "forced-known-stops" in modes:
        stops = case_stops(case)
        legs = [request(a, b) for a, b in zip(stops, stops[1:])]
        row["modes"]["forced-known-stops"] = {"orderedStops": stops, "legs": legs,
            "status": "executed" if legs else "not-requested-no-known-stops"}
    for result in row["modes"].values():
        legs = result["legs"]
        result["allLegsOk"] = bool(legs) and all(leg.get("ok") for leg in legs)
        result["successfulLegDistanceM"] = sum(leg.get("distance", {}).get("meters", 0)
                                               for leg in legs if leg.get("ok"))
    return row


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-source", type=Path, required=True)
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--inspect-only", action="store_true", help="Verify inputs without loading graph")
    parser.add_argument("--load-only", action="store_true", help="Load/index once and record graph counts")
    parser.add_argument("--modes", nargs="+", choices=("endpoint-only", "forced-known-stops"),
                        default=["endpoint-only", "forced-known-stops"])
    args = parser.parse_args()
    manifest = acquire_manifest(args.original_source.resolve())
    if args.inspect_only:
        write_json(args.output, {"manifest": manifest})
        return
    with contextlib.redirect_stdout(sys.stderr):
        service, stats = load_original(args.original_source.resolve())
    output = {"manifest": manifest, "graph": stats, "cases": []}
    write_json(args.output, output)
    if args.load_only:
        return
    if args.input is None:
        parser.error("--input is required for route execution")
    cases = json.loads(args.input.read_text())["cases"]
    for case in cases:
        print("Original engine case: " + case["id"], file=sys.stderr, flush=True)
        output["cases"].append(run_case(service, case, args.modes))
        write_json(args.output, output)


if __name__ == "__main__":
    main()
