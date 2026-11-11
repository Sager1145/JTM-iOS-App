//
//  TripListRules.swift — which journey list a trip is filed under, and
//  whether an upcoming trip's time has already gone by.
//

import Foundation
import RailCore

/// The Upcoming list's membership rules.
///
/// A trip is filed once, when it is added: a trip whose departure is still
/// ahead is upcoming, anything else is past. That answer is stored on the
/// record (``RailCore/TripListMembership``) and passing time never changes
/// it. An upcoming trip whose end has gone by is *overdue*: it stays in the
/// Upcoming list, marked, until the reader moves it, edits it or deletes it.
///
/// Records written before the field existed carry no membership and keep the
/// date rule: upcoming while their date is today or later in their region.
///
/// A trip whose clocks nobody set (``RailCore/Train/listByDate``: the editor's
/// placeholder time, not the reader's, a timetable's or a ticket's) is read as
/// a date only: filed upcoming while its date is today or later, overdue only
/// once its date has ended.
///
/// An observed clock (`actual_departure` / `actual_arrival`) outranks the
/// scheduled one: it is when the ride really started or ended, and the reader
/// typed it, so it counts even on a trip filed by its date alone.
///
/// Times are the record's own clock strings read on the region's clock.
/// `25:10` and `01:10+1` both mean the next day, exactly as
/// ``RailCore/Dates/parseTimeToMinutes(_:)`` reads them for the map.
public enum TripListRules {

    /// The list a newly added trip belongs to, decided at `now`.
    ///
    /// The trip's start is its first departure, else its first arrival, else
    /// the end of its date. A trip with no usable date is past: it has no
    /// position on a calendar to be ahead of.
    public static func initialMembership(
        for train: Train, clock: RegionClock, now: Date
    ) -> TripListMembership {
        guard let start = start(of: train, clock: clock) else { return .past }
        return start > now ? .upcoming : .past
    }

    /// The list a trip with this date and first clock would be filed under at
    /// `now` — the same rule as ``initialMembership(for:clock:now:)``, for a
    /// draft that is not a record yet. A nil `startClock` is a date only.
    public static func initialMembership(
        date: String?, startClock: String?, clock: RegionClock, now: Date
    ) -> TripListMembership {
        guard let day = clock.startOfDay(date) else { return .past }
        let start = Dates.parseTimeToMinutes(startClock).map { day.addingTimeInterval($0 * 60) }
            ?? endOfDay(day, clock: clock)
        return start > now ? .upcoming : .past
    }

    /// Whether the trip is listed under Upcoming.
    ///
    /// - Parameter today: the trip region's today, `YYYY-MM-DD`. Read only for
    ///   a record without a stored membership.
    public static func isUpcoming(_ train: Train, today: String?) -> Bool {
        switch train.listMembership {
        case .upcoming: return true
        case .past: return false
        case nil:
            guard let date = Dates.normalizeDateString(train.date), let today else { return false }
            return date >= today
        }
    }

    /// Whether an upcoming trip's time has already gone by.
    ///
    /// Only an upcoming trip can be overdue. Its end is its last arrival, else
    /// its last departure, else the end of its date; an undated trip has no end
    /// and is never overdue.
    public static func isOverdue(
        _ train: Train, clock: RegionClock, now: Date
    ) -> Bool {
        guard isUpcoming(train, today: clock.today(at: now)),
            let end = end(of: train, clock: clock)
        else { return false }
        return end <= now
    }

    /// The instant the trip starts: the boarding stop's actual departure, else first
    /// departure, else first arrival, else the end of its date.
    public static func start(of train: Train, clock: RegionClock) -> Date? {
        guard let day = clock.startOfDay(train.date) else { return nil }
        guard let start = actualStart(train) ?? scheduledStart(train) else { return endOfDay(day, clock: clock) }
        return day.addingTimeInterval(start * 60)
    }

    /// The instant the trip ends: the alighting stop's actual arrival, else last arrival,
    /// else last departure, else the end of its date.
    ///
    /// A record whose last time reads earlier than its first without a
    /// next-day spelling (`23:40` to `00:20`) is read as running past midnight,
    /// so its end is never before its start. Each kind's end wraps against
    /// the same kind's start (an actual end falls back to the scheduled
    /// start); the chosen end is then never before the chosen start.
    public static func end(of train: Train, clock: RegionClock) -> Date? {
        guard let day = clock.startOfDay(train.date) else { return nil }
        let scheduledFrom = scheduledStart(train)
        let actualFrom = actualStart(train)
        func wrapped(_ end: Double?, against start: Double?) -> Double? {
            guard var end else { return nil }
            if let start { while end < start { end += 1440 } }
            return end
        }
        guard var minutes = wrapped(actualEnd(train), against: actualFrom ?? scheduledFrom)
            ?? wrapped(scheduledEnd(train), against: scheduledFrom) else {
            return endOfDay(day, clock: clock)
        }
        if let start = actualFrom ?? scheduledFrom { minutes = max(minutes, start) }
        return day.addingTimeInterval(minutes * 60)
    }

    // MARK: - clock strings

    private static func actualStart(_ train: Train) -> Double? {
        guard let boarding = train.boardingStopIndex else { return nil }
        return Dates.parseTimeToMinutes(train.stops[boarding].actualDeparture)
    }

    private static func scheduledStart(_ train: Train) -> Double? {
        guard train.listByDate != true else { return nil }
        if let boarding = train.boardingStopIndex,
            let minutes = Dates.parseTimeToMinutes(train.stops[boarding].departure)
        {
            return minutes
        }
        for stop in train.stops {
            if let minutes = Dates.parseTimeToMinutes(stop.departure) { return minutes }
        }
        for stop in train.stops {
            if let minutes = Dates.parseTimeToMinutes(stop.arrival) { return minutes }
        }
        return nil
    }

    private static func actualEnd(_ train: Train) -> Double? {
        guard let alighting = train.alightingStopIndex else { return nil }
        return Dates.parseTimeToMinutes(train.stops[alighting].actualArrival)
    }

    private static func scheduledEnd(_ train: Train) -> Double? {
        guard train.listByDate != true else { return nil }
        if let alighting = train.alightingStopIndex,
            let minutes = Dates.parseTimeToMinutes(train.stops[alighting].arrival)
        {
            return minutes
        }
        for stop in train.stops.reversed() {
            if let minutes = Dates.parseTimeToMinutes(stop.arrival) { return minutes }
        }
        for stop in train.stops.reversed() {
            if let minutes = Dates.parseTimeToMinutes(stop.departure) { return minutes }
        }
        return nil
    }

    private static func endOfDay(_ day: Date, clock: RegionClock) -> Date {
        clock.calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    }
}
