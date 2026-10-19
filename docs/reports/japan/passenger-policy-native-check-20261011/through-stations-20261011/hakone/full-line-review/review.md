# Hakone railway: complete planned native visual review

2026-10-12. Exact line **jp-小田急箱根-鉄道線**, all10 station intervals. Read-only production review; wrote only contact images, the camera manifest and this note. No UI operation, capture, build, test or production edit. Current verification policy and railway audit skill applied. Root owns native evidence/configuration validation and the sole checklist.

**All59 viewpoints were actually visually inspected against Apple basemap with smooth overlay, and all59 display overlays were then visually inspected.** Interval endpoints and final tails were included. Counts alone were not used as a verdict. This review finds unresolved placement candidates, with real reversal stems/branches retained; the line is not an all-pass.

## Exact coverage and evidence

Evidence root: `docs/reports/japan/passenger-policy-native-check-20261011/parallel-instance-hakone/evidence`. All listed directories contain original `basemap.png`, `smooth.png`, `display.png`, `view.json`, `capture-state.json`. Smooth is red, display is cyan/green; blue labelled railway is Apple reference. Individual frames show the whole-line centreline clipped to their camera, including neighboring intervals/branches; overlap is not additional independent ground coverage.

| Interval | Capture item directory | Visually inspected zero-based ordinals | UI views (one-based) |
|---|---|---|---|
| 0 | `003413` | 0, 1, 2, 3, 4, 5 | 1–6 |
| 1 | `003414` | 0, 1, 2, 3, 4, 5 | 1–6 |
| 2 | `003415` | 0, 1, 2, 3 | 1–4 |
| 3 | `003416` | 0, 1, 2, 3, 4, 5, 6 | 1–7 |
| 4 | `003417` | 0, 1, 2, 3, 4 | 1–5 |
| 5 | `003418` | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 | 1–10 |
| 6 | `003419` | 0, 1, 2, 3, 4, 5, 6, 7 | 1–8 |
| 7 | `003420` | 0, 1, 2, 3, 4 | 1–5 |
| 8 | `003421` | 0, 1, 2, 3 | 1–4 |
| 9 | `003422` | 0, 1, 2, 3 | 1–4 |

[Exact camera/ordinal manifest](review-viewpoint-manifest.csv) lists all59 cameras, station IDs, timestamps, nominal scale and dependency. `hakone-iN-pXX.jpg` contacts show every basemap/smooth pair side-by-side, up to three ordinal rows. `display-all-pXX.jpg` contacts show every display overlay in nine labelled panels. Original suspect/end pairs reopened at1024×768: interval0/ordinal0; interval3/ordinal2; interval4/ordinal3; interval5/ordinal3; interval6/ordinal1 and6; interval9/ordinal3. Display originals also reopened for interval0/0,6/6,9/3.

Whole-line dependency in all59 view metadata: `ff006de1de08a2219cb10f1ff4b7ba5a68c934a59e5768d6ec077d380ff67e05`. Root supplied the exact native validation and fresh/reuse binding: interval0 fresh6, intervals1/5/6 reused24, remaining29 fresh. Capture timestamps are intentionally mixed and preserved. Root reported the scoped line complete with0failed/0pending. The on-disk global checkpoint includes unrelated national-plan pending rows (captured91,pending92125,failed0 when read); it must not be confused with the scoped line completion or interpreted as an alignment result.

## Interval observations

| Interval / all reviewed ordinals | Visual observation and classification |
|---|---|
| 0 / 0–5 | Odawara station exit, southward long approach and westward Itabashi turn all continuous. Several adjacent blue company tracks and broad station artwork limit exact passenger platform/corridor identity. Original ordinal0 shows red centred west of the labelled Tokaido blue rail, with the station/Odakyu/Hakone corridors beside it; this is insufficient for a wrong-company or correct-platform verdict. Local red/blue bend differences at3–5 remain candidates; no gross broken endpoint seen. |
| 1 / 0–5 | Itabashi–Kazamatsuri river corridor continuous. Red/cyan follow broad rail direction but northward bend timing differs near3–4 and before the station. Nearby Route1 remains a distinct road, not a replacement railway reference. Placement candidate; complete coverage does not accept all curves. |
| 2 / 0–3 | Kazamatsuri–Iryuda straight/curved sequence and both station approaches retained. Modest local rail/reference separations, especially station-side approach. No gross missing connected segment visible; precise railway/platform centre remains unaccepted. |
| 3 / 0–6 | Iryuda–Hakone-Yumoto reviewed completely. Strongest new candidate at ordinal2 (UIview3), Yamasaki approach: red cuts west/north of the curved blue labelled rail; original confirms it. Yumoto endpoint6 reaches the station corridor continuously, with blue platform fan/artwork limiting exact platform identity. |
| 4 / 0–4 | Hakone-Yumoto–Tonosawa approaches continuous. Ordinals2–4 show red straighter/south of the blue west-side Tonosawa bend; original3 confirms roughly10–25pixel separation through western curve. A blue tunnel-like/forest rail depiction supplies cartographic shape, not underground survey proof. Preserve its real bend until source/reference ownership is resolved. |
| 5 / 0–9 | Tonosawa–Ohiradai full traversal reviewed. Deyama U leg and eastward short reversal stem survive. Original3 confirms a substantially different red southern arrival/fork transition against blue reference, with a wedge between lines; stem existence is preserved, so do not turn this into a stem-deletion or smoothing-shortcut repair. Forest/tunnel portions remain geographically insufficient without independent support. Ohiradai approach8–9 keeps its separate station spur and neighboring main legs. |
| 6 / 0–7 | Ohiradai–Miyanoshita complete traversal. Ohiradai station spur, Kamidaihara/Kami-Ohiradai short stem and western outgoing leg remain distinct. Real reverse bends/U shapes at3–6 survive. Current bounded tunnel cartographic supplement is visible as a continuous western leg, rather than an endpoint chord. Modest remaining curve and Miyanoshita approach differences, original6, remain candidates; no new gross break or removed reversal observed. Surface/underground accuracy and station-platform identity remain unproven. |
| 7 / 0–4 | Miyanoshita–Kowakudani repeated curves and river-side U retained. Station approach and final tail inspected; red/cyan are broadly close with modest local separation. No gross disconnected ink seen. Forest/tunnel and platform identity remain limited. |
| 8 / 0–3 | Kowakudani–Chokoku-no-Mori U/long northern approach retained and continuous. Station-area curved alignment differs modestly from blue near3; exact corridor and station artwork acceptance unproved. |
| 9 / 0–3 | Chokoku-no-Mori–Gora full final interval. Curves, northern straight and Gora terminal end inspected, with original final3 confirming red and display enter the railway artwork continuously. The westward labelled Hakone Tozan Cable Car is separate and is not used as railway alignment; no line joining it was inferred. Exact final-platform point, circle/popups and company composition need main-product evidence. |

