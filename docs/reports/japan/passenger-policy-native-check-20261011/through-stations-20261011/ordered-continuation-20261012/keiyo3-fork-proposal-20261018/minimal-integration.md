# Keiyo-3 west-arm window: minimal integration proposal

Read-only source review, 2026-10-18. No source edits, tests/builds/app/capture/apply in this continuation.

The selected explicit west passenger track is an attributed display reference. It is not a surveyed representative centre. The own ordered source chain is OSM229030139 ->180845372 ->180845377 ->180845376, explicitly present in live relation14656632 (Fuchu-Honmachi ->Tokyo); current source window22..34 is13 controls and the proposed slice is22 supports. Both outer neighboring controls21/35 and every subsequent lower-fork/station support remain fixed. The descriptor should pin exact old/new interior arrays between those coordinate guards; one helper accepts only those exact old/new windows and replaces the old one. This gives idempotence without a stage flag or status branch.

## Existing ownership and exact dependency

- Authoritative western.selectedDisplayEvidence already points to keiyo-display-curves-evidence.json. Its western window currently owns only the lower tail, not the faulty northern fork approach. Add this bounded approach descriptor and its own source records to that existing western evidence window. Retain the existing lower-tail fields/indices/ways intact.
- repair-keiyo-display-curves.mjs currently reconstructs the western display as raw upstream prefix plus lower surveyed tail, and compares the entire existing display against that result. Apply the single helper to this reconstructed display before the comparison. This ensures earlier tail replay cannot restore the old eastward fork bulge.
- repair-keiyo-midcurve.mjs::westTrunkCoordinates reconstructs that same western candidate independently before asserting it. Apply the same helper there. The physical comparison must continue to cut originalArm at canonical index39, while the corrected display fork is index48. The shared trunk8 coordinate array itself must remain byte-for-byte equal, because replacement ends above the lower fork.
- repair-keiyo-shio-transverse-display.mjs freezes the entire original western arm in historical Shio baseline evidence. It restores that entire arm during retainedShioPackage and validates exact replay. Normalize only this pinned upstream window at its retained/reapply boundaries, using the same helper on both incoming arm and frozen baseline arm. Keep historical Shio evidence unchanged. The station region and trunk8/9 arrays are not touched by the approach helper.

## One helper, no module cycle

Place/export the exact bounded-coordinate helper in the existing Shio replay module, which already imports only Minami/geometry dependencies. The helper reads the new approach descriptor from the existing tail evidence JSON; it can validate the selected cached ways when cache is supplied. Both tail builder and midcurve already import Shio, so reuse introduces no reverse module import or new module/pipeline. Shio itself uses it for the frozen baseline normalization above. Keep it specific to this pinned own approach, not a generic repair/migration framework.

The approach descriptor contains source way IDs/tags/coordinates, explicit route-member proof, the old/new bounded arrays, and the source projection witnesses. Prefer deriving the projected boundary coordinates through the repository's existing geo projection when freezing authoritative evidence, then compare the exact derived slice; the provisional proposal's small equirectangular projection values are not a substitute for that source replay.

## Explicit physical/display index distinction

sharedEvidence.western.armDisplayForkIndex currently39 served both raw and display cuts only because the old upstream counts happened to agree. Introduce armCanonicalForkIndex39, update armDisplayForkIndex48, and change only the raw comparison in westTrunkCoordinates to use armCanonicalForkIndex. Existing Shio reconstruction/assertions then use the correct display48. The lower fork coordinate remains[139.95346,35.68953], trunkDecodedForkIndex remains7 and all canonical source/mileage/station IDs remain unchanged. This is index bookkeeping, not a new branch/topology.

## Native parts, follows and family

The western arm gains9 supports upstream of the shared corridor; existing final arm part count87 should become96 if grooming retains all inserted source supports. This count remains an output observation, not a hard-coded acceptance promise. Whole part chainage to the same lower fork/station changes, so its existing follow start/end and tenant family window must be rederived from actual parts. Existing shared trunk8 geometry and its landlord coordinate guards remain exact; a changed upstream length in another trunk interval can still change absolute mainline measures. Use existing partsForRetainedKeiyoStage(newPackage, oldLanes, originalPackage) at the CLI boundary, then existing repairParts. Do not add follow/lane ownership, lane offsets, family groups or boundaries. Current explicit lane/loop/chain-boundary arrays have no owned rows; Tokyo hub retains excluded crossing membership.

## Files expected to change if implementation is authorized

1. app/scripts/railway/keiyo-display-curves-evidence.json: add this one own approach descriptor inside the western evidence window; lower tail evidence remains historical and unchanged.
2. app/scripts/railway/repair-keiyo-display-curves.mjs: apply the shared helper after reconstructing western lower-tail display and include the new own approach provenance in its existing marker.
3. app/scripts/railway/keiyo-shared-corridor-evidence.json: distinguish canonical39/display48 on western arm.
4. app/scripts/railway/repair-keiyo-midcurve.mjs: reuse helper in western candidate reconstruction and use canonical index for raw comparison; existing CLI/parts machinery remains the single integration path.
5. app/scripts/railway/repair-keiyo-shio-transverse-display.mjs: own the one shared bounded helper and normalize only that upstream prefix at retained/reapply boundaries. Frozen Shio evidence file remains unchanged.
6. Existing keiyo-display-curves.test.mjs and keiyo-shared-corridor.test.mjs: regression for the own west arm (east-way IDs excluded), exact source chain/boundaries, canonical/display fork distinction, unchanged shared trunk8 and Shio local tails, physical preservation and older full replay/idempotence; refresh only directly affected old count/ruler expectations.

No production output apply, alternate repair executable, new stage flag or broader validation campaign is needed. Parent owns any focused test/candidate/native execution.
