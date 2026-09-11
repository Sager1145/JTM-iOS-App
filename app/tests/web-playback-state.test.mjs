import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";

import {
  evaluateAppScripts,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

// Harness copied from tests/web-lifecycle-races.test.mjs (`playbackHarness`),
// per the brief: reuse the existing setup pattern rather than inventing a new
// one. Generalized to accept a train list and to record RailMap.setSelected
// calls, which the existing harness discards.
function playbackHarness({ trains, selectedTrainId = trains[0]?.id ?? null } = {}) {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const moveend = [];
  const selectedCalls = [];
  const handler = {
    enabled: true,
    isEnabled() {
      return this.enabled;
    },
    enable() {
      this.enabled = true;
    },
    disable() {
      this.enabled = false;
    },
  };
  const map = {
    easeTo() {},
    jumpTo() {},
    getCenter: () => ({ lng: 0, lat: 0 }),
    getZoom: () => 10,
    getContainer: () => ({ clientWidth: 1000, clientHeight: 700 }),
    once(event, listener) {
      assert.equal(event, "moveend");
      moveend.push(listener);
    },
  };
  for (const name of [
    "dragPan",
    "scrollZoom",
    "boxZoom",
    "dragRotate",
    "keyboard",
    "doubleClickZoom",
    "touchZoomRotate",
    "touchPitch",
  ]) map[name] = Object.create(handler);

  let rafRequests = 0;
  context.__stateMap = map;
  context.__stateTrainStore = { trains };
  context.__stateSelectedTrainId = selectedTrainId;
  context.__stateSelectedCalls = selectedCalls;
  context.requestAnimationFrame = () => {
    rafRequests += 1;
    return rafRequests;
  };
  context.cancelAnimationFrame = () => {};
  vm.runInContext(
    `
      map = __stateMap;
      trainStore = { schema_version: SCHEMA_VERSION, trains: __stateTrainStore.trains };
      selectedTrainId = __stateSelectedTrainId;
      focusedTrainId = null;
      getTrainRouteTemplateKey = (train) => train.id + "-template";
      getMatchedRouteFeatures = () => [{
        type: "Feature",
        properties: { ride_segment: true, segment_index: 0 },
        geometry: { type: "LineString", coordinates: [[0, 0], [0.01, 0]] },
      }];
      getVisibleListTrains = () => __stateTrainStore.trains;
      trainPassesListFilter = () => true;
      fitTrainsBounds = () => {};
      updateEndpointLabels = () => {};
      Object.assign(RailMap, {
        _rideStrokeGeneration: 0,
        setSelected(id) { __stateSelectedCalls.push(id); },
        setPlaybackTrail() {},
        setPlaybackProgress() {},
        setPlaybackStations() {},
        setPlaybackStationIndex() {},
        setPlaybackHead() {},
        clearPlayback() {},
      });
    `,
    context,
  );

  return {
    context,
    emitMoveend() {
      const listeners = moveend.splice(0);
      listeners.forEach((listener) => listener());
    },
    rafRequests: () => rafRequests,
    selectedCalls,
    run(code) {
      return vm.runInContext(code, context);
    },
  };
}

function makeTrain(id, number, color) {
  return {
    id,
    number,
    date: "2026-09-07",
    origin: "A",
    destination: "B",
    visible: true,
    style: color ? { color } : undefined,
    stops: [
      { name: "A", stop_type: "origin", ride_segment: true },
      { name: "B", stop_type: "destination", ride_segment: false },
    ],
  };
}

// Drive a single-train queue all the way from idle to "playing" (start,
// begin, then deliver the intro moveend synchronously).
function armAndPlay(h) {
  assert.equal(h.run("Playback.start()"), true);
  h.run("Playback.begin()");
  h.emitMoveend();
}

// ── 1. setSpeed rounding / clamping ────────────────────────────────────────

test("setSpeed rounds to TUNE.SPEED_STEP and clamps to [SPEED_MIN, SPEED_MAX]", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const setSpeed = (v) => vm.runInContext(`Playback.setSpeed(${JSON.stringify(v)})`, context);

  assert.equal(setSpeed(0.1), 0.5); // below SPEED_MIN clamps up
  assert.equal(setSpeed(9), 4); // above SPEED_MAX clamps down
  // Source rule: Math.round(raw / step) * step, step = 0.25.
  // 1.13 / 0.25 = 4.52 -> rounds to 5 -> 5 * 0.25 = 1.25.
  assert.equal(setSpeed(1.13), 1.25);
  // NaN / non-number input: `Number(value) || 1` falls back to 1, so a bad
  // input never throws and always leaves a finite speed.
  assert.equal(setSpeed(NaN), 1);
  assert.equal(setSpeed("not-a-number"), 1);
  assert.ok(Number.isFinite(vm.runInContext("Playback.setSpeed(NaN)", context)));
});

