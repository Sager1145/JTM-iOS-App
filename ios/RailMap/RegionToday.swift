import Foundation
import RailCore
import RailPresentation

/// Today, on each of the five clocks — one answer for the whole app.
///
/// ## What this is, and what it is deliberately not
///
/// It answers "what day is it where this journey is", which the Upcoming
/// destination (§5.1) is built on: a Tokyo ride dated 2026-08-27 stopped being
/// ahead of the reader when Japan reached the 28th, not when London did six
/// hours later.
///
/// It does **not** answer "has this journey been ridden". That was tried and
/// it was wrong: a date is a plan, not an attendance record, so the app would
/// have written kilometres into the passport for a trip that was cancelled,
/// moved or simply never taken, on a day the reader did not open it. What is
/// counted is a stated fact on the record — see
/// ``RailPresentation/RideLedger`` — and nothing here is consulted about it.
///
/// ## Why it is held for a second
///
/// Building five `Calendar`s and reading five zones is not free, and this is
/// asked on paths that run once per body evaluation. A second rather than
/// until midnight, and the difference shows only at midnight: being at most
/// one second late to notice a day has turned is not something a reader can
/// observe, and a sheet drag that rebuilt five calendars per frame very much
/// was.
///
/// One `Date()` still serves all five regions within a call, which is the
/// property this was written for: two journeys in one region must not land on
/// different days by being asked a millisecond apart.
@MainActor
enum RegionToday {

    private static var value: [Region: String] = [:]
    private static var asOf = Date.distantPast

    static func byRegion() -> [Region: String] {
        let now = Date()
        if now.timeIntervalSince(asOf) < 1, !value.isEmpty { return value }
        var today: [Region: String] = [:]
        for region in Region.allCases {
            today[region] = RecordDate.today(in: region.clock, at: now)
        }
        value = today
        asOf = now
        return today
    }
}
