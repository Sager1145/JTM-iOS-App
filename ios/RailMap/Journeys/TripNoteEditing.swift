import Foundation
import RailCore

/// The pure rules behind the trip-note form, kept out of the view so they can
/// be tested without one.
enum TripNoteEditing {
    /// Width- and case-insensitive key: fullwidth Latin folds to halfwidth and
    /// letters to one case, so "Ｉncident" and "incident" collide.
    static func foldedKey(_ category: String) -> String {
        category.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.widthInsensitive, .caseInsensitive], locale: nil)
    }

    /// What to store for `typed`: an existing spelling when one equals it
    /// ignoring case and width, otherwise the typed text itself (trimmed at
    /// the ends). Run on save only, never per keystroke, so IME composition
    /// is untouched.
    static func canonicalCategory(_ typed: String, existing: [String]) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let key = foldedKey(trimmed)
        return existing.first { foldedKey($0) == key } ?? trimmed
    }

    /// The chips to show while `typed` is in the field: every suggestion
    /// containing it (folded), or all of them when it is empty.
    static func filteredSuggestions(_ suggestions: [String], typed: String) -> [String] {
        let key = foldedKey(typed)
        guard !key.isEmpty else { return suggestions }
        return suggestions.filter { foldedKey($0).contains(key) }
    }

    /// The instant a date picker pinned to `clock` should show for `time`.
    /// With no service date the picker is time-only, so `reference` (any
    /// instant on the day to show) supplies the civil day.
    static func pickerInstant(serviceDate: String?, time: String?, clock: RegionClock,
                              reference: Date) -> Date {
        if let exact = TripNoteTime.instant(serviceDate: serviceDate, time: time, clock: clock) {
            return exact
        }
        // A time-only picker shows a time of day: "25:10" reads 01:10 there.
        let minutes = (TripNoteTime.minutes(time) ?? 0) % (24 * 60)
        let start = clock.calendar.startOfDay(for: reference)
        return clock.calendar.date(byAdding: .minute, value: minutes, to: start) ?? reference
    }

    /// The stored time for what the picker now shows; nil outside the window.
    ///
    /// Without a service date the picker only knows a time of day, so the
    /// day part of the time being edited ("25:10" is day 1) is carried onto
    /// the picked time rather than dropped.
    static func time(forPicked instant: Date, serviceDate: String?, clock: RegionClock,
                     carryingDayOf current: String? = nil) -> String? {
        guard let picked = TripNoteTime.time(at: instant, serviceDate: serviceDate, clock: clock)
        else { return nil }
        guard serviceDate == nil || clock.startOfDay(serviceDate) == nil,
              let day = TripNoteTime.display(current)?.dayOffset, day > 0,
              let minutes = TripNoteTime.minutes(picked),
              minutes + day * 24 * 60 <= TripNoteTime.maximumMinutes else { return picked }
        return TripNoteTime.text(minutes: minutes + day * 24 * 60)
    }

    /// 00:00 on the service date to 47:59 after it; nil without a date.
    static func pickerRange(serviceDate: String?, clock: RegionClock) -> ClosedRange<Date>? {
        guard let start = clock.startOfDay(serviceDate),
              let end = clock.calendar.date(byAdding: .minute, value: TripNoteTime.maximumMinutes, to: start)
        else { return nil }
        return start...end
    }
}
