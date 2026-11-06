import Foundation
import Testing
@testable import RailCore

struct RegionConnectivityTests {
    @Test("no two supported regions are connected")
    func supportedRegionsAreMutuallyUnconnected() {
        let regions = ["jp", "kr", "tw", "hk", "mo"]
        for a in regions {
            #expect(RegionConnectivity.isSupported(a))
            #expect(RegionConnectivity.areConnected(a, a))
            for b in regions where a != b {
                #expect(!RegionConnectivity.areConnected(a, b), "\(a)-\(b)")
            }
        }
    }

    @Test("mainland China is unsupported and its links are disabled")
    func chinaDisabled() {
        #expect(!RegionConnectivity.isSupported("cn"))
        #expect(!RegionConnectivity.supportedRegions.contains("cn"))
        #expect(!RegionConnectivity.areConnected("hk", "cn"))
        #expect(!RegionConnectivity.areConnected("cn", "cn"))
        #expect(RegionConnectivity.connectedRegions(of: "hk") == ["hk"])
    }

    @Test("the hk-cn link exists in the data and is disabled")
    func hkCnLinkPresentButDisabled() throws {
        let url = try #require(Bundle.module.url(forResource: "region-connectivity", withExtension: "json"))
        let doc = try JSONDecoder().decode(
            RegionConnectivity.Document.self, from: Data(contentsOf: url))
        let link = try #require(doc.links.first { Set($0.regions) == ["hk", "cn"] })
        #expect(!link.enabled)
    }

    @Test("firstUnconnectedPair finds a jp plus tw trip and ignores single-region trips")
    func firstPair() {
        let pair = RegionConnectivity.firstUnconnectedPair(
            stationIDs: ["st:jp:a", "st:jp:b", "st:tw:c", nil])
        #expect(pair?.0 == "jp")
        #expect(pair?.1 == "tw")
        #expect(RegionConnectivity.firstUnconnectedPair(stationIDs: ["st:hk:a", "st:hk:b"]) == nil)
        #expect(RegionConnectivity.region(ofStationID: "st:kr:x") == "kr")
    }

    // MARK: solver and resolution

    private let o = Coordinate(lon: 139, lat: 35)
    private let t = Coordinate(lon: 139.05, lat: 35)

    private var sections: [RouteGraph.SectionFeature] {
        [.init(properties: .init(lineName: "Main", operator: "Operator", institutionTypeCode: "1"), lines: [[o, t]])]
    }
    private func station(_ p: Coordinate, _ code: String) -> Stations.Feature {
        .init(properties: ["n02_station_code": .string(code), "station_name": .string(code),
            "line_name": .string("Main"), "operator": .string("Operator"),
            "institution_type_code": .string("1")], geometry: .init(type: "Point", coordinates: .array([
                .number(p.lon), .number(p.lat)])))
    }
    private var features: [Stations.Feature] { [station(o, "O"), station(t, "T")] }

    private func section(from: String, to: String) -> RouteSection {
        RouteSection(from: "O", to: "T", fromN02StationCode: "O", toN02StationCode: "T",
                     fromStationID: from, toStationID: to)
    }

    @Test("the solver returns no path across unconnected regions but solves within one")
    func solverGuard() {
        let graph = RouteGraph.build(from: sections)
        let index = Stations.Index(features)
        func solve(_ s: RouteSection) -> RouteSolver.SolvedSection? {
            RouteSolver.solveSection(s, segmentIndex: 0, train: .init(), country: "jp",
                                     graph: graph, stations: index)
        }
        #expect(solve(section(from: "st:jp:o", to: "st:tw:t")) == nil)
        #expect(solve(section(from: "st:jp:o", to: "st:jp:t")) != nil)
        #expect(RouteSolver.solveSection(section(from: "st:cn:o", to: "st:cn:t"), segmentIndex: 0,
            train: .init(), country: "cn", graph: graph, stations: index) == nil)
    }

    @Test("resolution turns a cross-region section into a flagged gap with no drawn track")
    func resolutionFlagsGap() throws {
        let s = section(from: "st:jp:o", to: "st:tw:t")
        let train = Train(id: "x", date: "2026-07-01", number: "Local", company: "Operator",
            origin: "O", destination: "T", routeSections: [s],
            stops: [Stop(name: "O", n02StationCode: "O", rideSegment: true),
                    Stop(name: "T", rideSegment: false)], region: "jp")
        var resolution = RideRouteResolution(
            inputs: .init(sections: sections, stationCollection: .init(features: features)),
            country: "jp")
        let result = try resolution.resolve(.init(train: train))
        #expect(result.segments.isEmpty)
        #expect(result.physicalGaps.contains { $0.segmentIndex == 0 && !$0.isBoundary })
    }

    // MARK: store and data

    @Test("a cn trip survives encode and decode")
    func cnTripRoundTrips() throws {
        var train = StoreOperations.createBlankTrain(country: "cn")
        train.number = "G1"
        let decoded = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(train))
        #expect(decoded.region == "cn")
        #expect(decoded.number == "G1")
    }

    @Test("an imported trip spanning unconnected regions is kept and reported, not rejected")
    func importFlagsCrossRegion() throws {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.number = "X1"
        train.routeSections = [section(from: "st:jp:o", to: "st:tw:t")]
        let json = StoreOperations.json(train)
        let pair = try #require(TrainValidation.crossRegionPair(json))
        #expect(pair.0 == "jp" && pair.1 == "tw")
        _ = try TrainValidation.normalizeImportedTrain(json)
        // Free-text keys are not inspected.
        var named = StoreOperations.createBlankTrain(country: "jp")
        named.origin = "st:tw:fake"
        #expect(TrainValidation.crossRegionPair(StoreOperations.json(named)) == nil)
    }

    @Test("an hk trip with a CN-OSM source code is never one merged region set")
    func sourceCodesDoNotMerge() {
        #expect(RegionConnectivity.region(ofCode: "CN-OSM-N1") == "cn")
        #expect(RegionConnectivity.region(ofCode: "123456") == "jp")
        #expect(!RegionConnectivity.allConnected(["hk", "cn"]))
        #expect(RegionConnectivity.allConnected(["hk"]))
        RegionConnectivity.$supportedOverride.withValue(["hk", "cn"]) {
            #expect(!RegionConnectivity.allConnected(["hk", "cn"]))  // link still disabled
            #expect(RegionConnectivity.isSupported("CN"))
        }
    }

    @Test("Hong Kong data carries no XRL or West Kowloon")
    func hkDataHasNoXrl() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // feature subfolder
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = ["app/data/rail-sections-hk.json", "app/data/stations-hk.json",
                     "app/public/rail/hk-2025.json"]
        for file in files {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for needle in ["cn-guangshengan-hsr", "XJA", "西九龍", "西九龙", "West Kowloon"] {
                #expect(!text.contains(needle), "\(file) contains \(needle)")
            }
        }
    }
}

/// Runs a test with mainland China treated as supported, so retained cn
/// behaviour stays covered while the region is disabled in the shipped data.
struct MainlandChinaEnabled: TestTrait, TestScoping {
    func provideScope(
        for test: Test, testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await RegionConnectivity.$supportedOverride.withValue(
            ["jp", "tw", "hk", "mo", "kr", "cn"], operation: { try await function() })
    }
}
extension Trait where Self == MainlandChinaEnabled {
    static var mainlandChinaEnabled: Self { Self() }
}
