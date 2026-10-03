#!/usr/bin/env python3
"""Exercise production endpoint lookup without promoting partial railway paths.

Usage: script <existing RailKit build scratch>. No app build or simulator needed.
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
    link_inputs = [library]
else:
    module = next(scratch.rglob("Modules/RailCore.swiftmodule"), None)
    if module is None:
        raise SystemExit("An existing RailCore build is required")
    products = module.parent
    link_inputs = sorted((products.parent / "RailCore.build").glob("*.o"))
    if not link_inputs:
        raise SystemExit("RailCore object files are missing")

endpoint = (root / "ios/RailMap/MapEndpointLabels.swift").read_text()
positions = endpoint[endpoint.index("    /// A station's independently known"):
                     endpoint.index("    /// One card, before and after placement.")]
logic = endpoint[endpoint.index("    static func endpointStop("):
                 endpoint.index("    // MARK: - the overlap-avoidance layout")]
markers = (root / "ios/RailMap/MapRideMarkers.swift").read_text()
marker_logic = markers[markers.index("    static func stopPositions("):
                       markers.index("    /// Which continuous-stroke chain")]
identity = (root / "ios/RailMap/MapRideStationImportance.swift").read_text()
identity_logic = identity[identity.index("        // An exact id with conflicting locations"):
                          identity.index("        snapshotsByCountry[country] = snapshot")]

doubles = r'''
import Foundation
import CoreGraphics
import RailCore

enum RiddenRouteStore {
    struct Outcome { let isResolved: Bool }
    struct Segment {
        let segmentIndex: Int
        let from: String?
        let to: String?
        let coordinates: [Coordinate]
    }
    struct DrawnRide {
        let stops: [Stop]
        let segments: [Segment]
        let route: Outcome
        var markerPositions: [Int: Coordinate] = [:]
    }
}
struct IdentityTable {
    struct Station {
        let id: String
        let idCollision: Bool
        let lon: Double
        let lat: Double
        var lines: [String] = ["line"]
    }
    let stations: [Station]
}
struct Stamp { let validFrom: String?; let validTo: String? }
struct Snapshot { var endpointPositions: [String: MapEndpointLabels.StationPosition] = [:] }
func identities(_ table: IdentityTable, stamps: [String: Stamp] = [:]) -> Snapshot {
    let country = "jp"
    var snapshot = Snapshot()
'''

checks = r'''
@main struct Checks {
    static func main() {
        let airport = Coordinate(lon: 135.2431991, lat: 34.4358973)
        let middle = Coordinate(lon: 135.52, lat: 34.65)
        let end = Coordinate(lon: 135.50, lat: 34.73)
        let stops = [Stop(name: "Airport", n02StationCode: "origin", stopType: "origin"),
                     Stop(name: "Middle", n02StationCode: "middle", stopType: "passenger_stop"),
                     Stop(name: "End", n02StationCode: "end", stopType: "destination")]
        let ride = RiddenRouteStore.DrawnRide(
            stops: stops,
            segments: [.init(segmentIndex: 1, from: "Middle", to: "End", coordinates: [middle, end])],
            route: .init(isResolved: false))
        let table = IdentityTable(stations: [
            .init(id: "origin", idCollision: false, lon: airport.lon, lat: airport.lat),
            .init(id: "end", idCollision: false, lon: 136, lat: 35)])
        let positions = identities(table).endpointPositions
        func known(_ stop: Stop) -> Coordinate? {
            MapEndpointLabels.stationPosition(for: stop, country: "jp", on: "2026-07-03", in: positions)
        }
        precondition(MapEndpointLabels.endpointStop(of: ride, kind: .origin) == nil,
                     "A partial stroke must not impersonate the origin")
        let origin = MapEndpointLabels.endpointStop(of: ride, kind: .origin, stationPosition: known)
        precondition(origin?.position == airport && origin?.stop.name == "Airport" && origin?.index == 0)
        let destination = MapEndpointLabels.endpointStop(of: ride, kind: .destination, stationPosition: known)
        precondition(destination?.position == end, "A valid drawn endpoint must keep precedence")
        precondition(!ride.route.isResolved && ride.segments.count == 1 && ride.markerPositions.isEmpty)
        let unavailable = RiddenRouteStore.DrawnRide(stops: stops, segments: [], route: .init(isResolved: false))
        precondition(MapEndpointLabels.endpointStop(of: unavailable, kind: .origin, stationPosition: known)?.position == airport)
        print("PASS known endpoints survive partial/unavailable paths without moving their geometry or proof")

        precondition(MapEndpointLabels.stationPosition(for: stops[0], country: "kr", on: "2026-07-03", in: positions) == nil)
        precondition(MapEndpointLabels.stationPosition(for: Stop(name: "Airport", n02StationCode: "missing"), country: "jp", on: "2026-07-03", in: positions) == nil)
        let invalid = identities(.init(stations: [
            .init(id: "origin", idCollision: false, lon: .nan, lat: 34),
            .init(id: "end", idCollision: false, lon: 136, lat: 91)])).endpointPositions
        precondition(invalid.isEmpty)
        let conflict = identities(.init(stations: [
            .init(id: "origin", idCollision: false, lon: airport.lon, lat: airport.lat),
            .init(id: "origin", idCollision: false, lon: 136, lat: 35),
            .init(id: "end", idCollision: true, lon: end.lon, lat: end.lat)])).endpointPositions
        precondition(conflict.isEmpty)
        precondition(MapEndpointLabels.endpointStop(of: ride, kind: .origin, stationPosition: { _ in nil }) == nil)
        print("PASS invalid, absent, cross-region and conflicting station identities cannot supply an origin")

        let dated = identities(table, stamps: ["line:origin": .init(validFrom: "1994-09-04", validTo: "2027-01-01")]).endpointPositions
        precondition(MapEndpointLabels.stationPosition(for: stops[0], country: "jp", on: "1994-09-03", in: dated) == nil)
        precondition(MapEndpointLabels.stationPosition(for: stops[0], country: "jp", on: "1994-09-04", in: dated) == airport)
        precondition(MapEndpointLabels.stationPosition(for: stops[0], country: "jp", on: "2027-01-01", in: dated) == nil)
        precondition(MapEndpointLabels.stationPosition(for: stops[0], country: "jp", on: "invalid", in: dated) == nil)
        let memberships = identities(.init(stations: [
            .init(id: "origin", idCollision: false, lon: airport.lon, lat: airport.lat,
                  lines: ["closed", "open"])]), stamps: [
            "closed:origin": .init(validFrom: nil, validTo: "2020-01-01"),
            "open:origin": .init(validFrom: "2020-01-01", validTo: nil)]).endpointPositions
        precondition(MapEndpointLabels.stationPosition(for: stops[0], country: "jp", on: "2026-07-03", in: memberships) == airport)
        print("PASS station date stamps retain production validity boundaries")
    }
}
'''

source = (doubles + identity_logic + "    return snapshot\n}\n"
          + "enum MapEndpointLabels {\n" + positions
          + "    enum Kind: String { case origin, destination }\n" + logic + "}\n"
          + "enum MapRideMarkers {\n" + marker_logic + "}\n" + checks)
with tempfile.TemporaryDirectory(prefix="jtm-endpoint-stations-") as temporary:
    folder = Path(temporary)
    path = folder / "Checks.swift"
    path.write_text(source)
    executable = folder / "checks"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                    "-module-cache-path", str(folder / "modules"), "-I", str(products),
                    str(root / "ios/RailMap/AppleMapDatum.swift"), str(path),
                    *map(str, link_inputs), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
