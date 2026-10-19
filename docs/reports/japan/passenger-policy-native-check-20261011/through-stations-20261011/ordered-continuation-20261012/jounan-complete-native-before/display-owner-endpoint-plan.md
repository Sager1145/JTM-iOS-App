# Jōnan west display-owner and endpoint plan

Date: 2026-10-13  
Status: bounded read-only repair preparation. No candidate coordinates, source
mutation, build, or runtime acceptance is included.

## Current compact ownership

The six related rows are contiguous in the current `jp-2025.json` except for
the unrelated 横河原線 row at index 115:

| Package index | Legal line | Source intervals | Derived display parts |
|---:|---|---:|---|
| 111 | `jp-伊予鉄道-城北線` | `#0–#7` | part 0: 67 points, 2728.5 m |
| 112 | `jp-伊予鉄道-城南線` | `#0–#10` | part 0: 3 points, 52.2 m, `complex`; part 1: 73 points, 3581.7 m, `station-approach/groomed` |
| 113 | `jp-伊予鉄道-大手町線` | `#0–#3` | part 0: 26 points, 1340.0 m |
| 114 | `jp-伊予鉄道-本町線` | `#0–#3` | part 0: 13 points, 1377.8 m |
| 116 | `jp-伊予鉄道-花園線` | `#0` | part 0: 13 points, 463.1 m |
| 117 | `jp-伊予鉄道-連絡線` | `#0` | part 0: 11 points, 169.4 m |

None of these six source rows currently has `displayIntervalCoordinates` or
`displayStationCoordinates`. The current display is derived from `stations` and
`segments` by `displayPartsForLine`.

The current `display-lanes.json` has **no `byRegion.jp` lane entry** for any of
the six lines. Its matching `partsByRegion.jp` rows are derived compact-part
summaries, not offset-lane instructions. 城南 is the only member whose two part
rows embed explicit derived coordinates because they are classified
`complex`/`station-approach`; the other five rows have no embedded geometry.
There are also no current follows, family-window, chain-boundary, or reviewed
shared-corridor references for these IDs. A future display-only candidate must
rebuild the derived part rows, but it must not invent or preserve an offset-lane
value that is absent from the current file.

## Exact west owner windows

Coordinates below are the current source/derived indices only. They are custody
anchors, not proposed replacements.

### 城南線: legal multi-arm owner

- Legal interval `#0`, station indices `0→1` (`008756` 本町一丁目 → `008761`
  西堀端), is source `segments[0][2][0…4]`.
- The derived display deliberately separates it: part 1 indices `0…2` run
  `[132.75865,33.840755] → [132.75865,33.8403]`; part 0 indices `0…2` run
  `[132.75865,33.8403] → [132.758085,33.8403]`.
- `[132.75865,33.8403]` is the shared **junction vertex**, not a station. It must
  remain a non-station continuity point and must not become the dot for either
  本町一丁目 or 西堀端.
- Legal interval `#1`, station indices `1→2` (`008761` 西堀端 → `008768`
  南堀端), is `segments[1][2][0…7]`. Its source begins west of the junction and
  doubles east; the derived part 1 uses indices `2…8` to continue from the
  junction south and east. A display repair may preserve this split, but may not
  reinterpret the legal ordering as a train reversal.
- Interval `#2` (`008768→008764`) and part 1 indices `8…16` are the immediate
  east guard whenever the 南堀端 display midpoint changes.

### 大手町線: west horizontal owner

- Interval `#0`, station indices `0→1` (`008761` 西堀端 → `008760` 大手町駅前),
  maps to part 0 indices `0…3` and `segments[0][2][0…3]`.
- Interval `#1`, station indices `1→2` (`008760` 大手町駅前 → `008758`
  JR松山駅前), maps to part indices `3…10` and `segments[1][2][0…6]`.
- Interval `#2` (`008758→008751`) begins at part index 10 and is the immediate
  guard if the JR松山駅前 midpoint changes. Interval `#3` ends at shared
  `008739` 古町 and is the far-end guard.

The shared west rail is therefore owned by 城南 `#0/#1` and 大手町 `#0/#1`,
with 城南 `#2` and 大手町 `#2` as endpoint-adjacent guards. Moving only one
stroke would leave a visible seam at 西堀端, 大手町駅前, or JR松山駅前.

### 本町線 and 花園線: distinct-arm endpoint owners

- 本町線 interval `#3`, station indices `3→4` (`008748` 本町三丁目 → `008756`
  本町一丁目), maps to part 0 indices `9…12` and
  `segments[3][2][0…2]`. Its endpoint is the north–south Hommachi arm. It must
  not snap to `008761` 西堀端 or to the non-station Jōnan junction vertex.
- 花園線 interval `#0`, station indices `0→1` (`008772` 松山市駅 → `008768`
  南堀端), owns part 0 indices `0…12` and `segments[0][2][0…12]`. It is the
  required south-arm owner/guard for any 南堀端 display midpoint.

