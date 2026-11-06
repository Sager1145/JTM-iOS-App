import Foundation
import Testing

@testable import RailCore

/// The `list` field a trip is filed under survives every path to and from
/// disk, and a record that never had one keeps its exact shape.
@Suite("a trip's list membership round-trips and stays absent when unset")
struct TripListMembershipCodingTests {

    private static func sample(list: TripListMembership?) -> Train {
        var train = Train(
            id: "list_01", date: "2026-08-28", number: "のぞみ1号",
            trainType: "新幹線", company: "JR東海",
            origin: "東京", destination: "新大阪", direction: "down", visible: true,
            stops: [
                Stop(name: "東京", departure: "06:00", stopType: "origin", rideSegment: true),
                Stop(name: "新大阪", arrival: "08:27", stopType: "destination", rideSegment: true),
            ],
            region: "jp")
        train.listMembership = list
        return train
    }

    @Test("membership survives native Codable storage")
    func nativeCodable() throws {
        for list in [TripListMembership.upcoming, .past] {
            let data = try JSONEncoder().encode(Self.sample(list: list))
            let text = try #require(String(data: data, encoding: .utf8))
            #expect(text.contains("\"list\":\"\(list.rawValue)\""))
            #expect(try JSONDecoder().decode(Train.self, from: data).listMembership == list)
        }
    }

    @Test("membership survives canonical export and import")
    func canonicalExportImport() throws {
        let exported = TrainValidation.normalizeExportTrain(
            Self.sample(list: .upcoming), country: "jp",
            stations: TrainValidation.StationTable.empty)
        let text = StoreOperations.stringify(StoreOperations.json(exported))
        #expect(text.contains("\"visible\":true,\"list\":\"upcoming\""))
        let reimported = try TrainValidation.normalizeImportedTrain(
            try TrainValidation.JSON.parse(text))
        #expect(reimported.listMembership == .upcoming)
    }

    @Test("an unset membership is absent from native and canonical output")
    func absentStaysAbsent() throws {
        let train = Self.sample(list: nil)
        let native = try #require(String(data: JSONEncoder().encode(train), encoding: .utf8))
        #expect(!native.contains("\"list\""))
        let exported = TrainValidation.normalizeExportTrain(
            train, country: "jp", stations: TrainValidation.StationTable.empty)
        let canonical = StoreOperations.stringify(StoreOperations.json(exported))
        #expect(!canonical.contains("\"list\""))
        let reimported = try TrainValidation.normalizeImportedTrain(
            try TrainValidation.JSON.parse(canonical))
        #expect(reimported.listMembership == nil)
    }

    @Test("an unknown membership value is refused on import")
    func unknownValueRefused() throws {
        let json = try TrainValidation.JSON.parse(
            """
            {"id":"x","number":"1","origin":"A","destination":"B","list":"someday",
             "stops":[{"name":"A","ride_segment":true},{"name":"B","ride_segment":true}]}
            """)
        #expect(throws: (any Error).self) {
            try TrainValidation.normalizeImportedTrain(json)
        }
    }

    @Test("list_by_date survives native and canonical storage, and is absent when unset")
    func listByDateRoundTrips() throws {
        var train = Self.sample(list: .upcoming)
        train.listByDate = true
        let data = try JSONEncoder().encode(train)
        #expect(try JSONDecoder().decode(Train.self, from: data).listByDate == true)
        let exported = TrainValidation.normalizeExportTrain(
            train, country: "jp", stations: TrainValidation.StationTable.empty)
        let text = StoreOperations.stringify(StoreOperations.json(exported))
        #expect(text.contains("\"list\":\"upcoming\",\"list_by_date\":true"))
        let reimported = try TrainValidation.normalizeImportedTrain(try TrainValidation.JSON.parse(text))
        #expect(reimported.listByDate == true)

        let plain = Self.sample(list: .upcoming)
        let plainText = try #require(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        #expect(!plainText.contains("list_by_date"))
    }

    @Test("a non-boolean list_by_date is refused on import")
    func listByDateMustBeBoolean() throws {
        let json = try TrainValidation.JSON.parse(
            """
            {"id":"x","number":"1","origin":"A","destination":"B","list_by_date":"yes",
             "stops":[{"name":"A","ride_segment":true},{"name":"B","ride_segment":true}]}
            """)
        #expect(throws: (any Error).self) {
            try TrainValidation.normalizeImportedTrain(json)
        }
    }
}
