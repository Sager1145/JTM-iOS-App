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
    private let classOnly: [String: String] = [
        "journey_3741AFAFFD9A67394E057294ACF48B00": "A特急 is a service class, without a named service",
        "journey_8AD20CEBC2F4E010D786EA9CEE066ABE": "西武池袋線 急行 names a line and class",
    ]

    // Recorded named conventional rides, pinned independently of the lookup
    // under test. Shinkansen rides remain required by their explicit class.
    private let namedConventionalServices: [String: String] = [
        "journey_A9554752F257CDA52831A6C0EED248AF": "haruka",
        "journey_290DDF7BAF84271A16574A1D9669181F": "super-tsugaru",
        "journey_03F366E23A32B262DDDA6774510A20D4": "inaho",
        "journey_65F43AE4739DB31208BF9295B6539472": "shirasagi",
        "journey_7FDB2E2A33B27404C1C8198B3C2B29F8": "hokuto",
        "journey_43D90DF84B5E40D6304EC290E8ED4E74": "ozora",
        "journey_F6F27BD3CBEFAA23FC0956F049DED550": "ozora",
        "journey_32E525B07148EE19DC4F3B99A36535ED": "soya",
        "journey_10F4EC2286758F85D709118AAFA6260E": "soya",
        "journey_8BADA44ED18197CDFA42A2D89B3028F1": "hokuto",
        "journey_9B1957E8CA2CA62A34EEBFC519E64422": "yakumo",
        "journey_55E89F3BE5BD16BC06291B252CFFA81B": "super-oki",
        "journey_06EC08904789EE82E214ED3D28758DE5": "midori",
        "journey_9E0FE255A29C5BBDEE31480F4AED2BE8": "relay-kamome",
        "journey_02C494EB5E72DE2FE0D3E5BC7D303309": "asoboy",
        "journey_71102CEF82BE99D98F5C7101CD080E07": "asoboy",
        "journey_45E72A351DEC6512AF96B89578A93E9A": "kirishima",
        "journey_E9C359F48C7CC40ABC70DBD05B606CFA": "nichirin",
        "journey_6F379655E47131DD2F854B65A847B9F0": "sonic",
        "journey_31C35A5D2E003443D5E26D7654555B25": "kirameki",
        "journey_FEDC12334D0F270D498B929602534FA8": "sonic",
        "journey_CECE2010BC0D2F1EB19C89BFD5900CAD": "shiokaze",
        "journey_BEEF6E99345E6E5CD1F5B4AF369AC636": "ishizuchi",
        "journey_771C696806C4705B412A265B953BD9A7": "uzushio",
        "journey_07E6AD25D8057D28D08088C1D40C2491": "ishizuchi",
        "journey_2A4BA95A7B92CB19921B27A2D3279C34": "nanpu",
        "journey_510175D3C325909EF4C88C3A42E1108B": "tsurugisan",
        "journey_D2D514AAEA06253635D51310E9C4C06B": "nanpu",
        "journey_6322F5578A2F139890D3B028ADDAF45A": "nanpu",
        "journey_1C77A10398A5B717F5372522CD764D5F": "odoriko",
        "journey_680A26B9C2D06FDE49DABFF6A02DF17C": "narita-express",
        "journey_F29762068C2DDB4CD79CF4AF30B29529": "sunrise-izumo",
        "journey_BB3AD8FEF0D118561F7FC4FA6227A5A6": "yakumo",
        "journey_0DCC26B17610DE9969C200D26CBA75DE": "rapit",
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
