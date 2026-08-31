# Regional evidence guide

Read only the sections for the regions in scope. Counts and URLs here are leads from the repository's own `*.sources.md`; verify current operational facts against primary sources when recency matters.

## Japan (`jp`)

- Primary inventory and measured geometry: MLIT National Land Numerical Information railway data (N02). Confirm the dataset year and effective date in `jp-2025.sources.md`.
- Identity key is operator plus railway plus station membership. Coincident geometry must never suppress a missing identity.
- Station codes are six-digit N02-style codes in the journey/store compatibility layer. Keep regional identity and aliases separate from station-complex grouping.
- Audit discontinued, suspended, freight and non-passenger geometry explicitly. Absence from Apple Transit is not evidence for deleting an N02 railway.
- Treat N02 field anomalies as source conflicts, not new operators or lines: quarantine with an evidence-backed override.
- High-risk shapes: long JR lines split into strokes (`…-2`, `-p1` suffixes), urban parallel corridors, Shinkansen overlaps, loops, terminal reversals, branch rejoins, multi-line station throats.
- When cross-checking against OSM/OpenRailwayMap, exclude yard, siding, spur and crossover track unless the audited subject uses them; prefer `usage=main|branch` and document exceptions.

## Taiwan (`tw`)

- Primary sources: TDX rail APIs and official NLSC railway/metro/light-rail centreline and station datasets listed in `tw-2025.sources.md`; operator sources for openings, station order and service status.
- Preserve TDX/operator identities such as `StationUID`. Do not derive a country from a fragile operator prefix when the country-scoped station dataset can resolve it.
- Keep separate platform families for TRA, THSR, metro and airport rail even where they share a named complex.
- The Sanying Line is the standing reminder to compare package inventory against the currently operating network, not against the package's `generatedAt`.
- Alishan and mountain-railway switchbacks are real. A 180° pattern there is evidence, not an artefact — the preflight's one Taiwanese `REVERSAL_CANDIDATE` is `tw-alsr-alishan` and it is correct.
- Verify dense metro geometry, light-rail street running, airport MRT express/local infrastructure, and branch/loop order at close zoom.

## Hong Kong (`hk`)

- Sources: MTR journey-planner coordinates, MTR line/station open data, Light Rail route/stop data, Lands Department mapping, Hong Kong Tramways data — all listed in `hk-2025.sources.md`.
- Keep four concepts apart: physical track, named railway, scheduled service, stopping pattern.
- Light Rail 505 and 751 carry direction-specific physical edges that an ordered distinct-station list cannot express. The four `extraSegments` in this package exist for that reason and each carries an evidence string (`HK-LR-GEOM-002`) recording that the source holds one polyline per line, not one per track. Preserve them; do not invent a mirrored route.
- The East Rail Racecourse branch is `Sha Tin → Racecourse → University`. Do not connect it through Fo Tan because Fo Tan happens to lie on the nearby main line.
- Eastbound and westbound tram tracks are surveyed double track, not duplicate service names to collapse.
- Airport Express and Tung Chung Line share corridors while keeping separate identities, lanes and platform behaviour.
- Known open issue: the preflight reports ~11 intervals drawn as straight chords, the longest 1.5 km on `hk-mtr-eal-low`, plus 4 vertex jumps. These are source coverage gaps, not renderer faults.

## Macao (`mo`)

- Sources: Macao LRT official route/station information and DSCC mapping services listed in `mo-2025.sources.md`.
- Raw DSCC Macao Grid data uses its declared projected CRS (historically EPSG:8433 in this pipeline) and is transformed to canonical WGS84. Record the exact CRS and transformation.
- Three lines still need full interval, branch, station and source verification; a small network does not lower the evidence standard.
- Do not rewrite the package to match Apple MapKit. The presentation difference belongs in `AppleMapDatum`, and it must be verified on network lines, stations, ridden routes and playback together.
- Apple results around terminals and ferry/airport complexes are often buildings or entrances. Judge alignment from track geometry across several stations, never one POI.

## South Korea (`kr`)

- Sources per `kr-2025.sources.md`: official station records from data.go.kr, and track centrelines derived from the OpenStreetMap South Korea extract (ODbL) — so geometry here is **not** official survey data, unlike Taiwan or Macao. Say so in any alignment claim.
- Display ids are `kr-{revised-romanization}`; station groups are `kr-official-…`; persisted station codes (`KR-GYEONGBUSEON-SEOUL`) derive from each line's `codePrefix` and must not follow display-id renames.
- Names repeating across cities (중앙로 in 대구, 부산, 대전) carry numeric suffixes so groups never merge two different places. Check this before any same-name merge.
- Korea is inside the MapKit GCJ-02 display scope. An earlier Korean audit showed a single visual A/B at one complex yard was not enough to justify that — sample widely before changing the scope in either direction.
- Highest-defect region in the current preflight: ~37 straight chords, ~57 vertex jumps, 5 sparse intervals. Treat the OSM-derived alignment as the likely cause and look for official centreline coverage before hand-editing.

## United States (`us`) and Canada (`ca`)

- Both are built by one fail-closed pipeline, documented in `us-2025.sources.md` and `ca-2025.sources.md`, with per-line state in `na-2025-line-review.md` and `na-2025.acceptance.md`.
- Authority order: reviewed official/government GIS centreline → operator GTFS for identity, order, colour (geometry only after an independent FRA/OSM comparison) → FRA/BTS NARN routing for mainlines → OSM as a visual cross-check only. No published line is sourced directly from OSM.
- Fail-closed rules are part of the contract: missing provenance blocks a route, a failed trunk suppresses its branches, densification may not hide an endpoint chord, and near-reversals, broken seams, station-order jumps, repeated non-loop calls and unresolved anchors are release blockers. Both packages claim **no station-to-station fallback chords** — the preflight confirms zero, so any new `STRAIGHT_CHORD` here is a regression against a stated guarantee.
- A government layer documented as converted from GTFS cannot independently verify that same GTFS. Colours must be the exact GTFS `route_color` or a registered official palette.
- Blocked routes are deliberate and listed with reasons (exo, STM, REM, TTC 306/506, Kitchener, UP Express). Do not "fix" a coverage gap by publishing unverified track; the gap is the documented decision.
- Cross-border station ownership is explicit: Niagara Falls `NFL` is American, `NFS` Canadian, Saint-Lambert has one Canadian identity. No coordinate is inferred from a station name.
- North America is **outside** the Apple datum correction — Apple's basemap there is WGS84, and `verify.sh` pins that exclusion.

## Cross-region sampling for an Apple datum audit

For any proposed region-wide presentation transform:

1. Sample several cities, operators, surface and underground lines, terminals, curves and plain open track.
2. Compare canonical WGS84 and the candidate transform numerically against MapKit results.
3. Exclude ambiguous POIs, yards, station buildings and weak name matches.
4. Report median, p95, maximum, sample count, excluded count and geographic spread.
5. Do same-camera A/B visual checks at more than one location.
6. Reject a global rule when residuals are mixed, or when the transform improves one place and worsens another.
