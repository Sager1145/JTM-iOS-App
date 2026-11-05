import Foundation
import RailCore

/// What the editor's header fields showed when the draft opened.
///
/// A saved journey keeps every value the reader leaves alone: a field is
/// written back only when it differs from its seed. A new trip writes them all.
struct EditorSeed: Equatable {
    var trainType: String
    var number: String
    var company: String
    var departure: Date
    var arrival: Date
    /// The saved journey carried this clock. A placeholder clock is never written back.
    var departureKnown: Bool
    var arrivalKnown: Bool

    init(train: Train, isNew: Bool, now: Date = Date()) {
        let type = train.trainType ?? ""
        if isNew {
            trainType = JourneyDraftWork.serviceTypeIDs.contains(type) ? type : "local"
            number = ""
            company = ""
            departure = now
            arrival = now
            departureKnown = false
            arrivalKnown = false
            return
        }
        trainType = type
        number = train.number
        company = train.company ?? ""
        let day = Dates.normalizeDateString(train.date)
        let start = day.flatMap { Self.date(day: $0, time: "00:00") }
        let leaving = day.flatMap { day in
            train.stops.first?.departure.flatMap { Self.date(day: day, time: $0) }
        }
        let arriving = day.flatMap { day in
            train.stops.last?.arrival.flatMap { Self.date(day: day, time: $0) }
        }
        departure = leaving ?? start ?? now
        arrival = max(arriving ?? departure, departure)
        departureKnown = leaving != nil
        arrivalKnown = arriving != nil
    }

    /// A service day plus a clock that may run past 24:00.
    static func date(day: String, time: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let parts = time.split(separator: ":")
        guard let date = formatter.date(from: day), parts.count >= 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        let serviceDay = calendar.startOfDay(for: date)
        guard let civilDay = calendar.date(byAdding: .day, value: hours / 24, to: serviceDay) else {
            return nil
        }
        return calendar.date(
            bySettingHour: hours % 24, minute: minutes, second: 0, of: civilDay)
    }
}
