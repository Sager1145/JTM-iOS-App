# Ordered-continuation native visual receipt

Date: 2026-10-12

## Scope and receipt

Manually reviewed every `basemap.png`, `display.png`, and `smooth.png` panel in the following complete native evidence sets:

- Hakone Tozan Railway interval 9, Chōkokunomori (`005246`) → Gōra (`005231`), BEFORE: `/private/tmp/jtm-ordered-hakone-manual-20261012/captures/003422/000000..000003` — 4 views / 12 panels.
- The same Gōra interval AFTER: `/private/tmp/jtm-gora-terminal-after-evidence/captures/003422/000000..000003` — 4 views / 12 panels.
- Keihan Keishin Line interval 4, Otani (`006037`) → Kamisakaemachi (`005987`), AFTER: `/private/tmp/jtm-ordered-keishin-manual-20261012/captures/001474/000000..000005` — 6 views / 18 panels.
- Keihan Keishin Line interval 5, Kamisakaemachi (`005987`) → Biwako-hamaotsu (`005954`), AFTER: `/private/tmp/jtm-ordered-keishin-manual-20261012/captures/001475/000000..000003` — 4 views / 12 panels.
- JR East Yamanote Line interval 0, Shinagawa (`004095`) → Osaki (`004135`), BEFORE: `/private/tmp/jtm-shinagawa-forks-native-before/captures/005027/000000..000006` — 7 views / 21 panels.
- Three current Main on/off pairs: `shinagawa-south-fork-{1,2,3}-current-{overlay,basemap}.png` in this report directory — 3 pairs / 6 screenshots.
- Candidate UI receipt, Yamanote interval 0: `/private/tmp/jtm-keyboard-arrow-live/captures/005027/000000..000006` — 7 views, each with basemap/reference/display/smooth (28 panels).
- Revised candidate UI receipt, Tokaido interval 6, Shinagawa (`004095`) → Oimachi (`004197`): `/private/tmp/jtm-keyboard-arrow-live/captures/005392/000000..000007` — 8 recaptured views, each with basemap/reference/display/smooth (32 panels), re-reviewed in full after the north taper changed.

Total reviewed: 25 view triples / 75 native panels, 15 candidate view quadruples / 60 panels, plus 3 Main on/off pairs / 6 screenshots. Every basemap contains rendered roads, buildings, terrain, water, rail glyphs, and labels appropriate to its viewport; there are no blank tiles, loading placeholders, or empty panels being treated as a pass.

## Findings

### Gōra interval 9 BEFORE

- `000000`–`000003`: the approach from Chōkokunomori follows the Apple conventional-rail glyph through the final broad curve and northbound tangent. No mid-interval break, foldback, or road/water diversion is visible.
- The terminal defect is visible in `000001`–`000003`: the cyan display and red smooth line continue to the northern portion of Gōra's long north–south conventional-rail station footprint, beyond its longitudinal middle. This visually corroborates the supplied approximately 33 m northward terminal error; the screenshots alone were not used to remeasure it.
- The westbound `Hakone-Tozan-Cable-Car` glyph is a separate branch entering the west side of the station complex. The reviewed conventional-rail line does not turn onto or continue along that branch.

### Gōra interval 9 AFTER

- All four triples retain the same correctly aligned approach and final curve; no new kink, short fork, detached cap, or reversal appears between the curve and terminal.
- In `000001`–`000003`, the new display/smooth endpoint is visibly moved south from the BEFORE endpoint to the longitudinal middle of the elongated conventional-rail station/platform footprint. It remains centred on the north–south conventional rail band and does not jump into the west cable-car branch or east-side entrance buildings.
- At this map scale the terminal cap is only a few pixels and partly competes with Apple's blue station fill, but its position is still visible in the footprint middle. This supports the cartographic endpoint placement; it is not surveyed platform-centre evidence.

### Keishin interval 4 AFTER

- `000000`–`000002`: from Otani, the red smooth line remains continuous through the road-running curves and the Apple-labelled diagonal Keishin tunnel/cartographic segment. It does not follow the Meishin Expressway, local switchback roads, or the crossing Semimaru/Otsu tunnel depiction.
- `000003`–`000005`: the line continues through Osaka toward Kamisakaemachi with continuous tangents, crosses the broad Biwako Line bundle without turning onto it, and reaches the interval seam without a visible short cap, hook, or order reversal.
- The grey tunnel structures, route shields, and the wide blue Biwako Line bundle locally overlap the evidence line, but adjacent pixels/views keep the Keishin path traceable. No defect is hidden by a blank basemap.

### Keishin interval 5 AFTER

- `000000`–`000001`: the Kamisakaemachi seam agrees with interval 4 in position and heading, then follows the northbound street-running rail corridor without a seam kink or duplicate spur.
- `000002`–`000003`: the line reaches Biwako-hamaotsu and ends inside the Apple station box at the meeting with the Ishiyama-Sakamoto Line. It does not continue along that east–west line, reverse southward, or leave a detached short tail.
- Apple's wide blue station/rail fill and labels partially occlude the last few pixels at Hamaotsu, so these frames establish the visible cartographic centreline/terminal relationship rather than an exact platform lane.

### Shinagawa → Osaki Yamanote interval 0 BEFORE and three Main fork pairs

- `000000`: at Shinagawa the cyan display and red smooth path leave the west side of the dense conventional JR station bundle. The broad station fill and many parallel tracks do not expose a unique branch point. The blue Shinkansen corridor remains separate to the east.
- `000001`: south of the station, the path stays in the western conventional-rail corridor while several tracks remain parallel and fan gradually. This establishes the selected corridor but still supplies no discrete cartographic Y node.
- `000002`: around Yatsuyamabashi and Kitashinagawa, the selected path begins its gradual westward departure from the north–south rail bundle. It does not follow the nearby road, canal, cyan Keikyu corridor, or the eastern Shinkansen glyph.
- `000003`: the broad west/southwest Yamanote curve is unambiguous as a continuous rail corridor. The product path follows that curve, while the Tokaido-direction trunk continues south instead of turning toward Osaki. This is the strongest view for route identity, although the curve emerges from a multi-track fan rather than a single visible switch glyph.
- `000004`: through the dense crossing north/east of Osaki, the product remains on the same westbound approach. It crosses the prominent east–west blue rail depiction without turning onto it; overlapping rail glyphs and junction structures prevent selection of one exact connection pixel.
- `000005`: the westbound curve joins the north Osaki approach continuously. There is no visible foldback, detached cap, or switch onto the southbound trunk bundle.
- `000006`: the path arrives through the expected north/east Osaki station approach and remains continuous into the station bundle, confirming the destination side of the selected branch.

The three Main on/off pairs agree with that sequence at corridor level. Pair 1 near Yatsuyama shows the orange/green shared-stem separation around approximately `x=830, y=280–310`, while Apple's conventional-rail expansion/connection occupies a broad band around `x=805–845, y=430–560`; the product split is visibly north of the representative rail fan. The apparent black X near approximately `x=815, y=600` is an ambiguous crossing/merge inside the multi-track drawing, not a defensible Y-node pixel. Pair 2 shows already-separated, fanning conventional corridors and therefore constrains direction but not the original split. Pair 3 shows corresponding conventional corridors for the west/east curves into Osaki, but both possible connection bands are embedded in dense track crossings; the lower band also intersects the blue Yokosuka depiction. Roads, building edges, the blue Shinkansen and cyan Keikyu glyphs were excluded from the fork reading.

The native extraction at `shinagawa-south-fork-native-extraction` reports `partial_image_support`: 7 of 167 samples supported (4.19%), median offset 19.84 m, p95/maximum 22.74 m, for a `physical_rail_glyph_candidate`. The basemap also contains multiple crossing and parallel rail candidates. That receipt does not justify auto-alignment or promote either extracted LineString to identified Yamanote geometry.

Decision: the complete sequence is sufficient to accept the **branch identity and direction**—Yamanote takes the broad westward curve to Osaki while the Tokaido-direction trunk continues south—but it is insufficient to accept an **exact Y-branch pixel or coordinate**. A larger regional overhead basemap, retaining the Shinagawa shared stem, the continuing southbound trunk, the entire westward curve, and the Osaki approach in one view, is still needed before moving a shared-stem split. It must preserve enough labels or endpoint context to distinguish the conventional lines; a tighter crop of the same multi-track fan would not resolve the ambiguity.

