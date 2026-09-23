#!/usr/bin/env python3
"""Run the production editor validator against focused valid/invalid drafts.

Usage: python3 ios/tools/verify-editor-validation.py <RailKit swift-test scratch>
Compiles the actual application source and links existing RailCore objects.
No application data or simulator is modified.
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

harness = r'''
import Foundation
import RailCore

@main struct Checks {
    static func main() throws {
        let valid = Train(id: "journey_test", number: "Express 1", origin: "Tokyo",
                          destination: "Shinagawa", stops: [
                            Stop(name: "Tokyo", departure: "23:50", stopType: "origin", rideSegment: true),
                            Stop(name: "Shinagawa", arrival: "00:10+1", stopType: "destination", rideSegment: true)
                          ])
        var count = 0
        func issues(_ draft: Train) -> [RideDraftIssue] {
            RideDraftValidation.issues(for: draft, originalID: valid.id, existingIDs: [valid.id, "taken"])
        }
        func accepts(_ name: String, _ change: (inout Train) -> Void = { _ in }) {
            var draft = valid
            change(&draft)
            let result = issues(draft)
            precondition(result.blocking.isEmpty, "\(name): \(result)")
            count += 1
        }
        func rejects(_ name: String, field: RideDraftIssue.Field, _ change: (inout Train) -> Void) {
            var draft = valid
            change(&draft)
            let result = issues(draft)
            precondition(result.blocking.contains { $0.field == field }, "\(name): \(result)")
            count += 1
        }
        accepts("undated journey")
        accepts("explicit undated") { $0.date = TrainValidation.undated }
        accepts("leap day") { $0.date = "2028-02-29" }
        accepts("optional service metadata") { $0.numberEn = "Express"; $0.trainType = "Limited Express"; $0.vehicleType = "E235"; $0.company = "JR" }
        accepts("platform zero") { $0.stops[0].platformNumber = 0 }
        accepts("named route section") { $0.routeSections = [RouteSection(from: "Tokyo", to: "Shinagawa")] }
        accepts("canonical route policy") { $0.routePolicy = TrainValidation.canonicalRoutePolicy(nil) }
        accepts("valid color") { $0.style = TrainStyle(color: "#123456") }
        accepts("middle stop may have both times") {
            $0.stops.insert(Stop(name: "Intermediate", arrival: "23:55", departure: "23:56"), at: 1)
        }
        rejects("empty ID", field: .id) { $0.id = "" }
        rejects("invalid ID", field: .id) { $0.id = "invalid id" }
        rejects("blank service", field: .number) { $0.number = " \n" }
        rejects("blank origin", field: .origin) { $0.origin = " " }
        rejects("blank destination", field: .destination) { $0.destination = "" }
        // The shared schema deliberately accepts days 1...31 for legacy
        // calendar rollover, even when the month is shorter (Dates.swift).
        accepts("legacy rollover date") { $0.date = "2027-02-29" }
        rejects("out-of-range month", field: .date) { $0.date = "2027-13-01" }
        rejects("cleared enabled date", field: .date) { $0.date = "" }
        rejects("no stops", field: .stops) { $0.stops = [] }
        rejects("one stop", field: .stops) { $0.stops.removeLast() }
        rejects("blank stop", field: .stop(0)) { $0.stops[0].name = " " }
        rejects("invalid role", field: .stop(1)) { $0.stops[1].stopType = "invalid" }
        rejects("invalid station code", field: .stop(0)) { $0.stops[0].n02StationCode = "?" }
        rejects("negative platform", field: .stop(0)) { $0.stops[0].platformNumber = -1 }
        rejects("origin both times", field: .stop(0)) { $0.stops[0].arrival = "23:49" }
        rejects("destination both times", field: .stop(1)) { $0.stops[1].departure = "00:11+1" }
        rejects("incomplete route section", field: .routeSection(0)) { $0.routeSections = [RouteSection(from: "Tokyo")] }
        rejects("invalid section code", field: .routeSection(0)) { $0.routeSections = [RouteSection(from: "Tokyo", to: "Shinagawa", fromN02StationCode: "?")] }
        rejects("invalid policy institution", field: .routePolicy) { $0.routePolicy = TrainValidation.canonicalRoutePolicy(nil); $0.routePolicy?.allowedInstitutionTypeCodes = ["999"] }
        rejects("invalid policy filter", field: .routePolicy) { $0.routePolicy = TrainValidation.canonicalRoutePolicy(nil); $0.routePolicy?.institutionFilterMode = "invalid" }
        rejects("authoritative policy fallback", field: .routePolicy) { $0.routePolicy = TrainValidation.canonicalRoutePolicy(nil); $0.routePolicy?.allowBrowserStraightLineFallback = true }
        rejects("invalid color", field: .color) { $0.style = TrainStyle(color: "invalid") }
        var collision = valid
        collision.id = "taken"
        let collisionIssues = issues(collision)
        precondition(collisionIssues.blocking.isEmpty)
        precondition(collisionIssues.contains { $0.field == .id && $0.severity == .warning })
        count += 1
        var repaired = valid
        repaired.stops[0].name = ""
        precondition(!issues(repaired).blocking.isEmpty)
        repaired.stops[0].name = valid.stops[0].name
        precondition(issues(repaired).blocking.isEmpty)
        count += 1
        print("PASS \(count) production editor validation cases")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="jtm-editor-validation-") as temporary:
    folder = Path(temporary)
    checks = folder / "Checks.swift"
    checks.write_text(harness)
    executable = folder / "checks"
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(folder / "ModuleCache"))
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                    "-sdk", sdk, "-I", str(modules),
                    str(root / "ios/RailMap/EditorValidation.swift"), str(checks),
                    *map(str, objects), "-o", str(executable)], check=True, env=environment)
    subprocess.run([str(executable)], check=True)
