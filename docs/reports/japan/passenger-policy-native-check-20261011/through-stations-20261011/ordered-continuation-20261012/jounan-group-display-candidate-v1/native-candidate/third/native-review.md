# Third Inspector native review — Jounan six-line group

Status: **ACCEPT for the complete Third Inspector six-line native centreline scope**, with the cartographic-precision warnings below. This is a manual visual receipt for the frozen candidate and is not a national-completion claim or Main acceptance.

## Receipt

- Frozen group candidate SHA-256: `6453e121524c38948cbfc64d919ab0621b3f3c4e35667268368b2c6a4b7e8d1e`.
- Opened and reviewed every `basemap.png`, `display.png`, and `smooth.png` in the Third artifact: 29 complete intervals, 71 viewpoints, and 213 panels. No viewpoint was accepted from the report counters alone.
- Capture report: 71 captured, zero pending, zero failed. `report.json` SHA-256: `112c4d4ab92a30df1ca4f997689a42b64a73602d0bd7be1fd4fc84e7d4e4e5e5`; `scope-receipts.json` SHA-256: `dd37c492e141b1281060a4fb9aae2620c69c85619b149260ead5871029b16890`.
- Every basemap contained loaded map content. Every display and smooth panel contained the expected rendered route rather than a grid, empty panel, or loading placeholder.
- Exact coverage:
  - Jounan: 11 intervals / 27 viewpoints / 81 panels; per-interval viewpoint counts `2, 2, 3, 2, 3, 3, 2, 2, 3, 3, 2`; dependency `fd73a6523d6799e7ac0a5935287716061e5f3f4cb20af6d0d76f19b4760ac8d5`.
  - Johoku: 8 / 20 / 60; counts `2, 2, 3, 3, 2, 2, 3, 3`; dependency `62b80b9d8c191aa00f6e35326e011d3b4ea8397085e92a8ecf5573d0954e1b8f`.
  - Otemachi: 4 / 10 / 30; counts `2, 3, 2, 3`; dependency `a215fddf936ae8f210fd21030275dc2995942189964cecfeb56f64996ef0507b`.
  - Honmachi: 4 / 9 / 27; counts `2, 2, 2, 3`; dependency `e895be28fc0881047cf7b2408917c1ef65a80ee5f2b0b4b529cc6eddbca9d49c`.
  - Hanazono: 1 / 3 / 9; dependency `0156369be2211d5d03b4a007ff7461980913f81efbbfe91f5e6f4cf771f17a85`.
  - Renraku: 1 / 2 / 6; dependency `1aa85ae60f504dafb16237d655d8042e2d736bdc3df44bfe03c8e44bfd673fb1`.

## Visual result

No concrete rendering defect was found. Across the full scope, the display and smooth stages remain on the same mapped tram corridor without a detached cap, splice hook, visible interval gap, self-return, wrong-line branch, or smoothing-induced flattened curve.

- **Jounan #0–#1, west junction:** both directions use the literal rounded west-to-south arm and meet the north-south stem continuously at the reviewed non-station junction. The rendering does not create a reverse U-turn or borrow the independent north arm. The serialized legal inventory contains a reversed shared west arm; that remains a source/topology warning and does not by itself establish an operational H1-to-west movement. It is not a visible candidate-rendering defect in these panels.
- **Jounan #2–#10:** the moat corners, central eastbound corridor, northern turn, Dōgo Park curve, and final Dōgo approach remain continuous. The repaired #3, #9, and #10 curves keep their visible curvature; smoothing does not cut across blocks or the park. The Dōgo terminal ends on the same corridor without overshoot, return hook, or short cap.
- **Johoku #0–#7:** the full arc remains continuous through Heiwa, the repaired #2 and #5 shallow bends, H6, Kaya, and the Furu approach. The #2 route has no rejected south bow, and #5 has no flattened crest. The #6/#7 Kaya seam enters and leaves the same north-south rail in the same direction, with no cusp or lateral jump.
- **Shared-face guards:** Johoku and Renraku use the same reviewed diagonal Heiwa face. Honmachi H6 stays on its north-south dead-end face while Johoku uses the independent east-west Loop face. Renraku reaches the shared Kami north-south face cleanly without borrowing Johoku's westward continuation.
- **Otemachi and Furu:** all four intervals preserve the waterfront bend, east-west section, north turn, and diagonal approach. Both the Johoku and Otemachi Furu views terminate on the same own-tram approach; neither hooks into the adjacent Takahama/Johoku platform fan.
- **Honmachi:** all four intervals form one continuous north-south route. The H6 and H1 ends remain on their reviewed own faces without lateral hooks or invented connectors.
- **Hanazono:** all three views preserve the north-south approach and rounded southern terminal bend. The endpoint remains on the own tram corridor and does not visit the west arm, private tracks, or nearby diagonal rail.
- **Renraku:** both views preserve the monotonic Heiwa-to-Kami connector with clean shared endpoints and no return bend.

## Cartographic evidence boundary

Apple draws several street-running locations as broad translucent transit casing, and labels or station symbols obscure parts of the thin rail glyph. This limits frame-centre precision at Red Cross, Shimizu, H6, Heiwa, Furu, H1, and Kami. Shimizu has no defensible platform body in the reviewed map frame; Red Cross body edges are weak; the Johoku H6 outline is label-interrupted. The panels support the chosen own-corridor identity, continuity, direction, and absence of visible rendering defects. They do not establish surveyed metre-level centreline or platform precision.

This receipt is limited to the Third Inspector's isolated native centreline renderings. Main remains separate evidence.
