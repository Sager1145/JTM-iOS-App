"""Topology file `jtm-display-topology-v1` for the iOS display network.

Pure standard library, no dependency on the builder or any other project
module. `build-display-network.py` collects, per region, the final display
fragments and the package lines and hands them to `build_region_topology`; this
module returns the bytes of `{region}.topology.bin` and a report.

The byte layout is the contract in `docs/reference/rail-topology-format.md`,
whose code form is `ios/RailKit/Sources/RailCore/Topology/RailTopologyFormat.swift`.
The constants below repeat that file's numbers; the unit test compares them
with it, so a drift on either side fails a test.

What this module decides (everything else is the contract):

* Lines are the package lines that have display data, in manifest blob order.
  Nodes are the package stations in station order. Edges are the package
  intervals; an edge's length is the surveyed length stored with the interval.
* Positions are never re-derived by nearest-point search. A continuous line's
  final fragment is located inside the chain the builder first made (the final
  parts are a contiguous slice of it when history split the chain), and the
  station anchors the builder recorded for that chain are carried onto the
  slice; an interval is the vertex span between its two stations' anchors, or,
  where a branch lead-in splits it over chains that meet at a shared
  coordinate, the shortest route over those chains. A non-continuous line's
  final parts are matched, in order, to the pieces the builder cut from each
  interval. Every interval that is routed, left without geometry, or drawn at a
  length far from its surveyed length is in the report.
* Both metre rulers are the device ruler (`joinedChainCoordinates`). The
  overview ruler of a position is its projection onto the overview part, which
  is a subsequence of the full part.
* Links exist only for a reviewed physical junction row or a dated through
  service row, with the same acceptance rules as `TripConnectivity`. A row that
  cannot be placed on nodes is reported, never guessed.
"""
from __future__ import annotations

import bisect
import datetime as dt
import hashlib
import math
import re
import struct
from dataclasses import dataclass, field

FORMAT_NAME = "jtm-display-topology-v2"
MAGIC = b"JTMT"
FORMAT_VERSION = 2
HEADER_SIZE = 160
NO_STRING = 0xFFFFFFFF
UNSET = 0xFFFFFFFF
NO_DATE = 0
MAX_LINES_PER_REGION = 65535
MAX_NODES_PER_LINE = 65535
FILE_SUFFIX = ".topology.bin"

TABLES = ("lines", "nodes", "edges", "runs", "links", "identities", "stops", "stopNodes", "strings")
RECORD_SIZE = {
    "lines": 72, "nodes": 28, "edges": 28, "runs": 20, "links": 24,
    "identities": 20, "stops": 16, "stopNodes": 4, "strings": 1,
}

LINE_LOOP, LINE_HIGH_SPEED, LINE_PAIRED, LINE_RETIRED, LINE_NON_CONTINUOUS = 1, 2, 4, 8, 16
NODE_JUNCTION_POINT, NODE_NO_CHAIN_SLOT = 1, 2
EDGE_FORWARD, EDGE_REVERSE, EDGE_WITHHELD, EDGE_HAS_RUNS = 1, 2, 4, 8
LINK_PHYSICAL_JUNCTION, LINK_THROUGH_SERVICE = 1, 2
STOP_PLATFORM, STOP_REGISTRY, STOP_GROUP = 1, 2, 3



class TopologyError(RuntimeError):
    """The inputs cannot be turned into a topology file; the build stops."""


# --------------------------------------------------------------------------
# Dates and rulers
# --------------------------------------------------------------------------

_EPOCH = dt.date(1799, 12, 31)
_ISO = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def day_number(iso: str) -> int:
    """Day 1 is 1800-01-01. A malformed date or one before 1800 is an error."""
    if not isinstance(iso, str) or not _ISO.match(iso):
        raise TopologyError(f"not an ISO date: {iso!r}")
    try:
        date = dt.date(int(iso[0:4]), int(iso[5:7]), int(iso[8:10]))
    except ValueError as error:
        raise TopologyError(f"not a calendar date: {iso!r}") from error
    days = (date - _EPOCH).days
    if days < 1:
        raise TopologyError(f"date before 1800-01-01: {iso!r}")
    return days


def optional_day(iso) -> int:
    """A source bound of none is 0; a source `valid_to` is copied, never decremented."""
    return NO_DATE if not iso else day_number(iso)


def to_cm(metres: float) -> int:
    return int(math.floor(metres * 100.0 + 0.5))


def ruler(points: list) -> list[float]:
    """The device ruler: `joinedChainCoordinates` in MapLineGeometry.swift."""
    measures = [0.0] * len(points)
    for index in range(1, len(points)):
        a, b = points[index - 1], points[index]
        lat = ((a[1] + b[1]) / 2) * math.pi / 180
        measures[index] = measures[index - 1] + math.hypot(
            (b[0] - a[0]) * 111_320 * math.cos(lat), (b[1] - a[1]) * 111_320)
    return measures


def join_parts(parts: list) -> tuple[list, list[tuple[int, int]]]:
    """Joined chain coordinates (each part after the first drops its first
    vertex) and the inclusive vertex range of each part in them."""
    points: list = []
    bounds: list[tuple[int, int]] = []
    for index, part in enumerate(parts):
        if index == 0:
            start = 0
            points.extend(part)
        else:
            start = len(points) - 1
            points.extend(part[1:])
        bounds.append((start, len(points) - 1 if points else 0))
    return points, bounds


# --------------------------------------------------------------------------
# Records and the encoder
# --------------------------------------------------------------------------

@dataclass
class Run:
    chain: int
    full_from: int
    full_to: int
    overview_from: int = UNSET
    overview_to: int = UNSET


@dataclass
class Node:
    code: str | None
    chain: int
    full: int
    overview: int
    lon: float
    lat: float
    flags: int = 0


@dataclass
class Edge:
    length_cm: int
    cumulative_cm: int
    valid_from: int
    valid_to: int
    flags: int
    runs: list[Run] = field(default_factory=list)
    # Steps of the source polyline the edge spans: the route solver's graph has one edge
    # per step, and charges its per-edge institution penalty once for each.
    fine_edges: int = 1


@dataclass
class Identity:
    name: str
    family: str
    valid_from: int
    valid_to: int


@dataclass
class LineRecord:
    id: str
    family: str
    name: str
    aliases: str
    institution: int
    category_mask: int
    flags: int
    chain_count: int
    valid_from: int
    valid_to: int
    nodes: list[Node]
    edges: list[Edge]
    identities: list[Identity] = field(default_factory=list)
    operator: str | None = None     # operator name as the production solver reads it (N02_004 for jp)
    solver_name: str | None = None  # line name as the production solver reads it (N02_003 for jp)


@dataclass
class Link:
    node_a: int
    node_b: int
    kind: int
    directed: bool
    valid_from: int
    valid_to: int
    registry_id: str


@dataclass
class Stop:
    key: str
    kind: int
    nodes: list[int]


class _Strings:
    """Offset 0 is the empty string; the rest are interned in first-use order."""

    def __init__(self) -> None:
        self.buffer = bytearray(b"\x00\x00")
        self.offsets: dict[str, int] = {"": 0}

    def ref(self, value: str | None) -> int:
        if value is None:
            return NO_STRING
        known = self.offsets.get(value)
        if known is not None:
            return known
        encoded = value.encode("utf-8")
        if len(encoded) > 0xFFFF:
            raise TopologyError(f"string longer than 65535 bytes: {value[:40]!r}")
        offset = len(self.buffer)
        self.buffer += struct.pack("<H", len(encoded)) + encoded
        self.offsets[value] = offset
        return offset


def _frame_text(value: str | None) -> bytes:
    if value is None:
        return b"\x00"
    encoded = value.encode("utf-8")
    return b"\x01" + struct.pack("<I", len(encoded)) + encoded


