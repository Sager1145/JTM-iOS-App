# IR Kanazawa passenger-through-pair binding follow-up — 2026-10-18

The northwest reference is now credibly bound to the **Higashi-Kanazawa passenger through pair**, rather than selected merely from an own-operator railway relation. This is an inference from explicit passenger-stop membership on the exact source way, the operator’s station diagram, and inspected original aerial views. It supports the narrow choice of an own display reference; it does not establish a surveyed pair midpoint, directional train trajectory, exact passenger face or station-centre adjustment. Parent controls acceptance/application after independently checking these sources. No application is performed here.

The earlier [13-pair standard-map report](candidate-1-26-native-pixel-review-20261018.md) and its acceptance hold are preserved unchanged as the historical decision before this additional evidence. Its observation—red northwest of the labelled IR glyph at point7—remains accurate. The new aerial evidence resolves why that difference alone did not identify a wrong yard track.

## Explicit passenger anchor on the exact source way

Retained primary [way834273931/full.json](https://api.openstreetmap.org/api/0.6/way/834273931/full.json), already stored in `kanazawa-own-source/identified-osm-live.json`, contains node **3977860982** at exact way-node index40 of52. It is not a node selected by proximity. The node is v3,2024-03-14T15:49:27Z, `[136.6697151,36.5935457]`, name東金沢, `public_transport=stop_position`, `railway=stop`, **`train=yes`**. The source way v5 has an uninterrupted ordered node sequence from this passenger stop southwest through the candidate body to node11164797904, which exactly joins way394894111v7. The stop is therefore on the very source way used through the disputed curve, not just somewhere in the same operator’s yard.

The exact primary response is retained separately as [way-834273931-full-retained-primary.json](passenger-binding-sources-20261018/way-834273931-full-retained-primary.json), with a compact [stop extraction](passenger-binding-sources-20261018/higashi-stop-3977860982-retained-primary.json). A fresh identified [stop-memberships API request](https://api.openstreetmap.org/api/0.6/node/3977860982/relations.json) returned zero parent relations, saved verbatim. No directional train-route membership is invented. Earlier railway relation4669038 membership/operator/track_ref2 remains supporting context, not the sole passenger proof.

## Official platform-side correspondence

The [current official IR Higashi-Kanazawa station page](https://www.ishikawa-railway.jp/station/higashi_kanazawa/) links its [own layout PNG](https://www.ishikawa-railway.jp/station/higashi_kanazawa/img/fmp_higashi_kanazawa.png). The original was downloaded as source evidence and actually viewed with all labels: **platform2 is on the west side of the island for Toyama/Nanao; platform1 is on the east side for Kanazawa**. In the north-up aerial, these correspond to the northwest/southeast sides of the northeast–southwest island. This is consistent with the selected source’s track_ref2 and explicit Higashi-Kanazawa passenger stop. It does not equate track_ref2 to every later Kanazawa platform number or claim that the opposite-direction interval must use that single directional track.

Local official source: [official-higashi-kanazawa-layout.png](passenger-binding-sources-20261018/official-higashi-kanazawa-layout.png). Attribution: IRいしかわ鉄道. The official guide `https://www.ishikawa-railway.jp/company/pdf/tebiki.pdf` is archived at `/private/tmp/jtm-ir-official-tebiki-20261018.pdf` only. Its page19 render omitted Japanese text because the renderer lacked Adobe-Japan1 mappings; that failed labelled rendering is not evidence. The direct official PNG supplies the inspected platform labels. No large PDF is added to the repository.

## Actual aerial inspection

All six available original imagery basemap/smooth pairs below were actually opened (12PNGs), with no crop, image editing, coordinate digitisation or automatic track-centre inference. The source directory is `/private/tmp/jtm-ir-own-track-imagery-20261018/alignment/captures/000000/`; exact full paths, timestamps and contracts are recorded in [passenger-binding-evidence.json](passenger-binding-sources-20261018/passenger-binding-evidence.json).

| Own point | Directory | Observation |
| --- | --- | --- |
| 0 | `000000` | Higashi-Kanazawa passenger island and its through pair visible; overlay in own conventional group; centre/face not established. |
| 1 | `000001` | Same through pair continues beside container terminal and road bridge; red distinct from terminal apron tracks and SE Shinkansen. |
| 3 | `000003` | Red follows through pair between container terminal NW and maintenance/storage tracks SE; transverse road bridge briefly occludes rails. |
| 7 | `000007` | Real NW outer through pair beside treatment-plant fence; yard fans lie SE, cartographic blue middle-yard curve is not physical rail proof. |
| 10 | `000010` | Conventional passenger fan toward Kanazawa distinct from SE elevated/roofed Shinkansen; specific face under roofs unproven. |
| 12 | `000012` | Broad Kanazawa conventional group visible; roof/parallax occludes exact physical passenger face, caps and centre. |

Point0 shows the own passenger island. Points1/3 show the selected through pair beside the container terminal and separate storage/maintenance fan; the road bridge occludes short sections, so no hidden rail survey is claimed. Point7 shows the red reference following the real northwest outer through pair by the treatment-plant fence, outside the branching storage fan to the southeast. The standard-map blue label curve through the yard middle cannot replace that physical evidence. Point10 traces the conventional approach into Kanazawa, separate from the southeastern Shinkansen structure. Point12 has substantial roof/parallax occlusion, so exact face, cap and longitudinal centre remain unresolved.

Together, the same-way passenger stop, official west-side passenger-platform correspondence and these physical-corridor views provide a credible own passenger-through-pair binding. The source still has KSJ2 ancestry and no independent engineering survey has been established. The active southern118m return to generalized N02 remains an explicit schematic display transition; these new sources do not turn it into a surveyed physical seam. Preserve physical station coordinates, endpoints, the south fan, source IDs/km and all unrelated controls.

No app/native/capture, build, test, production or repair-source edits were performed. Only this research report, compact primary-source extracts, official PNG and viewed-source manifest were written. The previous withheld report was not overwritten.
