# Main native review — Jounan six-line group

Status: **ACCEPT for the complete frozen six-line Main capture scope**. All 29 interval ON/OFF pairs and the full-context ON/OFF pair were opened and reviewed, 60 panels total. No concrete rendering, station-face, continuity, hook, cap, false-join, or direction defect was found.

**Superseded for full-network acceptance by the Root review below.** The 60-panel coverage and the other interval findings remain valid.

## Receipt

- Frozen group candidate SHA-256: `6453e121524c38948cbfc64d919ab0621b3f3c4e35667268368b2c6a4b7e8d1e`.
- Opened every interval basemap and overlay pair: Jounan #00–#10 (11), Johoku #00–#07 (8), Otemachi #00–#03 (4), Honmachi #00–#03 (4), Hanazono #00 (1), and Renraku #00 (1). This is 29 pairs / 58 interval panels.
- Opened `full-six-line-context-basemap.png` and `full-six-line-context-overlay.png`, bringing reviewed coverage to 30 pairs / 60 panels.
- Every basemap was loaded map content, and every overlay contained the expected Main route and station annotations. The supplied full-path bounds, 3,497-vertex full-context count, and zero-budget-drop results were treated as capture metadata; the verdict comes from the pixels.

## Visual findings

No concrete defect appears in the complete scope. Main's simultaneous rendering adds nearby route strokes and station labels that are absent from an isolated Inspector, but all six reviewed lines remain distinguishable and retain the frozen candidate's own station anchors.

- **Jounan #00, Honmachi 1 / west junction / Nishihoribata:** the Honmachi 1 dot remains on the north-south face while Nishihoribata remains on the east-west face. The displayed path reaches the literal rounded west-to-south junction without a detached cap, diagonal shortcut, or collapse of the two station faces.
- **Jounan #01, Nishihoribata to Minamihoribata:** the route follows the same rounded west-to-south arm and continues east from the south join. The shared west arm is traversed in the intended displayed direction; Main does not render the serialized legal-inventory retracing as an operational reverse U-turn. Minamihoribata's dot is on its own east-west corridor.
- **Jounan #02–#05, Minamihoribata through Katsuyamacho:** the moat turn, Prefectural Office bend, shallow eastbound alignment, and Okaido approach remain continuous through their reviewed station faces. There is no block-cutting chord, sidewalk shortcut, flattened corner, doubled segment, false branch, or return hook.
- **Jounan #06–#08, Katsuyamacho through Kami:** the central and northern approaches remain continuous. Station `008742` at Kami is one exact shared north-south own-frame coordinate for Jounan and Renraku; their route approaches remain visually distinguishable, while Main correctly renders a single shared anchor rather than separate faces or dots.
- **Jounan #09–#10, Dogo Park and Dogo Onsen:** the park approach retains the broad own-corridor curve without a flattened chord or source-like bow. The terminal approach ends on the diagonal Dogo Onsen face without an overshoot, return hook, or detached cap.
- **Johoku #00, Heiwa:** Johoku and Renraku meet at their exact shared diagonal Heiwa face and diverge cleanly. Main does not invent a separate west station face or displace the dot onto the broad transit casing.
- **Johoku #01–#05, Red Cross Hospital through Kiyacho:** the repaired shallow curves, crest, and northward transition remain continuous through their station dots. There is no false southward bow, flattened hump, block-cutting chord, hook, or sharp splice.
- **Johoku #06–#07, Honmachi 6 through Kayamachi to Komachi:** the Kayamachi endpoint is inside its reviewed own north-south frame in both adjacent intervals, and the two paths meet without a seam. The final curve follows the own Loop rail into Komachi without switching to the nearby Takahama track or adding an endpoint hook.
- **Otemachi #00–#03:** all four complete intervals keep their own tram corridor and endpoint representatives. The western/Otemachi alignment, JR Matsuyama frontage, rounded Miyata bend, and Komachi approach remain continuous; nearby Yosan, Takahama, and Johoku strokes do not absorb or redirect the line.
- **Honmachi #00–#03:** the four intervals form a continuous north-south sequence through Honmachi 6, 5, 4, 3, and the southern Honmachi 1 terminal. Honmachi 6 uses its own north-south dead-end face; the separate Johoku east-west position is not collapsed into it, and the line does not extend to the Loop crossing.
- **Hanazono #00:** Matsuyamashi is centred on the reviewed own east-west terminal rail, the complete bend is smooth, and the north endpoint stops on Minamihoribata's own north-south Hanazono face. The visible 40–50 px gap to the Jounan east-west crossing is the expected station-ended inventory representation: the source and candidate contain no reviewed Hanazono lane, follow, or physical connector, and the frozen proposal explicitly preserves physical topology. Extending the line to the crossing would invent a join not supported by this scope.
- **Renraku #00:** the orange connector follows its own curve between the exact shared diagonal Heiwa anchor and exact shared north-south Kami anchor. Both joins are seamless and directionally traversable, with no platform-axis hook, false branch, or duplicate station dot.
- **Full six-line context:** all six repaired lines and their termini remain visible in the wider Main composition. Their shapes agree with the interval views; the context introduces no long-range gap, clipping, reversal, or unintended merge. Other visible Main routes remain separate context and were not treated as part of this candidate's acceptance scope.

## Evidence boundary

These Main captures show multiple route layers and labels at once. Broad Apple transit casing, road shields, station labels, and overlapping route strokes limit metre-level centreline and dot-centroid judgments, especially at the west junction, City Hall/Prefectural Office, and the Kami and Heiwa shared anchors. The panels support own-corridor identity, the reviewed shared-versus-distinct station-face decisions, continuity, complete interval extent, and the absence of visible hooks or false reversals. They do not establish surveyed platform precision.

The acceptance applies to this frozen six-line candidate and its 29 complete intervals. It does not change physical records, infer operational joins absent from the data, certify unrelated Main routes, or make a national completion claim.

## Root supersession — Hanazono network continuity

Status after independent whole-network review: **REJECT for Main full-network acceptance of V1**. V1 retains correct complete-interval geometry and own station faces, but its Hanazono display ends 29.8 m short of the existing Jounan #2 point at shared physical station `008768`. Apple renders the north-south continuation, so the visible gap is a network-continuity defect rather than an expected terminal separation. The source remains candidate-only pending the V2 delta and affected Main replay.

The earlier Hanazono conclusion that extending the display would invent a physical join is withdrawn. It conflated missing display coupling with missing physical continuity. The JavaScript and Swift counterparts both append `displayBranchLeadIns` as separate display parts (`rail-network.js` and `DisplayParts.swift`), while the Swift data model describes them as non-station lead-ins retained only in the displayed network. This mechanism can preserve the Hanazono station dot and interval endpoint while drawing the supported continuation, without changing the physical graph. No other finding in this receipt is superseded.

