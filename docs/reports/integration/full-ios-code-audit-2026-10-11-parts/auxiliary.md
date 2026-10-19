# Auxiliary — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## A1 — P2: RouteWorkbench can overwrite its input with its report

Locations: ios/auxiliary/RouteWorkbench/App/RouteWorkbenchModel.swift:274-276, :213-217; ios/tools/verification/route.sh:16.
The app accepts --inspect-input and --inspection-report without checking file identity, then writes report data atomically to automaticReportURL. Direct launch with the same path destroys the imported original after solve/inspection. The Shell module rejects only equal strings; /private/tmp/input.json and /private/tmp/./input.json pass that guard but resolve to the same file. This violates its stated contract that the input stays unchanged and report is separate. Targeted scratch query confirmed literal-distinct paths resolve equal; no app launched and no actual user file modified. Normalize/resolve both URLs and reject the same file before import/start; for existing files compare file identity as well. Test the production argument/output owner with equal path and alias; no such native owner test exists in the reviewed auxiliary tests.

## A2 — P2: Manual inspector capture can overlap an active batch capture

Locations: ios/auxiliary/RailAlignmentInspector/Sources/InspectorApp.swift:158-159; InspectorModel.swift:261-267; BatchCaptureController.swift:184-189, :318-321; InspectorMap.swift:119-126.
Start batch capture, then click the still-enabled manual evidence button while a batch snapshot is suspended. captureRequested checks only busyCapture; batch captures never set that flag. Both paths create independent MKMapSnapshotter work. Batch admission checks busyCapture only at its start, so the reverse order is fenced while manual admission during batch is not. The controller promises one snapshot in flight, and ios/VERIFICATION.md explicitly prohibits another heavy job while capturing. Unify admission or guard manual capture while batch.isRunning. Source trace proves concurrent admission is possible; no runtime CPU/performance measurement or actual snapshot overlap executed. Existing InspectionKit tests cover pure plans/identities but cannot catch app capture admission.

## Architecture judgment

Worth exploring: one evidence-capture module with a small interface admitting manual or batch requests. Current separate manual and batch owners expose admission requirements across the seam; sharing the owner gives locality to cancellation/admission and lets tests exercise the same interface as both callers. Preserve their distinct evidence scopes and human verdict semantics. Do not expand inspector centreline output into a claim about main app multi-line rendering.

## Positive contracts and limits

Temporal patches bind indexed edits to physical leg identity and validate subsequent date boundaries before persistence. Workbench mutable document is actor-owned and writes candidates atomically before publication. Alignment plan keeps invalid geometry visible as unknown; capture status never becomes a human geographic verdict. Captures retain exact input/render/reference dependencies and check receipts before reuse. Main/iPhone orientation and auxiliary typography bounds are present in source/build wiring. These are source observations, not runtime validation.

## Final inventory additions

AppleMapRailExtractor.swift (288 lines) and AppleMapRailExtractionTests.swift (83 lines) were found by the refreshed code inventory and read in full. Raster extraction explicitly reports glyph candidates, preserves unsupported gaps and ambiguity, and does not claim physical identity or surveyed alignment. Tests include offset, masked and broad-road rejection, equal-rival ambiguity and a required existing screenshot. No new concrete defect found. This review does not establish detection accuracy on unexamined imagery or runtime performance.

## Late inventory addition

AppleMapAnalysisService.swift (219 lines) was discovered by the final refreshed inventory and read in full. Reviewed snapshot scale/projected inverse, raster/OCR mask preparation, cancellation handoff to detached analysis, named station-POI limits, clipping and evidence serialization. No independently established new defect. Image coordinate orientation and extraction quality were not measured; this newly added path has no runtime certification from this audit.
