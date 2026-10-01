import Foundation
import Testing

@testable import RailCore

struct DatedEndpointNameShadowTests {
    private static func station(
        name: String,
        line: String,
        operatorName: String,
        code: String? = nil,
        group: String? = nil,
        codeBasis: String? = nil,
        historyID: String? = nil,
        validFrom: String? = nil,
        validTo: String? = nil,
        lon: Double,
        lat: Double
    ) -> Stations.Feature {
        var properties: [String: Stations.Value] = [
            "station_name": .string(name),
            "line_name": .string(line),
            "operator": .string(operatorName),
            "display_point": .array([.number(lon), .number(lat)]),
        ]
        if let code { properties["n02_station_code"] = .string(code) }
        if let group { properties["n02_group_code"] = .string(group) }
        if let codeBasis { properties["station_code_basis"] = .string(codeBasis) }
        if let historyID { properties["history_id"] = .string(historyID) }
        if let validFrom { properties["valid_from"] = .string(validFrom) }
        if let validTo { properties["valid_to"] = .string(validTo) }
        return Stations.Feature(
            properties: properties,
            geometry: .init(
                type: "Point", coordinates: .array([.number(lon), .number(lat)])))
    }

    private static func datedCandidates(
        endpoint: Stations.Query,
        index: Stations.Index,
        lineNames: [String],
        operatorNames: [String],
        rideDate: String
    ) -> [Int] {
        RouteSolver.filterStationCandidatesByRideDate(
            RouteSolver.resolveRouteEndpointStationCandidates(
                endpoint,
                in: index,
                allowedCodes: [],
                sectionLineNames: lineNames,
                sectionOperatorNames: operatorNames,
                rideDate: rideDate),
            in: index,
            rideDate: rideDate)
    }