### Unpromoted Yamanote and Tokaido candidate UI receipt

The candidate receipt is internally identified. All seven `005027` views declare reference line `jp-東日本旅客鉄道-山手線`, interval 0, one non-empty clipped reference part, and reference dependency `4f3ac630…`; all eight revised `005392` views declare reference line `jp-東日本旅客鉄道-東海道線`, interval 6, one non-empty clipped reference part, label `REVISED UNPROMOTED Tokaido candidate: longitudinal 200m station taper`, and reference dependency `401826bcbae0471e09ec42b3e2066b275546546b4b88d8e13c493541a837ab20`. The revised GeoJSON SHA-256 is `29797223f736b409c355ea79f32e2145905bbd1cf1b1b16ca1e0e00d35f19403`. The external candidate is the orange line in `reference.png`; the cyan `display.png` and red `smooth.png` remain the current source stages. The UI's nearest-reference figures are candidate/source diagnostics, not Apple residuals.

#### Yamanote `005027`, all 7 views

- `000000`: the orange candidate starts within the broad Shinagawa station rail footprint and reaches the west conventional corridor. The documented 7.14 m station-anchor connector is visible only as a small terminal adjustment inside the station fill; it does not cross to the Shinkansen or Keikyu corridors.
- `000001`: through the south station throat and Yatsuyamabashi, the orange path stays on the western conventional-rail fan and remains continuous. The parallel tracks prevent an exact lane-centre claim.
- `000002`: the candidate continues along the correct west-side conventional corridor as the Yamanote route begins separating from the southbound Tokaido-direction trunk. No gap, reversal, or road-following segment is visible.
- `000003`: through the broad westward curve, the candidate follows the visible thin conventional-rail alignment around the inside/north side of the multi-track band. It does not cut a straight chord across buildings, the canal, or the labelled Yokosuka line.
- `000004`: the candidate stays on the upper Yamanote approach while the bold labelled Yokosuka cartography runs separately below. The candidate remains a smooth rail-following curve across the entire frame, including the beginning of the documented tangent-interpolation window.
- `000005`: the 211.2 m cubic-tangent window from `[139.7338226705, 35.6169392]` to `[139.73149, 35.617]` remains visibly within the thin conventional-rail approach to Osaki. Its join to the retained Osaki stem has no visible corner, gap, foldback, or station-track borrowing.
- `000006`: the retained stem continues into the east side of the Osaki rail footprint and ends within the station complex without a detached cap. Dense parallel station tracks still make an exact Apple lane assignment unavailable.

Yamanote verdict: **adopt the full candidate for display cartography**. No full-range visual defect requires rejecting the candidate or the 211.2 m interpolation. The candidate preserves the correct Shinagawa–Osaki branch, follows visible Apple rail cartography, and is continuous at both interpolation joins. The remaining limits are the small 7.14 m Shinagawa endpoint connector and lane ambiguity inside both station bundles; neither produces a visible wrong-corridor segment in these views. The per-view candidate/source maximum reaches 12.91 m, but that number is not Apple evidence and is not used as the basis for adoption.

#### Revised Tokaido `005392`, all 8 views

- `000000`: the candidate now leaves the preserved Shinagawa anchor `[139.738535, 35.628135]` longitudinally; its next point `[139.73853718, 35.6280451764]` removes the former eastward cap. The orange 200 m quintic taper makes a gradual S-shaped transition entirely inside the broad station/throat rail footprint and joins the southbound conventional band without a corner, lateral hook, road crossing, or building borrow.
- `000001`: the same taper remains smooth through the south station throat and converges on the continuing conventional rail band before Yatsuyamabashi. No new bulge, gap, or reversal appears at the taper/body join.
- `000002`: the candidate continues south through the fanning tracks near Yatsuyamabashi and remains inside the Apple railway corridor. It does not inherit the Yamanote westward branch.
- `000003`: the candidate stays on the continuing southbound trunk while the Yamanote corridor curves west. It follows the visible north–south rail band without a road or canal diversion.
- `000004`: through the crossing beside the westward Osaki approaches, the candidate continues south and does not borrow either Yamanote or Yokosuka curvature. The multiple rail glyphs limit the statement to corridor-centre display alignment.
- `000005`: the candidate remains continuous through the documented cubic-tangent join near `[139.7365488, 35.6163321]` → `[139.73632, 35.61564]`; no visible kink or gap appears.
- `000006`: the retained tail continues straight toward Oimachi within the same north–south Apple rail corridor and crosses the east–west station approach without a spur.
- `000007`: the orange tail reaches the Oimachi station footprint continuously and ends in the station area without a terminal foldback or detached cap.

Revised Tokaido verdict: **adopt the full revised candidate for display cartography**. The only concrete defect in the prior candidate—the 58.75 m transverse Shinagawa hook—is absent. The replacement taper stays longitudinal and inside the visible station/throat rail footprint, while all downstream views retain the previously accepted southbound band, smooth interpolation join, and Oimachi endpoint. The revised candidate/current maximum of 32.66 m in `000000`–`000001` reflects the intended replacement of the old source hook and is not an Apple residual or the basis for acceptance. Apple does not expose an individual engineering lane inside the shared/parallel rail band, so this decision is limited to representative display geometry.

## Evidence boundary

This receipt records only static visual geometry in the listed native snapshots, candidate reference renders, and Main pairs, using the root-approved Apple rail identity. Its adoption decisions apply to display cartography only; they do not certify surveyed platform coordinates, an exact Shinagawa switch location, runtime follow/lane handoff, unreviewed intervals, or a new Gōra source fix beyond the captured AFTER render. Inspector lane counts and UI nearest-reference counters were not used as visual proof.

## Myoko Haneuma interval 2 native receipt

Manually reviewed all 19 `basemap.png` / `display.png` / `smooth.png` triples for Nihongi (`001691`) → Arai (`001675`) at `/private/tmp/jtm-alignment-current-inspection/captures/000091/000000..000018` — 19 views / 57 panels. Every basemap is rendered and usable; none is a loading or blank-map pass.

- `000000` and `000001`: Apple identifies the blue `Myoko-Haneuma-Line` station spur and the continuing northeast main. The cyan display and red smooth render meet at the visible south switch, retain the northbound spur into the elongated Nihongi station footprint, and continue northeast on the labelled railway. No road, building edge, pond, Route 261, or nearby Route 584 corridor is borrowed. The sharp reversal is the real switchback topology; there is no detached cap or diagonal shortcut across the neighbourhood.
- `000002`–`000004`: the northeast departure remains on the labelled Apple railway through the first broad bend. The thinner pale-blue line beside and south/east of it diverges as a watercourse; it is not evidence of a second rail alignment. Display and smooth stay continuous across the bend and the shared edges of these three views.
- `000005`–`000008`: the line completes the eastward-to-northward rural curve on the same labelled rail glyph. The product does not follow Route 584, field/building boundaries, the pond, or the adjacent streams. The red smoothing rounds the sampled curve without cutting across the inside terrain or producing a visible join kink.
- `000009`–`000014`: through Nakajiku, Himekawara, Oizumo and Hirotacho, the northbound product remains on the narrow Apple rail corridor. The Shibuegawa River and its tributaries stay visibly separate. All six frames agree at their overlaps; no gap, foldback, side spur, or newly straightened corner is visible.
- `000015` and `000016`: approaching Arai, the corridor bends gently west and then north while remaining on the labelled railway. Display and smooth cross the road and river features only where the Apple railway does and show no discontinuity at the bend.
- `000017` and `000018`: the product enters Arai through the same north–south passenger rail band and reaches the blue multi-track station footprint. The representative line stays within that rail group at the interval endpoint; it does not divert to the Shibuegawa River, nearby roads, or a station-side building. Apple's parallel station tracks do not expose one unique engineering lane, so these frames support the displayed passenger corridor and endpoint area rather than surveyed platform-track precision.