def line_content_hashes(lines: list[LineRecord], links: list[Link], stops: list[Stop]) -> list[bytes]:
    """Per line, 8 bytes: the first half of a SHA-256 over everything a trip drawn
    over this line depends on. A change to any of it gives a different hash, and
    nothing else does:
      - the line row (id, family, name, aliases, operator, institution, category,
        flags, chain count, dates), its identities;
      - every node (station code, both rulers, coordinates, chain, flags), every
        edge (length, cumulative length, dates, flags) and run;
      - every link that touches one of its nodes, as (own node ordinal, other line
        id, other node ordinal, kind, directed, dates, registry row), sorted, so a
        junction or through service added, removed or redated changes both lines;
      - every stop key (and kind) that resolves to one of its nodes, per node.
    Global node and line indices are not hashed, so adding a line elsewhere in the
    file changes nobody else's hash. The same input gives the same bytes."""
    node_base, total = [], 0
    for line in lines:
        node_base.append(total)
        total += len(line.nodes)
    owner: list[tuple[int, int]] = []       # global node -> (line index, ordinal)
    for line_index, line in enumerate(lines):
        owner.extend((line_index, ordinal) for ordinal in range(len(line.nodes)))
    touching: list[list[tuple]] = [[] for _ in lines]
    for link in links:
        (la, oa), (lb, ob) = owner[link.node_a], owner[link.node_b]
        row = (link.kind, 1 if link.directed else 0, link.valid_from, link.valid_to, link.registry_id)
        # Only a directed link has a side; an undirected one reads the same from both ends.
        touching[la].append((oa, lines[lb].id, ob, "A" if link.directed else "U") + row)
        touching[lb].append((ob, lines[la].id, oa, "B" if link.directed else "U") + row)
    stops_at: list[list[tuple]] = [[] for _ in range(total)]
    for stop in stops:
        for node in stop.nodes:
            stops_at[node].append((stop.key.encode("utf-8"), stop.kind))
    hashes = []
    for line_index, line in enumerate(lines):
        h = hashlib.sha256()
        h.update(b"jtm-topology-line-hash-v1")
        for text in (line.id, line.family, line.name, line.aliases, line.operator, line.solver_name):
            h.update(_frame_text(text))
        h.update(struct.pack("<HHHHII", line.institution, line.category_mask, line.flags,
                             line.chain_count, line.valid_from, line.valid_to))
        h.update(struct.pack("<II", len(line.nodes), len(line.edges)))
        for node in line.nodes:
            h.update(_frame_text(node.code))
            h.update(struct.pack("<IIffHH", node.full, node.overview, node.lon, node.lat,
                                 node.chain, node.flags))
        for ordinal, node in enumerate(line.nodes):
            marks = sorted(stops_at[node_base[line_index] + ordinal])
            h.update(struct.pack("<I", len(marks)))
            for key, kind in marks:
                h.update(struct.pack("<I", len(key)) + key + bytes([kind]))
        for edge in line.edges:
            h.update(struct.pack("<IIIIHHI", edge.length_cm, edge.cumulative_cm, edge.valid_from,
                                 edge.valid_to, edge.flags, len(edge.runs), edge.fine_edges))
            for run in edge.runs:
                h.update(struct.pack("<HIIII", run.chain, run.full_from, run.full_to,
                                     run.overview_from, run.overview_to))
        h.update(struct.pack("<I", len(line.identities)))
        for identity in line.identities:
            h.update(_frame_text(identity.name) + _frame_text(identity.family))
            h.update(struct.pack("<II", identity.valid_from, identity.valid_to))
        rows = sorted(touching[line_index])
        h.update(struct.pack("<I", len(rows)))
        for ordinal, other_id, other_ordinal, side, kind, directed, v_from, v_to, registry_id in rows:
            h.update(struct.pack("<I", ordinal) + _frame_text(other_id))
            h.update(struct.pack("<IcBBII", other_ordinal, side.encode(), kind, directed, v_from, v_to))
            h.update(_frame_text(registry_id))
        hashes.append(h.digest()[:8])
    return hashes


def encode_topology(region: str, package_sha256: bytes, display_sha256: bytes,
                    lines: list[LineRecord], links: list[Link], stops: list[Stop]) -> bytes:
    if len(package_sha256) != 32 or len(display_sha256) != 32:
        raise TopologyError("digests must be 32 bytes")
    if len(lines) > MAX_LINES_PER_REGION:
        raise TopologyError("too many lines")
    region_bytes = region.encode("ascii")
    if not 0 < len(region_bytes) <= 4:
        raise TopologyError(f"region code {region!r} does not fit 4 bytes")
    strings = _Strings()
    # Interning follows table order so the same input is the same bytes.
    line_rows, node_rows, edge_rows, run_rows = bytearray(), bytearray(), bytearray(), bytearray()
    identity_rows = bytearray()
    node_count = edge_count = run_count = identity_count = 0
    line_index_by_id: dict[str, int] = {}
    pending_nodes: list[tuple[int, LineRecord]] = []
    line_fields = []
    for line_index, line in enumerate(lines):
        if line.id in line_index_by_id:
            raise TopologyError(f"duplicate line id {line.id}")
        line_index_by_id[line.id] = line_index
        if len(line.nodes) > MAX_NODES_PER_LINE:
            raise TopologyError(f"{line.id}: more than {MAX_NODES_PER_LINE} nodes")
        line_fields.append((node_count, edge_count, identity_count))
        pending_nodes.append((line_index, line))
        node_count += len(line.nodes)
        edge_count += len(line.edges)
        identity_count += len(line.identities)
    for link in links:
        if not link.registry_id:
            raise TopologyError("a link needs the registry row it came from")
        if not (0 <= link.node_a < node_count and 0 <= link.node_b < node_count):
            raise TopologyError(f"link {link.registry_id} names a node outside the file")
    content_hashes = line_content_hashes(lines, links, stops)
    for line_index, line in pending_nodes:
        first_node, first_edge, first_identity = line_fields[line_index]
        line_rows += struct.pack(
            "<IIIIHHHHIIIIIIIHHII8s",
            strings.ref(line.id), strings.ref(line.family), strings.ref(line.name),
            strings.ref(line.aliases), line.institution, line.category_mask, line.flags,
            line.chain_count, line.valid_from, line.valid_to, first_node, len(line.nodes),
            first_edge, len(line.edges), first_identity, len(line.identities), 0,
            strings.ref(line.operator), strings.ref(line.solver_name), content_hashes[line_index])
    for line_index, line in pending_nodes:
        for node in line.nodes:
            node_rows += struct.pack(
                "<IIIffHHHH", strings.ref(node.code), node.full, node.overview,
                node.lon, node.lat, line_index, node.chain, node.flags, 0)
        for edge in line.edges:
            if edge.length_cm <= 0:
                raise TopologyError(f"{line.id}: edge length must be above zero")
            if edge.fine_edges < 1:
                raise TopologyError(f"{line.id}: an edge spans at least one source step")
            edge_rows += struct.pack(
                "<IIIIHHII", edge.length_cm, edge.cumulative_cm, edge.valid_from, edge.valid_to,
                edge.flags, len(edge.runs), run_count, edge.fine_edges)
            for run in edge.runs:
                run_rows += struct.pack(
                    "<HHIIII", run.chain, 0, run.full_from, run.full_to,
                    run.overview_from, run.overview_to)
            run_count += len(edge.runs)
    link_rows = bytearray()
    for link in links:
        if not link.registry_id:
            raise TopologyError("a link needs the registry row it came from")
        link_rows += struct.pack(
            "<IIBBHIII", link.node_a, link.node_b, link.kind, 1 if link.directed else 0, 0,
            link.valid_from, link.valid_to, strings.ref(link.registry_id))
    for line in lines:
        for identity in line.identities:
            identity_rows += struct.pack(
                "<IIIII", line_index_by_id[line.id], strings.ref(identity.name),
                strings.ref(identity.family), identity.valid_from, identity.valid_to)
    stop_rows, stop_node_rows = bytearray(), bytearray()
    stop_node_count = 0
    for stop in stops:
        key_bytes = stop.key.encode("utf-8")
        stop_rows += struct.pack(
            "<IHBBII", strings.ref(stop.key), len(key_bytes), stop.kind, 0,
            stop_node_count, len(stop.nodes))
        stop_node_rows += b"".join(struct.pack("<I", index) for index in stop.nodes)
        stop_node_count += len(stop.nodes)

    string_bytes = bytes(strings.buffer)
    tables = [
        (bytes(line_rows), len(lines)), (bytes(node_rows), node_count),
        (bytes(edge_rows), edge_count), (bytes(run_rows), run_count),
        (bytes(link_rows), len(links)), (bytes(identity_rows), identity_count),
        (bytes(stop_rows), len(stops)), (bytes(stop_node_rows), stop_node_count),
        (string_bytes + b"\x00" * ((4 - len(string_bytes) % 4) % 4), len(string_bytes)),
    ]
    directory = bytearray()
    cursor = HEADER_SIZE
    for payload, count in tables:
        directory += struct.pack("<II", cursor, count)
        cursor += len(payload)
    if cursor > 0xFFFFFFFF:
        raise TopologyError("file longer than 4 GiB")
    header = bytearray()
    header += MAGIC + struct.pack("<HH", FORMAT_VERSION, HEADER_SIZE)
    header += region_bytes.ljust(4, b"\x00") + struct.pack("<I", 0)
    header += package_sha256 + display_sha256
    header += struct.pack("<II", cursor, 0)
    header += directory
    if len(header) != HEADER_SIZE:
        raise TopologyError(f"header is {len(header)} bytes")
    return bytes(header) + b"".join(payload for payload, _ in tables)


