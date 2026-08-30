# Historical JTM railway audit lessons

This is a maintained summary of earlier Japan Train Map tasks. It records durable decision lessons, not instructions to reproduce old outputs or accept old counts as current truth.

## Timeline and outcomes

### Taiwan database and rendering work — 2026-07-31 to 2026-08-04

- The regional architecture was separated by database while keeping a shared rendering, routing, editing, and persistence interface.
- Taiwan identifiers retained operator/TDX identity such as `StationUID`; Japanese six-digit N02 identifiers were not imposed on Taiwan.
- A Taiwan sample route was rebuilt into physical adjacent-station intervals with official geometry and provenance.
- The Taiwan package was then audited for all routes: station anchors were placed on their own line geometry, separate platform families at a shared complex stayed separate, throat spikes and short double-backs were removed, and genuine Alishan reversals were preserved.
- Durable lesson: “smoother” is not synonymous with “more accurate.” Smoothing must protect real switchbacks, station anchors, line identities, and shared-track topology.

### Hong Kong and Macao restoration — 2026-08-10 onward

- Hong Kong and Macao map elements were restored to the same display contract as Japan, but their source and topology rules remained regional.
- Hong Kong Light Rail exposed a model limit: lines such as 505 and 751 use non-mirrored direction-specific track. `extraSegments` was introduced because a distinct-station ordered list cannot express every physical service edge.
- Hong Kong East Rail's Racecourse branch was later repaired as an explicit branch from Sha Tin through Racecourse to University, avoiding a false connection through Fo Tan.
- The tramway also showed why two physical tracks must not be collapsed merely because their labels look like eastbound/westbound services.
- Durable lesson: separate physical railway, stopping pattern, scheduled service, and direction. They are related but not interchangeable entities.

### Full four-region audit — 2026-08-11

- A read-only scan covered the then-current Japan, Taiwan, Hong Kong, and Macao packages and found that current package counts were not the same as current official inventory.
- Confirmed misses included the newly opened Taiwan Sanying Line and two Japanese official line identities whose geometry overlapped other railways.
- The existing missing-line validator could skip an identity when nearby geometry already covered the corridor. This was a false negative: shared geometry does not replace `(operator, railway)` identity or station membership.
- Ridden-route lanes and station markers could disagree, and the model could not represent platform-level StopGroup/Slot distinctions. Existing tests sometimes encoded the incorrect center-marker behavior.
- Durable lesson: validator code and test expectations are themselves audit subjects. A green suite can preserve the wrong contract.

### Japan nationwide topology and station work — 2026-08-12 to 2026-08-20

- Nationwide checks found uncovered official corridors, wrong branch directions, artificial reversals, station-to-line displacement, unstable parallel lanes, and unsafe same-name label merging.
- Subsequent rebuilds and multi-line station audits used explicit evidence classes. Tokyo, Nippori, and Sapporo received evidence-backed fixes; hundreds of groups without platform or direction evidence remained pending instead of being force-merged.
- A later 651-line read-only fidelity audit found station anchoring generally strong but topology warnings, an orphan missing-line error omitted by the headline line count, and many short-edge angular artifacts.
- The basemap validator originally accepted yard, siding, spur, and crossover track as reference geometry. When those were excluded, many apparent passes required review.
- Constrained renderer-level corner reduction preserved anchors, loops, and paired corridors better than Chaikin, unrestricted Visvalingam-Whyatt, or generic Bézier smoothing. It still needed a performance budget.
- Durable lesson: report orphan/global errors separately from line-level counts; filter comparison track by railway use; preserve topology before optimizing appearance.

### WebUI versus iOS alignment — 2026-08-24 to 2026-08-25

- Web and Swift produced matching pre-render display parts, yet iOS still appeared far from Apple railways.
- The missing layer was final rendering simplification: Web used `0.0625 px`; the old iOS renderer used `0.5 px`. At regional zooms the eightfold difference created long chords tens or hundreds of metres from curves while all pre-simplification parity tests passed.
- The iOS tolerance was aligned with Web and a textual verification contract was added so both the full network and ridden routes use the shared value.
- Durable lesson: validate the last geometry handed to the renderer. Cross-language model parity does not cover platform-only LOD, clipping, simplification, or vertex budgets.

### Apple basemap datum work — 2026-08-25 onward

- Macao initially remained displaced after simplification was fixed. DSCC geometry converted to canonical WGS84 was correct for WebUI; Apple MapKit presentation required a regional display correction.
- Multi-region MapKit audits extended the presentation correction only where evidence supported it. Later Korean work showed that a single visual A/B at a complex yard was insufficient and required broader review.
- The correction was kept out of canonical packages, route solving, statistics, and caches, and applied to every MapKit subject: network lines, network stations, ridden routes, and playback markers.
- Durable lesson: never infer a country-wide datum rule from one POI or one station. Sample multiple cities and line types, compare both candidate datums numerically, and keep the transformation at one audited boundary.

## Recurring failure patterns

1. **Single-source trust:** an official feed can contain implausible coordinates or schematic/direct shapes. Cross-check coordinates, ordering, and scale.
2. **Identity erased by overlap:** a corridor can be geometrically covered while an operator/line identity or station membership is missing.
3. **Service merged into railway:** direction words stripped from service names can concatenate outbound and inbound station sequences or invent loops.
4. **Branch without trunk:** a builder can reject an unusable trunk while accidentally publishing orphan branches.
5. **Station order rotated or concatenated:** a sequence can jump far away and return, especially on loops, branches, and cross-border routes.
6. **Station anchoring mistaken for source accuracy:** renderer anchoring can hide a bad package endpoint or create an unnatural throat.
7. **Over-smoothing:** generic smoothing can destroy real switchbacks, loop closure, paired alignments, station anchors, or length.
8. **Loose basemap matching:** yards and service tracks can make a wrong main-line alignment appear correct.
9. **Pre-render parity blind spot:** shared fixture output can match while final Web or iOS rendering diverges.
10. **POI/track confusion:** an Apple Maps search result may be an entrance, building, or station complex centroid, not the platform or track.
11. **Sample-to-global overclaim:** one station, one city, one line, or one zoom level cannot prove a country-wide result.
12. **Headline count blind spot:** global/orphan issues can be omitted from per-line PASS/ERROR totals.

## Reporting rule inherited from the history

Use `PASS`, `WARNING`, `ERROR`, and `INCOMPLETE` honestly. `INCOMPLETE` is the correct result when authoritative coverage or visual evidence is unavailable, even if all executable checks pass. Preserve unresolved evidence gaps as named ledger entries rather than guessing.
