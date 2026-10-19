# IR Kanazawa candidate1..26 — original pixel review, 2026-10-18

**Acceptance withheld.** All 13/13 original basemap/smooth pairs were actually opened and visually inspected (26 PNGs). The former V and long southern transition render continuously, but the selected northwest reference has an unresolved **own passenger-continuation identity** through the yard. Smoothness, operator identity and `track_ref=2` are insufficient to accept a potentially different own freight/yard/main track. Parent independently raised the same issue at point7. No apply is authorized by this report.

Source index: `/private/tmp/jtm-ir-kanazawa-native-20261018/capture-index.json`, 13views, no unavailable items. Standard light basemap, z18, 1600×1200, original basemap/smooth modes. This is the active decoded1..26 candidate in [the implementation note](north-boundary-implementation-20261018.md), expected one native part646controls/64,396.1m. That count/ruler is implementation context; this pixel review does not rerun generation.

## Observed rendering and unresolved identity

Northern views0–4 show a continuous broad departure curve from the retained Higashi-Kanazawa station context through the railway yard. No isolated kink, V or detached seam is visible. Red does not jump southeast onto the clearly separate Hokuriku Shinkansen. Red and the labelled IR blue glyph have visible lateral differences within the broad shaded yard; these cannot be dismissed as proof of the same passenger track.

Views6–8 cover the former V and Asanohommachi curve/river approach. The prior abrupt V is absent from the candidate red stroke, which makes a continuous heading change. **Point7 is the critical identity hold:** red follows the northwest reference while the labelled `IR Ishikawa Railway Line` curve lies visibly southeast; both remain northwest of the separate `Hokuriku Shinkansen` band. The same relationship continues into point8 and the river approach. No physical offset is calibrated from these pixels. Critical originals are both `basemap.png` and `smooth.png` in `/private/tmp/jtm-ir-kanazawa-native-20261018/alignment/captures/000000/000007/`, with adjacent `000006/` and `000008/` contexts.

The retained source chain834273931→394894111 has own railway relation4669038 membership, `route=railway`. Retained evidence does not provide directional `route=train` passenger membership. This does not prove the reference wrong, but leaves the intended passenger continuation unestablished. Explicit own passenger-route/platform/track-continuation evidence is required before acceptance. Do not pick a nearer blue stroke or another rail by proximity. Excluding Shinkansen does not select the correct conventional passenger track among yard tracks.

Views9–10 show the approximately118m southern return to generalized N02 as a longitudinal, gentle join, without a short transverse connector, reversal or abrupt station hook. This establishes only a rendering property; it does not prove a physical coalescing seam or passenger turnout. Views10–12 retain a continuous conventional station approach distinct from the eastern/southeastern Shinkansen band. Station0 and endpoint positions are documented as unchanged by the implementation; the broad station fills do not independently certify passenger-face centres/caps.

## Exact inspected originals

Each row means both original `basemap.png` and `smooth.png` were directly opened, below `/private/tmp/jtm-ir-kanazawa-native-20261018/alignment/captures/000000/`. [The JSON manifest](candidate-1-26-native-viewed-originals-20261018.json) records every full path and receipt metadata.

| Actual view ID | Directory | Observation |
| --- | --- | --- |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-0` | `000000` | Retained Higashi-Kanazawa station context; continuous departure, exact own face unproven. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-1` | `000001` | Northern curve continuous inside broad railway yard; lateral red/blue difference remains. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-2` | `000002` | Broad northern curve continuous; broad fill cannot establish passenger track. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-3` | `000003` | Continuous curve/road crossing, separate from SE Shinkansen. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-4` | `000004` | Visible displacement from labelled IR glyph; passenger continuation unproven. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-5` | `000005` | Continuous middle approach toward former V, changing lateral relation to blue. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-6` | `000006` | Former V replaced by continuous heading change; selected NW-side reference unresolved. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-7` | `000007` | CRITICAL HOLD: red NW of labelled IR curve at Asanohommachi; passenger continuation unresolved. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-8` | `000008` | NW displacement continues through river approach; separate from SE Shinkansen. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-9` | `000009` | Southern return appears longitudinal/gentle; no short transverse hook; physical passenger seam unproven. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-10` | `000010` | Continuous conventional station fan, west/NW of separate Shinkansen band; exact face unaccepted. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-11` | `000011` | Kanazawa broad station context continuous; passenger cap/centre unproven. |
| `jp-IRいしかわ鉄道-IRいしかわ鉄道線#3#point-12` | `000012` | Retained endpoint context continuous; no Main station-circle or exact-cap acceptance. |

## Bounds

All13 receipts remain `pending`, `reviewFresh=false`. Their recorded dependency is `599dbcbe9900b6eec629c5fccfc3b5d9eb2896c87c5583b26dbd1defe5cd98f0`, copied without recalculation. Contract: `inspector-centreline-v5-preserve-small-survey-curves;specified-capture-v3;projection-witness-v1`; whole-own-line smoothing before viewport clipping, isolated centreline without final lanes/follows/joins/family composition. Overlapping observations are not additive unique geographic coverage.

No app/native/capture, build, test, source or production edit occurred. This worker wrote only the report/manifest. Parent independent key-pixel review and passenger-reference resolution remain required; no whole-line or final Main acceptance is implied.
