import Foundation
import RailCore
import Testing

struct SampleServiceConformanceTests {
    private typealias Ref = TrainServicePatterns.Pattern.StationRef
    private struct Stations: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                let n02_station_code: String
                let n02_group_code: String?
                let display_point: [Double]?
            }
            let properties: Properties
        }
        let features: [Feature]
    }

    // Class descriptions, not named services. These are deliberately individual rides.
    private let classOnly = [
        "20260707_06_a_ltdexp": "A特急 is a service class, without a named service",
        "20260711_05_seibu_ikebukuro_semiexp": "西武池袋線 急行 names a line and class",
    ]

    @Test func sampleServiceConformance() throws {
        let root = try PortFixtures.repositoryRoot()
        let store = try JSONDecoder().decode(TrainStore.self, from:
            Data(contentsOf: root.appending(path: "app/data/train-store.json")))
        let stations = try JSONDecoder().decode(Stations.self, from:
            Data(contentsOf: root.appending(path: "app/data/stations.json")))
        var groups: [String: String] = [:]
        var points: [String: [Double]] = [:]
        for feature in stations.features {
            let p = feature.properties
            if let group = p.n02_group_code, !group.isEmpty { groups[p.n02_station_code] = group }
            if let point = p.display_point { points[p.n02_station_code] = point }
        }
        func matches(_ stop: Stop, _ ref: Ref) -> Bool {
            if stop.name == ref.name { return true }
            guard let code = stop.n02StationCode else { return false }
            if code == ref.sourceCode { return true }
            return groups[code] != nil && groups[code] == groups[ref.sourceCode]
        }
        // Both catalog arrays are in line order. Interleave them while retaining
        // each array's order and the required endpoints. Minimize display-point
        // distance across the whole sequence, rather than projecting onto chords
        // (which reverses 飯山/上越妙高 on the curved Hokuriku route).
        // This does not establish physical connectivity; route tests do that.
        func ordered(_ pattern: TrainServicePatterns.Pattern) throws -> [Ref] {
            struct State: Hashable { let required: Int; let optional: Int; let lastOptional: Bool }
            struct Path { let distance: Double; let refs: [Ref] }
            let required = pattern.stopRefs, optional = pattern.optionalStopRefs
            guard let first = required.first else { return [] }
            var paths = [State(required: 1, optional: 0, lastOptional: false): Path(distance: 0, refs: [first])]
            for total in 1..<(required.count + optional.count) {
                for (state, path) in paths.filter({ $0.key.required + $0.key.optional == total }) {
                    var next: [(State, Ref)] = []
                    if state.required < required.count,
                       state.required < required.count - 1 || state.optional == optional.count {
                        next.append((State(required: state.required + 1, optional: state.optional,
                                           lastOptional: false), required[state.required]))
                    }
                    if state.optional < optional.count {
                        next.append((State(required: state.required, optional: state.optional + 1,
                                           lastOptional: true), optional[state.optional]))
                    }
                    for (key, ref) in next {
                        let last = try #require(path.refs.last)
                        let a = try #require(points[last.sourceCode], "Missing point for \(last.sourceCode)")
                        let b = try #require(points[ref.sourceCode], "Missing point for \(ref.sourceCode)")
                        let dx = (a[0] - b[0]) * cos((a[1] + b[1]) * .pi / 360)
                        let distance = path.distance + hypot(dx, a[1] - b[1])
                        if distance < (paths[key]?.distance ?? .infinity) {
                            paths[key] = Path(distance: distance, refs: path.refs + [ref])
                        }
                    }
                }
            }
            return try #require(paths[State(required: required.count, optional: optional.count,
                                            lastOptional: false)]).refs
        }
        func matchedPrefix(_ stops: [Stop], _ refs: [Ref]) -> Int {
            var index = 0
            for ref in refs where index < stops.count {
                if matches(stops[index], ref) { index += 1 }
            }
            return index
        }
        var checked = 0, failures = 0
        for ride in store.trains where (ride.region ?? "jp") == "jp" {
            let service = TrainServiceBranding.service(for: ride)
            if classOnly[ride.id] != nil {
                #expect(service == nil, "Class-only exemption now resolves: \(ride.id)")
                #expect(!(ride.trainType ?? "").contains("新幹線"))
                continue
            }
            guard service != nil || (ride.trainType ?? "").contains("新幹線") else { continue }
            checked += 1
            let stops = ride.stops.filter { $0.stopType != "pass_through" && $0.stopType != "pass-through" }
            var best = 0
            var candidates = 0
            if let service {
                for pattern in TrainServicePatterns.patterns(for: service.id) {
                    guard let date = ride.date,
                          pattern.validFrom.map({ date >= $0 }) ?? true,
                          pattern.validUntil.map({ date < $0 }) ?? true else { continue }
                    candidates += 1
                    let refs = try ordered(pattern)
                    best = max(best, matchedPrefix(stops, refs), matchedPrefix(stops, Array(refs.reversed())))
                }
            }
            if service == nil || candidates == 0 || best < stops.count {
                failures += 1
                let unmatched = best < stops.count ? stops[best].name : "(no dated pattern)"
                let message = "\(ride.id) [\(ride.number)] service=\(service?.id ?? "unresolved") first unmatched stop=\(unmatched)"
                print("NONCONFORMING \(message)")
                Issue.record(Comment(rawValue: message))
            }
        }
        print("SampleServiceConformance: \(checked) checked, \(checked - failures) conforming, \(failures) nonconforming")
    }
}
