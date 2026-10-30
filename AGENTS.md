# Verification policy

The user retired standalone verification scripts and automatic verification
pipelines on 2026-10-10 because they consumed excessive time and CPU. Read
`ios/VERIFICATION.md` for their purposes and the current process. This policy
supersedes historical plans that require the removed runners or full matrices.

Start with a chat review of the changed code/data and relevant dependencies.
Review relevant Swift/JavaScript counterparts and bundled ID references when
shared behavior or identities change. Reuse still-applicable evidence after
confirming its relevant source/input dependencies are unchanged. Execute only the focused existing test, targeted
data query or incremental build needed to resolve a specific correctness question.
Coordinate one heavy job at a time across chats. Do not recreate umbrella runners,
full baseline/candidate suites, full-tree hash custody workflows, synthetic
evaluator campaigns or automatic delivery loops. Use the existing scope ledgers
for a short evidence/result note. Broaden checks only for an observed failure or
concrete dependency; stop once sufficient evidence exists.

Keep runtime validation, data builders, product constraints and meaningful
production regression tests. Chat review cannot prove runtime, pixel, leak or
performance claims; report unmeasured claims accurately. Retired reports remain
historical evidence. Do not run checks merely because a stale document names them.

# Railway evidence storage

New native railway evidence, screenshots, task requests, candidate outputs and
local build receipts belong under the mounted external canonical root:
`/Volumes/JTM Evidence/99 Compatibility/Workspace/JTM-iOS-App/railway-evidence/local/`.
Use its `diagnostics/sessions/` child for new Diagnostic sessions. Keep concise
review summaries in the existing scope ledgers.

The user's latest 2026-10-24 instruction requires evidence only on the external
drive `Untitled`, under `JTM Railway Evidence`; its APFS container mounts as
`/Volumes/JTM Evidence`. Read pictures at their canonical external paths. After
verifying a copy, delete its original and remove its original-location compatibility
link. Historical original paths are inventory lookup keys, not supported read paths.
Retain uncopied local iCloud originals until retrieval and copy verification succeed.
See `railway-evidence/README.md` and the external `00 Inventory/INDEX.md` for transfer
receipts and current remaining files.

Do not upload new evidence to iCloud or create an internal synced fallback when
external storage is unavailable. Pause evidence writes until the drive is mounted.
Do not add copy schedulers, age-based deletion or local eviction. Source code and
runtime dependencies remain in their established locations.

# Railway vector point count

When building railway vector geometry, represent straight spans with two endpoints
where possible. Retain additional vertices for stations, real bends and required
joins; omit redundant points along a straight span. Preserve station identities,
physical topology and mileage when simplifying display geometry.
