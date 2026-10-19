# IR Ishikawa intervals 3, 7 and 8: complete retained-original review (2026-10-18)

Exact owner: `jp-IRいしかわ鉄道-IRいしかわ鉄道線`. Reviewed every original **basemap.png + smooth.png** in these three intervals: **25 view pairs / 50 images**. The exact absolute paths, cameras, retained receipt dependencies and original file byte counts are in `intervals-3-7-8-original-review-manifest-20261018.json`. Files were opened directly with view_image, without crops, composites or redraws. Each view's actual capture-state owner/ordinal matched the retained evidence index; captured status and both original byte counts matched receipts. Existing recorded SHA values are copied, not recomputed.

| Interval | Exact directory slot and every reviewed ordinal | Review completeness |
|---|---|---|
| #3 東金沢 → 金沢 | `captures/000011/000000` through `000008`, inclusive | 9/9 pairs |
| #7 松任 → 西松任 | `captures/000015/000000` through `000006`, inclusive | 7/7 pairs |
| #8 西松任 → 加賀笠間 | `captures/000016/000000` through `000008`, inclusive | 9/9 pairs |

The directory root is `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/`. Slots are the exact sorted immutable-owner map from existing-evidence.json, not risk-array indices. Historical contract is z17 / 1024×768 / 1× / flat light / zero-lane inspector. Preparation's retained source/display/station identity matches are reused as historical input context; this review does not assert present Main renderer dependency equivalence. Parent's current Kanazawa candidate is v5…v26, as confirmed in repair-ir-kanazawa-display.mjs and its current evidence. The separately frozen kanazawa-candidate-fragment-5-22.json is an earlier version; its identical old baseline controls were used only to localize the northern lead. No candidate has been applied or captured here.

## Findings

**#3: the known v13 angular departure is confirmed, and the northern sparse chord remains a separate review lead outside the candidate window.**

- Views 000000–000003 cover the Higashi-Kanazawa departure and Otsu yard. The red path stays in the conventional side of the overall railway corridor, distinctly northwest of the separately labelled/ticked Hokuriku Shinkansen. However, in views **000001 and 000002**, the long red northwest chord visibly diverges from the more curved blue line labelled **IR Ishikawa Railway Line** through the yard. View000003 shows the chord converging again toward the conventional curve. This is a concrete cartographic discrepancy, not established wrong-track physical geometry: the broad yard fill and single blue representative curve do not identify which individual own passenger main track the red path should use.
- Exact retained decoded controls implicated by that northern discrepancy: **v2 `[136.66863,36.59284]`, v3 `[136.6657,36.59079]`, v4 `[136.66344,36.58926]`, and approach to v5 `[136.65912,36.58681]`**. The first long leg v2→v3 and following v3→v4 are outside the staged v5…v26 repair. No sharp isolated right angle is newly found there; the issue is the long straight representation across the blue curve. In original000002, metadata projection places v3 at approximately **(712.5,214.9)** and v4 at **(501.9,392.5)**; the red chord is visibly northwest of the blue IR curve. These screen positions were calculated only from that saved camera and exact controls to localize the lead, not to infer physical clearance.
- Views000003–000006 show the known southeast-facing V near Asanohommachi: v13 `[136.65639,36.58458]`, retained turn37.5117°, incoming21.326m/outgoing39.462m. It is most legible in **000004/smooth.png**, around x420/y490, against the gentler own conventional curve. This is the already implemented candidate's subject; no claim about candidate success follows from old originals. Current candidate authority restricts replacement to v5…v26, with its separate southern schematic transition limitation retained.
- Views000006–000008 show continuous approach into Kanazawa's conventional station side, with no additional gross detached hook, reversal or visible red gap found. The eastern Shinkansen remains independent. Broad station shading does not establish cap-to-cap centre, own platform midpoint, final station circle, or own production lanes.

**#7: all seven pairs show a continuous conventional corridor; no additional gross false corner found.**

