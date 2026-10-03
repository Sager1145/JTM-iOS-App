#!/usr/bin/env python3
"""Exercise production passport grouping of complete, partial and pending mileage.

Usage: script <RailKit build scratch>. The application grouping file compiles
unchanged against built RailCore/RailPresentation. The small collaborators below
only supply explicit Japan region, stop flags, and list ordering for the fixture.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
scratch = Path(sys.argv[1]).resolve()
library = next(scratch.rglob("libRailCore.a"), None)
if library is not None:
    products = library.parent
    link_inputs = [library, products / "libRailPresentation.a"]
else:
    core_module = next(scratch.rglob("Modules/RailCore.swiftmodule"), None)
    if core_module is None:
        raise SystemExit("Build RailKit first; RailCore module is missing")
    products = core_module.parent
    build = products.parent
    link_inputs = [*sorted((build / "RailCore.build").glob("*.o")),
                   *sorted((build / "RailPresentation.build").glob("*.o"))]
    if not link_inputs:
        raise SystemExit("Build RailKit first; package object files are missing")

checks = r'''
import Foundation
import RailCore
import RailPresentation

enum Region: String, Sendable {
    case jp
    var code: String { rawValue }
    static let enabledOrdered: [Region] = [.jp]
    static func resolved(_ train: Train) -> Region { .jp }
}
extension Train {
    var journeyClock: JourneyClock { JourneyClock(home: .forRegionCode("jp")) }
}
enum MapRideMarkers {
    static func rideFlags(_ stops: [Stop]) -> [Statistics.Stop] {
        stops.map { .init(arrival: $0.arrival, departure: $0.departure,
                         stopType: $0.stopType, rideSegment: $0.rideSegment) }
    }
}
enum StatisticsFormat {
    static func linesPrecede(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }
}

@main struct Checks {
    static func train(_ id: String, pending: Bool = false) -> Train {
        Train(id: id, date: "2026-10-03", number: id, trainType: "local",
              company: "Operator", origin: "A", destination: "B",
              stops: [Stop(name: "A", departure: "10:00", stopType: "origin", rideSegment: true),
                      Stop(name: "B", arrival: "11:00", stopType: "destination", rideSegment: true)],
              region: "jp", routeConfirmation: pending ? .pending : nil)
    }

    static func main() {
        let partial = Statistics.TrainEntry(km: 100, distanceIsKnown: false, partialDistanceIsProven: true)
        let completed = [Statistics.TrainEntry(km: 10), Statistics.TrainEntry(km: 30)]
        let combined = PassportStatistics.build(
            trains: [train("partial"), train("short"), train("long")], entries: [partial] + completed)
        precondition(combined.journeys == 3 && combined.totalKm == 140)
        precondition(combined.byYear.first?.km == 140 && combined.months(in: 2026).reduce(0) { $0 + $1.km } == 140)
        precondition(combined.weekdays(in: 2026).reduce(0) { $0 + $1.km } == 140)
        precondition(combined.operators.first?.km == 140 && combined.regions.first?.km == 140)
        precondition(combined.routes.first?.km == 140 && combined.stations.allSatisfy { $0.km == 140 })
        precondition(combined.measuredJourneys == 2 && combined.averageKm == 20)
        precondition(combined.longestByDistance?.id == "long" && combined.shortestByDistance?.id == "short")
        print("PASS proven partial parts remain in totals and distributions; complete journeys alone supply distance mean and records")

        let onlyPartial = PassportStatistics.build(trains: [train("partial")], entries: [partial])
        precondition(onlyPartial.totalKm == 100 && onlyPartial.measuredJourneys == 0 && onlyPartial.averageKm == 0)
        precondition(onlyPartial.longestByDistance == nil && onlyPartial.shortestByDistance == nil)
        print("PASS a partial-only passport retains measured parts without claiming a complete distance")

        let unproven = Statistics.TrainEntry(km: 123, distanceIsKnown: false)
        let excluded = PassportStatistics.build(
            trains: [train("legacy-unknown"), train("pending", pending: true), train("pending-stale", pending: true)],
            entries: [unproven, partial, .init(km: 999)])
        precondition(excluded.journeys == 3 && excluded.totalKm == 0 && excluded.measuredJourneys == 0)
        precondition(excluded.averageKm == 0 && excluded.longestByDistance == nil && excluded.shortestByDistance == nil)
        precondition(excluded.byYear.first?.count == 3 && excluded.byYear.first?.km == 0)
        precondition(excluded.operators.first?.count == 3 && excluded.operators.first?.km == 0)
        print("PASS pending and legacy unproven values stay excluded while their registered journeys remain counted")

        let completeOnly = PassportStatistics.build(trains: [train("short"), train("long")], entries: completed)
        precondition(completeOnly.totalKm == 40 && completeOnly.measuredJourneys == 2 && completeOnly.averageKm == 20)
        precondition(completeOnly.longestByDistance?.km == 30 && completeOnly.shortestByDistance?.km == 10)
        print("PASS complete-only passport totals, averages and distance records remain unchanged")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="jtm-passport-distance-") as temporary:
    folder = Path(temporary)
    source = folder / "Checks.swift"
    source.write_text(checks)
    executable = folder / "checks"
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
        "-module-cache-path", str(folder / "modules"), "-I", str(products),
        str(root / "ios/RailMap/PassportStatistics.swift"), str(source),
        *map(str, link_inputs), "-lsqlite3", "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