// ── 2. phase transitions ───────────────────────────────────────────────────

test("phase transitions through the documented lifecycle", () => {
  const h = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  const phase = () => h.run("Playback.phase()");

  assert.equal(phase(), "idle");
  assert.equal(h.run("Playback.start()"), true);
  assert.equal(phase(), "armed");
  h.run("Playback.begin()");
  assert.equal(phase(), "transitioning");
  h.emitMoveend();
  assert.equal(phase(), "playing");
  h.run("Playback.pause()");
  assert.equal(phase(), "paused");
  h.run("Playback.resume()");
  assert.equal(phase(), "playing");
  h.run("Playback.pause()");
  assert.equal(phase(), "paused");
  h.run("Playback.toggle()");
  assert.equal(phase(), "playing");
  h.run("Playback.stop()");
  assert.equal(phase(), "idle");
  assert.equal(h.run("Playback.isActive()"), false);
});

test("start() while playing returns false and keeps phase", () => {
  const h = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  armAndPlay(h);
  assert.equal(h.run("Playback.phase()"), "playing");
  assert.equal(h.run("Playback.start()"), false);
  assert.equal(h.run("Playback.phase()"), "playing");
});

test("pause() while idle is a no-op", () => {
  const h = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  assert.equal(h.run("Playback.phase()"), "idle");
  h.run("Playback.pause()");
  assert.equal(h.run("Playback.phase()"), "idle");
});

test("resume() while playing is a no-op", () => {
  const h = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  armAndPlay(h);
  assert.equal(h.run("Playback.phase()"), "playing");
  h.run("Playback.resume()");
  assert.equal(h.run("Playback.phase()"), "playing");
});

// ── 3. skip() ───────────────────────────────────────────────────────────

test("skip() is a no-op in idle, and clamps within a 2-train queue", () => {
  // I18N.t is not backed by the real string catalog in this sandbox, so
  // captionState().title is just the untranslated key ("video.caption") and
  // cannot distinguish which train is current. Use each train's distinct
  // style.color (carried straight into captionState().color) instead.
  const h = playbackHarness({
    trains: [
      makeTrain("t1", "T1", "#111111"),
      makeTrain("t2", "T2", "#222222"),
    ],
    selectedTrainId: null,
  });

  // idle: no-op, no queue to move through.
  h.run("Playback.skip(1)");
  assert.equal(h.run("Playback.phase()"), "idle");

  armAndPlay(h);
  const color = () => h.run("Playback.captionState().color");
  assert.equal(color(), "#111111");

  h.run("Playback.skip(1)");
  assert.equal(color(), "#222222");

  // Already at the last train: skip(+1) again must clamp, not throw or end.
  h.run("Playback.skip(1)");
  assert.equal(color(), "#222222");
  assert.notEqual(h.run("Playback.phase()"), "ended");

  h.run("Playback.skip(-1)");
  assert.equal(color(), "#111111");
  // skip(-1) at index 0 stays at 0.
  h.run("Playback.skip(-1)");
  assert.equal(color(), "#111111");
});

// ── 4. notifyExternalRender() ──────────────────────────────────────────────

