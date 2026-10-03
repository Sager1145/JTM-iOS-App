#!/usr/bin/env python3
"""Exercise production route outcomes, gap persistence and ridden mileage scope."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
scratch = Path(sys.argv[1])
modules = next(scratch.rglob('RailCore.swiftmodule')).parent
archives = list(scratch.rglob('libRailCore.a'))
if archives:
    modules = archives[0].parent
    link_inputs = [archives[0], next(scratch.rglob('libRailPresentation.a'))]
else:
    link_inputs = [*modules.parent.glob('RailCore.build/*.o'), *modules.parent.glob('RailPresentation.build/*.o')]
route = (root / 'ios/RailMap/RiddenRouteStore.swift').read_text()
mileage = (root / 'ios/RailMap/MileageStatisticsStore.swift').read_text()

def block(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        if source[end] == '{': depth += 1
        if source[end] == '}': depth -= 1
        end += 1
    return source[start:end]

checks = r'''
import Foundation
import RailCore
import RailPresentation
// Date adapters and pixel payloads are doubles; the production outcome,
// persistence schema and full-distance decision below are extracted unchanged.
enum Dates { static func daySpan(_ value: Int) -> Int { value } }
extension Train { var forDates: Int { 0 } }
enum RiddenRouteStore {
    typealias RouteOutcome = RailPresentation.RouteOutcome
    typealias SectionGap = RailPresentation.SectionGap
__GAP__
    struct PhysicalRouteSelection: Codable, Equatable, Sendable {
        let intervals: [StationIntervalResolver.DirectedInterval]
        let lines: [ResolvedRailLine]
    }
    struct DrawnSegment: Sendable {
        let segmentIndex: Int
        var partIndex = 0
        var sourceCoordinates: [Coordinate] = []
        var physicalRoute: PhysicalRouteSelection? = nil
        var from: String? = nil
        var to: String? = nil
    }
    struct DrawnRide: Sendable {
        let id: String
        let trainType: String?
        let country: String
        let colorHex: String
        let visible: Bool
        let segments: [DrawnSegment]
        let route: RouteOutcome
        let stops: [Stop]
        let daySpan: Int
        let geometryDigest: Int
        var physicalGaps: [PhysicalGap] = []
    }
__DRAWN__
__CACHE__
__SEGMENT__
    static func cacheChecks(_ gaps: [PhysicalGap]) throws {
        let value = RuntimeCache(version: "test", resolutionSemantics: "physical-section-continuity-v2",
            digest: "test", resourceRevision: "test", physicalGaps: gaps, segments: [])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RuntimeCache.self, from: data)
        precondition(decoded.physicalGaps == gaps)
        var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        old.removeValue(forKey: "physicalGaps")
        let oldData = try JSONSerialization.data(withJSONObject: old)
        precondition((try? JSONDecoder().decode(RuntimeCache.self, from: oldData)) == nil)
    }
}
enum MileageStatisticsStore {
__KNOWN__
}
@main struct Checks {
    static func main() throws {
        let sections = [RouteSection(from: "A", to: "B"), RouteSection(from: "B", to: "C")]
        let stops = [Stop(name: "A", departure: "10:00", rideSegment: true),
            Stop(name: "B", arrival: "10:30", departure: "10:31", rideSegment: true),
            Stop(name: "C", arrival: "11:00", rideSegment: true)]
        let train = Train(id: "ride", number: "", origin: "A", destination: "C", stops: stops)
        let path = [Coordinate(lon: 139, lat: 35), Coordinate(lon: 139.01, lat: 35)]
        let segments = [RiddenRouteStore.DrawnSegment(segmentIndex: 0, sourceCoordinates: path),
            RiddenRouteStore.DrawnSegment(segmentIndex: 1, sourceCoordinates: path)]
        let gap = RiddenRouteStore.PhysicalGap(segmentIndex: 1, isBoundary: true)
        let partial = RiddenRouteStore.drawnRide(train, country: "jp", segments: segments,
            expectedSections: sections, physicalGaps: [gap])
        precondition(partial.segments.count == 2 && partial.segments[1].sourceCoordinates == path)
        if case .partial(let solved, let expected, let gaps) = partial.route {
            precondition(solved == 1 && expected == 2 && gaps.count == 1)
            precondition(gaps[0].from == "B" && gaps[0].to == "B")
        } else { preconditionFailure("an unproven seam was marked resolved") }
        precondition(!MileageStatisticsStore.fullDistanceKnown(train: train, ride: partial))
        try RiddenRouteStore.cacheChecks([gap])
        print("PASS disconnected sections remain drawn, the named boundary stays partial, and cache persistence cannot erase its proof gap")

        let complete = RiddenRouteStore.drawnRide(train, country: "jp", segments: segments, expectedSections: sections)
        precondition(complete.route == .resolved)
        precondition(complete.geometryDigest != partial.geometryDigest)
        precondition(MileageStatisticsStore.fullDistanceKnown(train: train, ride: complete))
        var oneRidden = train
        oneRidden.stops[2].rideSegment = false
        precondition(MileageStatisticsStore.fullDistanceKnown(train: oneRidden, ride: partial))
        let missingUnridden = RiddenRouteStore.drawnRide(oneRidden, country: "jp", segments: [segments[0]], expectedSections: sections)
        precondition(MileageStatisticsStore.fullDistanceKnown(train: oneRidden, ride: missingUnridden))
        precondition(!MileageStatisticsStore.fullDistanceKnown(train: train, ride: nil))
        let uncertified = RiddenRouteStore.drawnRide(train, country: "jp", segments: segments,
            expectedSections: sections, physicalGaps: [.init(segmentIndex: 0, isBoundary: false)])
        precondition(!MileageStatisticsStore.fullDistanceKnown(train: train, ride: uncertified))
        print("PASS only ridden gaps invalidate the full ridden distance; independent unridden sections and complete rides retain their semantics")
    }
}
'''
for placeholder, extracted in {
    '__GAP__': block(route, '    struct PhysicalGap:'),
    '__DRAWN__': block(route, '    private nonisolated static func drawnRide(').replace('private nonisolated', 'nonisolated'),
    '__CACHE__': block(route, '    private struct RuntimeCache:'),
    '__SEGMENT__': block(route, '    private struct CachedSegment:'),
    '__KNOWN__': block(mileage, '    private nonisolated static func fullDistanceKnown(').replace('private nonisolated', 'nonisolated'),
}.items(): checks = checks.replace(placeholder, extracted)

with tempfile.TemporaryDirectory(prefix='jtm-physical-continuity-') as temporary:
    folder = Path(temporary)
    source = folder / 'Checks.swift'
    source.write_text(checks)
    executable = folder / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
        '-module-cache-path', str(folder / 'modules'), '-I', str(modules), str(source),
        *map(str, link_inputs), '-lsqlite3', '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
