import Foundation

extension TicketDate {
    /// `YYYY-MM-DD`. A ticket without a year is read as the latest such day
    /// no more than `aheadDays` after `now`: a ride log scans mostly used
    /// tickets, and an advance ticket is bought at most a few weeks ahead
    /// (JR sells a month ahead). Last December's ticket scanned in January
    /// stays last year; a ticket for next week stays this year.
    public func dayString(
        near now: Date, aheadDays: Int = 45, calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String? {
        var calendar = calendar
        calendar.timeZone = .current
        let thisYear = calendar.component(.year, from: now)
        let years = year.map { [$0] } ?? [thisYear - 1, thisYear, thisYear + 1]
        let candidates = years.compactMap { year -> (Int, Date)? in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day else { return nil }
            return (year, date)
        }
        let limit = calendar.date(byAdding: .day, value: aheadDays, to: now) ?? now
        let notTooFar = candidates.filter { $0.1 <= limit }
        guard let best = notTooFar.max(by: { $0.1 < $1.1 }) ?? candidates.min(by: { $0.1 < $1.1 })
        else { return nil }
        return String(format: "%04d-%02d-%02d", best.0, month, day)
    }
}

extension Ticket {
    /// The stored ticket facts of a reading. The reading's fare is in ISO 4217
    /// minor units (NT$1,490 is 149000); the store keeps whole units as
    /// printed (1490). Nil when the reading has none of these facts.
    public init?(reading: TicketReadingResult) {
        let currency = reading.currency?.value.uppercased()
        let fare = reading.fare.map { field -> Int in
            let exponent = Self.minorUnitExponent(currency ?? "")
            var divisor = 1
            for _ in 0..<exponent { divisor *= 10 }
            return field.value / divisor
        }
        self.init(
            seat: Self.normalizedSeat(reading.seat?.value),
            seatClass: reading.seatClass?.value,
            fare: fare,
            currency: fare == nil ? nil : currency,
            kind: reading.kind?.value.rawValue)
        if isEmpty { return nil }
    }

    /// ISO 4217 minor-unit digits for the currencies a ticket can carry.
    static func minorUnitExponent(_ code: String) -> Int {
        switch code {
        case "TWD", "HKD", "MOP", "CNY": 2
        default: 0
        }
    }
}
