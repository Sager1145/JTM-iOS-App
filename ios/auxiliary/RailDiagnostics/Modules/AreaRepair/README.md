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

Default writable target: `app/data/physical-rail-junctions.json`. `rail-history.json` needs `--allow-generated --confirm`; `jp-2025.json` is always refused. `write` without `--confirm` is a dry-run. Backups and an inverse receipt go under `<evidence root>/area-repairs/<id>/receipts/`.

## Tests

`bash ios/verify.sh area` has no test verb; the package tests (fixtures under `Tests/AreaKitTests/Fixtures`: scope/detectors, patch and write, real-data) run with `swift test --package-path ios/auxiliary/RailDiagnostics/Modules/AreaRepair --filter NAME` inside the heavy-job lock.
