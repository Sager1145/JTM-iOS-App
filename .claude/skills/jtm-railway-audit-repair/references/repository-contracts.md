# JTM repository contracts

Paths below are the standalone JTM iOS repository, which keeps the JavaScript WebUI as the reference implementation. Discover files before acting: the older `Japan-Train-Map` repository holds builders and validators that were not carried over, and this tree keeps gaining regions.

Seven regions ship today: `jp`, `tw`, `hk`, `mo`, `kr`, `us`, `ca`.

## Canonical data and clients

| Concern | Location | Contract |
|---|---|---|
| Compact railway packages | `app/public/rail/{jp,tw,hk,mo,kr,us,ca}-2025.json` | `compact-v1`, canonical WGS84 `[lon, lat]` |
| Package provenance | `app/public/rail/*-2025.sources.md` | Sources, rebuild method, limitations, licence |
| North America audit ledgers | `app/public/rail/{us,ca,na}-2025.audit.*`, `na-2025-line-review.*`, `na-2025.acceptance.md` | Per-line review state for the newest packages |
| Route graph data | `app/data/rail-sections*.json` | Country-suffixed outside Japan (`-tw`, `-hk`, `-mo`, `-kr`, `-us`, `-ca`) |
| Station data | `app/data/stations*.json` | Stable operator/region identifiers and groups |
| Readings | `app/data/station-readings*.json` | Country-scoped names/readings |
| Sample stores | `app/data/train-store*.json` | Cross-client import, solve and rendering fixtures |
| Precomputed sample parts | `app/data/sample-data*/` | Built by `npm run precompute*`; `jp/tw/hk/mo/kr` only |
| Web geometry | `app/public/rail-network.js` | Display parts, station anchoring, branches, grooming, lanes |
| Web final style | `app/public/railmap-style.js` | GeoJSON sources; `SEGMENT_SIMPLIFY_TOLERANCE_PX` |
| Swift portable logic | `ios/RailKit/Sources/RailCore/`, `RailPresentation/` | Foundation-only; checked against JS fixtures |
| Native package loader | `ios/RailMap/RailNetworkStore.swift` | Decodes every package, creates map subjects, applies the datum |
| Native final renderer | `ios/RailMap/RailMapView.swift` | MapKit LOD, clipping, simplification, annotations |
| Native style contract | `ios/RailMap/RailStyle.swift` | `simplifyTolerance` must equal the Web value |
| Apple presentation datum | `ios/RailMap/AppleMapDatum.swift` | Display boundary only; scope is `["tw", "hk", "mo", "kr"]` |
| Ridden route dual coordinates | `ios/RailMap/RiddenRouteStore.swift` | Display coordinates plus canonical `sourceCoordinates` |
| Region metadata | `ios/RailMap/RegionCatalog.swift` | One `case` per region, camera boxes, load tiers |
| iOS resource copy | `ios/copy-rail-packages.sh` | Copies Web packages/data into the bundle for `jp tw hk mo kr us ca`; no second committed copy |
| Cross-platform fixtures | `app/scripts/build/build-port-fixtures.mjs`, `port-fixtures/` | JS answers consumed by Swift parity tests |
| Main gate | `ios/verify.sh` | Fixture check, Swift build/tests, textual contracts, app build |
| Derived query mirror | `app/scripts/build/build-rail-database.mjs` → `app/data/rail.db` | Read-only join of packages/readings/sections; useful for audit queries, nothing in the app reads it |

## Builders and validators present in this tree

Only North America ships its pipeline here. `app/scripts/railway/` holds `build-north-america-rail-package.py`, the `download-*` fetchers (official networks, GTFS, NARN, OSM cross-check), the `normalize-*-official-networks.py` regional normalizers, `audit-na-package.py`, `audit-north-america-packages.py`, `crosscheck-na-stations.py`, `report-na-coverage.py`, `make-na-line-review.py`, the shared `lib/na_*.py` modules, the feed registry `na-feeds.json`, and `tests/test_*.py`.

`app/scripts/validation/` retains only `audit-japan-sample-branding.mjs`. The Japan, Taiwan, Hong Kong, Macao and Korea builders and the topology/alignment validators live in the older `Japan-Train-Map` repository — for those regions, treat the published JSON plus its `.sources.md` as the artefact you have, and say so in the report instead of implying a rebuild is available here.

