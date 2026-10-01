import Foundation

/// Matches a rider's two timed station calls to published occurrences on the service day.
/// Names alone are not sufficient: station identity and both clock times must agree.
public enum TimetableTripMatch {
    public static func candidates(
        for train: Train,
        serviceName: String = "",
        among trips: [TrainTimetableDatabase.Trip]
    ) -> [TrainTimetableDatabase.Trip] {
        guard train.stops.count >= 2,
              let fromCode = train.stops.first?.n02StationCode,
              let toCode = train.stops.last?.n02StationCode,
              let departure = train.stops.first?.departure.flatMap(Dates.parseTimeToMinutes),
              let arrival = train.stops.last?.arrival.flatMap(Dates.parseTimeToMinutes)
        else { return [] }

        let serviceName = (serviceName.isEmpty ? train.number : serviceName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trips.filter { trip in
            guard trip.timetableCompleteness != .conflict,
                  trip.passengerStops.count >= 2,
                  train.date == trip.serviceDate,
                  serviceName.isEmpty || matchesService(serviceName, trip: trip)
            else { return false }
            // The editor's `applying` operation installs the whole trip. Match
            // its endpoints so a rider's shorter segment is never expanded.
            guard let from = trip.origin, let to = trip.destination else { return false }
            return from.station.currentSourceCode == fromCode
                && from.departureSeconds.map { Double($0) / 60 == departure } == true
                && to.station.currentSourceCode == toCode
                && to.arrivalSeconds.map { Double($0) / 60 == arrival } == true
        }
    }

    private static func matchesService(_ input: String, trip: TrainTimetableDatabase.Trip) -> Bool {
        let names = [trip.service.canonicalName, trip.service.englishName,
                     trip.trainNumber, trip.publicNumber]
            .compactMap { $0?.lowercased() }
        let query = input.lowercased()
        return names.contains { $0 == query }
            || names.contains { query.hasPrefix($0 + " ") }
    }
}