## Station-frame midpoint plan

Future coordinates remain **TBD from focused native raw evidence**. The owner
candidate should use line-scoped `displayStationCoordinates` and
`displayIntervalCoordinates`, leaving `stations`, `segments`, station IDs,
kilometres, ordering, and physical topology unchanged.

| Station identity | Current owners / exact source indices | Evidence and constraint |
|---|---|---|
| `008756` 本町一丁目 | 城南 station 0 / part 1 index 0; 本町 station 4 / part 0 index 12 | Acquire the own north–south stop-frame midpoint. Keep distinct from `008761`; both legal rows may share a reviewed display midpoint only if the raw frame supports it. |
| `008761` 西堀端 | 城南 station 1 / part 0 index 2; 大手町 station 0 / part 0 index 0 | Acquire the own west horizontal stop-frame midpoint. Preserve the junction vertex separately and use the same reviewed frame only where both line renderings depict this stop face. |
| `008760` 大手町駅前 | 大手町 station 1 / part index 3 | Acquire the longitudinal midpoint on the same horizontal tram guide; check both adjacent intervals `#0/#1`. |
| `008758` JR松山駅前 | 大手町 station 2 / part index 10 | Acquire the own stop-frame midpoint at the horizontal-to-north turn; check `#1/#2`. |
| `008768` 南堀端 | 城南 station 2 / part 1 index 8; 花園 station 1 / part 0 index 12 | Acquire approach-specific station-frame evidence before sharing a display point. Check 城南 `#1/#2` and 花園 `#0`; do not force a cross-line turn. |
| `008772` 松山市駅 | 花園 station 0 / part index 0 | Keep distinct from private-rail `008773` 松山市; acquire the tram frame midpoint only. |

The current `nishihoribata-z18-before` extraction is not sufficient to fill this
table: it reports `partial_image_support`, no platform candidates, 0.4942 m/px,
and only partial rail-glyph candidates. It supports the presence and direction
of the west and north–south arms, while the focused Main pair supplies the
concrete approximate offsets (horizontal about 15 m north; stem about 6 m west).
The April–May 2010 regional aerial supports rail-arm identity only and is not
current station-frame precision evidence.

## Adjacent complete acceptance scope

Any change to one legal row changes that row's whole display derivation and
native dependency. The bounded acceptance scope is therefore the full six-line
set: **29 intervals / 70 native viewpoints**.

| Line | Complete intervals | Planned viewpoints |
|---|---:|---:|
| 城南線 | `#0–#10` | 27 |
| 城北線 | `#0–#7` | 19 |
| 大手町線 | `#0–#3` | 10 |
| 本町線 | `#0–#3` | 9 |
| 花園線 | `#0` | 3 |
| 連絡線 | `#0` | 2 |

Required shared-endpoint checks within that scope are:

- `008736`: 城北 `#0` and 連絡 `#0`;
- `008742`: 城南 `#7/#8` and 連絡 `#0`;
- `008739`: 城北 `#7` and 大手町 `#3`;
- `008719`: 城北 `#5/#6` and 本町 `#0`, retaining their current line-specific
  stop-face distinction;
- `008756`, `008761`, and `008768`: the direct west/south owner intervals listed
  above.

`008739` is also used by private-rail 高浜線. Keep that source and display
geometry immutable. If an implementation instead changes a global station
coordinate, 高浜線 `#1/#2` must be added as explicit guards; a line-scoped
display repair avoids that expansion.

## Direction and topology invariants

- Preserve the six legal station sequences and all 29 source intervals.
- Preserve the Jōnan two-part representation and the direction of every source
  interval; the display may omit the visual backtrack from its through part but
  may not encode a reverse-U as an operational movement.
- Do not add physical-registry joins. Shared station IDs authorize endpoint
  consistency checks, not through-running between legal records.
- Do not merge the two 本町六丁目 stop faces, 本町一丁目 with 西堀端, or tram
  松山市駅 with private-rail 松山市.
- Fit each route to its own Apple tram guide/station frame and keep roads,
  labels, moat edges, and private-rail geometry out of the trace.

## Current input custody

- `app/public/rail/jp-2025.json`:
  `a128bf177b2a13b0dd27e9520c04bc96691a0972bfdbdb9bfb939d85d2391942`
- `app/public/rail/display-lanes.json`:
  `63a39f601f6e63cf068123c0298d3912ecc58a0cbed3112478b1cc862235d7e4`
- `app/public/rail-network.js`:
  `78ba4d226dec60e0b091ad37607dae8f8580cf2f3a28c89d84155aac45de9c9d`

These hashes describe the concurrently current workspace inputs at review time;
they are evidence anchors, not a freeze or permission to overwrite later user
changes.
