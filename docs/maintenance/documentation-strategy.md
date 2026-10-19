# Documentation maintenance

Reviewed 2026-10-10. Project maintainers own this guide; each change author owns
updates to the documents affected by their work.

## Give each document a purpose

The root README is the entry point: explain the app, the shortest setup and where
to read next. Keep mutable details in one maintained location and link to it.

| Reader need | Maintained source |
| --- | --- |
| Use and recover journey workflows | User guide |
| Build, sign and release the app | Runbook |
| Understand native architecture | iOS README and accepted ADRs |
| Look up package contracts | API reference and actual Swift declarations |
| Port shared behavior | Porting guide, JavaScript sources, fixtures and relevant tests |
| Find current product capabilities | `ios/docs/features.md` and shipping code |
| Select proportionate evidence | Current section of `ios/VERIFICATION.md` |
| Understand a completed investigation | Clearly dated retained evidence or an owning scope ledger |

The source tree owns implementation facts. `ios/JTM.xcworkspace` owns workspace
membership; `ios/RailMap.xcodeproj/project.pbxproj` owns main-target settings;
`ios/RailKit/Package.swift` owns package products and dependencies. RailMap and the
three RailKit targets use feature directories without changing module ownership.
RailCore uses Foundation with scoped read-only SQLite timetable access;
RailPresentation owns portable display rules; RailApplication owns portable use
cases; RailMap owns native UI and platform effects.

Retired scripts and removed CI jobs are historical context, not operational
sources of truth. North America is retired; its offline archive does not describe
supported app inputs or a current data-release workflow.

## Update documents with the change

Review user-facing workflows against the shipping interface, public API prose
against current declarations and contracts, and command examples against existing
paths and schemes. Do not maintain fixed symbol counts, test counts, version
numbers or performance claims without a current source and a reason to include them.

For shared behavior or identities, review the relevant JavaScript/Swift counterpart
and bundled references together. Explain intentional parity differences. Mark
historical observations with their date and applicable scope; distinguish reviewed
procedure examples from commands actually executed in the current environment.

Documentation and mechanical changes need a diff and reference review. Reuse
applicable evidence after checking relevant dependencies. Run only the focused
existing test, query or incremental build needed to resolve a concrete question;
coordinate one heavy job at a time. Do not add a documentation CI pipeline,
umbrella runner, full matrix or corpus-wide custody process as routine upkeep.
Record a short result in the existing owning ledger when the scope calls for one.

## Keep history useful

Keep active guidance, durable decisions and evidence still needed by current
work. Remove obsolete instructions, duplicate copies and completed plans whose
useful conclusions are already captured elsewhere. Update incoming links when
moving or deleting pages. A deleted plan does not remove its product constraints
or invalidate useful dated evidence.

ADRs live under `docs/decisions/`. Keep their decision context and consequences;
label superseded decisions and link to their replacement instead of presenting
old architecture as current. When implementation changes, review affected ADRs
alongside the active guide. Do not turn a historical decision into a new automatic
gate merely because it once named one.

## Writing and review

Write for one audience and reader goal. Lead with the useful action or fact,
include failure/recovery guidance where relevant, and use repository-relative
links. Keep examples small and identify their prerequisites. Avoid secrets,
personal machine paths and unsupported measured claims.

Review changed documentation during code review and release preparation. Revisit
commands and requirements after toolchain, schema, workspace or signing changes;
update recovery guidance after an incident. Maintenance is tied to actual changes,
not a requirement to rerun every documented command on a fixed schedule.
