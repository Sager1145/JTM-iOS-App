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
