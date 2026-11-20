#!/usr/bin/env bash
# Regression guards: one command, a few minutes. Run before every merge to main.
# See ios/VERIFICATION.md ("Regression guards") and docs/maintenance/2026-11-06-regression-guards.md.
# Runs every step even after a failure, prints per-step timings, exits non-zero if any step failed.
# JTM_NATIVE_GUARDS=1 also runs the native editor time-zone suites (simulator; required before
# merging changes to JourneyEditor/, RecordDate or region-clock code — see ios/VERIFICATION.md).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2

# Stamped, fast port fixtures that are green. Deliberately excluded:
#  - route-graph, route-station-candidates, route-section-solve, route-solver-core:
#    legacy coordinate-key solver fixtures pinned at cache version 25; the JS
#    reference now emits identity keys at version 28, so they are stale until
#    the user decides whether to regenerate or retire them.
#  - historical-routes: green but slow, so run by hand
#    (build-port-fixtures.mjs --check --only=historical-routes.json).
FIXTURES=(continuous-stroke playback stats station-display display-parts i18n
  dates family-windows grooming overlap-lanes route-hints station-visibility
  stations store-ops validation import operator-branding route-feature
  station-join-smoothing)

# One swift test run: the guards plus the Swift/JS parity suites.
# Excluded as slow: RailHistoryPackageTests (~15 min), JunctionApproachTests (~11 min).
SWIFT_FILTER='RegressionGuard|AnnotationDiff|GeometryZoomLevelsTests|OverlaySwapSequencerTests|OverlayInsertionPlanTests|MapLoadAhead|RideArrivalPlan|AddOnlyBatchLedger|GeometryFrameResidency|SpatialGrid|MarkerPassDebt|MarkerSettleTurn|BoundedLookupCache|StrokeStabilityLedger|MapBuildArea|MapRebuildPolicyTests|TrainPatternVariants|PlaybackParityTests|RouteGraphParityTests|SamplePrecomputeProvenanceTests|LocalizationParityTests|ContinuousStrokeParityTests|TravelDirectionTests|DirectionalAlignmentSelectionTests|StrokeBakeEquality|NetworkStrokeBake|StrokeProjectionParity|StrokeBakeMapKitReference|RailStrokeTokens|GCJ02Tests|RailPack|RailTopology|RideRecordFile|RideKey|TopologyShadowComparison|ScreenPolylineThinning|RegressionGuardBinaryHeap|RegressionGuardCivilDate|RegressionGuardDisplayClosure|RegressionGuardSurveyOncePerStroke'

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
step "raildiagnostics membership" bash "$ROOT/ios/tools/check-raildiagnostics-membership.sh"
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
# Rail pack cache key and freshness check (docs/maintenance/2026-11-12-prebuilt-rail-map-pack.md, section 6).
step "rail pack inputs tests" python3 -I "$ROOT/ios/tools/tests/test_rail_pack_inputs.py"
# Rail pack size guards: the bundle checker (30,000,000 bytes) and the committed budgets. The real bake
# guards (per-pack bytes, per-level vertices, phone and pad windows) run in bake-rail-packs.sh; the fixture
# ones run in the railbake package tests below.
step "rail pack budget tests" python3 -I "$ROOT/ios/tools/tests/test_check_rail_pack_budget.py"
# The bake script stages packs and swaps them in only after the checks pass (stale packs removed, over budget changes nothing).
step "rail pack bake swap tests" python3 -I "$ROOT/ios/tools/tests/test_bake_rail_packs.py"
# Corridors split across operators share one visibility tier (display-network visibility groups).
# The built manifest is the data the app ships, so the guard can check it:
#   JTM_DISPLAY_NETWORK_DIR=<built rail-display-network dir>  checks that build;
#   JTM_GUARD_BUILD_NETWORK=1  builds one from this tree first (minutes, scratch dir);
# neither set: only the builder-function tests run (the manifest test skips, and says so).
corridor_net="${JTM_DISPLAY_NETWORK_DIR:-}"
if [ -z "$corridor_net" ] && [ "${JTM_GUARD_BUILD_NETWORK:-0}" = 1 ]; then
  corridor_tmp="$(mktemp -d)"
  corridor_net="$corridor_tmp/rail-display-network"
  step "build display network (corridor guard)" python3 -I "$ROOT/app/scripts/railway/build-display-network.py" \
    --rail-dir "$ROOT/app/public/rail" --output "$corridor_net" --history-dir "$ROOT/app/data" \
    --junctions "$ROOT/app/data/physical-rail-junctions.json" \
    --through-services "$ROOT/ios/RailKit/Sources/RailCore/Resources/japan-through-services.json" \
    --registry-dir "$ROOT/app/data/registry-bundle"
fi
step "corridor visibility tiers" env JTM_DISPLAY_NETWORK_DIR="$corridor_net" python3 -I "$ROOT/app/scripts/railway/tests/test_corridor_visibility.py"
[ -z "${corridor_tmp:-}" ] || rm -rf "$corridor_tmp"

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

# The pack baker (piece cutter, assembler, RailBake): its own package, host only.
bake_cmd=(swift test --package-path "$ROOT/ios/tools/railbake" --scratch-path "${JTM_RAILBAKE_SCRATCH:-/private/tmp/jtm-railbake}")
if [ -f /private/tmp/jtm-heavy-job-run.sh ]; then
  step "railbake package tests" bash /private/tmp/jtm-heavy-job-run.sh "${bake_cmd[@]}"
else
  step "railbake package tests" "${bake_cmd[@]}"
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
