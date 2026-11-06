import Foundation
import Testing

@testable import RailCore

@Suite("Add-trip autofill foundation")
struct TripAutofillTests {

    private static func base(
        rollingStock: RollingStock? = nil, ticket: Ticket? = nil, region: String? = "jp"
    ) -> Train {
        Train(
            id: "autofill_01", date: "2026-08-28", number: "のぞみ1号",
            trainType: "新幹線", company: "JR東海", origin: "東京", destination: "新大阪",
            direction: "down", visible: true,
            stops: [
                Stop(name: "東京", departure: "06:00", stopType: "origin", rideSegment: true),
                Stop(name: "新大阪", arrival: "08:27", stopType: "destination", rideSegment: true),
            ],
            region: region, rollingStock: rollingStock, ticket: ticket)
    }

    private func encoded(_ train: Train) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(train), as: UTF8.self)
    }

    // MARK: model

    @Test func absentBlocksAreNotWrittenAndRoundTripIdentically() throws {
        let train = Self.base()
        let text = try encoded(train)
        #expect(!text.contains("rolling_stock") && !text.contains("ticket"))
        let again = try JSONDecoder().decode(Train.self, from: Data(text.utf8))
        #expect(again == train)
        #expect(try encoded(again) == text)
        let json = StoreOperations.json(train)
        guard case .object(let object) = json else { Issue.record("not an object"); return }
        #expect(object["rolling_stock"] == nil && object["ticket"] == nil)
    }

    @Test func presentBlocksRoundTripThroughCodableAndImportExport() throws {
        let stock = RollingStock(
            setNumber: "G12", carCount: 16,
            cars: [.init(sequence: 1, number: "1", series: "N700S"), .init(sequence: 2)],
            riddenCar: 7, livery: "JR東海")
        let ticket = Ticket(seat: "5A", seatClass: "reserved", fare: 14720, currency: "JPY", kind: "ticket")
        let train = Self.base(rollingStock: stock, ticket: ticket)
        let text = try encoded(train)
        #expect(text.contains("\"rolling_stock\"") && text.contains("\"set_number\":\"G12\""))
        #expect(text.contains("\"seat_class\":\"reserved\""))
        #expect(try JSONDecoder().decode(Train.self, from: Data(text.utf8)) == train)

        let exported = TrainValidation.normalizeExportTrain(train)
        #expect(exported.rollingStock == stock && exported.ticket == ticket)
        let json = StoreOperations.json(train)
        let imported = try TrainValidation.normalizeImportedTrain(
            json, fallbackDate: "2026-08-28", country: "jp", stations: .empty)
        #expect(imported.rollingStock == stock)
        #expect(imported.ticket == ticket)
    }

    @Test func validationRejectsNegativeAndForeignCurrency() {
        var ids = Set<String>()
        let ok = TrainValidation.recordDiagnostics(
            Self.base(rollingStock: .init(carCount: 8, riddenCar: 0),
                      ticket: .init(fare: 0, currency: "JPY")), index: 0, ids: &ids)
        #expect(ok.isEmpty)
        ids = []
        let bad = TrainValidation.recordDiagnostics(
            Self.base(rollingStock: .init(carCount: -1, cars: [.init(sequence: -2)]),
                      ticket: .init(fare: -5, currency: "TWD")), index: 0, ids: &ids)
        #expect(Set(bad.map(\.path)) == [
            "rolling_stock.car_count", "rolling_stock.cars[0].sequence", "ticket.fare",
            "ticket.currency",
        ])
        #expect(Ticket.currencies(forRegion: "tw") == ["TWD"])
        #expect(Ticket.normalizedSeat(" ５ａ番 ") == "5A")
    }

    // MARK: formation

    @Test func bundledFormationMapsToVehicleTypeAndRollingStock() throws {
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let query = try database.trip(
            id: "jr-kyushu.ibusuki-no-tamatebako.1.2026-07-01", on: "2026-09-30")
        let trip = try #require(query)
        let draft = try #require(try database.rollingStockDraft(for: trip))
        #expect(draft.vehicleType == "キハ140")
        #expect(draft.rollingStock?.setNumber == "C")
        #expect(draft.rollingStock?.carCount == 2)
        #expect(draft.rollingStock?.cars?.map(\.number) == ["2", "1"])
        #expect(draft.rollingStock?.cars?.map(\.series) == ["キハ140", "キハ47"])

        let formation = try #require(try database.formation(for: trip))
        let blank = Train(id: "d", number: "", origin: "", destination: "", stops: [], region: "jp")
        let plain = trip.publishedStopsDraft(to: blank)
        let withStock = trip.publishedStopsDraft(to: blank, formation: formation)
        #expect(plain?.rollingStock == nil)
        #expect(withStock?.rollingStock == draft.rollingStock)
        #expect(withStock?.vehicleType == "キハ140")
        #expect(withStock?.stops == plain?.stops)

        let empty = TrainTimetableDatabase.rollingStockDraft(from: .init(
            id: "x", tripID: "t", serviceDate: "2026-09-30", evidenceKind: "planned", label: nil,
            carCount: nil, reservedSeatCapacity: 10, vehicleSeries: nil, allReserved: true,
            greenCarAvailable: nil, sourceID: "s", notes: nil, cars: []))
        #expect(empty == nil)
    }

    // MARK: nearby

    private static let places: [StationIndex.Place] = {
        let line = StationIndex.LineRef(
            name: "L", operatorName: nil, colorHex: nil)
        return StationIndex([
            .init(code: "A", name: "近駅", coordinate: Coordinate(lon: 139.7000, lat: 35.6800), line: line),
            .init(code: "B", name: "中駅", coordinate: Coordinate(lon: 139.7100, lat: 35.6800), line: line),
            .init(code: "C", name: "遠駅", coordinate: Coordinate(lon: 139.8000, lat: 35.6800), line: line),
        ]).all
    }()

    @Test func nearestRanksByHaversine() {
        let result = NearbyStations.nearest(to: 35.6800, lon: 139.7003, in: Self.places, limit: 2)
        #expect(result.map(\.place.code) == ["A", "B"])
        #expect(result[0].distanceMeters < 40)
        #expect(abs(result[1].distanceMeters - 880) < 40)
        #expect(NearbyStations.nearest(to: .nan, lon: 0, in: Self.places).isEmpty)
    }

    // MARK: inference

    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    @Test func nearbyThresholdsAndTouchedFields() {
        let near = [
            TripInference.NearbyStation(name: "近駅", code: "A", distanceMeters: 120),
            TripInference.NearbyStation(name: "中駅", code: "B", distanceMeters: 900),
            TripInference.NearbyStation(name: "遠駅", code: "C", distanceMeters: 4000),
        ]
        let proposals = TripInference.propose(signals: .init(now: now, region: "jp", nearby: near))
        let origins = proposals.filter { $0.field == .origin }
        #expect(origins.map(\.value) == ["近駅", "中駅"])
        #expect(origins.map(\.confidence) == [.high, .medium])
        #expect(origins.first?.stationCode == "A")
        #expect(proposals.contains { $0.field == .date && $0.source == .now })

        let medium = TripInference.propose(signals: .init(
            now: now, nearby: [.init(name: "中駅", distanceMeters: 300)]))
        #expect(medium.first { $0.field == .origin }?.confidence == .medium)

        let touched = TripInference.propose(signals: .init(
            now: now, nearby: near, touched: [.origin, .date]))
        #expect(touched.isEmpty)
    }

    @Test func ticketTimetableAndHistoryCombine() {
        let ticket = TicketReading(
            origin: "東京", destination: "新大阪", date: "2026-08-28", serviceName: "のぞみ",
            serviceNumber: "1", car: "7", seat: "５ Ａ", fare: 14720,
            confidence: [.seat: .low, .origin: .high])
        let match = TripInference.TimetableMatch(
            serviceName: "のぞみ", trainType: "新幹線", company: "JR東海",
            departureTime: "06:00", vehicleType: "N700S", setNumber: "G12", carCount: 16)
        let history = RideHistorySuggestions.suggestions(
            from: [Self.base(rollingStock: .init(livery: "X"))], origin: "東京", destination: "新大阪")
        let proposals = TripInference.propose(signals: .init(
            now: now, date: "2026-08-28", region: "jp", ticket: ticket, timetable: match,
            history: history, touched: [.company]))
        func first(_ field: TripInference.Field) -> TripInference.Proposal? {
            proposals.first { $0.field == field }
        }
        #expect(first(.seat)?.value == "5A" && first(.seat)?.confidence == .low)
        #expect(first(.currency)?.value == "JPY" && first(.currency)?.confidence == .medium)
        #expect(first(.fare)?.value == "14720")
        #expect(first(.vehicleType)?.source == .timetable && first(.vehicleType)?.confidence == .high)
        #expect(first(.company) == nil)
        #expect(first(.livery)?.source == .history && first(.livery)?.confidence == .medium)
        #expect(first(.origin)?.source == .ticket)
        #expect(first(.date)?.source == .ticket)
        // Sorted: confidence never increases down the list.
        #expect(zip(proposals, proposals.dropFirst()).allSatisfy { $0.confidence >= $1.confidence })
    }

    @Test func historyPrefersSameRouteThenLine() {
        func ride(_ id: String, _ from: String, _ to: String, type: String?, vehicle: String?,
                  line: String? = nil) -> Train {
            var train = Train(
                id: id, number: "n", trainType: type, vehicleType: vehicle,
                origin: from, destination: to, stops: [])
            if let line { train.routeSections = [RouteSection(lineNames: [line])] }
            return train
        }
        let trains = [
            ride("1", "A", "B", type: "特急", vehicle: "E657"),
            ride("2", "A", "B", type: "普通", vehicle: "E657"),
            ride("3", "A", "B", type: "普通", vehicle: nil),
            ride("4", "X", "Y", type: "快速", vehicle: "E233", line: "中央線"),
        ]
        let route = RideHistorySuggestions.suggestions(from: trains, origin: "A", destination: "B")
        #expect(route.first { $0.field == .trainType }?.value == "普通")
        #expect(route.first { $0.field == .trainType }?.count == 2)
        #expect(route.first { $0.field == .vehicleType }?.value == "E657")
        #expect(route.allSatisfy { $0.match == .sameRoute })
        let line = RideHistorySuggestions.suggestions(
            from: trains, origin: "Q", destination: "R", line: "中央線")
        #expect(line.map(\.value).sorted() == ["E233", "快速"])
        #expect(line.allSatisfy { $0.match == .sameLine })
        #expect(RideHistorySuggestions.suggestions(from: trains, origin: nil, destination: nil).isEmpty)
    }
}
