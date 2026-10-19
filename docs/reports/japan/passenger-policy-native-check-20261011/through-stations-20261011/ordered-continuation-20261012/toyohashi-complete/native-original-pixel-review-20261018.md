# Toyohashi actual original-pixel review — 2026-10-18

Read-only review of `jp-豊橋鉄道-東田本線` queue45. **All 28 original smooth/basemap pairs were actually opened and visually inspected: 56 PNGs covering the 11 newly captured intervals #0–8, #10 and #11.** This is a view inventory, not a sum of non-overlapping physical coverage. Parent retained #9 separately; this worker did not repeat or claim that review.

## Findings

No actionable corridor-level false V, reversal, detached interval seam or excursion onto a neighboring railway was found in these views. No geometry amendment is proposed from this review. The potentially sharp #8 and #11 controls are components of visible real street/forecourt turns and should remain.

- **#8 市役所前→札木:** the slant east–west street turns south near the basemap's Nishihatcho label. All three pairs show the stroke following this real tram corridor; the numerical lead `[137.39063,34.76768]` (27.59° in the existing queue note) lies in the progressive turn. A straight connection between the approach and Fudagi would cut out the street turn. These standard maps do not supply a physical track radius or tangent survey.
- **#11 駅前大通→駅前:** both pairs show the west street bending into the station-forecourt tram spur. The lead `[137.3834,34.76326]` (26.15° in the queue note) belongs to that bend. The red endpoint remains on the own tram spur and does not jump to the nearby Tokaido/Shinkansen/Atsumi fan. Exact terminal platform/rail-cap location cannot be established from these pixels.
- **Station ends:** all supplied first/last views were inspected, including Akaiwaguchi, the shared intermediate interval anchors and Eki-mae. No detached short endpoint connector or visible interval gap was found at this scale. These alignment images show the stroke; they do not establish the product's station-circle placement or complete physical stop caps.
- **Shinkawa, incidentally visible:** the full own-line red stroke includes a short diagonal/chamfer in the actual north–west street turn. It remains within the tram road corridor. This does not replace the parent's existing #9 review and does not support deleting a real turn. Small red/blue differences elsewhere also remain within broad own street bands; no numeric physical rail residual was measured.

The other inspected intervals follow the own named Azumada tram street corridor, including its shallow bends, rather than taking a shortcut across blocks or onto a parallel railway. This is corridor-level visual evidence only. Apple blue cartographic rail/route glyphs were not treated as surveyed individual tracks or used for nearest-neighbor coordinate snapping.

## Evidence and limits

Source index: `/private/tmp/jtm-toyohashi-missing-20261018/capture-index.json`. It reports 28 captured views, no failed/unavailable entries, with standard light basemap, zoom17, 1600×1200 pixels and basemap/smooth output modes. The README states these are native MKMapSnapshotter views at 1×, with the same map rectangle/viewport for both images and complete own-line smoothing before clipping. The examined #8 point1 camera reports approximately 0.978 m/point. No screenshot crop, composite or newly generated capture was substituted for the originals.

All index rows carry dependency `dd4143e7619df5d9eafa7b1e5e7d211ccc0f68c96e91fc6e211824c2718e231b`; this report records that supplied dependency and does not claim to have recomputed its digest. Captures occurred 2026-10-18 around 20:25 UTC. Metadata remains `result=pending`, `reviewFresh=false`; this report does not mutate review state or declare production/whole-line acceptance.

At this zoom, road corridors and real junction directions are visible, while individual tram rails, detailed curve transitions, narrow platform faces and whole-stop longitudinal centres are not reliably resolved. Label glyphs and wide blue bands obscure some local centreline details. The two modes do not audit multi-line color composition, station circles, train animation or product-wide runtime behavior. Distance-sample receipts, including display-vs-smooth values, are not independent Apple/physical alignment measurements and are not used to claim accuracy here.

No app operation, native capture, test, build, source/data change, candidate output or production apply was performed by this researcher. Only this report and its [exact inspected-file manifest](native-original-pixel-review-20261018.json) were written. Parent holds final review and acceptance.

