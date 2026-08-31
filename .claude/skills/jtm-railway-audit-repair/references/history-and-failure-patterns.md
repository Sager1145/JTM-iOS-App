# Historical JTM railway audit lessons

Distilled from every railway-repair session across the `Japan-Train-Map` and `JTM-iOS-App` repositories, 2026-07 to 2026-08. A shorter Chinese digest of the same material is in [lessons-zh.md](lessons-zh.md); this file is the authoritative one. These are durable decisions and defect classes, not instructions to reproduce old outputs or to accept old counts as current truth. Where a case is named, it is named because the same shape recurs.

## Timeline

### Taiwan database and rendering — 2026-07-31 to 2026-08-04

- Regions were separated by database while sharing one rendering, routing, editing and persistence interface. Taiwan kept TDX/operator identity (`StationUID` in `n02_station_code`); Japanese six-digit N02 identifiers were not imposed on it. The solver already read neutral property aliases — only the statistics layer was still hardcoded to `N02_*`.
- **Alishan: mileage agreed while the shape was wrong.** The router weighted a 2021 MOA detail layer equally with the current NLSC layer and preferred its coarse chords, so 樟腦寮→獨立山 was drawn 3.27 km against an official 4.10 km, and forced `via` points padded the length back. Fixed by NLSC-current-first routing (MOA penalised 2.5× and used only to bridge gaps) plus dense `via` sampling every 300 m (150 m in the figure-of-eight). Result: all 16 intervals within 0.2 km of the official table.
- **臺東線 self-reversal (+7.3 km).** NLSC's old/new double track broke the chain at 壽豐–豐田 and TDX's own geometry there was a 6.2 km straight chord; a 12× penalty made a 9.5 km detour "cheaper" than the chord. Fixed by subdividing TRA chords at 0.1 km before graph insertion and dropping the penalty to 2.5. Result 151.3 km against an official 150.9, self-overlap 0.00 km.
- **The corner-radius metric was measuring the wrong thing.** A circumcircle through three adjacent vertices, at 4 m vertex spacing, measures sampling density rather than sharpness — even a 6° bend scored under 40 m, so the whole network got smoothed and Alishan lost 107 m while its minimum radius got *worse* (14.5 → 12.4 m). Replaced with `windowed_corner_radius_meters`, sampling ±20 m along arc length. The fix became surgical: network corners under 40 m went 179 → 102, all four switchback vertices unmoved to the digit, 平溪線 displaced 0.00 m.
- Durable lesson: **"smoother" is not "more accurate", and "the mileage matches" is not "the shape is right."**

### Hong Kong and Macao — 2026-08-10 onward

- **One geometry source per line.** The first Hong Kong package spliced OSM with Lands Department data and produced 1,349 micro-kinks in 3,273 points (41%), because the seams between two surveys do not agree and simplification preserves spikes rather than removing them. Rebuilt from OSM alone, chained by exact node id: 23 lines, zero kinks, zero bridges. Cross-check between sources, never splice them into one polyline.
- **Model the physical railway, not the service.** Hong Kong's tram services share the same track; modelling per service drew the corridor five or six times and inflated 30 km to 150 km. The same rule later saved Korea, where 수도권 1호선 runs over 경부선 + 경인선 + 경원선 + 장항선.
- Light Rail 505 and 751 carry direction-specific physical edges an ordered distinct-station list cannot express — hence `extraSegments`, each carrying its evidence string.
- East Rail's Racecourse branch is `Sha Tin → Racecourse → University`, not a connection through Fo Tan. Eastbound and westbound tram tracks are surveyed double track, not two names to collapse.
- Durable lesson: **physical track, named railway, scheduled service and stopping pattern are four different entities.**

### Four-region audit — 2026-08-11

- A read-only scan found package line counts diverging from the current official inventory: Taiwan's newly opened Sanying Line and two Japanese identities whose geometry overlapped other railways were missing, and the missing-line validator skipped them precisely *because* nearby geometry covered the corridor.
- Ridden-route lanes and station markers could disagree, and some tests encoded the incorrect centre-marker behaviour.
- Durable lesson: **validators and their tests are audit subjects too. A green suite can preserve the wrong contract.**

### Japan nationwide topology and stations — 2026-08-12 to 2026-08-21

This is the longest campaign and produced most of the defect catalogue below.

