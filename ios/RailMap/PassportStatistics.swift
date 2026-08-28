import Foundation
import RailCore
import RailPresentation

/// The per-journey figures the passport's Flighty-shaped cards are drawn from.
///
/// ## Why this is not in `RailCore`
///
/// Everything in `Statistics` is a port with a committed fixture behind it:
/// the web app computes the same number, and `StatisticsParityTests` says the
/// two agree. None of what follows exists over there — the web panel has no
/// "most visited station", no weekday histogram and no shortest journey — so
/// there is nothing to be at parity *with*, and a new function in the ported
/// enum would be a function the parity suite silently does not cover.
///
/// It is also not a second way of measuring anything. Every kilometre here is
/// `Statistics.TrainEntry.km` — the matched, ridden distance the ported walk
/// already produced for that one journey — and every minute is
/// `Statistics.trainRideMinutes`. This type only *groups* those, which is why
/// the totals it reports add up to the ones the ported aggregate reports.
///
/// ## What a journey contributes
///
/// The endpoints are the first and last **effectively ridden** stopping calls,
/// not `origin` / `destination`. A reader who boarded halfway did not visit
/// the terminus the record names, and a passport that said they did would be
/// counting a station they never stood on. `Statistics.effectivelyRiddenStopIndexes`
/// is the same rule the map draws its ride markers with.
///
/// A journey with no usable times contributes no minutes and is not in the
/// mean, rather than entering it as a zero: "we do not know how long that one
/// took" and "it took no time" are different statements, and only one of them
/// is true.
struct PassportStatistics: Sendable {

    // MARK: - the pieces a card is set from

    /// One journey, reduced to what a superlative row needs to name it.
    struct Journey: Sendable, Equatable {
        let id: String
        /// `JourneyTitle.compact` — the name cut to what identifies it.
        let title: String
        /// The first and last effectively-ridden calls, as the record spells
        /// them. Both go through the readings table at the point of display.
        let from: String
        let to: String
        /// The record's own `YYYY-MM-DD`, or `""` when it carries none.
        let date: String
        let km: Double
        let minutes: Double
    }

    /// One row of a ranked list — a station, an operating company, or a pair
    /// of endpoints.
    struct Tally: Sendable, Identifiable {
        /// The stable key this row was accumulated under. Never shown.
        let id: String
        /// What the row is named after, unresolved: a station name, or an
        /// operator's raw N02 name.
        let name: String
        /// A route's far endpoint. `nil` for every other kind of row.
        let pair: String?
        let count: Int
        let km: Double
    }

    /// One column of a distribution chart.
    struct Column: Sendable, Identifiable {
        /// A calendar year, a month 1…12, or a weekday 1…7 with Sunday first —
        /// `Calendar`'s own numbering, so the labels can come from its symbols.
        let id: Int
        let count: Int
        let km: Double
    }

    /// One region's share, for the reference's "Countries & Territories".
    struct RegionTally: Sendable, Identifiable {
        let region: Region
        let count: Int
        let km: Double
        var id: String { region.rawValue }
    }

    // MARK: - what the cards read

    let journeys: Int
    let totalKm: Double
    /// How many journeys carry times at all — the denominator of the mean
    /// below, and the reason it is not simply `journeys`.
    let timedJourneys: Int
    let totalMinutes: Double

    let byYear: [Column]
    let byMonth: [Column]
    let byWeekday: [Column]
    /// Journeys with no usable date. They are in every total on this screen
    /// and in none of the three distributions, which is a thing the chart has
    /// to say out loud rather than quietly leave out.
    let undated: Int

    let longestByDistance: Journey?
    let shortestByDistance: Journey?
    let longestByTime: Journey?
    let shortestByTime: Journey?

    let stations: [Tally]
    let operators: [Tally]
    let routes: [Tally]
    let regions: [RegionTally]

    /// Mean ridden distance per journey. Every journey counts, including one
    /// whose geometry matched nothing — a ride that left no kilometres on the
    /// network still happened, and dropping it would inflate the mean.
    var averageKm: Double { journeys > 0 ? totalKm / Double(journeys) : 0 }

