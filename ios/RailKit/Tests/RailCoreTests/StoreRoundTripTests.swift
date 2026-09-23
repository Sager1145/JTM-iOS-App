import Foundation
import Testing

@testable import RailCore

// =========================================================================
//  What this app writes, this app can read.
//
//  There is no fixture for this and there cannot be one: `region` is this
//  port's own field, absent from the JavaScript, so the corpus generated from
//  the JavaScript says nothing about it. That is exactly how the asymmetry
//  survived — `normalizeExportTrain` was taught to carry `region` and
//  `StoreOperations.json(_:)` to write it, while `normalizeImportedTrain`'s
//  key whitelist stayed the JavaScript's thirteen. Every export the app made
//  was refused by its own importer with "Train contains unsupported field:
//  region.", one error per journey, so a backup the app had just written
//  could not be restored by it.
//
//  A round trip is the only shape of test that could have caught it: both
//  halves were individually correct and individually tested.
// =========================================================================

@Suite("a store the app exports is a store the app can import")
struct StoreRoundTripTests {

    private static func sample(region: String?) -> Train {
        Train(
            id: "roundtrip_01", date: "2026-08-28", number: "のぞみ1号",
            trainType: "新幹線", company: "JR東海",
            origin: "東京", destination: "新大阪", direction: "down", visible: true,
            stops: [
                Stop(name: "東京", departure: "06:00", stopType: "origin", rideSegment: true),
                Stop(name: "新大阪", arrival: "08:27", stopType: "destination", rideSegment: true),
            ],
            region: region)
    }

    @Test("an exported journey re-imports, and keeps the region it was exported with")
    func exportedJourneyReimports() throws {
        let exported = TrainValidation.normalizeExportTrain(
            Self.sample(region: "jp"), country: "jp",
            stations: TrainValidation.StationTable.empty)
        let text = StoreOperations.stringify(StoreOperations.json(exported))
        #expect(text.contains("\"region\""), "the export stopped writing region")

        let reimported = try TrainValidation.normalizeImportedTrain(
            try TrainValidation.JSON.parse(text))
        #expect(reimported.region == "jp")
        #expect(reimported.id == "roundtrip_01")
        #expect(reimported.stops.count == 2)
    }

    /// A ride that names no region still round-trips, and does not acquire one.
    ///
    /// The distinction matters: `Region.resolved` falls back to Japan because
    /// something has to be drawn right now, but writing that fallback into the
    /// record would make the guess permanent.
    @Test("an untagged journey round-trips without being tagged")
    func untaggedJourneyStaysUntagged() throws {
        let exported = TrainValidation.normalizeExportTrain(
            Self.sample(region: nil), country: "jp",
            stations: TrainValidation.StationTable.empty)
        let text = StoreOperations.stringify(StoreOperations.json(exported))
        #expect(!text.contains("\"region\""))

        let reimported = try TrainValidation.normalizeImportedTrain(
            try TrainValidation.JSON.parse(text))
        #expect(reimported.region == nil)
    }

    private static let legacyCaptionJSON = """
        {"id":"x","number":"はるか38号 (Haruka 38) (1038M)","origin":"A","destination":"B",
         "stops":[{"name":"A","departure":"06:00","stop_type":"origin","ride_segment":true},
                  {"name":"B","arrival":"07:00","stop_type":"destination","ride_segment":true}]}
        """

    @Test("a caption that carries the Latin name is split into number and number_en on import")
    func legacyCaptionIsSplitOnImport() throws {
        let train = try TrainValidation.normalizeImportedTrain(
            try TrainValidation.JSON.parse(Self.legacyCaptionJSON))
        #expect(train.number == "はるか38号 (1038M)")
        #expect(train.numberEn == "Haruka 38")
    }

