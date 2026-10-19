# Tsushima complete native — Secondary visual review

Reviewed 2026-10-13 from the saved Secondary captures only. I opened all 44 viewpoints and each basemap/display/smooth panel: 132 panels total. Every basemap was loaded; no blank grid or loading placeholder was treated as evidence. The seven complete intervals have counts `[7, 7, 6, 7, 6, 5, 6]`, zero pending captures, and zero failed captures. All views identify `jp-名古屋鉄道-津島線`, package `2025.5.2`, whole-line render dependency `3f1df5d5cffad0f8f9b4b47bc9d20a5724592ecf6c2fe55eaad2c02d03a1f59c`, and `Apple-only` reference dependency.

## Defect requiring repair

**REJECT current interval #5 勝幡→藤浪.** The east bridge approach contains a real displayed dogleg while Apple's own Tsushima double-blue railway remains continuous and nearly straight:

- `captures/002592/000002` (`#5#point-2`): cyan and magenta run along the own rail until about pixel `(818,216)`, notch south through roughly `(837,232)`, then return toward the straight rail. The notch is visible in both display and smooth panels and has no corresponding railway bend on the basemap.
- The same geometry is independently exposed by `captures/002592/000001` around `(506,376)→(524,394)` and by `captures/002592/000000` near the west side of the bridge. It is therefore one persistent geometry defect seen from three cameras, not label occlusion or one bad tile.
- Outside that bounded bridge/approach window, #5 points 0–4 follow the same own Tsushima rail corridor through the full interval. Points 3 and 4 show no second dogleg, parallel-line borrow, or station-return kink. A repair should retrace the complete affected bridge window between stable on-rail controls on both sides; merely hiding one rendered corner without replaying the whole interval would not establish continuity.

## Complete interval review

| Interval | Views | Result |
| --- | ---: | --- |
| #0 須ヶ口→甚目寺 | 7 | Loaded complete interval. The line leaves the 須ヶ口 shared rail fan westward in the natural tangent and then follows the own Tsushima corridor across the river; no U-turn, wrong branch, cap, or seam gap is visible. |
| #1 甚目寺→七宝 | 7 | Straight own rail corridor and both station seams remain continuous. No visible lateral jump or short tail. |
| #2 七宝→木田 | 6 | Complete straight-to-gentle-curve body reviewed; display and smooth stay on the own blue railway casing with no chord or station hook. |
| #3 木田→青塚 | 7 | Full long curve and all tails are continuous. Crossings and adjacent roads do not pull the display off the own rail. |
| #4 青塚→勝幡 | 6 | The complete curve into 勝幡 follows the own railway band; endpoints join cleanly and no additional cusp is visible. |
| #5 勝幡→藤浪 | 5 | **REJECT / repair pending:** persistent unsupported south notch at the east bridge approach in points 0–2, described above. The remainder of the body and the 藤浪 approach show no separate visible defect. |
| #6 藤浪→津島 | 6 | Loaded complete interval. The diagonal approach, bend onto the north–south Bisai corridor, and terminal tail into 津島 are continuous. The endpoint arrives in the existing shared station corridor in the forward direction; it does not reverse or invent a cross-platform connector. |

## Station and junction receipt

須ヶ口, 甚目寺, 七宝, 木田, 青塚, 勝幡, 藤浪, and 津島 were each visible in the endpoint/adjacent views. The rendered line intersects each station's own railway band or station tint; I found no concrete instance of a bead attached to a road, river edge, or neighboring railway. Apple often shows a broad blue railway/station casing rather than a sharply bounded platform rectangle in this scope, so these panels support own-corridor identity and travel direction, not metre-level longitudinal platform midpoint claims.

At 須ヶ口 the branch leaves the shared 名古屋本線 station throat toward 甚目寺 without a reverse-angle fold. At 津島 the line approaches along the same physical corridor used onward by the 尾西線; the saved single-line view ends at the station without a hook. These observations do not by themselves certify a production cross-line follow or route graph.

**Secondary verdict:** current whole-line native geometry is **not accepted** because interval #5 has a concrete, repeatable bridge dogleg. Intervals #0–4 and #6 have no other visible repair candidate in these 39 viewpoints; they remain reusable only if their display input and render dependency stay unchanged. A repaired #5 needs full-interval native replay, including both station ends and the bridge window.
