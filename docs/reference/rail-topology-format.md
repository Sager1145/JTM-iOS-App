# Rail topology file format `jtm-display-topology-v1`

Status: contract for the trip-loading pipeline (plan unit U0b,
`docs/maintenance/2026-11-11-trip-loading-baseline-and-plan.md`). Nothing reads
or writes this file in the app yet. The Swift constants in
`ios/RailKit/Sources/RailCore/Topology/RailTopologyFormat.swift` are the code
form of this page; `RailTopologyFormatTests` checks both against the
hand-built fixture `ios/RailKit/Tests/RailCoreTests/Topology/Fixtures/topology-mini.bin`.

One file per region, `rail-display-network/{region}.topology.bin`, written by
`app/scripts/railway/build-display-network.py` in the same run as
`{region}.display.bin`. The manifest region record gains `topologyFile`,
`topologyBytes` and `topologySHA256`. The app maps the file and reads records
in place; there is no decode step and no resident copy.

## Encoding rules

- Little-endian. Fixed-width records. Every table starts on a 4-byte boundary.
  `reserved` fields are written as zero and ignored.
- Strings live only in the string table. A reference is a `UInt32` byte offset
  into it, pointing at a `UInt16` byte length and then that many UTF-8 bytes.
  Offset 0 is the empty string. `0xFFFFFFFF` (`noString`) is "absent".
- Same input, same bytes. No timestamps, no map ordering.
- Versioning: `formatVersion` in the header is 1. A reader refuses any other
  value. A layout change bumps the version and the format name; there is no
  in-file feature negotiation.

## Units

| Quantity | Type | Unit |
|---|---|---|
| Length, chain position | `UInt32` | centimetres (0.01 m). `StrokeRef` measures are metres: divide by 100 |
| Unset position | `UInt32` | `0xFFFFFFFF` (`unsetMetres`) |
| Coordinate | `Float32` | degrees WGS84, coarse use only |
| Date | `UInt16` | day number, 1 = 2000-01-01, 0 = no bound, up to 2179-06-06 |

`validFrom` is the first day a row applies and `validTo` the last day,
inclusive. Both 0 means always. A query without a date matches only rows with
both 0.

## Layout

```
0     header (160 bytes)
160   lines       N x 52
      nodes       N x 28
      edges       N x 24
      runs        N x 20
      links       N x 20
      identities  N x 16
      stops       N x 16
      stopNodes   N x 4
      strings     bytes, zero-padded to a multiple of 4
```

### Header (160 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `JTMT` |
| 4 | 2 | formatVersion = 1 |
| 6 | 2 | headerSize = 160 |
| 8 | 4 | region, ASCII, NUL padded (`jp`, `tw`, `hk`, `mo`, `kr`) |
| 12 | 4 | flags = 0 |
| 16 | 32 | SHA-256 of the compact package the builder read |
| 48 | 32 | SHA-256 of `{region}.display.bin` this file belongs to |
| 80 | 4 | fileLength (bytes) |
| 84 | 4 | reserved |
| 88 | 72 | directory: 9 entries of (offset `UInt32`, count `UInt32`) in table order |

The directory `count` is a record count, except for `strings` where it is the
byte length before padding. A reader checks magic, version, header size, that
`fileLength` equals the file size, and that every table lies inside the file,
aligned, without overflow. It also rejects the file when the display blob's
SHA-256 differs from the header's (the manifest's `topologySHA256` is checked
before the file is opened).

### lines (52 bytes), manifest blob order, retired lines included

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | id (string) |
| 4 | 4 | family (string): operator plus normalised name |
| 8 | 4 | name (string) |
| 12 | 4 | aliases (string): alias names joined by U+001F, or empty |
| 16 | 2 | institution type code |
| 18 | 2 | category mask (statistics categories) |
| 20 | 2 | flags: bit 0 loop, 1 highSpeed, 2 pairedUpDown, 3 retired, 4 nonContinuous |
| 22 | 2 | chainCount (chains, or parts when nonContinuous) |
| 24 | 2 | validFrom |
| 26 | 2 | validTo |
| 28 | 4 | firstNode (global index) |
| 32 | 4 | nodeCount (at most 65,535) |
| 36 | 4 | firstEdge (global index) |
| 40 | 4 | edgeCount |
| 44 | 4 | firstIdentity (index into identities) |
| 48 | 2 | identityCount |
| 50 | 2 | reserved |