    /// Mean ride time over the journeys that carry times. See ``timedJourneys``.
    var averageMinutes: Double { timedJourneys > 0 ? totalMinutes / Double(timedJourneys) : 0 }

    var isEmpty: Bool { journeys == 0 }

    // MARK: - building it

    /// Group one region's already-matched journeys.
    ///
    /// `entries` is `MileageStatisticsStore`'s own per-journey output and is
    /// index-aligned with `trains`; a caller that hands over two lists of
    /// different lengths gets the shorter one, rather than a crash or a
    /// journey wearing another journey's distance.
    static func build(trains: [Train], entries: [Statistics.TrainEntry]) -> PassportStatistics {
        var journeys: [Journey] = []
        journeys.reserveCapacity(min(trains.count, entries.count))

        var years: [Int: (count: Int, km: Double)] = [:]
        var months: [Int: (count: Int, km: Double)] = [:]
        var weekdays: [Int: (count: Int, km: Double)] = [:]
        var undated = 0

        var stations = Accumulator()
        var operators = Accumulator()
        var routes = Accumulator()
        var regions: [Region: (count: Int, km: Double)] = [:]

        var totalKm = 0.0
        var totalMinutes = 0.0
        var timed = 0

        for (train, entry) in zip(trains, entries) {
            let flags = MapRideMarkers.rideFlags(train.stops)
            let ridden = Statistics.effectivelyRiddenStopIndexes(flags)
            let km = entry.km.isFinite ? entry.km : 0
            let minutes = Statistics.trainRideMinutes(
                Statistics.Train(
                    id: train.id, trainType: train.trainType, date: train.date, stops: flags))

            totalKm += km
            if let minutes, minutes.isFinite, minutes > 0 {
                totalMinutes += minutes
                timed += 1
            }

            // The calendar buckets. `Dates.trainDate` is the same normaliser
            // the date scope and the day slice use, so a journey lands in the
            // bucket the rest of the app already agrees it is in.
            let bucket = Dates.trainDate(
                Dates.Train(id: train.id, date: train.date, stops: []))
            if let day = calendarParts(bucket) {
                years[day.year, default: (0, 0)].count += 1
                years[day.year, default: (0, 0)].km += km
                months[day.month, default: (0, 0)].count += 1
                months[day.month, default: (0, 0)].km += km
                if let weekday = weekday(of: day) {
                    weekdays[weekday, default: (0, 0)].count += 1
                    weekdays[weekday, default: (0, 0)].km += km
                }
            } else {
                undated += 1
            }

            let region = Region.resolved(train)
            regions[region, default: (0, 0)].count += 1
            regions[region, default: (0, 0)].km += km

            let company = (train.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !company.isEmpty {
                operators.add(key: company, name: company, count: 1, km: km)
            }

            guard let first = ridden.first, let last = ridden.last, first != last else { continue }
            let from = train.stops[first].name
            let to = train.stops[last].name
            journeys.append(
                Journey(
                    id: train.id,
                    title: JourneyTitle.compact(train),
                    from: from, to: to,
                    date: calendarParts(bucket) == nil ? "" : bucket,
                    km: km,
                    minutes: minutes ?? 0))

            // Boarded here, alighted there: two visits, and the same station
            // reached twice in one journey is still two — a there-and-back on
            // one record is two calls at the same platform.
            stations.add(key: from, name: from, count: 1, km: km)
            stations.add(key: to, name: to, count: 1, km: km)

            // A route is undirected. 東京→新大阪 and 新大阪→東京 are the same
            // pair of places, and a passport that listed them apart would
            // report a return trip as two different routes ridden once each.
            let ends = from <= to ? (from, to) : (to, from)
            routes.add(
                key: "\(ends.0)\u{001F}\(ends.1)", name: ends.0, pair: ends.1, count: 1, km: km)
        }

        return PassportStatistics(
            journeys: min(trains.count, entries.count),
            totalKm: totalKm,
            timedJourneys: timed,
            totalMinutes: totalMinutes,
            byYear: columns(years).sorted { $0.id < $1.id },
            byMonth: filled(months, over: 1...12),
            byWeekday: filled(weekdays, over: 1...7),
            undated: undated,
            longestByDistance: journeys.max { $0.km < $1.km },
            shortestByDistance: journeys.filter { $0.km > 0 }.min { $0.km < $1.km },
            longestByTime: journeys.filter { $0.minutes > 0 }.max { $0.minutes < $1.minutes },
            shortestByTime: journeys.filter { $0.minutes > 0 }.min { $0.minutes < $1.minutes },
            stations: stations.ranked(),
            operators: operators.ranked(),
            routes: routes.ranked(),
            regions: Region.ordered.compactMap { region in
                guard let share = regions[region], share.count > 0 else { return nil }
                return RegionTally(region: region, count: share.count, km: share.km)
            }
            .sorted { $0.count == $1.count ? $0.km > $1.km : $0.count > $1.count })
    }

    // MARK: - the counting

    /// A ranked list under construction.
    ///
    /// Kept as one type rather than three loops because the three lists differ
    /// only in what they are keyed on, and a tie has to break the same way in
    /// all of them or the same data produces three different orders.
    private struct Accumulator {
        private var rows: [String: Tally] = [:]

        mutating func add(key: String, name: String, pair: String? = nil, count: Int, km: Double) {
            let existing = rows[key]
            rows[key] = Tally(
                id: key, name: name, pair: pair,
                count: (existing?.count ?? 0) + count,
                km: (existing?.km ?? 0) + km)
        }

        /// Most ridden first, then furthest, then by name — so a screen redrawn
        /// with identical data is redrawn in identical order. A dictionary has
        /// no order of its own, and "whichever way the hash fell" is a list
        /// that reshuffles itself between launches.
        func ranked() -> [Tally] {
            rows.values.sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                if a.km != b.km { return a.km > b.km }
                return StatisticsFormat.linesPrecede(a.id, b.id)
            }
        }
    }

