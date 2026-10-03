#!/usr/bin/env python3
"""Exercise the production playback controller without a simulator.

Usage: python3 ios/tools/verify-playback-lifecycle.py <RailKit swift-test scratch>
UIKit's passive display link and app stores are replaced with narrow test
collaborators. The actual controller/state-transition method bodies compile
unchanged; only tick's access level and the Objective-C selector are adapted.
The current Playback.swift is compiled alongside it; other RailCore types are
linked from the existing package build.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
scratch = Path(sys.argv[1]).resolve()
library = next(scratch.rglob("libRailCore.a"), None)
modules = library.parent if library else next(scratch.glob("*/debug/Modules"), None)
if modules is None:
    raise SystemExit("Run swift test --scratch-path <scratch> in ios/RailKit first")
objects = [library] if library else sorted((modules.parent / "RailCore.build").glob("*.swift.o"))
if not objects:
    raise SystemExit("RailCore build objects are missing")

collaborators = r'''
import Foundation
import RailCore
typealias CFTimeInterval = Double
@MainActor enum TestClock { static var now = 100.0 }
@MainActor func CACurrentMediaTime() -> Double { TestClock.now }
struct CAFrameRateRange { init(minimum: Float, maximum: Float, preferred: Float) {} }
@MainActor final class CADisplayLink {
    var timestamp = 0.0
    var preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    init(target: AnyObject, selector: String) {}
    func add(to: RunLoop, forMode: RunLoop.Mode) {}
    func invalidate() {}
}
enum Region { case jp; static func resolved(_ train: Train) -> Region { .jp } }
@MainActor final class AppLocalization {
    func stationName(_ name: String, code: String?, region: Region) -> String { name }
    func originName(of train: Train) -> String { train.origin }
    func destinationName(of train: Train) -> String { train.destination }
}
enum RiddenRouteStore {
    struct DrawnSegment: Sendable {
        let segmentIndex: Int
        var partIndex = 0
        let coordinates: [Coordinate]
    }
    struct DrawnRide: Sendable { let id: String; let segments: [DrawnSegment] }
}
enum RailSignpost {
    struct Signpost {
        func begin(_ name: String) -> Int { 0 }
        func end(_ name: String, _ token: Int) {}
    }
    static let map = Signpost()
}
@MainActor final class Renderer: PlaybackMapRendering {
    var snapshots: [PlaybackMapSnapshot] = []
    var clears = 0
    var framed: [Coordinate] = []
    func renderPlayback(_ snapshot: PlaybackMapSnapshot?) {
        if let snapshot { snapshots.append(snapshot) } else { clears += 1 }
    }
    func framePlayback(coordinates: [Coordinate], maxZoom: Double, animated: Bool) {
        framed = coordinates
    }
}
'''

checks = r'''
@main struct Checks {
    @MainActor static func main() async throws {
        let trains = (0..<2).map { i in
            Train(id: "run\(i)", number: "\(i)", origin: "A", destination: "B", stops: [
                Stop(name: "A", stopType: "origin", rideSegment: true),
                Stop(name: "B", stopType: "destination", rideSegment: true)])
        }
        let rides = trains.enumerated().map { i, train in
            RiddenRouteStore.DrawnRide(id: train.id, segments: [.init(segmentIndex: 0, coordinates: [
                Coordinate(lon: 135 + Double(i), lat: 35),
                Coordinate(lon: 135.001 + Double(i), lat: 35)])])
        }
        let controller = PlaybackController()
        let renderer = Renderer()
        controller.mapRenderer = renderer
        controller.speed = 4
        var count = 0
        func check(_ result: Bool, _ name: String) {
            precondition(result, name)
            count += 1
        }
        func start() {
            precondition(controller.start(trains: trains, rides: rides, reducedMotion: true))
        }
        func tick() {
            TestClock.now += 0.1
            controller.tick(timestamp: TestClock.now)
        }
        func completeJourney() {
            for _ in 0..<100 where controller.phase == .playing { tick() }
            precondition(controller.phase == .transitioning)
        }

        check(!controller.start(trains: [], rides: [], reducedMotion: true,
                                restoringSelection: "old"), "empty scope cannot arm")
        check(controller.phase == .idle && controller.restoreSelectedTrainID == nil,
              "empty scope leaves no restoration token")
        start()
        let reducedPlan = controller.estimate(trains: trains, rides: rides, reducedMotion: true)
        let motionPlan = controller.estimate(trains: trains, rides: rides, reducedMotion: false)
        check(abs(motionPlan.seconds - reducedPlan.seconds - 3.3) < 0.000001,
              "native quote counts opening, intro, finale moves")
        let singlePlan = controller.estimate(trains: [trains[0]], rides: rides, reducedMotion: true)
        check(abs(singlePlan.seconds - 2.22) < 0.000001,
              "native quote counts final terminus and fixed holds at 4x")
        check(controller.estimate(trains: [], rides: []).seconds == 0, "empty native quote is zero")
        check(controller.phase == .armed && controller.queueCount == 2, "start arms full queue")
        check(renderer.snapshots.last?.frame.progress == 0, "overview supplies first export frame")
        controller.next()
        check(controller.phase == .armed && controller.queueIndex == 1 && controller.progress == 0,
              "armed next does not press play")
        controller.previous()
        check(controller.phase == .armed && controller.queueIndex == 0, "armed previous stays armed")
        controller.begin()
        tick()
        check(controller.phase == .playing && controller.progress > 0, "begin advances clock")
        _ = controller.estimate(trains: [trains[1]], rides: rides)
        check(controller.queueCount == 2 && controller.queueIndex == 0 && controller.phase == .playing,
              "estimate does not replace active queue")
        controller.togglePause()
        let paused = controller.exactProgress
        tick()
        check(controller.exactProgress == paused, "paused clock does not advance")
        controller.next()
        check(controller.phase == .paused && controller.queueIndex == 1 && controller.progress == 0,
              "paused next remains paused at new origin")
        check(renderer.snapshots.last?.path.trainID == "run1"
              && renderer.snapshots.last?.frame.head == rides[1].segments[0].coordinates.first,
              "paused skip paints new train immediately")
        controller.next()
        check(controller.phase == .paused && controller.queueIndex == 1 && controller.progress == 0,
              "next at final journey does not fabricate completion")
        controller.previous()
        check(controller.phase == .paused && controller.queueIndex == 0, "paused previous remains paused")
        controller.togglePause()
        check(controller.phase == .playing, "resume starts selected journey")
        completeJourney()
        controller.togglePause()
        try await Task.sleep(for: .milliseconds(250))
        check(controller.phase == .paused && controller.queueIndex == 0, "pause cancels terminus advance")
        controller.togglePause()
        check(controller.phase == .playing && controller.queueIndex == 1, "resume terminus moves forward")
        tick()
        check(renderer.snapshots.last?.done.count == 1, "completed journey joins backlog")
        controller.previous()
        completeJourney()
        try await Task.sleep(for: .milliseconds(250))
        tick()
        check(renderer.snapshots.last?.done.count == 1, "replaying does not duplicate completed geometry")
        completeJourney()
        try await Task.sleep(for: .milliseconds(250))
        check(controller.phase == .ended && controller.progress == 1, "queue ends after final terminus")
        check(!controller.canGoNext && !controller.canGoPrevious, "ended queue disables navigation")
        var finishes = 0
        controller.onFinish = { finishes += 1 }
        start()
        check(controller.phase == .armed && controller.progress == 0, "ended run restarts from origin")
        try await Task.sleep(for: .seconds(1))
        check(finishes == 0, "restart cancels previous finale callback")
        controller.begin()
        completeJourney()
        controller.stop()
        try await Task.sleep(for: .milliseconds(250))
        check(controller.phase == .idle && controller.queueCount == 0, "stop cancels terminus task")
        start()
        controller.begin()
        controller.onFrame = { snapshot in if snapshot.frame.finished { controller.stop() } }
        for _ in 0..<100 where controller.phase == .playing { tick() }
        check(controller.phase == .idle, "frame consumer stop cannot resurrect playback")
        controller.onFrame = nil
        controller.onFinish = nil
        var dense = (0..<2002).map { Coordinate(lon: 135 + Double($0) * 0.000001, lat: 35) }
        dense[1] = Coordinate(lon: 140, lat: 42)
        let denseRide = RiddenRouteStore.DrawnRide(id: trains[0].id, segments: [
            .init(segmentIndex: 0, coordinates: dense)])
        precondition(controller.start(trains: [trains[0]], rides: [denseRide], reducedMotion: true))
        check(renderer.framed.contains(dense[1]), "overview sampling preserves unsampled extreme bend")
        controller.stop()
        let arrival = Coordinate(lon: 135.01, lat: 35)
        let departure = Coordinate(lon: 136, lat: 36)
        let gapTrain = Train(id: "gap", number: "Gap", origin: "A", destination: "D", stops: [
            Stop(name: "A", stopType: "origin", rideSegment: true),
            Stop(name: "B", stopType: "passenger_stop", rideSegment: true),
            Stop(name: "C", stopType: "passenger_stop", rideSegment: true),
            Stop(name: "D", stopType: "destination", rideSegment: true)])
        let gapRide = RiddenRouteStore.DrawnRide(id: gapTrain.id, segments: [
            .init(segmentIndex: 0, coordinates: [Coordinate(lon: 135, lat: 35), arrival]),
            .init(segmentIndex: 2, coordinates: [departure, Coordinate(lon: 136.01, lat: 36)])])
        precondition(controller.start(trains: [gapTrain], rides: [gapRide], reducedMotion: true))
        let nativeGap = renderer.snapshots.last!.path
        check(nativeGap.stations[1].coord == arrival && nativeGap.stations[2].coord == departure,
              "native controller preserves both stations across unridden gap")
        let webGap = Playback.compile(train: gapTrain, features: gapRide.segments.map {
            .init(geometry: .lineString($0.coordinates), rideSegment: $0.segmentIndex != 1,
                  segmentIndex: Double($0.segmentIndex)) })!
        check(webGap.stations[1].coord == departure, "default compile preserves Web parity at gap")
        controller.stop()
        print("PASS \(count) production playback lifecycle checks")
    }
}
'''

source = (root / "ios/RailMap/PlaybackController.swift").read_text()
source = source.replace("import QuartzCore\n", "").replace("import UIKit\n", "import Foundation\n")
source = source.replace("private func tick(timestamp:", "func tick(timestamp:")
source = source.replace("#selector(ClockTarget.fire(_:))", '"fire"').replace("@objc func fire", "func fire")
with tempfile.TemporaryDirectory(prefix="jtm-playback-lifecycle-") as temporary:
    folder = Path(temporary)
    production = folder / "PlaybackController.swift"
    production.write_text(source)
    playback_source = folder / "Playback.swift"
    playback_source.write_text("@testable import RailCore\n" +
                              (root / "ios/RailKit/Sources/RailCore/Playback.swift").read_text())
    harness = folder / "Checks.swift"
    harness.write_text(collaborators + checks)
    executable = folder / "checks"
    developer = Path(os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"))
    compiler = developer / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
    sdk = developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    if not compiler.is_file() or not sdk.is_dir():
        raise SystemExit("Host Swift compiler or MacOSX SDK unavailable; lifecycle checks not run")
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(folder / "ModuleCache"))
    subprocess.run([str(compiler), "-disable-sandbox", "-swift-version", "6", "-parse-as-library", "-sdk", str(sdk),
                    "-module-cache-path", str(folder / "ModuleCache"),
                    "-I", str(modules), str(playback_source), str(production), str(harness), *map(str, objects),
                    "-o", str(executable)], check=True, env=environment)
    subprocess.run([str(executable)], check=True)
