# Sobu-3 Nakamagome: exact display-ruler dependencies

2026-10-18. Source-only audit of the [staged own-passenger fragment](candidate-fragment.json). No builder/code or production data was changed; no apply, tests, native/app or build ran. This read computed only the selected Sobu-3 line's old/candidate DisplayParts and queried its exact measured dependencies. [ruler-dependencies.json](ruler-dependencies.json) retains the full current/candidate native part rows, every exact dependency row, measures/classifications, station anchors and the integration caveat. Candidate measures are derived observations, not applied output.

## One geometry and one ruler

The current source interval still equals the staged baseline. The current `partsByRegion` row exactly equals the existing `partRowsForLine(line, RailNetwork.displayPartsForLine(line))` result. The candidate was assembled in memory by setting only this line's `displayIntervalCoordinates[3]` to the bounded splice. Its outer raw supports and all other own interval/station inputs remain unchanged.

The **existing production `RailNetwork.displayPartsForLine`** produces one part before/after. `partRowsForLine` emits an embedded **`complex`** row, not an interval-range row:

- Current summary: `[SOBU,0,-1,-1,346,24427.1,'complex',<346 coordinates>,[]]`.
- Candidate summary: `[SOBU,0,-1,-1,347,24425.0,'complex',<347 coordinates>,[]]`.

`SOBU` is exactly `jp-東日本旅客鉄道-総武線-3`. Row8 withheld spans are empty in both. Native `build-display-network.py:987–992` consumes row7's embedded coordinates for this kind, so changing the compact display override alone would leave native geometry stale. Regenerate this one row through the existing geometry functions; do not hand-generate a second native/groomed shape. The no-faithful-interval-range fallback is intentional and must not be forced into a plain interval row.

The existing `repair-shinagawa-display-lanes.mjs:18–22,100–119` ruler uses per-edge midpoint-latitude equirectangular distance with111320m/degree. It differs from the haversine helper used for the earlier fragment-only review; the full-part delta below is the authority for display measure rebasing.

| Exact retained support | Current part vertex / measure | Candidate part vertex / measure |
| --- | --- | --- |
| Start `[139.70858,35.59237]` | 190 / 12006.113972475643m | 190 / same |
| End `[139.69821,35.58934]` | 209 / 13005.999017148131m | 210 / 13003.930305638969m |
| Full part end | 345 / 24427.08524884414m | 346 / 24425.01653733498m |

There are191 exact prefix vertices, including the start support, and137 exact suffix vertices, including the end support. Every suffix support shifts by **−2.0687115091623127m**; maximum deviation from that constant shift is1.82×10⁻¹²m. No station, measured-reference endpoint, loop/chain boundary or withheld boundary occurs in the changed interior. Prefix measures stay exact; suffix measures use that one delta. A future interior boundary must fail for review rather than receive an invented proportional mapping. The rounded native total is regenerated from the candidate part; it is not obtained by blindly adding the delta to24427.1.

## Exact measured rows

### Own lane rows

Eight current `byRegion.jp` rows all refer to Sobu part0. Seven stay byte-for-byte unchanged:

`[0,300,0]`, `[300,700,-0.5]`, `[700,1560.9,0]`, `[1560.9,2160.9,0]`, `[2160.9,2325,0]`, `[2325,6358.7,-0.5]`, `[6358.7,6958.7,0]`.

These shorthand triples are `[from,to,lane]`; the full `[SOBU,0,...]` rows are in the JSON. The remaining row spans across the changed geometry, but both its endpoints are retained supports: `[SOBU,0,6958.7,17247.18419333458,-0.5]` becomes `[SOBU,0,6958.7,17245.115481825414,-0.5]`. Its lane identity stays−0.5. No lane boundary is inside the changed window and no new station lane pin is needed.

### Follows in both roles

There are **zero Sobu tenant rows** and **four rows with Sobu as canonical owner**. Only the canonical columns6/7 of the two downstream `jp-東日本旅客鉄道-東海道線-3` tenant rows shift. Tenant geometry, part0 and columns2/3 remain unchanged:

| Tenant | Tenant span | Current Sobu canonical span | Candidate Sobu canonical span |
| --- | --- | --- | --- |
| 東海道線-3 | 0…1675 | 16733.146684572363…18397.18419333458 | 16731.0779730632…18395.115481825414 |
| 東海道線-3 | 3425…6675 | 20147.18419333458…23372.18419333458 | 20145.115481825414…23370.115481825414 |
| 大崎支線 | 1656.6631909646057…2527.033017433455 | 9438.910697753388…10309.280524222238 | unchanged retained prefix |
| 大崎支線-p1 | 1656.6631909646057…2527.033017433455 | 9438.910697753388…10309.280524222238 | unchanged retained prefix |