Visual decision for this captured interval: no concrete source-versus-Apple cartographic displacement, gap, wrong branch, or smoothing defect is visible in the 19-view sequence. The Nihongi switchback identity and the continuous route to Arai are supported at the captured scale. This does not turn the stored `pending` Inspector verdict into a whole-line pass.

The interval render is also not proof of Main's final unique built ink. Inspector draws the interval's canonical source fallback across the station spur/main split and does not exercise Main's lane/family/follow composition. In these opaque static overlays, coincident retrace or duplicate overdraw cannot be distinguished from one stroke. The views therefore validate the visible fallback geometry against Apple, while Main's seven-vertex spur plus continuous-main ownership and actual built-pixel handoff require their own production receipt. No conclusion is made for Myoko Haneuma intervals 0, 1, or 3–8.

## Shinagawa fork native AFTER receipt

Manually reviewed every `basemap.png`, `display.png`, and `smooth.png` panel in the updated zero-lane Inspector captures:

- Yamanote interval 0, Shinagawa (`004095`) → Osaki (`004135`): `/private/tmp/jtm-shinagawa-forks-native-after/captures/005027/000000..000006` — 7 views / 21 panels.
- Tokaido interval 6, Shinagawa (`004095`) → Oimachi (`004197`): `/private/tmp/jtm-shinagawa-forks-native-after/captures/005392/000000..000007` — 8 views / 24 panels.

All 15 AFTER basemaps are genuinely loaded. Roads, buildings, waterways, Apple blue station/rail bands, labels, traffic signals, and route shields are present at each camera; no grid, blank tile, or loading placeholder is counted as evidence.

### Yamanote interval 0 AFTER

- `000000`: the cyan display begins at the reviewed Shinagawa point inside the western conventional-JR station/throat footprint. The short initial adjustment remains within the blue rail group and proceeds south without crossing to the eastern Shinkansen or Keikyu identities. The red smooth line retains the same endpoint and has no detached cap or transverse hook.
- `000001`–`000002`: through the south throat and Yatsuyamabashi, display and smooth stay in the western conventional corridor as it separates from the continuing southbound trunk. They do not borrow the adjacent road, canal, Keikyu, or Shinkansen depiction.
- `000003`–`000004`: the line follows the complete broad westward Yamanote curve and remains on the visible upper/northern conventional rail band through the dense crossing. The transition into and out of the candidate interpolation range is continuous, with no chord across buildings or water, local kink, gap, reversal, or jump to the bold Yokosuka route below.
- `000005`: the retained approach and the approximately 211 m interpolation window form one continuous curve toward Osaki. The join is not visibly exposed as a corner, and the line remains on the same upper Yamanote approach through the multi-track fan.
- `000006`: the line enters the blue Osaki station footprint on that approach and continues through the station group without a detached tail or last-frame turn onto the crossing Yokosuka corridor. The individual engineering track remains ambiguous inside the broad station fan.

Yamanote AFTER visual decision: the promoted cyan/red geometry reproduces the previously reviewed candidate throughout all seven native views. Both station areas, the full westward branch, and both sides of the interpolation window remain continuous on the identified Apple conventional passenger corridor. No visible regression or new unsupported segment is present.

### Tokaido interval 6 AFTER

- `000000`–`000001`: the cyan and red lines start at the reviewed Shinagawa point and make the revised longitudinal 200 m taper inside the broad conventional station/throat footprint. The S-shaped transition is visible but remains within the rail group; the rejected transverse eastward cap is absent. Both ends of the taper are smooth, without a gap, cusp, road/building borrow, or jump to Shinkansen/Keikyu.
- `000002`–`000003`: south of Yatsuyamabashi, the line continues in the southbound conventional trunk while the Yamanote path departs west. It does not inherit the westward branch, and the taper/body continuation has no visible seam.
- `000004`–`000005`: through the dense Osaki-side crossing, display and smooth retain the north–south trunk identity. The documented downstream interpolation join is continuous and does not turn onto the Yamanote/Osaki curve or the blue Yokosuka depiction.
- `000006`: the retained tail stays on the same southbound band through the waterfront approach, with no lateral excursion or newly straightened corner.
- `000007`: at Oimachi, the line crosses the blue station footprint on the same north–south conventional corridor. Because the whole-line Inspector render continues beyond the reviewed station coordinate, this frame establishes a continuous station seam/representative band rather than a clipped interval cap or one surveyed platform lane.

Tokaido AFTER visual decision: all eight views retain the accepted revised display geometry. The north taper, full body, downstream interpolation join, and Oimachi seam show no visible regression, gap, wrong-corridor turn, or renewed transverse hook.

These decisions cover only static zero-lane Inspector display/smooth geometry. They do not establish Main's runtime lane/family/branch ownership, ride handoff, company offsets, or actual production ink. A Main grid or a rendered-status screen without visible map/overlay remains unusable evidence and is not replaced by this receipt.

## Myoko Haneuma intervals 0–1 native receipt

`report.json` and the individual `view.json` files identify the new captures rather than relying on directory order:

- interval 0, Myoko-Kogen (`001746`) → Sekiyama (`001719`): capture prefix `000089`, `/private/tmp/jtm-shinagawa-forks-native-after/captures/000089/000000..000022` — 23 views / 69 panels, 23 captured and 0 failed; stored verdict remains `pending`.
- interval 1, Sekiyama (`001719`) → Nihongi (`001691`): capture prefix `000090`, `/private/tmp/jtm-shinagawa-forks-native-after/captures/000090/000000..000019` — 20 views / 60 panels, 20 captured and 0 failed; stored verdict remains `pending`.

Manually reviewed every `basemap.png`, `display.png`, and `smooth.png` triple: 43 views / 129 panels. All 43 basemaps are genuinely loaded with Apple roads, terrain, waterways, buildings, rail/station glyphs, or labels; no grid, blank tile, or loading placeholder is counted.

### Interval 0: Myoko-Kogen → Sekiyama

- `000000`–`000001`: the product starts within the elongated blue Myoko-Kogen station footprint and leaves on the labelled `Myoko-Haneuma-Line`. Cyan display and red smooth share the railway's northbound curve; the adjacent Sekigawa River and roads remain distinct. The endpoint has no detached cap, foldback, or transverse station exit.
- `000002`–`000005`: through the first mountain/river bends, display and smooth remain on the thin labelled Apple railway. They do not borrow the parallel river, tributaries, or local roads, and the overlapping views show no seam or source chord across a bend.
- `000006`–`000013`: the long forested middle is continuous and smoothly curved on Apple's visible blue railway glyph. No gap, corner, reversal, or excursion to a watercourse/road is visible. Much of this span exposes only cartographic rail ink amid forest/terrain, so it supports the displayed corridor but is insufficient evidence for physical or surveyed track-centre precision.
- `000014`–`000018`: the approach curves toward Sekiyama continue on the same labelled corridor. The smoothing rounds the source progression without cutting across the inside terrain or producing a new join kink; nearby streams remain visibly separate.
- `000019`–`000021`: the final approach is continuous across the shared frame edges and remains on the north–south passenger railway. No short tail, lateral hook, or last-frame road/building borrow is visible.
- `000022`: the line enters the blue Sekiyama station footprint on the same corridor and crosses its longitudinal middle continuously. This whole-line render establishes a station seam/representative rail group rather than an interval-clipped terminal cap or a surveyed platform lane.

Interval 0 visual decision: no concrete source-versus-Apple cartographic displacement, gap, wrong branch, chord, or smoothing defect is visible in the complete 23-view sequence. The forested middle remains a physical-position evidence limitation, not a confirmed alignment error.

### Interval 1: Sekiyama → Nihongi

- `000000`–`000001`: the sequence resumes at Sekiyama on the same station footprint and passenger corridor seen in interval 0. Display and smooth leave the station continuously, without a seam, detached tail, or road diversion.
- `000002`–`000007`: across rural straights and gentle bends, the product stays on the labelled Apple railway. Rectangular water bodies, streams, local roads, and field/building edges remain separate, and no source chord cuts away from the rail glyph.
- `000008`–`000011`: the forest/rural section remains continuous on the thin labelled railway with no visible kink, gap, or reversal. As in interval 0's forested span, the Apple basemap supplies representative cartographic evidence but does not expose surveyed physical track-centre detail; that is an evidence warning rather than a visible defect.
- `000012`–`000016`: through the Matsuzaki/Nihongi approach curves, cyan and red remain on the same corridor and pass roads and waterways only where the Apple railway does. The overlapping views reveal no newly straightened bend or smoothing seam.
- `000017`–`000018`: the south approach to Nihongi/Sakamoto remains continuous and aligned with the labelled rail corridor; no short spur, foldback, or incorrect water/road following is visible.
- `000019`: the product reaches the Apple Y-shaped Nihongi switchback shown again at the start of interval 2. It meets the visible south junction and follows both the station spur and the continuing northeast main without a diagonal shortcut. This supports the displayed switch/junction geometry; it does not by itself prove single ownership or absence of coincident retrace at the seam.

