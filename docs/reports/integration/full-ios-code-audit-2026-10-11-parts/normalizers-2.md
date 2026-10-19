# Normalizers 2 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## T2-1 [P2] Finish validation before writing route completeness and research state

Anchor: [ios/tools/normalize-reviewed-current-n02-route-identities-20260930.py:503-507](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-current-n02-route-identities-20260930.py:503) and `:522-525`.

normalize prepares route rows in memory, but writes each changed fact-completeness file immediately inside the validation loop (:504), before confirming all target completeness rows were found. It likewise writes research-queue files (:523), before confirming full queue scope, the second completeness read, and generated fact-key uniqueness (:524-541). Actual route segments, sources, additions and facts are written only later (:543-555).

Concrete rejection scenario: a declared target lacks its route_lines research row. All changed completeness notes and earlier queue notes are persisted, then queue_seen != target_trip_ids throws. The command reports failure and leaves the route segments/facts at their old state while the evidence notes describe the newly prepared state. Similarly, a non-open queue row in a later file causes earlier owner-file changes to remain. This follows directly from the source write order; no injected failure or normalizer execution was performed.

Collect the changed completeness/queue records in the existing in-memory output preparation and write them after the seen-set/status/fact validations pass. This requires no new pipeline or general defensive framework.

Related early-write example: [ios/tools/normalize-reviewed-central-fujikawa2-20260930.py:88-91](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-central-fujikawa2-20260930.py:88) writes the shared Fujikawa service record before even reading the candidate/source and calling validate. A rejected/missing candidate still creates or rewrites that shared canonical service. The current saved service row already matches the literal, so this review does not claim existing bytes are presently wrong. Prepare that shared row with the other outputs and validate its proposed identity before publishing it.

## Investigated and resolved, not findings

- The base Haruka53–60 normalizer emits planned seat categories without car_count while current seeds/tests expect nine cars. The actual rebuild driver lists that base at [rebuild-reviewed-train-timetable.py:53](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/rebuild-reviewed-train-timetable.py:53), then [annotate-reviewed-west-haruka-nine-car-20260930.py](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/annotate-reviewed-west-haruka-nine-car-20260930.py) at :362. The annotation validates all sixty Haruka formations and sets car_count=9 at :55-57. This is an explicit owner/overlay sequence. Hokkaido base scripts likewise require the later standard formation overlays at driver :342-344. A standalone base invocation is not claimed to preserve every later-enriched field; this audit does not promote that documented sequencing as a generator defect.
- The Taisetsu overlay cites a current guide describing 特別快速大雪. Focused raw canonical records for 3591D and 3592D already declare special_rapid, agreeing with that source interpretation. No classification finding. No outside train fact was asserted.
- Sonic59's rollover uses ordered printed clocks. Its current candidate has 宇佐23:55 followed by 杵築00:11/00:12; the reviewed parser increments the service-day offset at that transition, and no same-stop midnight straddle exists in this pinned input.
- Source-pinned promotion scripts generally retain exact-day occurrence bounds, source permission metadata, null clock sides, planned-versus-actual formation distinctions, route-only boundaries without passenger-call insertion, and partial current-N02 line claims. These are useful contracts. Source pinning is repository evidence, not a fresh external timetable verification.
