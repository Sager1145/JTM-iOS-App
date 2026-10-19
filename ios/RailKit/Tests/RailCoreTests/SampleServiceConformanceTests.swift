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

    // Recorded named conventional rides, pinned independently of the lookup
    // under test. Shinkansen rides remain required by their explicit class.
    private let namedConventionalServices = [
        "20260703_01_haruka": "haruka",
        "20260706_02_super_tsugaru2": "super-tsugaru",
        "20260706_03_inaho14": "inaho",
        "20260708_02_shirasagi2": "shirasagi",
        "20260713_07_hokuto21": "hokuto",
        "20260714_01_ozora3": "ozora",
        "20260714_04_ozora12": "ozora",
        "20260715_01_soya": "soya",
        "20260715_02_soya": "soya",
        "20260716_07_hokuto20": "hokuto",
        "20260719_02_yakumo11": "yakumo",
        "20260719_03_super_oki5": "super-oki",
        "20260720_47_midori35_shintosu_arita": "midori",
        "20260721_06_relay_kamome22": "relay-kamome",
        "20260721_08_asoboy3": "asoboy",
        "20260721_09_asoboy4": "asoboy",
        "20260722_04_kirishima8": "kirishima",
        "20260722_05_nichirin10": "nichirin",
        "20260722_06_sonic44": "sonic",
        "20260722_07_kirameki6": "kirameki",
        "20260722_08_sonic54_kokura_kurosaki": "sonic",
        "20260723_02_shiokaze5": "shiokaze",
        "20260723_03_ishizuchi10": "ishizuchi",
        "20260723_05_uzushio10": "uzushio",
        "20260724_01_ishizuchi9": "ishizuchi",
        "20260724_02_nanpu9": "nanpu",
        "20260724_03_tsurugisan6": "tsurugisan",
        "20260724_05_nanpu17": "nanpu",
        "20260724_06_nanpu28": "nanpu",
        "20260726_07_odoriko": "odoriko",
        "20260727_08_narita_express": "narita-express",
        "20260729_05_sunrise_izumo": "sunrise-izumo",
        "20260730_03_yakumo22": "yakumo",
        "20260731_02_rapit_alpha3": "rapit",
    ]

    @Test func sampleServiceConformance() throws {
        let root = try PortFixtures.repositoryRoot()
        let store = try JSONDecoder().decode(TrainStore.self, from:
            Data(contentsOf: root.appending(path: "app/data/train-store.json")))
        let japaneseIDs = Set(store.trains.filter { ($0.region ?? "jp") == "jp" }.map(\.id))
        try #require(Set(namedConventionalServices.keys).isSubset(of: japaneseIDs),
                     "Required named conventional rides disappeared from the sample store")
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
            if let expected = namedConventionalServices[ride.id] {
                let resolved = try #require(service, "Required sample branding disappeared: \(ride.id)")
                #expect(resolved.id == expected, "\(ride.id) must retain its named service identity")
            }
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