    @Test("an explicit number_en keeps the caption exactly as written")
    func explicitNumberEnLeavesTheCaptionAlone() throws {
        let json = Self.legacyCaptionJSON.replacingOccurrences(
            of: "{\"id\":\"x\",", with: "{\"id\":\"x\",\"number_en\":\"X\",")
        let train = try TrainValidation.normalizeImportedTrain(
            try TrainValidation.JSON.parse(json))
        #expect(train.number == "はるか38号 (Haruka 38) (1038M)")
        #expect(train.numberEn == "X")
    }

    @Test("number_en is written right after number, and only when set")
    func numberEnIsWrittenAfterNumberOnlyWhenSet() throws {
        var train = Self.sample(region: nil)
        let without = StoreOperations.stringify(StoreOperations.json(train))
        #expect(!without.contains("number_en"))

        train.numberEn = "Nozomi 1"
        let exported = TrainValidation.normalizeExportTrain(
            train, country: "jp", stations: TrainValidation.StationTable.empty)
        let text = StoreOperations.stringify(StoreOperations.json(exported))
        #expect(text.contains("\"number\":\"のぞみ1号\",\"number_en\":\"Nozomi 1\""))

        let reimported = try TrainValidation.normalizeImportedTrain(
            try TrainValidation.JSON.parse(text))
        #expect(reimported.number == "のぞみ1号")
        #expect(reimported.numberEn == "Nozomi 1")
    }

    @Test("vehicle type survives native Codable storage and stays distinct from service class")
    func vehicleTypeSurvivesNativeCodableRoundTrip() throws {
        var train = Self.sample(region: "jp")
        train.vehicleType = "N700S"

        let data = try JSONEncoder().encode(train)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"train_type\":\"新幹線\""))
        #expect(text.contains("\"vehicle_type\":\"N700S\""))

        let decoded = try JSONDecoder().decode(Train.self, from: data)
        #expect(decoded.trainType == "新幹線")
        #expect(decoded.vehicleType == "N700S")
    }

    @Test("vehicle type survives canonical export and import")
    func vehicleTypeSurvivesExportImportRoundTrip() throws {
        var train = Self.sample(region: "jp")
        train.vehicleType = "N700S"

        let exported = TrainValidation.normalizeExportTrain(
            train, country: "jp", stations: TrainValidation.StationTable.empty)
        let text = StoreOperations.stringify(StoreOperations.json(exported))
        #expect(text.contains("\"train_type\":\"新幹線\",\"vehicle_type\":\"N700S\""))

        let reimported = try TrainValidation.normalizeImportedTrain(
            try TrainValidation.JSON.parse(text))
        #expect(reimported.trainType == "新幹線")
        #expect(reimported.vehicleType == "N700S")
    }

    @Test("an absent vehicle type remains absent from native and canonical output")
    func absentVehicleTypeStaysAbsent() throws {
        let train = Self.sample(region: nil)
        let nativeText = try #require(String(data: JSONEncoder().encode(train), encoding: .utf8))
        #expect(!nativeText.contains("vehicle_type"))

        let exported = TrainValidation.normalizeExportTrain(
            train, country: "jp", stations: TrainValidation.StationTable.empty)
        let canonicalText = StoreOperations.stringify(StoreOperations.json(exported))
        #expect(!canonicalText.contains("vehicle_type"))

        let reimported = try TrainValidation.normalizeImportedTrain(
            try TrainValidation.JSON.parse(canonicalText))
        #expect(reimported.vehicleType == nil)
    }

    /// The whitelist still rejects what it is for. Widening it by one key must
    /// not turn it into a door.
    @Test("a key the schema does not define is still refused")
    func anUnknownKeyIsStillRefused() throws {
        let json = try TrainValidation.JSON.parse(
            """
            {"id":"x","number":"1","origin":"A","destination":"B",
             "stops":[],"nickname":"nope"}
            """)
        #expect(throws: (any Error).self) {
            try TrainValidation.normalizeImportedTrain(json)
        }
    }
}
