# Nagasaki first-half original pixel review — 2026-10-18

Reviewed all **26/26 original basemap/smooth pairs (52 PNGs)** for own line `jp-長崎電気軌道-本線`, intervals **#0–11 inclusive**. No false corner is established by these pixels. Genuine tram street bends must be preserved. The Hamaguchi approach in #8–9 remains an unresolved alignment lead; no source candidate or production change is accepted here.

The source capture index is `/private/tmp/jtm-nagasaki-missing-20261018/capture-index.json` (53 views overall; no unavailable item IDs). This report covers only its 26 views for #0–11. All are `captured`. The originals use the standard light Apple basemap, z17, 1600×1200, basemap and smooth modes. Each pair was opened directly and visually inspected; no contact-sheet or transformed-image substitute was used.

The capture README states that complete own-line geometry is smoothed before clipping to each immutable viewport; the red stroke can therefore extend beyond the selected interval. This is isolated centreline evidence, without final lane/follow/family composition. Each receipt remains `result=pending`, `reviewFresh=false`; this report does not rewrite native acceptance. The exact metadata, paths, timestamps and recorded dependency are retained in [the viewed-original manifest](nagasaki-first-half-viewed-originals.json). The dependency is copied from receipts, not recomputed.

## Findings

| Interval | Own station interval | Pixel finding |
| --- | --- | --- |
| #0 | 住吉 → 昭和町通 | Continuous southbound street bend from Sumiyoshi; no isolated false corner established. |
| #1 | 昭和町通 → 千歳町 | Gentle street alignment; no isolated cusp established. |
| #2 | 千歳町 → 若葉町 | Gentle southward street alignment; no isolated cusp established. |
| #3 | 若葉町 → 長崎大学 | Shallow street bow toward Nagasaki University; preserve real bend. |
| #4 | 長崎大学 → 岩屋橋 | Continuous shallow transition toward Iwayabashi; no detached seam established. |
| #5 | 岩屋橋 → 浦上車庫 | Real southwest corridor transition toward the tram depot; preserve own tram bend and exclude adjacent JR rails. |
| #6 | 浦上車庫 → 大橋 | Continuous own tram corridor toward Ohashi; lateral cartographic difference unresolved. |
| #7 | 大橋 → 平和公園 | Own tram corridor toward Peace Park; no isolated cusp or depot extension established. |
| #8 | 平和公園 → 原爆資料館 | Real south-to-southeast compound street bend; Hamaguchi lateral alignment remains an unresolved lead. |
| #9 | 原爆資料館 → 大学病院 | Real diagonal-to-south Hamaguchi turn; numerical 28.23-degree lead alone does not justify deletion. |
| #10 | 大学病院 → 浦上駅前 | Continuous tram street south toward Urakami; distinct from adjacent JR station tracks. |
| #11 | 浦上駅前 → 茂里町 | Continuous southeast street curve toward Mori-machi; no detached gap established. |

The #8 corridor bends south toward southeast around Matsuyama, and #9 turns from the Hamaguchi diagonal toward the south. The saved #9 lead `[129.86407,32.77002]` (about 28.23°) is compatible with this real change of street direction. Neither #9 original pair shows an isolated V, reversal or detached transverse segment that would establish a deletion. Around the diagonal, the red stroke appears laterally displaced from the blue cartographic route in places, sometimes toward a grey block/forecourt edge. This is a bounded follow-up question requiring independently attributed own tram geometry or a more resolving own-track view; it does not support snapping to the blue glyph.

#5 also contains a genuine southwest transition toward the own tram strip/depot. #6–7 run beside a separate JR corridor and river; the nearby `NagasakiLine` railway must not substitute for the own `NagasakiElectricTramwayLine`. #10–11 remain on the own tram street east of the JR Urakami station tracks. No interval gap, branch onto JR, or isolated arbitrary station connector is established by the inspected pairs. Sumiyoshi is the beginning of this named line fragment; the pictures do not authorize extending it north to Akasako or treating it as the entire operating system terminal.

## Exact inspected originals

Every row below means **both** `basemap.png` and `smooth.png` were actually viewed. Directory paths are relative to the absolute root `/private/tmp/jtm-nagasaki-missing-20261018/alignment/captures/`. The JSON manifest contains each full absolute filename.

| Actual view ID | Capture directory |
| --- | --- |
| `jp-長崎電気軌道-本線#0#point-0` | `000000/000000` |
| `jp-長崎電気軌道-本線#0#point-1` | `000000/000001` |
| `jp-長崎電気軌道-本線#1#point-0` | `000001/000000` |
| `jp-長崎電気軌道-本線#1#point-1` | `000001/000001` |
| `jp-長崎電気軌道-本線#2#point-0` | `000012/000000` |
| `jp-長崎電気軌道-本線#2#point-1` | `000012/000001` |
| `jp-長崎電気軌道-本線#3#point-0` | `000016/000000` |
| `jp-長崎電気軌道-本線#3#point-1` | `000016/000001` |
| `jp-長崎電気軌道-本線#4#point-0` | `000017/000000` |
| `jp-長崎電気軌道-本線#4#point-1` | `000017/000001` |
| `jp-長崎電気軌道-本線#5#point-0` | `000018/000000` |
| `jp-長崎電気軌道-本線#5#point-1` | `000018/000001` |
| `jp-長崎電気軌道-本線#6#point-0` | `000019/000000` |
| `jp-長崎電気軌道-本線#6#point-1` | `000019/000001` |
| `jp-長崎電気軌道-本線#7#point-0` | `000020/000000` |
| `jp-長崎電気軌道-本線#7#point-1` | `000020/000001` |
| `jp-長崎電気軌道-本線#8#point-0` | `000021/000000` |
| `jp-長崎電気軌道-本線#8#point-1` | `000021/000001` |
| `jp-長崎電気軌道-本線#8#point-2` | `000021/000002` |
| `jp-長崎電気軌道-本線#9#point-0` | `000022/000000` |
| `jp-長崎電気軌道-本線#9#point-1` | `000022/000001` |
| `jp-長崎電気軌道-本線#10#point-0` | `000002/000000` |
| `jp-長崎電気軌道-本線#10#point-1` | `000002/000001` |
| `jp-長崎電気軌道-本線#10#point-2` | `000002/000002` |
| `jp-長崎電気軌道-本線#11#point-0` | `000003/000000` |
| `jp-長崎電気軌道-本線#11#point-1` | `000003/000001` |

## Bounds

These z17 standard-map images do not resolve individual rails, surveyed curve radius, longitudinal platform centres, exact stop caps or passenger platform edges. Lateral map differences are qualitative observations, not measured physical offsets. Blue route glyphs are cartographic evidence, not independent rail survey. Red circles/caps and the final product lane composition were not independently accepted by this isolated centreline review. Overlapping viewpoints are separate observations and are not summed as whole-line reviewed coverage.

The other 27 new views, intervals outside #0–11, earlier receipts and any parent-reviewed interval are outside this worker’s inspection manifest. No app, build, capture, test, production source/data edit or geometry repair was performed. This report and its manifest are the only outputs.