def read_topology(data: bytes) -> dict:
    """A plain decode used by the tests and by the build's own self-check."""
    if len(data) < HEADER_SIZE or data[:4] != MAGIC:
        raise TopologyError("bad magic")
    version, header_size = struct.unpack_from("<HH", data, 4)
    if version != FORMAT_VERSION or header_size != HEADER_SIZE:
        raise TopologyError("unsupported version")
    region = data[8:12].rstrip(b"\x00").decode("ascii")
    (length,) = struct.unpack_from("<I", data, 80)
    if length != len(data):
        raise TopologyError("length mismatch")
    directory = {}
    for number, name in enumerate(TABLES):
        offset, count = struct.unpack_from("<II", data, 88 + 8 * number)
        size = count * RECORD_SIZE[name]
        if offset % 4 or offset < HEADER_SIZE or offset + size > len(data):
            raise TopologyError(f"bad table {name}")
        directory[name] = (offset, count)
    string_offset = directory["strings"][0]

    def text(reference: int) -> str | None:
        if reference == NO_STRING:
            return None
        (size,) = struct.unpack_from("<H", data, string_offset + reference)
        start = string_offset + reference + 2
        return data[start:start + size].decode("utf-8")

    def rows(name: str, layout: str):
        offset, count = directory[name]
        step = RECORD_SIZE[name]
        return [struct.unpack_from(layout, data, offset + step * index) for index in range(count)]

    raw_runs = rows("runs", "<HHIIII")
    raw_edges = rows("edges", "<IIIIHHII")
    raw_nodes = rows("nodes", "<IIIffHHHH")
    lines = []
    for row in rows("lines", "<IIIIHHHHIIIIIIIHHII8s"):
        (line_id, family, name, aliases, institution, category, flags, chain_count,
         valid_from, valid_to, first_node, node_count, first_edge, edge_count,
         first_identity, identity_count, _, operator, solver_name, content_hash) = row
        nodes = [{
            "code": text(code), "full": full, "overview": overview, "lon": lon, "lat": lat,
            "chain": chain, "flags": node_flags,
        } for code, full, overview, lon, lat, _, chain, node_flags, _ in
            raw_nodes[first_node:first_node + node_count]]
        edges = []
        for length_cm, cumulative, e_from, e_to, e_flags, run_count, first_run, fine_edges in \
                raw_edges[first_edge:first_edge + edge_count]:
            edges.append({
                "lengthCm": length_cm, "cumulativeCm": cumulative, "validFrom": e_from,
                "validTo": e_to, "flags": e_flags, "fineEdges": fine_edges,
                "runs": [{"chain": chain, "fullFrom": ff, "fullTo": ft, "overviewFrom": of,
                          "overviewTo": ot} for chain, _, ff, ft, of, ot in
                         raw_runs[first_run:first_run + run_count]],
            })
        lines.append({
            "id": text(line_id), "family": text(family), "name": text(name),
            "aliases": text(aliases), "institution": institution, "categoryMask": category,
            "flags": flags, "chainCount": chain_count, "validFrom": valid_from,
            "validTo": valid_to, "firstNode": first_node, "firstEdge": first_edge,
            "identityCount": identity_count, "firstIdentity": first_identity,
            "operator": text(operator), "solverName": text(solver_name), "contentHash": content_hash,
            "nodes": nodes, "edges": edges,
        })
    stop_nodes = [value for (value,) in rows("stopNodes", "<I")]
    return {
        "region": region, "packageSHA256": data[16:48], "displaySHA256": data[48:80],
        "lines": lines,
        "links": [{
            "nodeA": a, "nodeB": b, "kind": kind, "directed": bool(flags & 1),
            "validFrom": v_from, "validTo": v_to, "registryID": text(registry),
        } for a, b, kind, flags, _, v_from, v_to, registry in rows("links", "<IIBBHIII")],
        "identities": [{
            "line": line, "name": text(name), "family": text(family),
            "validFrom": v_from, "validTo": v_to,
        } for line, name, family, v_from, v_to in rows("identities", "<IIIII")],
        "stops": [{
            "key": text(key), "keyLength": key_length, "kind": kind,
            "nodes": stop_nodes[first:first + count],
        } for key, key_length, kind, _, first, count in rows("stops", "<IHBBII")],
    }


# --------------------------------------------------------------------------
# Direction rules (port of RailwayDirection.allowedDirections)
# --------------------------------------------------------------------------

def allowed_directions(line: dict, interval_index: int) -> list[int]:
    permitted = line.get("permittedTraversal")
    traversal = [1] if permitted == "forward" else [-1] if permitted == "reverse" else [-1, 1]
    order = line.get("stationOrderDirection")
    if order not in ("up", "down"):
        return traversal
    physical = line.get("alignmentDirection")
    if physical not in ("up", "down"):
        physical = None
        names = [row[1] for row in line.get("stations") or []]
        for pair in line.get("alignmentPairs") or []:
            if pair.get("direction") not in ("up", "down") or pair.get("with") == line["id"]:
                continue
            if pair.get("from") not in names or pair.get("to") not in names:
                continue
            start, end = names.index(pair["from"]), names.index(pair["to"])
            if min(start, end) <= interval_index < max(start, end):
                physical = pair["direction"]
                break
    if physical is None:
        return traversal
    sign = 1 if physical == order else -1
    return [value for value in traversal if value == sign]


# --------------------------------------------------------------------------
# Geometry derivation
# --------------------------------------------------------------------------

@dataclass
class LineSource:
    """Everything the builder knows about one line with display data."""
    key: str
    line: dict                      # the package line
    continuous: bool
    fragments: list[dict]           # final full fragments in blob order
    overview: list[dict] | None     # overview fragments, parallel to `fragments`, or None
    chains: list[dict]              # continuous: original chains (polyline, anchorIndexByStation, firstInterval)
    pieces: list[tuple]             # non-continuous: (lane, owner interval, rounded coordinates) in creation order
    withheld: set                   # interval indices the alignment gate withheld
    slots: dict                     # station code -> [chain, vertex] of the final station record
    stamps: dict                    # (draw id, part index) -> (validFrom ISO, validTo ISO)
    draw_ids: list[str]             # draw id of each final fragment
    origins: list[tuple[int, int]]  # continuous: per final fragment (original chain index, first vertex in it)


def _tuples(points: list) -> list[tuple]:
    return [(point[0], point[1]) for point in points]


def _rounded_tuples(points: list) -> list[tuple]:
    return [(round(point[0], 7), round(point[1], 7)) for point in points]


def _align_retained(full: list[tuple], simplified: list[tuple]) -> list[int] | None:
    """Indices of `full` that `simplified` kept, in order. The simplified part is
    a subsequence of the full one whose first and last vertices are the full
    part's own."""
    m, o = len(full), len(simplified)
    if o == m:
        return list(range(m)) if full == simplified else None
    if o < 2 or o > m or full[0] != simplified[0] or full[-1] != simplified[-1]:
        return None
    retained = [0]
    cursor = 1
    for index in range(1, o - 1):
        limit = m - 1 - (o - 1 - index)          # leave room for the vertices still to place
        while cursor <= limit and full[cursor] != simplified[index]:
            cursor += 1
        if cursor > limit:
            return None
        retained.append(cursor)
        cursor += 1
    retained.append(m - 1)
    return retained


class _OverviewMap:
    """Position on a fragment's overview ruler of a vertex of its full ruler."""

    def __init__(self, full_parts: list, overview_parts: list) -> None:
        self.ok = len(full_parts) == len(overview_parts) and bool(full_parts)
        self.failures = 0
        if not self.ok:
            if overview_parts:      # an overview exists but does not match: reported, not silently unset
                self.failures += 1
            return
        self.full_points, self.full_bounds = join_parts([_tuples(p) for p in full_parts])
        self.points, self.bounds = join_parts([_tuples(p) for p in overview_parts])
        self.measures = ruler(self.points)
        self.retained: list[list[int] | None] = []
        self.retained_index: list[dict[int, int] | None] = []
        for full, simplified in zip(full_parts, overview_parts):
            aligned = _align_retained(_tuples(full), _tuples(simplified))
            if aligned is None:
                self.failures += 1
            self.retained.append(aligned)
            self.retained_index.append(
                None if aligned is None else {value: slot for slot, value in enumerate(aligned)})

    def position(self, vertex: int) -> int:
        """Centimetres on the overview ruler, or UNSET."""
        if not self.ok:
            return UNSET
        for part, (start, end) in enumerate(self.full_bounds):
            if start <= vertex <= end:
                break
        else:
            return UNSET
        retained = self.retained[part]
        if retained is None:
            return UNSET
        offset = vertex - start
        overview_start = self.bounds[part][0]
        known = self.retained_index[part].get(offset)
        if known is not None:
            return to_cm(self.measures[overview_start + known])
        after = bisect.bisect_right(retained, offset)
        before = after - 1
        a = self.points[overview_start + before]
        b = self.points[overview_start + after]
        p = self.full_points[vertex]
        lat = ((a[1] + b[1]) / 2) * math.pi / 180
        scale = math.cos(lat)
        dx, dy = (b[0] - a[0]) * scale, b[1] - a[1]
        denominator = dx * dx + dy * dy
        t = 0.0 if denominator == 0 else max(0.0, min(1.0, (
            ((p[0] - a[0]) * scale) * dx + (p[1] - a[1]) * dy) / denominator))
        first = self.measures[overview_start + before]
        second = self.measures[overview_start + after]
        return to_cm(first + t * (second - first))


@dataclass
class _Piece:
    """One stretch of an interval on one final fragment's ruler."""
    order: tuple
    fragment: int
    vertex_from: int
    vertex_to: int


def _stamp_window(stamps: dict, draw_id: str, part_index: int) -> tuple | None:
    return stamps.get((draw_id, part_index))


