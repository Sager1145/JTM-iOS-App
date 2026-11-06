import Foundation

// MARK: - one journey's clock

/// The clock ONE journey's dates and printed times are on.
///
/// One clock for a journey that stays in one zone, and a table of them for a
/// journey that does not. Either way every caller that asks a journey what
/// time it is goes through this type, which is what let cross-zone support be
/// a change to this file rather than to every call site.
///
/// ## When a journey has more than one clock
///
/// The five Asian networks do not touch each other and each is one zone from
/// end to end, so a ride in any of them has one clock and ``stops`` is empty.
///
/// Clock offsets and region package membership are separate questions.
/// The app only loads the five supported regional packages.
///
/// ## What the table changes, and what it deliberately does not
///
/// It changes three answers here — ``clock(atStopIndex:)``,
/// ``crossesTimeZones`` and ``offsetMinutes(fromStopIndex:toStopIndex:on:)`` —
/// and `Statistics.trainRideMinutes(_:clock:)` applies that offset to the
/// ride duration, between the first and last effectively ridden stops. The
/// plain `Statistics.trainRideMinutes(_:)` stays the JavaScript port; with no
/// per-stop table the zone-aware form equals it exactly, which is all the
/// JavaScript parity constraint requires (the JavaScript has no zones).
///
/// Nothing else changes. In particular the stop times themselves stay exactly
/// as the reader wrote them down — `25:10` is a business fact about an
/// overnight service, and converting a printed time between zones would be
/// the app rewriting the timetable. A stop says which clock it is on; it is
/// never restated in another.
public struct JourneyClock: Sendable, Hashable {

    /// The clock the journey as a whole is dated on.
    ///
    /// The ORIGIN's, when the journey carries a per-stop table — a record's
    /// `date` is the day it departed, and the day it departed is a fact about
    /// where it departed from. A journey with no table answers its region's.
    public let home: RegionClock

    /// The clock each stop prints its times on, in stop order.
    ///
    /// Empty for a journey that has one clock, which is every journey in the
    /// five supported regional packages. Empty
    /// rather than "filled with copies of `home`" so that ``crossesTimeZones``
    /// costs nothing to ask and so that a caller cannot tell a
    /// single-clock journey apart by the size of an array.
    public let stops: [RegionClock]

    public init(home: RegionClock) {
        self.home = home
        self.stops = []
    }

    /// A journey whose stops are on the clocks in `stops`.
    ///
    /// A table that turns out to name ONE clock is collapsed to it: a journey
    /// that stays on one clock is a journey that stays on one clock whether or
    /// not the caller happened to know its stops one at a time.
    ///
    /// ## Two identifiers can be one clock, and here they are
    ///
    /// Clock equivalence compares the printed name and offset on the
    /// journey's own day, rather than the database zone identifier alone.
    ///
    /// - Parameter date: the journey's own day, `YYYY-MM-DD`. A record with
    ///   no usable date uses ``undatedReference``, consistently with
    ///   ``offsetMinutes(fromStopIndex:toStopIndex:on:)``.
    public init(stops: [RegionClock], fallback: RegionClock, on date: String? = nil) {
        let home = stops.first ?? fallback
        self.home = home
        let instant = home.startOfDay(date) ?? Self.undatedReference
        let distinct = Set(stops.map { Self.readingKey($0, at: instant) })
        self.stops = distinct.count <= 1 ? [] : stops
    }

    /// The instant a journey with no usable date is read on.
    ///
    /// 1970-01-01T00:00Z supplies a deterministic fallback for an undated record.
    static let undatedReference = Date(timeIntervalSince1970: 0)

    /// What a reader can tell one stop's clock from another's — the offset it
    /// reads on this day, and the name it is printed under.
    ///
    /// Not the zone identifier. See ``init(stops:fallback:on:)``.
    private static func readingKey(_ clock: RegionClock, at instant: Date) -> String {
        let offset = clock.timeZone.secondsFromGMT(for: instant)
        // The fallback name as well as the key, because a zone this build has
        // no name for carries an empty key and its own identifier as the name
        // — so two unnamed zones an hour apart stay two clocks.
        return "\(offset)|\(clock.nameKey)|\(clock.fallbackName)"
    }

    /// The journey's clock, from the region code the record carries.
    public init(regionCode: String?) {
        self.init(home: .forRegionCode(regionCode))
    }

    /// The clock the stop at `index` prints its times on.
    ///
    /// An index no stop exists at answers ``home`` rather than `nil`: a caller
    /// that has a stop index has a stop, and returning an optional would make
    /// every call site handle a case it cannot reach.
    public func clock(atStopIndex index: Int) -> RegionClock {
        guard index >= 0, index < stops.count else { return home }
        return stops[index]
    }

    /// Whether this journey's printed times are on more than one clock.
    ///
    /// The one flag a surface has to consult before it may treat the
    /// difference between two printed times as a duration.
    public var crossesTimeZones: Bool { !stops.isEmpty }

    /// The minutes that must be ADDED to a time printed at `fromStopIndex`
    /// before it can be compared with one printed at `toStopIndex`.
    ///
    /// `date` is the journey's own day. Undated records use the same
    /// deterministic reference as the clock-equivalence calculation.
    public func offsetMinutes(
        fromStopIndex: Int, toStopIndex: Int, on date: String?
    ) -> Int {
        guard crossesTimeZones else { return 0 }
        let from = clock(atStopIndex: fromStopIndex)
        let to = clock(atStopIndex: toStopIndex)
        guard from.timeZone.identifier != to.timeZone.identifier else { return 0 }
        let instant = home.startOfDay(date) ?? Self.undatedReference
        let fromSeconds = from.timeZone.secondsFromGMT(for: instant)
        let toSeconds = to.timeZone.secondsFromGMT(for: instant)
        return (toSeconds - fromSeconds) / 60
    }

    // MARK: - the questions the app actually asks

    /// Today, on this journey's clock.
    public func today(at now: Date) -> String { home.today(at: now) }

    /// Whether this journey is still ahead of the reader, on its own clock.
    public func isUpcoming(_ date: String?, at now: Date) -> Bool {
        home.isUpcoming(date, at: now)
    }

    /// Whether this journey's day is over, on its own clock.
    public func hasPassed(_ date: String?, at now: Date) -> Bool {
        home.hasPassed(date, at: now)
    }

    /// Whether this journey has happened — its day is today or earlier, on its
    /// own clock.
    public func isTodayOrEarlier(_ date: String?, at now: Date) -> Bool {
        home.isTodayOrEarlier(date, at: now)
    }
}
