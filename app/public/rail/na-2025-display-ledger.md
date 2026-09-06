# North America display review — full line ledger

> **Note (2026-09-05):** the TTC line ids below predate the correction of the
> Blue Night numbering and no longer exist. `ttc-304*` → `ttc-504*` (King),
> `ttc-306*` → `ttc-506*` (Carlton), `ttc-310*` → `ttc-510*` (Spadina); the branch
> shards were re-cut at the same time, so a `-bN` here does not map to the same
> `-bN` now. The review this ledger records is unchanged; only the names moved.

Walks every flagged row in `na-2025-display-review.json` (62 lines) and every line with
follow rows in `display-lanes.json` (221 unique `(line, canonical)` pairs across us+ca,
259 raw follow rows). Evidence pulled from `na-2025-line-review.json`, `display-releases.json`,
the compact-v1 packages' `geometrySource.officialGeometryComparison`/`verifiedOfficialNetworks`,
and station/geometry recomputed with the real `rail-network.js` (`buildNetworkFromCompactPackage`,
the same call `build-display-lanes.mjs` makes) so part indexes and along-line measures match
exactly what produced the follow rows. `/private/tmp/.../agent-b/results.json` does not exist in
this session; OSM verdicts below come from the row's own `osmVerdicts` field and
`display-releases.json` instead.

## Summary

- reference-warning: 26 lines — 25 KEEP-VISIBLE (line's own geometrySource is a named,
  `verifiedOfficialNetworks`-listed operator/government centreline; OSM/NARN is the coarser
  reference), 1 NEEDS-ALIGNMENT-REVIEW (`metro-transit-intercity-tran-s-line`, whose own
  geometrySource **is** `narn` — the coarse reference itself, not a verified centreline).
- seam-jogs: 25 lines — informational; renderer tapers them at z16 (residual 0 in every case
  checked). 23 of 25 already carry a "corners under half the minimum radius" note in the
  line-review ledger; 2 (`mbta-providence-stoughton-line`, `south-florida-regional-trans-dml`)
  do not (their review passed with no radius issue recorded).
- withheld / osm-confirms-defect: 10 lines — all intervals resolved to station pairs below;
  2 are confirmed defects (verdict B, stays withheld correctly), 8 are unmeasured (verdict D,
  no nearby OSM way to check against — withheld stays fail-closed, appropriately cautious).
- branch-parts: 7 lines — all 7 are REAL-BRANCH (wyes, reversal joints at stub terminals, and
  one streetcar loop closure). 0 SUSPECT-GAP.
- Follow pairs: 221 unique `(line, canonical)` pairs — 221 PLAUSIBLE, 0 DOUBTFUL. 8 of the 221
  are flagged "weak" (the shared run is only a busy terminal throat — Toronto Union Station's
  western approach, or NYC's Sunnyside/Harold Interlocking — where several same-operator lines
  are equally valid canonical partners, so the specific partner chosen is somewhat arbitrary
  but never geographically wrong).

---

## 1. reference-warning (26 lines)

Rule applied: if the line's own `geometrySource` string is listed in the package's
`geometrySource.verifiedOfficialNetworks` (a provenance-verified operator/government
centreline — CTA's own alignment, DART's, NTAD's Amtrak alignment, TTC's, etc.), the
warning means OSM/NARN is the coarser reference and the package correctly kept its better
source: **KEEP-VISIBLE**. If the line's own geometrySource is itself `gtfs-shape` or `narn`
(i.e. it has no better source than the thing it's being compared against), the deviation is
a real open question: **NEEDS-ALIGNMENT-REVIEW**.

| line | geometrySource | dev / limit | reference that disagreed | where | decision |
| --- | --- | ---: | --- | --- | --- |
| `amtrak-amtrak-cascades-us` Amtrak Cascades | `amtrak-ntad-cascades` (verified) | 57.57/50m | narn 1168 vs osm 243 | near Mount Vernon–Bellingham Amtrak stations, WA | KEEP-VISIBLE |
| `amtrak-empire-builder` Empire Builder | `amtrak-ntad-empire-builder` (verified) | 106.68/50m | narn 6982 vs osm 307 | near Cut Bank–Browning–East Glacier Park, MT | KEEP-VISIBLE |
| `cta-blue-line` Blue Line | `cta-blue` (verified) | 29.38/25m | osm 451 | near Division St, between Chicago(Blue) and Damen | KEEP-VISIBLE |
| `dallas-area-rapid-transit-da-blue` | `dart-blue` (verified) | 25.51/25m | osm 264 / narn 114 | near Cityplace/Uptown–SMU/Mockingbird | KEEP-VISIBLE |
| `dallas-area-rapid-transit-da-orange` | `dart-orange` (verified) | 25.51/25m | narn 91 / osm 400 | same Cityplace/Uptown–SMU/Mockingbird shared trunk | KEEP-VISIBLE |
| `dallas-area-rapid-transit-da-red` | `dart-red` (verified) | 26.27/25m | narn 229 / osm 214 | same shared DART trunk | KEEP-VISIBLE |
| `los-angeles-county-metropoli-metro-k-line` Metro K | `la-metro-807` (verified) | 31.79/25m | osm 201 / narn 3 | near Leimert Park–Hyde Park–MLK Jr | KEEP-VISIBLE |
| `mbta-orange-line` Orange Line | `mbta-rapid-orange` (verified) | 35.8/25m | osm 187 / narn 8 | near Back Bay–Tufts Medical Center–Chinatown | KEEP-VISIBLE |
| `metro-transit-intercity-tran-s-line` Sound Transit S Line | **`narn`** (not verified — this IS the coarse reference) | 33.96/30m | osm 297 | near Lakewood–South Tacoma | **NEEDS-ALIGNMENT-REVIEW** |
| `metropolitan-atlanta-rapid-t-blue` MARTA Blue | `marta-blue` (verified) | 45.27/25m | osm 177 / narn 17 | near Ashby–Vine City–West Lake | KEEP-VISIBLE |
| `metropolitan-atlanta-rapid-t-gold` MARTA Gold | `marta-gold` (verified) | 66.77/25m | osm 269 / narn 30 | near Civic Center–North Avenue–Midtown | KEEP-VISIBLE |
| `metropolitan-atlanta-rapid-t-green` MARTA Green | `marta-green` (verified) | 42.45/25m | osm 121 / narn 2 | same Ashby–Vine City shared trunk as Blue | KEEP-VISIBLE |
| `metropolitan-transit-authori-3` NYC 3 | `mta-subway-service-3` (verified) | 36.08/25m | osm 436 | near Grand Army Plaza–Eastern Pkwy–Botanic Garden | KEEP-VISIBLE |
| `metropolitan-transit-authori-a` NYC A | `mta-subway-service-a` (verified) | 25.56/25m | osm 564 | near Jay St-MetroTech–High St–Fulton St | KEEP-VISIBLE |
| `metropolitan-transit-authori-b` NYC B | `mta-subway-service-b` (verified) | 26.04/25m | osm 419 | near 167 St–161 St-Yankee Stadium–155 St | KEEP-VISIBLE |
| `metropolitan-transit-authori-c` NYC C | `mta-subway-service-c` (verified) | 25.56/25m | osm 345 | same Jay St-MetroTech shared trunk as A | KEEP-VISIBLE |
| `metropolitan-transit-authori-d` NYC D | `mta-subway-service-d` (verified) | 26.04/25m | osm 460 / narn 4 | same 167 St–161 St shared trunk as B | KEEP-VISIBLE |
| `metropolitan-transit-authori-fx` NYC F Express | `mta-subway-service-fx` (verified) | 40.68/25m | osm 510 | near Church Av–7 Av–Jay St-MetroTech | KEEP-VISIBLE |
| `metropolitan-transit-authori-g` NYC G | `mta-subway-service-g` (verified) | 32.78/25m | osm 229 | near 15 St-Prospect Park–7 Av–4 Av-9 St | KEEP-VISIBLE |
| `metropolitan-transit-authori-m` NYC M | `mta-subway-service-m` (verified) | 30.25/25m | osm 351 | near Marcy Av–Delancey St-Essex St–Broadway-Lafayette | KEEP-VISIBLE |
| `miami-dade-transit-2600-b1` Metrorail | `miami-metrorail` (verified) | 61.48/30m | osm 38 / narn 1 | near Earlington Hts–Miami Airport Station | KEEP-VISIBLE |
| `wmata-green` Green Line | `wmata-metrorail-green` (verified) | 26.18/25m | osm 306 / narn 2 | near Waterfront–L'Enfant Plaza–Archives | KEEP-VISIBLE |
| `ttc-4` / `ttc-4-b2` Line 4 Sheppard | `ttc-subway-4` (verified) | 34.45m / 34.12m /25m | osm 46 / osm 9 | near Don Mills–Leslie–Bessarion | KEEP-VISIBLE |
| `ttc-306` / `ttc-306-b4` Carlton | `ttc-streetcar-306` (verified) | 22.02m/20m | osm 338 / osm 20 | near Main St–Danforth Ave / Main Street Station | KEEP-VISIBLE |

All 25 KEEP-VISIBLE lines carry a geometrySource string that appears verbatim in that
package's `geometrySource.verifiedOfficialNetworks` list (confirmed by direct lookup against
`us-2025.json`/`ca-2025.json`). The one exception, `metro-transit-intercity-tran-s-line`
(Sound Transit Tacoma–Lakewood S Line), ships on `narn` — the North American Rail Network
fallback layer — with no better independent source, so its 33.96 m disagreement with OSM near
Lakewood/South Tacoma is a genuine open alignment question rather than an expected coarse-vs-fine
mismatch.

