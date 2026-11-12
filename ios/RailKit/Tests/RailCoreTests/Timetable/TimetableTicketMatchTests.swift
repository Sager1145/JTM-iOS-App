import Foundation
import Testing
@testable import RailCore

@Suite("Ticket to timetable occurrence")
struct TimetableTicketMatchTests {
    private func akagi3() throws -> (TrainTimetableDatabase.Trip, [TrainTimetableDatabase.Trip]) {
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let trips = try database.trips(on: "2026-09-30")
        let trip = try #require(trips.first { $0.service.id == "akagi" && $0.publicNumber == "3" })
        return (trip, trips)
    }

    @Test func aPrintedSegmentFindsItsTrip() throws {
        let (trip, trips) = try akagi3()
        let calls = trip.passengerStops
        try #require(calls.count >= 4)
        let from = calls[1], to = calls[3]
        let minutes = 10 * 60
        let query = TimetableTicketMatch.Query(
            date: "2026-09-30", serviceName: trip.service.canonicalName, serviceNumber: "0003号",
            originCode: try #require(from.station.currentSourceCode),
            destinationCode: try #require(to.station.currentSourceCode),
            departureMinutes: minutes)
        #expect(TimetableTicketMatch.candidates(for: query, among: trips).map(\.id) == [trip.id])
    }

    @Test func aReversedStationsOrMissingServiceFindNothing() throws {
        let (trip, trips) = try akagi3()
        let calls = trip.passengerStops
        let from = try #require(calls[1].station.currentSourceCode)
        let to = try #require(calls[3].station.currentSourceCode)
        let minutes = 10 * 60
        let name = trip.service.canonicalName
        func run(_ q: TimetableTicketMatch.Query) -> [String] {
            TimetableTicketMatch.candidates(for: q, among: trips).map(\.id)
        }
        // A printed clock cannot rule out a trip whose database publishes no time.
        #expect(run(.init(date: "2026-09-30", serviceName: name, serviceNumber: "3",
                          originCode: from, destinationCode: to, departureMinutes: minutes + 1)).count == 1)
        #expect(run(.init(date: "2026-09-30", serviceName: name, serviceNumber: "3",
                          originCode: to, destinationCode: from)).isEmpty)
        #expect(run(.init(date: "2026-09-30", serviceName: nil, serviceNumber: nil,
                          originCode: from, destinationCode: to)).isEmpty)
        #expect(run(.init(date: "2026-09-29", serviceName: name, serviceNumber: "3",
                          originCode: from, destinationCode: to)).isEmpty)
    }

    @Test func numbersLoseSuffixAndLeadingZeros() {
        #expect(TimetableTicketMatch.normalizedNumber("0023号") == "23")
        #expect(TimetableTicketMatch.normalizedNumber("１２３次") == "123")
        #expect(TimetableTicketMatch.normalizedNumber("0") == "0")
        #expect(TimetableTicketMatch.normalizedNumber(" ") == nil)
        #expect(TimetableTicketMatch.normalizedNumber(nil) == nil)
    }
}
