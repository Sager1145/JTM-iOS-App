# jtm-display-network-v2 — chunked, indexed, fully local display database

Status: design approved by the orchestrator (Fable), 2026-09-10. Implementers follow this
exactly; anything not specified here keeps the v1 behaviour of
`app/scripts/railway/build-display-network.py` and `ios/RailMap/RailDisplayNetwork.swift`.

## 0. What is being rebuilt, and what is not

- REBUILT: the display database the iOS map reads — the derivative produced by
  `build-display-network.py` into the app bundle directory `rail-display-network/`.
  Today (v1, `jtm-display-network-v1`) it is `manifest.json` + one whole JSON file per region.
- NOT rebuilt: the seven canonical `compact-v1` packages `app/public/rail/{jp,tw,hk,mo,kr,us,ca}-2025.json`.
  They stay the source of truth. jp/tw/hk/mo/kr builders live in the web repo; us/ca in this repo.
  The skill's preflight (`audit_jtm_packages.py`) is run on them before and after as the gate.
- NOT changed: the Web client (`rail-network.js` reads compact-v1 + display-lanes.json in a worker).
- Invariant kept from v1: geometry is NOT cut into tiles. The chunk unit is a whole railway line
  (all its fragments/chains and its station rows). Viewport culling stays in the renderer.

## 1. Output layout (bundle directory `rail-display-network/`)

```
manifest.json                 # format "jtm-display-network-v2"; all line headers, no geometry
{region}.display.bin          # concatenated per-line JSON documents (UTF-8); byte ranges in manifest
{region}.stations.json        # station identity table for the region (search/disambiguation)
display-network-report.json   # build report + identity ledger (NOT copied into the bundle)
```
`{region}` ∈ jp, tw, hk, mo, kr, us, ca. Regions absent from `--rail-dir` are omitted (as v1).

## 2. manifest.json

