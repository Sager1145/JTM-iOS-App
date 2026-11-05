import Foundation
import Testing
@testable import RailCore

/// Opt-in census of the bundled example trips through the app's draw path.
///
/// Every precomputed leg in `app/data/sample-data*/` and the special-sample
/// directories is projected with `RouteNetwork.precomputedDisplayParts`, the
/// same call `RiddenRouteStore` makes before drawing, against the display
/// network the map's "all rail routes" layer is built from. For each leg it
/// records which display lines carried it, whether the projection fell back
/// to the raw solver path, and how far the drawn stroke strays from the solved
/// path (a wrong branch or a cross-country chord shows up as a large distance).
/// The JSON report is consumed by `app/scripts/samples/audit-sample-routes.py`.
///
///     SAMPLE_DISPLAY_CENSUS=1 SAMPLE_DISPLAY_CENSUS_OUTPUT=/abs/out.json \
///       swift test --filter SampleTripDisplayCensusTests
struct SampleTripDisplayCensusTests {
    static let directories: [(String, String)] = [
        ("sample-data", "jp"), ("new-year-grand-loop-data", "jp"), ("tokyo-limited-express-loop-data", "jp"),
        ("sample-data-tw", "tw"), ("sample-data-hk", "hk"), ("sample-data-kr", "kr"), ("sample-data-mo", "mo"),
    ]

    struct Leg: Encodable {
        let store: String
        let ride: String
        let segment: Int
        let from: String?
        let to: String?
        var projected = false
        var displayLineIDs: [String] = []
        var displayLines: [String] = []
        var displayOperators: [String] = []
        var sourceLengthM = 0.0
        var drawnLengthM = 0.0
        /// Largest distance from a solved-path sample to the drawn stroke.
        var sourceToDrawnMaxM = 0.0
        /// Largest distance from a drawn sample to the solved path.
        var drawnToSourceMaxM = 0.0
        /// Longest straight drawn edge between consecutive vertices.
        var longestDrawnEdgeM = 0.0
    }

    static func network(_ loaded: DisplayParts.LoadedPackage) -> RouteNetwork {
        RouteNetwork(lines: loaded.package.lines.map { line in
            RouteNetwork.Line(
                lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: DisplayParts.parts(for: line, topology: loaded.topologyByLineID[line.id] ?? .init()),
                intervals: RailIntervalCodes.intervals(for: line), compactLine: line)
        })
    }

    static func resample(_ line: [Coordinate], step: Double) -> [Coordinate] {
        guard var previous = line.first else { return [] }
        var out = [previous]
        for next in line.dropFirst() {
            let distance = Geometry.distanceMeters(previous, next)
            let count = max(1, Int(distance / step))
            for i in 1...count {
                let t = Double(i) / Double(count)
                out.append(Coordinate(lon: previous.lon + (next.lon - previous.lon) * t,
                                      lat: previous.lat + (next.lat - previous.lat) * t))
            }
            previous = next
        }
        return out
    }

    static func distance(_ point: Coordinate, to lines: [[Coordinate]]) -> Double {
        let sy = 111_320.0, sx = 111_320.0 * cos(point.lat * .pi / 180)
        var best = Double.infinity
        for line in lines {
            if line.count == 1 { best = min(best, Geometry.distanceMeters(point, line[0])) }
            for (a, b) in zip(line, line.dropFirst()) {
                best = min(best, Geometry.perpDistanceMeters(point, a, b, sx: sx, sy: sy))
            }
        }
        return best
    }

