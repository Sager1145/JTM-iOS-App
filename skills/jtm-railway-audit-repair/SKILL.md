---
name: jtm-railway-audit-repair
description: Audit and repair Japan Train Map railway inventory, station identity, topology, surveyed geometry, and WebUI/iOS rendering parity for Japan, Taiwan, Hong Kong, or Macao. Use for missing or misrouted lines, straight station chords, wrong branches or directions, station offsets, Apple Maps alignment, compact-v1 package changes, and cross-platform railway regressions.
---

# JTM Railway Audit and Repair

Produce an evidence-backed result that distinguishes source-data defects, topology defects, Web rendering defects, and iOS MapKit presentation defects. A green format check is not proof that a railway follows the real track.

## Route the task

1. Respect whether the user asked for an audit, diagnosis, or repair. Audit-only and diagnosis requests do not authorize data or code changes.
2. Find the repository root containing `app/public/rail/` and `ios/`. Treat the working tree as shared; preserve unrelated changes.
3. Read [references/history-and-failure-patterns.md](references/history-and-failure-patterns.md) and [references/repository-contracts.md](references/repository-contracts.md) before planning work.
4. Read the affected country sections in [references/regional-evidence.md](references/regional-evidence.md). For current inventory, openings, closures, official geometry, or other changeable facts, verify against current primary sources rather than relying on the historical snapshot.
5. Before changing or validating files, read [references/verification-and-reporting.md](references/verification-and-reporting.md).

## Evidence standard

- Prefer official surveyed GIS or infrastructure geometry for alignment; use official route maps, station lists, and timetables for service identity and order. These prove different things.
- Cross-check even official feeds. Reject or quarantine implausible coordinates, impossible ordering, direction merges, and geometry that collapses to station-to-station chords.
- Use OpenStreetMap/OpenRailwayMap as attributed geometry evidence or an independent cross-check when official measured geometry is absent. Do not silently promote it to an official source.
- Treat Apple Maps as evidence about the iOS presentation boundary, not as the canonical data store. A POI may represent an entrance or building rather than the track or platform.
- Record URL, publisher, dataset/version date, CRS, licence, retrieval date, transformation, and any manual override. Never guess missing geometry.

## Audit in layers

Run the inexpensive structural preflight first:

```bash
python3 skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py \
  --repo . --countries jp,tw,hk,mo
```

Then inspect each layer independently:

1. **Inventory and identity:** compare operator/railway identities and station memberships with current official inventories. Geometry overlap never proves that a named railway is present.
2. **Stations:** verify stable regional IDs, names/aliases, order, coordinates, line membership, transfer groups, and whether separate platform families were incorrectly merged.
3. **Topology:** verify every adjacent station interval, loops, branches, reversal tails, direction-specific track, joins, crossings, and through-running. Distinguish a physical railway from the services that use it.
4. **Geometry:** scan for direct chords, large vertex jumps, self-overlap, double-backs, sharp artificial turns, wrong corridors, displaced station approaches, and missing trunk/branch coverage. Prioritize metro, light rail, tram, loop, and branched lines.
5. **WebUI:** inspect `displayPartsForLine`, station anchoring, grooming, lane assignment, GeoJSON simplification, route slicing, and representative low/medium/high zoom rendering.
6. **iOS:** prove package parity before investigating `RailNetworkStore`, `RailMapView`, LOD, clipping, vertex budgets, `RailStyle.simplifyTolerance`, and `AppleMapDatum`. Check network lines, stations, ridden routes, playback, cache coordinates, and statistics separately.

Do not let one layer's success erase another layer's failure. In particular, pre-simplification fixture parity cannot validate the final MapKit simplifier.

## Repair at the owning layer

- Fix repeatable source/build/override logic and regenerate outputs. Do not hand-edit only `*-2025.json` when a builder owns it.
- Keep every committed package in canonical WGS84 `[longitude, latitude]`. Apply any proven Apple basemap datum correction once, at the MapKit display boundary; keep routing, statistics, exports, caches, and WebUI data canonical.
- Preserve station anchors, shared-track keys, line identity, loops, branch lead-ins, stop order, and source attribution when smoothing. Prefer constrained, bounded edits over unconstrained curve fitting.
- Model non-mirrored directions or extra physical edges explicitly. Do not force a service with direction-specific track into one distinct-station sequence.
- Suppress an uncertain line rather than publish invented track, but report the resulting coverage gap and evidence needed to restore it.
- After regeneration, review package, stations, rail sections, readings, samples, fixtures, logos, source notes, and iOS resource wiring as one change set.

## Completion gate

A repair is complete only when:

- the affected official inventory and identities are accounted for;
- every changed station and interval has traceable evidence;
- structural, topology, geometry, station-anchor, Web, Swift parity, and final iOS rendering checks appropriate to the change pass;
- representative problem locations have been visually checked at useful zoom levels in both clients when visual alignment was in scope;
- unresolved warnings and limitations are listed rather than converted into a false PASS;
- the report names the exact countries, line counts, test commands, failures, evidence, and files changed.

Never claim “all lines fixed” from sampling, a single station, a single zoom level, or only a zero-error validator summary.