def _chain_spans(source: LineSource, originals: list, report: dict) -> list[list[tuple]]:
    """Per original chain, the intervals it carries as `(interval, from vertex,
    to vertex, hop)` in the chain's own vertex numbers; `hop` numbers the chains
    one interval is laid across, in travel order.

    1. An interval whose two stations are both anchored on one chain is the
       vertex span between the anchors.
    2. An interval no chain carries whole (a branch lead-in splits the track
       over two chains that meet at a shared coordinate) is the shortest route
       over the chains from one station's anchors to the other's, changing
       chain only where two chains hold the same coordinate and one of the two
       is at its end.
    An interval neither places is left without runs and reported.
    Routed intervals are reported with their display and surveyed lengths."""
    line = source.line
    station_count = len(line["stations"])
    is_loop = bool(line.get("isLoop"))
    interval_count = station_count if is_loop else station_count - 1
    result: list[list[tuple]] = []

    def anchor(chain: dict, station: int):
        anchors = chain["anchorIndexByStation"]
        value = anchors.get(station)
        if value is None and is_loop and station == station_count - 1:
            value = anchors.get(station_count)
        return value

    for chain, polyline in zip(source.chains, originals):
        anchors = chain["anchorIndexByStation"]
        last = len(polyline) - 1
        closed = last > 0 and polyline[0] == polyline[last]
        # A closed polyline has one vertex for its seam, anchored as vertex 0. The
        # chain may run the way the stations are listed or against it; the
        # stations away from the seam say which, and the seam station is then
        # the start or the end of the polyline accordingly.
        against = False
        if closed:
            inner = [value for _, value in sorted(anchors.items()) if 0 < value < last]
            against = sum(b < a for a, b in zip(inner, inner[1:])) > sum(b > a for a, b in zip(inner, inner[1:]))
        spans = []
        for interval in range(interval_count):
            start = anchors.get(interval)
            end = anchors.get(interval + 1)
            if end is None and is_loop:
                end = anchors.get((interval + 1) % station_count)
            if start is None or end is None:
                continue
            if closed and not against and end == 0 and start > 0:
                end = last
            if closed and against and start == 0 and end not in (0, last):
                start = last
            if start != end:
                spans.append((interval, start, end, 0))
        result.append(spans)
    missing = [i for i in range(interval_count)
               if not any(span[0] == i for spans in result for span in spans)]
    if not missing:
        return result

    # 2. Routes over the chains.
    rulers = [ruler(polyline) for polyline in originals]
    by_coordinate: dict[tuple, list[tuple[int, int]]] = {}
    for oi, polyline in enumerate(originals):
        for vertex, point in enumerate(polyline):
            by_coordinate.setdefault(point, []).append((oi, vertex))
    joins: dict[tuple[int, int], list[tuple[int, int]]] = {}
    for holders in by_coordinate.values():
        if len(holders) < 2:
            continue
        for oi, vertex in holders:
            for oj, other in holders:
                if oj != oi and (vertex in (0, len(originals[oi]) - 1) or other in (0, len(originals[oj]) - 1)):
                    joins.setdefault((oi, vertex), []).append((oj, other))
    for interval in missing:
        starts = [(oi, v) for oi, chain in enumerate(source.chains)
                  if (v := anchor(chain, interval)) is not None]
        goals = {(oi, v) for oi, chain in enumerate(source.chains)
                 if (v := anchor(chain, (interval + 1) % station_count)) is not None}
        path = _shortest_route(starts, goals, rulers, joins) if starts and goals else None
        if path is None:
            continue                    # reported by `_edge` as an edge without geometry
        hop = 0
        display = 0.0
        for (oi, a), (oj, b) in zip(path, path[1:]):
            if oi == oj and a != b:
                result[oi].append((interval, a, b, hop))
                hop += 1
                display += abs(rulers[oi][b] - rulers[oi][a])
        report["routedEdges"].append({
            "line": source.key, "interval": interval, "hops": hop,
            "displayMetres": round(display, 1),
            "surveyedMetres": round(float(line["segments"][interval][0]) * 1000.0, 1)})

    return result


def _shortest_route(starts: list, goals: set, rulers: list, joins: dict):
    """Dijkstra over (chain, vertex) states. Moves go along one chain to a goal
    or to a vertex where the chain can be left; a join costs nothing."""
    import heapq
    interesting: dict[int, set[int]] = {}
    for (oi, vertex) in joins:
        interesting.setdefault(oi, set()).add(vertex)
    for oi, vertex in goals:
        interesting.setdefault(oi, set()).add(vertex)
    best: dict[tuple, float] = {}
    previous: dict[tuple, tuple | None] = {}
    queue: list[tuple] = []
    for node in sorted(starts):
        best[node] = 0.0
        previous[node] = None
        heapq.heappush(queue, (0.0, node))
    while queue:
        cost, node = heapq.heappop(queue)
        if cost > best.get(node, math.inf):
            continue
        if node in goals:
            path = [node]
            while previous[path[-1]] is not None:
                path.append(previous[path[-1]])
            return path[::-1]
        oi, vertex = node
        moves = [((oi, other), abs(rulers[oi][other] - rulers[oi][vertex]))
                 for other in sorted(interesting.get(oi, ())) if other != vertex]
        moves += [(target, 0.0) for target in sorted(joins.get(node, ()))]
        for target, step in moves:
            if cost + step < best.get(target, math.inf):
                best[target] = cost + step
                previous[target] = node
                heapq.heappush(queue, (cost + step, target))
    return None


def _derive_continuous(source: LineSource, report: dict):
    line = source.line
    station_count = len(line["stations"])
    is_loop = bool(line.get("isLoop"))
    fragments = source.fragments
    originals = [_rounded_tuples(chain["polyline"]) for chain in source.chains]
    original_edges = _chain_spans(source, originals, report)

    if len(source.origins) != len(fragments):
        raise TopologyError(f"{source.key}: {len(source.origins)} fragment origins for {len(fragments)} fragments")
    placed = []               # per final fragment: (original index, offset, points, measures, anchors)
    for number, fragment in enumerate(fragments):
        points, _ = join_parts([_rounded_tuples(part) for part in fragment["parts"]])
        oi, k = source.origins[number]
        # The builder recorded where this fragment was cut from; the coordinates
        # are only compared to prove that record.
        if not 0 <= oi < len(originals) or originals[oi][k:k + len(points)] != points:
            raise TopologyError(
                f"{source.key}: fragment {source.draw_ids[number]} is not the slice of chain {oi} "
                f"at vertex {k} that the builder recorded")
        anchors = {i: v - k for i, v in source.chains[oi]["anchorIndexByStation"].items()
                   if k <= v <= k + len(points) - 1}
        placed.append((oi, k, points, ruler(points), anchors))

    overviews = []
    for number, fragment in enumerate(fragments):
        overview = source.overview[number] if source.overview else None
        mapper = _OverviewMap(fragment["parts"], overview["parts"]) if overview else None
        if mapper is not None:
            report["overviewAlignFailures"] += mapper.failures
        overviews.append(mapper)

    def position(number: int, vertex: int) -> tuple[int, int]:
        mapper = overviews[number]
        return (to_cm(placed[number][3][vertex]), mapper.position(vertex) if mapper else UNSET)

    # Nodes: the first final chain holding the station's anchor, as the slot rule does.
    nodes: list[Node] = []
    node_vertex: list[tuple[int, int] | None] = []
    for j, row in enumerate(line["stations"]):
        found = None
        for number, (_, _, _, _, anchors) in enumerate(placed):
            vertex = anchors.get(j)
            if vertex is None and j == station_count - 1 and is_loop:
                vertex = anchors.get(station_count)
            if vertex is not None:
                found = (number, vertex)
                break
        node_vertex.append(found)
        if found is None:
            nodes.append(Node(row[0], 0, UNSET, UNSET, row[2], row[3], NODE_NO_CHAIN_SLOT))
            report["unanchoredStations"].append(f"{source.key}:{row[0]}")
            continue
        number, vertex = found
        full, overview = position(number, vertex)
        chain = int(fragments[number].get("chain") or 0)
        nodes.append(Node(row[0], chain, full, overview, row[2], row[3], 0))
        slot = source.slots.get(row[0])
        if slot is not None and (int(slot[0]), int(slot[1])) != (chain, vertex):
            report["slotMismatches"].append(f"{source.key}:{row[0]} slot {slot} node {[chain, vertex]}")

    # Edges: pieces of each interval on the final fragments.
    pieces: dict[int, list[_Piece]] = {}
    owner_chain: dict[tuple[int, int], int] = {}
    for number, (oi, k, points, _, _) in enumerate(placed):
        high = k + len(points) - 1
        for interval, a, b, hop in original_edges[oi]:
            lo, hi = min(a, b), max(a, b)
            lo2, hi2 = max(lo, k), min(hi, high)
            if hi2 <= lo2:
                continue
            forward = a < b
            start, end = (lo2, hi2) if forward else (hi2, lo2)
            if owner_chain.setdefault((interval, hop), oi) != oi:
                report["intervalsOnSeveralChains"] += 1
                continue
            pieces.setdefault(interval, []).append(
                _Piece((hop, start if forward else -start), number, start - k, end - k))
    edge_count = station_count if is_loop else station_count - 1
    edges: list[Edge] = []
    cumulative = 0
    for interval in range(edge_count):
        km = float(line["segments"][interval][0])
        length_cm = to_cm(km * 1000.0)
        runs = []
        stamp_windows = []
        for piece in sorted(pieces.get(interval, []), key=lambda p: p.order):
            number = piece.fragment
            full_from, ov_from = position(number, piece.vertex_from)
            full_to, ov_to = position(number, piece.vertex_to)
            fragment = fragments[number]
            runs.append(Run(int(fragment.get("chain") or 0), full_from, full_to, ov_from, ov_to))
            stamp_windows.append(_stamp_window(source.stamps, source.draw_ids[number], 0))
        edges.append(_edge(source, interval, length_cm, cumulative, runs, stamp_windows, report))
        cumulative += length_cm
    _settle_runs(edges, nodes, station_count, is_loop, always=False)
    chain_count = len({int(f.get("chain") or 0) for f in fragments})
    return nodes, edges, chain_count


