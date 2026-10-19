import Testing
import RailCore

struct MapPolicyTests {
    private func station(_ line: String, drawn: Bool = true, landlord: Bool = false,
                         measure: Double = 10, region: String = "jp", group: String = "family") -> StationBeadPolicy.Station {
        .init(region: region, stationCode: "platform", lineID: line, isDrawn: drawn,
              anchorMeasure: measure, windows: [.init(groupID: group, isLandlord: landlord, from: 10, to: 20)])
    }

    @Test func drawnLandlordSuppressesTenantAtInclusiveAnchor() {
        let tenant = station("tenant")
        #expect(StationBeadPolicy.isSuppressed(tenant, siblings: [tenant, station("owner", landlord: true)]))
        #expect(!StationBeadPolicy.isSuppressed(station("owner", landlord: true), siblings: [tenant]))
    }

    @Test func offscreenOrDifferentFamilyLandlordDoesNotSuppressTenant() {
        let tenant = station("tenant")
        #expect(!StationBeadPolicy.isSuppressed(tenant, siblings: [tenant, station("owner", drawn: false, landlord: true)]))
        #expect(!StationBeadPolicy.isSuppressed(tenant, siblings: [tenant, station("owner", landlord: true, group: "other")]))
        #expect(!StationBeadPolicy.isSuppressed(tenant, siblings: [tenant, station("owner", landlord: true, measure: 21)]))
        #expect(!StationBeadPolicy.isSuppressed(tenant, siblings: [tenant, station("owner", landlord: true, region: "tw")]))
    }

    @Test func visibleTenantsElectLowestLineAndNamesSurviveWhenNoDotIsDrawn() {
        let a = station("a"), b = station("b")
        #expect(!StationBeadPolicy.isSuppressed(a, siblings: [b, a]))
        #expect(StationBeadPolicy.isSuppressed(b, siblings: [b, a]))
        #expect(!StationBeadPolicy.isSuppressed(b, siblings: [station("a", drawn: false), b]))
        #expect(!StationBeadPolicy.isSuppressed(station("b", drawn: false), siblings: [station("a", drawn: false), station("b", drawn: false)]))
    }

    @Test func riddenVisibilityUsesSourceSectionForZeroDistanceBranchAndHonorsInvalidation() {
        let a = Coordinate(lon: 139, lat: 35), b = Coordinate(lon: 139.01, lat: 35)
        let index = Statistics.buildEdgeIndex(sections: [.init(properties: .init(
            n02_001: .string("11"), n02_002: .string("2"),
            n02_003: .string("test"), n02_004: .string("東日本旅客鉄道")), coordinates: [a, b])], country: "jp")
        var policy = RiddenCategoryVisibility()
        let filter = Statistics.RiddenCategoryFilter(jr: false)
        let hidesRidden = policy.draws(key: "ride#0.1", isRidden: true, sourceCoordinates: [b, b],
                             sectionSourceLines: [[a, b], [b, b]], from: "A", to: "B", country: "jp", index: index, filter: filter)
        #expect(!hidesRidden)
        let drawsUnridden = policy.draws(key: "ride#0.1", isRidden: false, sourceCoordinates: [b, b],
                            sectionSourceLines: [[a, b]], from: "A", to: "B", country: "jp", index: index, filter: filter)
        #expect(drawsUnridden)
        let drawsWithoutIndex = policy.draws(key: "missing", isRidden: true, sourceCoordinates: [a, b],
                            sectionSourceLines: [], from: "A", to: "B", country: "jp", index: nil, filter: filter)
        #expect(drawsWithoutIndex)
        policy.invalidate()
        let unknown = Coordinate(lon: 140, lat: 35)
        let drawsAfterInvalidation = policy.draws(key: "ride#0.1", isRidden: true, sourceCoordinates: [unknown, unknown],
                            sectionSourceLines: [], from: "A", to: "B", country: "jp", index: index, filter: filter)
        #expect(drawsAfterInvalidation)
    }
}