- **Branch stations interleaved into the trunk's station order.** 函館線 carried the 砂原支線's stations inside the main sequence, so (a) the trunk interval across the junction did not exist at all, (b) the branch drew as broken blocks, and (c) recorded journeys inherited the detour — 北斗21 was stored as 駒ヶ岳 → 東森 → 森, 3.3 km longer than the real main line, calling at a station it never stops at. 中央線's みどり湖 was the same disease. Fixed by a table-driven split, and a hard-won implementation rule: **rewrite only the station window that actually changes** — re-encoding the whole line left a V-kink at every station and shattered 函館線 into 16 parts.
- **`compact-v1` allows one row per station per line.** At 大宮, N02 files 埼京線 under 東北線 and the package welded the branch onto the front of the trunk's station order, so the branch had *no* 大宮 row and its journey could only project onto the trunk's eastern island — drawing a 98 m, 73° chord across the station throat. The fix was to split the branch into its own line id with the junction station carrying its own anchor. **A branch that needs a different platform point needs its own line id.**
- **Track-group split points must be shared on both sides.** 石北線 stopped at 生田原 and 石北線-2 started at 西留辺蘂, and nothing drew the 19.05 km between them; 東海道線's 大垣–垂井 was structurally identical. Fixing it needed both code (split the track graph at T-junctions) and data (adjacency ledger rows) — one alone leaves the station graph in two components.
- **Pseudo-adjacency edges create phantom geometry.** 成田線's tripled corridor was not a lanes-table fault: three skip-station pseudo-edges at 成田 formed a K4 clique, chain decomposition degraded to `tree_decompose`, and the corridor was drawn three times. 品川's V came from a 大井町–西大井 pseudo-edge for a connection with no passenger service.
- **An anchor on the wrong siding manufactures a reversal.** 取手's station order was fine; its nearest N02 node sat on the 緩行線 terminating track, so the path backed up 2.5 km to reach the through line — 11.36 km against an official 6.0 — and the renderer cut the fold into a 取手 → 取手 3.9 km stub.
- **Distance alone cannot separate two alignments; geometry can.** A detector dropped 森–駒ヶ岳 as "skipping 東森" because the lengths coincided.
- **Basemap disagreement is not proof we are wrong.** Comparing 663 lines against OSM, 594 matched within 50 m. Of the 69 flagged, only **5** were genuinely our error — and each was a line drawn on track that no longer exists (福知山線 旧上り線 9.1 m away, razed 筑豊本線, razed 飯田線 alignment, the abandoned 板谷峠 switchback corridor, an N02 second-bore coarse centreline). The rest sorted into: suspended/BRT lines OSM has re-tagged as disused (a product decision, not a defect), 55 tunnel segments 50–120 m off where **OSM is the wrong one** — volunteers approximate long tunnels while N02 is the official centreline — and guideway bus that can never match.
- **A detector's false-positive rate can exceed 90%.** Of 113 "floating" station points, 107 were detector artefacts (named sidings, tunnel approximations, terminals, systematic survey offsets, weak fuzzy matches); 11 were real.
- **Every existing audit had a blind spot, and one chord fell through all three.** 岸里玉出's 211 m chord across the station was invisible to station-anchoring (the chord passes through the dot), to basemap-alignment (which needs ≥150 m of >50 m deviation, and this peaked at 84 m), and to the ridden-route approach audit (which only looks at ridden lines). It took a fourth, purpose-built audit measuring the first and last 300 m of every interval against the nearest *active* OSM way, using the interval's own median as the ambient value.
- **OSM track names are legal ownership, not platform ownership.** The evidence ledger scored 高野線's platform by distance to ways *named* 高野線; the two tracks at 天下茶屋–岸里玉出 legally belong to 南海本線 and OSM names them so, which scored the wrong platform 185 m away as correct. Claim a line's own track by operator → name → running track, never by nearest.
- **`validate-basemap-alignment.mjs` structurally cannot find a wrong platform choice.** It measures distance to *any* active way; in a large station a dozen parallel tracks lie 5–15 m apart, so any choice passes. A wrong platform is 20–120 m sustained over 100–300 m — under both halves of that gate. Wrong threshold, wrong question.
- **Corridor extrapolation invented corridors.** Lane boundaries were extrapolated all the way to the next station; with Shinkansen station spacing of 30–50 km, a 2 km real parallel stretch became tens of km of fake corridor. Capping the snap at 2,000 m took Japan's lane mileage from 3,273 km to 1,776 km. A useful negative result came with it: **the bridge parameter (6000 → 0) changed nothing** — do not tune it again.
- **`line-offset` sign is relative to the feature's own digitised direction.** Two lines digitised in opposite senses offset to the same side unless the sign is flipped, and on a loop seam (大阪環状線) the direction cannot be inferred from geometry at all — the slicer must report the branch it took rather than being reverse-engineered afterwards.
- The lane translation scheme was later **retired** in the JP repository's spec (§7.2 rewritten to "each line draws its own measured geometry; no further translation schemes", R14 withdrawn). Check which regime a package is under before proposing offsets.
- 赤羽 is a standing exception: 東北新幹線 and 赤羽線 share 240 m within 3 m because they are the upper and lower decks of one viaduct. Geometrically coincident, different railways, must not be de-duplicated.

