# Current chat ownership — 2026-10-10

The user requested independent chats with minimal mutual contact. This allocation
supersedes the earlier informal coordination messages. Existing changes, staged
source removals, evidence and paused-process restoration obligations are preserved.
This is an ownership agreement, not evidence that outstanding repairs pass.

## Independent work lanes

| Lane | Owning chat | Exclusive current write scope |
| --- | --- | --- |
| Route solving | 重构大量线路的求解功能 (`01a12775-abed-7740-a4e6-e4e71df93648`) | `ios/auxiliary/RouteWorkbench/`; `ios/RailMap/Infrastructure/Persistence/RiddenRouteStore.swift`, `TimetableRouteEvidence.swift`; RailCore solver, graph, physical matching, route confirmation, shared-work/memo/limiter and batch inspection implementation plus their directly corresponding tests; existing route plans |
| Display geometry | Compare railway line alignment (`01a12775-57a9-7af3-b693-e4f1abcf27a8`) | `ios/auxiliary/RailAlignmentInspector/`; RailCore `ContinuousStroke.swift`, `DisplayParts.swift`, `PrecomputedRouteDisplay.swift`, `DisplayChunkReader.swift` and directly corresponding tests; `ios/RailMap/Map/MapLineGeometry.swift`; JS stroke/display counterparts and their tests; Japan generated display packages/caches, display-only lane/follow/mileage reference remaps and display port fixtures; Inspector project wiring; existing alignment plans and evidence |
| Historical through services | 修复全时段直通线路网 (`01a12775-0776-7fa1-9bb2-ceb5b4e043fd`) | `ios/auxiliary/ThroughWorkbench/`; RailCore `JapanThroughServices.swift`, `Resources/japan-through-services.json` and through-service tests; `app/data/japan-through-services.sources.md`; dated service evidence and existing history plans |
| UI interaction | 制定 JTM iOS 重構路線圖 (`01a11e89-e93c-7ca0-8652-88f20736a64a`) | Returned journey-list state and interaction: `BottomChrome.swift`, `WorkspacePanelPage.swift`, relevant editor/chooser views, `WorkspaceEditingTests.swift`; `parent-coordination.md`. No solver or display implementation ownership |
| Shared integration | Coordinate across chats (`01a127c6-3674-7352-85da-b947861adaf5`) | This allocation; shared schema/API decisions, source-center/ignore/index transition after the route owner's current handoff, main-app/package wiring, runtime resource manifests and shared cache revision integration; physical railway databases/topology/identity joins. Display-only generated outputs and Inspector wiring belong to alignment |

An unlisted shared file is not implicitly writable by every lane. Its owner is
assigned here before modification. Existing unrelated user changes in an owned
file remain preserved. Lane ownership does not authorize staging, committing,
pushing, publishing, moving other chats, or terminating processes.

## Stable boundaries

Each lane reads current published data as an input and writes only its own scope.
Display-only splitting must preserve physical reachability and surveyed identities.
Historical services refer to physical station/line/section identities, not temporary
display-part positions. Solving never treats display proximity as physical evidence.
UI consumes route results; it does not change solver lifecycle to fix panel state.

For a physical database/registry, shared schema or other cross-lane edit,
record the exact proposed records/fields and reason in the lane's existing ledger.
The integration owner applies the shared change at a checkpoint. The display lane
owns its geometry plus derived display outputs end to end; these are not routine
integration handoffs. Do not have two
chats regenerate the same outputs or edit different records of the same JSON file.
The pending 二本木 split includes historical dependencies
`echigo-shirayuki` leg 0 and `hokuetsu-echigo-yuzawa` leg 3. Review dates and ID
references during integration; current historical reports do not certify pending
display artifacts. Persisted geometry changes require cache revision review.

## Communication and execution

- No routine peer-to-peer status requests, repeated ownership negotiations or
  duplicate reviews. Each chat uses its existing scope ledger.
- At completion or a genuine cross-lane blocker, leave one handoff: owned files,
  behavior changed, focused evidence, exact requested integration and uncertainties.
  This chat reads those ledgers and chat status; workers need not message peers.
- Continue useful work within the lane without waiting for another lane's changes.
  Avoid broadening a local defect into nationwide review or general refactoring.
- Build products, report files and temporary outputs use lane-specific directories.
  Never reuse the same scratch directory across Xcode and SwiftPM, or overwrite
  another lane's products. Do not share mutable running app instances.
