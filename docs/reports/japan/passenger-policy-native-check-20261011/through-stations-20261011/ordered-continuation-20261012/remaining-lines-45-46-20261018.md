# Queue45–46 retained evidence preparation — 2026-10-18

Scoped query of the existing BatchEvidence plan, selected receipts and current own interval/station identities only. No national scan, app capture, production mutation or whole-line acceptance.

| Queue | Own line | Intervals | Legacy planned views | Retained current matches | Missing planned views |
| --- | --- | ---: | ---: | ---: | ---: |
| 45 | 豊橋鉄道 東田本線 | 12 | 30 | 2 (#9) | 28 |
| 46 | 長崎電気軌道 本線 | 24 | 55 | 2 (#21) | 53 |

The retained four states are captured, exact own source/display/station identities match, and named files exist with matching receipt byte counts. Content digests were not recomputed. These are old isolated zero-lane fixed-z17 receipts, not current dependency admission or production composition proof. Full scoped detail is `/private/tmp/jtm-45-46-receipt-detail.json`.

Actually viewed four original images: `smooth.png` and `basemap.png` at `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/008660/000001/` (Toyohashi #9) and `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/009069/000000/` (Nagasaki #21). Toyohashi's controls at [137.39019,34.76308] / [137.38987,34.76289] encode the real Shin-kawa street turn (52.67°/35.86°); the red approach visibly follows the identified tram corridor around the intersection at this scale. Nagasaki's [129.87636,32.74396] / [129.87658,32.74396] controls (47.46°/28.59°) sit at the real Nishihamamachi river-side bend; the visible own tram path turns there too. Neither numerical angle alone supports deleting these bends. Exact platform centres and track-level residuals remain unmeasured.

Other unviewed leads: Toyohashi #8 v7 [137.39063,34.76768] 27.59° and #11 v5 [137.3834,34.76326] 26.15°; Nagasaki #9 v4 [129.86407,32.77002] 28.23° and #19 v9 [129.87428,32.74235] 27.48°. These lack retained views in the selected inventory. Next native work should request missing intervals through the unified app, preserving the four valid historical originals; no duplicate app or scan engine is needed.

The first reuse of the prior scoped query stopped when no retained view existed for a numerical lead. The read-only scratch query was corrected to report missing evidence explicitly, and completed; no production behavior changed.