    private static func columns(_ buckets: [Int: (count: Int, km: Double)]) -> [Column] {
        buckets.map { Column(id: $0.key, count: $0.value.count, km: $0.value.km) }
    }

    /// A distribution over a fixed axis, zeroes included.
    ///
    /// A month nobody travelled in is part of the shape of the year, so the
    /// chart draws twelve columns whatever the data says. A YEAR nobody
    /// travelled in is not — the axis there is however many years the records
    /// span — which is why only these two are filled.
    private static func filled(
        _ buckets: [Int: (count: Int, km: Double)], over range: ClosedRange<Int>
    ) -> [Column] {
        range.map { Column(id: $0, count: buckets[$0]?.count ?? 0, km: buckets[$0]?.km ?? 0) }
    }

    // MARK: - reading a record's date

    /// The calendar a record's date is read on.
    ///
    /// Gregorian and UTC, deliberately: jsonspec's `date` is three numbers,
    /// not an instant, and the weekday of 2026-07-03 is Friday everywhere. A
    /// calendar carrying the device's zone would put a journey in a different
    /// column for a reader who flew east, which is a histogram that changes
    /// when nothing about the record did.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// `YYYY-MM-DD` as three numbers, or `nil` for `Dates.undated` and for
    /// anything else that is not a day.
    private static func calendarParts(_ date: String) -> (year: Int, month: Int, day: Int)? {
        let fields = date.split(separator: "-")
        guard fields.count == 3,
            let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]),
            (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return (year, month, day)
    }

    /// `Calendar`'s own weekday numbering — 1 is Sunday — so a label can come
    /// straight from `shortWeekdaySymbols` without an index rule of its own.
    private static func weekday(of day: (year: Int, month: Int, day: Int)) -> Int? {
        guard
            let point = calendar.date(
                from: DateComponents(year: day.year, month: day.month, day: day.day))
        else { return nil }
        return calendar.component(.weekday, from: point)
    }
}
