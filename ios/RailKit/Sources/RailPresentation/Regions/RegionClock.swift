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
/// ask which regional clock a ride is on. This app draws every network at
/// once, and the question is per ride.
///
/// ## Two kinds of region, and why the type does not care which it has
///
/// The supported Asian networks make this look simpler than it is. None of them
/// observes daylight saving, and none has for decades — Japan stopped in 1951,
/// Taiwan, Hong Kong and Macao in 1979, Korea in 1988, China in 1991 — and each is one zone
/// from end to end. A journey inside any of them therefore cannot be ambiguous
/// about its day, and no stop time can land in a skipped or repeated hour.
///
/// Each supported region supplies a default clock. JourneyClock centralizes
/// per-stop clock calculations without treating a display relationship or a
/// region change as evidence of a physical railway connection.
///
/// None of that is written down here as arithmetic. Which offset a zone has on
/// a given day, and whether that day had 23 hours in it, are facts about the
/// world and keeping them true is the time-zone database's job — so the lookup
/// goes through `TimeZone(identifier:)` and every calculation through
/// `Calendar`. ``fixedOffsetSeconds`` is only the parachute for a device whose
/// database has never heard of `Asia/Macau`, and for a summer-time zone it is
/// the STANDARD offset, which is the best a parachute can do.
///
/// ## What is deliberately absent
///
/// Any conversion of a printed stop time. See ``JourneyClock``.
public struct RegionClock: Sendable, Hashable {

    /// The region this clock belongs to, spelled the way every `RailCore`
    /// entry point spells `country` — `"jp"`, `"tw"`, `"hk"`, `"mo"`, `"kr"`, `"cn"`.
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

    // MARK: - regional clocks

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

    /// China railway timetables use Beijing time throughout the network.
    public static let china = RegionClock(
        regionCode: "cn", identifier: "Asia/Shanghai", fixedOffsetSeconds: 8 * 3600,
        nameKey: "ios.clock.zoneChina", fallbackName: "China Standard Time")

    /// Every clock the app can be asked for, in the region catalog's order.
    public static let all: [RegionClock] = [
        japan, taiwan, hongKong, macao, korea, china,
    ]

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

    // MARK: - a clock named by a zone rather than by a region

    /// The clock one station is on, from the zone identifier its package
    /// carries — falling back to the region's default when the identifier is
    /// missing or is one this build has no name for.
    ///
    /// A zone the table does not name still gets a working clock, built from
    /// the database and described by its own identifier, rather than being
    /// silently read on the wrong one. That is what makes adding a station in
    /// a zone nobody anticipated a cosmetic problem instead of a wrong answer
    /// about which day a journey was.
    public static func forZone(_ identifier: String?, regionCode: String?)
        -> RegionClock
    {
        guard let identifier, !identifier.isEmpty else {
            return forRegionCode(regionCode)
        }
        guard TimeZone(identifier: identifier) != nil else {
            return forRegionCode(regionCode)
        }
        return RegionClock(
            regionCode: regionCode ?? "", identifier: identifier,
            fixedOffsetSeconds: 0, nameKey: "", fallbackName: identifier)
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
    /// 2026, and `ios/docs/porting.md`'s own table says to pin both the calendar and
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
