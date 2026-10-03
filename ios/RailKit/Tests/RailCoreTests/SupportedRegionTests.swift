import RailCore
import Testing

struct SupportedRegionTests {
    @Test(arguments: ["us", "US", "ca", "CA"])
    func retiredRegionsAreRejectedBeforeNormalization(_ region: String) {
        let raw = TrainValidation.JSON.object(.init([("region", .string(region))]))
        #expect(throws: TrainValidation.ValidationError.self) {
            try TrainValidation.validateSupportedRegions(raw)
        }
        #expect(throws: TrainValidation.ValidationError.self) {
            try TrainValidation.normalizeImportedTrain(raw)
        }
    }

    @Test(arguments: ["US-official-new-york", "ca-official-toronto"])
    func untaggedRetiredStationIdentitiesAreRejected(_ code: String) {
        let train = Train(id: "untagged", number: "Local", origin: "A", destination: "B",
                          stops: [.init(name: "A", n02StationCode: code)])
        #expect(throws: TrainValidation.ValidationError.self) {
            try TrainValidation.validateSupportedRegions(train)
        }
    }

    @Test(arguments: ["jp", "tw", "hk", "mo", "kr"])
    func activeRegionsRemainSupported(_ region: String) throws {
        let train = Train(id: "active", number: "Local", origin: "A", destination: "B",
                          stops: [], region: region)
        try TrainValidation.validateSupportedRegions(train)
    }

    @Test func serviceNamesDoNotBecomeRailwayIdentities() throws {
        let train = Train(id: "us-caption", number: "CA-service caption", origin: "A",
                          destination: "B", stops: [], region: "jp", notes: "US-example note")
        try TrainValidation.validateSupportedRegions(train)
    }

    @Test func retiredRouteIdentityIsRejectedDespiteActiveRegionTag() {
        let train = Train(id: "mixed", number: "Local", origin: "A", destination: "B",
                          routeSections: [.init(lineIDs: ["ca-official-line"])],
                          stops: [], region: "jp")
        #expect(throws: TrainValidation.ValidationError.self) {
            try TrainValidation.validateSupportedRegions(train)
        }
    }
}
