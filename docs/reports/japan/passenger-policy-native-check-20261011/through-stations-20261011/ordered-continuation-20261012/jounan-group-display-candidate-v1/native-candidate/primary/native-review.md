# Primary native review — six-line Jounan group

Status: **ACCEPT for the complete Primary Inspector six-line scope**, with the cartographic-clarity warnings below. This is not acceptance of the Secondary or Third Inspectors, Main, or production source application.

## Receipt

- Reviewed every `basemap.png`, `display.png`, and `smooth.png` for all 27 Jounan viewpoints (81 panels) under `/private/tmp/jtm-jounan-group-native-primary-v1/captures`.
- Interval counts `#0...#10`: `2, 2, 3, 2, 3, 3, 2, 2, 3, 3, 2`.
- Capture directories: `001584` (#0), `001585` (#1), `001587` (#2), `001588` (#3), `001589` (#4), `001590` (#5), `001591` (#6), `001592` (#7), `001593` (#8), `001594` (#9), `001586` (#10).
- Every basemap was visibly loaded. Every display and smooth panel contained the expected rendered line; none was a grid/loading placeholder.
- All 27 `view.json` files identify `jp-伊予鉄道-城南線` and share `wholeLineRenderDependency` `fd73a6523d6799e7ac0a5935287716061e5f3f4cb20af6d0d76f19b4760ac8d5`.
- Staged source SHA supplied for this run: `18a9c251ef06a2780114876ada7e6e44ea66efe28e4318f717b71a28758219c3`.

The completed Primary artifact contains 29 intervals, 71 viewpoints, and 213 panels with no missing review scope. In addition to the Jounan receipt above, I opened every panel for:

- Johoku: 20 viewpoints, interval counts `2, 2, 3, 3, 2, 2, 3, 3`, dependency `62b80b9d8c191aa00f6e35326e011d3b4ea8397085e92a8ecf5573d0954e1b8f`.
- Otemachi: 10 viewpoints, interval counts `2, 3, 2, 3`, dependency `a215fddf936ae8f210fd21030275dc2995942189964cecfeb56f64996ef0507b`.
- Honmachi: 9 viewpoints, interval counts `2, 2, 2, 3`, dependency `e895be28fc0881047cf7b2408917c1ef65a80ee5f2b0b4b529cc6eddbca9d49c`.
- Hanazono: 3 viewpoints, dependency `0156369be2211d5d03b4a007ff7461980913f81efbbfe91f5e6f4cf771f17a85`.
- Renraku: 2 viewpoints, dependency `1aa85ae60f504dafb16237d655d8042e2d736bdc3df44bfe03c8e44bfd673fb1`.

All additional basemaps were visibly loaded, and every display and smooth panel contained its expected line rather than a grid/loading placeholder.

## Visual findings

- **#0–#1, west junction and short branch:** the rendered branch, the literal non-station junction, and the eastbound corridor are present without a detached cap, loop, or spur borrowed from the crossing north-south line. Display and smooth renderings meet continuously at the reviewed junction. The sharp inventory relationship at the junction remains a topology boundary between the H1-to-junction part and the reversed west arm; these panels do not establish a direct train-passable H1-to-west movement.
- **#2–#6, central corridor:** all 15 viewpoints show a continuous line through successive station seams and road bends. The selected display and smoothed traces stay on the same Apple transit corridor; no new backtrack, crossing-lot chord, zero-length edge, or visible interval seam appears. The turns at the moat/canal corner and the later east/north transition remain rounded and connected.
- **#7–#9, north/east corridor and park curve:** all eight viewpoints preserve the northbound turn, the eastbound run, and the curve around Dōgo Park. The smooth trace follows the same visible corridor through both bends; it neither cuts across the park nor hooks into the nearby road/river geometry. Shared interval endpoints do not produce a visible gap or doubled tail.
- **#10, Dōgo terminal approach:** both viewpoints show a continuous final approach and a clean terminal end in the same mapped transit corridor. The last segment has no overshoot, return hook, or short detached cap.

## Other five lines

- **Johoku, #0–#7 (20 viewpoints):** the complete loop/arc stays continuous across the Heiwa shared area, the long western/northern arc, the Shimizu bends, the Kaya north–south section, and the southern diagonal return. The repaired #2 and #5 curves render as shallow continuous rail curves, without the rejected false bow or flattened cut. The #6/#7 Kaya seam and endpoint remain on the same north–south mapped face. At Heiwa, the selected Johoku trace follows its legal own continuation and does not jump west to the unrelated thin blue casing or borrow the Renraku diagonal as a new spur. No seam gap, self-return, or terminal cap is visible.
- **Otemachi, #0–#3 (10 viewpoints):** the waterfront turn, east–west street section, northbound turn, and diagonal continuation all remain continuous. The Furu/shared-tram end stays on the same diagonal transit corridor; it does not hook into the adjacent Takahama geometry. Both display and smooth views preserve the station-to-station direction with no crossing-lot chord or doubled endpoint.
- **Honmachi, #0–#3 (9 viewpoints):** the complete north–south route is visible through all seams. H6 remains on the Honmachi north–south face rather than the independent Johoku east–west face, and the H1 end reaches the reviewed shared coordinate without an extra connector or lateral hook. No new bend, gap, or endpoint overshoot appears.
- **Hanazono, #0 (3 viewpoints):** the full north–south line and its southern terminal curve are continuous. It stays separate from the diagonal rail and station-area geometry crossing the southern end; neither display nor smooth introduces a spur or return.
- **Renraku, #0 (2 viewpoints):** the short Heiwa-to-Kami connector remains on its reviewed curved/diagonal path and meets the shared Kami north–south face cleanly. It does not jump to the unrelated west/east casing at Heiwa or form a hook at either end.

## Evidence boundary

At this zoom, Apple often draws a broad blue transit casing and labels over the thin underlying track glyph. This is most limiting around Red Cross/Shimizu/H6 and the dense shared faces at Heiwa, Furu, H1, and Kami. The panels support representative cartographic corridor placement and continuity, but not metre-level surveyed centreline precision where the glyph is covered. Inspector counters, source agreement, and nearest-distance diagnostics were not used as pass evidence.

Raw reprojection acceptance is provenance only and was not substituted for these native captures. The group still requires the independent Secondary and Third complete native reviews and Main validation before production acceptance.