Interval 1 visual decision: no concrete source-versus-Apple cartographic displacement, gap, wrong branch, chord, or smoothing defect is visible in the complete 20-view sequence. The Sekiyama seam and Nihongi switchback connect to the already reviewed adjacent interval views without a visible discontinuity.

These are opaque static zero-lane Inspector renders. Coincident duplicate/retrace ink cannot be distinguished from one stroke, and the receipt does not establish Main lane/family/follow ownership or actual built ink. Together with the separate interval 2 receipt above, this covers Myoko Haneuma intervals 0–2 only; intervals 3–8 and the complete nine-interval Main scope remain outside this decision.

## Myoko Haneuma intervals 6–8 native receipt

The capture prefixes were confirmed from `report.json` and each first `view.json` in `/private/tmp/jtm-myoko-north-native-20261012`:

- interval 6, Minami-Takada (`001637`) → Takada (`001632`): prefix `000095`, `000000..000006` — 7 views / 21 panels.
- interval 7, Takada (`001632`) → Kasugayama (`001613`): prefix `000096`, `000000..000012` — 13 views / 39 panels.
- interval 8, Kasugayama (`001613`) → Naoetsu (`001600`): prefix `000097`, `000000..000009` — 10 views / 30 panels.

All 30 `basemap.png` / `display.png` / `smooth.png` triples were manually reviewed, 90 panels total. The report records 30 captures and 0 failures. Every basemap is loaded with Apple roads, buildings, waterways, railway labels, or station/multi-track glyphs; none is a grid, blank tile, or loading placeholder.

### Interval 6: Minami-Takada → Takada

- `000000`–`000002`: cyan display and red smooth remain on the labelled north–south `Myoko-Haneuma-Line` through the Minami-Takada departure and urban corridor. The adjacent Oda River, small drainage channels, roads, and building edges stay distinct. The first endpoint and shared frame edges show no detached cap, hook, or jump.
- `000003`–`000004`: the slight westward progression and return toward Takada remain centred on the visible railway glyph. The Ginyō River crossing is made on the railway; there is no watercourse borrow, straight chord, or smoothing corner.
- `000005`–`000006`: the line enters the blue Takada multi-track/station footprint continuously and remains within its longitudinal passenger rail group. Display and smooth do not divert to Route 198 or neighbouring streets. Parallel Apple tracks prevent an individual engineering-lane claim, but no wrong-corridor segment or short terminal foldback is visible.

Interval 6 decision: no confirmed visual displacement, gap, wrong branch, chord, or smoothing defect in all seven views.

### Interval 7: Takada → Kasugayama

- `000000`–`000002`: the sequence leaves the same Takada station group and follows the labelled line north through the urban corridor. The station seam with interval 6 is continuous and the line does not borrow the adjacent road or drainage channel.
- `000003`–`000006`: through the broad northwest bend at Kitancho/Tsuchihashi, display and smooth follow the entire Apple rail curve. The line crosses Route 13 and the local waterways only where the Apple railway does; no source chord cuts across fields or buildings.
- `000007`–`000010`: the long northbound straight across fields, the Hokuriku Expressway, and the Shozenji River remains on the labelled railway. Overlapping frames expose no gap, lateral step, or new kink.
- `000011`–`000012`: the product reaches the blue Kasugayama station footprint beside Joetsu City Hall on the same corridor. The interval seam is continuous, and the representative stroke stays inside the multi-track/station group without a detached tail or turn onto Kenshinko-Odori.

Interval 7 decision: no confirmed visual displacement, gap, wrong branch, chord, or smoothing defect in all 13 views.

### Interval 8: Kasugayama → Naoetsu

- `000000`–`000003`: the line resumes within the Kasugayama station group, leaves northward, and follows the gently bending Apple railway through Kasugano/Bishamonkokubunji. The seam with interval 7 and the Route 8 crossing are continuous.
- `000004`–`000006`: this is the closest visual ambiguity in the interval. The Myoko line curves northeast beside the Otagawa River and converges with the parallel Nihonkai-Hisui rail corridor. Original-size review confirms the cyan/red path stays on the labelled Myoko railway and then inside the widening Apple rail fan; it does not follow the filled river or cut across the junction. These exact views are therefore rejected as offset candidates, while the individual parallel track remains indeterminate.
- `000007`: the product continues through the expanding Naoetsu approach fan on a visible Apple track within the labelled Myoko rail group. It has no lateral jump at the fan-out and does not switch to the river or road.
- `000008`–`000009`: the last short tail crosses the broad Naoetsu multi-track footprint and ends inside the blue station box, near its longitudinal middle. It remains continuous through the station approach and has no detached cap, last-moment hook, foldback, or extension into a freight/yard spur. The dense Apple fan supports the passenger station footprint and representative band, not one surveyed platform track.

Interval 8 decision: no confirmed visual displacement, gap, wrong branch, chord, or smoothing defect in all ten views. The explicitly checked apparent-offset candidates are `000097/000004`–`000006` at the river/parallel-line convergence and `000097/000008`–`000009` in the Naoetsu fan; both remain inside the correct labelled Apple rail/station group at original resolution.

This receipt covers static zero-lane Inspector geometry only. Opaque overlap cannot establish that there is no duplicate/retrace stroke, and the multi-track station views cannot prove exact lane ownership. It does not replace Main's whole-line, folded-stem, family/follow, or terminal production receipt. The combined nine-interval conclusion also remains with the root ledger because intervals 3–5 are reviewed separately.

## Myoko Haneuma interval 2 current-v5 native receipt

