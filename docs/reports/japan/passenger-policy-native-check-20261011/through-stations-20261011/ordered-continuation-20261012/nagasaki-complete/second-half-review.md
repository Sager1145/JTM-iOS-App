# Nagasaki main line: second-half original pixel review

2026-10-18. Exact line jp-長崎電気軌道-本線, intervals12..23 excluding21. Reviewed all27 indexed original basemap+smooth pairs (54 images) with functions.view_image. No false-corner repair candidate was identified in these views. This is scoped visual evidence, not whole-line acceptance or surveyed track-centre proof.

Source index: /private/tmp/jtm-nagasaki-missing-20261018/capture-index.json. Settings: light standard basemap, zoom17,1600×1200,350m spacing. All27 selected entries have captured status and both original files present. No pixels were altered, cropped, composited or redrawn. The exact54 absolute image paths, item IDs, ordinals, coordinates and findings are recorded in second-half-viewed-originals.json.

## Findings by interval

| Interval | Own endpoints | Pairs | Finding |
|---|---|---:|---|
|12|茂里町→スタジアムシティノース|2|Gentle road/median curve through the Zenza-machi vicinity; no isolated hook or false V.|
|13|スタジアムシティノース→スタジアムシティサウス|3|Broad compound turn via Takaracho follows the visible street corridor. Preserve its direction changes.|
|14|スタジアムシティサウス→八千代町|3|Longitudinal street run; overlapping views show the Nishizaka approach. No concrete false corner.|
|15|八千代町→長崎駅前|2|Real bends into the station forecourt road; the own southbound continuation remains distinct from the eastbound arm.|
|16|長崎駅前→五島町|3|Straight/gentle southbound median through the Asahi bridge intersection. No false apex or reversal.|
|17|五島町→大波止|3|Broad southbound road curvature; a straight harbour-side shortcut would erase real alignment.|
|18|大波止→出島|2|Real bend into Dejima-dori, supported by the basemap corridor.|
|19|出島→新地中華街|3|Southeast street run then substantial northeast turn at Tsukimachi-dori. This conspicuous turn is real and should remain.|
|20|新地中華街→西浜町|2|Diagonal bridge/junction approach follows the visible tram/road corridor. The turn where it meets the eastbound arm is not an isolated false spike.|
|22|観光通→思案橋|2|Eastbound curve follows the street; no detached false point apparent.|
|23|思案橋→崇福寺|2|Real southeast bend at Aburayamachi and terminal approach. The red endpoint remains within the corridor without a visible terminal hook.|

## Coverage and limits

Capture slots are lexicographic, not interval numbers:12→000004,13→000005,14→000006,15→000007,16→000008,17→000009,18→000010,19→000011,20→000013,22→000014,23→000015. Every indexed point in those slots was viewed as both original basemap.png and smooth.png. Individual scenes also contain other intervals; observations above are restricted to the assigned own intervals. Interval21 was explicitly excluded and remains supported by the separate legacy review.

There are no missing pairs inside this assignment. Dense labels, generalized blue corridor shading and street render geometry limit exact individual-rail/platform positioning, especially at Nagasaki-ekimae and Nishihamachi junctions. These standard-map images establish visual corridor consistency and the absence of an obvious false corner at this scale; they do not measure pixel residuals, certify a surveyed centre, inspect every possible zoom/style, or prove the native app's final packaged runtime. This pass did not independently recompute capture-to-current-source identity bits.

No code or production edit, tests, build, app/native launch, recapture or heavy job. IR Ishikawa research was left unchanged.