def _derive_parts(source: LineSource, report: dict):
    line = source.line
    station_count = len(line["stations"])
    is_loop = bool(line.get("isLoop"))
    fragments = source.fragments
    by_lane: dict[float, list] = {}
    for sequence, (lane, owner, coordinates) in enumerate(source.pieces):
        by_lane.setdefault(float(lane), []).append((sequence, owner, _tuples(coordinates)))
    cursors = {lane: 0 for lane in by_lane}
    covered = {lane: 0 for lane in by_lane}      # vertices of the current original already matched

    flat = 0
    part_runs: dict[int, list] = {}              # interval -> [(order, chain, full cm, overview cm, draw id, part index)]
    flat_of: dict[tuple[int, int], int] = {}
    for number, fragment in enumerate(fragments):
        lane = float(fragment.get("lane") or 0.0)
        originals = by_lane.get(lane)
        if originals is None:
            raise TopologyError(f"{source.key}: fragment lane {lane} has no recorded pieces")
        overview = source.overview[number] if source.overview else None
        for part_index, part in enumerate(fragment["parts"]):
            points = _rounded_tuples(part)
            cursor = cursors[lane]
            if cursor >= len(originals):
                raise TopologyError(f"{source.key}: more final parts than pieces in lane {lane}")
            sequence, owner, original = originals[cursor]
            start = covered[lane]
            if original[start:start + len(points)] != points:
                raise TopologyError(
                    f"{source.key}: part {part_index} of {source.draw_ids[number]} does not continue "
                    "the piece the builder cut")
            covered[lane] = start + len(points) - 1
            if covered[lane] == len(original) - 1:
                cursors[lane] += 1
                covered[lane] = 0
            full_cm = to_cm(ruler(points)[-1])
            overview_cm = UNSET
            if overview is not None and len(overview["parts"]) == len(fragment["parts"]):
                overview_cm = to_cm(ruler(_tuples(overview["parts"][part_index]))[-1])
            part_runs.setdefault(owner, []).append(
                ((sequence, start), flat, full_cm, overview_cm, source.draw_ids[number], part_index))
            flat_of[(number, part_index)] = flat
            flat += 1
    for lane, originals in by_lane.items():
        if cursors[lane] != len(originals):
            raise TopologyError(f"{source.key}: lane {lane} pieces were not all found in the final parts")
    edge_count = station_count if is_loop else station_count - 1
    edges: list[Edge] = []
    cumulative = 0
    for interval in range(edge_count):
        km = float(line["segments"][interval][0])
        length_cm = to_cm(km * 1000.0)
        runs, windows = [], []
        for _, chain, full_cm, overview_cm, draw_id, part_index in sorted(part_runs.get(interval, [])):
            runs.append(Run(chain, 0, full_cm, 0 if overview_cm != UNSET else UNSET, overview_cm))
            windows.append(_stamp_window(source.stamps, draw_id, part_index))
        edges.append(_edge(source, interval, length_cm, cumulative, runs, windows, report))
        cumulative += length_cm
    nodes: list[Node] = []
    for j, row in enumerate(line["stations"]):
        outgoing = edges[j] if j < len(edges) else None
        incoming = edges[j - 1] if j > 0 else (edges[-1] if is_loop and edges else None)
        node = Node(row[0], 0, UNSET, UNSET, row[2], row[3], NODE_NO_CHAIN_SLOT)
        if outgoing is not None and outgoing.runs:
            first = outgoing.runs[0]
            node = Node(row[0], first.chain, first.full_from, first.overview_from, row[2], row[3], 0)
        elif incoming is not None and incoming.runs:
            last = incoming.runs[-1]
            node = Node(row[0], last.chain, last.full_to, last.overview_to, row[2], row[3], 0)
        else:
            adjacent = [e for e in (outgoing, incoming) if e is not None]
            # A station whose every adjacent interval is withheld has nothing drawn to sit on:
            # it keeps NODE_NO_CHAIN_SLOT, as the contract says, and is not an error.
            if not adjacent or not all(e.flags & EDGE_WITHHELD for e in adjacent):
                report["unanchoredStations"].append(f"{source.key}:{row[0]}")
        nodes.append(node)
    _settle_runs(edges, nodes, station_count, is_loop, always=True)
    return nodes, edges, flat


def _edge(source: LineSource, interval: int, length_cm: int, cumulative: int,
          runs: list[Run], windows: list, report: dict) -> Edge:
    if length_cm <= 0:
        raise TopologyError(f"{source.key}: interval {interval} has no surveyed length")
    flags = 0
    allowed = allowed_directions(source.line, interval)
    if 1 in allowed:
        flags |= EDGE_FORWARD
    if -1 in allowed:
        flags |= EDGE_REVERSE
    if interval in source.withheld:
        flags |= EDGE_WITHHELD
    if not runs and not flags & EDGE_WITHHELD:
        report["edgesWithoutGeometry"].append(f"{source.key}#{interval}")
    stamped = [w for w in windows if w is not None]
    valid_from = valid_to = NO_DATE
    if stamped:
        # One edge can lie on track with different stamps. It is usable on a day
        # when any of its track is, so the window is the hull of the runs' windows
        # and an unstamped run (or a missing bound) leaves that side open.
        froms = [NO_DATE if w is None else optional_day(w[0]) for w in windows]
        tos = [NO_DATE if w is None else optional_day(w[1]) for w in windows]
        valid_from = NO_DATE if NO_DATE in froms else min(froms)
        valid_to = NO_DATE if NO_DATE in tos else max(tos)
        report["datedEdges"] += 1
        if len(set(windows)) > 1:
            report["edgesWithMixedValidity"] += 1
            report["mixedValidityEdges"].append(
                {"edge": f"{source.key}#{interval}", "validFrom": valid_from, "validTo": valid_to})
    segments = source.line.get("segments") or []
    steps = len(segments[interval][2]) - 1 if interval < len(segments) and len(segments[interval]) > 2 else 1
    return Edge(length_cm, cumulative, valid_from, valid_to, flags, runs, max(1, steps))


def _settle_runs(edges: list[Edge], nodes: list[Node], station_count: int,
                 is_loop: bool, always: bool) -> None:
    """Mark which edges need explicit runs. An edge may omit them only when its
    single run is exactly the range between its two nodes' own positions."""
    for index, edge in enumerate(edges):
        a = nodes[index]
        b = nodes[(index + 1) % station_count]
        direct = (
            not always and len(edge.runs) == 1 and a.flags == 0 and b.flags == 0
            and edge.runs[0].chain == a.chain == b.chain
            and edge.runs[0].full_from == a.full and edge.runs[0].full_to == b.full
            and edge.runs[0].overview_from == a.overview and edge.runs[0].overview_to == b.overview)
        if direct:
            edge.runs = []
        else:
            edge.flags |= EDGE_HAS_RUNS


# --------------------------------------------------------------------------
# Links and stops
# --------------------------------------------------------------------------

# An edge whose drawn length is outside this band of its surveyed length is
# listed in the report: the geometry or the stored length is off, or the edge was
# laid on the wrong stretch of its chain.
LENGTH_RATIO_BAND = (0.8, 1.25)


def _report_length_mismatches(key: str, nodes: list[Node], edges: list[Edge], report: dict) -> None:
    for index, edge in enumerate(edges):
        if edge.flags & EDGE_WITHHELD:
            continue
        if edge.runs:
            drawn = sum(abs(run.full_to - run.full_from) for run in edge.runs)
        else:
            a, b = nodes[index], nodes[(index + 1) % len(nodes)]
            if a.full == UNSET or b.full == UNSET:
                continue
            drawn = abs(b.full - a.full)
        if drawn and not LENGTH_RATIO_BAND[0] <= drawn / edge.length_cm <= LENGTH_RATIO_BAND[1]:
            report["lengthMismatchEdges"].append(
                {"line": key, "interval": index, "drawnCm": drawn, "surveyedCm": edge.length_cm})


def has_same_train_evidence(evidence: list) -> bool:
    """`RouteGraph.PhysicalJunction.hasSameTrainEvidence`."""
    for item in evidence:
        trimmed = str(item).strip()
        if not trimmed:
            continue
        lower = trimmed.lower()
        if "openstreetmap.org" in lower:
            continue
        if lower.startswith("way ") and lower[4:].isdigit():
            continue
        return True
    return False


def line_pairs(record: dict) -> list[tuple[str, str]]:
    """`TripConnectivity.Junctions.linePairs`."""
    ids = list(record.get("lineIDs") or [])
    distinct = set(ids)
    if len(distinct) == 2:
        a, b = ids[0], next(value for value in ids if value != ids[0])
        return [(a, b)]
    if len(distinct) > 2 and record.get("fromLineIDs") and record.get("toLineIDs"):
        from_ids, to_ids = list(record["fromLineIDs"]), list(record["toLineIDs"])
        if set(from_ids).isdisjoint(to_ids) and set(from_ids) | set(to_ids) == distinct:
            return [(a, b) for a in from_ids for b in to_ids]
    return []


