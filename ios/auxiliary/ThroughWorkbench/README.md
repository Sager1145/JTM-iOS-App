# Through-history workspace

An internal SwiftUI workspace in RailDiagnostics for reviewing and repairing Japan through-service history. It targets review from **1996-12-31**, the oldest locally documented N02 observation, while retaining the imported catalog's separate **2005-01-01 coverage floor**. It does not certify national historical completeness. Production app code and railway resources are read-only inputs.

Open the single **RailDiagnostics** scheme in `ios/JTM.xcworkspace` and select **Through history**. This module no longer has a standalone application or project. Build, human tasks and exact pattern/date agent requests are described in [RailDiagnostics](../RailDiagnostics/README.md). The local `WorkbenchCore` package remains available for focused tests.

The build copies the current `japan-through-services.json` and compact physical `jp-2025.json` into the app bundle. It includes `rail-history.json` when present. These inputs retain their existing identities and schema fields. No North American data is loaded. Historical geometry is retained as evidence; the corridor preview resolves the selected pattern against the imported physical package. A through-service relationship cannot establish a physical connection or prove routing solvability.

Enter ISO review and comparison dates (`YYYY-MM-DD`) and press **Apply dates**, search the pattern sidebar, and open **Review overview** to inspect issues and dated differences. Pattern detail shows ordered legs, source links, recorded patches, expanded JSON and reference geometry. Missing geometry stays explicit. Dates use Gregorian UTC days with exclusive `validTo` boundaries.

Changing the review date invalidates the previous inspection plan. In the unified app, generating the range plan is an explicit action through the selected end date. Plan export checks the requested end date before reusing a cached plan. Sidebar search ignores surrounding whitespace.

**Create dated patch** accepts a JSON object such as:

```json
{
  "changes": { "validFrom": "2008-06-14" },
  "legChanges": [
    { "index": 0, "changes": { "fromStationCode": "reviewed-station-code" } }
  ]
}
```

Leg indices are zero-based. Saved leg edits bind the original line and station identity; earlier reorders that would retarget them are rejected. Pattern and leg changes preserve unedited fields; `null` removes a field. A patch requires a source URL, review note and effective start, with an optional exclusive end. Use `changes.legs` to replace a full ordered leg sequence. When that pattern has `legVariants`, include the corrected `changes.legVariants` too so their indices cannot silently retarget. Each variant contains ordered `legIndices`, source URLs, notes and an optional half-open date window; unmatched or ambiguous periods have no selected path. For removal, enable the removal toggle with empty `changes` and `legChanges`. The full-pattern editor under **Add pattern** can capture a missing corridor with all schema fields, ordered legs and sources. Match the JSON `id` to the Pattern ID field and enter the evidence in both the patch attribution and the pattern's `sourceURLs` as appropriate. Physical line and station IDs must be reviewed against the imported package.

Working documents autosave atomically in the app's Application Support `ThroughWorkbench/working-document.json`. All file I/O, decoding and core evaluation run through a serial actor. A newly bootstrapped bundled document receives six reviewed onset constraints; restored or imported working documents retain their own patches. Import supports a working document, replacement catalog, physical package or history JSON. Importing a replacement catalog starts a fresh patch history while preserving the loaded physical package and history. Invalid imports and failed saves display an error and retain the current in-memory document.

**Export → Working document** preserves the base catalog, optional physical package/history and all temporal patches. **Export → Expanded catalog** writes the selected day's compatible through-service catalog for separate production review. Export does not replace a production resource. Working documents can be large because they include the physical package once rather than duplicating it per review date.

The app uses standard split navigation, forms, system colors and semantic controls. Dynamic Type is clamped to `.xSmall ... .xLarge`, iPhone supports portrait only, and iPad supports its own orientations. Keyboard shortcuts include Command-N for a new pattern, Command-1 for the overview and Command-S to save an open patch.

Validation follows `../../VERIFICATION.md`: scoped code/data review, focused core tests and one coordinated Catalyst build when needed. Runtime, accessibility, pixel and performance claims require native observation. The workbench does not reconstruct missing endpoint variants automatically; source gaps, historical identities and completeness remain explicit review work.

## Historical inspection plan

Opening a document in RailDiagnostics does not run the full historical plan. **检查计划** opens the dashboard; **刷新计划** uses the current review date as the end of the range, and **导出 JSON** retains the report's displayed range. Browsing a single date does not rerun the historical plan. Successful imports and patches invalidate it; regenerate explicitly when that range investigation is needed.

The plan samples the historical target and end date, plus the day before and day of every declared pattern, leg, variant, connector and temporal-patch boundary within that range. Checks cover catalog identities, half-open dates, ordered paths, source attribution, physical anchors/direction, dated junctions and historical coverage prerequisites. Repeated findings are grouped with their affected dates and next action. Filters separate errors, warnings and unknown evidence, and each pattern finding links back to the record.

The detector preserves raw compact-v1 coordinates and reconstructs omitted shared vertices; it does not silently snap endpoints, invent a missing seam or infer a physical connection from equal station codes. Source URL syntax does not establish the content of a publication. Missing external inventories, historical operator/geometry proof and native routing evidence remain explicit tasks even if structural checks pass.

The logo and app icon are installed from `App/Assets.xcassets`. The original generated artwork and prompt are retained under `Design/`. See `docs/superpowers/specs/2026-10-10-through-inspection-design.md` and the generated inspection report for the complete check scope and record-level repair queue.


The working document can also retain one `physicalJunctions` reference registry, independently of dated service patches. Import **Reviewed physical junctions** to inspect existing documents with this evidence. Catalog replacement preserves the already imported physical references. Recorded junctions are accepted only for matching source identities and actual surveyed leg endpoints within their evidence dates; display connectors and common station codes alone remain unresolved. This does not reproduce the native routing graph or certify historical geometry.

An explicitly sourced, bounded `legVariants` entry with `suspended: true` and empty `legIndices` records a confirmed full-service suspension. An ordinary gap between variants continues to mean unknown. Loop legs may carry `loopTraversal` (`forward`/`reverse`) with `loopTraversalSourceURLs`; direction refers to the physical base's stored station order and supports wrapping the closing interval.