---

## 2. seam-jogs (25 lines, informational)

All 25 are survey seams the continuous-stroke engine redraws as tapers; every line checked
has `strokes.z16.residualJogs = 0` (confirmed against `na-2025-display-review.json`), i.e. the
raw jog count never survives to the rendered z16 geometry. 23 of 25 already have a
"corners under half the `<band>` minimum radius" WARN note in `na-2025-line-review.json`;
the raw→residual count and the note's corner count are independent diagnostics of the same
underlying tight curvature, not duplicates.

| line | seam-jogs | radius note already present? |
| --- | ---: | --- |
| `amtrak-adirondack-us` | 2 | yes — 13 corners under half the longhaul 500m minimum |
| `amtrak-amtrak-cascades-us` | 2 | yes — 11 corners under half the longhaul 640m minimum |
| `amtrak-borealis` | 1 | yes — 5 corners under half the longhaul 640m minimum |
| `amtrak-capitol-corridor` | 1 | yes — 5 corners under half the regional 250m minimum |
| `amtrak-carolinian` | 2 | yes — 11 corners under half the longhaul 640m minimum |
| `amtrak-empire-builder` | 4 | yes — 52 corners under half the longhaul 800m minimum |
| `amtrak-empire-service` | 3 | yes — 10 corners under half the longhaul 640m minimum |
| `amtrak-ethan-allen-express` | 2 | yes — 9 corners under half the longhaul 500m minimum (see branch-parts §3) |
| `amtrak-hiawatha-service` | 1 | yes — 3 corners under half the longhaul 400m minimum |
| `amtrak-lake-shore-limited-b1` | 1 | yes — 3 corners under half the longhaul 500m minimum |
| `amtrak-lincoln-service-missouri-river-runner` | 1 | yes — 3 corners under half the longhaul 640m minimum |
| `amtrak-missouri-river-runner` | 1 | yes — 2 corners under half the longhaul 500m minimum |
| `amtrak-palmetto` | 2 | yes — 15 corners under half the longhaul 640m minimum |
| `amtrak-piedmont` | 1 | yes — 2 corners under half the longhaul 500m minimum |
| `amtrak-southwest-chief` | 2 | yes — 64 corners under half the longhaul 800m minimum (see withheld §4) |
| `amtrak-vermonter` | 1 | yes — 32 corners under half the longhaul 640m minimum (see withheld §4) |
| `connecticut-transit-hartford-line` | 1 | yes — 3 corners under half the regional 200m minimum |
| `mbta-foxboro-event-service` | 1 | yes — 2 corners under half the regional 200m minimum |
| `mbta-providence-stoughton-line` | 1 | **no** — review passed with no radius issue |
| `metro-north-railroad-danbury` | 1 | yes — 2 corners under half the regional 200m minimum |
| `north-county-transit-distric-sprinter` | 1 | yes — 2 corners under half the commuter 80m minimum |
| `port-authority-trans-hudson-world-trade-center-33rd-street` | 1 | yes — 3 corners under half the metro 30m minimum |
| `south-florida-regional-trans-dml` | 1 | **no** — review passed with no radius issue |
| `south-florida-regional-trans-mce` | 1 | yes — 3 corners under half the longhaul 400m minimum (see withheld §4) |
| `utah-transit-authority-uta-704-b1` | 1 | yes — 7 corners under half the commuter 80m minimum |

---

## 3. branch-parts (7 lines — all REAL-BRANCH)

Checked each line's `displayPartsForLine` output (via the real `rail-network.js`) against its
station order. Every case is a genuine wye/spur, a reversal joint at a stub-end terminal, or a
streetcar loop closure — none is a broken/disconnected chain.

| line | parts | shape | decision |
| --- | --- | --- | --- |
| `amtrak-ethan-allen-express` | Burlington↔Rutland, Rutland↔NY Penn (Moynihan) | Rutland, VT is a documented reversal point — Ethan Allen Express trains back in/out there; the two parts meet exactly (0m) at Rutland | REAL-BRANCH (reversal joint) |
| `amtrak-valley-flyer` | New Haven↔Springfield, Springfield↔Greenfield | Springfield Union Station is a stub-end terminal; New Haven–Springfield–Greenfield trains reverse there (same as Vermonter) | REAL-BRANCH (reversal joint) |
| `bart-red` | Millbrae↔SFO (25 vertices, 2.7km spur), SFO↔Richmond (544 vertices, trunk) | SFO is served by BART's wye off the main Peninsula line; trains from Millbrae detour out to SFO and back before continuing north | REAL-BRANCH (wye spur) |
| `mta-long-island-rail-road-city-terminal-zone` | Grand Central↔Jamaica, Jamaica↔Atlantic Terminal | Genuine fork at Jamaica: one leg to Manhattan (Grand Central Madison via the Main Line/East Side Access), the other to Brooklyn (Atlantic Terminal via the Atlantic Branch) | REAL-BRANCH (fork at Jamaica) |
| `new-jersey-transit-nj-transi-nlr` Newark Light Rail | Grove St↔Penn Station Newark (12 stns, original City Subway), Penn Station↔Broad St (4 stns) | Matches real Newark Light Rail geography: the 2006 Broad Street Extension diverges from the original City Subway at Newark Penn Station | REAL-BRANCH (branch at Penn Station Newark) |
| `port-authority-trans-hudson-journal-square-33rd-street-via-hoboken` | Christopher St↔Hoboken (reversed lead-in), Journal Square↔33rd St | Hoboken Terminal is stub-ended; PATH's JSQ–33rd-via-Hoboken service genuinely reverses there to reach the separate Hoboken–33rd tunnel | REAL-BRANCH (reversal joint at Hoboken) |
| `ttc-509` Harbourfront | Union Station↔Exhibition Loop (3.9km), Exhibition Loop↔Exhibition Loop at Manitoba Dr (57m) | The 57m second part is the physical loop closure at Exhibition Loop — exactly the "a loop closing" case | REAL-BRANCH (loop closure) |

0 SUSPECT-GAP. This also accounts for all 7 lines in the review's `branch-parts | 7` summary count.

---

## 4. withheld / osm-confirms-defect (10 lines)

Station pairs and OSM verdicts pulled from `display-releases.json` where available (exact,
with median/max deviation and a human note) and otherwise resolved directly from each line's
own station order at the interval index.

| line | interval(s) | station pair | verdict | note |
| --- | --- | --- | --- | --- |
| `amtrak-pennsylvanian` | 13 (stays withheld); 6,12 released | Philadelphia↔Trenton | **B — osm-confirms-defect** | "Localised defect near Zoo interlocking, West Philadelphia: one interpolated sample 277m off while the other 33 points are within 16m — a chord or misrouting across the curve." Display draws this interval from the reviewed Amtrak shared-station-interval canonical instead. |
| `amtrak-southwest-chief` | 17,23,25,28 (stay withheld); 7,9,11,14 released | Raton↔Las Vegas NM; Flagstaff↔Kingman; Needles↔Barstow; San Bernardino↔Riverside-Downtown | D — not measured | No nearby OSM way to check against for the 4 still-withheld intervals; fail-closed is the correct conservative choice given no evidence either way. |
| `amtrak-vermonter` | 1,17,26 (stay withheld); 25 released | Essex Junction-Burlington↔Waterbury-Stowe; New Haven↔Bridgeport; Baltimore Penn↔BWI Airport | D — not measured | Same: no evidence to release on, withheld correctly. |
| `bart-blue` / `bart-green` | 9 (stays withheld) | West Oakland↔Lake Merritt | **D** (row says stillWithheld, osmVerdict `9:D`) | Both lines share the same interval/geometry through the Oakland core; not measured, stays withheld. |
| `maryland-transit-administrat-brunswick-washington` | 11,13 (stay withheld); 15 released | Dickerson MARC↔Point of Rocks MARC; Brunswick MD MARC↔Harpers Ferry WV MARC | D — not measured | Not measured; withheld correctly. |
| `nashville-mta-wego-public-tr-90` WeGo Star | 2 | Martha Station↔Mt. Juliet Station | **B — osm-confirms-defect** | "Chord across a curve: package vertices sit on a constant bearing at exactly 240m spacing while the OSM Nashville & Eastern way curves; sustained 67m off." |
| `south-florida-regional-trans-mce` | 1 | Metrorail Transfer Station↔Ft Lauderdale Airport Station | D — not measured | Withheld correctly, no evidence. |
| `south-shore-line-lakeshore` | 5 | Hegewisch↔Hammond Gateway | D — not measured | Withheld correctly. |
| `via-ottawa-montr-al` | 0 | Montréal↔Dorval | D — not measured | Withheld correctly. |