The current-v5 capture is \`/private/tmp/jtm-myoko-middle-native-20261012/captures/000091/000000..000018\`. Its \`view.json\` identifies \`jp-えちごトキめき鉄道-妙高はねうまライン#2\`, Nihongi (\`001691\`) → Arai (\`001675\`), whole-line render dependency \`dc06926618ea1cab7a784e22d90fef40dd0d546acf4dc72cbb518a4f6ae507df\`, captured on 2026-10-12. Manually reviewed all 19 \`basemap.png\` / \`display.png\` / \`smooth.png\` triples, 57 panels. Every basemap is loaded with Apple rail/station glyphs, roads, terrain, buildings, or waterways; none is a grid, blank tile, or loading placeholder.

- \`000000\`–\`000001\`: Apple clearly shows the real Nihongi switchback: a northbound station spur and a northeast continuing main meet at the same south switch. Cyan display and red smooth reproduce both legs and the common switch point. They do not replace the folded topology with a direct station-to-main chord, cut across Route 261/buildings, or continue the spur as a false straight-through route.
- \`000002\`–\`000004\`: the northeast main leaves the switch on the labelled \`Myoko-Haneuma-Line\` and completes the first broad eastward bend. The product remains on the railway rather than the adjacent thin watercourse, roads, ponds, or forest boundary; the curve has no exposed join corner.
- \`000005\`–\`000008\`: through the long east-to-north rural curve, display and smooth stay on the labelled rail glyph across every overlapping frame. No chord cuts the inside of the curve, and no gap, reversal, or diversion to Route 584 or nearby streams is visible.
- \`000009\`–\`000014\`: the northbound corridor through Nakajiku, Himekawara, Oizumo, and Hirotacho remains continuous on Apple's railway. The product stays distinct from the Shibuegawa River and tributaries, and the six views show no lateral step or new smoothing kink.
- \`000015\`–\`000016\`: the Arai approach bends gently while remaining on the same passenger rail corridor. Road and river crossings occur only where the Apple railway crosses them; there is no short spur or last-curve chord.
- \`000017\`–\`000018\`: cyan/red enter the blue Arai multi-track station footprint continuously and remain inside its longitudinal passenger rail group. The seam has no detached cap, hook, or diversion to the Shibuegawa River. Apple does not expose a unique surveyed platform track inside the station fan.

Current-v5 visual decision: no concrete cartographic displacement, gap, wrong branch, switchback chord, or smoothing defect is visible in the complete 19-view sequence. The Nihongi folded topology is supported directly by the Apple rail glyph at original resolution, and the route remains continuous through the Arai station seam.

This current-v5 receipt **supersedes the earlier v4 interval-2 receipt for current-render acceptance**. The older section remains historical evidence only and is not reused as proof of the v5 render. As with the other Inspector receipts, opaque coincident strokes cannot establish absence of duplicate/retrace ink, and this does not prove Main lane/family/follow ownership or actual production composition.

## Hohi Main Line intervals 27–35 current-v5 native receipt

The assigned capture prefixes were matched by each `view.json` `itemID` and checked against the expected viewpoint counts in `/private/tmp/jtm-hohi-full-native-20261012/plan.json`:

- interval 27, station `009628` → `009623`: `captures/000991/000000..000019` — 20 views / 60 panels.
- interval 28, station `009623` → `009614`: `captures/000992/000000..000016` — 17 views / 51 panels.
- interval 29, station `009614` → `009587`: `captures/000993/000000..000023` — 24 views / 72 panels.
- interval 30, station `009587` → `009573`: `captures/000995/000000..000017` — 18 views / 54 panels.
- interval 31, station `009573` → `009555`: `captures/000996/000000..000016` — 17 views / 51 panels.
- interval 32, station `009555` → `009548`: `captures/000997/000000..000008` — 9 views / 27 panels.
- interval 33, station `009548` → `009534`: `captures/000998/000000..000005` — 6 views / 18 panels.
- interval 34, station `009534` → `009506`: `captures/000999/000000..000008` — 9 views / 27 panels.
- interval 35, station `009506` → `009479`: `captures/001000/000000..000015` — 16 views / 48 panels.

Manually reviewed every `basemap.png`, `display.png`, and `smooth.png` triple: 136 views / 408 panels. All 136 basemaps are genuinely loaded with Apple terrain, roads, rivers, buildings, railway labels, or station/multi-track glyphs. No grid, blank tile, or loading placeholder is counted.

### Interval 27 (`000991`)

- `000000`–`000007`: display and smooth leave the first station footprint on the labelled Hohi railway, remain distinct from Route 502/local roads and the adjacent river, and follow each broad valley bend without a shortcut, detached endpoint, or frame-edge step.
- `000008`–`000016`: through the river crossings, wooded slopes, and the long sweep into the populated valley, cyan/red remain on Apple's thin railway glyph. The overlaps expose no chord across the inside of a bend, water/road borrow, gap, or new smoothing corner.
- `000017`–`000019`: the route enters the wider terminal rail/station footprint continuously and stays inside its longitudinal rail group. Parallel station tracks prevent an individual engineering-lane claim, but there is no visible wrong branch, transverse hook, or short folded tail.

Interval 27 decision: no confirmed cartographic displacement, gap, wrong corridor, chord, or smoothing defect in all 20 views. The forested stretches support a representative displayed corridor rather than surveyed track-centre precision.

### Interval 28 (`000992`)

- `000000`–`000005`: the line resumes inside the same station fan and leaves on the continuous Hohi corridor. The long diagonal and first northeast bends remain on Apple rail ink rather than nearby streets or waterways.
- `000006`–`000014`: all river-parallel and S-curve views retain the visible rail glyph through their full bends. There is no inside-bend chord, seam step, reversal, or diversion onto the river bank.
- `000015`–`000016`: display and smooth enter the next station footprint on the same corridor without a detached cap or last-view hook.

Interval 28 decision: no confirmed visual defect in all 17 views; exact track choice inside the station footprint remains cartographically ambiguous.

### Interval 29 (`000993`)

- `000000`–`000007`: cyan/red follow the labelled railway through the first rural and forest bends; roads, field boundaries, and tributaries remain separate.
- `000008`–`000015`: this is the closest river-corridor ambiguity. Original-size review confirms that the route crosses and then parallels the broad river where Apple's railway glyph does; it does not borrow the filled watercourse or cut diagonally between exposed rail segments. Every bend remains continuous across overlapping frames.
- `000016`–`000023`: the route continues through highway crossings and river loops to the next station group without a visible gap, lateral jump, short spur, or terminal foldback.

Interval 29 decision: no confirmed cartographic displacement, river borrow, chord, or smoothing defect in all 24 views. Forest and river-adjacent frames do not establish physical track-centre accuracy beyond Apple's thin cartographic railway.

### Interval 30 (`000995`)

- `000000`–`000011`: the departure and successive west/north river-valley bends stay on the Hohi railway. The line remains distinct from the broad river, highway, and local roads, with no curve shortcut or frame seam.
- `000012`–`000017`: the final river-side curves and small-station approach are continuous; the endpoint remains inside the visible station/rail footprint without a hook or detached tail.

Interval 30 decision: no confirmed visual defect in all 18 views; wooded river-valley views provide representative cartographic alignment only.

### Interval 31 (`000996`)

- `000000`–`000004`: the route leaves the small station continuously and crosses roads/water only on the visible Apple railway.
- `000005`–`000013`: all sweeping wooded-valley bends retain the thin rail glyph, including the stream crossings. No direct chord, watercourse borrow, gap, or reversal appears.
- `000014`–`000016`: the line enters the more developed multi-track endpoint within the correct rail group. The widening fan does not introduce a visible branch jump, though it cannot identify one surveyed passenger track.

Interval 31 decision: no confirmed cartographic displacement or smoothing defect in all 17 views; physical precision through the forest remains unmeasured.

### Intervals 32–34 (`000997`–`000999`)

- Interval 32, `000000`–`000008`: through the denser suburban corridor, road/stream crossings, and the broad sweep into the station footprint, display and smooth remain on the visible Hohi rail glyph. There is no gap, shortcut, wrong branch, or endpoint cap. The station fan supports the rail group but not a unique track.
- Interval 33, `000000`–`000005`: the entire short urban interval is continuous between its two station footprints. The adjacent stream and street corridor remain distinct; no foldback, seam, or short-tail defect is visible.
- Interval 34, `000000`–`000008`: the gentle urban/suburban bends and expressway crossings remain on the labelled railway through the final station approach. No road/water borrow, lateral step, or smoothing kink is visible.

Intervals 32–34 decision: no confirmed visual defect in the complete 9-, 6-, and 9-view sequences.

### Interval 35 (`001000`)

- `000000`–`000006`: the route leaves the shared station continuously and follows the visible Hohi corridor through dense Oita streets and the first parallel-rail approaches. There is no road diversion, seam, or arbitrary diagonal.
- `000007`–`000012`: original-size review of the widening junction/yard and river-crossing frames confirms that display and smooth remain on one visible Hohi approach inside the Apple rail fan. They do not jump to a street, the blue Shinkansen corridor, or the river, and the overlapping frames expose no gap or branch-switch kink.
- `000013`–`000015`: the last approach remains continuous inside the broad Oita station footprint and finishes longitudinally within the rail group. No last-frame hook, detached cap, or extension into a side spur is visible.

Interval 35 decision: no confirmed visual displacement, wrong-corridor turn, gap, or smoothing defect in all 16 views. The dense fan supports a representative Hohi passenger corridor and station footprint; it cannot resolve exact platform/engineering track ownership.

Across assigned intervals 27–35, the complete current-v5 static sequences show no concrete source-versus-Apple cartographic error, new discontinuity, bend chord, or station-tail defect. This finding is limited to these nine intervals. The renders are opaque zero-lane Inspector evidence: coincident duplicate/retrace ink cannot be ruled out, and this receipt does not establish Main lane/family/follow ownership, production composition, or a whole-line Hohi result.

## Dosan Line intervals 20–39 current-v5 native receipt

Each capture was identified from its first `view.json` `itemID`; its on-disk view/triple count matches the corresponding item in `/private/tmp/jtm-hohi-full-native-20261012/plan.json`:

- #20 `008850`→`008884`, `002822`, 19 views; #21 `008884`→`008897`, `002823`, 8; #22 `008897`→`008912`, `002824`, 7; #23 `008912`→`008946`, `002825`, 19; #24 `008946`→`009004`, `002826`, 23.
- #25 `009004`→`009009`, `002827`, 4; #26 `009009`→`009024`, `002828`, 7; #27 `009024`→`009057`, `002829`, 8; #28 `009057`→`009066`, `002830`, 10; #29 `009066`→`009071`, `002831`, 7.
- #30 `009071`→`009059`, `002833`, 5; #31 `009059`→`009061`, `002834`, 6; #32 `009061`→`009095`, `002835`, 8; #33 `009095`→`009092`, `002836`, 5; #34 `009092`→`009102`, `002837`, 4.
- #35 `009102`→`009129`, `002838`, 6; #36 `009129`→`009132`, `002839`, 5; #37 `009132`→`009168`, `002840`, 5; #38 `009168`→`009169`, `002841`, 12; #39 `009169`→`009185`, `002842`, 6.

Manually reviewed every `basemap.png`, `display.png`, and `smooth.png`: 174 views / 522 panels. All 174 Apple basemaps are genuinely loaded with terrain, roads, rivers, buildings, railway labels, station footprints, or track fans. No grid, blank tile, or loading placeholder is counted.

### Mountain and river corridor, intervals 20–24

- #20 `000000`–`000018`: the complete Oboke/Yoshino River valley sequence follows the labelled Dosan railway through its long forest curves, river crossings, and station endpoints. Display and smooth do not borrow Route 32, local roads, or the river. No curve chord, frame-edge step, detached station cap, or reversal is visible.
- #21 `000000`–`000007`: the route continues along the narrow river valley and enters/leaves the next station footprint continuously. The line remains on Apple rail ink through all bends and does not switch to the adjacent road or watercourse.
- #22 `000000`–`000006`: the full river bend and station approach remain continuous on the railway; cyan/red cross the tributary only where the Apple rail does. No short tail, wrong-bank diversion, or smoothing corner is visible.
- #23 `000000`–`000018`: all 19 forested mountain views preserve the actual succession of broad left/right rail curves from the river station to the next station footprint. The product does not replace them with a direct chord across terrain or follow the numerous winding mountain roads. The last station seam remains connected without a foldback.
- #24 `000000`–`000022`: all 23 views carry the line through the remaining mountain sweeps, the transition onto the open plateau, and the long approach into the urban station group. The bends are continuous and the smoothing does not expose a corner or cut across the inside terrain. The final urban views remain in the labelled rail band.

Intervals 20–24 decision: no confirmed cartographic displacement, road/river borrow, missing real curve, chord, gap, or endpoint defect. Long forested/tunnel-like portions expose only Apple's representative railway glyph and therefore do not prove surveyed physical track-centre placement.

### Kochi plain and urban approach, intervals 25–30

- #25 `000000`–`000003`: the short station-to-station sequence follows the visible southwest curve and adjacent straight rail band without a branch jump or endpoint seam.
- #26 `000000`–`000006`: the full diagonal urban/rural corridor stays on the Dosan railway through roads, drainage channels, and both station footprints; no canal/road borrow or lateral step is visible.
- #27 `000000`–`000007`: the line remains centred on the visible railway through the gentle approach curve and wider station footprint. The broad fan supports the correct corridor but not one engineering track.
- #28 `000000`–`000009`: across the long east–west plain, road and drainage crossings, and the two station groups, display/smooth remain on the Dosan rail glyph. No straight-line gap or diversion to the parallel Tosaden corridor appears.
- #29 `000000`–`000006`: the sequence stays on the northern Dosan corridor through the river bridge and widening junction/station fan. The southern Tosaden line and filled river remain visibly separate; no cross-fan branch jump is exposed.
- #30 `000000`–`000004`: the route continues through the same multi-track approach, follows the visible curve, and ends inside the next station group without a hook, gap, or switch to the adjacent railway.

Intervals 25–30 decision: no confirmed visual displacement, wrong corridor, river/road borrow, gap, or smoothing defect. Multi-track stations establish a representative Dosan rail group rather than exact platform track ownership.

### Kochi urban corridor, intervals 31–39

- #31 `000000`–`000005`: all six views follow the labelled railway through its shallow urban curve, waterways, roads, and station seams without a discontinuity or branch switch.
- #32 `000000`–`000007`: the route crosses the Kokubu River and completes the visible bend into the east–west urban rail band. Display/smooth remain on the railway and do not take the bridge road or river.
- #33 `000000`–`000004` and #34 `000000`–`000003`: both short urban intervals remain continuous on the same straight/gently curving rail band through their full station footprints; no short cap, lateral step, or street borrow is visible.
- #35 `000000`–`000005`: the full southern sweep and return to the urban station band are preserved. The route does not chord the large curve across the city grid or switch to nearby roads at either end.
- #36 `000000`–`000004` and #37 `000000`–`000004`: all broad city bends, overpasses, the Kagami River crossing, and their station endpoints remain on the labelled Dosan railway without a gap or wrong-bridge choice.
- #38 `000000`–`000011`: the complete 12-view sequence follows the Dosan corridor through parallel rail/road/waterway geometry and multiple station footprints. The red smooth line stays on the same Apple rail band through every bend and does not migrate to the nearby Tosaden Ino line or Ujigawa River.
- #39 `000000`–`000005`: the final assigned interval remains continuous through the river crossing and parallel station bands, ending within the visible station footprint without a detached cap, hook, or track-family jump.

Intervals 31–39 decision: no confirmed cartographic displacement, wrong parallel railway, missing bend, gap, or endpoint defect. Dense urban station fans and coincident-looking rail ink do not reveal a unique passenger/engineering lane.

Across assigned Dosan intervals 20–39, the complete current-v5 static sequences show no concrete source-versus-Apple cartographic error, lost switch/curve, new discontinuity, curve chord, or station-tail defect. This receipt covers these 20 intervals only, not the entire 60-interval line. These are opaque zero-lane Inspector renders: they cannot rule out coincident duplicate/retrace strokes or establish Main lane/family/follow ownership and production composition.

## Dosan interval 23 Shingai reference-candidate receipt

The 19 views at `/private/tmp/jtm-hohi-full-native-20261012/captures/002825/000000..000018` identify `jp-四国旅客鉄道-土讃線#23`; every `view.json` records `referenceLineID` `jp-四国旅客鉄道-土讃線` and `referenceIntervalIndex` 23. Manually reviewed every loaded `basemap.png`, current `display.png`, current `smooth.png`, and new `reference.png`: 19 views / 76 panels.

