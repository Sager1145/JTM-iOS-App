# AreaRepair

Small-area capture and repair for Rail Diagnostics: select an area, collect evidence, detect problems, draft/preview a patch, write it behind a guarded transaction. Design rationale is in `../../DESIGN.md`; user how-to in `../../README.md`; agent recipe in `.claude/skills/rail-diagnostics/SKILL.md`.

## Layout

- `Sources/AreaKit` — library: `AreaScope`/selection, `AreaLoader`/`DataRoot`/`ScratchOverlay`, `Detectors/`, `AreaEvidence` (jtm-area-evidence-v1), `AreaPatch` (jtm-area-patch-v1), `Preview`, `WriteTransaction` (`WriteReceipt`, undo), `GuardRunner`.
- `Sources/jtm-area` — CLI: `capture-data`, `problems`, `apply`, `preview`, `write`, `undo`, `guard`. Run via `bash ios/verify.sh area VERB [options]` (`--help` per verb). One compact JSON on stdout. Exit 0 ok, 2 invalid/refused (dry-run write too), 4 problems or guard failure, 1 internal.
- `App/` — `AreaRepairModel`, `AreaWorkspaceView` (workspace ⌃⌘5; commands in `Sources/UnifiedDiagnosticCommands.swift`). Selection type lives in `ios/InspectionKit/Sources/RailInspection/AreaSelection.swift`, request plumbing in `DiagnosticRequest.swift`, capture in `DiagnosticSession.runArea`.

## Entry points

- Library: `AreaPatch.decode/validate/encoded`, `AreaPatch.guards(for:)`, `AreaEvidence.make/write`, `Preview.run`, the write transaction and `GuardCommands`.
- Agent capture: `python3 -I ios/tools/verification/diagnostic-run.py area capture ...`.

## Writes

Junction rows are checked against the registry rules (≤30 m shortLink, evidence, geometryEvidence) and every jp `lineIDs` entry must be a line of `jp-2025.json`; a retired line absent from the package is accepted only when `rail-history.json` knows `jp-<operator>-<line>` (section, station or identity period) and the row's `validFrom`/`validTo` overlaps one of its periods (e.g. 江差線 yes, 海峡線 no).

Default writable target: `app/data/physical-rail-junctions.json`. `rail-history.json` needs `--allow-generated --confirm`, and the result then lists `generatorFixNeeded` (mirror into `app/scripts/railway/jp-rail-history-events.json`); `jp-2025.json` is always refused. One decision (`OpDisposition`) drives both the dry-run plan and the write check. `write` without `--confirm` is a dry-run. Backups, the inverse patch and a `pending` receipt listing every file's hashes go under `<evidence root>/area-repairs/<id>/receipts/` before the first repository write; any failure restores the backups. `undo` accepts a `written` or `pending` (interrupted) receipt. Scratch overlays (`apply --scratch`, preview) refuse the repository root, its ancestors, its `app/` tree and any directory whose targets resolve to repository data files.

## Tests

`bash ios/verify.sh area` has no test verb; the package tests (fixtures under `Tests/AreaKitTests/Fixtures`: scope/detectors, patch and write, real-data) run with `swift test --package-path ios/auxiliary/RailDiagnostics/Modules/AreaRepair --filter NAME` inside the heavy-job lock.
