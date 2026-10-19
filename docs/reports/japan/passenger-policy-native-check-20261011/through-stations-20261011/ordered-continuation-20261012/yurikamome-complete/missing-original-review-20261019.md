# Queue 67 Yurikamome: missing original review, 2026-10-19

All **8/8 new pairs / 16 original PNGs** were actually opened individually at original detail: interval 0 新橋→汐留 (3 pairs), interval 1 汐留→竹芝 (5 pairs). No confirmed false V, isolated sharp connector, wrong-line transfer, or discontinuity supports a geometry repair in these two intervals. Preserve the real compound curves. No candidate is proposed.

The capture result is evidenceReady, 8 captured / 0 failed / 0 pending, PID 87042, updated 2026-10-19T05:41:08Z. These capture counts are availability evidence; the findings below come from the actual originals. Native receipt review fields remain pending; this document does not mutate them or grant whole-line acceptance.

## Exact original evidence

Session: `/private/tmp/jtm-yurikamome-missing-20261019`. Capture index: `capture-index.json`; exact complete file paths and per-view findings are retained in `missing-original-review-viewed-manifest-20261019.json`. Each directory below had both `basemap.png` and `smooth.png` actually viewed, rather than a contact sheet or generated overlay.

| Interval | Point | Original directory | Viewed |
|---|---:|---|---|
| #0 | 0 | `/private/tmp/jtm-yurikamome-missing-20261019/alignment/captures/000000/000000` | basemap + smooth, original |
| #0 | 1 | `/private/tmp/jtm-yurikamome-missing-20261019/alignment/captures/000000/000001` | basemap + smooth, original |
| #0 | 2 | `/private/tmp/jtm-yurikamome-missing-20261019/alignment/captures/000000/000002` | basemap + smooth, original |
| #1 | 0 | `/private/tmp/jtm-yurikamome-missing-20261019/alignment/captures/000001/000000` | basemap + smooth, original |
| #1 | 1 | `/private/tmp/jtm-yurikamome-missing-20261019/alignment/captures/000001/000001` | basemap + smooth, original |
| #1 | 2 | `/private/tmp/jtm-yurikamome-missing-20261019/alignment/captures/000001/000002` | basemap + smooth, original |
| #1 | 3 | `/private/tmp/jtm-yurikamome-missing-20261019/alignment/captures/000001/000003` | basemap + smooth, original |
| #1 | 4 | `/private/tmp/jtm-yurikamome-missing-20261019/alignment/captures/000001/000004` | basemap + smooth, original |

The camera for #0 p2 and #1 p0 is identical; both separate original pairs were opened. This overlap is not additional geographic coverage. **Legacy originals viewed in this continuation: 0 pairs / 0 PNGs.** The other 58 available legacy pairs remain unviewed here, including interval 4's 13 Rainbow Bridge/loop views. The reviewed northern curves already have continuous own-corridor context, so no optional loop expansion was needed. This is not a 66-view whole-line verdict.

## Pixel findings and own-line distinction

- **#0 p0–2:** 新橋 starts east of the broad western JR multi-track group and proceeds southeast in the distinct diagonal own corridor. The turn at 汐留北 into the southwest-going 汐留 approach is rounded, continuous, and corresponds to that corridor. It is a real change of direction, not evidence to flatten it. No red detour into the JR tracks or the nearby east–west tunnel alignment is visible.
- **#1 p0–1:** Departure from 汐留 continues southwest, then gradually approaches the north–south own corridor east of JR. The station transition has no visible hook or gap. The name 汐留 and adjacent blue linework alone do not establish a subway or shared platform identity; the continuous own alignment is the reference used here.
- **#1 p1–3:** South of 汐留 the route makes a substantial eastward bend near 浜松町, then a broad southeast/southward bend toward 竹芝. Both changes have corresponding own-corridor linework in the basemap. The red stroke remains continuous, rather than taking the broad JR group to the west. Small lateral differences in cartographic strokes are insufficient to choose an exact guideway/track reference or remove controls.
- **#1 p3–4:** The curved northern approach and southwest-running 竹芝 station section remain connected without an isolated corner or endpoint hook. Western JR and monorail context are separate; no nearest-neighbor transfer is proposed.

The maps show a distinct own approach and station context at 新橋, 汐留 and 竹芝, but **full usable platform longitudinal caps, directional guideway/rail centres, and exact station-centre accuracy are not independently established by these z17 standard-map pixels**. Building shapes, labels, merged station fill and guideway casing are not a platform survey. No station point should be moved from this review, and a nearby JR/subway platform cannot substitute for an own platform.

## Relevant current source and receipt identity

Current own line is `jp-ゆりかもめ-東京臨海新交通臨海線`, package 2025.5.2, 16 stations / 15 intervals. Current source decoded controls and display controls for both reviewed intervals match the session's named identity plan **exactly by IEEE coordinate bits**, including own from/to station IDs. Plan: `/private/tmp/jtm-yurikamome-missing-20261019/alignment/identity-plan-6c2a5a20311a4c275ba7440af2a614713bbf143e667f16d59a0fe90d43357611.json`. This direct comparison avoids treating viewport-clipped, projection-round-tripped `view.sourceCoordinates` as a complete interval identity.

Source/display are equal for these two captured intervals: 12 decoded controls for #0, 45 for #1. Own source is attributable to `app/data/rail-sections.json` (MLIT N02-25):

| Interval | Raw feature index (zero-based) | Direction | Raw oriented controls | Current decoded interior |
|---|---:|---|---|---|
| 0 | 21004 | reverse | 0..9 (all 10) | 1..10 |
| 1 | 21011 | reverse | 0..42 (all 43) | 1..43 |

Both raw features explicitly carry `N02_003=東京臨海新交通臨海線` and `N02_004=ゆりかもめ`. Physical station anchors are the two decoded endpoints, not asserted to be raw section endpoints. #1's compact source segment uses the previous segment endpoint as its decoded start. This is original own N02 shape, not a newly introduced display alias. N02 identity does not turn the basemap into an independent passenger-platform survey.

## Rendering bounds and disposition

Both modes are 1600×1200, standard/light, north-up flat z17, 350m sample spacing. The recorded contract is `inspector-centreline-v5-preserve-small-survey-curves;specified-capture-v3;projection-witness-v1`, isolated own centreline (ownLane=0, mainLane=0), with complete own display smoothed before immutable viewport clipping. Whole-line dependency is recorded verbatim: `3c892929a27280e7bf9c28c88e37f9550d7051d3a727c0698fa18fc73217018f`. This does not measure final Main lanes/follows/joins or prove unseen parts of the line.

**Disposition:** preserve #0/#1 reviewed source/display geometry; no source-ready error or station-centre candidate is established. Retain actual elevated/compound bends. Exact own platform caps remain unresolved. No native capture, app control, build, test, source edit or production mutation was performed in this review; only this report and the viewed manifest were written.
