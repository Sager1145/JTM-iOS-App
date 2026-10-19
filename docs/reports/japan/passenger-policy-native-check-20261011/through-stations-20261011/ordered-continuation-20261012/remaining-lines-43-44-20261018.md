# Queue 43–44: own-line receipt preparation (2026-10-18)

Read-only review of queue43 `jp-東日本旅客鉄道-総武線-3` and queue44 `jp-東武鉄道-伊勢崎線-2`. No production edits, tests, builds, app/native operations, external research, new captures or national hash campaign. This note records available legacy evidence and limited original-image observations; neither line is accepted here.

## Exact inventory and current identity

Capture root: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence`.

The inventory `plan.json` was read to obtain the **lexicographically sorted itemID directory map**, not risk-plan order. Each actual capture-state itemID was then checked against its slot. Each receipt's named immutable `identity-plan-<planDigest>.json` supplied the exact own interval identity. Current package compact intervals were expanded with continuation/end-station semantics and current display interval/station overrides. Source and display coordinates were compared as exact IEEE-754 UInt64 bit patterns, with exact from/to station IDs. Only these two lines' identities and receipts were compared.

| Queue / interval | Slot | Expected inventory views | Existing captured states | Current own identity matches | Missing expected views |
| --- | --- | ---: | ---: | ---: | ---: |
| 43 Sobu-3 #0 | `005751` | 7 | 7 | 7 | 0 |
| 43 Sobu-3 #1 | `005752` | 15 | 16 | 15 | 0 |
| 43 Sobu-3 #2 | `005753` | 12 | 12 | 12 | 0 |
| 43 Sobu-3 #3 | `005754` | 20 | 20 | 20 | 0 |
| 43 Sobu-3 #4 | `005755` | 9 | 9 | 9 | 0 |
| 43 Sobu-3 #5 | `005756` | 16 | 16 | 16 | 0 |
| 44 Tobu Isesaki-2 #0 | `006083` | 4 | 4 | 4 | 0 |

Sobu-3 has **79/79 expected views captured** and matching own source/display/station identity, plus one retained extra state: `captures/005752/000015/capture-state.json`. That extra state's source and from/to station IDs still match, but its display identity is stale; it is not in the current inventory's 0…14 viewpoint set for #1. Preserve it as historical evidence; do not count 80 current views. Tobu has **4/4 expected views captured** and matching own identity. All 84 existing states say `captured`, with no failed state found in these slots. Across their receipts, no listed evidence file is missing and no saved byte count differs. PNG/content SHA-256 values and whole-file immutable-plan digests were not recomputed, so these are existence/size and selected-identity findings, not fresh content-hash admission.

Named immutable plans under the capture root:

- Sobu-3 current matching #0/#1/#2 states: `identity-plan-816d3e84393027df093ffd66c6f697668274886e0055cbcee26accad065a4b1d.json`.
- Sobu-3 #3/#4/#5: `identity-plan-ca243929d9af5237145ae651192f3d6ecb23530b44a940bb978fe55c6d0db9b7.json`.
- Sobu-3 retained stale #1/view15: `identity-plan-57a1c7394e4341c4f370a98c84a73f64b909e156bdaf48f4513bcb73c0a08db6.json`.
- Tobu #0: `identity-plan-45870ba48e8a273e2c0f7ce07fceded536a0642945f8b2f39e0b2bfc9df4a47e.json`.

These are legacy isolated centreline receipts using `inspector-centreline-v5-preserve-small-survey-curves;fixed-z17-v2`, zero own/main lane offsets, z17, 1024×768 logical points, light, 1× backing. Current specified-capture/projection-witness contracts differ. Matching interval coordinates do not establish current whole-line smoothing/dependency admission, production lanes/follows/family composition, physical connections or exact platform position. No fresh current native dependency comparison was run.

## Existing own-line primary reports read first

- [Tokyo/Shinagawa source review](../tokyo-shinagawa/source-review.md): underground Tokyo Sobu ownership, independent Shinagawa passenger-pair anchor, exact adjacent display seams, retained southern Osaki follows and their limits. Underground Sobu must not be moved onto nearby surface JR cartography.
- [Tokyo/Shinagawa full-interval results](../tokyo-shinagawa/station-throats/results.md): original #1 15/15 and #2 12/12 manual paired-image review and representative Main observations. Its stated geographic/roof/underground limits remain; it does not accept the other four Sobu-3 intervals.
- [Southern branch source audit](../../../tokyo-southern-branch-audit-2026-10-01.md): own southern passenger/freight tracks and distinct Osaki fork memberships; an overlaid cartographic crossing is not a new connection.
- [Oshiage source review](../oshiage-review.md) and [original capture note](../oshiage/capture-note.md): distinguish B3 Tobu/Hanzomon from B1 Keisei/Toei and surface Tobu. Those early captures used the older `[139.81335,35.71026]` display endpoint and are not evidence of the current cut.
- [Later Oshiage central-cut reference](../oshiage/central-cut-reference.json), checked against current `geometrySource.manualOverrides.oshiage-platform-display`: the current representative source-bound river-crossing cut is `[139.81345102105016,35.70970842655579]`. The retained source URLs are official Tobu/Metro and engineering-history references plus the georeferenced GSI river landmark. It is explicitly a representative central cut, not a modern surveyed physical-platform centre.

## Original pixels actually inspected

Viewed the **original `smooth.png` and `basemap.png`** in each directory below: eight unmodified images, no contact-sheet replacement, crop or redraw. Paths are absolute and reference existing native outputs.

| Own interval / view | Original files | Observation and limit |
| --- | --- | --- |
| Sobu-3 #1 / 9 | [smooth](</Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/005752/000009/smooth.png>), [basemap](</Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/005752/000009/basemap.png>) | Near Tamachi/Takanawa the red line takes a visible direction change east of the curving blue Keihin–Tohoku rail band, passing through the built-up Shibaura corridor. Current lead #1 vertex35 is 20.08° at `[139.7453511,35.6426383]`. This is the independent underground Yokosuka/Sobu approach; separation from that blue surface band does not establish a defect or authorize moving it. Underground centreline cannot be measured from this cartography. |
| Sobu-3 #2 / 5 | [smooth](</Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/005753/000005/smooth.png>), [basemap](</Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/005753/000005/basemap.png>) | Red broadly follows the labelled Yokosuka southwest–northeast curve across the separate north–south rail group south of Osaki. It does not turn into the north–south line in the image. Lead #2 vertex54 is 18.65° at `[139.73205,35.61655]`. Multi-track width, grade separation and separate branches prevent this view certifying track-level ownership or exact centre. No obvious local red break was seen in this single viewport. |
| Tobu #0 / 0 | [smooth](</Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/006083/000000/smooth.png>), [basemap](</Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/006083/000000/basemap.png>) | Hikifune red endpoint lies in the longitudinal Tobu station/rail band; red continues south without an obvious detached hook at this scale. Current adjacent source/display vertices1/2 yield 87.49°/87.54° local turns around the short crosswise support near `[139.81658,35.71726]` / `[139.81651,35.71726]`. This sharp numerical lead is not a visible-defect verdict; z17 roof/rail shading cannot resolve a narrow own-platform midpoint or the short support itself. |
| Tobu #0 / 3 | [smooth](</Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/006083/000003/smooth.png>), [basemap](</Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/006083/000003/basemap.png>) | Red leaves the northeast approach and ends in the separate north–south Oshiage underground station group at the river crossing. Surface Tobu curves west toward Skytree; the B1 Asakusa group crosses separately. No snapping to either is justified. Endpoint viewport is centred exactly on the current representative cut, but broad blue/purple shading and hidden B3 rails do not prove the physical platform's precise centre. |

Recorded camera centres (longitude, latitude), all z17/heading0/pitch0: Sobu #1/9 `[139.74547489197218,35.64269832389867]`; Sobu #2/5 `[139.73162047100823,35.61636343846496]`; Tobu #0/0 `[139.816637,35.718314]`; Tobu #0/3 `[139.81345102105016,35.70970842655579]`. Each inspected view records one rendered display part and one smooth part. Requested camera and legacy metadata are reported, not a new projection calibration.

## Exact line/station scope and next evidence

Sobu-3 is seven station records / six intervals: 東京 `003766` → 新橋 `003872` → 品川 `004095` → 西大井 `004235` → 武蔵小杉 `004301` → 新川崎 `004358` → 鶴見 `004496`. Current explicit display station overrides are 新橋 `[139.7587133,35.6662038]` and 品川 `[139.73965305042694,35.629035]`; physical station rows remain distinct. The Tokyo physical row already carries the underground `[139.765379,35.681726]` anchor. Registered own-line connection references include `tokyo-east-21`; separate `tokyo-tokaido-shimbashi` and `shimbashi-tokaido-shinagawa` source paths do not convert close/crossing display strokes into additional junctions.

Tobu Isesaki-2 is 曳舟 `003479` → 押上 `003526`, one interval. Current display endpoint is `[139.81345102105016,35.70970842655579]`; physical 押上 stays `[139.813731,35.70847]`. `stationLaneByCode['003526']=0` remains explicit. Registered junction `oshiage-tobu-hanzomon` uses the existing physical surveyed `[139.81374,35.70843]` vertex; the display central cut does not rewrite it.

Additional numerical leads, not yet visually inspected here: Sobu #3 vertices14/13, 17.18°/16.62° near `[139.70808,35.59208]` / `[139.70858,35.59237]`; Tobu #0 vertex13, 23.85° at `[139.81437,35.71184]`, and vertex10, 14.61° at `[139.81527,35.71248]`. A repair needs own passenger-corridor support and original pixels at the affected scale; neither turn magnitude nor nearest cartographic rail is sufficient.

Preparation complete, with **83 expected own-identity-compatible legacy views**, one separately retained stale extra, and eight original images actually inspected. No new repair proposed from this limited review. Remaining Sobu #0/#3/#4/#5 coverage and station extents require their existing original paired evidence to be reviewed before geographic conclusions. Current Main composition and precise underground/roof-obscured platform centres remain unmeasured here. Do not recapture all views or certify either entire line from these counts.

Own-only scratch detail: `/private/tmp/jtm-43-44-receipt-detail.json`; targeted read query: `/private/tmp/jtm-43-44-receipt-query.py`. These are preparation artifacts, not a new verification runner.