- One heavy job at a time, as required by `ios/VERIFICATION.md`. The route lane
  finishes its current 201-record repeat and restores its explicitly paused external
  test before releasing the window. Other lanes continue source/evidence work.
  Record release in the route plan; the integration owner schedules the next needed
  job. A released route window does not prove the resumed external job is idle.
- No umbrella runner, automatic delivery, full matrix or new baseline campaign.
  Reuse applicable results; run only the focused check needed for a concrete question.

## Parked and completed chats

`JTM 重构：UI 与全平台回归` and `JTM 重构：架构、覆盖率与质量` remain
stopped with their evidence preserved; their historical automatic pipelines do not
restart. UI work currently has the single owner above. General architecture,
coverage and footprint work is deferred until the active behavior changes have a
stable integration checkpoint, rather than editing the same helpers concurrently.

`Streamline verification scripts` remains completed; the current verification
policy is authoritative. `Rewrite chat thinking skill` is separate configuration
work and receives no JTM production assignment. Unrelated personal/cloud chats
are outside this repository allocation.

## Physical workspace status

The current lanes still use the same checkout, which contains extensive mixed
uncommitted work and staged raw-source removals. No checkout has been reset or
moved wholesale: doing so would transfer other lanes' in-progress state. Exclusive
write ownership and separate scratch products reduce interference now; they are
not filesystem isolation. A lane can move to a managed worktree at a stable,
reviewed checkpoint with its exact owned state and required local inputs preserved.
Until then, do not run blanket staging, cleanup, source relocation or delivery.

## First shared integration handoff applied

Alignment handed off two synthetic fixture records, drawn-cache invalidation and
Inspector source membership. Integration updated only the five proposed fields in
those two `port-fixtures/display-parts.json` records; all other records/metadata
were compared in memory and preserved. `RouteGraph.routeDrawnCacheVersion` is now
31 so old persisted display geometry is retired. The existing Inspector project
now lists `InspectorStrokeGeometry.swift` in its source group and compile phase;
its XcodeGen spec already includes the Sources directory.

Evidence: scoped diff whitespace check and project plist lint passed. No build or
Swift test was started while the route window is occupied. Focused Swift parity
and Inspector compilation remain pending; these edits do not establish native
branch pixels or current build success. Existing Nihongi output changes were
preserved. The older fixture prose still describes station-derived lead-ins; its
wording needs alignment with the geometry owner's final contract at review.

## Ownership correction: geometry and its derived artifacts stay together

The exact shared-spur repair expanded beyond the first two synthetic records.
Splitting geometry implementation from its dependent display artifacts created
repeated integration messages, contrary to the user's requested independence.
The alignment lane now exclusively owns its relevant Japan display packages,
part/lane/follow and display mileage references, display port fixtures and auxiliary
Inspector project membership, including the already applied integration edits.
It must preserve physical station/segment identities, historical service data,
source-center/index state, other lane edits and the Hisatsu publication exclusion.
Unrelated regional artifacts are not included. Do not regenerate the whole national
corpus for a scoped repair. The solver's running frozen bundle remains unchanged.
Cache version 31 stays integrated; future unreleased geometry corrections can use
that revision unless a concrete cache compatibility issue requires another change.
Physical databases/registry and shared public API changes still need integration;
display fixture or generated-geometry updates no longer need a separate message.

## Route lane's new direct-user scope

The route owner reports a new direct user request to improve the test tool and
organize the repository. RouteWorkbench detailed reports, filters and selected
result detail remain exclusively in that lane. It additionally owns
`docs/repository-organization.md` and its local classification inventory. Repository
classification is read-only first; active code, compiled databases, source-center
paths and other lane files stay in place. Any move is limited to identified root
scratch prompt files with no code/build dependency, preserving their contents and
recording old/new paths. `.gitignore`, root README, Git index and shared project
wiring remain integration-owned; propose those exact edits in the lane ledger.
This allocation introduces no heavy-job permission while the restored external
test is running. Finish source work and record the specific Catalyst build needed.

## Source organization migration — 2026-10-10

The user explicitly assigned physical Xcode/source organization and newly created
diagnostic-app placement to 整理并重构 Xcode 项目结构 (`01a12801-b8c1-7163-b1bf-dd87043391e9`).
The prior lane owners were idle at this integration point. Their domain logic
ownership remains; paths now resolve through source-ownership.json and
ios/docs/source-structure.md. RouteWorkbench and ThroughWorkbench are under
ios/auxiliary. Swift modules retain their boundaries and resources. This lane
also owns the new workspace, source inventory, mechanical extractions, naming
and comment corrections. No other chat was messaged or moved.
