#!/usr/bin/env bash
# Regression guards: one command, a few minutes. Run before every merge to main.
# See ios/VERIFICATION.md ("Regression guards") and docs/maintenance/2026-11-06-regression-guards.md.
# Runs every step even after a failure, prints per-step timings, exits non-zero if any step failed.
# JTM_NATIVE_GUARDS=1 also runs the native editor time-zone suites (simulator; required before
# merging changes to JourneyEditor/, RecordDate or region-clock code — see ios/VERIFICATION.md).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2

# Stamped, fast port fixtures that are green. Deliberately excluded: route-graph,
# route-station-candidates, route-section-solve, route-solver-core, import,
# station-join-smoothing (known red), historical-routes (slow), operator-branding
# and route-feature (red today).
FIXTURES=(continuous-stroke playback stats station-display display-parts i18n
  dates family-windows grooming overlap-lanes route-hints station-visibility
  stations store-ops validation)

# One swift test run: the guards plus the Swift/JS parity suites.
# Excluded as slow: RailHistoryPackageTests (~15 min), JunctionApproachTests (~11 min).
SWIFT_FILTER='RegressionGuard|AnnotationDiff|GeometryZoomLevelsTests|OverlaySwapSequencerTests|MapLoadAhead|RideArrivalPlan|AddOnlyBatchLedger|GeometryFrameResidency|SpatialGrid|MarkerPassDebt|StrokeStabilityLedger|MapBuildArea|MapRebuildPolicyTests|TrainPatternVariants|PlaybackParityTests|RouteGraphParityTests|SamplePrecomputeProvenanceTests|LocalizationParityTests|ContinuousStrokeParityTests|TravelDirectionTests|DirectionalAlignmentSelectionTests'

names=(); times=(); results=(); failed=0

step() { # step <label> <command...>
  local label="$1"; shift
  echo "==> $label"
  local start=$SECONDS rc=0
  "$@" || rc=$?
  local dt=$((SECONDS - start))
  names+=("$label"); times+=("$dt"); results+=("$([ "$rc" -eq 0 ] && echo ok || echo FAIL)")
  [ "$rc" -eq 0 ] || failed=1
  return 0
}

step "ui-test identifiers" bash "$ROOT/ios/tools/check-ui-test-identifiers.sh"
step "ui tokens" bash "$ROOT/ios/tools/check-ui-tokens.sh"
step "string keys" bash "$ROOT/ios/tools/check-string-keys.sh"
# Shinkansen stop-pattern database: fails only on the new keys' rules (allStations,
# variants, coupled, source files) until the data branches that correct the existing
# stop lists have landed. Then add --strict here so the base-data rules fail too.
# See ios/VERIFICATION.md ("Shinkansen stop-pattern database").
step "shinkansen patterns (new-key rules)" python3 -I "$ROOT/ios/tools/build-shinkansen-patterns.py" --check --strict
step "shinkansen patterns tests" python3 -I "$ROOT/ios/tools/tests/test_build_shinkansen_patterns.py"
# Train database: no copied timetable times anywhere (user decision 2026-11-11), and the
# confirmed corrections are reproducible from the tracked baseline (re-running changes nothing).
step "timetable stops only" python3 -I "$ROOT/ios/tools/check-timetable-stops-only.py"
step "train database corrections tests" python3 -I "$ROOT/ios/tools/tests/test_apply_train_database_corrections.py"

for f in "${FIXTURES[@]}"; do
  step "fixture $f" node "$ROOT/app/scripts/build/build-port-fixtures.mjs" --check "--only=$f.json"
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift_cmd=(swift test --package-path "$ROOT/ios/RailKit" --filter "$SWIFT_FILTER")
if [ -f /private/tmp/jtm-heavy-job-run.sh ]; then
  step "swift guards + parity" bash /private/tmp/jtm-heavy-job-run.sh "${swift_cmd[@]}"
else
  step "swift guards + parity" "${swift_cmd[@]}"
fi

if [ "${JTM_NATIVE_GUARDS:-0}" = 1 ]; then
  # The editor's draft model lives in the app, so these run on the simulator.
  native_cmd=(xcodebuild test -project "$ROOT/ios/RailMap.xcodeproj" -scheme RailMapTests
    -destination "${JTM_SIM_DESTINATION:-platform=iOS Simulator,id=0DBE2488-0BEB-4932-9B55-091B3CC793B6}"
    -only-testing:RailMapTests/TripDraftDeviceZoneTests
    -only-testing:RailMapTests/TripDraftStoredFormatsTests)
  if [ -f /private/tmp/jtm-heavy-job-run.sh ]; then
    step "native editor time-zone suites" bash /private/tmp/jtm-heavy-job-run.sh "${native_cmd[@]}"
  else
    step "native editor time-zone suites" "${native_cmd[@]}"
  fi
fi

echo
echo "Regression guard summary"
total=0
for i in "${!names[@]}"; do
  printf '  %-4s %5ss  %s\n' "${results[$i]}" "${times[$i]}" "${names[$i]}"
  total=$((total + times[i]))
done
echo "  total ${total}s"
if [ "$failed" -ne 0 ]; then echo "RESULT: FAILED (fix commands are printed above each failure)"; exit 1; fi
echo "RESULT: ok"