### WebUI versus iOS alignment — 2026-08-24 to 2026-08-25

- Web and Swift produced matching pre-render display parts, yet iOS drew visibly further from Apple's railways. The missing layer was the final simplifier: Web `0.0625 px`, the old iOS renderer `0.5 px`. Eightfold, invisible to every parity fixture, and worth tens to hundreds of metres at regional zoom.
- **The 0.0625 value is derived, not arbitrary, and it is bounded on both sides.** From a 1.5 px stroke and a 90° corner, the chord deviation works out to 0.114 px; divided by geojson-vt's measured 1.6× overshoot that caps tolerance at 0.071, and 0.0625 is the first clean binary fraction below it. Halving it again was rejected as below the promise it implements. The lower bound is hard: at tolerance 0 a single z6 tile carries 155,574 vertices and MapLibre drops the tile outright — the blank squares over Kantō.
- Durable lesson: **validate the last geometry handed to the renderer.** Cross-language model parity does not cover platform-only LOD, clipping, simplification or vertex budgets.

### Apple basemap datum — 2026-08-25 onward

- Macao stayed displaced after simplification was fixed: DSCC geometry converted to canonical WGS84 is right for the WebUI, and Apple's MapKit presentation needed a regional correction. It was extended only where evidence supported it; a later Korean check showed a single visual A/B at one complex yard was not enough.
- The correction stays out of canonical packages, routing, statistics and caches, and covers every MapKit subject: network lines, network stations, ridden routes, playback markers.
- **The display coordinates are not reversible.** `coordinates` has already been GCJ-02 shifted, so a cache that stores it re-shifts on the next load; the drawn path needs its own WGS84 copy alongside `sourceCoordinates`.
- Durable lesson: **never infer a country-wide datum rule from one POI or one station.** Sample multiple cities and line types, compare both candidate datums numerically, keep the transform at one audited boundary.

### iOS-side geometry — 2026-08-28 to 2026-08-29

- **A straight chord can be created inside the app, with a perfect package.** `RouteGraph.Edge` carries only a length, not the section geometry it was built from, so a Dijkstra path is drawn as straight lines between graph nodes. It is invisible normally because a station-to-station journey crosses 9–55 edges — but where one interval *is* one edge over a tight curve, the chord shows. That is exactly why 熊本市電 (300 m station spacing) and ゆいレール's 安里 curve were the ones that looked wrong.
- **`sourceCoordinates` is for statistics and must stay same-origin with the N02 edge index.** "Improving" it to the display network pushed unmatched ridden distance from 3.342 km to 95.326 km — Tokyo's two Shinkansen platforms draw from OSM track, which the N02 edge index cannot match.
- A `load` five suspension points long overwrote a newer working set; one writer, one generation counter.

### Korea, then North America — 2026-08-11 onward

