# Direct own glyph proposal: Main #16, #19, #20

Proposal only. No package, source, native part, station slot, UI or build changed. Root must replay complete related intervals in all three requested Inspectors and Main before any acceptance/apply.

`candidate.json` and `candidate.geojson` contain three complete candidate intervals, with 22, 16 and 12 direct WGS84 controls respectively. `controls.json` provides literal raw pixel controls, exact unprojected coordinates, projected original source points and signed local source residuals. Those residuals describe displacement; they do not generate the candidate. Each camera comes directly from its original `view.json` MKMapRect; viewport 999×654. `z18-reprojection-receipt.json` records all ten actual reprojections, all opened and reviewed. Orange is candidate and magenta is literal original source.

## Identified glyphs and label handling

Main #19 has ONE central black railway glyph with sleeper marks. Literal view1 anchors (450,310), (500,310), (700,309), (900,309) reject the previous V3 two-edge/casing average. Broad dark casing and nearby road edges are not a second rail. The full incoming curve is supported by original Shinkawabashi pixels (540,326), (600,352), (650,370), (690,383), (750,399), then view1 (160,289), (180,293), (240,300.5), (300,307). The label-free controls carry shape through text gaps; the proposal never returns to displaced source under text.

Main #20 is the single shallow-curved glyph. Literal view1 controls (180,350.5), (390,335), (420,332), (480,323), (500,320), (600,304), (620,300), (700,286) and view2 (350,342) preserve its changing tangent. Labels, perpendicular Tokaido blue transit glyph, road casing and neighboring Inuyama glyph are not target evidence. Sparse supports should receive the existing local smoothing during native replay; raw piecewise interpolation itself is not proof of final production stroke alignment.

Main #16 differs: two actual sleeper-marked parallel rails are visible in the identified Main corridor upstream, then merge to the single glyph. Here controls describe their provisional group midline, not an average of broad casing/roads. #16 is not declared independently resolved at Shin Kiyosu. The retained physical start [136.83536,35.21146] lies in its multitrack station group and carries a WARNING. Upstream group-midline uncertainty is roughly 2–3px. Its single southbound glyph uses explicit label-free view3 flanks (389.5,40), (399,60), (408,80), (419,100), (427.5,120), (437,140), (441,150).

## Station boundary warnings

Marunouchi005337 provisional endpoint uses (471,231), [136.84198711408624,35.204625793777495]. Independent station worker corroborated this normal from both label flanks; (474,231) is about3px transversely wrong. Frame chainage/native acceptance remains Root responsibility.

Shinkawabashi005374 provisional start uses (454,280), [136.85237591897993,35.195456036607474]. Independent worker supports own normal around277–281 under the label; prior (454,269) was casing. Its precise opposing-face representative/chainage remains provisional.

Futatsuiri005377 is shared EXACTLY by candidate #19 end and #20 start at (482,309), [136.8596121226845,35.19473890827177]. Own single glyph normal is supported to about1px, while station face acceptance remains provisional.

Nishibiwajima005376 extends the scope to adjacent #21: original source/physical (499.5,327) is approximately7–9px south of the own glyph under text. Root independently reviewed the complete capped own blue station frame on both sides of the single Main glyph; its longitudinal surfaces agree around chainage515–517. Candidate #20 therefore ends at Root's frame-normal pick (516,316.5), [136.86536851289753,35.195131029593654], with chainage ±3px and normal ±1.5px. Root #21 starts at that exact alias. It does not return to the known wrong physical guard. `nishibiwajima-face-candidate.json` preserves the initial south narrow textured strip lead approximately(437,337)→(597,313), alongside Root's adjudicated full own-frame result. Pale building polygons were excluded; the capped northern strip is part of the station frame in Root's independent review, unlike ordinary continuous rail casing. Actual native candidate replay remains pending.

## Slice/integration evidence

The candidate and source each retain interval identity 16/19/20 and [longitude,latitude] convention. Both original #19/#20 coordinates and new candidate have exact shared Futatsuiri boundaries. Source arrays are copied literally from the original interval inputs. No physical mileage, topology, IDs, source supports, native parts or package rows are altered. There are no added branch lead-ins. Source endpoint chainage changes for005337/005374 must be coordinated with neighboring Main #17/#18 by Root; candidate arrays alone do not prove full-scope consistency.

## Review result and limits

Opened all ten original z18 raws before tracing and all ten exact candidate reprojections after. #19 and #20 direct supports follow their identified literal glyphs and visibly reject displaced source. #16 body follows the actual parallel-to-single corridor with group ambiguity explicitly retained. No quantitative whole-path residual, native smoothed/lane rendering, station frame acceptance or complete application replay is claimed. Prior V1/V2/V3 proposals remain rejected references only. The candidate is reviewable and ready for Root's pixel/slice adjudication; it is not native accepted.
