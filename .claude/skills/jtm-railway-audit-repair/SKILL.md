---
name: jtm-railway-audit-repair
description: Audit and repair Japan Train Map railway inventory, station identity, topology, surveyed geometry, and WebUI/iOS rendering parity for any shipped region (jp, tw, hk, mo, kr, us, ca). Use for missing or misrouted lines, station-to-station straight chords, wrong branches or directions, station dots off their line, Apple Maps alignment and datum questions, compact-v1 package changes, and cross-platform railway regressions.
---

# JTM Railway Audit and Repair

Produce an evidence-backed result that separates four different things: a source-data defect, a topology defect, a Web rendering defect, and an iOS MapKit presentation defect. They look identical on a screenshot and are fixed in different places. A green format check is not proof that a railway follows the real track.

## Route the task

1. Respect the mode the user asked for. An audit or a diagnosis does not authorize data or code changes; a repair does.
2. Work from the repository root that contains `app/public/rail/` and `ios/`. The tree is usually dirty from parallel sessions — preserve unrelated changes and do not adopt someone else's build errors as your own.
3. Read [references/repository-contracts.md](references/repository-contracts.md) for who owns which file, and [references/history-and-failure-patterns.md](references/history-and-failure-patterns.md) for the defect classes this project keeps producing and the open ledger of known-unfixed findings. [references/lessons-zh.md](references/lessons-zh.md) is a shorter Chinese digest of the same material — useful when reporting to the user in Chinese, but the English file is authoritative.
4. Read only the in-scope country sections of [references/regional-evidence.md](references/regional-evidence.md). Inventory, openings, closures, and official geometry change — verify current facts against primary sources rather than trusting the snapshot.
5. Read [references/verification-and-reporting.md](references/verification-and-reporting.md) before running or claiming any check.

## Know what the format means before measuring anything

Every geometric conclusion depends on reading `compact-v1` correctly. The rows are positional:

```text
stations[i] = [id, name, lon, lat, roma, romaSource, (tzIndex)]
segments[i] = [km, continuesFromPrevious, coordinates]      # one row per station interval
```

- `continuesFromPrevious == 1` means the row **drops the vertex it shares with the previous row**. The interval's real polyline is `[previous_row_last_vertex] + coordinates`. `jp`, `us` and `ca` use this; `tw`, `hk`, `mo` and `kr` repeat the shared vertex instead and use `0`. Measuring a continuing row on its own under-reports its length and puts its first endpoint at the wrong place — the reason an earlier version of this skill's own preflight mis-measured 5,575 Japanese intervals.
- `km` is the length of that reconstructed polyline. Geometry and `km` that disagree is an internal inconsistency, not a rounding artefact.
- Station anchors coincide **exactly** with interval endpoints in every shipped package. An anchor sitting metres off its line is a regression, not a tolerance.
- `extraSegments` exists because an ordered distinct-station list cannot express direction-specific physical track (Hong Kong Light Rail 505 and 751). Each entry needs `from`, `to` and an `evidence` string; an entry without evidence is an invented edge.
- Coordinates are canonical WGS84 `[longitude, latitude]` everywhere, in every package, for every region.

## Preflight

The script sits beside this file in `scripts/`. Which path reaches it depends on where the skill is installed:

```bash
# project install, from an iOS checkout
python3 .claude/skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py --limit 40
# user-level install, from any checkout — including the web-only repository
python3 ~/.claude/skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py --repo . --limit 40
```

It needs `app/public/rail/` and nothing else. In a checkout with no `ios/` — the web repository still owns the Japan, Taiwan, Hong Kong, Macao and Korea builders and has no iOS tree — it audits the packages and reports `WEB_ONLY_CHECKOUT`, naming the cross-platform contracts it could not check rather than calling them missing files.

It audits every package it finds (`--countries jp,tw,hk,mo` narrows it), reconstructs chained geometry, and takes about ten seconds for all seven. Alongside header, identity and anchor errors it reports `INTERVAL_RETRACES_LINE` (an interval carrying an extra lap of its own line) and six review classes: `STRAIGHT_CHORD`/`SPARSE_GEOMETRY` (an interval drawn as a straight line instead of following track), `DETOUR_RATIO` (walking far further than the gap between its two stations), `SELF_OVERLAP` (a line drawn on top of itself, parallel and far apart along the line), `VERTEX_JUMP`, `REVERSAL_CANDIDATE` and `GEOGRAPHIC_OUTLIER`. Add `--json report.json` for the full list, `--strict` to fail on unreviewed warnings.

Warnings are review candidates, never verdicts: Alishan's spirals and 木次線 出雲坂根 are real, and a dead-straight Shinkansen viaduct is not a chord. Historically these detectors have run past 90% false positives on some defect classes — triage every finding against evidence, and say what you concluded. Equally, ask what a detector *cannot* see: a 211 m chord across 岸里玉出 passed through three separate audits untouched.