test("notifyExternalRender stops playback and fires onFinish(aborted); is a no-op while idle", () => {
  const h = playbackHarness({ trains: [makeTrain("t1", "T1")] });

  // Idle: no-op, no listener call.
  const idleEvents = [];
  h.context.__idleEvents = idleEvents;
  h.run("Playback.onFinish((e) => __idleEvents.push(e))");
  h.run("Playback.notifyExternalRender()");
  assert.equal(idleEvents.length, 0);
  assert.equal(h.run("Playback.phase()"), "idle");

  armAndPlay(h);
  const events = [];
  h.context.__events = events;
  h.run("Playback.onFinish((e) => __events.push(e))");
  h.run("Playback.notifyExternalRender()");
  assert.equal(h.run("Playback.phase()"), "idle");
  assert.equal(events.length, 1);
  assert.equal(events[0].aborted, true);
});

// ── 5. prepare() ────────────────────────────────────────────────────────

test("prepare() reports an empty queue, and a real queue's trains/seconds", () => {
  const empty = playbackHarness({ trains: [], selectedTrainId: null });
  const emptyReport = empty.run("Playback.prepare()");
  assert.equal(emptyReport.trains, 0);
  assert.equal(emptyReport.skipped, 0);
  assert.equal(empty.run("Playback.start()"), false);
  assert.equal(empty.run("Playback.phase()"), "idle");

  const h = playbackHarness({
    trains: [makeTrain("t1", "T1"), makeTrain("t2", "T2")],
    selectedTrainId: null,
  });
  const report = h.run("Playback.prepare()");
  assert.equal(report.trains, 2);
  assert.ok(Number.isFinite(report.seconds));
  assert.ok(report.seconds > 0);
});

// ── 6. stop({restoreSelection}) ────────────────────────────────────────────

test("stop({restoreSelection:false}) skips restoring the pre-playback selection; plain stop() restores it", () => {
  const h1 = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  armAndPlay(h1);
  const before1 = h1.selectedCalls.length;
  h1.run("Playback.stop()");
  const restoredCalls = h1.selectedCalls.slice(before1);
  assert.ok(
    restoredCalls.includes("t1"),
    `expected plain stop() to restore selection "t1", got ${JSON.stringify(restoredCalls)}`,
  );

  const h2 = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  armAndPlay(h2);
  const before2 = h2.selectedCalls.length;
  h2.run("Playback.stop({restoreSelection:false})");
  const skippedCalls = h2.selectedCalls.slice(before2);
  assert.ok(
    !skippedCalls.includes("t1"),
    `expected stop({restoreSelection:false}) not to restore "t1", got ${JSON.stringify(skippedCalls)}`,
  );
});

// ── 7. isDrivingCamera() ────────────────────────────────────────────────

test("isDrivingCamera() is true only in playing/transitioning", () => {
  const h = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  const driving = () => h.run("Playback.isDrivingCamera()");

  assert.equal(driving(), false); // idle
  h.run("Playback.start()");
  assert.equal(driving(), false); // armed
  h.run("Playback.begin()");
  assert.equal(driving(), true); // transitioning
  h.emitMoveend();
  assert.equal(driving(), true); // playing
  h.run("Playback.pause()");
  assert.equal(driving(), false); // paused
  h.run("Playback.resume()");
  assert.equal(driving(), true); // playing again
  h.run("Playback.stop()");
  assert.equal(driving(), false); // idle
});

// ── 8. full-run integration ─────────────────────────────────────────────

