# JTM repository contracts

These paths describe the current standalone JTM iOS repository, which retains the JavaScript WebUI as the reference implementation. Discover files before acting because the original `Japan-Train-Map` repository may contain additional builders and validators.

## Canonical data and clients

| Concern | Current location | Contract |
|---|---|---|
| Compact railway packages | `app/public/rail/{jp,tw,hk,mo}-2025.json` | `compact-v1`, canonical WGS84 `[lon, lat]` |
| Package provenance | `app/public/rail/*-2025.sources.md` | Sources, rebuild method, limitations, licence |
| Route graph data | `app/data/rail-sections*.json` | Country-suffixed outside Japan |
| Station data | `app/data/stations*.json` | Stable operator/region identifiers and groups |
| Readings | `app/data/station-readings*.json` | Country-scoped names/readings |
| Sample stores | `app/data/train-store*.json` | Cross-client import, solve, and rendering fixtures |
| Web geometry | `app/public/rail-network.js` | Display parts, station anchoring, branches, grooming, lanes |
| Web final style | `app/public/railmap-style.js` | GeoJSON sources and simplification tolerance |
| Swift portable logic | `ios/RailKit/Sources/RailCore/` | Foundation-only; checked against JS fixtures |
| Native package loader | `ios/RailMap/RailNetworkStore.swift` | Decodes every package and creates map subjects |
| Native final renderer | `ios/RailMap/RailMapView.swift` | MapKit LOD, clipping, simplification, annotations |
| Native style contract | `ios/RailMap/RailStyle.swift` | Must agree with Web simplification budget |
| Apple presentation datum | `ios/RailMap/AppleMapDatum.swift` | Display-boundary conversion only; inspect current country set |
| Ridden route dual coordinates | `ios/RailMap/RiddenRouteStore.swift` | Display coordinates plus canonical `sourceCoordinates` |
| iOS resource copy | `ios/copy-rail-packages.sh` | Copies Web packages/data into the app bundle; no second committed package copy |
| Cross-platform fixtures | `app/scripts/build/build-port-fixtures.mjs`, `port-fixtures/` | JS answers consumed by Swift parity tests |
| Main gate | `ios/verify.sh` | JS fixture check, Swift tests/contracts, app build |

## Ownership rules

- Determine whether a package is generated and find its builder, raw evidence, overrides, and source notes before editing. In the original repository these commonly live under `app/scripts/railway/`, `app/data/raw/railway/`, and `app/scripts/validation/`; the standalone repository may retain only a subset.
- Change the earliest reproducible owning layer. If only the generated JSON exists, document the limitation before a surgical edit and add a repeatable override or validator where practical.
- Never create a second iOS copy of a railway package. `ios/copy-rail-packages.sh` intentionally copies the Web package at build time.
- When shared JavaScript logic changes, rebuild `port-fixtures` and review the semantic diff before accepting Swift changes.
- `RailCore` and `RailPresentation` remain platform-free. MapKit- or SwiftUI-specific fixes belong in `ios/RailMap/` unless the behavior is genuinely portable and backed by fixtures.

## Cross-platform invariants

1. Package coordinates stay WGS84 and longitude-first.
2. Web and Swift decode the same `compact-v1` structures and produce equivalent pre-render display parts.
3. Web and iOS final simplifiers share the declared tolerance, including complete-network and ridden-route paths.
4. Any Apple datum conversion happens exactly once at the MapKit boundary and covers lines, stations, rides, and playback without changing canonical caches/statistics.
5. Station anchors, line identities, branches, loops, `extraSegments`, lanes, and source attribution survive regeneration.
6. Country-specific IDs are not normalized into Japanese N02 semantics.

## Defect routing

| Symptom | Inspect first | Do not assume |
|---|---|---|
| Same wrong geometry in both clients | package/builder/source | renderer bug |
| Web correct, iOS locally straight or offset | final simplifier, LOD, clipping, datum boundary | bad package |
| Route cannot solve but network draws | stations, rail sections, IDs, route graph | display geometry is sufficient |
| Station dot off its own line | package anchor, display anchoring, lane/StopGroup model | moving the dot alone is safe |
| Branch jumps or doubles back | station order, segment orientation, branch lead-in, direction merge | generic smoothing will fix topology |
| Line missing despite covered corridor | operator/line identity and membership audit | overlap means complete inventory |
| Only Apple basemap disagrees uniformly | multi-point datum audit | apply a global coordinate shift |
| Low zoom wrong, high zoom right | simplification and LOD budgets | source coordinates changed with zoom |