- `000000`–`000015`: the orange reference preserves the already reviewed Dosan main through every forest curve. It remains coincident with the same labelled Apple rail corridor as the cyan/red current render, introduces no chord, kink, road borrow, or lateral switch, and does not alter the junction geometry before the Shingai approach.
- `000016`: at the first clear station/junction view, the orange reference retains the main-line curve and cusp on Apple's visible main. Its added branch leaves from that same cusp and follows the blue station spur; it does not invent a second junction farther up the main or cut across the adjacent mountain road.
- `000017`–`000018`: original-size comparison confirms that the orange branch runs longitudinally inside the elongated blue Shingai station/platform footprint and ends around its longitudinal middle. It does not stop at the footprint's near/south edge, overshoot through its far end, or fold back. The shared cusp and continuing main remain in their prior positions and show no visible corner or disconnected branch seam.

Bounded visual decision: **accept the interval-23 Shingai reference candidate for display-cartographic promotion**. The full 19-view candidate keeps the existing main and cusp while adding the cartographically supported station spur to the platform footprint's longitudinal middle. This is an unpromoted `reference.png` decision only; it is not evidence that the candidate is present in current Inspector display/smooth or Main production ink. Apple exposes a representative station footprint rather than surveyed platform-track precision.

## Dosan interval 24 Shingai → Tosa-Yamada reference-candidate receipt

