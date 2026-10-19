# Current feature reference

Reviewed against the source layout on 2026-10-10. This page identifies implemented
feature areas; it does not assert complete runtime acceptance or performance.

| Capability | Source owner |
| --- | --- |
| Journey list, search and details | `ios/RailMap/Journeys/`, `Workspace/` |
| Journey editing, station selection and route repair | `ios/RailMap/JourneyEditor/` |
| Map rendering, geometry, station labels and ridden coverage | `ios/RailMap/Map/` |
| Mileage and journey statistics | `ios/RailMap/Statistics/` and RailCore |
| Playback and video export | `ios/RailMap/Playback/` |
| Sharing cards and snapshots | `ios/RailMap/Sharing/` |
| JSON import/export, samples, backups and OCR entry | `ios/RailMap/Import/` |
| Timetable matching and service selection | `ios/RailMap/Timetable/` and RailCore |
| Localization and display settings | `ios/RailMap/Localization/`, `Settings/` |

Supported bundled regions are Japan, Taiwan, Hong Kong, Macao and Korea.
North America remains an offline archive. Through-service presentation does not
prove a physical connection; unresolved physical routes stay pending. iPhone is
portrait only, while iPad supports four orientations. See [native product rules](../AGENTS.md).

Read [the user guide](../../docs/guides/user-guide.md) for workflows and
[the source structure guide](source-structure.md) for module and file ownership.
Use the [current function/interface/implementation map](../../docs/reference/function-interface-map.md)
for ownership, the unified diagnostics interface, and outstanding simplifications.
The [historical feature parity ledger](../../docs/reports/integration/feature-parity-ledger.md)
retains its recorded gaps and evidence. Current scope ledgers under
`ios/refactor-parallel/` retain unresolved acceptance questions. Use
[the current verification policy](../VERIFICATION.md) to select evidence.
