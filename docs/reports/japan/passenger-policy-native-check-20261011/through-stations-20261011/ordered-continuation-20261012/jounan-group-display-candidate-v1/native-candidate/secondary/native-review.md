# Secondary Inspector native review — Jounan six-line group

## Receipt

- Candidate: frozen group candidate `6453e121524c38948cbfc64d919ab0621b3f3c4e35667268368b2c6a4b7e8d1e`.
- Capture report: 29 complete intervals, 71 viewpoints, 213 panels, with zero pending and zero failed captures.
- This review opened every `basemap.png`, `display.png`, and `smooth.png` for the 44 associated-line viewpoints not covered by the existing Secondary Jounan partial receipt: Johoku 8 intervals / 20 viewpoints / 60 panels; Otemachi 4 / 10 / 30; Honmachi 4 / 9 / 27; Hanazono 1 / 3 / 9; Renraku 1 / 2 / 6. The existing `jounan-partial-native-review.md` records the other 11 intervals / 27 viewpoints / 81 panels.
- Every reviewed basemap was loaded map content rather than a grid or placeholder. The three panels were present for every viewpoint.
- Whole-line render dependencies were constant within each reviewed line: Johoku `62b80b9d8c191aa00f6e35326e011d3b4ea8397085e92a8ecf5573d0954e1b8f`; Otemachi `a215fddf936ae8f210fd21030275dc2995942189964cecfeb56f64996ef0507b`; Honmachi `e895be28fc0881047cf7b2408917c1ef65a80ee5f2b0b4b529cc6eddbca9d49c`; Hanazono `0156369be2211d5d03b4a007ff7461980913f81efbbfe91f5e6f4cf771f17a85`; Renraku `1aa85ae60f504dafb16237d655d8042e2d736bdc3df44bfe03c8e44bfd673fb1`.

## Visual result

**ACCEPT for this Secondary Inspector native centreline scope.** I found no visible cap, detached short tail, splice hook, backtrack, unintended reversal, or newly straightened corner in the 44 reviewed viewpoints.

- **Johoku:** intervals 0–7 remain continuous through the Heiwa departure, the repaired middle curves, the Shobokyoku turn, the Kaya approach, and the H6 end. The #2 and #5 bends follow one continuous cartographic corridor without the rejected bow/flat cut. The #6/#7 seam enters and leaves the Kaya curve in the same direction; smoothing does not create a cusp or a terminal cap. At Heiwa, the rendered path uses the diagonal shared face and turns toward the Johoku corridor rather than jumping to the unrelated west blue casing.
- **Otemachi:** intervals 0–3 preserve the waterfront bend, the east-west segment, the north turn, and the diagonal Furu approach. Display and smooth views agree at all seams; the Furu end does not hook toward the adjacent Takahama alignment.
- **Honmachi:** intervals 0–3 form one continuous north-south path from the H6 face to the H1 shared end. The northern and southern shared faces keep their line direction, and the full sequence has no side-arm borrow or reversal.
- **Hanazono:** all three views show a continuous turn from the shared north-south face into the east-west Hanazono corridor. Both ends remain present, with no short cap or corner overshoot.
- **Renraku:** both views preserve the distinct diagonal Heiwa departure and the southbound Kami face. The curve is monotonic and smooth; it does not borrow Johoku's westward continuation or introduce a return bend at Kami.

Apple renders several of these street-running corridors as broad translucent blue route casing, with labels and station symbols obscuring the thin rail glyph at Red Cross, Shimizu, H6, Heiwa, Furu, H1, and Kami. Those frames support representative cartographic continuity and the absence of visible rendering defects; they do not establish surveyed metre precision or prove production lane/family behavior. This receipt is limited to the Secondary Inspector's isolated centreline rendering. Main and other Inspector receipts remain separate evidence.
