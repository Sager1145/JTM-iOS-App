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
        // Built from the region clock's own wall-clock fields, so a daylight
        // saving change on `reference`'s day cannot move the shown time.
        let minutes = (TripNoteTime.minutes(time) ?? 0) % (24 * 60)
        var parts = clock.calendar.dateComponents([.year, .month, .day], from: reference)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return clock.calendar.date(from: parts) ?? reference
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
        guard let start = clock.instant(serviceDate: serviceDate, clock: "00:00"),
              let end = clock.instant(serviceDate: serviceDate,
                                      clock: TripNoteTime.text(minutes: TripNoteTime.maximumMinutes)),
              start <= end
        else { return nil }
        return start...end
    }

    // MARK: day of an undated trip

    /// The note time for a pick on a time-only picker. Dated trips are the
    /// plain picked time. Undated, the day is Day 2 (clock + 24 h) when the
    /// reader chose it by hand and it is still the day being edited, else
    /// Day 2 only when the picked clock is earlier than the departure's.
    static func time(forPicked instant: Date, serviceDate: String?, clock: RegionClock,
                     current: String?, dayChosenByHand: Bool, departureMinutes: Int?) -> String? {
        guard let picked = time(forPicked: instant, serviceDate: serviceDate, clock: clock,
                                carryingDayOf: dayChosenByHand ? current : nil) else { return nil }
        return undatedAware(picked, serviceDate: serviceDate, clock: clock,
                            dayChosenByHand: dayChosenByHand, departureMinutes: departureMinutes)
    }

    /// A suggested time for an undated trip with its automatic day applied; a
    /// dated trip's, or one the reader has set by hand, is returned as is.
    static func undatedAware(_ time: String, serviceDate: String?, clock: RegionClock,
                             dayChosenByHand: Bool, departureMinutes: Int?) -> String {
        guard pickerRange(serviceDate: serviceDate, clock: clock) == nil, !dayChosenByHand,
              let minutes = TripNoteTime.minutes(time) else { return time }
        return withDay(autoDay(forClockMinutes: minutes, departureMinutes: departureMinutes), of: time)
    }

    /// Whether an existing note's stored day is not the one a fresh pick of its
    /// clock would get on an undated trip, so it must count as the reader's.
    static func dayWasChosen(time: String?, serviceDate: String?, clock: RegionClock,
                             departureMinutes: Int?) -> Bool {
        guard pickerRange(serviceDate: serviceDate, clock: clock) == nil,
              let minutes = TripNoteTime.minutes(time) else { return false }
        return day(of: time) != autoDay(forClockMinutes: minutes, departureMinutes: departureMinutes)
    }

    /// 1 (Day 2) when the clock is earlier than the departure's, else 0.
    static func autoDay(forClockMinutes minutes: Int, departureMinutes: Int?) -> Int {
        guard let departureMinutes else { return 0 }
        return minutes % dayMinutes < departureMinutes % dayMinutes ? 1 : 0
    }

    /// The trip's departure clock in minutes: the first stop's departure,
    /// else its arrival, modulo a day.
    static func departureMinutes(of train: Train) -> Int? {
        guard let first = train.stops.first else { return nil }
        for text in [first.departure, first.arrival] {
            if let minutes = TripNoteTime.minutes(text) { return minutes % dayMinutes }
        }
        return nil
    }

    /// 0 for Day 1, 1 for Day 2 ("25:10").
    static func day(of time: String?) -> Int {
        (TripNoteTime.minutes(time) ?? 0) / dayMinutes
    }

    /// `time` with its clock kept and its day set (0 or 1).
    static func withDay(_ day: Int, of time: String?) -> String {
        let clock = (TripNoteTime.minutes(time) ?? 0) % dayMinutes
        return TripNoteTime.text(minutes: clock + min(max(day, 0), 1) * dayMinutes)
    }

    private static let dayMinutes = 24 * 60
}

/// "Add note" and "Change place" from the trip-details sheet: the sheet steps
/// aside, the main map picks, and the sheet comes back before the answer is
/// handed on. Each step waits for the one before it, so a sheet is never
/// presented while another is still leaving.
@MainActor
final class TripNoteDetailsStepAside {
    /// Closes the details sheet and calls back once it is gone.
    private let closeDetails: (@escaping @MainActor () -> Void) -> Void
    /// Starts the main-map pick; its callback hears the anchor or nil.
    private let startPick: (TripNoteAnchor?, @escaping (TripNoteAnchor?) -> Void) -> Void
    /// Presents the details sheet again and calls back once it is up.
    private let reopenDetails: (@escaping @MainActor () -> Void) -> Void
    private(set) var isActive = false
    /// Bumped by every run and by ``abandon()``: a step of a run that is no
    /// longer the current one does nothing.
    private var run = 0

    init(closeDetails: @escaping (@escaping @MainActor () -> Void) -> Void,
         startPick: @escaping (TripNoteAnchor?, @escaping (TripNoteAnchor?) -> Void) -> Void,
         reopenDetails: @escaping (@escaping @MainActor () -> Void) -> Void) {
        self.closeDetails = closeDetails
        self.startPick = startPick
        self.reopenDetails = reopenDetails
    }

    /// The flow's `pickPlace`: `finish` runs with the anchor (nil when
    /// cancelled) only after the details sheet is back. A second request while
    /// one runs is answered nil at once.
    func pick(initial: TripNoteAnchor?, finish: @escaping (TripNoteAnchor?) -> Void) {
        guard !isActive else { finish(nil); return }
        isActive = true
        run += 1
        let mine = run
        closeDetails { [self] in
            guard run == mine else { return }
            startPick(initial) { [self] anchor in
                guard run == mine else { return }
                reopenDetails { [self] in
                    guard run == mine else { return }
                    isActive = false
                    finish(anchor)
                }
            }
        }
    }

    /// The owner is going away, or a step never answered: drop the run in
    /// flight. Nothing it still has pending runs, and a new pick may start.
    func abandon() {
        run += 1
        isActive = false
    }
}
