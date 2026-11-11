import Foundation

/// Matches a rider's two station calls to published occurrences on the service day.
/// The bundled database is stops-only, so a match rests on the service name or
/// number, the service day and both endpoint stations. A clock time the rider
/// recorded is compared only against a published time that exists; an absent
/// published time never counts for or against a trip, and one is never invented.
public enum TimetableTripMatch {
    public static func candidates(
        for train: Train,
        serviceName: String = "",
        among trips: [TrainTimetableDatabase.Trip]
    ) -> [TrainTimetableDatabase.Trip] {
        guard TrainTimetableDatabase.accepts(train), train.stops.count >= 2,
              let fromCode = train.stops.first?.n02StationCode,
              let toCode = train.stops.last?.n02StationCode
        else { return [] }

        let serviceName = (serviceName.isEmpty ? train.number : serviceName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Without a time to tell trains apart, two endpoints alone name no train.
        guard !serviceName.isEmpty else { return [] }
        let departure = train.stops.first?.departure.flatMap(Dates.parseTimeToMinutes)
        let arrival = train.stops.last?.arrival.flatMap(Dates.parseTimeToMinutes)
        return trips.filter { trip in
            guard trip.timetableCompleteness != .conflict,
                  trip.passengerStops.count >= 2,
                  train.date == trip.serviceDate,
                  matchesService(serviceName, trip: trip)
            else { return false }
            // The editor's `applying` operation installs the whole trip. Match
            // its endpoints so a rider's shorter segment is never expanded.
            guard let from = trip.origin, let to = trip.destination else { return false }
            guard from.station.currentSourceCode == fromCode,
                  to.station.currentSourceCode == toCode else { return false }
            if let departure, let published = from.departureSeconds, Double(published) / 60 != departure {
                return false
            }
            if let arrival, let published = to.arrivalSeconds, Double(published) / 60 != arrival {
                return false
            }
            return true
        }
    }

    /// The physical matcher's labels, plus a name followed by any trailing text.
    private static func matchesService(_ input: String, trip: TrainTimetableDatabase.Trip) -> Bool {
        if TimetablePhysicalRouteMatch.matchesService(input, trip: trip) { return true }
        let names = [trip.service.canonicalName, trip.service.englishName,
                     trip.trainNumber, trip.publicNumber]
            .compactMap { $0?.lowercased() }
        let query = input.lowercased()
        return names.contains { query.hasPrefix($0 + " ") }
    }
}