// Steps the module's own frame() clock manually instead of relying on the
// harness's counting-only requestAnimationFrame stub (which never invokes
// its callback). frame()'s dt is `Math.min(TUNE.MAX_FRAME_S, (now -
// lastFrameMs) / 1000)`, so a fixed 80ms step per tick (< the 100ms clamp)
// always advances exactly one clamped tick regardless of how large the
// jump actually is — bigger steps would just be wasted, not wrong. Real
// setTimeout is left untouched: armTimer/transitionTimer/finishTimer (the
// autoBegin delay, the terminus hold between trains, and the finale hold)
// all use it, so the driver awaits a real tick whenever no frame is
// in flight, letting those timers fire on Node's own event loop.
function driveFrames(h, { maxSteps = 20000, onStep } = {}) {
  let pendingFrame = null;
  let fakeNow = 0;
  h.context.performance = { now: () => fakeNow };
  h.context.requestAnimationFrame = (cb) => {
    pendingFrame = cb;
    return 1;
  };
  h.context.cancelAnimationFrame = () => {
    pendingFrame = null;
  };
  const phase = () => h.run("Playback.phase()");
  const phases = [phase()];
  const record = () => {
    const p = phase();
    if (phases[phases.length - 1] !== p) phases.push(p);
    onStep?.(p);
    return p;
  };
  return {
    phases,
    hasPendingFrame: () => pendingFrame != null,
    sample: record,
    async runToEnded() {
      for (let i = 0; i < maxSteps; i++) {
        if (record() === "ended") return phases;
        if (pendingFrame) {
          const cb = pendingFrame;
          pendingFrame = null;
          fakeNow += 80; // <= TUNE.MAX_FRAME_S * 1000
          cb(fakeNow);
        } else {
          // Nothing scheduled on our fake rAF: something is waiting on a
          // real setTimeout (terminus hold) instead. Give the event loop a
          // turn so that timer can fire.
          await new Promise((resolve) => setTimeout(resolve, 4));
        }
      }
      throw new Error(
        `never reached 'ended' after ${maxSteps} iterations; phases so far: ${JSON.stringify(phases)}`,
      );
    },
  };
}

test("a full run walks armed -> transitioning/playing -> second train -> ended -> idle and finishes unaborted", async () => {
  const h = playbackHarness({
    trains: [
      makeTrain("t1", "T1", "#111111"),
      makeTrain("t2", "T2", "#222222"),
    ],
    selectedTrainId: null, // no selection -> full 2-train queue, not just t1
  });
  const finishes = [];
  h.context.__finishes = finishes;
  h.run("Playback.onFinish((e) => __finishes.push(e))");
  const clearCalls = [];
  h.context.__clearCalls = clearCalls;
  h.run("RailMap.clearPlayback = () => { __clearCalls.push(true); };");
  // The harness's map stub has no fitBounds; smoothFitBounds's finale-fit
  // path needs it.
  h.run("map.fitBounds = () => {};");

  // Install the fake rAF/clock BEFORE anything that can call
  // requestAnimationFrame — begin()'s intro moveend hand-off requests the
  // very first frame synchronously, and a driver installed any later would
  // miss it, leaving the run stalled with no pending frame to step.
  const colorsSeen = new Set();
  const driver = driveFrames(h, {
    onStep: () => colorsSeen.add(h.run("Playback.captionState().color")),
  });

  assert.equal(h.run("Playback.start({autoBegin:true})"), true);
  driver.sample();
  assert.equal(h.run("Playback.phase()"), "armed");
  // Drive begin() ourselves instead of waiting on the real armTimer
  // (overview + 120ms) that autoBegin scheduled. That timer is still
  // pending and fires later as a harmless no-op (begin() bails once phase
  // is no longer "armed").
  h.run("Playback.begin()");
  driver.sample();
  assert.equal(h.run("Playback.phase()"), "transitioning");
  h.emitMoveend(); // land the intro camera move -> starts the clock
  driver.sample();

  const phases = await driver.runToEnded();

  assert.equal(h.run("Playback.phase()"), "ended");
  assert.ok(phases.includes("armed"), `expected an "armed" phase, got ${JSON.stringify(phases)}`);
  assert.ok(phases.includes("playing"), `expected a "playing" phase, got ${JSON.stringify(phases)}`);
  assert.equal(phases[phases.length - 1], "ended");
  // Both trains' caption colors were seen at some point during the run.
  // (The default DEFAULT_TRAIN_COLOR also shows up, sampled while "armed"
  // and before beginTrain() has compiled a path yet — that's expected, not
  // a missed train.)
  assert.ok(colorsSeen.has("#111111"), `expected to see train 1's color, saw ${[...colorsSeen]}`);
  assert.ok(colorsSeen.has("#222222"), `expected to see train 2's color, saw ${[...colorsSeen]}`);
  // No frame is left in flight once the run has ended.
  assert.equal(driver.hasPendingFrame(), false);

  // isActive() already excludes "ended" (see app-playback.js's isActive
  // doc comment), so it is false the instant the run reaches "ended" —
  // well before the finale hold below elapses.
  assert.equal(h.run("Playback.isActive()"), false);

  // Advance past the finale fit + its hold so the finishTimer set in
  // finish() fires and reports the run as done.
  await new Promise((resolve) => setTimeout(resolve, 2600));

  assert.equal(finishes.length, 1);
  // finishes[0] is a vm-realm object, so assert.deepEqual (cross-realm
  // constructor mismatch) would false-fail here; compare structurally.
  assert.equal(finishes[0].aborted, false);
  assert.deepEqual(Object.keys(finishes[0]), ["aborted"]);
  // Surprising: a natural finish never calls Playback.stop() itself (only
  // an external stop()/notifyExternalRender()/UI close does), so
  // RailMap.clearPlayback() is NOT invoked and phase stays "ended" rather
  // than moving to "idle" — nothing in app-playback.js's finish()/
  // announceFinished() path calls stop(). The title's "-> idle" describes
  // isActive() being false, not an actual phase transition.
  assert.equal(clearCalls.length, 0);
  assert.equal(h.run("Playback.phase()"), "ended");
});

