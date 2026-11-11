import Foundation

/// Finds the published occurrence a paper ticket describes. A ticket names
/// the service (のぞみ 23号), the day and the two stations of the ride, and
/// often the departure clock; it never prints the arrival, so the two-clock
/// ``TimetableTripMatch`` cannot be used. The ride may be any part of the
/// trip: both stations must be passenger calls, in order. A printed
/// departure must equal a published departure at the first call when one is
/// published; the bundled database is stops-only, so it then matches by name or
/// number, day and stations alone.
public enum TimetableTicketMatch {
    public struct Query: Sendable, Equatable {
        public var date: String
        public var serviceName: String?
        public var serviceNumber: String?
        public var originCode: String
        public var destinationCode: String
        /// Minutes after midnight of the printed departure, folded into one day.
        public var departureMinutes: Int?

        public init(
            date: String, serviceName: String?, serviceNumber: String?,
            originCode: String, destinationCode: String, departureMinutes: Int? = nil
        ) {
            self.date = date
            self.serviceName = serviceName
            self.serviceNumber = serviceNumber
            self.originCode = originCode
            self.destinationCode = destinationCode
            self.departureMinutes = departureMinutes
        }
    }

    /// Trips that fit every printed fact. Without a service name or number the
    /// ticket does not identify one train, so nothing is returned.
    public static func candidates(
        for query: Query, among trips: [TrainTimetableDatabase.Trip]
    ) -> [TrainTimetableDatabase.Trip] {
        let name = query.serviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let number = normalizedNumber(query.serviceNumber)
        guard !name.isEmpty || number != nil, query.originCode != query.destinationCode else { return [] }
        let label = [name, number ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return trips.filter { trip in
            guard trip.serviceDate == query.date, trip.timetableCompleteness != .conflict else { return false }
            if !TimetablePhysicalRouteMatch.matchesService(label, trip: trip) {
                // A number alone must equal the public or operating number.
                guard name.isEmpty, let number,
                      [trip.publicNumber, trip.trainNumber].contains(where: { normalizedNumber($0) == number })
                else { return false }
            }
            let calls = trip.passengerStops
            guard let from = calls.firstIndex(where: { $0.station.currentSourceCode == query.originCode }),
                  calls[(from + 1)...].contains(where: { $0.station.currentSourceCode == query.destinationCode })
            else { return false }
            // The bundled database stores no times, so the printed departure can
            // only rule a trip out when this database publishes one.
            if let minutes = query.departureMinutes, let seconds = calls[from].departureSeconds {
                guard (seconds / 60) % 1440 == minutes % 1440 else { return false }
            }
            return true
        }
    }

    /// The printed number without its suffix or leading zeros ("0023号" is "23").
    static func normalizedNumber(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let folded = (raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "号號次호"))
        let trimmed = folded.drop { $0 == "0" }
        let value = trimmed.isEmpty && !folded.isEmpty ? "0" : String(trimmed)
        return value.isEmpty ? nil : value
    }
}