## Actual inspected original files

Every table row means **both** `basemap.png` and `smooth.png` in the named directory were opened. The directory root is `/private/tmp/jtm-toyohashi-missing-20261018/alignment/captures/`. The full absolute two-file paths, unchanged metadata path/status and capture timestamp are repeated per view in the JSON manifest.

| Actual viewpoint ID | Directory suffix | Original files inspected | Finding |
| --- | --- | --- | --- |
| `jp-豊橋鉄道-東田本線#0#point-0` | `000000/000000` | `basemap.png`, `smooth.png` | Akaiwaguchi end and Ihara approach stay on the named tram street corridor; shallow road bends retained. Exact stop caps not resolved. |
| `jp-豊橋鉄道-東田本線#0#point-1` | `000000/000001` | `basemap.png`, `smooth.png` | Akaiwaguchi end and Ihara approach stay on the named tram street corridor; shallow road bends retained. Exact stop caps not resolved. |
| `jp-豊橋鉄道-東田本線#0#point-2` | `000000/000002` | `basemap.png`, `smooth.png` | Akaiwaguchi end and Ihara approach stay on the named tram street corridor; shallow road bends retained. Exact stop caps not resolved. |
| `jp-豊橋鉄道-東田本線#1#point-0` | `000001/000000` | `basemap.png`, `smooth.png` | Ihara–Keirinjo-mae follows the same longitudinal tram road, with its shallow change in bearing; no isolated V or transverse connector visible. |
| `jp-豊橋鉄道-東田本線#1#point-1` | `000001/000001` | `basemap.png`, `smooth.png` | Ihara–Keirinjo-mae follows the same longitudinal tram road, with its shallow change in bearing; no isolated V or transverse connector visible. |
| `jp-豊橋鉄道-東田本線#1#point-2` | `000001/000002` | `basemap.png`, `smooth.png` | Ihara–Keirinjo-mae follows the same longitudinal tram road, with its shallow change in bearing; no isolated V or transverse connector visible. |
| `jp-豊橋鉄道-東田本線#2#point-0` | `000004/000000` | `basemap.png`, `smooth.png` | Keirinjo-mae–Azumada remains in the tram road band; no visible gap at the shared interval end. |
| `jp-豊橋鉄道-東田本線#2#point-1` | `000004/000001` | `basemap.png`, `smooth.png` | Keirinjo-mae–Azumada remains in the tram road band; no visible gap at the shared interval end. |
| `jp-豊橋鉄道-東田本線#3#point-0` | `000005/000000` | `basemap.png`, `smooth.png` | Azumada–Azumada-sakaue follows the gentle street curve; no opposite-facing fold or isolated cusp found. |
| `jp-豊橋鉄道-東田本線#3#point-1` | `000005/000001` | `basemap.png`, `smooth.png` | Azumada–Azumada-sakaue follows the gentle street curve; no opposite-facing fold or isolated cusp found. |
| `jp-豊橋鉄道-東田本線#3#point-2` | `000005/000002` | `basemap.png`, `smooth.png` | Azumada–Azumada-sakaue follows the gentle street curve; no opposite-facing fold or isolated cusp found. |
| `jp-豊橋鉄道-東田本線#4#point-0` | `000006/000000` | `basemap.png`, `smooth.png` | Azumada-sakaue–Maehata stays within the broad road/median corridor; near-straight supports do not create an isolated jog. |
| `jp-豊橋鉄道-東田本線#4#point-1` | `000006/000001` | `basemap.png`, `smooth.png` | Azumada-sakaue–Maehata stays within the broad road/median corridor; near-straight supports do not create an isolated jog. |
| `jp-豊橋鉄道-東田本線#4#point-2` | `000006/000002` | `basemap.png`, `smooth.png` | Azumada-sakaue–Maehata stays within the broad road/median corridor; near-straight supports do not create an isolated jog. |
| `jp-豊橋鉄道-東田本線#5#point-0` | `000007/000000` | `basemap.png`, `smooth.png` | Maehata–Higashihatcho keeps the shallow real street change in bearing, with no detached station connector visible. |
| `jp-豊橋鉄道-東田本線#5#point-1` | `000007/000001` | `basemap.png`, `smooth.png` | Maehata–Higashihatcho keeps the shallow real street change in bearing, with no detached station connector visible. |
| `jp-豊橋鉄道-東田本線#6#point-0` | `000008/000000` | `basemap.png`, `smooth.png` | Higashihatcho–Toyohashikoen-mae follows the own east–west/slant street corridor and its actual road bend; no neighbor-rail inference used. |
| `jp-豊橋鉄道-東田本線#6#point-1` | `000008/000001` | `basemap.png`, `smooth.png` | Higashihatcho–Toyohashikoen-mae follows the own east–west/slant street corridor and its actual road bend; no neighbor-rail inference used. |
| `jp-豊橋鉄道-東田本線#6#point-2` | `000008/000002` | `basemap.png`, `smooth.png` | Higashihatcho–Toyohashikoen-mae follows the own east–west/slant street corridor and its actual road bend; no neighbor-rail inference used. |
| `jp-豊橋鉄道-東田本線#7#point-0` | `000009/000000` | `basemap.png`, `smooth.png` | Toyohashikoen-mae–Shiyakusho-mae stays on the slant tram road, including the approach to the east–south road turn. |
| `jp-豊橋鉄道-東田本線#7#point-1` | `000009/000001` | `basemap.png`, `smooth.png` | Toyohashikoen-mae–Shiyakusho-mae stays on the slant tram road, including the approach to the east–south road turn. |
| `jp-豊橋鉄道-東田本線#8#point-0` | `000010/000000` | `basemap.png`, `smooth.png` | Real east–south street-corridor turn near Nishihatcho; the numerical lead at [137.39063,34.76768] is part of this progressive turn. Preserve; physical curve radius/rail offset unresolved. |
| `jp-豊橋鉄道-東田本線#8#point-1` | `000010/000001` | `basemap.png`, `smooth.png` | Real east–south street-corridor turn near Nishihatcho; the numerical lead at [137.39063,34.76768] is part of this progressive turn. Preserve; physical curve radius/rail offset unresolved. |
| `jp-豊橋鉄道-東田本線#8#point-2` | `000010/000002` | `basemap.png`, `smooth.png` | Real east–south street-corridor turn near Nishihatcho; the numerical lead at [137.39063,34.76768] is part of this progressive turn. Preserve; physical curve radius/rail offset unresolved. |
| `jp-豊橋鉄道-東田本線#10#point-0` | `000002/000000` | `basemap.png`, `smooth.png` | Shinkawa–Ekimaeodori remains on the own east–west tram street. The incidental Shinkawa diagonal/chamfer is a real turn, not grounds to flatten; exact radius unresolved. |
| `jp-豊橋鉄道-東田本線#10#point-1` | `000002/000001` | `basemap.png`, `smooth.png` | Shinkawa–Ekimaeodori remains on the own east–west tram street. The incidental Shinkawa diagonal/chamfer is a real turn, not grounds to flatten; exact radius unresolved. |
| `jp-豊橋鉄道-東田本線#11#point-0` | `000003/000000` | `basemap.png`, `smooth.png` | Real turn into the station-forecourt tram spur; [137.3834,34.76326] belongs to this approach. Endpoint stays separate from the neighboring mainline fan; exact terminal cap unresolved. |
| `jp-豊橋鉄道-東田本線#11#point-1` | `000003/000001` | `basemap.png`, `smooth.png` | Real turn into the station-forecourt tram spur; [137.3834,34.76326] belongs to this approach. Endpoint stays separate from the neighboring mainline fan; exact terminal cap unresolved. |

Related parent scope note: [remaining-lines-45-46-20261018.md](../remaining-lines-45-46-20261018.md). The present report adds actual review of the 28 missing views; it does not reinterpret the prior isolated #9 receipts as a new capture or duplicate reviewed coverage.