test("finale after skipping every train fits nothing degenerate", async () => {
  const h = playbackHarness({
    trains: [
      makeTrain("t1", "T1", "#111111"),
      makeTrain("t2", "T2", "#222222"),
    ],
    selectedTrainId: null, // no selection -> full 2-train queue, not just t1
  });
  h.run("map.fitBounds = () => {};");

  // Install the fake rAF/clock before skip() — while still "armed", skip()
  // calls beginTrain() -> runClock() synchronously, which requests the
  // first frame immediately (no moveend to wait on).
  const driver = driveFrames(h);

  assert.equal(h.run("Playback.start()"), true);
  assert.equal(h.run("Playback.phase()"), "armed");
  // Skip straight to the last train while still armed: skip() calls
  // beginTrain() non-intro, which (per beginTrain's mid-queue branch) runs
  // the clock immediately rather than waiting on a moveend.
  h.run("Playback.skip(1)");
  assert.equal(h.run("Playback.captionState().color"), "#222222");

  await driver.runToEnded();

  assert.equal(h.run("Playback.phase()"), "ended");
  // The skipped-to train did run to completion (skip() while armed starts
  // its clock, it isn't dropped), so trailDone/finaleFit had a real,
  // non-degenerate set of points to fit — this asserts that path neither
  // threw nor left the run stuck.
  assert.equal(driver.hasPendingFrame(), false);
});

// ── 9. regressions from the "ended" re-arm / pause-in-hold / recompile diff ──

// Mirrors driveFrames's fake rAF/clock, but hands control back to the caller
// one tick at a time instead of looping to "ended" itself — for tests that
// need to intervene mid-run (pause during the terminus hold, bump the stroke
// generation) rather than just observe the final state.
function frameStepper(h) {
  let pendingFrame = null;
  let fakeNow = 0;
  h.context.performance = { now: () => fakeNow };
  h.context.requestAnimationFrame = (cb) => {
    pendingFrame = cb;
    return 1;
  };
  h.context.cancelAnimationFrame = () => {
    pendingFrame = null;
  };
  return {
    async until(predicate, maxSteps = 20000) {
      for (let i = 0; i < maxSteps; i++) {
        if (predicate()) return;
        if (pendingFrame) {
          const cb = pendingFrame;
          pendingFrame = null;
          fakeNow += 80; // <= TUNE.MAX_FRAME_S * 1000, see driveFrames above
          cb(fakeNow);
        } else {
          // Nothing scheduled on our fake rAF: something is waiting on a
          // real setTimeout (terminus hold) instead.
          await new Promise((resolve) => setTimeout(resolve, 4));
        }
      }
      throw new Error(`predicate never satisfied after ${maxSteps} iterations`);
    },
    step() {
      if (!pendingFrame) return false;
      const cb = pendingFrame;
      pendingFrame = null;
      fakeNow += 80;
      cb(fakeNow);
      return true;
    },
  };
}

