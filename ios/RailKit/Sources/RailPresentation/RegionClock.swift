import Foundation
import RailCore

// =========================================================================
//  RegionClock.swift — which clock a journey's dates are read on.
//
//  `RailCore.Dates` deliberately has no time zone, and its own header says
//  why at length: the JavaScript it is a port of does every date calculation
//  in UTC integers, so the port does the same on integer civil dates and
//  never touches `Calendar`, `TimeZone` or `DateFormatter`. That is exactly
//  right for the RECORD. A stop that reads 25:10 is 25:10 in the timetable
//  the reader copied it from, on whatever calendar day the record names, and
//  no zone conversion may ever be applied to it.
//
//  It is not enough for the three questions this app asks that are not civil
//  arithmetic at all:
//
//      · what day is it?
//      · is this journey still ahead of me?
//      · has this journey happened, so that its kilometres count?
//
//  Each of those turns an INSTANT into a civil date, and that conversion
//  needs a zone. Until this file existed the zone used was the device's, and
//  the device is not where the train is: a Tokyo journey dated 2026-08-27
//  was still listed as upcoming at 19:00 in London — six hours after the 28th
//  had begun in Japan and the journey was over.
//
//  So the zone is the RIDE's, taken from its region. A journey is a thing
//  that happened in a place, and the place is what decides which day it was.
// =========================================================================

/// The clock one region's journeys are written on.
///
/// **This is not a port**, for the reason `RegionCatalog.Region` is not one:
/// the web app has a region switch and one active country, so it never has to
/// ask which of five clocks a ride is on. This app draws all five networks at
/// once, and the question is per ride.
///
/// ## Why the five regions make this simple, and why it is still not hardcoded
///
/// None of the five observes daylight saving, and none has for decades —
/// Japan stopped in 1951, Taiwan, Hong Kong and Macao in 1979, Korea in 1988.
/// All five have kept one offset ever since: UTC+9 for Japan and Korea, UTC+8
/// for Taiwan, Hong Kong and Macao. A journey's day therefore cannot be
/// ambiguous, and no stop time can land in a skipped or repeated hour.
///
/// That is a fact about the world, and keeping facts about the world true is
/// the time-zone database's job rather than this file's — so the lookup goes
/// through `TimeZone(identifier:)` and the arithmetic through `Calendar`,
/// which is what would start answering correctly on its own if one of the five
/// ever adopted summer time. ``fallbackOffsetSeconds`` is only the parachute
/// for a device whose database has never heard of `Asia/Macau`; it is not the
/// answer this type prefers.
///
/// ## What is deliberately absent
///
/// A journey on more than one clock. See ``JourneyClock``, which is where that
/// will be added and what it will change.
public struct RegionClock: Sendable, Hashable {

    /// The region this clock belongs to, spelled the way every `RailCore`
    /// entry point spells `country` — `"jp"`, `"tw"`, `"hk"`, `"mo"`, `"kr"`.
    public let regionCode: String

    /// The zone itself, resolved once from the time-zone database.
    public let timeZone: TimeZone

    /// The offset this region has kept since it last observed summer time,
    /// used only when the device's database does not know ``timeZone``'s
    /// identifier. See the type's note: this is the parachute, not the answer.
    public let fixedOffsetSeconds: Int

    /// The catalog key naming this zone in the reader's language, and the
    /// structural English behind it. The app resolves the pair; this tier has
    /// no catalog, exactly as `PresentationText` elsewhere in this module.
    public let nameKey: String
    public let fallbackName: String

    /// The zone's name as the interface should print it.
    public var name: PresentationText {
        PresentationText(key: nameKey, fallback: fallbackName)
    }

    // MARK: - the five

    /// Japan — 日本標準時, UTC+9, no summer time since 1951.
    public static let japan = RegionClock(
        regionCode: "jp", identifier: "Asia/Tokyo", fixedOffsetSeconds: 9 * 3600,
        nameKey: "ios.clock.zoneJapan", fallbackName: "Japan Standard Time")

    /// Taiwan — 國家標準時間, UTC+8, no summer time since 1979.
    public static let taiwan = RegionClock(
        regionCode: "tw", identifier: "Asia/Taipei", fixedOffsetSeconds: 8 * 3600,
        nameKey: "ios.clock.zoneTaiwan", fallbackName: "Taiwan Standard Time")

    /// Hong Kong — 香港時間, UTC+8, no summer time since 1979.
    public static let hongKong = RegionClock(
        regionCode: "hk", identifier: "Asia/Hong_Kong", fixedOffsetSeconds: 8 * 3600,
        nameKey: "ios.clock.zoneHongKong", fallbackName: "Hong Kong Time")