`app/package.json` still lists scripts whose files were not carried over: `npm run lint` (`check-source.mjs`) fails with `MODULE_NOT_FOUND`, and `audit:apple-tiles:jp`, `rebuild:railway:jp` and the `generate:*` sample scripts are likewise missing. `npm test` runs `node --test` against a tree with no JS test files — a vacuous pass. Do not cite any of them as evidence.

## Ownership rules

- Determine whether a package is generated and find its builder, raw evidence, overrides and source notes before editing anything.
- Change the earliest reproducible owning layer. If only the generated JSON exists, document that limitation before a surgical edit, and leave a repeatable override or check behind.
- Never create a second iOS copy of a railway package; `ios/copy-rail-packages.sh` copies the Web package at build time on purpose.
- When shared JavaScript logic changes, regenerate `port-fixtures/` and review the semantic diff before touching Swift.
- `RailCore` and `RailPresentation` stay platform-free. MapKit- and SwiftUI-specific fixes belong in `ios/RailMap/`.
- Country-specific station identifiers are not normalized into Japanese N02 semantics.

## Invariants `ios/verify.sh` enforces as text

These are grep contracts pinned to file, function and variable names. They fail on a rename or a move even when behaviour is unchanged — grep `ios/verify.sh` for a symbol before relocating it, and change the contract deliberately rather than deleting it.

1. `SEGMENT_SIMPLIFY_TOLERANCE_PX` in `railmap-style.js` equals `simplifyTolerance` in `RailStyle.swift` (both `0.0625`).
2. `RailMapView` derives its epsilon from `RailStyle.simplifyTolerance`, and exactly two renderer simplifiers share it — the complete network and ridden routes.
3. `RailNetworkStore` calls `AppleMapDatum.display` exactly twice (network lines and network stations); `RiddenRouteStore` routes ridden coordinates through it; the route cache, ridden-line statistics and `MileageStatisticsStore` keep `sourceCoordinates` in WGS84.
4. `AppleMapDatum.gcj02Countries` is exactly `["tw", "hk", "mo", "kr"]` — North America is deliberately excluded because Apple's basemap there is WGS84.
5. `RailCore` imports nothing but Foundation; `RailPresentation` nothing but Foundation and RailCore.
6. The map's annotation classes are named only by `RailMapAnnotations.swift`, `RailMapView.swift` and `MapPlaybackLayer.swift`.
7. Apple Maps station links are assembled only in `StationPlaceLink.swift`.
8. `build-port-fixtures.mjs --check` regenerates every fixture in memory and fails if any answer moved.

## Cross-platform invariants

1. Package coordinates stay WGS84 and longitude-first.
2. Web and Swift decode the same `compact-v1` structures and produce equivalent pre-render display parts.
3. Web and iOS final simplifiers share the declared tolerance, on both the complete-network and ridden-route paths.
4. Any Apple datum conversion happens once, at the MapKit boundary, across lines, stations, rides and playback — and never reaches caches or statistics.
5. Station anchors, line identities, branches, loops, `extraSegments`, lanes and source attribution survive regeneration.

## Defect routing

| Symptom | Inspect first | Do not assume |
|---|---|---|
| Same wrong geometry in both clients | package / builder / source | renderer bug |
| Web correct, iOS locally straight or offset | final simplifier, LOD, clipping, datum boundary | bad package |
| Route cannot solve but network draws | stations, rail sections, IDs, route graph | display geometry is enough |
| Station dot off its own line | package anchor, display anchoring, lane/StopGroup model | moving the dot alone is safe |
| Branch jumps or doubles back | station order, segment orientation, branch lead-in, direction merge | smoothing will fix topology |
| Line missing though the corridor is covered | operator/line identity and membership audit | overlap means complete inventory |
| Only the Apple basemap disagrees, uniformly | multi-point datum audit | apply a global coordinate shift |
| Low zoom wrong, high zoom right | simplification and LOD budgets | source coordinates changed with zoom |
| Interval drawn as one straight line | source coverage gap in the builder, then `km` vs geometry | the renderer dropped the vertices |
| Chord on a **ridden route** only, network fine | `RouteGraph.Edge` (length without geometry), then endpoint snapping onto a platform point | the package is at fault |
| One interval hugely longer than its stations are apart | per-station projection onto a round-trip shape | a real detour, before checking the projection |
| Same railway drawn twice | two feeds building it, deduped by operator string | a lanes/corridor bug |