test("re-arming from ended inside the closing hold settles the finished run once", async () => {
  const h = playbackHarness({
    trains: [
      makeTrain("t1", "T1", "#111111"),
      makeTrain("t2", "T2", "#222222"),
    ],
    selectedTrainId: null,
  });
  h.run("map.fitBounds = () => {};");
  const finishes = [];
  h.context.__finishes = finishes;
  h.run("Playback.onFinish((e) => __finishes.push(e))");
  const clearCalls = [];
  h.context.__clearCalls = clearCalls;
  h.run("RailMap.clearPlayback = () => { __clearCalls.push(true); };");

  const driver = driveFrames(h);
  assert.equal(h.run("Playback.start({autoBegin:true})"), true);
  h.run("Playback.begin()");
  h.emitMoveend();
  await driver.runToEnded();
  assert.equal(h.run("Playback.phase()"), "ended");
  assert.equal(finishes.length, 0);

  // Re-arm BEFORE the closing hold (TUNE.FINALE_MS + TUNE.FINALE_HOLD_MS)
  // elapses: start()'s "ended" branch calls stop({keepBar:true}) first,
  // which should settle the finished run (announce it, clear the map layer)
  // exactly once before re-arming over it.
  assert.equal(h.run("Playback.start()"), true);
  assert.equal(finishes.length, 1);
  assert.equal(finishes[0].aborted, false);
  assert.equal(clearCalls.length, 1);
  assert.equal(h.run("Playback.phase()"), "armed");

  // Wait past where the original finishTimer would have fired if it had
  // survived the re-arm — it must not have, or this fires a second,
  // stale completion.
  const hold = h.run("Playback.TUNE.FINALE_MS + Playback.TUNE.FINALE_HOLD_MS");
  await new Promise((resolve) => setTimeout(resolve, hold + 50));
  assert.equal(
    finishes.length,
    1,
    "a stale finishTimer from the settled run must not announce again",
  );
  assert.equal(h.run("Playback.phase()"), "armed");
  // The queue itself is intact (re-arm did not drop it): prepare() still
  // reports both trains.
  const report = h.run("Playback.prepare()");
  assert.equal(report.trains, 2);
});

test("stop after the hold elapsed announces nothing more", async () => {
  // Two trains, like the full-run test above — NOT a single-train queue.
  // A single-train queue leaves beginTrain()'s intro safety-net timer
  // (`transitionTimer = setTimeout(runClock, duration + 260)`, ~1160ms with
  // TUNE.INTRO_MS=900) live: nothing ever bumps transitionToken again to
  // invalidate it (a second train's beginTrain() does), so ~1160ms after the
  // run starts it stray-fires runClock() and snaps phase from "ended" back
  // to "playing" — which then makes this test's own stop() call announce
  // a spurious {aborted:true} on top of finish()'s own {aborted:false}.
  // That looks like a real, pre-existing latent bug independent of this
  // diff (worth flagging to the orchestrator), but it is not what this test
  // is checking, so sidestep it here the same way the full-run test does.
  const h = playbackHarness({
    trains: [
      makeTrain("t1", "T1", "#111111"),
      makeTrain("t2", "T2", "#222222"),
    ],
    selectedTrainId: null,
  });
  h.run("map.fitBounds = () => {};");
  const finishes = [];
  h.context.__finishes = finishes;
  h.run("Playback.onFinish((e) => __finishes.push(e))");

  const driver = driveFrames(h);
  assert.equal(h.run("Playback.start({autoBegin:true})"), true);
  h.run("Playback.begin()");
  h.emitMoveend();
  await driver.runToEnded();
  assert.equal(h.run("Playback.phase()"), "ended");

  const hold = h.run("Playback.TUNE.FINALE_MS + Playback.TUNE.FINALE_HOLD_MS");
  await new Promise((resolve) => setTimeout(resolve, hold + 50));
  assert.equal(finishes.length, 1);

  h.run("Playback.stop()");
  assert.equal(
    finishes.length,
    1,
    "stop() after finish()'s own timer already announced must not announce again",
  );
  assert.equal(h.run("Playback.phase()"), "idle");
});

