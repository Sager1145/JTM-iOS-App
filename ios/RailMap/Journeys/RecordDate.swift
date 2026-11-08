import Foundation
import RailCore
import RailPresentation

/// Today, and the spelling a record's `date` field takes.
///
/// Deliberately not in `RailCore`. That module is pure and checked against
/// recorded fixtures, and a function whose answer depends on when it is called
/// can be neither — "what is today" is the app's question, not the ported
/// logic's.
///
/// One owner because there used to be five copies of the same three lines:
/// the journeys workspace had one and the screenshot importer had four, and
/// each built its own `Calendar(identifier: .gregorian)`, set its own time
/// zone and spelled its own `%04d-%02d-%02d`. Both files' documentation
/// already pointed at the *other* one as the reason it was written that way,
/// which is the shape of a thing that wants a single home. Five calendars is
/// five places for a time zone to drift, and a record dated a day out is a
/// journey that leaves the day it belongs to.
///
/// ## One zone, the ride's
///
/// **"What day is it?" is a question about a place.** A journey belongs to a
/// region, and the day it is on is the day it is there — so ``today(in:)`` and
/// ``todayParts(in:)`` take the ride's ``RegionClock`` and are the only way to
/// ask. Reading the device's clock instead was wrong for every reader not
/// standing in the region: a Tokyo journey dated 2026-08-27 was still listed
/// as upcoming at 19:00 in London, six hours after the 28th had begun in Japan.
///
/// **A `Date` handed to a `DatePicker` is a real instant read on the region's
/// calendar.** ``date(from:in:)`` and ``text(from:in:)`` build and read it
/// through that same calendar (Gregorian, the region's zone), and every picker
/// is pinned to it with `.environment(\.timeZone, clock.timeZone)` and
/// `.environment(\.calendar, clock.calendar)`. The picker therefore draws the
/// wall clock that is stored, whatever zone or calendar the device is set to,
/// and the day the reader taps is the day that reaches the record. The device's
/// zone is never consulted.
enum RecordDate {

    // MARK: - the picker's carrier

    /// `YYYY-MM-DD`, the only spelling a record's `date` takes.
    static func text(from date: Date, in clock: RegionClock) -> String {
        clock.civilDate(of: date)
    }

    /// A record's date as a `Date`, for the pickers that need one.
    static func date(from text: String, in clock: RegionClock) -> Date? {
        clock.startOfDay(text)
    }

    /// The same, from three numbers that are already known to be a day.
    static func date(from parts: (year: Int, month: Int, day: Int), in clock: RegionClock) -> Date {
        clock.calendar.date(
            from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? Date()
    }

    // MARK: - what day it is where the train is

    /// Today on one region's clock, spelled the way a record spells a date.
    ///
    /// `now` is a parameter so that a caller asking about several regions at
    /// once asks about ONE instant. Five separate `Date()` calls straddling
    /// midnight would put two rides in the same region on different days.
    static func today(in clock: RegionClock, at now: Date = Date()) -> String {
        clock.today(at: now)
    }

    /// Today on one region's clock, as three numbers, for the rules that
    /// reason about a calendar day rather than about a string —
    /// `TransferGuide.calendarDate` resolving the year a screenshot does not
    /// print.
    static func todayParts(
        in clock: RegionClock, at now: Date = Date()
    ) -> (year: Int, month: Int, day: Int) {
        clock.components(at: now)
    }
}
