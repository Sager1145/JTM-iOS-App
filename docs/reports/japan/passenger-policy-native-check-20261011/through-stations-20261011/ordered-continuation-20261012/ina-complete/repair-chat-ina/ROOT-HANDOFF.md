# Ina platform midpoint candidates - Root handoff

Seven western own-platform frame midpoint candidates are supported by existing screenshots; six stations remain unresolved. Coordinates are WGS84 [longitude, latitude]. No production apply or actual native-after acceptance.

## Seven supported candidates

Select only the identifiable western real platform frame: midpoint of its longitudinal caps, then normal landing onto the established own Ina guideway. Exclude the eastern face and Shinkansen. Marked original-resolution images show yellow caps, cyan midpoint/normal, and red landing.

| Index | Station / ID | Own cap pixels | Own rail landing | Candidate coordinate |
| --- | --- | --- | --- | --- |
| 1 | 鉄道博物館 / 002881 | [418, 263] to [454, 408] | [452, 332] | [139.61757019014368, 35.920243278551226] |
| 2 | 加茂宮 / 002857 | [450, 267] to [431, 400] | [465, 337] | [139.61674992757816, 35.93572656561451] |
| 3 | 東宮原 / 002844 | [468, 247] to [448, 393] | [475, 322] | [139.61809357175832, 35.94270671528384] |
| 4 | 今羽 / 002835 | [460, 266] to [439, 400] | [467, 336] | [139.61943565641405, 35.9499659160949] |
| 5 | 吉野原 / 002824 | [475, 210] to [454, 342] | [479, 279] | [139.6207950294305, 35.95721842868368] |
| 6 | 原市 / 002812 | [489, 254] to [467, 394] | [496, 328] | [139.62216622453707, 35.9638356581054] |
| 7 | 沼南 / 002802 | [500, 215] to [479, 364] | [508, 293] | [139.6235655975533, 35.971172610840206] |

Cap picking uncertainty is approximately 3 pixels longitudinal, 4 at stations1-2; landing uncertainty 2 pixels transverse. Local scale is approximately0.482m/pixel. These are cartographic proposals, not survey results. Independent station1-7 review and parent inspection of all seven marked images agree. Unproven eastern-face allocation does not block this bounded western-frame selection.

## Six unresolved stations

| Index | Station | Evidence gap |
| --- | --- | --- |
| 0 | 大宮 / 002914 | The own loop is visible, but the passenger platform/frame is obscured by the terminal roof/deck. A loop stub endpoint cannot establish the terminal platform midpoint. |
| 8 | 丸山 / 002787 | The southern pale frame cap is visible near y255; the northern cap is covered by the Ina label/nearby station label. The current y327 guideway anchor is physical-chainage projection and cannot establish the platform midpoint. |
| 9 | 志久 / 002770 | The pale western strip bears directional road arrows and continues outside the station footprint. Complete own passenger platform caps cannot be distinguished in these screenshots. |
| 10 | 伊奈中央 / 002756 | The long pale western strip has directional road arrows and continues outside the station footprint; it is not an established passenger platform. The provisional own-guideway anchor does not establish a platform midpoint. |
| 11 | 羽貫 / 002747 | The long pale western strip follows the arrow-bearing road beyond the station footprint. No complete distinct own passenger platform caps can be established. |
| 12 | 内宿 / 002742 | Separate pale fragments and a terminal guideway stub are visible, but the complete own terminal passenger frame and its two longitudinal caps are not established. Do not substitute the stub end or merge pale fragments. |

For stations0,8-12, platform candidates stay null. Wider or label-free saved own-station views must identify the full caps. If existing captures cannot resolve them, retain the gap and obtain explicit platform evidence. Do not substitute old physical-chainage projections or terminal stub ends.

## Files and integration

- root-candidate.json:13 station IDs, seven candidate coordinates and six nulls; complete diagnostic body manifest.
- platform-midpoint-candidates.json: exact raw image/camera, caps, midpoint, rail landing, uncertainty, marked evidence and gaps.
- station-review-index.json: synchronized decisions; physical coordinates and diagnostic anchors retained for comparison.
- diagnostic-interval-manifest.json:12 intervals,90 combined points,11 exact seams. Seven supported anchors equal existing interval endpoints; no body arrays changed this adjudication. Six unresolved diagnostic anchors must not be treated as platform midpoints.
- review-receipt.json: all seven coordinates match inverse projection from actual station cameras. Maximum longitudinal landing residual1.158px is within declared picking uncertainty.

Root resolves remaining frame caps, updates adjacent display endpoints and interval partitions, then freezes/integrates and reviews actual independent Inspector/Main after-captures. Prior56 primary projection pairs and13 station pairs are diagnostic review, not native-after acceptance. Physical ID/km/routing and production source are unchanged. Changes remain in this repair-report directory.

## Supplemental capture request for Root

Save each actual raw basemap with its own view.json camera, selected line/station identity, viewport dimensions and scale. Aim for z18 or z19, heading0/pitch0; pan or vary zoom to move labels if a label-free mode is unavailable. Preserve one wider context view showing the Ina-labelled approach and competing Shinkansen/roads. More zoom alone cannot resolve roof-obscured physical ownership.

| Station | Required supplemental screenshots | Complete adjacent interval scope after anchor change |
| --- | --- | --- |
| Omiya /002914 | A close view of the own New Shuttle terminal passenger frame with both longitudinal caps and the loop entrance; a wider view separating it from JR/Tobu/Shinkansen. If the roof still hides the frame, an identified own-platform plan or overhead reference is required before placing its midpoint. | interval0 |
| Maruyama /002787 | Two slightly panned/zoomed close basemap views moving the Ina/station label off the north cap, with overlap to the visible south cap around old y255; one full-platform context view. | intervals7,8 |
| Shiku /002770 | Close own-platform view distinguishing both passenger caps from the arrow-bearing western road; wider labelled Ina approach/road separation. If cartography omits the frame, a georeferenced own-platform reference is required. | intervals8,9 |
| Ina-Chuo /002756 | Close full own passenger frame with both caps and rail contact, plus wider Ina/road separation. Do not use the continuous arrow-bearing pale road strip. | intervals9,10 |
| Hanuki /002747 | Close full own platform frame with both caps, plus wider approach showing Ina versus arrow-bearing road and Shinkansen. | intervals10,11 |
| Uchijuku /002742 | A close full terminal passenger frame including northwest pale shapes, southeast fragment, own guideway stub and both actual platform caps; wider view showing where Ina terminates while Shinkansen continues. If fragments remain unidentified, obtain an own-terminal platform plan/overhead reference. | interval11 |

Root continues final adjudication, synchronizes aliases/adjacent endpoint partitions, and performs actual after-capture pixel review in all three independent Inspectors across all12 complete intervals. Reuse valid unchanged baseline evidence; changed anchors require the full adjacent scopes listed above. Main must inspect all13 station dots on their selected own platform/rail representatives, both termini, Omiya loop, joins, and production lane-offset continuity. Save raw basemap and product overlay pairs with actual cameras. Capture success counts alone are not acceptance; record unresolved pixels explicitly. Coordinate one heavy job and preserve existing UI/build ownership.