test("the intro safety net cannot restart a run that already finished", async () => {
  // Single-train queue on purpose (see the comment in "stop after the hold
  // elapsed announces nothing more" above): this is exactly the shape that
  // leaves beginTrain()'s intro moveend safety net
  // (`transitionTimer = setTimeout(runClock, TUNE.INTRO_MS + 260)`) live with
  // nothing to invalidate it via a second train's beginTrain(). Before the
  // beginTrain() fix (runClock's once-only `handed` guard clearing
  // transitionTimer), that stale timer fired after finish() and snapped
  // phase from "ended" back to "playing".
  const h = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  h.run("map.fitBounds = () => {};");
  const finishes = [];
  h.context.__finishes = finishes;
  h.run("Playback.onFinish((e) => __finishes.push(e))");
  const trailCalls = [];
  h.context.__trailCalls = trailCalls;
  h.run(`
    RailMap.setPlaybackTrail = (done, runs, color) => {
      __trailCalls.push(done.length);
    };
  `);

  const driver = driveFrames(h);
  assert.equal(h.run("Playback.start({autoBegin:true})"), true);
  h.run("Playback.begin()");
  h.emitMoveend();
  await driver.runToEnded();
  assert.equal(h.run("Playback.phase()"), "ended");
  assert.equal(finishes.length, 0);

  const trailCallsAtEnded = trailCalls.length;

  // Wait past where the intro safety net's stale transitionTimer
  // (TUNE.INTRO_MS + 260, ~1160ms) would have fired if the fix hadn't
  // cleared it, with margin.
  const introSafetyNet = h.run("Playback.TUNE.INTRO_MS + 260");
  await new Promise((resolve) => setTimeout(resolve, introSafetyNet + 240));
  assert.equal(h.run("Playback.phase()"), "ended");
  assert.equal(finishes.length, 0, "finish()'s own timer hasn't elapsed yet");
  assert.equal(
    trailCalls.length,
    trailCallsAtEnded,
    "no stray runClock() should have produced a new setPlaybackTrail call",
  );

  // Now wait past finish()'s own hold (FINALE_MS + FINALE_HOLD_MS) so the
  // real completion announces exactly once.
  const hold = h.run("Playback.TUNE.FINALE_MS + Playback.TUNE.FINALE_HOLD_MS");
  await new Promise((resolve) => setTimeout(resolve, hold + 50));
  assert.equal(finishes.length, 1);
  assert.equal(finishes[0].aborted, false);
  assert.equal(h.run("Playback.phase()"), "ended");
});

test("external render at ended still counts as a completion, not an abort", async () => {
  const h = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  h.run("map.fitBounds = () => {};");
  const finishes = [];
  h.context.__finishes = finishes;
  h.run("Playback.onFinish((e) => __finishes.push(e))");

  const driver = driveFrames(h);
  assert.equal(h.run("Playback.start({autoBegin:true})"), true);
  h.run("Playback.begin()");
  h.emitMoveend();
  await driver.runToEnded();
  assert.equal(h.run("Playback.phase()"), "ended");

  h.run("Playback.notifyExternalRender()");
  assert.equal(finishes.length, 1);
  // Per stop()'s endedDuringHold branch (finishTimer still pending when
  // notifyExternalRender's stop({restoreSelection:false}) lands): this
  // reads as the run's own completion, not an abort. Recording the observed
  // value here rather than assuming it, per the brief.
  assert.equal(finishes[0].aborted, false);
  assert.equal(h.run("Playback.phase()"), "idle");
});