Both confirmed defects (`amtrak-pennsylvanian` interval 13, `nashville-mta-wego-public-tr-90`
interval 2) are appropriately kept off-display, with a documented chord/misrouting cause. All 8
D-verdict intervals across the other 8 lines are simply unmeasured (no OSM way nearby), so the
fail-closed default is the correct, conservative behaviour — none of these are evidence of a bad
geometry, just absent evidence.

---

## 5. Follow pairs (221 unique line→canonical pairs, 259 raw rows)

Every follow row already passed the build's own filter (median lateral offset ≤25m,
sustained ≥1km, on a reviewed shared-corridors policy), so it is expected that the large
majority check out. For each pair, station names were resolved along BOTH lines' real
`buildNetworkFromCompactPackage` geometry at the exact from/to measures recorded in
`display-lanes.json` (matching the same part index and withheld-interval splits the
build used), then checked against known network geography. Result: **221/221 PLAUSIBLE,
0 DOUBTFUL.** 8 pairs are marked weak (shared run is only a busy multi-line terminal throat
— Toronto Union Station's western approach, or NYC's Sunnyside/Harold Interlocking — where
several same-operator lines would match equally well, so the specific canonical partner
picked is somewhat arbitrary, though never geographically wrong).

### Toronto/Southern Ontario (28 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `go-transit-br` | `go-transit-lw` | Union Station GO | Union Station GO | 1944m (1row) | PLAUSIBLE |
| `go-transit-ki` | `go-transit-br` | Union Station GO, Bloor GO | Downsview Park GO, Union Station GO | 3300m (1row) | PLAUSIBLE (weak: shared Union Station western throat only) |
| `go-transit-ki` | `go-transit-lw` | Union Station GO | Union Station GO | 1925m (1row) | PLAUSIBLE |
| `go-transit-ki` | `go-transit-mi` | Bloor GO | Kipling GO, Union Station GO | 2375m (1row) | PLAUSIBLE (weak: shared Union Station western throat only (Bloor GO area); several GO lines converge here) |
| `go-transit-lw-b1` | `go-transit-lw` | Aldershot | Aldershot | 4850m (1row) | PLAUSIBLE |
| `go-transit-mi` | `go-transit-br` | Union Station GO | Union Station GO | 5195m (1row) | PLAUSIBLE |
| `go-transit-rh` | `go-transit-le` | Union Station GO | Union Station GO | 2500m (1row) | PLAUSIBLE |
| `go-transit-st` | `go-transit-le` | Union Station GO | Union Station GO, Danforth GO, Scarborough GO | 14233m (1row) | PLAUSIBLE |
| `grt-ion-light-rail-301-b2` | `grt-ion-light-rail-301` | Willis Way Station, Laurier-Waterloo Park Station | Waterloo Public Square Station, Laurier-Waterloo Park Station | 1001m (1row) | PLAUSIBLE |
| `ttc-304-b1` | `ttc-304` | King St East at Church St, King St West at Yonge St East Side - King Station, King St West at Bay St | King St West at Jarvis St, King St East at Church St, King St West at Yonge St West Side - King Station | 1844m (1row) | PLAUSIBLE |
| `ttc-4-b1` | `ttc-4` | Don Mills Station, Leslie Station | Don Mills Station, Leslie Station | 1486m (1row) | PLAUSIBLE |
| `ttc-5-b1` | `ttc-5` | Birchmount Station, Golden Mile Station, Hakimi Lebovic Station | Birchmount Station, Golden Mile Station, Hakimi Lebovic Station | 1656m (1row) | PLAUSIBLE |
| `ttc-5-b2` | `ttc-5` | Forest Hill Station, Cedarvale Station, Oakwood Station | Forest Hill Station, Cedarvale Station, Oakwood Station | 1479m (1row) | PLAUSIBLE |
| `ttc-509` | `ttc-310` | Union Station, Queens Quay/Ferry Docks Station, Queens Quay West at Harbourfront Centre | Union Station, Queens Quay/Ferry Docks Station, Queens Quay West at Harbourfront Centre | 1850m (1row) | PLAUSIBLE |
| `ttc-509` | `ttc-511` | Queens Quay West at Dan Leckie Way, Bathurst St at Queens Quay West North Side Billy Bishop Airport, Fleet St at Bathurst St | Bathurst St at Fort York Blvd, Fleet St at Bathurst St, Fleet St at Bastion St | 1359m (1row) | PLAUSIBLE |
| `union-pearson-express-up-exp-up` | `go-transit-br` | UP Express Union Station, Bloor GO | Downsview Park GO, Union Station GO | 3350m (1row) | PLAUSIBLE (weak: shared Union Station western throat only) |
| `union-pearson-express-up-exp-up` | `go-transit-ki` | Mount Dennis GO, Weston GO | Mount Dennis GO, Weston GO, Etobicoke North GO | 14100m (1row) | PLAUSIBLE |
| `union-pearson-express-up-exp-up` | `go-transit-lw` | UP Express Union Station | Union Station GO | 1625m (1row) | PLAUSIBLE |
| `union-pearson-express-up-exp-up` | `go-transit-mi` | Bloor GO | Kipling GO, Union Station GO | 2375m (1row) | PLAUSIBLE (weak: shared Union Station western throat only (Bloor GO area)) |
| `via-toronto-london` | `go-transit-br` | Union Station GO, Aldershot | Downsview Park GO, Union Station GO | 1100m (1row) | PLAUSIBLE (weak: shared Union Station western throat only) |
| `via-toronto-london` | `go-transit-lw` | Aldershot | Exhibition GO, Mimico GO, Long Branch GO | 57300m (1row) | PLAUSIBLE |
| `via-toronto-london` | `via-toronto-windsor` | Brantford, Woodstock, London | Brantford, Woodstock, Ingersoll | 125347m (1row) | PLAUSIBLE |
| `via-toronto-sarnia` | `go-transit-br` | Union Station GO | Union Station GO | 5250m (1row) | PLAUSIBLE |
| `via-toronto-sarnia` | `go-transit-ki` | Malton, Brampton, Georgetown | Mount Dennis GO, Weston GO, Etobicoke North GO | 134650m (1row) | PLAUSIBLE |
| `via-toronto-sarnia` | `go-transit-mi` | Union Station GO, Malton | Kipling GO, Union Station GO | 2375m (1row) | PLAUSIBLE (weak: shared Union Station western throat only) |
| `via-toronto-sarnia` | `via-toronto-windsor` | London | London | 18500m (1row) | PLAUSIBLE |
| `via-toronto-windsor` | `go-transit-br` | Union Station GO, Oakville | Downsview Park GO, Union Station GO | 1075m (1row) | PLAUSIBLE (weak: shared Union Station western throat only) |
| `via-toronto-windsor` | `go-transit-lw` | Oakville, Aldershot | Exhibition GO, Mimico GO, Long Branch GO | 57300m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity (24 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-adirondack-us` | `amtrak-lake-shore-limited` | Schenectady, Albany-Rensselaer Amtrak Station | Albany-Rensselaer Amtrak Station, Schenectady | 28925m (1row) | PLAUSIBLE |
| `amtrak-adirondack-us` | `amtrak-lake-shore-limited-b1` | Hudson Amtrak Station, Rhinecliff Amtrak Station, Poughkeepsie Amtrak Station | Ny Moynihan Train Hall At Penn Station, Croton-Harmon Amtrak Station, Poughkeepsie Amtrak Station | 226458m (1row) | PLAUSIBLE |
| `amtrak-amtrak-cascades-us` | `amtrak-empire-builder` | Edmonds, Everett Amtrak Station | Edmonds, Seattle | 53875m (1row) | PLAUSIBLE |
| `amtrak-borealis` | `amtrak-hiawatha-service` | Chicago Union Station, Glenview Amtrak Station, Sturtevant Amtrak Station | Milwaukee, General Mitchell Intl. Airport Amtrak Station, Sturtevant Amtrak Station | 138025m (1row) | PLAUSIBLE |
| `amtrak-carl-sandburg` | `amtrak-southwest-chief` | Plano Amtrak Station, Mendota Amtrak Station, Princeton Amtrak Station | Mendota Amtrak Station, Princeton Amtrak Station, Galesburg Amtrak Station | 202275m (1row) | PLAUSIBLE |
| `amtrak-carolinian` | `amtrak-palmetto` | Newark, Metropark Amtrak Station, NEW Brunswick | Newark, Metropark Amtrak Station, Trenton | 789625m (2rows) | PLAUSIBLE |
| `amtrak-empire-builder` | `amtrak-borealis` | Milwaukee, Columbus Amtrak Station, Portage | Milwaukee, Columbus Amtrak Station, Portage | 515575m (9rows) | PLAUSIBLE |
| `amtrak-empire-builder` | `amtrak-hiawatha-service` | Chicago Union Station, Glenview Amtrak Station, Milwaukee | Glenview Amtrak Station, Chicago Union Station, Milwaukee | 137325m (2rows) | PLAUSIBLE |
| `amtrak-empire-builder-b1` | `amtrak-amtrak-cascades-us` | Portland | Portland, Vancouver | 16044m (1row) | PLAUSIBLE |
| `amtrak-empire-builder-b1` | `amtrak-empire-builder` | Spokane | Spokane, Ephrata Amtrak | 2925m (1row) | PLAUSIBLE |
| `amtrak-empire-service` | `amtrak-lake-shore-limited` | Buffalo Depew Station, Rochester, Ny State Fair | Rochester, Buffalo Depew Station, Albany-Rensselaer Amtrak Station | 476475m (2rows) | PLAUSIBLE |
| `amtrak-empire-service` | `amtrak-lake-shore-limited-b1` | Hudson Amtrak Station, Rhinecliff Amtrak Station, Poughkeepsie Amtrak Station | Ny Moynihan Train Hall At Penn Station, Croton-Harmon Amtrak Station, Poughkeepsie Amtrak Station | 226453m (1row) | PLAUSIBLE |
| `amtrak-ethan-allen-express` | `amtrak-adirondack-us` | Fort Edward Amtrak, Saratoga Springs Amtrak Station, Schenectady | Fort Edward Amtrak, Saratoga Springs Amtrak Station, Schenectady | 352323m (1row) | PLAUSIBLE |
| `amtrak-ethan-allen-express` | `amtrak-ethan-allen-express` | Rutland | Castleton Amtrak Station, Castleton Amtrak Station | 2233m (1row) | PLAUSIBLE |
| `amtrak-lincoln-service-missouri-river-runner` | `amtrak-southwest-chief` | Kansas City | Kansas City | 8496m (1row) | PLAUSIBLE |
| `amtrak-missouri-river-runner` | `amtrak-lincoln-service-missouri-river-runner` | Independence Amtrak Station, Lee'S Summit Amtrak, Warrensburg Amtrak Station | Kirkwood Amtrak Station, Washington Amtrak Station, Hermann | 438555m (1row) | PLAUSIBLE |
| `amtrak-missouri-river-runner` | `amtrak-southwest-chief` | Kansas City | Kansas City | 8525m (1row) | PLAUSIBLE |
| `amtrak-pennsylvanian` | `amtrak-palmetto` | Trenton, Newark, Ny Moynihan Train Hall At Penn Station | Ny Moynihan Train Hall At Penn Station, Newark, Metropark Amtrak Station | 145304m (1row) | PLAUSIBLE |
| `amtrak-piedmont` | `amtrak-carolinian` | Charlotte Amtrak Station, Kannapolis, Salisbury | Cary, Durham Amtrak Station, Burlington Amtrak Station | 277205m (1row) | PLAUSIBLE |
| `amtrak-valley-flyer` | `amtrak-shore-line-east` | New Haven | New Haven | 3700m (1row) | PLAUSIBLE |
| `amtrak-vermonter` | `amtrak-palmetto` | Newark, Metropark Amtrak Station, Trenton | Newark, Metropark Amtrak Station, Trenton | 281675m (1row) | PLAUSIBLE |
| `amtrak-vermonter` | `amtrak-shore-line-east` | Bridgeport, Stamford | New Haven, Bridgeport, Stamford | 62850m (2rows) | PLAUSIBLE |
| `amtrak-vermonter` | `amtrak-valley-flyer` | Greenfield Amtrak Station, Northampton, Holyoke Amtrak | Holyoke Amtrak, Northampton, Greenfield Amtrak Station | 156200m (2rows) | PLAUSIBLE |
| `amtrak-wolverine` | `amtrak-lake-shore-limited` | Hammond-Whiting Amtrak Station | South Bend Amtrak Station, Chicago Union Station | 57100m (1row) | PLAUSIBLE |

### NYC/NJ Transit (21 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `new-jersey-transit-nj-transi-bntn` | `new-jersey-transit-nj-transi-mne` | Newark Broad ST, Denville, Dover | Newark Broad ST, Hackettstown, Mount Olive | 42716m (2rows) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-bntn` | `new-jersey-transit-nj-transi-njcl` | NEW YORK PENN Station, Secaucus Upper Level | NEW YORK PENN Station, Secaucus Upper Level | 13900m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-bntn-b1` | `new-jersey-transit-nj-transi-mnbnp` | Hoboken | Hoboken | 3375m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-bntn-b1` | `new-jersey-transit-nj-transi-mneg` | Newark Broad ST | Newark Broad ST | 9110m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mnbn` | `new-jersey-transit-nj-transi-mnbnp` | Suffern, Mahwah, Ramsey Route 17 Station | Suffern, Mahwah, Ramsey Route 17 Station | 24675m (2rows) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mnbn-b1` | `new-jersey-transit-nj-transi-mnbnp` | Ridgewood, GLEN ROCK BORO HALL, Radburn | Ridgewood, GLEN ROCK BORO HALL, Radburn | 26216m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mnbnp-b1` | `new-jersey-transit-nj-transi-mnbn` | GLEN ROCK MAIN LINE, Hawthorne, Paterson | GLEN ROCK MAIN LINE, Hawthorne, Paterson | 26518m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mnbnp-b1` | `new-jersey-transit-nj-transi-mnbnp` | Ridgewood | Ridgewood | 1475m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mne` | `new-jersey-transit-nj-transi-njcl` | Secaucus Upper Level, NEW YORK PENN Station | NEW YORK PENN Station, Secaucus Upper Level | 13890m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mne-b1` | `new-jersey-transit-nj-transi-mne` | Newark Broad ST | Newark Broad ST | 4200m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mne-b1` | `new-jersey-transit-nj-transi-mneg` | Hoboken | Hoboken | 8285m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mneg` | `new-jersey-transit-nj-transi-mnbnp` | Hoboken | Hoboken | 3375m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mneg` | `new-jersey-transit-nj-transi-mne` | Newark Broad ST, EAST Orange, Brick Church | Summit, Short Hills, Millburn | 25700m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mneg-b1` | `new-jersey-transit-nj-transi-mne` | Brick Church | Brick Church, EAST Orange, Newark Broad ST | 8000m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mneg-b1` | `new-jersey-transit-nj-transi-njcl` | NEW YORK PENN Station | NEW YORK PENN Station, Secaucus Upper Level | 13175m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mneg-b2` | `new-jersey-transit-nj-transi-mne` | Maplewood | Maplewood, South Orange, Mountain Station | 14723m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mneg-b2` | `new-jersey-transit-nj-transi-njcl` | NEW YORK PENN Station, Secaucus Upper Level | NEW YORK PENN Station, Secaucus Upper Level | 13850m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-mrl` | `new-jersey-transit-nj-transi-pasc` | Secaucus Lower Level, Hoboken | Hoboken, Secaucus Lower Level | 14014m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-nec` | `new-jersey-transit-nj-transi-njcl` | NEW YORK PENN Station, Secaucus Upper Level, Newark | NEW YORK PENN Station, Secaucus Upper Level, Newark | 34600m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-pasc` | `new-jersey-transit-nj-transi-mnbnp` | Hoboken, Secaucus Lower Level | Secaucus Lower Level, Hoboken | 12750m (1row) | PLAUSIBLE |
| `new-jersey-transit-nj-transi-rarv` | `new-jersey-transit-nj-transi-njcl` | NEW YORK PENN Station, Secaucus Upper Level, Newark | NEW YORK PENN Station, Secaucus Upper Level, Newark | 19150m (1row) | PLAUSIBLE |

### Boston MBTA (20 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `mbta-b` | `mbta-d` | Blandford Street, Kenmore, Hynes Convention Center | Kenmore, Hynes Convention Center, Copley | 6750m (1row) | PLAUSIBLE |
| `mbta-c` | `mbta-b` | East Somerville, Gilman Square, Magoun Square | East Somerville, Gilman Square, Magoun Square | 4691m (1row) | PLAUSIBLE |
| `mbta-c` | `mbta-d` | Kenmore, Hynes Convention Center, Copley | Fenway, Kenmore, Hynes Convention Center | 7150m (1row) | PLAUSIBLE |
| `mbta-capeflyer` | `mbta-providence-stoughton-line-b5` | South Station | South Station | 1780m (1row) | PLAUSIBLE |
| `mbta-e` | `mbta-b` | Medford/Tufts, Ball Square, Magoun Square | Copley, Arlington, Boylston | 9900m (1row) | PLAUSIBLE |
| `mbta-e-b1` | `mbta-d` | Union Square, Lechmere | Lechmere, Union Square | 1684m (1row) | PLAUSIBLE |
| `mbta-fairmount-line` | `mbta-providence-stoughton-line-b5` | Readville, Fairmount, Blue Hill Avenue | Fairmount, Blue Hill Avenue, Morton Street | 14690m (1row) | PLAUSIBLE |
| `mbta-fall-river-new-bedford-line` | `mbta-capeflyer` | JFK/UMass, Quincy Center, Braintree | Brockton, Braintree | 54250m (1row) | PLAUSIBLE |
| `mbta-fall-river-new-bedford-line` | `mbta-providence-stoughton-line-b5` | South Station | South Station | 1775m (1row) | PLAUSIBLE |
| `mbta-fall-river-new-bedford-line-b1` | `mbta-fall-river-new-bedford-line` | East Taunton | East Taunton | 5300m (1row) | PLAUSIBLE |
| `mbta-foxboro-event-service` | `mbta-providence-stoughton-line` | Providence, Pawtucket/Central Falls, Attleboro | Providence, Pawtucket/Central Falls, South Attleboro | 45839m (2rows) | PLAUSIBLE |
| `mbta-framingham-worcester-line` | `mbta-providence-stoughton-line` | Back Bay | Back Bay | 1475m (1row) | PLAUSIBLE |
| `mbta-greenbush-line` | `mbta-capeflyer` | Quincy Center, JFK/UMass, South Station | South Station | 16341m (1row) | PLAUSIBLE |
| `mbta-haverhill-line` | `mbta-newburyport-rockport-line` | North Station | North Station | 3165m (1row) | PLAUSIBLE |
| `mbta-kingston-line` | `mbta-capeflyer` | JFK/UMass, Quincy Center, Braintree | Braintree | 16750m (1row) | PLAUSIBLE |
| `mbta-kingston-line` | `mbta-providence-stoughton-line-b5` | South Station | South Station | 1775m (1row) | PLAUSIBLE |
| `mbta-lowell-line` | `mbta-newburyport-rockport-line` | North Station | North Station | 1729m (1row) | PLAUSIBLE |
| `mbta-needham-line` | `mbta-providence-stoughton-line` | Forest Hills, Ruggles, Back Bay | Forest Hills, Ruggles, Back Bay | 8536m (1row) | PLAUSIBLE |
| `mbta-newburyport-rockport-line` | `mbta-fitchburg-line` | North Station | North Station | 1075m (1row) | PLAUSIBLE |
| `mbta-providence-stoughton-line` | `mbta-providence-stoughton-line-b5` | Route 128, Readville | Route 128 | 3175m (1row) | PLAUSIBLE |

### NYC Subway (MTA) (19 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `metropolitan-transit-authori-1` | `metropolitan-transit-authori-3` | 103 St, 96 St, 86 St | 96 St, 72 St, 66 St-Lincoln Center | 10400m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-3` | `metropolitan-transit-authori-b` | Atlantic Av-Barclays Ctr, Bergen St, Grand Army Plaza | Atlantic Av-Barclays Ctr, 7 Av | 1325m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-6x` | `metropolitan-transit-authori-6` | Pelham Bay Park, Buhre Av, Middletown Rd | Pelham Bay Park, Buhre Av, Middletown Rd | 24081m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-7x` | `metropolitan-transit-authori-7` | Flushing-Main St, Mets-Willets Point, Junction Blvd | Flushing-Main St, Mets-Willets Point, 111 St | 16551m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-a-b2` | `metropolitan-transit-authori-rockaway-park-shuttle` | Rockaway Park-Beach 116 St, Beach 105 St, Beach 98 St | Rockaway Park-Beach 116 St, Beach 105 St, Beach 98 St | 4536m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-b` | `metropolitan-transit-authori-d` | Bedford Park Blvd, Kingsbridge Rd, Fordham Rd | Bedford Park Blvd, Kingsbridge Rd, Fordham Rd | 25950m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-c` | `metropolitan-transit-authori-a` | Euclid Av, Shepherd Av, Van Siclen Av | Euclid Av, Shepherd Av, Van Siclen Av | 29896m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-d` | `metropolitan-transit-authori-a` | 145 St, 125 St, 59 St-Columbus Circle | 59 St-Columbus Circle, 72 St, 81 St-Museum of Natural History | 7825m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-d` | `metropolitan-transit-authori-fx` | 7 Av, 47-50 Sts-Rockefeller Ctr, 42 St-Bryant Pk | 2 Av, Broadway-Lafayette St, W 4 St-Wash Sq | 5200m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-g` | `metropolitan-transit-authori-a` | Hoyt-Schermerhorn Sts, Fulton St | Lafayette Av, Hoyt-Schermerhorn Sts | 1100m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-g` | `metropolitan-transit-authori-fx` | Church Av, Fort Hamilton Pkwy, 15 St-Prospect Park | Church Av, 7 Av | 6525m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-j` | `metropolitan-transit-authori-m` | Bowery, Delancey St-Essex St, Marcy Av | Myrtle Av, Flushing Av, Lorimer St | 5600m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-m` | `metropolitan-transit-authori-d` | Broadway-Lafayette St, W 4 St-Wash Sq, 14 St | 7 Av, 47-50 Sts-Rockefeller Ctr, 42 St-Bryant Pk | 5575m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-m` | `metropolitan-transit-authori-fx` | 36 St | Queens Plaza | 1025m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-m` | `metropolitan-transit-authori-r` | Steinway St, 46 St, Northern Blvd | Forest Hills-71 Av, 67 Av, 63 Dr-Rego Park | 8406m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-r` | `metropolitan-transit-authori-d` | Jay St-MetroTech, DeKalb Av, Atlantic Av-Barclays Ctr | DeKalb Av, Atlantic Av-Barclays Ctr, Union St | 5200m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-r` | `metropolitan-transit-authori-fx` | Forest Hills-71 Av, 67 Av, 63 Dr-Rego Park | Jackson Hts-Roosevelt Av, Forest Hills-71 Av, Queens Plaza | 8100m (2rows) | PLAUSIBLE |
| `metropolitan-transit-authori-rockaway-park-shuttle` | `metropolitan-transit-authori-a` | Broad Channel, Howard Beach-JFK Airport, Aqueduct-N Conduit Av | Broad Channel, Howard Beach-JFK Airport, Aqueduct-N Conduit Av | 10549m (1row) | PLAUSIBLE |
| `metropolitan-transit-authori-z` | `metropolitan-transit-authori-j` | Jamaica Center-Parsons/Archer, Jamaica, 121 St | Broad St, Fulton St, Chambers St | 21417m (1row) | PLAUSIBLE |

### Chicago (9 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `cta-orange-line` | `cta-green-line` | Roosevelt, Harold Washington Library-State/Van Buren | Adams/Wabash, Roosevelt | 2175m (1row) | PLAUSIBLE |
| `metra-bnsf` | `metra-sws` | Chicago Union Station | Chicago Union Station | 1925m (1row) | PLAUSIBLE |
| `metra-hc` | `metra-sws` | Chicago Union Station | Chicago Union Station | 2700m (1row) | PLAUSIBLE |
| `metra-milwaukee` | `metra-ncs` | Chicago Union Station, Western Ave | Western Ave, Chicago Union Station | 9000m (1row) | PLAUSIBLE |
| `metra-milwaukee-2` | `metra-ncs` | Chicago Union Station, Western Ave, Grand/Cicero | River Grove, Western Ave, Chicago Union Station | 20700m (1row) | PLAUSIBLE |
| `metra-ncs` | `metra-union-pacific-2` | Western Ave | Chicago OTC, Kedzie | 2150m (1row) | PLAUSIBLE |
| `metra-ri-b2` | `metra-ri` | 35th St. - Lou Jones | 35th St. - Lou Jones, Gresham | 11200m (1row) | PLAUSIBLE |
| `metra-ri-b2` | `metra-ri-b1` | 95th St.-Longwood | 95th St.-Longwood | 1305m (1row) | PLAUSIBLE |
| `metra-up-nw-b1` | `metra-up-nw` | Pingree Road | Pingree Road | 1450m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity / Chicago (8 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-carl-sandburg` | `metra-bnsf` | LaGrange Road, Naperville Amtrak Station | Halsted Street, Western Avenue, Cicero | 56675m (1row) | PLAUSIBLE |
| `amtrak-carl-sandburg` | `metra-sws` | Chicago Union Station | Chicago Union Station | 1950m (1row) | PLAUSIBLE |
| `amtrak-hiawatha-service` | `metra-milwaukee` | Glenview Amtrak Station, Chicago Union Station | Chicago Union Station, Western Ave, Healy | 52575m (1row) | PLAUSIBLE |
| `amtrak-lake-shore-limited` | `metra-sws` | Chicago Union Station | Chicago Union Station | 7600m (1row) | PLAUSIBLE |
| `amtrak-lincoln-service-missouri-river-runner` | `metra-sws` | Chicago Union Station | Chicago Union Station | 2625m (1row) | PLAUSIBLE |
| `amtrak-southwest-chief` | `metra-bnsf` | Naperville Amtrak Station | Halsted Street, Western Avenue, Cicero | 56150m (2rows) | PLAUSIBLE |
| `amtrak-southwest-chief` | `metra-sws` | Chicago Union Station | Chicago Union Station | 1925m (1row) | PLAUSIBLE |
| `amtrak-wolverine` | `metra-sws` | Chicago Union Station | Chicago Union Station | 7600m (1row) | PLAUSIBLE |

### DC (WMATA/MARC) (8 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `maryland-transit-administrat-brunswick-washington` | `maryland-transit-administrat-brunswick-washington-b2` | GERMANTOWN MARC, BOYDS MARC, BARNESVILLE MARC | GERMANTOWN MARC | 14356m (1row) | PLAUSIBLE |
| `maryland-transit-administrat-brunswick-washington` | `maryland-transit-administrat-camden-washington` | UNION STATION MARC Washington | UNION STATION MARC Washington | 1450m (1row) | PLAUSIBLE |
| `maryland-transit-administrat-brunswick-washington-b1` | `maryland-transit-administrat-brunswick-washington-b2` | DICKERSON MARC, MONOCACY MARC | MONOCACY MARC | 29500m (1row) | PLAUSIBLE |
| `maryland-transit-administrat-brunswick-washington-b3` | `maryland-transit-administrat-brunswick-washington-b2` | BARNESVILLE MARC, MONOCACY MARC | MONOCACY MARC | 33134m (1row) | PLAUSIBLE |
| `maryland-transit-administrat-camden-washington` | `maryland-transit-administrat-penn-washington` | UNION STATION MARC Washington | UNION STATION MARC Washington | 3300m (2rows) | PLAUSIBLE |
| `wmata-orange` | `wmata-blue` | Stadium-armory Metrorail Station, Potomac AVE Metrorail Station, Eastern Market Metrorail Station | Stadium-armory Metrorail Station, Potomac AVE Metrorail Station, Eastern Market Metrorail Station | 13825m (1row) | PLAUSIBLE |
| `wmata-yellow` | `wmata-blue` | Pentagon Metrorail Station, Pentagon CITY Metrorail Station, Crystal CITY Metrorail Station | Pentagon Metrorail Station, Pentagon CITY Metrorail Station, Crystal CITY Metrorail Station | 9875m (1row) | PLAUSIBLE |
| `wmata-yellow` | `wmata-green` | MT Vernon SQ Metrorail Station, Gallery Place Metrorail Station, Archives Metrorail Station | L'enfant Plaza, Archives Metrorail Station, Gallery Place Metrorail Station | 2800m (1row) | PLAUSIBLE |

### LA (8 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `los-angeles-county-metropoli-metro-e-line` | `los-angeles-county-metropoli-metro-a-line` | Little Tokyo / Arts District Station, Historic Broadway Station, Grand Ave Arts / Bunker Hill Station | Little Tokyo / Arts District Station, Historic Broadway Station, Grand Ave Arts / Bunker Hill Station | 4525m (1row) | PLAUSIBLE |
| `los-angeles-county-metropoli-metro-k-line` | `los-angeles-county-metropoli-metro-c-line` | LAX / Metro Transit Center, Aviation / Century Station | Aviation / Imperial Station, Aviation / Century Station, LAX / Metro Transit Center | 2225m (1row) | PLAUSIBLE |
| `metrolink-91-pv-line` | `metrolink-ie-oc-line` | Corona, Corona - North Main, Riverside - La Sierra | Corona, Corona - North Main, Riverside - La Sierra | 54350m (1row) | PLAUSIBLE |
| `metrolink-91-pv-line` | `metrolink-oc-line` | Norwalk / Santa Fe Springs, Buena Park, Fullerton | Fullerton, Buena Park, Norwalk / Santa Fe Springs | 40825m (1row) | PLAUSIBLE |
| `metrolink-91-pv-line` | `metrolink-sb-line` | L.A. Union Station | L.A. Union Station | 1025m (1row) | PLAUSIBLE |
| `metrolink-ie-oc-line` | `metrolink-sb-line` | San Bernardino Depot, San Bernardino - Downtown | San Bernardino Depot, San Bernardino - Downtown | 2140m (1row) | PLAUSIBLE |
| `metrolink-oc-line` | `metrolink-ie-oc-line` | Oceanside, San Clemente Pier, San Clemente | Oceanside, San Clemente Pier, San Clemente | 87225m (1row) | PLAUSIBLE |
| `metrolink-oc-line` | `metrolink-sb-line` | L.A. Union Station | L.A. Union Station | 1010m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity / NYC/NJ Transit (5 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-carolinian` | `new-jersey-transit-nj-transi-njcl` | Ny Moynihan Train Hall At Penn Station | NEW YORK PENN Station, Secaucus Upper Level | 14700m (1row) | PLAUSIBLE |
| `amtrak-palmetto` | `new-jersey-transit-nj-transi-atlc` | Philadelphia | Philadelphia | 12425m (1row) | PLAUSIBLE |
| `amtrak-palmetto` | `new-jersey-transit-nj-transi-nec` | Metropark Amtrak Station, Trenton | Metropark Amtrak Station, Metuchen, Edison Station | 58875m (1row) | PLAUSIBLE |
| `amtrak-palmetto` | `new-jersey-transit-nj-transi-njcl` | Ny Moynihan Train Hall At Penn Station, Newark | NEW YORK PENN Station, Secaucus Upper Level, Newark | 34300m (2rows) | PLAUSIBLE |
| `amtrak-vermonter` | `new-jersey-transit-nj-transi-njcl` | Ny Moynihan Train Hall At Penn Station, Newark | NEW YORK PENN Station, Secaucus Upper Level | 14900m (1row) | PLAUSIBLE |

### Dallas (5 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `dallas-area-rapid-transit-da-blue` | `dallas-area-rapid-transit-da-orange` | WEST END Station, Akard Station, ST PAUL Station | Smu/mockingbird Station, Cityplace/uptown Station, Pearl/arts District Station | 8025m (1row) | PLAUSIBLE |
| `dallas-area-rapid-transit-da-green` | `dallas-area-rapid-transit-da-orange` | Bachman Station, Burbank Station, Inwood/love Field Station | Pearl/arts District Station, ST PAUL Station, Akard Station | 13400m (1row) | PLAUSIBLE |
| `dallas-area-rapid-transit-da-red` | `dallas-area-rapid-transit-da-blue` | 8th & Corinth Station, Cedars Station, EBJ Union Station | 8th & Corinth Station, Cedars Station, EBJ Union Station | 13850m (1row) | PLAUSIBLE |
| `dallas-area-rapid-transit-da-red` | `dallas-area-rapid-transit-da-orange` | Smu/mockingbird Station, Lovers LANE Station, PARK LANE Station | Parker ROAD Station, Downtown Plano Station, 12th Street Station | 23242m (1row) | PLAUSIBLE |
| `mckinney-avenue-trolley-m-line-ob-b1` | `mckinney-avenue-trolley-m-line-ob` | CityPlace & McKinney, McKinney & Lemmon, McKinney & Hall | CityPlace & Noble, CityPlace & McKinney, McKinney & Blackburn | 1441m (1row) | PLAUSIBLE |

### NYC Metro-North (5 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `metro-north-railroad-danbury` | `metro-north-railroad-harlem` | Grand Central, Harlem-125 St | Grand Central, Harlem-125 St, Melrose | 19600m (1row) | PLAUSIBLE |
| `metro-north-railroad-danbury` | `metro-north-railroad-new-haven` | Greenwich, Stamford, Noroton Heights | Mt Vernon, Pelham, New Rochelle | 46800m (1row) | PLAUSIBLE |
| `metro-north-railroad-hudson` | `metro-north-railroad-harlem` | Grand Central, Harlem-125 St | Grand Central, Harlem-125 St | 8525m (1row) | PLAUSIBLE |
| `metro-north-railroad-new-canaan` | `metro-north-railroad-new-haven` | Stamford, Old Greenwich, Riverside | Grand Central, Harlem-125 St, Fordham | 56123m (1row) | PLAUSIBLE |
| `metro-north-railroad-new-haven` | `metro-north-railroad-harlem` | Grand Central, Harlem-125 St, Fordham | Grand Central, Harlem-125 St, Melrose | 19650m (1row) | PLAUSIBLE |

### SF BART (5 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `bart-blue` | `bart-orange` | Lake Merritt, Fruitvale, Coliseum | Lake Merritt, Fruitvale, Coliseum | 18100m (1row) | PLAUSIBLE |
| `bart-blue` | `bart-red` | Daly City, Balboa Park, Glen Park | Daly City, Balboa Park, Glen Park | 22140m (1row) | PLAUSIBLE |
| `bart-green` | `bart-orange` | Lake Merritt, Fruitvale, Coliseum | Lake Merritt, Fruitvale, Coliseum | 60731m (1row) | PLAUSIBLE |
| `bart-green` | `bart-red` | Daly City, Balboa Park, Glen Park | Daly City, Balboa Park, Glen Park | 22140m (1row) | PLAUSIBLE |
| `bart-red` | `bart-orange` | 12th Street / Oakland City Center, 19th Street Oakland, MacArthur | Richmond, El Cerrito Del Norte, El Cerrito Plaza | 19949m (1row) | PLAUSIBLE |

### NYC PATH (4 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `port-authority-trans-hudson-hoboken-33rd-street` | `port-authority-trans-hudson-world-trade-center-33rd-street` | 33rd Street, 23rd Street, 14th Street | 33rd Street, 23rd Street, 14th Street | 4075m (1row) | PLAUSIBLE |
| `port-authority-trans-hudson-hoboken-world-trade-center` | `port-authority-trans-hudson-journal-square-33rd-street-via-hoboken` | Newport | Newport | 1575m (1row) | PLAUSIBLE |
| `port-authority-trans-hudson-journal-square-33rd-street-via-hoboken` | `port-authority-trans-hudson-journal-square-33rd-street-via-hoboken` | Christopher Street | Newport, 9th Street | 2425m (1row) | PLAUSIBLE |
| `port-authority-trans-hudson-journal-square-33rd-street-via-hoboken` | `port-authority-trans-hudson-world-trade-center-33rd-street` | Newport, 9th Street, 14th Street | Newport, 33rd Street, 23rd Street | 6182m (2rows) | PLAUSIBLE |

### SF Muni (4 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `san-francisco-municipal-tran-f` | `san-francisco-municipal-tran-j` | Market St & Church St, Market St & Buchanan St, Market St & Laguna St | Church St & Duboce Ave, Metro Van Ness Station, Metro Civic Center Station/Outbd | 3800m (1row) | PLAUSIBLE |
| `san-francisco-municipal-tran-f-b1` | `san-francisco-municipal-tran-f` | The Embarcadero & Greenwich St, Embarcadero & Sansome St, The Embarcadero & Bay St | The Embarcadero & Green St, The Embarcadero & Greenwich St, The Embarcadero & Sansome St | 1720m (1row) | PLAUSIBLE |
| `san-francisco-municipal-tran-f-b2` | `san-francisco-municipal-tran-f` | Market St & Church St, Market St & Dolores St, Market St & Guerrero St | Market St & Church St, Market St & Buchanan St, Market St & Laguna St | 4324m (1row) | PLAUSIBLE |
| `san-francisco-municipal-tran-t` | `san-francisco-municipal-tran-t-b1` | Bayshore Blvd & Sunnydale Ave, Bayshore Blvd & Blanken Ave, Third Street & Le Conte Ave | Bayshore Blvd & Sunnydale Ave, Bayshore Blvd & Areta Ave, Third Street & Le Conte Ave | 1350m (1row) | PLAUSIBLE |

### Salt Lake City (4 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `utah-transit-authority-uta-701` | `utah-transit-authority-uta-703` | Meadowbrook Station, Murray North Station, Murray Central Station | Meadowbrook Station, Murray North Station, Murray Central Station | 6325m (1row) | PLAUSIBLE |
| `utah-transit-authority-uta-701-b1` | `utah-transit-authority-uta-704` | Ballpark Station, 900 South Station, 600 South Station | Ballpark Station, 900 South Station, 600 South Station | 4400m (1row) | PLAUSIBLE |
| `utah-transit-authority-uta-703-b1` | `utah-transit-authority-uta-704` | Ballpark Station, 900 South Station, 600 South Station | Ballpark Station, 900 South Station, 600 South Station | 2475m (1row) | PLAUSIBLE |
| `utah-transit-authority-uta-703-b2` | `utah-transit-authority-uta-703-b1` | University South Campus Station, Stadium Station | Stadium Station, University South Campus Station | 1309m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity / LA (3 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-southwest-chief` | `metrolink-91-pv-line` | Fullerton | Norwalk / Santa Fe Springs, Buena Park, Fullerton | 47625m (1row) | PLAUSIBLE |
| `amtrak-southwest-chief` | `metrolink-ie-oc-line` | Riverside - Downtown | Corona, Corona - North Main, Riverside - La Sierra | 64775m (1row) | PLAUSIBLE |
| `amtrak-southwest-chief` | `metrolink-oc-line` | L.A. Union Station | L.A. Union Station | 1457m (1row) | PLAUSIBLE |

### Montreal (3 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `exo-ca` | `exo-sj` | Gare Montréal-Ouest, Gare Vendôme, Gare Lucien-L'Allier | Gare Lucien-L'Allier, Gare Vendôme, Gare Montréal-Ouest | 8066m (1row) | PLAUSIBLE |
| `exo-vh` | `exo-sj` | Gare Montréal-Ouest, Gare Vendôme, Gare Lucien-L'Allier | Gare Lucien-L'Allier, Gare Vendôme, Gare Montréal-Ouest | 8232m (1row) | PLAUSIBLE |
| `via-ottawa-montr-al` | `exo-vh` | Montréal, Dorval | Gare Dorion, Gare Pincourt, Gare Île-Perrot | 22575m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity / Boston MBTA (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-lake-shore-limited` | `mbta-framingham-worcester-line` | Back Bay, Framingham, Worcester | Back Bay, Lansdowne, Boston Landing | 68725m (3rows) | PLAUSIBLE |
| `amtrak-lake-shore-limited` | `mbta-providence-stoughton-line` | Back Bay | Back Bay | 1475m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity / Connecticut (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-amtrak-hartford-line` | `connecticut-transit-hartford-line` | Springfield, Windsor Locks, Windsor | New Haven, Wallingford, Meriden | 99525m (1row) | PLAUSIBLE |
| `amtrak-valley-flyer` | `connecticut-transit-hartford-line` | Wallingford Amtrak, Meriden, Berlin Amtrak | Wallingford, Meriden, Berlin Amtrak | 95250m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity / DC (WMATA/MARC) (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-palmetto` | `maryland-transit-administrat-penn-washington` | Baltimore Penn Station, Bwi Thurgood Marshall Airport Station, New Carrollton Amtrak Station | Baltimore Penn Station, MARTIN AIRPORT MARC, EDGEWOOD MARC | 121875m (3rows) | PLAUSIBLE |
| `amtrak-vermonter` | `maryland-transit-administrat-penn-washington` | Bwi Thurgood Marshall Airport Station, New Carrollton Amtrak Station | New Carrollton Amtrak Station, SEABROOK MARC, BOWIE STATE MARC | 47025m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity / NYC Metro-North (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-lake-shore-limited-b1` | `metro-north-railroad-hudson` | Croton-Harmon Amtrak Station, Poughkeepsie Amtrak Station | Riverdale, Ludlow, Yonkers Amtrak Station | 99950m (1row) | PLAUSIBLE |
| `amtrak-vermonter` | `metro-north-railroad-new-haven` | Stamford, Ny Moynihan Train Hall At Penn Station | New Rochelle, Larchmont, Mamaroneck | 26950m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity / US-other (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-amtrak-cascades-us` | `metro-transit-intercity-tran-s-line` | Tacoma, Tukwila Amtrak, Seattle | Lakewood Station, South Tacoma Station, Tacoma | 74825m (4rows) | PLAUSIBLE |
| `amtrak-empire-builder` | `sound-transit-n-line` | Edmonds, Seattle | Everett Amtrak Station, Mukilteo Station, Edmonds | 51550m (7rows) | PLAUSIBLE |

### Chicago / Chicago/NW Indiana (South Shore) (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `metra-me-b1` | `south-shore-line-lakeshore` | 63rd St. | 63rd St. | 1325m (1row) | PLAUSIBLE |
| `metra-me-b3` | `south-shore-line-lakeshore` | 59th St. (U. of Chicago) | 63rd St. | 2200m (1row) | PLAUSIBLE |

### Connecticut / Amtrak/VIA intercity (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `connecticut-transit-hartford-line` | `amtrak-shore-line-east` | New Haven | New Haven | 3375m (1row) | PLAUSIBLE |
| `shore-line-east-shore-line-east-train` | `amtrak-shore-line-east` | New Haven, Branford, Guilford | New London, Old Saybrook, Westbrook | 81607m (1row) | PLAUSIBLE |

### Houston (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `houston-metro-800-b1` | `houston-metro-900` | Theater District Capitol, Central Station Capitol, Convention District Capitol | Eado Stadium Stn, Convention District Capitol, Central Station Capitol | 1666m (1row) | PLAUSIBLE |
| `houston-metro-900-b1` | `houston-metro-800` | Convention District Rusk, Central Station Rusk, Theater District Rusk | Theater District Rusk, Central Station Rusk, Convention District Rusk | 1377m (1row) | PLAUSIBLE |

### Miami/South Florida (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `south-florida-regional-trans-dml` | `south-florida-regional-trans-mce` | MiamiCentral Station | MiamiCentral Station | 13839m (1row) | PLAUSIBLE |
| `south-florida-regional-trans-mce` | `south-florida-regional-trans-tr` | Ft Lauderdale Airport Station, Boca Raton Station, West Palm Beach Station | West Palm Beach Station, Lake Worth Station, Boynton Beach Station | 75049m (1row) | PLAUSIBLE |

### NYC LIRR (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `mta-long-island-rail-road-city-terminal-zone` | `mta-long-island-rail-road-west-hempstead-branch` | Woodside, Forest Hills, Kew Gardens | Forest Hills, Kew Gardens, Jamaica | 16242m (1row) | PLAUSIBLE |
| `mta-long-island-rail-road-hempstead-branch` | `mta-long-island-rail-road-west-hempstead-branch` | Jamaica, Kew Gardens, Forest Hills | Grand Central, Forest Hills, Kew Gardens | 19459m (1row) | PLAUSIBLE |

### NYC Metro-North / Amtrak/VIA intercity (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `metro-north-railroad-new-haven` | `amtrak-shore-line-east` | Stamford, Noroton Heights, Darien | New Haven, Bridgeport, Stamford | 63948m (1row) | PLAUSIBLE |
| `metro-north-railroad-waterbury` | `amtrak-shore-line-east` | Bridgeport, Stratford | Bridgeport | 8125m (1row) | PLAUSIBLE |

### New Orleans (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `new-orleans-rta-12-b1` | `new-orleans-rta-12` | Canal St at Carondelet St, Carondelet St at Gravier St, CarondeletSt at Poydras St | Canal St at Carondelet St, St Charles Ave at Common St, St Charles Ave at Union St | 1416m (1row) | PLAUSIBLE |
| `new-orleans-rta-47` | `new-orleans-rta-48` | Canal at Hennessy, N. Carrollton Ave. at Canal St., Canal at Scott | N. Carrollton at Bienville, N. Carrollton Ave. at Canal St., Canal at Scott | 4431m (1row) | PLAUSIBLE |

### SF Muni / SF BART (2 pairs)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `san-francisco-municipal-tran-j` | `bart-red` | Metro Van Ness Station, Metro Civic Center Station/Outbd, Metro Powell Station | Civic Center / UN Plaza, Powell Street, Montgomery Street | 2923m (1row) | PLAUSIBLE |
| `san-francisco-municipal-tran-j-b4` | `bart-red` | Metro Van Ness Station, Civic Center / UN Plaza, Powell Street | Civic Center / UN Plaza, Powell Street, Montgomery Street | 2837m (1row) | PLAUSIBLE |

### Amtrak/VIA intercity / Chicago/NW Indiana (South Shore) (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-lake-shore-limited` | `south-shore-line-lakeshore` | South Bend Amtrak Station, Chicago Union Station | Hudson Lake, South Bend Airport | 16325m (3rows) | PLAUSIBLE |

### Amtrak/VIA intercity / NYC LIRR (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-vermonter` | `mta-long-island-rail-road-west-hempstead-branch` | Stamford, Ny Moynihan Train Hall At Penn Station | Grand Central, Forest Hills | 1550m (1row) | PLAUSIBLE (weak: shared Sunnyside/Harold Interlocking throat only; any LIRR Main-Line branch would match equally, so the specific partner (West Hempstead) is an arbitrary pick among several) |

### Amtrak/VIA intercity / SF Bay Area commuter (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-capitol-corridor` | `ace-ace` | Fremont, Great America Parkway Station, Santa Clara Amtrak | San Jose, Santa Clara Amtrak, Great America Parkway Station | 34545m (1row) | PLAUSIBLE |

### Atlanta MARTA (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `metropolitan-atlanta-rapid-t-green` | `metropolitan-atlanta-rapid-t-blue` | Ashby Station, VINE CITY Station, SEC District Station | Ashby Station, VINE CITY Station, SEC District Station | 7935m (1row) | PLAUSIBLE |

### Chicago / Amtrak/VIA intercity (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `metra-hc` | `amtrak-lincoln-service-missouri-river-runner` | Summit, Willow Springs, Lemont | Summit, Joliet | 56318m (2rows) | PLAUSIBLE |

### Edmonton (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `edmonton-transit-system-metro` | `edmonton-transit-system-capital` | Century Park Station, Southgate Station, South Camputs Ft. Edmonton Station | Century Park Station, Southgate Station, South Camputs Ft. Edmonton Station | 12150m (1row) | PLAUSIBLE |

### Ottawa (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `ottawa-carleton-regional-tra-4` | `ottawa-carleton-regional-tra-2` | South KEYS | South KEYS | 1375m (1row) | PLAUSIBLE |

### Philadelphia SEPTA (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `septa-m1-b1` | `septa-m1` | Matsonford, Gulph Mills Station, Hughes Park | Matsonford, Gulph Mills Station, Hughes Park | 2794m (1row) | PLAUSIBLE |

### SF Bay Area commuter (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `ace-ace` | `caltrain-local-weekday` | San Jose, Santa Clara Amtrak | San Jose, Santa Clara Amtrak, College Park Station | 4275m (2rows) | PLAUSIBLE |

### San Diego (NCTD) (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `north-county-transit-distric-498` | `north-county-transit-distric-498-b1` | San Diego - Old Town, San Diego - Santa Fe Depot | San Diego - Old Town, San Diego - Santa Fe Depot | 5185m (1row) | PLAUSIBLE |

### VIA/Amtrak intercity (CA) / Montreal (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `amtrak-adirondack-ca` | `exo-sh` | Montréal, Gare Saint-Lambert | Gare Saint-Lambert, Montréal | 5965m (1row) | PLAUSIBLE |

### Vancouver (1 pair)

| line | follows (canonical) | shared stations (line side) | shared stations (canon side) | run | decision |
| --- | --- | --- | --- | ---: | --- |
| `translink-expo-line-b1` | `translink-millennium-line` | Lougheed Town Centre Station, Production Way-University Station | Production Way-University Station, Lougheed Town Centre Station | 1922m (1row) | PLAUSIBLE |