```jsonc
{
  "format": "jtm-display-network-v2",
  "generatedAt": "<ISO-8601>",
  "packageSHA256": { "jp": "<sha256 of jp-2025.json>", ... },          // as v1
  "inputSHA256":   { "display-lanes.json": "...", "shared-corridors.json": "...",
                     "na-render-groups.json": "...", "jp-render-groups.json": "...", ... },
  "regions": [
    {
      "region": "jp",
      "file": "jp.display.bin", "bytes": 123, "sha256": "<sha256 of the whole blob>",
      "stationsFile": "jp.stations.json", "stationsBytes": 123, "stationsSHA256": "...",
      "minZoomMapLibre": 3,                                              // as v1
      "minLon": .., "minLat": .., "maxLon": .., "maxLat": ..,          // as v1
      "families": { "<groupId>": { "color": "#..", "colorDark": "#.." } },  // moved here from the v1 region file
      "lineCount": 655, "stationCount": 9041, "vertexCount": 123456,
      "loadStrategy": "whole" | "lines",   // "whole" when fullBytes <= 1.5 MB, else "lines" (§7)
      "fullBytes": 123, "overviewBytes": 0      // fullBytes + overviewBytes == bytes
    }
  ],
  "lines": {
    "<lineId>": {
      // every v1 field, unchanged: id, region, name, nameRoma, operator, operatorLogo, kind, rank,
      // color, colorDark, renderGroup, minZoomMapLibre, lodMinZoomMapLibre, visibilityLengthKm, logo, ...
      "bounds": { "minLon": .., "minLat": .., "maxLon": .., "maxLat": .. },   // over the line's final display vertices
      "chunk":  { "offset": 0, "length": 4567, "sha256": "<sha256 of the chunk bytes>" },
      "overview": { "offset": 9000, "length": 800, "sha256": "...", "vertexCount": 40 },  // only on a "lines" region's qualifying lines (§3)
      "displayLabel": "本線",                    // §5.2 — unique within the region
      "nameKey": "<normalised name, §5.0>",
      "operatorShort": "...",                     // when the package has it, else operator
      "stationCount": 12, "vertexCount": 345, "chainCount": 1,
      "dependsOn": ["<lineId>", ...]                          // other lines in this region this line's `follows` rows reference
    }
  }
}
```
`lines[id].chunk` is a byte range inside `regions[].file` for that line's region.
Chunks are laid out in manifest `lines` order for the region, which is the region's own package
line order (the order `package["lines"]` lists them, matching v1's per-region fragment order).

## 3. `{region}.display.bin` — per-line chunk documents

Each chunk is one UTF-8 JSON document, byte-exact at `[offset, offset+length)`. No framing bytes,
no separators; `length` is authoritative. Document schema = the v1 region file restricted to one
line, so the existing Swift `RailDisplayNetworkFile` decoder decodes a chunk unchanged:

```jsonc
{
  "format": "jtm-display-network-v2",
  "region": "jp",
  "lineId": "<lineId>",
  "detail": "full" | "overview",  // "overview" only on an overview chunk (§7); a full chunk carries "full"
  "families": {},                 // always empty in v2 chunks; families live in manifest.regions[]
  "lines": [ <LineFragment>... ], // exactly the v1 fragment rows for this line (lineKey == lineId)
  "stations": [ <Station>... ]    // exactly the v1 station rows for this line (lineKey == lineId)
}
```
Fragment and station row fields are byte-for-byte the v1 fields (`lineKey, lane, parts, continuous,
chain, joinPrevious, laneRows, totalMetres, follows, withheld, familyWindows` / `id, lineKey,
stationCode, name, lon, lat, nameRoma, minZoomMapLibre, lodMinZoomMapLibre, isTerminal, showsLabel,
groupLineKeys, lane, bearing, slot`). Stations that are shared by several lines appear in every
line's chunk exactly as they appear per line in v1 (v1 already carries one row per (line, station)).
Row keys are region-qualified exactly as in v1: every fragment's and station's `lineKey` is
`"{region}|{lineId}"` (the manifest `lines` dictionary is keyed the same way), while the chunk
header `lineId` and the manifest line's `id` carry the bare line id. `bounds` is emitted for every
line and covers its fragment vertices and its station rows, so a line whose display intervals are
all withheld still has a load rect.

JSON is emitted with `ensure_ascii=False`, `separators=(",", ":")`, and coordinates rounded exactly
as v1 rounds them (do not change precision).

Blob layout: full chunks are laid out first, contiguous from offset 0 through `fullBytes`; for a
`"lines"`-strategy region, overview chunks are appended contiguously after them, from `fullBytes`
through the end of the blob (`bytes`). An overview document is the full document simplified per §7
(Douglas–Peucker 50 m, `laneRows`/`follows`/`lane` dropped, `withheld`/`familyWindows` rescaled to
the new `totalMetres`, `stations` filtered to `minZoomMapLibre <= 6`).

## 4. `{region}.stations.json` — station identity table

```jsonc
{
  "format": "jtm-display-stations-v2",
  "region": "jp",
  "stations": [
    {
      "key": "jp:003700",            // "{region}:{stationId}" — globally unique across regions
      "id": "003700",
      "name": "新宿",
      "nameKey": "新宿",              // §5.0
      "nameRoma": "Shinjuku",
      "lon": 139.7004, "lat": 35.6898, // representative anchor = arithmetic mean of member rows
      "spreadMetres": 549.0,          // max great-circle distance between any two member rows
      "lines": ["jp-京王電鉄-京王線", ...],   // sorted, every line whose station rows carry this id
      "operators": ["京王電鉄", ...],           // sorted distinct
      "hubId": "<display-hubs.json hub id>" | null,
      "displayLabel": "新宿",         // §5.1 — unique within the region
      "homonymGroup": "<nameKey>" | null,   // set when ≥2 distinct ids share nameKey in the region
      "idCollision": false            // true when spreadMetres > 300
    }
  ],
  "homonymGroups": {
    "<nameKey>": { "keys": ["jp:000123", "jp:004567"], "maxSeparationKm": 1581.2 }
  },
  "idCollisions": [
    { "key": "jp:003700", "spreadMetres": 549.0,
      "members": [ { "lineId": "...", "lon": .., "lat": .. }, ... ] }
  ],
  "similarNameGroups": [
    { "core": "浦和", "keys": ["jp:...", ...], "names": ["浦和","東浦和","南浦和"] }
  ]
}
```
Rules:
- Identity is the package's station id, never the name. Two rows with the same id are the same
  station; two rows with different ids are different stations even when the name is identical.
- `similarNameGroups` is review data only. Similar names are NEVER merged and never share a key.
- `idCollisions` (same id, rows > 300 m apart) are reported, not repaired here — repair belongs to
  the owning builder (NA: `na-station-id-repairs.json`; jp/kr: web repo). Legit transfer-hub spread
  (新宿 549 m) is expected; the report lets a reviewer tell those from real collisions.

## 5. Identity rules

### 5.0 nameKey
`NFKC` normalise → strip all whitespace (ASCII and full-width) → `ヶ`→`ケ`, `ヵ`→`カ` → for Latin
regions (us, ca) case-fold and strip a trailing " Station" / " station" token → strip trailing "駅"
/ "站" / "역" only if the name is longer than that suffix. Nothing else.

### 5.1 Station displayLabel (unique per region)
1. If `nameKey` is unique among the region's distinct station ids → `name`.
2. Else if the operators sets differ → `name（{operatorShort of the first line}）` for jp/tw/hk/mo/kr,
   `name ({operator})` for us/ca.
3. Else if the first line names differ → `name（{first line name}）` / `name ({first line name})`.
4. Else → `name（{lat:.2f},{lon:.2f}）` / `name ({lat:.2f},{lon:.2f})`.
5. If rule 4 still collides (directional tram stops of one line) → `name（{stationId}）` / `name ({stationId})`.
"first line" = the lowest-`rank`, then lexicographically smallest, line id in `lines`.
Assert uniqueness of displayLabel within a region after assignment; on failure fall to rule 4.

### 5.2 Line displayLabel (unique per region)
1. If `nameKey(name)` is unique among the region's lines → `name`.
2. Else if `operator` is unique among the same-name lines → `{operatorShort} {name}` (CJK: no
   space, `{operatorShort}{name}`).
3. Else → `{operatorShort}{name}（{firstStation}–{lastStation}）` using the line's first and last
   station names in package order.
Assert uniqueness per region; on failure append the line id in parentheses.

## 6. display-network-report.json (build output, not bundled)

```jsonc
{ "format": "jtm-display-network-report-v2", "generatedAt": "...",
  "regions": { "jp": { "lines": 655, "stations": 9041, "vertices": .., "blobBytes": .., "manifestBytes": ..,
                       "largestChunkBytes": .., "largestChunkLineId": "...",
                       "homonymGroups": 395, "idCollisions": 17, "similarNameGroups": 517,
                       "sameNameLines": 62, "danglingRenderGroupIds": [...] } },
  "timingsSeconds": { "jp": 1.23, ... } }
```

## 7. iOS reading contract (for the Swift change spec)

- Launch: decode `manifest.json` only (no geometry). Build the per-line header index and the
  per-region records exactly as v1 `records(...)` does, now with `bounds` per line.
- Drawing: given the padded camera rect + camera zoom, the set of lines to load =
  `{ line | line.region intersects, line.bounds ∩ rect ≠ ∅, line.nativeMinZoomMapLibre ≤ zoom + margin }`
  minus lines already loaded. Load each needed chunk by reading exactly `chunk.length` bytes at
  `chunk.offset` from the region blob (memory-mapped `Data(contentsOf:options:.alwaysMapped)` sliced,
  or `FileHandle` seek+read) and decoding it with the existing `RailDisplayNetworkFile` decoder.
  Verify `chunk.sha256` in DEBUG builds only.
- Loaded lines are kept (no eviction) exactly as v1 keeps regions; a later LRU is out of scope.
- `families` come from `manifest.regions[].families`.

### Dynamic loading (v2.1)

A request is served in waves, not one undifferentiated batch: an **urgent**
wave for lines that intersect the un-padded visible rect at the current
zoom, a **padded** wave for the rest of the build rect (v1's original set),
and — once both are satisfied — an idle **prefetch** wave one more
build-rect-half ring outward, run at `.utility` priority so it never
competes with a camera-driven request. A camera move preempts a prefetch
batch in flight (it never waits behind idle work); it still waits behind an
urgent or padded batch, as v1 did. Prefetched lines do not count against
`displayAttempts`, since a cancelled prefetch was never a failure.

Residency is now budgeted: a `residentByteBudget` (16 MB of chunk bytes; the seven regions total 22 MB, Japan alone 12 MB)
caps what a completed batch may leave loaded. Exceeding it runs a
least-recently-requested eviction over lines the current request does not
need, skipping any line a surviving line's `dependsOn` still names, before
the batch's one `publishDisplayNetwork()`. The 定位 (fit-to-network) frame
does not depend on residency: `networkExtent` is the union of the manifest extents of the
countries the last camera request touched (the country nearest the camera alone when the
union would span more than half the world, i.e. Japan and North America together), and an
open-sea request keeps the previous frame.
- Overview backbones (`NetworkVisibilityPolicy.isOverviewBackbone`): rank 0, Korean rank-1 고속선, Japanese
  lines named 新幹線, and every line of an operator listed in `overviewOperatorsByRegion` (us: Amtrak;
  ca: Amtrak, Via Rail Canada) get the −30 sentinel, so they load and draw at the smallest zoom.
- Station identity tables are loaded on demand only (search / disambiguation), never for drawing.

### Size-aware loading

A region whose full-chunk blob is at or under 1.5 MB (`loadStrategy == "whole"`; today tw, hk, mo,
kr, ca) loads all of its lines in one batch, the same as v1. A larger region (`loadStrategy ==
"lines"`; today jp, us) instead serves an `overview` chunk — for every line with `rank == 0`,
`minZoomMapLibre <= 6`, or operator Amtrak/Via Rail Canada — at app zoom ≤ 7, then upgrades to the
line's full chunk above that zoom; a resident full chunk is never downgraded back to overview.
Measured: jp's 432 overview-qualifying lines shrink from 11.0 MB to 1.3 MB; us's 295
overview-qualifying lines shrink from 2.6 MB to 0.59 MB.
- All existing `verify.sh` textual contracts must keep passing: 4× `AppleMapDatum.display` in
  `RailNetworkStore.swift`, headers-only `CompactPackage.Headers.load` index string, no direct
  `CompactPackage.load(contentsOf:` in app code.

## 8. Validation

- `python3 -m unittest discover tests` in `app/scripts/railway` (tests updated for v2).
- New builder self-check: after writing, re-open every region blob, decode every chunk via its
  manifest range, and assert `lineId`, fragment count, station count and sha256 match.
- `SCRATCH=/tmp/jtm-rail-core ./ios/verify.sh --core`, then the full `./ios/verify.sh`.
- `./ios/copy-rail-packages.sh <tmpdir>` produces the v2 directory.
- Measure and report: manifest decode time; bytes decoded for a Tokyo city viewport vs the v1
  whole-region file; total bundle size v1 vs v2.
