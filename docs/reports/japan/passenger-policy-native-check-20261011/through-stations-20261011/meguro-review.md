# Meguro three-company handoff — source review, 2026-10-11

Read-only review under `AGENTS.md`, `ios/VERIFICATION.md` and the passenger representative policy. No production edit, UI action, build or test. Targeted reads and one lightweight `RailNetwork.displayPartsForLine` endpoint query only. Parent chat owns integration; capture owner owns native images.

## Current operation and identities

The relevant current passenger topology is Tokyu Meguro Line continuing into either Namboku or Mita at Meguro, and Namboku/Mita sharing the facilities from Meguro through Shirokanedai to Shirokane-takanawa. It is not a Namboku-to-Mita through service, and JR Yamanote remains an independent surface corridor.

Official sources checked live on 2026-10-11:

- [Tokyu Meguro station](https://www.tokyu.co.jp/area/meguro/station/) lists Namboku and Toei Mita as through routes, with Fudo-mae the adjacent Tokyu station. The linked [current station plan](https://www.tokyu.co.jp/railway/station_map/pdf/mg01-meguro_0.pdf), dated 2026-07-15, identifies underground platforms 1 toward Hiyoshi and 2 toward Shirokane-takanawa and treats JR separately.
- [Tokyo Metro Meguro–Shirokane-takanawa fare policy](https://www.tokyometro.jp/ticket/particularcase/meguro_shiroganetakanawa/index.html) confirms facility sharing with Toei Mita on that bounded section; [official Metro FAQ](https://ssl.tokyometro.jp/support/faq_answer?faqno=OpenFAQ-000407&lang=ja) also identifies the duplicate section.
- [Tokyu Meguro Line history](https://www.tokyu.co.jp/railway/train-history/mg/) records Namboku/Mita through operation starting September 2000.

`ios/RailKit/Sources/RailCore/Resources/japan-through-services.json` contains active `mita-meguro` from 2000-09-26, `namboku-saitama-meguro` from 2001-03-28, and Namboku/Mita Sotetsu–Tokyu patterns from 2023-03-18, with no current end date. The Namboku catalog start scopes the wider Saitama corridor, not the original Meguro handoff date. Both current calendar day and the inspector's previously visible 2025-05-02 selection are later than these onsets. A catalog corridor confirms some through trains, not a dated departure or all endpoint combinations (`JapanThroughServices.swift` documents that limit).

The catalog separately marks the old Toyoko leg of Hibiya through running with exclusive `validTo: 2013-03-16`. Do not promote Nakameguro's former Hibiya/Toyoko service into a current through join. None of those station identities belongs to this Meguro group.

## Source and display seam

The three compact station rows use exact common `[139.71566,35.632485]`, code `004072`, and distinct operators: Tokyo Metro, Tokyo Metropolitan Government, and Tokyu. All have no `displayStationCoordinates` override, circle owner or explicit station lane pin.

Registered `app/data/stations.json` station features retain distinct N02 station codes 004073 (Namboku), 004072 (Mita), and 004074 (Tokyu) while sharing group 004072. Each contains the same two-point underground platform LineString `[139.71542,35.6332]` to `[139.7159,35.63177]`; the compact point equals its midpoint. This is a registered platform-family source, not a newly chosen nearby rail.

The existing production endpoint query confirms:

| Display part | Meguro ordering/supports |
|---|---|
| Namboku part 0 | Starts at common anchor, then `[139.71542,35.6332]`, then `[139.71534,35.63352]` northward. |
| Mita part 0 | Ends with the same three points in reverse order. |
| Tokyu Meguro part 0 | Ends `[139.71606,35.63133]`, `[139.7159,35.63177]`, common anchor. Its platform ray opposes the shared northward ray. |

Meguro is absent from the four explicit `through-running-display-joins.json` entries. No 120 m through Bezier replay is applied here. The common source point therefore does not prove that the final lane-offset screen endpoints are identical. Do not pin all three strokes to zero merely to suppress their company parallelism; native endpoint presentation needs direct observation.

JR Yamanote's compact point is separate `[139.715829,35.632923]`. Its registered curved surface station LineString and `display_point: [139.7157271,35.6334057]` are also separate. Shared station group 004072 is an interchange identity, not authority to merge underground and JR display anchors.

## Company parallelism and consumers

Current `display-lanes.json` has a Namboku follow covering follower metres 0–2650, referencing Mita part 0 canonical metres 26578.930586656144–23950 in reverse order. A follow shares the representative centerline; it does not remove a company's stroke. Namboku lane row is -0.5 from 0–11367.7. Mita's terminal lane row is -0.5 from 22647.9–26578.9. Because their part orders oppose each other, these equal signed lanes occupy opposite physical screen sides of the shared centerline. Tokyu has no lane row in this part and uses the zero default south of the handoff.

All three have no family windows, stroke exclusions or chain boundary suppression in the current JP lane artifact. `shared-corridors.json` retains an old low-confidence Namboku→Mita landlord seed with the stated Meguro–Shirokane-takanawa span; that seed selects the canonical centerline and cannot by itself prove track ownership. The current artifact does not convert this pair into one hidden tenant stroke. A separate Tokyu/Toyoko landlord seed near Den-en-chofu does not make their Meguro approaches shared with JR or either subway line.

JS `rail-network.js:3189–3211,4035` retains follow references, and `railmap.js:1671–1686` resolves canonical points/measures before emission. Native `RailNetworkStore.swift:1450–1473` retains lane rows, follow canonical IDs and family windows as separate fields; `MapLineGeometry.swift:392–402` resolves canonical chains before `ContinuousStroke`. Circle guards in JS `rail-network.js:4391–4405` and Swift `StationDisplay.swift:228–244` require an explicit owner, same nonempty operator and exact display point. No owner declaration exists here, so no cross-company circle suppression is authorized.

Source verdict: the present artifacts retain Namboku/Mita company parallelism over their shared passenger section, preserve the Tokyu handoff identity, and keep Yamanote independent. No data change follows from these reads. Pixel spacing, terminal lane convergence and exact original Apple underground black-track alignment await capture-owner evidence.

## Native evidence

Reviewed six stable same-camera images supplied by capture owner: `meguro/{namboku-central,mita-central,tokyu-central}-z18-{overlay,basemap}.png`, centered at `[139.71566,35.632485]`. The selected-day label is 2025-05-02; the footer reports z18.00 and 0.48 m/pt. Namboku and Mita show the same northward centerline approach at the common pin tip; Tokyu approaches from the south with a coherent continuing direction. The selected underground approaches occupy the western station corridor and remain separate from the visible JR/Saikyo surface tracks to the east. None shows an erroneous cross-link into those surface rails.

The Inspector draws an independent zero-lane centerline preview. Coincident preview pin tips establish only source/preview centerline agreement. They do not show the main map's final Namboku/Mita lane-offset endpoints, company-parallel screen seam, or station anchor-slot placements. The source opposite lane rows are retained evidence of the intended company parallelism, not a pixel-spacing certification. Do not convert this preview coincidence into an instruction to pin all companies to lane zero or create a broad merged station window.

Apple's large building/station footprint covers the underground path; the central frames do not expose exact original black underground track supports or identify the underground platform's georeferenced central extent unambiguously. The current point is the registered station LineString midpoint, and the screenshots provide no specific evidence requiring relocation.

Also reviewed capture-owner's stable `meguro/namboku-north-approach-view2-z18-{overlay,basemap}.png` (camera `[139.716619,35.635092]`) and `meguro/tokyu-south-approach-view2-z18-{overlay,basemap}.png` (camera `[139.715607,35.62786]`), with matching AX records. Capture owner confirms all five pairs have equal reported camera values and were captured after a separate setup/observation call; see `meguro/capture-note.md`.

The north preview retains the broad curve away from the station toward the east, crossing beneath the independent north–south JR surface corridor; it does not incorrectly continue following the JR line. Cyan display geometry and magenta smoothed centerline stay close while retaining this curve. Basemap Mita text supplies context but does not expose precise underground black-track supports. No individual necessary small bend or fork is identified as missing. The south preview retains the continuing curved Tokyu approach alongside its corridor across the Meguro River area; there is no visible chord across neighboring building blocks or detached spur. The north and south AX footers each report `可视平滑→显示 0.7 m`; this compares smoothing to display geometry, not to Apple black rail.

Final scoped verdict: all ten stable PNGs support coherent underground centerline continuity at the registered point and retention of the visible north/south approach curves; no specific relocation or production geometry repair is justified. Underground original black track agreement, every small surveyed curve, main-map company-parallel terminal lane convergence and company marker placement remain unmeasured. The independent zero-lane previews cannot resolve those main-map offset questions. Do not snap the underground group to nearby JR surface rail, add a 300 m station merge, or remove company parallelism merely because the preview centerlines meet. No precision-alignment pass claimed.