def compile_junction_links(document: dict, region: str, node_of) -> tuple[list[Link], list[dict]]:
    """Links from `physical-rail-junctions.json`. `node_of(line id, code)` is the
    global node index or None. Returns (links, rows that could not be used)."""
    links: list[Link] = []
    skipped: list[dict] = []
    seen = set()
    for record in document.get("junctions") or []:
        if record.get("region") != region:
            continue
        row_id = record.get("id") or ""
        code = record.get("stationCode")
        evidence = record.get("evidence") or []
        if not code or not evidence:
            skipped.append({"id": row_id, "reason": "noStationCodeOrEvidence"})
            continue
        if record.get("endJunction") is not None and not has_same_train_evidence(evidence):
            skipped.append({"id": row_id, "reason": "endJunctionWithoutTrainEvidence"})
            continue
        pairs = line_pairs(record)
        if not pairs:
            skipped.append({"id": row_id, "reason": "noTwoLinePair"})
            continue
        valid_from, valid_to = optional_day(record.get("validFrom")), optional_day(record.get("validTo"))
        for first, second in pairs:
            a, b = node_of(first, code), node_of(second, code)
            if a is None or b is None:
                missing = [line for line, node in ((first, a), (second, b)) if node is None]
                skipped.append({"id": row_id, "reason": "stationCodeNotOnLine",
                                "stationCode": code, "lines": missing})
                continue
            low, high = sorted((a, b))
            key = (low, high, LINK_PHYSICAL_JUNCTION, valid_from, valid_to, row_id)
            if key not in seen:
                seen.add(key)
                links.append(Link(low, high, LINK_PHYSICAL_JUNCTION, False, valid_from, valid_to, row_id))
    return links, skipped


def _variants_valid(variants: list, leg_count: int) -> bool:
    def valid_day(value) -> bool:
        if value is None:
            return True
        try:
            return day_number(value) > 0
        except TopologyError:
            return False

    def valid_url(value: str) -> bool:
        match = re.match(r"^https?://([^/\s?#]+)", value or "", re.IGNORECASE)
        return bool(match) and not re.search(r"\s", value)

    for variant in variants:
        indices = variant.get("legIndices") or []
        if variant.get("suspended") is True:
            if indices or variant.get("validFrom") is None or variant.get("validTo") is None:
                return False
        elif not indices:
            return False
        if len(set(indices)) != len(indices) or any(not 0 <= i < leg_count for i in indices):
            return False
        if not valid_day(variant.get("validFrom")) or not valid_day(variant.get("validTo")):
            return False
        urls = variant.get("sourceURLs") or []
        if not urls or not all(valid_url(u) for u in urls):
            return False
        v_from, v_to = variant.get("validFrom"), variant.get("validTo")
        if v_from is not None and v_to is not None and v_from >= v_to:
            return False
    ordered = sorted(variants, key=lambda v: v.get("validFrom") or "")
    for previous, following in zip(ordered, ordered[1:]):
        end, start = previous.get("validTo"), following.get("validFrom")
        if end is None or start is None or end > start:
            return False
    return True


def _active(valid_from: int, valid_to: int, day: int | None) -> bool:
    if day is None:
        return valid_to == NO_DATE
    if valid_from != NO_DATE and valid_from > day:
        return False
    if valid_to != NO_DATE and day >= valid_to:
        return False
    return True


def pattern_legs_on(pattern: dict, day: int | None, coverage_from: int) -> list[dict]:
    """`JapanThroughServices.Pattern.legs(on:)` with dates as day numbers."""
    p_from, p_to = optional_day(pattern.get("validFrom")), optional_day(pattern.get("validTo"))
    if not _active(p_from, p_to, day):
        return []
    if p_from == NO_DATE and day is not None and coverage_from and day < coverage_from:
        return []
    legs = pattern["legs"]
    variants = pattern.get("legVariants")
    if variants is not None:
        if not _variants_valid(variants, len(legs)):
            return []
        matching = [v for v in variants if _active(
            optional_day(v.get("validFrom")), optional_day(v.get("validTo")), day)]
        if len(matching) != 1 or matching[0].get("suspended") is True:
            return []
        indices = list(matching[0]["legIndices"])
    else:
        indices = list(range(len(legs)))
    positions = [position for position, index in enumerate(indices) if _active(
        optional_day(legs[index].get("validFrom")), optional_day(legs[index].get("validTo")), day)]
    if any(b != a + 1 for a, b in zip(positions, positions[1:])):
        return []
    return [legs[indices[position]] for position in positions]


def compile_through_links(document: dict, node_of) -> tuple[list[Link], list[dict]]:
    """Links from `japan-through-services.json`: one per pair of adjacent legs of
    a pattern's effective path, with the day ranges over which that pair exists."""
    coverage_from = optional_day(document.get("coverageFrom"))
    connectors = document.get("connectors") or []

    def connector_joins(first_ids, first_code, second_ids, second_code, day) -> bool:
        for c in connectors:
            if not _active(optional_day(c.get("validFrom")), optional_day(c.get("validTo")), day):
                continue
            if (c["fromLineID"] in first_ids and first_code == c["fromStationCode"]
                    and c["toLineID"] in second_ids and second_code == c["toStationCode"]):
                return True
            if (c["toLineID"] in first_ids and first_code == c["toStationCode"]
                    and c["fromLineID"] in second_ids and second_code == c["fromStationCode"]):
                return True
        return False

    connector_days = set()
    for c in connectors:
        for key in ("validFrom", "validTo"):
            if c.get(key):
                connector_days.add(day_number(c[key]))
    links: list[Link] = []
    skipped: list[dict] = []
    for pattern in document.get("patterns") or []:
        days = set(connector_days)
        if coverage_from:
            days.add(coverage_from)
        for holder in [pattern, *(pattern.get("legs") or []), *(pattern.get("legVariants") or [])]:
            for key in ("validFrom", "validTo"):
                if holder.get(key):
                    days.add(day_number(holder[key]))
        boundaries = sorted(days)
        segments = []                       # (start, end, representative day)
        previous = NO_DATE
        for boundary in boundaries:
            segments.append((previous, boundary, 1 if previous == NO_DATE else previous))
            previous = boundary
        segments.append((previous, NO_DATE, None))
        windows: dict[tuple, list[list[int]]] = {}
        for start, end, day in segments:
            legs = pattern_legs_on(pattern, day, coverage_from)
            for a, b in zip(legs, legs[1:]):
                first_ids = [a["lineID"]] + ([a["reverseLineID"]] if a.get("reverseLineID") else [])
                second_ids = [b["lineID"]] + ([b["reverseLineID"]] if b.get("reverseLineID") else [])
                if a["toStationCode"] == b["fromStationCode"]:
                    code_a = code_b = a["toStationCode"]
                elif connector_joins(first_ids, a["toStationCode"], second_ids, b["fromStationCode"], day):
                    code_a, code_b = a["toStationCode"], b["fromStationCode"]
                else:
                    continue
                for first in first_ids:
                    for second in second_ids:
                        if first == second:
                            continue
                        node_a, node_b = node_of(first, code_a), node_of(second, code_b)
                        if node_a is None or node_b is None:
                            row = {"id": pattern["id"], "reason": "stationCodeNotOnLine",
                                   "lines": [first, second], "codes": [code_a, code_b]}
                            if row not in skipped:      # once per pair, not once per date segment
                                skipped.append(row)
                            continue
                        low, high = sorted((node_a, node_b))
                        spans = windows.setdefault((low, high), [])
                        if spans and spans[-1][1] == start and spans[-1][1] != NO_DATE:
                            spans[-1][1] = end
                        else:
                            spans.append([start, end])
        for (low, high), spans in windows.items():
            for start, end in spans:
                links.append(Link(low, high, LINK_THROUGH_SERVICE, False, start, end, pattern["id"]))
    unique = {}
    for link in links:
        unique[(link.node_a, link.node_b, link.valid_from, link.valid_to, link.registry_id)] = link
    return list(unique.values()), skipped


def compile_stops(lines: list[LineRecord], node_base: list[int], registry: dict | None) -> tuple[list[Stop], dict]:
    """Stop keys to nodes: platform/station code (kind 1), registry station id
    `st:*` (kind 2) and group code (kind 3)."""
    by_code: dict[str, list[int]] = {}
    for line, base in zip(lines, node_base):
        for ordinal, node in enumerate(line.nodes):
            if node.code is not None:
                by_code.setdefault(node.code, []).append(base + ordinal)
    stops = [Stop(code, STOP_PLATFORM, sorted(set(nodes))) for code, nodes in by_code.items()]
    registry_stations = 0
    groups = 0
    if registry:
        codes_of: dict[str, set[str]] = {}
        for station_id, row in (registry.get("stations") or {}).items():
            codes_of.setdefault(station_id, set()).update(row.get("codes") or [])
        for code, station_id in (registry.get("stationCodes") or {}).items():
            codes_of.setdefault(station_id, set()).add(code)
        nodes_of: dict[str, list[int]] = {}
        for station_id, codes in codes_of.items():
            nodes = sorted({n for c in codes for n in by_code.get(c, [])})
            if not nodes:
                group = ((registry.get("stations") or {}).get(station_id) or {}).get("group")
                nodes = sorted(set(by_code.get(group, []))) if group else []
            if nodes:
                nodes_of[station_id] = nodes
                stops.append(Stop(station_id, STOP_REGISTRY, nodes))
                registry_stations += 1
        for group, station_ids in (registry.get("groupCodes") or {}).items():
            nodes = sorted({n for s in station_ids for n in nodes_of.get(s, [])} | set(by_code.get(group, [])))
            if nodes:
                stops.append(Stop(group, STOP_GROUP, nodes))
                groups += 1
    stops.sort(key=lambda stop: (stop.key.encode("utf-8"), stop.kind))
    return stops, {"platformKeys": len(by_code), "registryKeys": registry_stations, "groupKeys": groups}


