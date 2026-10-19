# Miyazu #15 Kabutoyama south bow: own passenger source

2026-10-18. Read-only source research after actual reinspection of both original modes at #15 points1/2/3 from `/private/tmp/jtm-miyazu-missing-20261018/capture-index.json`. Original pixel disagreement and all8 pair observations remain in `missing-native-review-20261018.md`. No new capture/native/build/apply. The source supports a candidate own passenger display curve; runtime pixels remain required.

## Identity and original source

Own interval15 is かぶと山004208 [134.919925,35.60679]→久美浜004231 [134.895112,35.602299]. Physical compact row stores2.326km; decoded51 controls. `app/data/rail-sections.json` feature19836 has49 controls, N02_00112/N02_0025/N02_003宮津線/N02_004WILLER　TRAINS. **All49 feature controls reversed equal decoded1..49 exactly**. The south bow is original N02 source geometry, not an introduced display alias. Both stations, mileage, physical topology and all other intervals are retained.

Existing cache `railway-sources/local/osm/degree-cells/E134N35.json`, fetched2026-08-18T10:30:06.574Z from maps.mail.ru Overpass. Five exactly identified own ways have cache geometry identical to the freshly retained exact-object API node geometry:

| Own east→west way | Version/date | Nodes | End-to-next shared node |
|---|---|---|---|
|32052885|v9,2023-02-20T14:15:21Z|4|359808114|
|1044465764|v2,same date|11|359808273|
|32052892|v11,same date|12|359808159|
|1044465765|v1,2022-03-27T12:44:30Z|3|359808163|
|491716768|v6,2023-02-18T14:29:16Z|5|ends359808169|

All are railway=rail,usage=main,operator京都丹後鉄道,name京都丹後鉄道宮豊線,KSJ2:LIN宮津線,gauge1067,sourceKSJ2, with no service tag;491716768 is tunnel=yes. Direct [way1044465764/full](https://api.openstreetmap.org/api/0.6/way/1044465764/full.json) and [way32052892/full](https://api.openstreetmap.org/api/0.6/way/32052892/full.json), and the other three exact-way responses, are retained under `interval-15-source/way-ID-full.json`, including node versions/coordinates. This chain is selected by positive passenger identity and exact connected node IDs, not by nearest blue glyph, adjacent road178, other rail, or averaging.

Already retained `interval-9-source/identified-osm-live.json` contains complete relation objects from the exact [way32052922/relations API](https://api.openstreetmap.org/api/0.6/way/32052922/relations.json); reuse avoids another download. Train6015174 v45 (2025-05-02),宮津→豊岡, owns these five consecutive ways at zero-based134..138; complete train19072502 v3 (2026-08-25),西舞鶴→豊岡, at204..208. Reverse trains12030454 v13 at76..80 and19072511 v3 at81..85 contain the exact reverse sequence. Full tags/member slices are frozen with the candidate, explicitly distinguishing passenger continuity from mere railway relation/operator membership. The existing operator passenger timetable evidence in the #9 report independently names this corridor, but does not provide surveyed track coordinates.

## Frozen local window and limits

`interval-15-source/window-calculation.json` freezes old compact/full coordinates, N02 feature, source ways/node IDs, projections, alternatives and candidate. Proposed decoded3..28 inclusive26 old controls→25 own controls; candidate50 full controls. Retain decoded2 [134.91919,35.60674] and29 [134.90653,35.60458] exactly, plus every other outside support and both station endpoints. Project only onto the identified east→west chain; no reversal, neighbor snap or control averaging.

Entry3 [134.91883,35.6067]→[134.91882712590913,35.60673141517377],3.5029m. Exit28 [134.90717,35.60465]→[134.9071612442955,35.60469496582078],5.0623m. Largest old-control separation from this own reference is36.1460m at decoded18 [134.91253,35.60474], a coordinate comparison, not an Apple pixel residual. Candidate entry/exit headings2.5872°/3.6297°, next raw guard8.3985°, maximum local9.4002° (retained source curvature, not flattened). Ending25/26/27 leaves approximately9–12.68° seam/guard bends; starting4 creates13.44° entry. Ending29 moves a seam to12.11°. Frozen3..28 avoids those larger seam changes while retaining the genuine broad coastal/reverse bend and tunnel approach. These evaluated alternatives are local source calculations, not visual acceptance.

OSM has KSJ2 ancestry, so explicit passenger identity is credible but this is not an independent track survey. Standard map pixels show the south bow disagreement but cannot prove physical rail centre, station platform caps/faces, hidden tunnel alignment, or measurement accuracy. Candidate inspection must review the whole bow and both joins, while preserving #9 accepted candidate point-for-point. No station movement or physical source edit is proposed. #6 northern-arm offset and other retained Miyazu leads stay separate and pending.

## Same-authority candidate implementation

Extended the existing `app/scripts/railway/repair-miyazu-yosano-display.mjs`, its one evidence JSON and existing test file. No second Miyazu repair script or generic stage framework. The existing accepted #9 fields/candidate/native row remain exact history; the authority accepts exact original, accepted-only-#9 and combined candidate shapes for replay. Only new interval15 provenance carries `source-candidate-native-review-pending`. Five exact response byte guards, versioned tags/node controls, shared-node chain, all four explicit passenger relation/member sequences, exact N02 row/feature and3..28 boundary projections are validated before constructing one own display fragment.

The same `partRowsForLine` and display-interval/native plain-row path now consume both9/15 overrides. Actual current native row `[line,0,0,17,1569,83947,null,null,[]]` becomes `[line,0,0,17,1568,83936.6,null,null,[]]`; it stays plain interval-backed, with no independent embedded station-approach geometry. No own lane/follow/family/hub/loop/reverse/stroke/boundary references exist; existing guards reject introduced measured dependencies and preserve unrelated native rows/document keys. Both raw N02 features and all six scoped primary response files remain protected in CLI apply snapshots. No production apply was run.

Focused existing test regression first failed because interval15 override was absent (`/private/tmp/jtm-miyazu15-red.log`). After implementation,4/4 tests passed,0failed,432.2ms (`/private/tmp/jtm-miyazu15-green.log`), covering physical/IDs/km/other-line preservation, #9 exact upgrade/idempotence, exact source membership/node/byte/guard refusal, native row from both intervals, actual1569→1568 row upgrade, and entry/exit tangent bounds. Command: `node --test app/scripts/railway/tests/miyazu-yosano-display.test.mjs`.

Candidate export completed through the existing CLI only: `node app/scripts/railway/repair-miyazu-yosano-display.mjs --candidate-root /private/tmp/jtm-miyazu15-candidate-20261018`. Read-only comparison against the current production package confirmed only own display interval15 is added, accepted9 remains point-for-point exact, physical stations/segments are exact, and every other line is exact. Candidate native row is1568/83936.6m. Export log `/private/tmp/jtm-miyazu15-export.log`. No native capture, app/build or apply. Parent must inspect candidate bow, both splices and retained region before acceptance/application; original #9 candidate receipt/report is not overwritten.