Full exact rows, identities and mapped candidates are retained in the JSON. Downstream follows reference geographically unchanged Sobu suffix geometry; changing their canonical measures preserves that same geometry rather than changing tenant route ownership. Replaying Osaki geometry is unnecessary.

### Family, hub and other references

- One own family-owner row: `[SOBU,0,9430.79295925673,10309.280524222238,0,'東日本旅客鉄道:東海道線']`. Both boundaries are retained prefix and remain exact.
- One hub member, `jp-tokyo`: `lineId=SOBU`, `partIndex=0`, `classKey='group\u0000東日本旅客鉄道:東海道線'`, `slot=0`, `side=-1`, `reversed=false`, `from=700`, `to=2325`, `previousLane=-0.5`. Entire member remains exact; no `alongsideFrom/alongsideTo` field exists on it.
- No own `loopsByRegion`, `reversedLoopParts`, `chainBoundariesByRegion`, `strokeExcludedByRegion` or `releasedIntervalsByRegion` entries were found. No reversal tails, extra segments or display branch lead-ins occur on this Sobu row.
- Package `structure` values belong to the **N02 walk ruler**, not this derived display ruler (`rail-network.js:2187`). Do not rebase them for a display-only correction. Canonical segments/km, railway identity and station-circle ownership remain unchanged.

## Anchors and grooming/part implications

Display station coordinates remain exact; no station centre moves. Current station lane pins stay `003766=0`, `003872=0`, `004095=0`. Native anchor vertex indexes and full-part measures are:

| Station | Current → candidate vertex | Current → candidate measure, m |
| --- | --- | --- |
| 東京003766 | 0 →0 | 0 →0 |
| 新橋003872 | 26 →26 | 1860.9133488848852 →same |
| 品川004095 | 95 →95 | 6658.703843696129 →same |
| 西大井004235 | 177 →177 | 10309.280524222238 →same |
| 武蔵小杉004301 | 269 →270 | 16733.146684572366 →16731.077973063206 |
| 新川崎004358 | 292 →293 | 19394.171663777764 →19392.102952268604 |
| 鶴見004496 | 345 →346 | 24427.08524884414 →24425.01653733498 |

The part has no topology split. Native `chain_from_embedded_coordinates` derives anchor indexes from its new embedded geometry and station coordinates; do not patch indexes by a guessed global+1. Prefix/suffix comparison establishes that this candidate's only final-part geometry change is the local splice. It does not establish pixel, smoothing-performance or Main composition acceptance.

## Smallest integration recommendation

Keep the **staged fragment/source evidence as the sole new coordinate authority**, and one bounded package edit that writes Sobu `displayIntervalCoordinates[3]`. The existing Tokyo geometry owner `repair-tokyo-platform-approaches.py:81–114` rewrites only0/1/2 and preserves other override keys, so no historical Tokyo tunnel or Shinagawa passenger-pair geometry needs duplication or reinterpretation. The derived ruler step should consume only before/after packages, never independently reconstruct the OSM splice.

Reuse the retained-prefix/suffix mapper and both-role follow handling already in **`repair-shinagawa-display-lanes.mjs`**, plus the existing `partRowsForLine`. Do not copy an interpolating or nearest-segment ruler mapper from `repair-shinagawa-apple-forks-display.mjs`; that private helper currently targets Yamanote/Tokaido, and this Sobu change has no interior measured boundary requiring it. Only this module's own CLI currently calls `repairShinagawaLanes`; no second active importing caller was found in the repair sources.

**One concrete reuse blocker:** `repairShinagawaLanes` currently rejects *any* Sobu family row at lines174–175. The valid retained-prefix Osaki owner row above therefore prevents invoking it unchanged, even though that row does not need a new measure. The smallest extension is to let the same retained-support `remap` classify/preserve this exact guarded family row (or map its two boundary columns through that same mapper), while retaining failure for unexpected/interior references. The current historical Shinagawa pin removal/reapplication would yield the same prefix pin here, but must not create a new geometry authority or change its boundaries.

Use a bounded Sobu before/after package view to avoid touching the unrelated Tokyo terminal helper, and do not select `--osaki`: both Osaki follows and their family geometry are unchanged. Update only the one Sobu native row, the last Sobu lane endpoint and the two downstream canonical follow spans; preserve all other rows/regions and identities. Keep explicit guards for the exact recorded family/hub/loop state. Later focused integration verification/native review can validate the resulting own corridor and cross-line follow composition; this source audit has not done so.