    @Test("retired Hankyu Umeda cannot fall through to current Metro Umeda")
    func retiredExplicitMembershipShadowsOtherOperatorNamesake() {
        let index = Stations.Index([
            Self.station(
                name: "梅田", line: "神戸線", operatorName: "阪急電鉄",
                validTo: "2019-10-01", lon: 135.4986, lat: 34.7055),
            Self.station(
                name: "梅田", line: "1号線(御堂筋線)",
                operatorName: "大阪市高速電気軌道",
                code: "007065", lon: 135.4995, lat: 34.7039),
        ])
        let endpoint = Stations.Query.name("梅田")

        #expect(Self.datedCandidates(
            endpoint: endpoint, index: index,
            lineNames: ["神戸線"], operatorNames: ["阪急電鉄"],
            rideDate: "2019-09-30") == [0, 1])
        #expect(Self.datedCandidates(
            endpoint: endpoint, index: index,
            lineNames: ["神戸線"], operatorNames: ["阪急電鉄"],
            rideDate: "2019-10-01").isEmpty)

        // With no hard operator identity, the still-current namesake retains
        // the normal nationwide name-resolution behavior.
        #expect(Self.datedCandidates(
            endpoint: endpoint, index: index,
            lineNames: ["神戸線"], operatorNames: [],
            rideDate: "2019-10-01") == [1])
    }

    @Test("a valid constrained shared platform keeps the complete candidate pool")
    func activeMembershipDoesNotBlanketFilterSharedPlatforms() {
        let index = Stations.Index([
            Self.station(
                name: "共同駅", line: "A線", operatorName: "A鉄道",
                code: "A01", group: "shared", lon: 135.0, lat: 35.0),
            Self.station(
                name: "共同駅", line: "B線", operatorName: "B鉄道",
                code: "B01", group: "shared", lon: 135.0, lat: 35.0),
        ])

        #expect(Self.datedCandidates(
            endpoint: .name("共同駅"), index: index,
            lineNames: ["A線"], operatorNames: ["A鉄道"],
            rideDate: "2024-01-01") == [0, 1])
    }

    @Test("an explicit code bypasses the dated name shadow guard")
    func explicitCodeKeepsStableIdentityResolution() {
        let index = Stations.Index([
            Self.station(
                name: "梅田", line: "神戸線", operatorName: "阪急電鉄",
                code: "HK01", validTo: "2019-10-01",
                lon: 135.4986, lat: 34.7055),
            Self.station(
                name: "梅田", line: "1号線(御堂筋線)",
                operatorName: "大阪市高速電気軌道",
                code: "007065", lon: 135.4995, lat: 34.7039),
        ])

        let candidates = RouteSolver.resolveRouteEndpointStationCandidates(
            .stop(.init(name: "梅田", n02StationCode: "HK01")),
            in: index,
            allowedCodes: [],
            sectionLineNames: ["神戸線"],
            sectionOperatorNames: ["阪急電鉄"],
            rideDate: "2019-10-01")
        #expect(candidates == [0])
    }

    @Test("a dated fixed code crosses a rename without accepting an unrelated wrong name")
    func datedCodeUsesKnownHistoricalNameVariantOnly() {
        let index = Stations.Index([
            Self.station(
                name: "梅田", line: "宝塚線", operatorName: "阪急電鉄",
                code: "007048", codeBasis: "exact_current_geometry_identity",
                historyID: "jp.station-rename.test",
                validTo: "2019-10-01",
                lon: 135.4986, lat: 34.7056),
            Self.station(
                name: "大阪梅田", line: "宝塚線", operatorName: "阪急電鉄",
                code: "007048", validFrom: "2019-10-01",
                lon: 135.4986, lat: 34.7056),
            Self.station(
                name: "別駅", line: "別線", operatorName: "別鉄道",
                code: "other", lon: 140.0, lat: 36.0),
        ])

        #expect(Self.datedCandidates(
            endpoint: .stop(.init(name: "大阪梅田", n02StationCode: "007048")),
            index: index, lineNames: ["宝塚線"], operatorNames: ["阪急電鉄"],
            rideDate: "2019-09-30") == [0])
        #expect(Self.datedCandidates(
            endpoint: .stop(.init(name: "大阪梅田", n02StationCode: "007048")),
            index: index, lineNames: ["宝塚線"], operatorNames: ["阪急電鉄"],
            rideDate: "2019-10-01") == [1])

        // The written name is not known in 007048's code pool, so the existing
        // inconsistent-pair behavior still falls back to the unrelated name.
        #expect(Self.datedCandidates(
            endpoint: .stop(.init(name: "別駅", n02StationCode: "007048")),
            index: index, lineNames: ["別線"], operatorNames: ["別鉄道"],
            rideDate: "2019-09-30") == [2])
        #expect(index.isCertifiedHistoricalNameAlias(
            actualIndex: 0, referenceName: "大阪梅田", referenceCode: "007048"))
        #expect(!index.isCertifiedHistoricalNameAlias(
            actualIndex: 2, referenceName: "大阪梅田", referenceCode: "007048"))

        let sharedGroupOnly = Stations.Index([
            Self.station(
                name: "梅田", line: "宝塚線", operatorName: "阪急電鉄",
                code: "007048", group: "shared-group",
                codeBasis: "exact_current_geometry_identity",
                historyID: "jp.station-rename.test", validTo: "2019-10-01",
                lon: 135.4986, lat: 34.7056),
            Self.station(
                name: "大阪梅田", line: "宝塚線", operatorName: "阪急電鉄",
                code: "007049", group: "shared-group", validFrom: "2019-10-01",
                lon: 135.4986, lat: 34.7056),
        ])
        #expect(!sharedGroupOnly.isCertifiedHistoricalNameAlias(
            actualIndex: 0, referenceName: "大阪梅田", referenceCode: "007048"))
    }

    @Test("the reviewed Hankyu codes select their surveyed old-name memberships")
    func reviewedHankyuRenameCodesResolveBeforeBoundary() throws {
        let root = try PortFixtures.repositoryRoot()
        var sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: root.appending(path: "app/data/rail-sections.json")).features
        var stationFeatures = try Stations.FeatureCollection.load(
            contentsOf: root.appending(path: "app/data/stations.json")).features
        let overlay = try RailHistoryOverlay.load(
            from: root.appending(path: "app/data/rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sections, stations: &stationFeatures)
        let index = Stations.Index(stationFeatures)

        func resolved(
            currentName: String, code: String, oldName: String,
            line: String, date: String
        ) -> [Int] {
            let candidates = Self.datedCandidates(
                endpoint: .stop(.init(name: currentName, n02StationCode: code)),
                index: index, lineNames: [line], operatorNames: ["阪急電鉄"],
                rideDate: date)
            #expect(!candidates.isEmpty)
            #expect(candidates.allSatisfy {
                let feature = index.features[$0]
                return Stations.stationName(feature) == oldName
                    && Stations.stationCode(feature) == code
                    && Stations.stationLineName(feature) == line
                    && Stations.stationOperator(feature) == "阪急電鉄"
            })
            #expect(candidates.allSatisfy {
                index.isCertifiedHistoricalNameAlias(
                    actualIndex: $0, referenceName: currentName, referenceCode: code)
            })
            return candidates
        }

        #expect(!resolved(
            currentName: "大阪梅田", code: "007048", oldName: "梅田",
            line: "宝塚線", date: "2019-03-23").isEmpty)
        #expect(!resolved(
            currentName: "京都河原町", code: "005990", oldName: "河原町",
            line: "京都線", date: "2011-05-14").isEmpty)
    }
}