### nodes (28 bytes), grouped per line in station order

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | stationCode (string), `noString` for a junction point |
| 4 | 4 | fullMetres: cm on the full chunk's chain ruler |
| 8 | 4 | overviewMetres: cm on the overview chunk's ruler for the same chain index, or unset |
| 12 | 4 | longitude `Float32` |
| 16 | 4 | latitude `Float32` |
| 20 | 2 | line index |
| 22 | 2 | chain (or part) index |
| 24 | 2 | flags: bit 0 junctionPoint, bit 1 noChainSlot |
| 26 | 2 | reserved |

A node is a station, or a junction point between stations (no station code).
Both rulers are unset for a station with no chain slot (205 Japanese
stations); the span cannot be drawn and the caller treats it as undrawable.

### edges (24 bytes), grouped per line in node order

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | lengthCm, surveyed, above zero |
| 4 | 4 | cumulativeCm: length from the line's first node to this edge's first node |
| 8 | 2 | validFrom |
| 10 | 2 | validTo |
| 12 | 2 | flags: bit 0 forward, 1 reverse, 2 withheld, 3 hasRuns |
| 14 | 2 | runCount |
| 16 | 4 | firstRun (index into runs) |
| 20 | 4 | reserved |

Edge `k` of a line joins node ordinals `k` and `(k + 1) mod nodeCount`. A loop
line has `nodeCount` edges, the last one closing the loop; other lines have
`nodeCount - 1`. `forward` allows travel first node to second, `reverse` the
other way. A `withheld` edge is drawn dashed and counts for no distance.

### runs (20 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | chain (or part) index |
| 2 | 2 | reserved |
| 4 | 4 | fullFromCm |
| 8 | 4 | fullToCm |
| 12 | 4 | overviewFromCm, or unset |
| 16 | 4 | overviewToCm, or unset |

Runs are the pieces of one edge on one chain or part each, in the edge's travel
order. From greater than to means the piece runs against the chain's own
direction.

### links (20 bytes), the only way to change lines

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | nodeA (global index) |
| 4 | 4 | nodeB (global index) |
| 8 | 1 | kind: 1 physicalJunction, 2 throughService |
| 9 | 1 | flags: bit 0 directed (A to B only) |
| 10 | 2 | validFrom |
| 12 | 2 | validTo |
| 14 | 2 | reserved |
| 16 | 4 | registryID (string): the junction or through-service row it was compiled from |

A link exists only for a reviewed physical junction or a dated through service.
Equal station codes, equal names, station complexes, shared display points and
operator families never create one (`TripConnectivity` grants nothing for
them). Nodes of the same line need no link.

### identities (16 bytes)

Dated former names of a renamed or transferred line: line index `UInt32`,
name (string), family (string), validFrom, validTo. Listed under the line via
`firstIdentity`/`identityCount`.

### stops (16 bytes), sorted ascending by (key UTF-8 bytes, kind)

key (string, 4), keyLength `UInt16`, kind `UInt8` (1 platform or station code,
2 registry station id `st:*`, 3 group code), reserved `UInt8`, firstNode
(index into stopNodes, `UInt32`), nodeCount `UInt32`. `stopNodes` holds global
node indices in ascending order. A reader binary-searches by key bytes, so a
trip resolves without waiting for the registry decode.

## Id spaces

- Line index: position in `lines` (`UInt16` in refs, so at most 65,535 per
  region). Line ids are unique strings per region.
- Node ordinal: position within a line (`UInt16`). Global node index =
  `line.firstNode + ordinal`. A `NodeRef` is (line index, ordinal).
- Edge ordinal and global edge index: same scheme with `firstEdge`.
- Chain index: names a chain of the line's display chunk; the stroke chain id
  is `"{region}|{lineID}#{chain}"`.
- Line indices, ordinals and metres are valid for one topology file only. Any
  cache of them (the ride record file) is keyed by the file's SHA-256.

## Two metre rulers and chain addressing

A span is addressed in chain metres so a ride follows whichever chunk the
network layer holds. Each node stores its position twice:

