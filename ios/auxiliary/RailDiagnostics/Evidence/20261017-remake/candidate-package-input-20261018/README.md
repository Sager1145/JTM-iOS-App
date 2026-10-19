# Optional alignment package input — 2026-10-18

This evidence checks the unified app's optional candidate-package input interface. It does not establish a corner repair, screenshot alignment or Main production composition result. All three native requests use `prepare`, not `capture`; no new snapshots were collected here.

## Contract

An alignment request may use existing `inputPath` for an absolute Japan compact JSON path. Omission loads bundled `jp-2025.json`. The requested file is read with the same `DisplayParts.LoadedPackage.load`, exact-line admission, renderer and captures. A supplied missing/invalid package fails visibly without falling back to the bundle. Package country is compared case-insensitively with `jp`, including existing `JP` packages. Route retains required journey-JSON input semantics; through rejects `inputPath`.

The human form accepts an optional package path or JSON picker. Picker bytes are retained in app-owned input storage while security scope is active, with the original basename. Copying disables workspace/action changes and submission; a failed copy blocks submission until an explicit edit or new choice. Header search uses the selected package. The task card displays Package path/bundled source; a subsequent workspace Capture task carries the current alignment input path forward. Immutable `request.json` includes that path; `result.json` and `alignment-geometry.json` record actual `packageInputPath` and `packageInputSource`. Relevant full-own-line and selected receipt identities still govern compatible resume. These native observations did not exercise a changed-geometry resume rejection or a picker copy failure.

## Retained observations

- `candidate-package-build.log`: parent-run incremental Catalyst build ended `BUILD SUCCEEDED`. Existing InspectorMap deprecated-trait warnings and skipped AppIntents metadata warning remain; this is not a zero-warning claim. Original: `/private/tmp/jtm-diagnostics-candidate-package-build.log`.
- Focused contract test was executed by the parent: `swift test --package-path ios/auxiliary/RailAlignmentInspector/InspectionKit --scratch-path /private/tmp/jtm-inspection-kit-tests --jobs 2 --filter DiagnosticRequestTests.inputPathContractDependsOnWorkspace`. One test in one suite passed in 0.003 seconds. The first sandbox invocation failed on cache permissions; supported escalation succeeded. Raw output remains in the parent tool record; no separate test log was saved and the test was not rerun for this archive.
- `input-smoke/`: agent request for Sotetsu main line interval 0, z19, 1600×1200, basemap/smooth. `result.json` is `prepared`, `dependenciesVerified=true`, `packageInputSource=request`, captured 0 / pending 7. Actual package path is `/Users/sager/Documents/GitHub/JTM-iOS-App/app/public/rail/jp-2025.json`.
- `missing-input/`: agent request points to `does-not-exist.json`. Result is `failed`, `dependenciesVerified=false`, source remains `request`, zero selected captures, and the missing-file error is visible in `missing-input-AX.txt`. No bundle fallback.
- `human-input/`: parent operated the human form with the same external path, exact line / interval 0, Prepare, then labelled Command Return. Result is `prepared`, source `request`, captured 0 / pending 6 at form default z18 / 1024×768 / all modes. `human-input-AX.txt` retains the resulting task card and package source. Different camera settings explain the 6 versus 7 pending views.

The smoke inputs intentionally use the current repository package via an external path, not modified geometry. The retained request/result/geometry/index/plan files are byte copies from `/private/tmp/jtm-corner-repair-20261018/{input-smoke,missing-input,human-input}`. Absolute paths inside them describe the original run; copying them does not relocate or rerun the sessions. AX text is the observed accessibility state, not screenshot pixel evidence. No compact production data was edited by this interface work.

## 实际路径输入修复

原生输入曾把证据路径中的japan自动改成Japan；现关闭任务表单技术输入及reviewPaths的autocorrection/autocapitalization。最终增量build成功（literal-input-build.log），父会话实际键入原始小写japan路径并用常显⌃⌘S保存，review-notes.json中的完整路径与输入逐字一致，证据SHA仍匹配。原始AX及截图见literal-path-AX.txt / literal-path.png。这是一次路径字段观察，不是全输入法或无障碍矩阵。

此接口随后实际完成鳩原34视角候选采集，验证changed-own-geometry拒绝续跑及既有结果保护，并在正式display数据依赖相同后复用102张原图。实际几何修复和Main对照见仓库ordered-continuation的hokuriku-p1-complete/sharp-corner-repair-20261018/README.md；它与本页早先的三个零截图prepare输入检查分开记录。
