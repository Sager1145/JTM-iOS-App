# 29. 大糸線（JR East）— complete baseline analysis

All32 intervals,33 stations in owning-line north-to-south order 南小谷→松本 were reviewed in all three actual native inspector applications. Each captured247 viewpoints with zero failures and native AX-confirmed idle completion. Root opened every contact sheet00..61 in each app:741 composite viewpoints total. Collection counts do not establish alignment.

Original RailMap.app was subsequently opened at all32 complete interval cameras; all32 valid ON/OFF pairs64 frames were actually viewed. Receipts confirm network rendered with budgetDrops0, network OFF, equal centre/distance/viewport, actual basemap pixels and both interval endpoints visible. Initial ON frames18 and20 had blank-grid basemaps and are retained in their rejected directories; same-camera replacements were reviewed. A live camera mismatch24 blocked capture and the planned camera was restored by restarting before its accepted pair. Some initial scale labels were stale; no metre measurements use them. Main is the actual original app, using its current dark basemap, not a replacement coordinate drawing.

## Candidates and constraints

- Minami-Otari/Chikuni remain on the east Himekawa corridor. Local river bends vary. The operator boundary at Minami-Otari is not a physical track terminus.
- Hakuba-Oike→Shinano-Moriue river-side/Shiojima bends show changing east/south differences. Moriue→Hakuba crossing remains continuous; Hakuba's broad platform band needs an own passenger-frame check.
- Hakuba→Iimori→Kamishiro→Minami-Kamishiro retains straight/gentle bends, with local offsets and unresolved own platform caps.
- Interval7 is a priority cartographic candidate: preserve Sanosaka mountain S curves; north Lake Aoki turn and the long east-shore straight sit visibly east of Apple rail glyph in all three apps. Offset changes along the curve, so no whole-line translation is justified.
- Yanaba→Uminokuchi→Inao retains lake-side continuity; Kizaki south curve and Nogu river approach retain varying local differences.
- Shinano-Kizaki→Kita-Omachi long straight is east/northeast of glyph. Kita-Omachi→Shinano-Omachi curve differs locally. The broad Shinano-Omachi station/yard fan is not an own passenger-platform axis.
- Southern plain corridor through Minami-Omachi, Takase River, Tokiwa, Kutsukake, Matsukawa, Hosono, Oiwake, Ariake, Hotaka, Hakuyacho, Toyoshina, Minami-Toyoshina, Nakagaya and Hitoichiba is continuous. Local offsets vary and Ariake yard fan remains independent.
- Azusabashi approach, Azusa rail bridge and Shimatakamatsu station/curve sit south of Apple glyph locally; Shimauchi curve repeats a south difference. Retain the actual Narai River crossing/curve and independent Miyabuchi fork.
- Existing Matsumoto display interval31/station002506 correction is retained. The former acute short tail is absent in the current three-app views and original Main final pair. Existing accepted display cartography must not be replaced by the former physical junction endpoint.

All33 own longitudinal full-platform midpoint checks remain open in this whole-line review. This does not revoke or expand the earlier Matsumoto-specific accepted cartography. No new production geometry, station alias, topology, kilometre or bundled resource edit was applied. Detailed per-interval observations and evidence links are in interval-review.json.

## Dependencies and evidence limits

Focused owning-row equality was rechecked after review: frozen source equals current app/public/rail/jp-2025.json, all three inspector bundles and original Main bundle. Existing override is only interval31 and station002506. Read displayLineForCoordinates / decodeIntervals against Swift CompactPackage display decode and station endpoint welding; Main camera plan applies current effective display coordinates before computing bounds. Read existing matsumoto-oito-display-evidence.json and historical Matsumoto native candidate RESULT.md; retain that earlier repair and physical-junction/topology separation.

This work supports visual baseline findings at the viewed scales. No surveyed metre accuracy, runtime performance, pixel-perfect whole-line pass or full-platform acceptance is claimed. No build, national runner, full verification matrix or synthetic evaluator was run. Next ordered baseline owner is30 jp-東日本旅客鉄道-東北線-2; Oito repair candidates and platform checks remain open.
