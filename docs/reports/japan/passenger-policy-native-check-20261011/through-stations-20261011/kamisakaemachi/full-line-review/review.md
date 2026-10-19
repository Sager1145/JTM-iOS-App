# Keishin whole-line native-capture review — 2026-10-12

Scope: `jp-京阪電気鉄道-京津線`, all6 intervals from御陵 toびわ湖浜大津. **30/30 planned viewpoints visually inspected in all3 images** (basemap, display, smooth), including every intermediate ordinal and each interval's initial and final viewport. Current report has30 captured,0 pending,0 failed for this line; those counts describe capture coverage, not geographic acceptance. Source line unchanged per root.

Receipt root: `/private/tmp/jtm-remaining-lines-manual-evidence`, directories001470–001475. Root produced6 fresh native captures for interval4 and reused24 receipts after exact dependency matching/native validation. Each read receipt's itemID/pointOrdinal matched the sorted plan. Contacts were created locally at half image size; important candidates/endpoints were also opened as separate original1024×768 basemap/display/smooth triples. This reviewer did not operate UI, change source/code, build or test.

The blue/purple labelled rail is Apple basemap content, green/cyan is display, and red is smooth. Surface map alignment cannot establish hidden tunnel/underground track position. Through operation with Kyoto Metro does not make the company line identical to Metro; adjacentJR and Ishiyama-Sakamoto tracks remain separate geographic/physical identities. Preserve the current company identity, Metro independence and terminal fork.

## Exact coverage

[coverage.json](coverage.json) contains every viewpoint coordinate, root and ordinal. Contacts use `contacts/keishin-NN-basemap.jpg`, `-display.jpg`, and `-smooth.jpg`.

| Interval | Stations | Receipt directory | All3 image ordinals visually read | Observation |
|---|---|---|---|---|
| 0 | 御陵→京阪山科 | `001470` | 0–5 (6/6) | Misasagi underground lead and emergence toward Keihan-Yamashina. Display/smooth remain on the labelled Keishin depiction and separate from JR Biwako tracks. Underground position cannot be accepted from surface streets. |
| 1 | 京阪山科→四宮 | `001471` | 0–2 (3/3) | Keihan-Yamashina→Shinomiya station approaches, central curve and final tail follow labelled Keishin corridor, south of distinct JR railway. Yard allocation/platform centres unproved. |
| 2 | 四宮→追分 | `001472` | 0–4 (5/5) | Shinomiya→Oiwake crosses the developed corridor and parallels the road; the green depiction remains associated with labelled Keishin rail. Local road/rail pixel overlap is not a basis for merging tracks. |
| 3 | 追分→大谷 | `001473` | 0–5 (6/6) | Oiwake→Otani mountain/road corridor and final approach examined. Parallel Meishin expressway is distinct. Otani curve green/red lie north of the labelled blue railway in the shared final viewport; retained bounded candidate. |
| 4 | 大谷→上栄町 | `001474` | 0–5 (6/6) | Fresh native Otani→Kamisakaemachi captures. Otani curve retains the north-side separation; straight mountain crossing follows labelled Keishin tunnel depiction, distinct from the diagonal highway tunnels. Descending surface approach into Kamisakaemachi remains continuous. |
| 5 | 上栄町→びわ湖浜大津 | `001475` | 0–3 (4/4) | Kamisakaemachi→Biwako-Hamaotsu street-running straight, tight terminal turn and endpoint examined. Green/red remain along558 street-running corridor, then approach terminal beside separate Ishiyama-Sakamoto rail. Terminal fork must remain. |

## Kamisakaemachi and retained candidates

**上栄町 station005987**, physical `[135.86019,35.00518]`: both #4/5 and #5/0 inspected. Original #4/5 basemap/display/smooth was opened at native resolution. The descending Keishin stroke comes north from theOsaka1 road/JR crossing, bends northeast byMiyukicho, and joins558 toward the street-running section. The station stays on a continuous depiction; no detached station stroke, local backtracking or new fork was visible. The map's platform band does not certify a platform centre, so no station move is supported by this evidence alone.

**Otani approach curve** is the strongest bounded follow-up candidate: #3/4–5 and #4/0–1, representative viewport centres `[135.853165,34.994310]` and `[135.856708,34.994883]`. Original #4/1 triple was opened at native resolution. Our green/red curve is visibly north of the blue labelled Keishin curve around theOtani road bend; then the depicted rail leaves the road northeast along the labelled mountain/tunnel leg. The north-side difference is present in display as well as smooth, so it is not merely a red-only smoothing anomaly. It needs positively identified passenger track/grade/portal evidence; the broad road and railway depiction overlap locally, and no exact replacement coordinates are certified here. Do not shift the hidden leg to a nearby road or highway tunnel.

**Biwako-Hamaotsu terminal**, #5/2–3: original #5/2 triple inspected at native resolution. Keishin comes up558 and turns into the terminal platform/fork area beside the separately labelled Ishiyama-Sakamoto line. The local curve is intentional terminal geometry; shared proximity or platform depiction is not evidence to erase the fork, promote a physical connection, or select operational track allocation.

**Misasagi underground lead**, #0/0–2: labelled map depiction and surface streets show context but provide insufficient underground truth. Keep this explicitly unresolved for geographic certification. The mountain interior similarly does not establish precise tunnel position from uniform green canopy.

All30 viewpoints are reviewed; there is no missing-capture gap. Retained uncertainty concerns Otani physical geography and hidden track accuracy. No whole-line geographic pass, pixel-error measurement, surveyed platform centre or operating traversal permission is claimed.