# --------------------------------------------------------------------------
# The region
# --------------------------------------------------------------------------

def _line_flags(source: LineSource) -> int:
    line = source.line
    flags = 0
    if line.get("isLoop"):
        flags |= LINE_LOOP
    if line.get("isHSR"):
        flags |= LINE_HIGH_SPEED
    if line.get("alignmentOf") or line.get("alignmentPairs"):
        flags |= LINE_PAIRED
    if not source.continuous:
        flags |= LINE_NON_CONTINUOUS
    return flags


# Edges whose drawn length is far from the surveyed one in the source data
# itself (tram stations placed along the track differently from the stored
# kilometres). A ledger that may only shrink.
KNOWN_LENGTH_MISMATCHES = frozenset({
    ("jp|jp-伊予鉄道-城北線", 4), ("jp|jp-伊予鉄道-城北線", 5), ("jp|jp-伊予鉄道-城北線", 6),
    ("jp|jp-伊予鉄道-花園線", 0), ("jp|jp-万葉線-高岡軌道線", 5), ("jp|jp-万葉線-高岡軌道線", 12),
})

# Registry rows the builder cannot turn into a link: the row names a station
# code one of its lines does not have, has one line only (nothing to join), or
# has no station code or evidence. Reported, not guessed, until the reviewed
# exception file turns each into a link, an intra-line row or an error. A
# ledger that may only shrink; a row not listed here stops the build.
KNOWN_UNPLACED_JUNCTION_ROWS = frozenset({
    ('agano-ikebukuro-seibu-chichibu', 'stationCodeNotOnLine'),
    ('akabane-tohoku-track', 'noTwoLinePair'),
    ('aomori-tohoku-tsugaru', 'stationCodeNotOnLine'),
    ('astram-kencho-class16-class24', 'noTwoLinePair'),
    ('fukui-railway-fukubu-class12-class21-shokokaigisho-mae', 'noTwoLinePair'),
    ('goryokaku-esashi-hakodate-kamiiso', 'noStationCodeOrEvidence'),
    ('goryokaku-hakodate-esashi', 'stationCodeNotOnLine'),
    ('higashi-kanagawa-tokaido-yokohama', 'stationCodeNotOnLine'),
    ('kaifu-mugi-asato', 'stationCodeNotOnLine'),
    ('kanazawa-ir-hokuriku', 'stationCodeNotOnLine'),
    ('kanda-tohoku-track', 'noTwoLinePair'),
    ('kikonai-esashi-kaikyo', 'noStationCodeOrEvidence'),
    ('kikonai-kaikyo-isaribi', 'noTwoLinePair'),
    ('kintetsu-keihanna-class21-class12-mid-tunnel', 'noStationCodeOrEvidence'),
    ('kitaosaka-minoh-semba-class12-class21', 'noTwoLinePair'),
    ('kobe-new-transit-port-island-class16-class24-minami-koen', 'noTwoLinePair'),
    ('kobe-new-transit-port-island-class24-class16-port-terminal', 'noTwoLinePair'),
    ('kobe-new-transit-rokko-island-class16-class24-minami-uozaki', 'noTwoLinePair'),
    ('kobe-new-transit-rokko-island-class24-class16-island-kitaguchi', 'noTwoLinePair'),
    ('matobacho-gap-008063', 'noTwoLinePair'),
    ('matsuda-east-15', 'stationCodeNotOnLine'),
    ('musashino-minami-fuchuhommachi-tsurumi', 'noStationCodeOrEvidence'),
    ('nagoya-chuo-tokaido', 'stationCodeNotOnLine'),
    ('naka-oguni-tsugaru-kaikyo', 'noTwoLinePair'),
    ('naoetsu-shinetsu-hokuriku', 'stationCodeNotOnLine'),
    ('niiya-yosan-uchiko', 'stationCodeNotOnLine'),
    ('nippori-tohoku-main-approach', 'noTwoLinePair'),
    ('nishi-biwajima-nagoya-inuyama', 'stationCodeNotOnLine'),
    ('okutsugaru-imabetsu-kaikyo-osm', 'noTwoLinePair'),
    ('osaka-metro-chuo-class12-class21-osakako', 'noTwoLinePair'),
    ('osaka-metro-nankou-port-town-class16-class24-nakafuto', 'noTwoLinePair'),
    ('osaka-metro-nankou-port-town-class16-class24-trade-center-mae', 'noTwoLinePair'),
    ('osaka-metro-nankou-port-town-class24-class16-ferry-terminal', 'noTwoLinePair'),
    ('osaki-yamanote-tokaido', 'stationCodeNotOnLine'),
    ('sangi-asake-gap-005982', 'noTwoLinePair'),
    ('seibu-chichibu-connector', 'stationCodeNotOnLine'),
    ('sendai-kagoshima-hisatsu-orange', 'stationCodeNotOnLine'),
    ('senseki-tohoku-connector', 'stationCodeNotOnLine'),
    ('tokoname-tokoname-airport', 'stationCodeNotOnLine'),
    ('tokyo-sobu-shin-nihonbashi', 'noTwoLinePair'),
    ('tokyo-tohoku-kanda', 'noTwoLinePair'),
    ('tokyo-tohoku-shinkansen-ueno', 'noTwoLinePair'),
    ('tokyo-tokaido-shinkansen-shinagawa', 'noTwoLinePair'),
    ('tokyo-tokaido-yurakucho', 'noTwoLinePair'),
    ('toyama-chitetsu-toyamako-class12-class21-okuda-chugakko-mae', 'noTwoLinePair'),
    ('tsubata-hokuriku-nanao', 'stationCodeNotOnLine'),
    ('tsugaru-futamata-kaikyo-tsugaru', 'stationCodeNotOnLine'),
    ('tsukuda-tokushima-dosan', 'stationCodeNotOnLine'),
    ('uchiko-yosan-uchiko', 'stationCodeNotOnLine'),
})


def enforce_invariants(region: str, report: dict) -> None:
    """Stop the build on what the file's consumers cannot work around: a station
    with no position, an edge with no geometry, a slot or overview that does not
    line up, an edge length or an unplaced link row outside the ledgers above.
    Only jp has ledger entries; every other region must report none. Link rows
    are only checked for a region that has lines."""
    problems = []
    for name in ("unanchoredStations", "slotMismatches", "edgesWithoutGeometry"):
        if report[name]:
            problems.append(f"{name}: {report[name][:5]}")
    if report["overviewAlignFailures"]:
        problems.append(f"overviewAlignFailures: {report['overviewAlignFailures']}")
    known_lengths = KNOWN_LENGTH_MISMATCHES if region == "jp" else frozenset()
    reported_lengths = {(row["line"], row["interval"]) for row in report["lengthMismatchEdges"]}
    extra = [row for row in report["lengthMismatchEdges"]
             if (row["line"], row["interval"]) not in known_lengths]
    if extra:
        problems.append(f"lengthMismatchEdges outside the ledger: {extra[:5]}")
    if report["lines"]:     # the ledger is two-sided: a fixed edge must leave it
        stale = sorted(known_lengths - reported_lengths)
        if stale:
            problems.append(f"KNOWN_LENGTH_MISMATCHES entries no longer reported (remove them): {stale[:5]}")
    if report["lines"]:     # a region with no lines has nothing to place the registry rows on
        known_rows = KNOWN_UNPLACED_JUNCTION_ROWS if region == "jp" else frozenset()
        rows = [row for row in report["unplacedJunctionRows"]
                if (row["id"], row["reason"]) not in known_rows]
        if rows:
            problems.append(f"unplacedJunctionRows outside the ledger: {rows[:5]}")
        stale_rows = sorted(known_rows - {(row["id"], row["reason"]) for row in report["unplacedJunctionRows"]})
        if stale_rows:
            problems.append(f"KNOWN_UNPLACED_JUNCTION_ROWS entries no longer reported (remove them): {stale_rows[:5]}")
        if report["unplacedThroughServiceRows"]:
            problems.append(f"unplacedThroughServiceRows: {report['unplacedThroughServiceRows'][:5]}")
    if problems:
        raise TopologyError(f"{region}: " + "; ".join(problems))


def new_report() -> dict:
    return {
        "overviewAlignFailures": 0, "unanchoredStations": [], "slotMismatches": [],
        "edgesWithoutGeometry": [], "edgesWithMixedValidity": 0, "mixedValidityEdges": [], "datedEdges": 0,
        "intervalsOnSeveralChains": 0, "routedEdges": [], "lengthMismatchEdges": [],
    }


# --------------------------------------------------------------------------
# Institution and operator of each Japanese line (N02, the route solver's source)
# --------------------------------------------------------------------------
INSTITUTION_CODES = frozenset({1, 2, 3, 4, 5})
_VARIANT_SUFFIX = re.compile(r"(.*)-(?:p\d+|\d+)")


