import RailCore
import RailPresentation
import SwiftUI

/// Turns a journey, the filtered list, or the statistics into the strings a
/// ``ShareCardView`` prints. Reads only values computed once elsewhere (the
/// statistics store's view and passport, including its per-journey distance
/// and time maps); it never walks routes or recomputes mileage.
@MainActor
struct ShareCardBuilder {
    let localization: AppLocalization
    let passport: PassportStatistics?
    /// Drawn-route length by journey, used where the statistics have no
    /// matched distance yet.
    var drawnKm: [String: Double] = [:]

    private func km(_ train: Train) -> Double? {
        passport?.journeyKm[train.id] ?? drawnKm[train.id].flatMap { $0 > 0 ? $0 : nil }
    }

    private func minutes(_ train: Train) -> Double? {
        if let minutes = passport?.journeyMinutes[train.id] { return minutes }
        return train.rideMinutes.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private var l: AppLocalization { localization }

    // MARK: journey

    func journey(_ train: Train, stops mode: ShareStopsMode) -> ShareCardContent {
        // The same boarding and alighting stops as the card, detail and sort.
        let first = train.stops.boardingStopIndex.map { train.stops[$0] }
        let last = train.stops.alightingStopIndex.map { train.stops[$0] }
        let origin = l.stationName(train.origin, in: train, code: train.originStationCode)
        let destination = l.stationName(train.destination, in: train, code: train.destinationStationCode)
        // main: operator names through companyText (English operator names).
        let company = train.company.map(JourneyBranding.companyText)
            ?? JourneyBranding.operatorLabels(of: train).joined(separator: " / ")
        let eyebrow = [company, train.trainType].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")

        var facts: [ShareCardContent.Fact] = []
        if let km = km(train) {
            facts.append(.init(id: "km", value: StatisticsFormat.km(km) + " km",
                               label: l.text("ios.share.fact.distance", fallback: "Distance")))
        }
        if let minutes = minutes(train) {
            facts.append(.init(id: "time", value: StatisticsFormat.duration(minutes, l),
                               label: l.text("ios.share.fact.time", fallback: "On board")))
        }
        let calls = train.stops.filter { $0.stopType != "pass_through" }.count
        facts.append(.init(id: "stops", value: calls.formatted(),
                           label: l.text("ios.share.fact.stops", fallback: "Stops")))

        let rows = stopRows(train, mode: mode)
        let spoken = ([train.number, eyebrow, train.date ?? "", "\(origin) → \(destination)"]
            + facts.map { "\($0.label) \($0.value)" } + rows.map { "\($0.leading) \($0.title)" })
            .filter { !$0.isEmpty }.joined(separator: "\n")
        return ShareCardContent(
            accentHex: train.style?.color,
            eyebrow: eyebrow.isEmpty ? l.text("ios.share.scope.journey") : eyebrow,
            // The compact title, not the record's full name: the route is
            // the hero just below, so a name that spells it would say it twice.
            title: JourneyTitle.compact(train),
            subtitle: train.date.map { StatisticsFormat.spelledDate($0, localization: l) },
            body: .journey(
                origin: origin, departure: first.flatMap { RideCardTimeText.departure(of: $0) },
                destination: destination, arrival: last.flatMap { RideCardTimeText.arrival(of: $0) }),
            facts: facts,
            rows: rows,
            rowsHeading: l.text(mode.localizationKey),
            spokenText: spoken)
    }

    /// Key stops: the ends, every passenger stop and each service change; or
    /// every recorded call. Times as the record spells them.
    private func stopRows(_ train: Train, mode: ShareStopsMode) -> [ShareCardContent.Row] {
        let legs = JourneyServiceSections.legs(of: train)
        let mapping = RecordedRouteMapping(
            stops: train.stops, sections: StoreOperations.rideRouteSections(for: train))
        let changes = Set(legs.dropFirst().compactMap {
            mapping?.stopIndex(atSectionBoundary: $0.fromSectionIndex)
        })
        let last = train.stops.count - 1
        return train.stops.indices.compactMap { index in
            let stop = train.stops[index]
            let important = index == 0 || index == last || changes.contains(index)
                || stop.stopType == "passenger_stop"
            if mode == .key, !important { return nil }
            let time = RideCardTimeText.departure(of: stop) ?? "—"
            return ShareCardContent.Row(
                id: "\(index)",
                leading: time,
                title: l.stationName(stop.name, in: train, code: stop.n02StationCode),
                trailing: stop.platformNumber.map { l.countryText("table.platform", fallback: "Platform") + " \($0)" },
                emphasised: index == 0 || index == last || changes.contains(index))
        }
    }

    // MARK: list

    func list(_ trains: [Train], title: String) -> ShareCardContent {
        let dated = trains.compactMap(\.date).sorted()
        let span: String? = {
            guard let first = dated.first, let last = dated.last else { return nil }
            let a = StatisticsFormat.dayLabel(first, localization: l)
            let b = StatisticsFormat.dayLabel(last, localization: l)
            return a == b ? a : "\(a) – \(b)"
        }()
        let km = trains.compactMap { self.km($0) }.reduce(0, +)
        let minutes = trains.compactMap { self.minutes($0) }.reduce(0, +)
        var facts: [ShareCardContent.Fact] = [
            .init(id: "count", value: trains.count.formatted(),
                  label: l.text("ios.share.fact.journeys", fallback: "Journeys")),
        ]
        if km > 0 {
            facts.append(.init(id: "km", value: StatisticsFormat.km(km) + " km",
                               label: l.text("ios.share.fact.distance", fallback: "Distance")))
        }
        if minutes > 0 {
            facts.append(.init(id: "time", value: StatisticsFormat.duration(minutes, l),
                               label: l.text("ios.share.fact.time", fallback: "On board")))
        }
        let rows = trains.map { train -> ShareCardContent.Row in
            let from = l.stationName(train.origin, in: train, code: train.originStationCode)
            let to = l.stationName(train.destination, in: train, code: train.destinationStationCode)
            return ShareCardContent.Row(
                id: train.id,
                leading: train.date.map { StatisticsFormat.dayLabel($0, localization: l) } ?? "—",
                title: "\(JourneyTitle.compact(train))  \(from) → \(to)",
                trailing: self.km(train).map { StatisticsFormat.km($0) + " km" },
                emphasised: false)
        }
        return ShareCardContent(
            accentHex: trains.first?.style?.color,
            eyebrow: l.text("ios.share.scope.list"),
            title: title,
            subtitle: span,
            body: .list,
            facts: facts,
            rows: rows,
            rowsHeading: nil,
            spokenText: ([title, span ?? ""] + facts.map { "\($0.label) \($0.value)" }
                + rows.map { "\($0.leading) \($0.title)" }).joined(separator: "\n"))
    }

    // MARK: statistics

    func statistics(
        store: MileageStatisticsStore, scopeTitle: String
    ) -> ShareCardContent? {
        guard let view = store.view else { return nil }
        let overall = view.overall
        let passport = self.passport
        let coverage = store.coverageReading(
            ridden: overall.networkKm, denominator: store.totalKm, localization: l)
        var facts: [ShareCardContent.Fact] = []
        if let passport, passport.totalMinutes > 0 {
            facts.append(.init(id: "time", value: StatisticsFormat.duration(passport.totalMinutes, l),
                               label: l.text("ios.share.fact.time", fallback: "On board")))
        }
        if let passport {
            facts.append(.init(id: "stations", value: passport.stations.count.formatted(),
                               label: l.text("ios.share.fact.stations", fallback: "Stations")))
            facts.append(.init(id: "operators", value: passport.operators.count.formatted(),
                               label: l.text("ios.share.fact.operators", fallback: "Operators")))
        }
        facts.append(.init(id: "coverage", value: coverage.bar,
                           label: l.text("ios.share.fact.coverage", fallback: "Network")))

        let months = passport?.months(in: store.selectedYear) ?? []
        let peak = Double(months.map(\.count).max() ?? 0)
        let monthBars = months.map { column in
            ShareCardContent.Bar(
                id: "m\(column.id)", label: "\(column.id)", value: column.count.formatted(),
                fraction: peak > 0 ? Double(column.count) / peak : 0)
        }
        let busiest = months.max { $0.count < $1.count }.flatMap { column -> String? in
            guard column.count > 0 else { return nil }
            return l.text("ios.share.busiest", params: [
                "month": .string(StatisticsFormat.monthName(column.id, localization: l)),
                "n": .number(Double(column.count)),
            ], fallback: "Busiest: \(StatisticsFormat.monthName(column.id, localization: l))")
        }
        let operatorPeak = passport?.operators.first?.km ?? 0
        let operatorBars = (passport?.operators.prefix(3) ?? []).map { tally in
            ShareCardContent.Bar(
                id: tally.id, label: StatisticsFormat.companyLabel(tally.name),
                value: StatisticsFormat.km(tally.km) + " km",
                fraction: operatorPeak > 0 ? tally.km / operatorPeak : 0)
        }
        let rides = passport?.journeys ?? 0
        let heroCaption = l.text("ios.share.heroCaption", params: ["n": .number(Double(rides))],
                                 fallback: "ridden on \(rides) journeys")
        return ShareCardContent(
            accentHex: nil,
            eyebrow: l.text("ios.share.scope.statistics"),
            title: scopeTitle,
            subtitle: nil,
            body: .statistics(
                hero: StatisticsFormat.km(overall.riddenAll), heroUnit: "km", heroCaption: heroCaption,
                months: monthBars, busiestMonth: busiest, operators: operatorBars),
            facts: facts,
            rows: [],
            rowsHeading: l.text("ios.share.rhythm", fallback: "Rides by month"),
            spokenText: ([scopeTitle, "\(StatisticsFormat.km(overall.riddenAll)) km", heroCaption]
                + facts.map { "\($0.label) \($0.value)" }).joined(separator: "\n"))
    }
}