The 23 views at `/private/tmp/jtm-hohi-full-native-20261012/captures/002826/000000..000022` identify `jp-四国旅客鉄道-土讃線#24`; the checked metadata records `referenceLineID` `jp-四国旅客鉄道-土讃線` and `referenceIntervalIndex` 24. Manually reviewed every loaded `basemap.png`, current `display.png`, current `smooth.png`, and `reference.png`: 23 views / 92 panels.

- `000000`–`000001`: the orange reference begins on the same Apple Dosan main and fold cusp as the existing cyan/red render. Its Shingai spur follows the blue station rail/footprint longitudinally and ends around the footprint's middle; it neither stops at the near edge nor overshoots the far end. The candidate preserves the continuing main and cusp without adding a second junction or borrowing the nearby road.
- `000002`–`000015`: through every mountain and forest curve, the orange reference follows the same labelled Apple Dosan rail glyph as the current display/smooth. No direct terrain chord, corner, gap, road borrow, or wrong parallel trace is visible.
- `000016`–`000019`: across the transition from the mountain corridor to the open plateau and built-up approach, the candidate remains continuous on the visible railway. It does not step laterally at the change in map context or expose a new seam.
- `000020`–`000022`: the final approach remains in the correct Tosa-Yamada rail group and station footprint. The candidate reaches the destination longitudinally without a hook, detached short cap, or loss of the last station segment.

Bounded visual decision: **accept the interval-24 reference candidate for display-cartographic promotion**. Across the full Shingai→Tosa-Yamada sequence it preserves the supported Shingai station-middle spur, fold cusp and main, then follows the same Apple rail corridor continuously to the destination. This is a reference-only decision; it does not show the candidate in current Inspector display/smooth or Main AFTER. Apple's rail glyph and station footprints support representative cartographic placement, not a surveyed engineering lane.

This 23-quad set is the only current-reference evidence asserted by this receipt. Because the global current reference changed after the earlier interval-23 capture, the captured counter and the old #23 reference images do not refresh or establish current-reference coverage for #23; that earlier receipt remains historical evidence for the candidate version it displayed.

## Dosan interval 6 Sanuki-Saida → Tsubojiri reference-candidate receipt

The 24 views at `/private/tmp/jtm-myoko-middle-native-20261012/captures/002865/000000..000023` identify `jp-四国旅客鉄道-土讃線#6`; the checked first and last metadata record `referenceLineID` `jp-四国旅客鉄道-土讃線` and `referenceIntervalIndex` 6. Manually reviewed every loaded `basemap.png`, current `display.png`, current `smooth.png`, and `reference.png`: 24 views / 96 panels.

- `000000`–`000002`: the orange reference starts longitudinally within the Sanuki-Saida station frame and leaves on the same Apple Dosan railway as the current render. It preserves the station approach curve without an endpoint hook, lateral jump, or road borrow.
- `000003`–`000019`: the candidate follows the same Apple Dosan cartographic rail glyph through the complete mountain sequence. The long curves, direction changes, and narrow forest corridor remain intact; no terrain chord, new corner, gap, or substitution of the nearby winding roads is visible.
- `000020`–`000021`: the orange trace preserves the approach into the Tsubojiri switchback area and follows the mapped rail bend around the river/clearing. The fold geometry and continuing rail are unchanged, with no premature diagonal shortcut into the station.
- `000022`–`000023`: original-size comparison shows the candidate entering the blue Tsubojiri station frame on the Apple rail axis and ending around the frame's longitudinal middle. It does not stop at the near edge, run through the far end, fold back, or disturb the adjoining rail curve.

Bounded visual decision: **accept the interval-6 Tsubojiri reference candidate for representative display-cartographic promotion**. The full Sanuki-Saida→Tsubojiri sequence retains the Apple-supported rail curves and switchback approach while placing the terminal endpoint at the station frame's longitudinal middle. This is an unpromoted `reference.png` decision only; it does not establish current Inspector display/smooth or Main AFTER behavior, and Apple's station frame does not resolve a surveyed engineering track. The separate interval-7 duplicate-point issue is outside this capture and this decision.

## Dosan Shingai and Tsubojiri updated-data native AFTER receipt

Manually reviewed every loaded `basemap.png`, `display.png`, and `smooth.png` in the two current-v5 updated-data captures: 43 views / 129 panels.

- Dosan #23, `/private/tmp/jtm-dosan-station-centres-native-after-primary/captures/002825/000000..000018`, 19 triples. `000000`–`000015` retain every previously accepted mountain curve without a chord, gap, road borrow, or new smoothing corner. In `000016`–`000018`, the cyan display and red smooth render preserve the continuing Apple main and its fold cusp while adding the Shingai station spur on the blue station axis. The spur reaches approximately the station frame's longitudinal middle; it neither stops at the near edge nor overshoots, and the shared cusp is connected without a second junction. **Pass for the scoped Inspector AFTER rendering of the applied Shingai update.**
- Dosan #6, `/private/tmp/jtm-dosan-station-centres-native-after-west/captures/002865/000000..000023`, 24 triples. `000000`–`000021` retain the full Sanuki-Saida departure, mountain curves, and Tsubojiri switchback approach without a chord, gap, road borrow, or altered cusp. Rechecking the plan metadata resolves the apparent continuation in original-size `000022`–`000023`: Tsubojiri is the intermediate ownership seam between #6 and #7 on one through railway part, not the end of the railway. The #6 identity `display` ends at station-frame midpoint A `[133.82353637323274, 34.05422071479742]`, and #7 identity `display` starts at exactly A. Inspector `renderedDisplay` deliberately clips the shared original part 1 to the camera, so it continues southeast along the same Apple Dosan rail curve; the adjacent #7 capture uses the same rendered part and begins its selected interval at A. The continuation is therefore required context rather than a 423 m terminal tail. No actual offset, shortcut, branch jump, or seam kink is visible at A. **Pass for the scoped Inspector AFTER rendering of the applied Tsubojiri seam update.**

This receipt establishes only zero-lane Inspector current-v5 rendering for these two intervals. It does not establish Main production AFTER, lane/family/follow ownership, or surveyed engineering-track placement. The separate Dosan #7 duplicate-point repair is outside these captures.

## Joetsu Line intervals 0–16 current-v5 native receipt

Reviewed every loaded `basemap.png`, `display.png`, and `smooth.png` under `/private/tmp/jtm-joetsu-full-native-20261012-trunk/captures` for the captures whose `view.json` identity is `jp-東日本旅客鉄道-上越線#0` through `#16`: 266 views / 798 panels. Directory order was not used as interval order. All 266 basemaps contain rendered Apple map content; no grid, blank tile, or loading placeholder is counted. The evidence package is `2025.5.2`; the shared line dependency is `7d0a8da6b084144c6c8290903bf5d0e35eace925ffac21db5c1507eb1ffd5811`.

- #0 `002389`→`002355`, capture `004322`, 9 views, dependency `03edc58234fed603a1e4b4eb668fdf72ca6120d73ecdd5d94d361830fdc9a0f2`; #1 `002355`→`002340`, `004323`, 5, `5b48e57b217c7b3a810d2f794b8c8de13c5bcce5f7a6c4e7be666e6d70e8fc91`; #2 `002340`→`002301`, `004334`, 11, `0c8be37ff6a0bf4e528717710e7a91b6aae8b668fb466eaf341b6c72cc522eac`.
- #3 `002301`→`002247`, `004345`, 15, `848223b0843d2a7908fcef12d84c3e1e3d0614000ca41736ee2c06b0c47b33a2`; #4 `002247`→`002209`, `004350`, 18, `ff0aa6c0c8413c0b098be22e4a7af81225912dccdb358dd5caa81b6db933cfc1`; #5 `002209`→`002188`, `004351`, 11, `4495803ac5ff108a440a9a7b8945030f4607d7c3644a05c9e2ac046930e849dc`.
- #6 `002188`→`002144`, `004352`, 19, `d8d6df00aa2872d14cf5577531776b8196a57b44d211532b24b9b3668ddc9f50`; #7 `002144`→`002112`, `004353`, 11, `b71320ab81a5f3f2f8d6494d6277ee43926720906a9b39466dec0273b0bace14`; #8 `002112`→`002071`, `004354`, 18, `2589a637125b6281dcfc8c08c8c4f38d50fd649d3305c7666b3166d9a21f22a2`.
- #9 `002071`→`002035`, `004355`, 16, `983572d64c1db5b8ce681b15e8e1f0be66547365068754942dc0b79a738dfbae`; #10 `002035`→`001977`, `004324`, 17, `ff2cd172df52d292021a693b33b619c930dbd332c227024488040c84ce86c7c9`; #11 `001977`→`001877`, `004325`, 22, `90a396098751815596c64c18da0ff13780d7e660b9e8b2a39630bbccba6bf61f`.
- #12 `001877`→`001813`, `004326`, 17, `8396972e11f89b381a1a9c4b5cbb0ea6a6a0f317e3b9d27a92bfac8d707384e3`; #13 `001813`→`001794`, `004327`, 12, `69efdd71b8c91819b3ece0f0ba1d98804545911e95223d6a0bc4748cbe58c95b`; #14 `001794`→`001775`, `004328`, 12, `3e2be06bae4caafa7dc143b2780902f477a4101f65bda55d3ca0620f76f314c5`.
- #15 `001775`→`001739`, `004329`, 31, `7d58d4d53181a31eacbac8abf70abf2e24100d8eb6e51a640c9aaaeb7bd50656`; #16 `001739`→`001728`, `004330`, 22, `2a7e571a9c01eda3cd520db57ee74b4eae0ac36ee6902c989f7370a47ca2a2fb`.