- Korea reused the Hong Kong pipeline shape but its geometry comes from an OSM extract, not official survey data — and it is today the region with by far the most straight-chord and vertex-jump candidates. Two geometry paths were needed because Korean OSM is tagged two ways: metro/light rail/monorail chain through route relations, mainlines need a named-track subgraph with station-to-station shortest paths (a double-scan diameter path ran 631 km down to Busan and back).
- **Official data can simply be wrong.** Alaska Railroad's own GTFS places Fairbanks at 60.608 / −149.062 — on the Kenai Peninsula, 12 km from Grandview — and Whittier about 55 km off. The builder copied it faithfully and drew the Aurora Winter as 1,065 km against a real ~570, with 72.8% of the line lying on itself. This is the strongest argument in the whole history for multi-source cross-validation.
- **Round-trip shapes break per-station projection.** `cut_at_stations` chose each station's projection independently, and an operator's out-and-back shape offers two candidates metres apart in space but kilometres apart along the line. Adjacent stations picked opposite passes: CTA's Brown Line drew Kimball → Kedzie, really 410 m, as 32.6 km, and the whole 18 km line as 190 km. Fixed by enumerating each station's candidate projections (local minima of the distance function) and solving the assignment for the whole line at once with Viterbi. 190 → 18.0 km.
- **Deduplicate by geometry and stations, never by operator string.** 45 railways were drawn twice — once from GTFS, once from an OSM fallback whose duplicate check compared operator names — because in North America the publisher is routinely not the operator: GCRTA vs Greater Cleveland RTA, TransLink vs InTransitBC, Réseau express métropolitain vs Pulsar, Keolis vs VRE. Every new feed can add another silent duplicate. The coverage report compounded it: comparing by operator, a partially covered operator (PATH in, the same authority's AirTrain JFK out) always reports work still to do.
- **A build cache fingerprint that does not hash the library silently republishes old geometry.** The NA cache key covered the build script and the feed archives but not `lib/`, where every geometry fix actually lived.
- **A provenance statement is a testable claim.** `ca-2025.sources.md` said no coordinate came from OpenStreetMap while three lines carried `geometrySource: "osm"` (the US package, 32). Under-declaring what a package owes a source is the one error class in that file that costs someone else something.
- The pipeline that came out of this is deliberately fail-closed: missing provenance blocks a route, a failed trunk suppresses its branches, and blocked operators are listed with reasons instead of being filled in with plausible track.

### Region loading — 2026-08-30

- Eager loading made every reader wait on Japan's 9.3 MB. Tiered loading (`RegionCatalog` marks `jp`/`us` large, the rest compact, small regions concurrent first) fixed it. Check that a lazy or tiered loader still hands both clients identical geometry.
- **Country-scoped caches must all be reset on a switch.** `railContentHashCache` was never cleared, so after JP → TW the hash was still Japan's: warm cache injected Japanese geometry into a Taiwan session — same-name pairs like 松山 and 板橋 would draw the other country's line — and new solutions persisted into the Japanese namespace.

### The audit tooling was itself wrong — 2026-08-31

- The first version of this skill's preflight read `segments[i]` as a self-contained polyline. For `jp`, `us` and `ca`, where `continuesFromPrevious == 1` drops the vertex shared with the previous row, that under-measured 5,575 Japanese intervals and mis-located every continuing row's first endpoint — while printing `0 errors, 2 warnings`.
- Its straight-chord gate was set at 20 km, so the 48 intervals across Hong Kong and Korea that really are drawn as straight lines — including 1.52 km on the East Rail low-platform line — never appeared.
- Durable lesson: **prove the reader against the format before trusting any geometric number.** A validator that misreads the encoding produces confident, wrong reassurance.

### Open ledger — found by the rebuilt preflight, not yet fixed

- **`us / metropolitan-atlanta-rapid-t-atlsc` segment 10 carries a whole extra lap.** Peachtree Center Station → Carnegie Way @ Ted Turner Dr are 264 m apart; the interval is drawn as 3.93 km whose geometry passes within 0–23 m of **all twelve** of the line's stations. The other eleven intervals sum to 3.929 km, which is the real 2.7-mile loop — so the package's `lengthKm: 7.857` is very nearly double the truth, and any ridden-mileage statistic for this line inherits the error. This is the loop-seam sibling of the CTA Brown Line projection bug: at the seam the interval took the long way round. It is isolated — a scan of every line in all seven packages finds no second case. The fix belongs in the North America builder's station-projection/loop handling, not in the published JSON.
- **`jp-西日本旅客鉄道-東海道線-2` segment 0** declares 0.698 km while its own geometry walks 0.873 km (大阪 → 福島, the 梅田貨物線 stroke); `jp-阪急電鉄-今津線-2` segment 0 declares 1.019 against 1.085. Both endpoints sit exactly on their station anchors, so one of the two numbers is stale.
- **Hong Kong 11 and Korea 42 intervals** are drawn as straight chords or near-straight sparse geometry; Korea adds 57 vertex jumps. Both are source coverage gaps rather than renderer faults, and Korea's OSM-derived alignment is the likely cause.
- **Six US lines are drawn partly on top of themselves** (Galveston 86%, Atlanta Streetcar 82%, SunTran 790 57%, Portland Streetcar NS 55%, LIRR Port Washington 20%, RTD E 12%). The first four are loop or couplet street lines and share the Atlanta signature; the last two need separate review.

## Defect catalogue

**Source layer**

1. Official feed with wrong coordinates (Alaska Railroad GTFS). Cross-check every source, official or not.
2. Multi-source splicing producing seam kinks (Hong Kong OSM + LandsD, 41% of vertices). One source per line; cross-check without merging.
3. A chord inside the source distorting routing cost, not just appearance (TDX 壽豐–豐田).
4. Per-station projection onto a round-trip shape (CTA Brown Line, 410 m drawn as 32.6 km).
5. Duplicate railways from two feeds, hidden by an operator-name dedup (45 NA lines).
6. Service modelled as railway, inflating mileage several-fold (Hong Kong trams, Korean 광역전철).
7. Missing identity behind covered geometry (Sanying Line, two Japanese identities).

**Topology and station order**

8. Branch stations interleaved into the trunk order (函館線, 中央線).
9. Track-group split points not shared, leaving an undrawn gap (石北線, 大垣–垂井).
10. Pseudo-adjacency edges forming cliques and multiplying corridors (成田線, 品川).
11. Station anchored to the wrong siding, manufacturing a reversal stub (取手).
12. One-row-per-station-per-line forcing a branch onto the trunk's platform (大宮).
13. Rotated or concatenated station order, especially on loops and cross-border routes.

**Geometry and smoothing**

14. Generic smoothing destroying real switchbacks, loop closure, paired alignment or length.
15. A sharpness metric that actually measures sampling density (circumcircle at 4 m spacing).
16. Package-layer corner rounding creating edges the render layer cannot tell from noise — Alishan's median edge is 10.6 m with 48.6% under 10 m, and the renderer's noise gate is 8 m.
17. Shared vertices between a trunk and its branch being smoothed apart (up to 24 m); protect keys shared by multiple parts.
18. Corridor extrapolation inventing parallel corridors between distant stations.

**Renderer and cross-platform**

19. Two simplifiers with different tolerances, invisible to pre-render parity fixtures.
20. Endpoint snapping rewriting the last vertex to a platform point and drawing a chord when the display line is a different track (`canonicalizeRouteFeature` / `snapEndpoint`, 260 m budget, 大宮 98 m at 73°).
21. Graph edges without geometry drawing Dijkstra paths as straight lines (`RouteGraph.Edge`).
22. `line-offset` sign taken from geometry rather than from the slicer, ambiguous at a loop seam.
23. Display coordinates written back into a cache after an irreversible datum shift.
24. Zoom-dependent visibility keyed on rank rather than length, so one corridor split across operators breaks apart when zooming out.

**Tooling and process**

25. A validator that misreads the format.
26. A threshold set where the real defect cannot reach it.
27. Detectors with >90% false positives; every finding needs triage, not a count.
28. Audits with structural blind spots — check what a detector *cannot* see before trusting a clean result.
29. Build caches whose fingerprint misses the code that produces the output.
29b. A loop's seam interval taking the long way round, doubling the line's published length (Atlanta Streetcar).
30. Provenance and licence statements that no longer match the data.
31. Global and orphan errors omitted from per-line PASS/ERROR totals.

## Known-correct things that trip detectors

Do not "fix" these without new evidence:

- Real switchbacks and spirals: Alishan (獨立山 spiral, 神木/第一/第二分道), 木次線 出雲坂根 three-stage, 阪和線 東羽衣, 千歳線 新千歳空港, Korea's 영동선. Japan had 16 interval reversals of which several are genuine.
- 二萬平 is *not* a switchback — it is an R≈30 m horseshoe.
- 湯檜曽's two platforms 73 m apart are a fact to draw (up line at grade, down line in tunnel), not a pair to average.
- 赤羽: 東北新幹線 and 赤羽線 coincide within 3 m for 240 m on one viaduct.
- Shinkansen tunnel segments 50–120 m from OSM: the basemap is the approximation, not the package.
- Suspended and BRT-replaced lines still drawn from N02 while OSM has re-tagged them disused: a product decision.
- Guideway bus (志段味線) can never match a railway basemap layer.

## Reporting rule inherited from the history

Use `PASS`, `WARNING`, `ERROR` and `INCOMPLETE` honestly. `INCOMPLETE` is the correct result when authoritative coverage or visual evidence is unavailable, even if every executable check passes. Keep unresolved evidence gaps as named ledger entries rather than guessing, and report global or orphan findings separately so they cannot disappear from a headline count.