- `fullMetres` on the full chunk's chain ruler;
- `overviewMetres` on the overview chunk's ruler for the same chain index.

Overview chunks keep fewer vertices (861 of 8,782 stations on the continuous
Japanese lines) but every node has a position on them: the builder projects
the node onto the overview chain. The builder copies the value of the chunk's
own `measures` at the node's position, so a `StrokeRef` built from a node uses
exactly the ruler `ChainRef.measures` uses.

A span `(line, fromNode, toNode)` becomes `StrokeRef`s as follows:

1. Walk the edges between the two nodes in the span's direction.
2. For an edge without `hasRuns`, the piece is `from` = first node's metres,
   `to` = second node's metres on the shared chain; it is reversed when
   travelling against the edge. The edge's two nodes must share a chain.
3. For an edge with `hasRuns`, the pieces are its runs (reversed order and
   swapped ends when travelling against the edge).
4. Adjacent pieces on the same chain with matching ends merge into one
   `StrokeRef`; a new `StrokeRef` starts wherever the chain or part changes.
5. If any needed ruler value is unset the span cannot be drawn at that
   detail.

## Part-range rule for non-continuous fragments

Lines flagged `nonContinuous` (11 Japanese lines and every line of tw, hk, mo
and kr) have no single chain. Their display data is separate fragments called
parts, each with its own ruler starting at 0 m at the fragment's first vertex.
For these lines:

- `chain` is the part index, and a node's metres are measured on its part;
- every edge carries runs (`hasRuns`), because its end nodes may sit on
  different parts and the track between them may use several;
- the runs, not the end nodes' own positions, are authoritative for the
  edge's geometry;
- overview chunks preserve part indices, so the same index addresses the part
  at either detail.

Continuous lines use runs only for the 163 intervals split across lane
pieces.

## How a ride refers to the file

`RideRefs` (`ios/RailKit/Sources/RailCore/Rides/RideRefs.swift`) holds a
16-byte key, an outcome, spans and gaps, and no coordinates.

A span is 8 bytes, little-endian: `line UInt16`, `fromNode UInt16`,
`toNode UInt16`, `tag UInt16`. Nodes are line-local ordinals. **Direction is
the order of the two nodes**: increasing ordinals when `fromNode < toNode`,
decreasing otherwise. On a loop line, tag bit 15 (`wraps`) means the ride
crosses the closing edge instead: from < to then travels downward through node
0 to the last node and on to `toNode`, and from > to travels upward through the
last node and node 0. `fromNode == toNode` never occurs. Tag bits 0 to 13 are
the section index within the trip (at most 16,383), bit 14 `unproven` (found
only without the line filter: drawn dotted, excluded from distance).

A path that changes lines is several spans with the same section index in
travel order. The join is a link and is not stored.

Distance of a span is one subtraction of `cumulativeCm` values (plus the
closing edge for a wrapping span). Withheld edges and `unproven` spans are
excluded from distance.

## Unresolved and historical sections

- A section that cannot be resolved has no spans. It is recorded as a gap
  `{section UInt16, reason UInt8}` with reason bits 0 noPath, 1 ambiguous,
  2 unknownStop, 3 withheld. Never a straight line, never track outside the
  topology.
- Outcome per trip: resolved (no gaps), partial (some spans, some gaps),
  unresolved (spans empty), disabledRegion.
- Historical track is ordinary data. Retired and renamed lines are lines
  flagged `retired` with `validFrom`/`validTo`; their stations are nodes with
  codes; closed intervals carry `validTo` on the edge. The ride's date selects
  the edges and links valid on that day; the same section resolves differently
  the day before and the day of a closure. Dated former names are in
  `identities`.
- A date-less ride matches only rows with both bounds 0.

## Fixture

`topology-mini.bin` (940 bytes, region `jp`) is hand-built with literal
offsets. It has two lines. `jp.test-a` has 3 nodes, 2 edges (the second
one-way, withheld and dated), an alias pair and one former-name row.
`jp.test-b` is a retired, dated, non-continuous loop with 3 nodes (one a
junction point on part 0, one on part 1), 3 edges with 4 runs (one lane-split
edge crossing parts), a dated physical-junction link to line A and a directed
through-service link. Three stop keys, one mapping to two nodes. One node has
no overview position.