### Visible surface corridor, intervals 0–11

- #0–5: every urban/plain departure, shallow bend, road crossing, river crossing, and station approach remains on the same Apple railway band. Display and smooth do not borrow roads, drainage channels, or nearby rail corridors. Dense station fans support the selected representative corridor but do not identify one surveyed passenger track.
- #6–10: the full river-valley sequences preserve the visible bank-side railway curves and bridge approaches. No wrong-bank jump, curve chord, detached station cap, seam step, or foldback is visible. Around #8 `000008`–`000010`, Apple shows parallel railway traces; the render stays within that railway group, but the images do not resolve exact engineering-lane ownership.
- #11: all 22 views remain continuous through the narrowing river corridor, wooded bends, and endpoint station footprint. Roads, expressway structures, and river edges remain distinct from the rendered railway. No visible gap, shortcut, or last-view hook appears.

### Mountain tunnel transition, intervals 12–16

- #12 `000000`–`000008` follows the visible valley railway through the station and river bends. From roughly `000009` onward the route enters mountain/forest where Apple does not expose a continuously identifiable surface rail glyph; the displayed diagonal/tunnel continuation therefore cannot be accepted or rejected against the basemap alone. The visible portal/valley approach and the later station/rail fan reconnect continuously without a confirmed wrong-corridor turn.
- #13 preserves the visible station/valley curves at both exposed ends. Frames spanning the mountain transition include terrain with no independently readable railway alignment, so the concealed portion remains **WARNING: Apple basemap cannot verify underground geometry**. No exposed-end kink, reversal, or disconnected cap is visible.
- #14 is dominated by green mountain terrain and underground continuation. Faint blue diagonal features in these frames are not sufficiently identifiable as the conventional Joetsu railway, so they were not used as alignment proof. The complete 12-view render is continuous, but its underground placement remains a basemap-evidence WARNING rather than a visual pass.
- #15 `000000`–`000028` likewise crosses a long concealed mountain section. Nearby diagonal blue lines and winding access features cannot establish the underground rail centre. At `000029`–`000030`, the line emerges into the visible station/rail footprint continuously and without a short cap or wrong approach. The concealed middle remains unverified.
- #16 `000000`–`000017` carries the route through another mountain/tunnel sequence. Ski/access lines, roads, streams, and faint map strokes are not treated as railway proof. In `000018`–`000021`, the rendered curve rejoins the visible built-up railway/station corridor without a confirmed seam kink, road borrow, or endpoint hook. The hidden portion remains unverified.

Scoped decision: across intervals 0–11 and the exposed approaches/portals/station footprints in #12–16, no concrete source-versus-Apple cartographic displacement, lost real curve, wrong railway, discontinuity, or endpoint defect is visible. The long underground portions of #12–16 remain explicit evidence gaps; continuity of cyan/red ink there is not Apple alignment proof. Intermediate-station continuation beyond a selected interval endpoint is expected whole-part context and was not classified as overshoot. This receipt covers only Joetsu intervals 0–16 (266 current-v5 views), not intervals 17–33 or the complete 34-interval line, and it does not establish Main lane/family/follow ownership or surveyed track-centre accuracy.

## Shinanoi Line intervals 7–13 current-v5 native receipt

Filtered `/private/tmp/jtm-joetsu-gala-native-after/captures` by `view.json.itemID` and manually reviewed every loaded `basemap.png`, `display.png`, and `smooth.png` for `jp-東日本旅客鉄道-篠ノ井線#7` through `#13`: 121 views / 363 panels. All basemaps contain rendered Apple map content; no grid, blank tile, or loading placeholder is counted. The evidence package is `2025.5.2`; all seven captures share `wholeLineRenderDependency` `4788bb7f889f112192f692965d2bdbd237b06cbf6de96a563ec0656b7382f346`, identity plan `identity-plan-8be979d85e9c4f6f83e8722b244e30e4fcd71ff81f05bb8b9ae68e72e41b38f2.json`, and Apple-only basemap/reference dependency.

- #7 `002345`→`002269`, capture `005684`, 27 views. The exposed departure and destination station groups use the same Apple Shinanoi railway. The long middle runs through mapped mountain/tunnel terrain; its faint diagonal map stroke is not independently strong enough to prove the concealed rail centre. No visible portal/end kink or disconnected cap appears, but the concealed middle remains **WARNING: Apple basemap cannot verify underground geometry**.
- #8 `002269`→`002228`, `005685`, 12 views. The complete plain/river-side interval follows the labelled Apple rail glyph through its bends and both station frames. No road or river-edge borrow, lateral step, missing tail, or endpoint hook is visible.
- #9 `002228`→`002215`, `005686`, 14 views. The line remains on the same Apple railway through the wooded approach, expressway crossing, river crossings, long open curve, and destination platform group. Display and smooth stay continuous with no chord or wrong-bank jump.
- #10 `002215`→`002212`, `005675`, 11 views. All open-valley bends and crossings remain on the Apple railway, and both station approaches enter their platform groups longitudinally without an exposed seam step or short cap.
- #11 `002212`→`002178`, `005676`, 19 views. The departure platform, visible valley sections, and final Obasute approach remain continuous on the Shinanoi rail glyph. Several mountain frames expose no reliable surface railway, so those concealed sections remain a basemap-evidence warning. At `000017`–`000018`, the line enters the Apple Obasute station siding/platform group and reaches the shared station seam `[138.093175, 36.502867]` around the group's longitudinal middle; it does not terminate on the nearby expressway or road.
- #12 `002178`→`002127`, `005677`, 25 views. Original-size `000000`–`000002` and metadata confirm the real Obasute switchback is retained: rendered part 0 runs from the southeast switch point near `[138.09548, 36.50107]` up the station siding to the station-middle seam, while rendered part 1 returns through that same switch point and continues northwest on the Apple main. The overlap makes the reversal visually subtle, but there is no straight chord across the fold, detached spur, or clipped through-context. The remaining curves follow the visible Apple corridor into the destination station group without a new gap or hook.
- #13 `002127`→`002096`, `005678`, 13 views. The full final interval remains on the same Apple conventional-rail corridor through the straight plain, junction approach, and dense Shinonoi station fan. The endpoint lies longitudinally within the intended platform group; adjacent parallel platform groups do not provide surveyed lane identity, but no visible branch jump, end overshoot, or short tail is present.

Scoped decision: no concrete source-versus-Apple cartographic displacement, lost real curve, wrong railway, discontinuity, or station-end defect is visible in the exposed portions of intervals #7–13. The Obasute reversal and shared station seam are present rather than flattened or clipped. Mountain/tunnel portions in #7 and #11 remain explicit Apple-basemap evidence gaps. Whole-part continuation through intermediate station seams is required context and was not classified as overshoot. This receipt covers only Shinanoi intervals 7–13, not intervals 0–6 or Main lane/family/follow ownership, and it does not establish surveyed engineering-track placement.
