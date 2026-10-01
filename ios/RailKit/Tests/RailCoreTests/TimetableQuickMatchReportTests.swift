import Foundation
import Testing
@testable import RailCore

@Suite("Report-backed timetable lookup")
struct TimetableQuickMatchReportTests {
    @Test func akagiExactDateTripsRetainPublishedStopsAndSources() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let trips = try database.trips(on: "2026-09-30")
            .filter { $0.service.id == "akagi" }
        #expect(Set(trips.compactMap(\.publicNumber)) == ["3", "6", "9"])
        #expect(Set(trips.map(\.passengerStops.count)) == [11, 12, 13])
        for trip in trips {
            #expect(!trip.canApplyToRouteEditor)
            #expect(try database.sources(for: trip).contains {
                $0.urlOrLocator.hasPrefix("https://timetables.jreast.co.jp/2610/train/")
            })
        }
        #expect(try database.trips(on: "2026-09-29")
            .allSatisfy { $0.service.id != "akagi" })
    }

    @Test func partialAzusaMatchKeepsSourceAndDraftBoundary() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let trips = try database.trips(on: "2026-09-27")
        let trip = try #require(trips.first { $0.service.id == "azusa" })
        let from = try #require(trip.origin)
        let to = try #require(trip.destination)
        let draft = Train(
            id: "lookup", date: "2026-09-27", number: "",
            origin: from.station.name, destination: to.station.name,
            stops: [
                Stop(name: from.station.name,
                     n02StationCode: from.station.currentSourceCode,
                     departure: from.departureTime, stopType: "origin"),
                Stop(name: to.station.name,
                     n02StationCode: to.station.currentSourceCode,
                     arrival: to.arrivalTime, stopType: "destination"),
            ], region: "jp")

        let matches = TimetableTripMatch.candidates(
            for: draft, serviceName: "あずさ", among: trips)
        #expect(matches.map(\.id).contains(trip.id))
        #expect(!trip.canApplyToRouteEditor)
        #expect(trip.applying(to: draft) == nil)
        let published = try #require(trip.publishedStopsDraft(to: draft))
        #expect(published.stops.count == trip.passengerStops.count)
        #expect(published.routeSections == nil)
        #expect(try database.sources(for: trip).contains {
            URL(string: $0.urlOrLocator)?.scheme == "https"
        })
    }
}
