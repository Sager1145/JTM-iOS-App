# Tokyo physical route repair — 2026-09-30

Implementation and data are ready for the consolidated app validation. No Xcode build or Simulator run was started by this task in the resumed validation phase. Playback/video-export files were not edited by this task.

## Behavior

- The main JR Tokyo station code `003766` has four displayed platform families: Sobu/Yokosuka, other conventional JR, northern Shinkansen, and Tokaido Shinkansen. Alias members remain available for routing and station details. Remote Keiyo/Metro platforms remain separately represented.
- Both Tokyo tunnel aliases pin their final 300 m to the elected circle. Groomed Web vertices are embedded in the native display derivative when the raw interval chain differs. At Shinagawa the Tokaido Shinkansen interval drops exactly two reversed seam vertices and retains its survey endpoints and remaining vertices.
- New native rides select train type, endpoints, then a physical line serving both endpoints. Each mandatory intermediate visit and its adjacent physical interval is filled. Generated visits have no invented times. The selected corridor survives actual workspace export/import and reaches AI input as read-only line IDs/section codes.
- Tokyo–Shinagawa ordinary choices include the surface Tokaido alignment (Tokyo, Yurakucho, Shimbashi, Hamamatsucho, Tamachi, Takanawa Gateway, Shinagawa) and the Sobu tunnel (Tokyo, Shimbashi, Shinagawa). Deleting Yurakucho replaces the generated surface visits with the tunnel route. Deleting Shimbashi then yields no viable route; progression is disabled until undo/endpoints change. Endpoint times and stable editor row IDs are preserved; undo restores the route snapshot.
- Each package interval has a reversible identity `lineID@sortedStationCodes`, with occurrence suffixes for repeated endpoint pairs and loop closing intervals included. Ordered `section_codes` carry travel order. There are 9,576 unique JP codes. Both timetable databases contain that registry and physical sections for all 84 NEX trips; all 882 trips, 8,520 stop-time rows, 88 relations, 53 number segments, 24 operator segments and 275 line segments remain present.
- Both clients resolve explicitly coded geometry directly from the physical package. Unknown/disconnected codes cannot fall back to a nearby N02 railway. Source WGS84 survey geometry stays separate from display grooming; gaps between physical platforms remain multipart geometry.
- The NEX sample, part-171, combined sample and manifest agree with the current train store. Full timetable rebuild skips only byte-identical numbered file-provider copies when reading facts; files remain intact and every input remains included in the source fingerprint.

## Completed verification

- 140 affected Swift tests in 11 suites pass (route choices, interval identity, AI hints, timetable runtime/app draft, sample cache provenance, archive/import/export, station display/visibility and package geometry).
- All 106 Web tests pass; 12 focused route/display tests also pass after the final advisory update.
- 69 Python display-network tests, 4 physical-code tests, 2 copy-input tests and the circle-owner test pass.
- The final native display derivative builds successfully; its main JR Tokyo circles are exactly four, all six JR line memberships remain present (alongside Metro), and the six affected native/Web base paths match at seven decimal places.
- JavaScript local asset/source and undefined-global checks pass; edited files have no diff whitespace errors.
- Timetable snapshot verification is aligned; runtime and derived database bytes match, integrity/FKs pass, and their package/history/source hashes match the final inputs.
- Package preflight reports zero errors, with the existing 20 warnings and six out-of-scope informational findings. The bounded Tokyo override check passes. Display-parts, visibility, station-visibility, validation and store-operation fixtures were refreshed for the affected data.

An initial full Swift run exposed stale archive/fixture/cache assertions after these fields and sample changes. Those failures were corrected and the affected suites above rerun successfully. That expensive full run was stopped while unrelated historical/pattern solver cases were still running; this report does not claim a complete full-suite pass.

## Consolidated app checks still required

Use the consolidated build snapshot after station-name/rail.db synchronization; shared editor/data writes and the build/Simulator slot are now released by this task. No Swift/Xcode build or Simulator process from this task remains active.

1. Build `RailMap` once with the standard `ios/verify.sh --app` gate.
2. Run `OrdinaryPhysicalRouteUITests/testSurfaceStationDeletionSwitchesToTunnelThenReportsNoAlternative`: new journey → type before endpoints → Tokyo/003766 and Shinagawa/004095 → surface line → delete Yurakucho → tunnel → delete Shimbashi → no route → undo.
3. Verify Tokyo (`35.68,139.75,0.12`) shows exactly four main JR circles with straight terminal approaches and all six line memberships in details. Verify Shinagawa Tokaido Shinkansen enters/exits without the old backward fold.
4. Load the July 27 NEX sample and a saved ordinary tunnel choice; check Shimbashi lies on the tunnel stroke, save/reopen retains it, and AI prompt includes the chosen type/line/interval data. Check both directions and a Yamate-to-Sobu multipart platform transition.

Relevant cases: `RailwayRouteChoicesTests`, `RailIntervalCodeTests`, `JourneyCompletionTests/ordinaryRouteChoiceInformsCompletion`, `SamplePrecomputeProvenanceTests`, `TimetableAppFlowTests`; focused Web checks are in `app/tests/tokyo-platform-approaches.test.mjs` and `display-lanes-parts.test.mjs`.
