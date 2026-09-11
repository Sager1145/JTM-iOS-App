# 0008: Chunked, indexed display network database

- Status: Accepted
- Date: 2026-09-10
- Decision owners: Project maintainers
- Supersedes: None (evolves the `rail-display-network` derivative of 0006)

## Context

The iOS map draws from a display derivative built at Xcode build time by
`app/scripts/railway/build-display-network.py`. Version 1 wrote one whole JSON
file per region (Japan 12 MB), decoded in full the first time the camera
touched that region. A Tokyo city view therefore decoded every Japanese line
although it draws about one line in nine. The derivative also carried no
station or line identity beyond the raw rows: same-name stations (Japan has
several hundred homonym groups more than 1 km apart) and same-name lines
(本線 ×11, Green Line ×5) were distinguishable only by id.

The seven canonical `compact-v1` packages stay the source of truth. Their
builders for jp/tw/hk/mo/kr live in the web repository and had just completed a
per-line rebuild; regenerating them from raw sources is out of scope here.

## Decision

Rebuild the display derivative as `jtm-display-network-v2`
(`docs/DISPLAY_NETWORK_V2_2026-09-10.md`):

- `manifest.json` holds every line's header, bounds, `dependsOn` (canonical
  lines named by its `follows`) and a byte range. No geometry.
- `{region}.display.bin` concatenates one independently decodable JSON chunk per
  railway line, in package order. Geometry is never tiled; the chunk unit is a
  whole line, so continuous strokes stay continuous.
- `{region}.stations.json` is a station identity table keyed `{region}:{id}`
  with normalised names, per-region unique display labels, homonym groups,
  id-spread collisions and similar-name review groups. Identity is the package
  id, never the name; similar names are never merged.
- The iOS store memory-maps a region blob once, loads only the lines whose
  bounds intersect the padded build rect at a drawable zoom plus the transitive
  `dependsOn` closure, keeps loaded lines under a budgeted LRU rather than
  resident forever, and publishes once per completed batch.

## Consequences

- A city view decodes the lines on screen (Tokyo: 75 lines, 1.7 MB of 12.2 MB)
  instead of a country. Launch decodes only the manifest.
- Runtime whole-file digests are gone; chunk sha256 is checked in DEBUG builds,
  release corruption is caught by decode and validation.
- `activeRegionCount`/`activeNetworkBytes` now count regions with a resident
  line and resident chunk bytes; a 16 MB budget (chunk bytes; the seven regions total 22 MB, Japan alone 12 MB) evicts the
  least-recently-requested lines a batch does not need, rather than keeping
  every loaded line resident forever.
- The 定位 frame derives from `networkExtent` — the union of the manifest
  extents of the countries under the camera's last request (the nearest one
  alone when they straddle the Pacific) — rather than from resident lines, so
  eviction and not-yet-arrived chunks cannot shrink the frame.
- Overview backbones — lines eligible at every zoom down to the globe — are
  rank 0 (every Shinkansen, THSR, Acela, Brightline), Korea's rank-1 고속선,
  and by operator table every Amtrak and VIA Rail line in `us`/`ca`
  (`NetworkVisibilityPolicy.overviewOperatorsByRegion`); the loader's region
  and line gates derive from the same policy, so those lines are also always
  loaded wherever their country is on screen.
- The identity table is data only; no search UI consumes it yet.
- The builder runs about eight seconds longer (identity tables, digests).
- Large regions (jp, us) also emit a simplified "overview" chunk per qualifying line, served at
  app zoom ≤ 7 and upgraded to the full chunk above that; jp's 432 overview lines shrink from
  11.0 MB to 1.3 MB, us's 295 from 2.6 MB to 0.59 MB, while small regions keep loading whole.

## Alternatives considered

- Web Mercator tiles: rejected in 2026-09-01 in favour of continuous strokes
  with viewport culling; tiling would reintroduce seams.
- One file per line: thousands of bundle resources slow copy and install; a
  blob with an offset index reads the same bytes.
- SQLite: a relational mirror already exists (`app/data/rail.db`) and nothing
  reads it; the map needs sequential geometry rows, not joins.
- Rebuilding the canonical packages from raw sources: different repository,
  just completed there, and not what the functional requirements need.

## Validation

- `cd app/scripts/railway && python3 -m unittest discover tests`
- `cd ios/RailKit && swift test`
- `./ios/verify.sh --core`, then `./ios/verify.sh`
- `./ios/copy-rail-packages.sh <tmpdir>` yields the v2 directory
- Skill preflight on the canonical packages before and after must match.
