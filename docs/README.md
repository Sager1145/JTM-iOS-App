# Documentation

Start with the current guides. Dated reports retain source evidence and findings
for their recorded inputs; they are not current execution instructions.

| Purpose | Entry |
| --- | --- |
| Use the app | [User guide](guides/user-guide.md) |
| Build, sign, release and recover | [Runbook](guides/runbook.md) |
| Native setup and constraints | [iOS README](../ios/README.md), [verification policy](../ios/VERIFICATION.md) |
| Feature and file ownership | [Features](../ios/docs/features.md), [source structure](../ios/docs/source-structure.md) |
| Actual feature interfaces and simplification review | [Feature interface audit](architecture/feature-interface-audit.md), [function interface map](reference/function-interface-map.md) |
| Shared Swift/JavaScript behavior | [Porting guide](../ios/docs/porting.md) |
| Package API | [RailKit reference](reference/api-reference.md) |
| Service branding and data contracts | [Branding](reference/train-service-branding.md), [database checklist](reference/train-service-database-checklist.md), [rail history](reference/rail-history.md) |
| Repository layout and cleanup record | [Repository organization](repository-organization.md) |
| Documentation upkeep | [Maintenance policy](maintenance/documentation-strategy.md) |
| Dated maintenance records | [Codebase structure review](maintenance/2026-11-05-codebase-structure-review.md), [UI reorganization passes](maintenance/ui-reorganization.md), [sample-trip verification](maintenance/sample-trips-verification.md), [2026-10 refactor archive](maintenance/archive/2026-10-refactor/) |
| Architecture decisions | [ADRs](decisions/) |
| Design specifications | [Specifications](specs/), [dated designs](superpowers/specs/) |
| Work in progress | [Plans](superpowers/plans/), [2026-10 scope ownership (archived)](maintenance/archive/2026-10-refactor/task-ownership-20261010.md) |
| Retained completion evidence | [Completed work records](superpowers/completed/) |
| Historical findings and evidence | Reports by topic: `docs/reports/` moved to the external evidence drive on 2026-10-30 (see [evidence storage](../railway-evidence/README.md)); `docs/reports/...` paths in older documents are lookup keys there |
| Diagnostic apps | [Auxiliary app index](../ios/auxiliary/README.md) |
| Railway source provenance | [Source center](../railway-sources/README.md) |

Reports are grouped into integration, performance, routing, Japan, North America,
stations, map display, journeys, timetable and source research. Source-structure
inventories and reviews live in `ios/docs/reviews/`. Keep data provenance and
license documents beside their datasets/assets; keep AGENTS.md, CLAUDE.md and
local README entry points at their discovery locations.