def build_n02_index(document: dict) -> dict:
    """From the N02 railroad sections (`rail-sections.json`): per line key
    `jp-{N02_004}-{N02_003}` the institution type `N02_002` and the operator
    `N02_004`, the two fields the route solver reads from each section
    (`RouteGraph`, `Statistics.RailProperties`). A line whose sections carry two
    codes stops the build: the solver would price its sections differently. The index
    also holds the section vertices in a grid (`cells`), for `n02_corridor_names`."""
    lines: dict[str, tuple[int, str, str]] = {}
    operators: dict[str, set[int]] = {}
    names: list[str] = []            # attribute id -> N02_003
    name_ids: dict[str, int] = {}
    cells: dict[tuple[int, int], list[tuple[float, float, int]]] = {}
    for feature in document.get("features") or []:
        props = feature.get("properties") or {}
        operator, name, raw = props.get("N02_004"), props.get("N02_003"), props.get("N02_002")
        if not operator or not name:
            continue
        try:
            code = int(raw)
        except (TypeError, ValueError):
            raise TopologyError(f"N02 section of {operator} {name} has institution {raw!r}")
        if code not in INSTITUTION_CODES:
            raise TopologyError(f"N02 section of {operator} {name} has institution {code}")
        key = f"jp-{operator}-{name}"
        known = lines.get(key)
        if known is not None and known[0] != code:
            raise TopologyError(f"N02 line {key} has institution {known[0]} and {code}")
        lines[key] = (code, operator, name)
        operators.setdefault(operator, set()).add(code)
        geometry = feature.get("geometry") or {}
        coordinates = geometry.get("coordinates") or []
        if geometry.get("type") == "MultiLineString":
            coordinates = [point for part in coordinates for point in part]
        name_id = name_ids.setdefault(name, len(names))
        if name_id == len(names):
            names.append(name)
        for lon, lat in coordinates:
            cells.setdefault((int(lon / N02_CELL), int(lat / N02_CELL)), []).append((lon, lat, name_id))
    return {"lines": lines, "operators": operators, "names": names, "cells": cells}


ALIAS_SEPARATOR = "\u001f"
N02_CELL = 0.0005                 # degrees, about 55 m
N02_MATCH_METRES = 40.0
N02_SAMPLES_PER_INTERVAL = 6
N02_ALIAS_SHARE = 0.30


def n02_corridor_names(line: dict, own_name: str, index: dict) -> list[str]:
    """Other N02 line names that run along this package line. The solver names a track
    by the N02 section it lies on, one name per section, while a package line can follow
    track that N02 files under another line (the Yokosuka-Sobu rapid line between
    Shinagawa and Tsurumi is N02's Tokaido Line). A trip or section that names the other
    line must still reach this one. Sample each interval's polyline, find the nearest N02
    vertex within 40 m, and keep every name other than `own_name` that holds at least 30%
    of the matched samples, most frequent first."""
    cells = index.get("cells") or {}
    names = index.get("names") or []
    votes: dict[int, int] = {}
    matched = 0
    for segment in line.get("segments") or []:
        points = segment[2] if len(segment) > 2 else []
        step = max(1, len(points) // N02_SAMPLES_PER_INTERVAL)
        for lon, lat in points[::step]:
            cx, cy = int(lon / N02_CELL), int(lat / N02_CELL)
            best, best_distance = None, N02_MATCH_METRES
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for x, y, name_id in cells.get((cx + dx, cy + dy), ()):
                        distance = math.hypot((x - lon) * 111320 * math.cos(math.radians(lat)), (y - lat) * 111320)
                        if distance <= best_distance:
                            best, best_distance = name_id, distance
            if best is not None:
                votes[best] = votes.get(best, 0) + 1
                matched += 1
    if not matched:
        return []
    kept = [(count, names[name_id]) for name_id, count in votes.items()
            if names[name_id] != own_name and count / matched >= N02_ALIAS_SHARE]
    return [name for _, name in sorted(kept, key=lambda item: (-item[0], item[1]))]


def n02_attributes(line_id: str, index: dict) -> tuple[int, str, str, str]:
    """(institution, operator, solver line name, how) for a topology line id. The id is
    `jp-{operator}-{name}` plus, for a variant of the same line, a `-p1` or `-2`
    style suffix, removed until the key is known (how = "line"). A line the N02
    data does not list under its own name (the Keio New Line is part of the Keio
    Line there; the Hiroden loop is part of its other lines) takes the code of its
    operator when every section of that operator has the same one (how =
    "operator"; the line keeps its own name, as N02 has no other). Anything else stops the build."""
    lines, operators = index["lines"], index["operators"]
    candidate = line_id
    while True:
        found = lines.get(candidate)
        if found is not None:
            return found[0], found[1], found[2], "line"
        match = _VARIANT_SUFFIX.fullmatch(candidate)
        if match is None:
            break
        candidate = match.group(1)
    for operator in sorted(operators, key=lambda name: (-len(name), name)):
        if line_id.startswith(f"jp-{operator}-"):
            codes = operators[operator]
            if len(codes) == 1:
                return next(iter(codes)), operator, None, "operator"
            raise TopologyError(f"{line_id}: not an N02 line, and {operator} has institutions {sorted(codes)}")
    raise TopologyError(f"{line_id}: no N02 line or operator to take the institution from")


def build_region_topology(region: str, sources: list[LineSource], package_sha256: bytes,
                          display_sha256: bytes, junctions: dict | None,
                          through_services: dict | None, registry: dict | None,
                          n02_index: dict | None = None) -> tuple[bytes, dict]:
    """The bytes of `{region}.topology.bin` and a report. `sources` are the lines
    with display data in manifest blob order. `n02_index` (see `build_n02_index`)
    gives each Japanese line its institution and operator; a region without N02
    data has institution 0 and the package's operator name."""
    report = new_report()
    report["institutionLines"] = {}
    report["institutionByOperatorLines"] = []
    lines: list[LineRecord] = []
    for source in sources:
        line = source.line
        stations = line.get("stations") or []
        if not stations:
            raise TopologyError(f"{source.key}: no stations")
        codes = [row[0] for row in stations]
        if len(set(codes)) != len(codes):
            raise TopologyError(f"{source.key}: duplicate station codes")
        if len(line.get("segments") or []) != (len(stations) if line.get("isLoop") else len(stations) - 1):
            raise TopologyError(f"{source.key}: interval count does not match the stations")
        derive = _derive_continuous if source.continuous else _derive_parts
        nodes, edges, chain_count = derive(source, report)
        _report_length_mismatches(source.key, nodes, edges, report)
        name = line["name"]
        family = line.get("railwayIdentity") or "-".join(
            [region, line.get("operator") or "", line.get("nameNorm") or name])
        if region == "jp":
            if n02_index is None:
                raise TopologyError("jp lines need the N02 sections to take institution and operator from")
            institution, operator, solver_name, how = n02_attributes(line["id"], n02_index)
            if how == "operator":
                report["institutionByOperatorLines"].append(line["id"])
            counts = report["institutionLines"]
            counts[str(institution)] = counts.get(str(institution), 0) + 1
        else:
            institution, operator, solver_name = 0, line.get("operator") or None, name
        aliases = ALIAS_SEPARATOR.join(n02_corridor_names(line, solver_name or name, n02_index)) \
            if region == "jp" else ""
        lines.append(LineRecord(
            id=line["id"], family=family, name=name, aliases=aliases, institution=institution,
            category_mask=0, flags=_line_flags(source), chain_count=chain_count,
            valid_from=NO_DATE, valid_to=NO_DATE, nodes=nodes, edges=edges, operator=operator,
            solver_name=solver_name or name))
    node_base, total = [], 0
    for record in lines:
        node_base.append(total)
        total += len(record.nodes)
    ordinal_of = {(record.id, node.code): base + ordinal for record, base in zip(lines, node_base)
                  for ordinal, node in enumerate(record.nodes)}

    def node_of(line_id: str, code: str):
        return ordinal_of.get((line_id, code))

    links, skipped = [], []
    if junctions is not None:
        found, rows = compile_junction_links(junctions, region, node_of)
        links += found
        skipped += rows
    through_skipped = []
    if through_services is not None:
        found, through_skipped = compile_through_links(through_services, node_of)
        links += found
    links.sort(key=lambda l: (l.kind, l.node_a, l.node_b, l.valid_from, l.valid_to, l.registry_id))
    stops, stop_counts = compile_stops(lines, node_base, registry)
    data = encode_topology(region, package_sha256, display_sha256, lines, links, stops)
    report.update({
        "lines": len(lines), "nodes": total, "edges": sum(len(l.edges) for l in lines),
        "runs": sum(len(e.runs) for l in lines for e in l.edges), "links": len(links),
        "junctionLinks": sum(1 for l in links if l.kind == LINK_PHYSICAL_JUNCTION),
        "throughServiceLinks": sum(1 for l in links if l.kind == LINK_THROUGH_SERVICE),
        "stops": len(stops), "stopKeys": stop_counts, "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "unplacedJunctionRows": skipped, "unplacedThroughServiceRows": through_skipped,
        "noChainSlotNodes": sum(1 for l in lines for n in l.nodes if n.flags & NODE_NO_CHAIN_SLOT),
    })
    return data, report