## Concrete candidate cameras

Original paths below are under the evidence root; `basemap.png`, `smooth.png`, `display.png` and `view.json` share each directory. Approximate separations are visual estimates from original screenshot pixels, not measured residuals to surveyed physical rails. Cameras identify viewpoints, not exact defect coordinates.

| Interval / ordinal / UIview | Original directory | Camera centre latitude,longitude | Finding |
|---|---|---|---|
| 0 / 0 / 1 | `captures/003413/000000/` | 35.25635500,139.15543000 | Station parallel-track/reference ambiguity; no wrong-company conclusion. |
| 1 / 3 / 4 | `captures/003414/000003/` | 35.24680440,139.13420291 | Kazamatsuri bend northward shift candidate seen in contact pair. |
| 3 / 2 / 3 | `captures/003416/000002/` | 35.23702804,139.11491558 | Yamasaki approach: original red approximately20–35px west/north of blue curve. |
| 4 / 3 / 4 | `captures/003417/000003/` | 35.23450943,139.09405066 | Tonosawa western bend: original red approximately10–25px south/straighter. |
| 5 / 3 / 4 | `captures/003418/000003/` | 35.23256604,139.08586226 | Deyama southern arrival/fork wedge; stem retained, placement correspondence unresolved. |
| 6 / 1 / 2 | `captures/003419/000001/` | 35.23624196,139.07480668 | Ohiradai separate station spur and Kami stem retained; no spur deletion. |
| 6 / 6 / 7 | `captures/003419/000006/` | 35.24105655,139.06349638 | Miyanoshita southern reverse curves: original local red/blue bend differences, roughly5–15px. |
| 9 / 3 / 4 | `captures/003422/000003/` | 35.25090500,139.04825000 | Gora final tail: original red/display continuous into railway artwork; cable-car identity separate. |

## Current repaired interval6 source boundary

Read the current `repair-hakone-passenger-corridor.mjs` and `hakone-passenger-corridor-evidence.json`; did not run the builder or test it. The current **displayCartographicOverrides[6]** explicitly calls itself an Apple native original-rail cartographic display supplement, **no underground survey claim**. It replaces only source indices47–54 of identified OSM **way242460442**, tagged `tunnel=yes`, with fixed endpoints and neighboring source indices46/55 preserved. Its declared source window is longitude139.072621→139.0694651, latitude35.2364299→35.2365981. The builder checks original-way direction, unchanged endpoints, a bounded source window and west tangent guard. Reading those checks establishes intended scope, not that every check passed here.

The source retains two independent `displayReversalBranches` for Deyama and Kami-Ohiradai, and actual native images retain them. Existing `parallel-hakone-analysis.md` documents older same source/reference mismatch candidates and saved GSI support; its provenance is a lead, not an independent new primary survey claim. The current wider complete review does not establish physical underground rail position, legal current passenger operation or train-specific platform allocation.

## Verdict limits and owning follow-up

All planned line viewpoints are reviewed. Concrete geographic candidates remain, prioritizing Yamasaki interval3/2, Tonosawa interval4/3 and Deyama interval5/3. Resolve exact same passenger-leg source versus Apple reference before any geometry change; retain actual reversal stems, separate Ohiradai spur, bridges, tunnels and real short reverse bends. Missing/ambiguous track or tunnel interiors remain insufficient; do not snap to Route1, rivers, adjacent JR/Odakyu/Izu-Hakone corridors or the Gora cable car.

This zero-lane Inspector evidence does not certify main-product lanes, neighboring railway composition, station circles/popups, markers, LOD, ridden routes, performance or leaks. Capture completeness and the observed continuous final tails do not prove all-track accuracy. Root should carry these specific findings into the single checklist; no new checklist or production repair was created by this worker.
