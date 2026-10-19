# Keikyu Airport V5 — Primary native visual review

Verdict: **ACCEPT for this Primary Inspector candidate rendering**, with the evidence limits below. This is a pixel review of the actual native basemap/display/smooth captures; the zero-failure report and internal distance values were not used as Apple-alignment proof.

## Coverage receipt

- Reviewed every basemap/display/smooth panel for all 27 viewpoints: 81 panels total.
- Contact pages opened at original detail: `review-0.jpg` through `review-8.jpg`.
- Underlying full-resolution triples checked as needed under `captures/001329` through `captures/001334`.
- Capture mapping: `001329` = interval 0 (4 views), `001330` = interval 1 (4), `001331` = interval 2 (3), `001332` = interval 3 (4), `001333` = interval 4 (5), `001334` = interval 5 (7).
- Every panel is a readable 1024×768 PNG. All 27 `view.json` files identify `jp-京浜急行電鉄-空港線`, the expected interval index, `referenceDependency: Apple-only`, and the same `wholeLineRenderDependency` `3af34319e9ae54d158c4aff64aa9b1dfb41177172bd88a84f39635ce81a9170f`.

## Visual findings

- **#0 Kamata→Kojiya, 4/4:** The candidate follows the own Airport Line corridor out of the unchanged Kamata shared end, through the initial southeast bend and into Kojiya. Display and smooth views retain the same bend sense with no short cap, return, or new splice. The Kojiya display endpoint lies in the intended station frame; the separately shown source/physical locus does not pull the rendered line back to the old point.
- **#1 Kojiya→Otorii, 4/4:** The previously rejected northward hump before Otorii is absent. The line now holds a continuous shallow arc through the visible Keikyu band and reaches the reviewed Otorii frame without touching the upper building/frame edge. Display and smooth panels show no local V, retrace, or seam kink.
- **#2 Otorii→Anamori-Inari, 3/3:** The full short interval remains on the single own corridor. Both ends join their adjacent directions continuously, and the Anamori endpoint placement does not create a terminal-looking cap or a return toward the old physical point.
- **#3 Anamori-Inari→Tenkūbashi, 4/4:** The candidate remains continuous across the river/interchange approach and enters the diagonal Keikyu station frame. It does not turn onto the perpendicular Tokyo Monorail geometry. The smooth path preserves the same approach direction at both ends with no bridge-crossing chord or station hook.
- **#4 Tenkūbashi→Haneda Airport Terminal 3, 5/5:** All views keep the candidate on the own Keikyu east-west/diagonal guide through the airport approach. The Tenkūbashi departure, middle span, and T3 arrival form one continuous curve; no visible join appears at the source control transitions. The T3 seam is inside the reviewed own frame and continues directly into #5 rather than bending toward the Monorail boxes.
- **#5 Terminal 3→Terminal 1·2, 7/7:** Across the runway/water views, the rendered display and smooth paths preserve V5's real arc and follow the only labelled Keikyu guide. There is no constant-shift crossing, new wiggle, label-induced detour, or premature cap. The final two views carry the line continuously into the diagonal Terminal 1·2 frame and end near its longitudinal middle; the north-south Monorail station geometry remains separate.

## Evidence limits

Some airport middle panels contain faint/partly labelled underground cartography and translucent station polygons. Their identity is supported by the same continuous Keikyu guide in the overlapping neighboring views; this receipt does not claim surveyed track or platform accuracy. The visible blue source/physical geometry is intentionally distinct in places and is not treated as the accepted display locus. This receipt covers Primary only and does not establish Main, lane/family behavior, or the other two Inspector builds.