- 000000–000001: Matto station and southwest departure. Multiple conventional yard/station tracks are shown; red continues along their corridor. The retained v1/v2 angle leads24.7540°/24.8071° share an approximately **0.89455m** leg (v1 incoming140.371m; v2 outgoing34.492m). At this view scale that tiny source leg is not evidence of a physical or visible large corner.
- 000002–000004: the gradual southwest sweep and Chiyoni-dori crossing remain continuous; no local hook, reversal or gap visible.
- 000005–000006: Nishi-Matto approach remains continuous and separate from the southeast ticked railway. Own narrow passenger caps and station centre cannot be read from broad shading.

**#8: all nine pairs remain continuous; no additional gross false corner found.**

- 000000–000001: Nishi-Matto southwest departure shows a small local inflection, without a gross detached hook. Retained v2 `[136.5487,36.51755]`/v3 `[136.54869,36.51753]` turns28.1453°/30.2365° share a **2.39943m** leg (v2 incoming5.57970m; v3 outgoing45.3338m). These are bounded short-span leads, not automatic defects.
- 000002–000005: the Miyabo yard-side straight remains continuous along the northwest conventional corridor. Red does not jump onto the southeast ticked railway.
- 000006–000008: approach to Kaga-Kasama remains continuous through the station corridor; no gross false angle, reversal or gap found. Station fill remains insufficient to establish an own passenger-frame centre.

## Scope and disposition

The known #3 V remains the concrete existing candidate. The newly documented northern Otsu chord warrants **bounded attributable own conventional passenger-track investigation** before any extension: do not fit it to a nearest blue rail, infer a representative midpoint from the yard fill, or blend toward the Shinkansen. No additional repair is proposed from these pixels. #7/#8 tiny source turns remain pending without demonstrated meaningful deviation.

This completes original-pixel review only for these three intervals. It does not certify individual track ownership inside the broad yard/station fill, physical junctions, own station centres, Main station circles/lanes, or the unapplied candidate. No code/data/native/capture/build/test changes or external acquisition were made; only this report and its viewed manifest were written.

## Requested bounded source follow-up: raw decoded controls 0…5

Used only the already retained, explicitly identified own **way834273931 v5** full response (52 versioned nodes, north-to-south order), with the repository's `jp-manual-corrections/geo.mjs:projectPointOntoPolyline`. No objects were acquired and no replacement fragment was edited. Full values and exact source-segment node IDs are in `north-controls-0-5-own-projections-20261018.json`.

| Decoded control | Distance to identified own track2 | North-to-south source segment index | Projected own coordinate |
|---|---:|---:|---|
| v0 `[136.66948,36.59345]` | 6.49195m | 11 | `[136.66952949888562,36.59340723087063]` |
| v1 `[136.66887,36.59301]` | 9.95405m | 13 | `[136.66895093184243,36.59294842648297]` |
| v2 `[136.66863,36.59284]` | 14.04644m | 14 | `[136.6687515130676,36.592759756223764]` |
| v3 `[136.6657,36.59079]` | **42.57183m** | 20 | `[136.66601427680988,36.59050206668785]` |
| v4 `[136.66344,36.58926]` | **19.04734m** | 25 | `[136.66354936851315,36.589112925132675]` |
| v5 `[136.65912,36.58681]` | 3.66734m | 34 | `[136.65909660136217,36.58683710652589]` |

The existing identified own chain **does cover the northern discrepancy**: all six closest witnesses are interior chain segments, ordered 11→13→14→20→25→34. Its retained main / 1067 / track_ref 2 / own-operator identity provides a concrete basis for a subsequent bounded corridor assessment, unlike simply copying Apple's label line. This establishes source availability and the raw-control discrepancy, not a replacement boundary choice or surveyed representative centre. v0 is the own station coordinate and is not proposed for movement. Current guard4 and v5 boundary remain untouched. The staged v5…v26 candidate is unchanged.

The labelled blue conventional cartographic curve through Otsu is a **lead**, not an individually attributed physical track glyph throughout the yard. The separately ticked Shinkansen stays excluded. Do not turn the 42.57 m source distance into a claimed Apple pixel residual or whole-line verdict.