test("pausing in the terminus hold and resuming advances once", async () => {
  const h = playbackHarness({
    trains: [
      makeTrain("t1", "T1", "#111111"),
      makeTrain("t2", "T2", "#222222"),
    ],
    selectedTrainId: null,
  });
  h.run("map.fitBounds = () => {};");
  const trailCalls = [];
  h.context.__trailCalls = trailCalls;
  h.run(`
    RailMap.setPlaybackTrail = (done, runs, color) => {
      __trailCalls.push({ doneLength: done.length, color });
    };
  `);

  const stepper = frameStepper(h);
  assert.equal(h.run("Playback.start({autoBegin:true})"), true);
  h.run("Playback.begin()");
  h.emitMoveend();
  assert.equal(h.run("Playback.phase()"), "playing");

  // Drive until train 1's terminus flips phase to "transitioning" (the
  // TERMINUS_HOLD_MS hold finishTrain() arms transitionTimer for, not the
  // intro's moveend hand-off, which already happened above).
  await stepper.until(() => h.run("Playback.phase()") === "transitioning");

  const before = trailCalls.length;
  h.run("Playback.pause()");
  assert.equal(h.run("Playback.phase()"), "paused");
  h.run("Playback.resume()");

  // resume() detects pausedAtTerminus and calls advanceAfterTerminus()
  // directly instead of restarting the clock — this should move the run to
  // train 2 exactly once, not replay train 1's arrival a second time.
  assert.equal(h.run("Playback.captionState().color"), "#222222");
  assert.equal(h.run("Playback.phase()"), "playing");

  const after = trailCalls.length;
  assert.equal(
    after,
    before + 1,
    "advanceAfterTerminus() from resume() must produce exactly one new setPlaybackTrail call",
  );
  // Train 1 has exactly one run (single matched-feature stub); if the hold
  // had fired twice, this would be doubled instead.
  assert.equal(trailCalls[after - 1].doneLength, 1);
  assert.equal(trailCalls[after - 1].color, "#222222");

  await stepper.until(() => h.run("Playback.phase()") === "ended");
  assert.equal(h.run("Playback.phase()"), "ended");
});

test("a stroke-generation bump mid-run re-uploads the stations", async () => {
  const h = playbackHarness({ trains: [makeTrain("t1", "T1")] });
  h.run("map.fitBounds = () => {};");
  const stationsCalls = [];
  h.context.__stationsCalls = stationsCalls;
  h.run(`
    RailMap.setPlaybackStations = (stations) => { __stationsCalls.push(stations); };
  `);

  const stepper = frameStepper(h);
  assert.equal(h.run("Playback.start({autoBegin:true})"), true);
  h.run("Playback.begin()");
  h.emitMoveend();
  assert.equal(h.run("Playback.phase()"), "playing");

  // beginTrain() already uploaded the stations once before any frame ran.
  const before = stationsCalls.length;
  assert.ok(before >= 1);
  const prevLength = stationsCalls[before - 1].length;

  // RailMap._rideStrokeGeneration is the harness's stub for the counter
  // rideStrokeGeneration() reads (see playbackHarness's Object.assign(RailMap,
  // {...})); bumping it here simulates railmap.js's _applyRideStrokes
  // rebuilding the NA continuous strokes mid-playback.
  h.run("RailMap._rideStrokeGeneration = (RailMap._rideStrokeGeneration || 0) + 1;");
  stepper.step();

  assert.equal(
    stationsCalls.length,
    before + 1,
    "expected frame()'s recompile branch to re-upload the stations after the generation bump",
  );
  assert.equal(stationsCalls[stationsCalls.length - 1].length, prevLength);
});
