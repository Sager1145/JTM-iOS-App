import Foundation
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
/// ## Two different zones live in this file, and the difference is the point
///
/// **"What day is it?" is a question about a place.** A journey belongs to a
/// region, and the day it is on is the day it is there — so ``today(in:)`` and
/// ``todayParts(in:)`` take the ride's ``RegionClock`` and are the only way to
/// ask. Reading the device's clock instead was wrong for every reader not
/// standing in the region: a Tokyo journey dated 2026-08-27 was still listed
/// as upcoming at 19:00 in London, six hours after the 28th had begun in Japan.
///
/// **A `Date` handed to a `DatePicker` is not an instant, it is a carrier for
/// a civil date**, and it is built and read back through the *device's*
/// calendar — ``date(from:)`` and ``text(from:)`` — because that is the
/// calendar the picker itself draws. The two conversions are exact inverses on
/// the same zone, so the day the reader taps is the day that reaches the
/// record, whatever zone the device is in and wherever the journey is. Pinning
/// these to a region's zone instead would make the picker show one day and
/// store another for anyone west of it.
///
/// The seam between them is the seed: ``date(from:)`` is handed the parts
/// ``todayParts(in:)`` produced, so the picker opens on the ride's today while
/// still being read in the reader's own calendar.
enum RecordDate {

    /// The calendar a record date is carried through on this device.
    ///
    /// Gregorian by name rather than `Calendar.current`: a reader whose device
    /// is set to the Japanese or the Buddhist calendar still stores
    /// `2026-08-28`, because that is what the file format says — jsonspec's
    /// `date` is not a localized string. The time zone is the device's, for
    /// the reason the type's note gives: this is the picker's own calendar,
    /// not an answer about where a train is.
    private static var carrierCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    // MARK: - the picker's carrier

    /// `YYYY-MM-DD`, the only spelling a record's `date` takes.
    static func text(from date: Date) -> String {
        let parts = carrierCalendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A record's date as a `Date`, for the pickers that need one.
    static func date(from text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return carrierCalendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The same, from three numbers that are already known to be a day.
    static func date(from parts: (year: Int, month: Int, day: Int)) -> Date {
        carrierCalendar.date(
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