    /// Macao — 澳門時間, UTC+8, no summer time since 1979.
    ///
    /// The database spells the identifier `Asia/Macau`. `Asia/Macao` is a link
    /// to it and resolves to the same zone; the canonical spelling is used so
    /// that ``timeZone``'s own identifier reads back unchanged.
    public static let macao = RegionClock(
        regionCode: "mo", identifier: "Asia/Macau", fixedOffsetSeconds: 8 * 3600,
        nameKey: "ios.clock.zoneMacao", fallbackName: "Macao Time")

    /// Korea — 한국 표준시, UTC+9, no summer time since 1988.
    public static let korea = RegionClock(
        regionCode: "kr", identifier: "Asia/Seoul", fixedOffsetSeconds: 9 * 3600,
        nameKey: "ios.clock.zoneKorea", fallbackName: "Korea Standard Time")

    /// Every clock the app can be asked for, in the region catalog's order.
    public static let all: [RegionClock] = [japan, taiwan, hongKong, macao, korea]

    /// The clock a region code names.
    ///
    /// An unrecognised code — including `nil`, and including a ride that names
    /// no region at all — answers Japan. That is not a guess invented here: it
    /// is the same fallback `Region.resolved` and
    /// `StoreOperations.createBlankTrain(country:)` already make, and a ride
    /// drawn against Japan's package while being dated on Taiwan's clock would
    /// be two answers to one question.
    public static func forRegionCode(_ code: String?) -> RegionClock {
        guard let code, !code.isEmpty else { return japan }
        let folded = code.lowercased()
        return all.first { $0.regionCode == folded } ?? japan
    }

    private init(
        regionCode: String,
        identifier: String,
        fixedOffsetSeconds: Int,
        nameKey: String,
        fallbackName: String
    ) {
        self.regionCode = regionCode
        self.fixedOffsetSeconds = fixedOffsetSeconds
        self.nameKey = nameKey
        self.fallbackName = fallbackName
        // No `!`: a device that knows neither the identifier nor how to build
        // a fixed offset still has to produce a clock, and UTC is the one
        // answer that cannot be wrong about which hemisphere it is in.
        self.timeZone =
            TimeZone(identifier: identifier)
            ?? TimeZone(secondsFromGMT: fixedOffsetSeconds)
            ?? TimeZone(secondsFromGMT: 0)
            ?? .gmt
    }

    // MARK: - instants, and the civil dates they fall on

