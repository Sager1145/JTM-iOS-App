# Yamasaki bounded display repair — 2026-10-12

Root's actual [GSI aerial](regional-aerial/yamasaki-z18.png) at35.237028,139.114916, reviewed directly here, separates the narrow railway grade southeast/below the source crosshair from Route1 and neighboring roads. This corroborates the previously identified same passenger leg of OSM way235606888; imagery date remains unavailable. It supports the local display repair, not a survey or whole-line acceptance.

## Change and ownership

Added `app/scripts/railway/repair-hakone-yamasaki-display.mjs`, `hakone-yamasaki-display-evidence.json` and focused regression `tests/hakone-yamasaki-display.test.mjs`. This outer stage leaves earlier strict passenger-station and Hakone corridor stages unchanged, replays them on their original owned inputs and rejects unreviewed current Hakone dependencies. No Kisuki file was edited.

Only Hakone display interval3 changes:69 points, exact selected way235606888 supports17–24, transition supports8–34 blended from corresponding canonical-source projections through an along-track quintic zero-slope taper. Unchanged physical prefix includes source index13; unchanged suffix starts35. Boundary samples project onto the original tangent edges, avoiding perpendicular cross-track seam connectors. Station endpoints/display anchors, physical segments/mileage, source station IDs/coordinates, intervals4–9, reversal tails and independent Deyama/Kami/Ohiradai branches remain unchanged.

Only native Hakone main part1 changes its geometry/derived rows and measured extent,8272.770521358394→8268.748702948702m. Native parts0/2/3/4/5/6, their extents and all existing follow/family/loop/exclusion/fork references are preserved. Display extent is not physical mileage.

Applied through fresh snapshots of the current package, lanes and established four station-name input-reference files. Prepared temporary outputs, reread all exact input snapshots immediately before apply and atomically renamed each changed file. Current concurrent Kisuki Minami metadata/rows and unrelated lines remain preserved by the outer-stage splice. No build, UI, native capture, commit or push by this worker.

## Focused evidence

- Three new behavior tests first failed on missing interval3 correction/stale native row. After implementation, all five new cases and seven existing Hakone passenger-corridor cases pass: `node --test app/scripts/railway/tests/hakone-yamasaki-display.test.mjs app/scripts/railway/tests/hakone-passenger-corridor.test.mjs`,12tests,0failures.
- Regression checks exact identified supports, unchanged physical/other intervals/stems, guard-tangent collinearity, source/node/service rejection, unknown measured-reference rejection, unrelated rows/metadata preservation, native rows and idempotence.
- Production JS RailStroke invoked at nominal ~1m/point with lane0 and minimum rounding. Diagnostic core-support distance to final ink segments was at most0.038m; the regression requires<1m. Initial test compared only final sample vertices, which falsely treated sampling gaps as bypasses; inspection established the drawn segments still pass the supports, and the regression now measures segment distance. This is a production-JS scoped geometric check, not a native pixel claim.
- Candidate and `--apply` exited0. Fresh post-apply targeted query confirmed exact package replay, exact lane replay, physical/protected fields unchanged and both Kisuki Minami and Hakone Yamasaki metadata present.

## Remaining result boundary

Root owns the combined incremental build, native after capture and main-product review. Current saved before-native Hakone images retain the old dependency and must not be relabelled after evidence. The bounded source repair is applied and replayable; native Yamasaki placement, all59-view geographic pass, station circles/popups and main-map composition remain unaccepted until the relevant root observations.