    static func length(_ line: [Coordinate]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + Geometry.distanceMeters($1.0, $1.1) }
    }

    static func strings(_ value: Any?) -> [String] { (value as? [Any])?.compactMap { $0 as? String } ?? [] }

    @Test("Every bundled sample leg through the app display projection",
          .enabled(if: ProcessInfo.processInfo.environment["SAMPLE_DISPLAY_CENSUS"] == "1"))
    func sampleDisplayCensus() throws {
        let root = try PortFixtures.repositoryRoot()
        var networks: [String: RouteNetwork] = [:]
        var lineInfo: [String: (String, String)] = [:]
        var legs: [Leg] = []
        for (directory, country) in Self.directories {
            if networks[country] == nil {
                let loaded = try DisplayParts.LoadedPackage.load(
                    contentsOf: root.appending(path: "app/public/rail/\(country)-2025.json"))
                networks[country] = Self.network(loaded)
                for line in loaded.package.lines { lineInfo[line.id] = (line.name, line.operator ?? "") }
            }
            let network = try #require(networks[country])
            let folder = root.appending(path: "app/data/\(directory)")
            let parts = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0.hasPrefix("part-") && $0.hasSuffix(".json") }.sorted()
            var cache = RouteProjectionCache()
            for name in parts {
                let object = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: name)))
                let part = try #require(object as? [String: Any])
                let ride = (part["train"] as? [String: Any])?["id"] as? String ?? name
                guard let route = part["route"] as? [String: Any],
                      let features = route["features"] as? [[String: Any]] else { continue }
                for (offset, feature) in features.enumerated() {
                    let p = feature["properties"] as? [String: Any] ?? [:]
                    let geometry = feature["geometry"] as? [String: Any] ?? [:]
                    let strokes: [[Coordinate]]
                    if geometry["type"] as? String == "LineString" {
                        strokes = [((geometry["coordinates"] as? [[Double]]) ?? []).compactMap(Coordinate.init(pair:))]
                    } else {
                        strokes = ((geometry["coordinates"] as? [[[Double]]]) ?? []).map { $0.compactMap(Coordinate.init(pair:)) }
                    }
                    let hints = RouteHints(
                        requiredLineNames: Self.strings(p["required_line_names"]),
                        preferredLineNames: Self.strings(p["preferred_line_names"]),
                        requiredOperatorNames: Self.strings(p["required_operator_names"]),
                        preferredOperatorNames: Self.strings(p["preferred_operator_names"]),
                        requiredLineIDs: Self.strings(p["required_line_ids"]),
                        sectionCodes: Self.strings(p["section_codes"]),
                        fromStationCode: p["from_n02_station_code"] as? String,
                        toStationCode: p["to_n02_station_code"] as? String)
                    for source in strokes where source.count >= 2 {
                        var leg = Leg(store: directory, ride: ride, segment: p["segment_index"] as? Int ?? offset,
                                      from: p["from"] as? String, to: p["to"] as? String)
                        let drawn = network.precomputedDisplayParts(source: source, hints: hints, cache: &cache)
                        let drawnLines = drawn.map(\.coordinates)
                        leg.projected = drawn.contains { !$0.displayLineIDs.isEmpty }
                        var seen = Set<String>()
                        leg.displayLineIDs = drawn.flatMap(\.displayLineIDs).filter { seen.insert($0).inserted }
                        leg.displayLines = leg.displayLineIDs.map { lineInfo[$0]?.0 ?? $0 }
                        leg.displayOperators = Array(Set(leg.displayLineIDs.compactMap { lineInfo[$0]?.1 })).sorted()
                        leg.sourceLengthM = Self.length(source)
                        leg.drawnLengthM = drawnLines.reduce(0) { $0 + Self.length($1) }
                        for line in drawnLines {
                            for (a, b) in zip(line, line.dropFirst()) {
                                leg.longestDrawnEdgeM = max(leg.longestDrawnEdgeM, Geometry.distanceMeters(a, b))
                            }
                        }
                        for point in Self.resample(source, step: 50) {
                            leg.sourceToDrawnMaxM = max(leg.sourceToDrawnMaxM, Self.distance(point, to: drawnLines))
                        }
                        for point in drawnLines.flatMap({ Self.resample($0, step: 50) }) {
                            leg.drawnToSourceMaxM = max(leg.drawnToSourceMaxM, Self.distance(point, to: [source]))
                        }
                        legs.append(leg)
                    }
                }
            }
        }
        #expect(legs.isEmpty == false)
        let output = ProcessInfo.processInfo.environment["SAMPLE_DISPLAY_CENSUS_OUTPUT"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.temporaryDirectory.appending(path: "sample-display-census.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(legs).write(to: output)
        print("sample display census: \(legs.count) legs -> \(output.path)")
    }
}
