# Regional evidence guide

Read only the sections for the countries in scope. URLs and counts are leads from the current repository; verify current operational facts online with primary sources when recency matters.

## Japan (`jp`)

- Primary inventory and measured geometry: MLIT National Land Numerical Information railway data (N02). Confirm the dataset year and effective date in `app/public/rail/jp-2025.sources.md`.
- Identity key: operator plus railway identity and the associated station memberships. Do not let coincident geometry suppress a missing identity.
- Station codes are six-digit N02-style codes in the journey/store compatibility layer. Preserve regional identity and aliases separately from station-complex grouping.
- Audit discontinued, suspended, freight, and non-passenger geometry explicitly; absence from Apple Transit is not sufficient evidence to delete an N02 railway.
- Treat N02 field anomalies as source conflicts, not new operators or lines. Quarantine with an evidence-backed override.
- High-risk shapes: long JR lines with split strokes, urban parallel corridors, Shinkansen overlaps, loops, terminal reversals, branch rejoin points, and multi-line station throats.
- When comparing with OSM/OpenRailwayMap, exclude yard, siding, spur, and crossover track unless the audited subject specifically uses them. Prefer `usage=main|branch` and document exceptions.

## Taiwan (`tw`)

- Primary sources: TDX rail APIs and official government railway/metro/light-rail centerline and station datasets listed in `tw-2025.sources.md`; use operator sources for openings, station order, and service status.
- Preserve TDX/operator station identities such as `StationUID`; do not derive country from a fragile operator prefix when the country-scoped station dataset can resolve it.
- Keep separate platform families for TRA, THSR, metro, and airport rail even when they share a named station complex.
- The Sanying Line history is a reminder to compare package inventory with the current operating network, not the package's `generatedAt` label alone.
- Preserve real Alishan and mountain-railway switchbacks. A 180-degree pattern may be correct evidence, not automatically an artificial reversal.
- Verify dense metro geometry, light-rail street running, airport MRT express/local infrastructure, and branch/loop order at close zoom.

## Hong Kong (`hk`)

- Use MTR official journey-planner coordinates, line/station open data, Light Rail route/stop data, Lands Department mapping, and Hong Kong Tramways data listed in `hk-2025.sources.md`.
- Separate four concepts: physical track, named railway, scheduled service, and stopping pattern.
- Light Rail 505 and 751 contain direction-specific physical edges that a distinct station-order array cannot fully express. Preserve explicit `extraSegments` and their evidence instead of inventing a mirrored route.
- The East Rail Racecourse branch is `Sha Tin → Racecourse → University`; do not connect it through Fo Tan simply because Fo Tan lies on the nearby main line.
- Eastbound and westbound tram tracks are surveyed double track, not duplicate service names to collapse automatically.
- Airport Express and Tung Chung Line share corridors while retaining separate railway identities, lanes, and station/platform behavior.

## Macao (`mo`)

- Use Macao LRT official route/station information and DSCC mapping services listed in `mo-2025.sources.md`.
- Raw DSCC Macao Grid data uses its declared projected CRS (historically EPSG:8433 in this pipeline) and is transformed to canonical WGS84 for the package. Record the exact CRS and transformation.
- A three-line network still requires full interval, branch, station, and source verification; small counts do not reduce the evidence standard.
- Do not rewrite the Web package to match Apple MapKit. If multi-point evidence shows a presentation datum difference, keep it in `AppleMapDatum` and verify network lines, stations, ridden routes, and playback together.
- Apple search results around terminals and ferry/airport complexes may represent buildings or entrances. Use track geometry and multiple stations, not one POI, to judge alignment.

## Cross-region sampling for an Apple datum audit

For any proposed country-wide presentation transform:

1. Select multiple cities/areas, operators, surface/underground lines, terminals, curves, and uncomplicated open-track locations.
2. Compare canonical WGS84 and the candidate transform numerically against MapKit results.
3. Exclude ambiguous POIs, yards, station buildings, and results with weak name matches.
4. Report median, p95, maximum, sample count, excluded count, and geographic distribution.
5. Perform same-camera A/B visual checks at more than one location.
6. Reject a global rule when residuals are mixed or the transform improves one place while worsening another.
