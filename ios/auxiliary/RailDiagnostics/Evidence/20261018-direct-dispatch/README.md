# Direct request dispatch: native observation (2026-10-18)

The parent operator opened `/private/tmp/jtm-miyazu-missing-20261018/request.json` in the latest Debug Rail Diagnostics. The explicit capture action started without another Run action and completed **28/28 views, 0 failed, 0 pending**. Saved `result.json` is `evidenceReady`; `run-status.json` is `evidenceReady` with `active: false`. The parent actually inspected the completed UI and saved [completed-ui.png](completed-ui.png).

[request.json](request.json), [result.json](result.json) and [run-status.json](run-status.json) are byte-for-byte copies of the completed session files, checked stable while copying. Their original absolute evidence paths remain intact; image receipts are retained in the original session rather than duplicated here.

- Request: `miyazu-missing-own-intervals`, own Miyazu intervals 3, 6 and 15; standard basemap + smooth, z17, 1600×1200.
- Process: **PID 52148**.
- Executable: `/private/tmp/jtm-rail-diagnostics/Build/Products/Debug-maccatalyst/RailDiagnostics.app/Contents/MacOS/RailDiagnostics`.
- Invocation: `A0B99B1B-9B1E-4639-B349-CC356793051A`.
- Completed status timestamp: `2026-10-18T22:18:48Z`.

The parent also ran one authorized `open -n` against that Debug app outside the restricted sandbox. It returned 0; the following `pgrep` observation found only PID 52148 for the same executable, with no second instance. The observed result is **single-process retention**, not a rejected-launch error. An earlier ordinary sandboxed `open` returned -10827; that restricted attempt is not the real single-instance outcome.

This verifies native direct dispatch and the observed same-executable single-process behavior for this run. It does not establish every Launch Services/app-location combination, geometry acceptance, own platform centres or Main production composition. Earlier valid/invalid/busy observations of the preview flow remain in `../20261018-hot-open/`; they are not relabelled as fresh direct-dispatch rejection tests. No performance claim follows. The parent retains the shared app lease; this documentation task did not operate the app or start another capture.