## Audit in layers

Do not let one layer's success erase another's failure.

1. **Inventory and identity** — compare `(operator, railway)` identities and station memberships with the current official inventory. Geometry that covers a corridor never proves the named railway is present; that false negative is how the Taiwan Sanying Line and two Japanese identities were missed. De-duplicate by geometry and station sets, never by operator name — in North America the publisher is routinely not the operator, and that dedup let 45 railways be drawn twice.
2. **Stations** — stable regional IDs, names/aliases, order, coordinates, line membership, transfer groups, and whether separate platform families at one complex were wrongly merged.
3. **Topology** — every adjacent-station interval, loops, branches, reversal tails, direction-specific track, joins, crossings, through-running. Keep four concepts apart: physical track, named railway, scheduled service, stopping pattern — modelling services as railways drew Hong Kong's tram corridor five times and inflated 30 km to 150 km. Watch for branch stations interleaved into a trunk's station order: it deletes the trunk interval across the junction and rewrites recorded journeys into a detour.
4. **Geometry** — chords, vertex jumps, self-overlap, double-backs, artificial sharp turns, wrong corridors, displaced station approaches, missing trunk or branch coverage. Metro, light rail, tram, loop and branched lines first.
5. **WebUI** — `displayPartsForLine`, station anchoring, grooming, lane assignment, GeoJSON simplification, route slicing, at low/medium/high zoom.
6. **iOS** — prove package parity first, then `RailNetworkStore`, `RailMapView` LOD/clipping/vertex budgets, `RailStyle.simplifyTolerance`, and `AppleMapDatum`. Check network lines, network stations, ridden routes, playback, the route cache, and statistics separately — they are separate subjects that can disagree.

A chord on a ridden route can be produced entirely inside a client, with a perfect package: `RouteGraph.Edge` carries a length but not its section geometry, so a solved path is drawn straight between graph nodes wherever one station interval happens to be one edge over a tight curve; and the Web's `canonicalizeRouteFeature`/`snapEndpoint` rewrites an interval's last vertex to the platform point, which draws a chord when the display line is a different track. Establish which layer owns the chord before touching data.

Pre-simplification fixture parity cannot validate the final MapKit simplifier. That gap is exactly how the drawn line stood eight times further off the track than the Web's while every parity test passed.

## Repair at the owning layer

- Fix the earliest reproducible layer — source, builder, or override — and regenerate. Do not hand-edit `*-2025.json` when a builder owns it; if only the generated JSON exists, say so in the report and leave a repeatable override or check behind.
- Keep every committed package canonical WGS84. Any Apple basemap datum correction stays at the MapKit display boundary (`AppleMapDatum`, currently `tw, hk, mo, kr`) and out of routing, statistics, exports, caches and the WebUI. Never infer a country-wide datum rule from one POI or one station.
- Preserve station anchors, shared-track keys, line identity, loops, branch lead-ins, stop order and source attribution when smoothing. Constrained, bounded corner reduction beats generic Chaikin/Visvalingam/Bézier smoothing, which destroys real switchbacks and loop closure. Check any sharpness metric against vertex spacing first — a circumcircle through three adjacent points measures sampling density, not sharpness, and smoothed the whole Taiwanese network while making Alishan's minimum radius worse.
- Matching mileage does not prove a correct shape: Alishan once matched the official table to the kilometre while cutting the 獨立山 spiral and padding the length back with forced via points.
- Use one geometry source per line. Splicing two surveys gave Hong Kong 1,349 micro-kinks in 3,273 points; cross-check sources against each other, never merge them into one polyline.
- Rewrite only the station window that actually changes. Re-encoding a whole line to fix one branch left a V-kink at every station and shattered 函館線 into 16 parts.
- Model non-mirrored directions and extra physical edges explicitly rather than forcing them into one station sequence.
- Suppress an uncertain line rather than publish invented track — then report the coverage gap and the evidence needed to restore it.
- `ios/verify.sh` enforces several of these invariants as **textual greps** against specific file, function and variable names. Moving or renaming that code breaks the gate even when the behaviour is unchanged; grep `ios/verify.sh` for the symbol before you move it, and update the contract deliberately.

## Completion gate

A repair is complete only when:

- the affected official inventory and identities are accounted for;
- every changed station and interval has traceable evidence (URL, publisher, dataset version/date, CRS, licence, retrieval date, transformation, manual overrides);
- the structural, topology, geometry, anchor, Web, Swift-parity and final-iOS checks appropriate to the change all pass;
- representative problem locations were looked at in both clients, at useful zoom levels, when visual alignment was in scope;
- unresolved warnings are listed as a ledger instead of being converted into a false PASS;
- the report names the exact regions, line counts, commands, failures, evidence and files changed.

Never claim "all lines fixed" from sampling, one station, one zoom level, or a validator summary that reports zero errors.
