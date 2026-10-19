# Jounan group V3 — Primary fresh native review

- Candidate SHA-256: `e5c87f0e10dfa935f766a39fdd8d2cc87b96bfa521bae4dfbef3c609a100a491`
- Fresh scope: `jp-伊予鉄道-城南線` intervals 0–10 and `jp-伊予鉄道-花園線` interval 0.
- Coverage actually opened: all 30 viewpoints and all 90 panels (`basemap.png`, `display.png`, and `smooth.png`). 城南線 counts by interval were `2,2,3,2,3,3,2,2,3,3,2` (27 views); 花園線 #0 had 3 views.
- Capture receipt: 12 complete intervals, 30 captured, 0 pending, 0 failed. The loaded basemaps contained Apple cartography rather than an empty/grid state.
- Whole-line render dependencies in the reviewed `view.json` files: 城南線 `e7309d79aefe10d27aab6021f4c48c86dbb3ee2e52f029946a6d9dafa357f1a0`; 花園線 `ee528d46d26c2343597b7dbb790350159da103e55327e37e7b6494c957143efa`.

## Visual result

**ACCEPT for the fresh Primary native rendering of these two changed lines.**

- 城南線 #2: in all three views the cyan display path follows the visible tied black railway across the east–west head and around the City Hall curve. The earlier moat/road-curb course is absent. The magenta smoothing stays on the same railway curve without a corner shortcut, cap, notch, or new return.
- Shared fork `q` and 花園線 lead-in: all three 花園線 views show the north–south line continuing from its own Minamihoribata station face to the same visible junction on 城南線. Display and smooth views have no gap, overshoot, diagonal hook, or U-turn at the join.
- 城南線 #0–1 and #3–10: every assigned view retains continuous ink through the west arm, intermediate bends, seams, and short tails. Full-resolution checks of #0 and #10 found no new cap, splice, or terminal hook; smoothing remains coincident with the displayed corridor.

This is a cartographic pixel review of the two freshly rendered lines. It does not establish surveyed railway precision, scheduled through-running at the display connector, or a physical graph join. It does not accept the other four lines in the six-line group; their earlier evidence can be reused only after the owning input/dependency equivalence is confirmed. Main and the other Inspector instances are outside this receipt.