    /// A Gregorian calendar pinned to this zone.
    ///
    /// Explicitly Gregorian rather than `Calendar.current`, which is the
    /// reader's — a device set to the Japanese calendar answers year 8 for
    /// 2026, and `PORTING.md`'s own table says to pin both the calendar and
    /// the zone rather than inherit either.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The three numbers of the civil date `instant` falls on here.
    public func components(at instant: Date) -> (year: Int, month: Int, day: Int) {
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return (parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }

    /// The civil date `instant` falls on here, spelled the way a record spells
    /// a date — `YYYY-MM-DD`, which is what `RailCore.Dates` compares.
    public func civilDate(at instant: Date) -> String {
        let parts = components(at: instant)
        return String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
    }

    /// Today, here.
    ///
    /// `now` is a parameter and not `Date()` inside the body so that this is
    /// testable: a function whose answer depends on when it is called cannot be
    /// checked against a fixture, which is the reason `ContentView.todayString`
    /// gave for keeping the question out of `RailCore` in the first place.
    public func today(at now: Date) -> String { civilDate(at: now) }

    /// The first instant of a record's date, here.
    ///
    /// `nil` for anything that is not a date — `undated`, `__all__`, or a
    /// misspelling — because those name no day for a clock to place.
    public func startOfDay(_ date: String?) -> Date? {
        guard let date = Dates.normalizeDateString(date) else { return nil }
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whether a record's date is today here or later — §1.1's "upcoming".
    ///
    /// A comparison of two civil dates rather than of two instants, which is
    /// what makes a journey upcoming for the whole of its own day: an instant
    /// comparison against midnight would retire this morning's journey at
    /// 00:01. An undated record answers `false`; it has no position on a
    /// calendar to be ahead of.
    public func isUpcoming(_ date: String?, at now: Date) -> Bool {
        guard let date = Dates.normalizeDateString(date) else { return false }
        return date >= today(at: now)
    }

    /// Whether a record's date is in the past here. Not the negation of
    /// ``isUpcoming(_:at:)`` — an undated record is neither.
    public func hasPassed(_ date: String?, at now: Date) -> Bool {
        guard let date = Dates.normalizeDateString(date) else { return false }
        return date < today(at: now)
    }

    /// Whether a record's date is today here or earlier — "has this journey
    /// happened?", which the screenshot importer opens on.
    ///
    /// Also not the negation of ``isUpcoming(_:at:)``: both answer `true` for
    /// today. A journey is upcoming for the whole of its own day *and* has
    /// happened by the end of it, because a day is the finest grain a record's
    /// `date` has, and the app is forbidden (§1.1) from splitting it finer by
    /// implying a departure time it has not been told.
    public func isTodayOrEarlier(_ date: String?, at now: Date) -> Bool {
        guard let date = Dates.normalizeDateString(date) else { return false }
        return date <= today(at: now)
    }

    // MARK: - saying so

    /// `UTC+9`, `UTC+8` — and `UTC+5:45` if this ever has to name a zone that
    /// is not on the hour.
    ///
    /// Read out of the database at an instant rather than off
    /// ``fixedOffsetSeconds``, so that a region which adopted summer time
    /// would be described correctly on the day it started rather than on the
    /// day this file was next edited.
    public func utcOffsetText(at instant: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: instant)
        let sign = seconds < 0 ? "-" : "+"
        let total = abs(seconds) / 60
        let hours = total / 60
        let minutes = total % 60
        return minutes == 0
            ? "UTC\(sign)\(hours)"
            : String(format: "UTC%@%d:%02d", sign, hours, minutes)
    }
}

// MARK: - one journey's clock

/// The clock ONE journey's dates and printed times are on.
///
/// A wrapper around a single ``RegionClock`` today, and the wrapper is the
/// point: every caller that asks a journey what time it is goes through this
/// type, so the day cross-zone journeys are supported is a change to this file
/// rather than to every call site.
///
/// ## Why there is only one clock in it today
///
/// None of the five networks reaches another region. A ride in this app is
/// drawn against exactly one package, measured against exactly one station
/// table and tagged with exactly one `region` (`RegionCatalog`), so every stop
/// on it prints its times on the same clock. That is a statement about the
/// data as it is, not a simplification of a journey that could be otherwise —
/// and it is checked, in the sense that ``crossesTimeZones`` is the one flag
/// any surface has to consult before it may treat two printed times as
/// comparable.
///
/// ## What cross-zone support will change
///
/// Exactly three members here, and one function above this tier:
///
/// 1. ``clock(atStopIndex:)`` — today every stop answers ``home``. It becomes
///    a lookup into a per-stop table, which is what a border crossing needs:
///    the departure is on one clock and the arrival on another.
/// 2. ``crossesTimeZones`` — today constant `false`. It becomes "the table
///    holds more than one zone", and it is what tells a surface that the
///    difference between two printed times is not a duration.
/// 3. ``offsetMinutes(fromStopIndex:toStopIndex:)`` — today constant `0`. It
///    becomes the correction that makes them comparable again.
///
/// The function above this tier is `RailCore.Statistics.trainRideMinutes`,
/// which subtracts the first stop's departure from the last stop's arrival.
/// That is correct for every journey this app can hold today and wrong by the
/// offset for one that crosses a zone. It must NOT be fixed in `RailCore` —
/// that tier is a port checked against the JavaScript by fixture, and the
/// JavaScript has no zones at all. The correction belongs here, applied on top
/// of the ported answer, which is why (3) is stated in minutes: the ported
/// function's own unit.
///
/// Nothing else changes. In particular the stop times themselves stay exactly
/// as the reader wrote them down — `25:10` is a business fact about an
/// overnight service, and converting a printed time between zones would be
/// the app rewriting the timetable.
public struct JourneyClock: Sendable, Hashable {

    /// The clock the journey as a whole is on — its region's.
    public let home: RegionClock

    public init(home: RegionClock) {
        self.home = home
    }

    /// The journey's clock, from the region code the record carries.
    public init(regionCode: String?) {
        self.init(home: .forRegionCode(regionCode))
    }

    /// RESERVED — the clock the stop at `index` prints its times on.
    ///
    /// Every index answers ``home`` today, including indices no stop exists
    /// at: a journey has one clock, so there is no index at which the answer
    /// could be different, and returning an optional would make every call
    /// site handle a `nil` that cannot happen. See the type's note.
    public func clock(atStopIndex index: Int) -> RegionClock { home }

    /// RESERVED — whether this journey's printed times are on more than one
    /// clock. Constant `false` today. See the type's note.
    public var crossesTimeZones: Bool { false }

    /// RESERVED — the minutes that must be ADDED to a time printed at
    /// `fromStopIndex` before it can be compared with one printed at
    /// `toStopIndex`. Constant `0` today. See the type's note.
    public func offsetMinutes(fromStopIndex: Int, toStopIndex: Int) -> Int { 0 }

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
