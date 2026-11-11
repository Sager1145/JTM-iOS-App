import Testing

@testable import RailCore

struct ActualDepartureSortTests {
    private static func train(_ id: String, departure: String, actual: String? = nil) -> Train {
        Train(
            id: id, date: "2026-08-27", number: id, origin: "A", destination: "B",
            stops: [
                Stop(
                    name: "A", departure: departure, actualDeparture: actual,
                    stopType: "origin", rideSegment: true),
                Stop(name: "B", arrival: "23:00", stopType: "destination", rideSegment: true),
            ])
    }

    @Test("sorting uses the boarding stop's actual departure when present")
    func sortsByActual() {
        let early = Self.train("early", departure: "09:00", actual: "12:00")
        let late = Self.train("late", departure: "10:00")
        #expect(Dates.sortByDateAndDeparture([early, late]).map(\.id) == ["late", "early"])
        #expect(Dates.departureMinutes(of: early) == 720)
    }

    /// Stops 0...4 with a mid-train ride 1 -> 3, scheduled 08:00 + 10 min per stop.
    static func midTrain(types: Bool) -> Train {
        var stops = (0..<5).map { index -> Stop in
            var stop = Stop(name: "S\(index)")
            stop.departure = String(format: "%02d:%02d", 8, index * 10)
            stop.arrival = String(format: "%02d:%02d", 8, index * 10)
            stop.rideSegment = (1...3).contains(index)
            return stop
        }
        if types { stops[1].stopType = "origin"; stops[3].stopType = "destination" }
        return Train(id: "mid", date: "2026-08-27", number: "1", origin: "S1", destination: "S3", stops: stops)
    }

    @Test("a mid-train boarding is the origin stop; alighting the destination stop")
    func midTrainIndexes() {
        let train = Self.midTrain(types: true)
        #expect(train.boardingStopIndex == 1)
        #expect(train.alightingStopIndex == 3)
    }

    @Test("an import without origin/destination types uses the rideSegment ends")
    func untypedImportUsesRideSegment() {
        var train = Self.midTrain(types: false)
        for index in 0..<5 { train.stops[index].rideSegment = (2...4).contains(index) }
        #expect(train.boardingStopIndex == 2)
        #expect(train.alightingStopIndex == 4)
        #expect(Dates.departureMinutes(of: train) == 8 * 60 + 20)
    }

    @Test("a single-stop train has a boarding stop but nowhere to alight")
    func singleStop() {
        let one = Train(
            id: "one", date: "2026-08-27", number: "1", origin: "A", destination: "A",
            stops: [Stop(name: "A")])
        #expect(one.boardingStopIndex == 0)
        #expect(one.alightingStopIndex == nil)
    }

    @Test("the sort key uses the boarding stop's actual, then its scheduled departure")
    func midTrainSortKey() {
        var train = Self.midTrain(types: true)
        #expect(Dates.departureMinutes(of: train) == 8 * 60 + 10)
        train.stops[1].actualDeparture = "09:30"
        #expect(Dates.departureMinutes(of: train) == 9 * 60 + 30)
    }
}
