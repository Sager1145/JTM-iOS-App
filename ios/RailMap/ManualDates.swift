import Foundation
import RailCore

/// The dates the reader typed in themselves, and their persistence.
///
/// A journey's date comes from its record. These do not: they are days the
/// reader intends to travel and has not logged anything for yet, added so the
/// date filter has something to point at while a trip is still being planned.
/// `Dates.availableDates` merges the two.
///
/// ## Why this is a type and not three `@State`s
///
/// It was an array, a `UserDefaults` key spelled by a private function, and
/// three more functions that loaded, appended and pruned it — five members of
/// `RailWorkspaceView` that only ever spoke to each other, scattered between a
/// menu three hundred lines up and a `.task` three hundred down. Nothing named
/// the rule they share: **every change to the list is written to disk in the
/// same statement that makes it**, which is the whole of why a typed date
/// survives a relaunch.
///
/// The text being typed is deliberately NOT here. That is one alert's transient
/// state, it is bound to a `TextField`, and it has no meaning once the alert
/// closes — it stays `@State` on the view, where SwiftUI can own it.
@MainActor
@Observable
final class ManualDates {

    /// Read-only from outside: the two mutations below are the only ones that
    /// keep the list and the disk in step.
    private(set) var dates: [String] = []

    var isEmpty: Bool { dates.isEmpty }

    private static let key = "manual-dates"

    /// Restore what the reader typed in a previous session.
    func load() {
        dates = (UserDefaults.standard.array(forKey: Self.key) as? [String]) ?? []
    }

    /// Add a typed date, if it is one.
    ///
    /// Returns the normalised spelling so the caller can select it — the point
    /// of adding a date is to look at it, and `Dates.normalizeDateString` is
    /// what decides whether "2026-8-9" and "2026-08-09" are the same day.
    /// `nil` means the text was not a date and nothing changed.
    @discardableResult
    func add(_ typed: String) -> String? {
        guard let normalized = Dates.normalizeDateString(typed) else { return nil }
        if !dates.contains(normalized) { dates.append(normalized) }
        persist()
        return normalized
    }

    /// Drop every typed date that no journey ended up on.
    ///
    /// The reader's own "remove empty dates": a date added for a trip that was
    /// never logged is clutter in a menu, but only the caller knows which dates
    /// the records actually occupy.
    func prune(keeping used: Set<String>) {
        dates.removeAll { !used.contains($0) }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(dates, forKey: Self.key)
    }
}
