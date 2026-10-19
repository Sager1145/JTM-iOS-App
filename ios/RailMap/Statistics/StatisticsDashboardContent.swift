import RailCore
import RailPresentation
import SwiftUI

/// Passport dashboard cards. The containing workspace owns scrolling and scope controls.
struct StatisticsDashboardContent: View {
    @Environment(AppLocalization.self) private var localization
    @Bindable var itineraries: ItineraryStore
    @Bindable var statistics: MileageStatisticsStore
    /// Which region's numbers these are.
    ///
    /// The map draws every region at once, but a statistic cannot: the
    /// categories differ (捷運 / 地下鐵, 高鐵 / 新幹線), and coverage is a
    /// fraction of one network's own length. So this screen keeps the region
    /// switch the rest of the app no longer has, and it is a `Binding` because
    /// the shell reloads `MileageStatisticsStore` when it moves.
    /// `nil` is 全部 — every network in one denominator.
    @Binding var region: Region?
    /// Explicit geometry-aware membership overrides the coarse region slice.
    var memberIDs: Set<String>? = nil
    /// Generation of `memberIDs`, supplied by the geometry-aware workspace memo.
    var memberKey: Int? = nil
    /// The printed ticket scope for an area selection.
    var scopeName: String? = nil

    /// The workspace's shared memoisation cache — see ``WorkspaceDerived`` —
    /// so ``scoped(_:)`` computes its region + ridden slice once per (trains
    /// generation, region) rather than rebuilding a whole
    /// `ItineraryStore.Loaded` on every body evaluation.
    var derived: WorkspaceDerived

    /// §11.2's resolved surface for one journey, from the app's ONE caller of
    /// `JourneyPresentationResolver`.
    ///
    /// A closure rather than a call: `JourneyBridge`'s own note says the
    /// priority order is decided once, in the tested module, and that keeping
    /// that promise means having exactly one caller. This screen quotes two
    /// journeys (``superlative(_:_:value:)``) and asks that caller for their
    /// surface rather than becoming a second one.
    var journeyPresentation: (Train) -> JourneyPresentation
    /// Open one journey's record — §3.1's L4, which is a sheet.
    ///
    /// Not a selection. Passport has no journey panel to hand a selection to:
    /// §5.3 removed the 乘車記録 list from this screen because the log has a
    /// destination of its own, so tapping a journey here opens the record
    /// rather than silently changing what the map behind the panel draws.
    var openJourney: (Train) -> Void

    /// §13.2: work under about 400 ms must not flash progress UI at the
    /// reader. Held here rather than inside the summary because the summary is
    /// mounted and unmounted by this decision.
    @State private var progressVisible = false

    /// The year, month or weekday axis used by the journey rhythm chart.
    ///
    /// Month rather than year by default, and deliberately: a store covering
    /// one year has ONE year column and nothing to see, while every store has
    /// twelve months and a shape.
    @State private var rhythm: RhythmScale = .month

    /// Whether the two rankable lists are ordered by how often or by how far.
    /// Two properties rather than one, because the reference gives each list
    /// its own control and a reader comparing 里程 in one against 趟數 in the
    /// other is asking a question a shared toggle cannot hold.
    @State private var operatorMetric: RankMetric = .count
    @State private var routeMetric: RankMetric = .count
    @State private var selectedWidgetKind: StatisticsCardKind?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `TOP_SEGMENT_CATEGORIES`. Not `view.categories`: the coverage rows carry
    /// a JR（含新幹線）row that is the UNION of two other rows, which is right
    /// for percentages and would merely duplicate sections here. Every row
    /// below is one EXCLUSIVE mode, which is why 在來線 reads as JR在來線.
    private struct TopSegmentSpec {
        /// `nil` = 全部鐵道, the unfiltered list.
        let mask: Int?
        let i18n: String
    }

    private static let topSegmentSections: [TopSegmentSpec] = [
        TopSegmentSpec(mask: nil, i18n: "stat.allrail"),
        TopSegmentSpec(mask: Statistics.maskHSR, i18n: "stat.hsr"),
        TopSegmentSpec(mask: Statistics.maskCONV, i18n: "stat.jrconv"),
        TopSegmentSpec(mask: Statistics.maskMETRO, i18n: "stat.metro"),
        TopSegmentSpec(mask: Statistics.maskPRIV, i18n: "stat.priv"),
        TopSegmentSpec(mask: Statistics.maskTRAM, i18n: "stat.tram"),
    ]


    private struct TopSegmentSection: Identifiable {
        let key: String
        let rows: [Statistics.TopRow]
        var id: String { key }
    }

    private struct CategoryDetail: Identifiable {
        let category: Statistics.Category
        let rows: [StatisticsLineCoverage.Row]
        var id: Int { category.mask }
    }

    /// The three axes 乘坐分佈 can be read on.
    enum RhythmScale: String, CaseIterable, Identifiable {
        case year, month, weekday
        var id: String { rawValue }
        var localizationKey: String { "ios.stats.scale.\(rawValue)" }
    }

    /// What a ranked list is ordered — and drawn — by.
    enum RankMetric: String, CaseIterable, Identifiable {
        case count, distance
        var id: String { rawValue }
        var localizationKey: String { "ios.stats.metric.\(rawValue)" }
    }

    /// One row of 距離紀錄's scale block: what the total is being compared to,
    /// and how far around it that is.
    ///
    /// Every figure is a real ratio against a real distance — the WGS-84
    /// equator the map's own kilometres are measured on, the Moon's mean
    /// distance, and the Sun's own circumference. §5.3 asks this screen to be
    /// more expressive than the editor while keeping the numbers accurate, and
    /// a souvenir figure that is not true is not a souvenir.
    private struct ScaleSpec {
        let i18n: String
        let systemImage: String
        let km: Double
    }

    private static let scaleSpecs: [ScaleSpec] = [
        ScaleSpec(i18n: "ios.stats.aroundEarth", systemImage: "globe.asia.australia", km: 40075.017),
        ScaleSpec(i18n: "ios.stats.toTheMoon", systemImage: "moon", km: 384_400),
        ScaleSpec(i18n: "ios.stats.aroundSun", systemImage: "sun.max", km: 4_375_517),
    ]

    /// How many rows a ranked list shows before the rest is folded away —
    /// the reference's own count above its "Show More".
    private static let rankedListLimit = 8

    /// `TOP_SEGMENT_LIMIT`.
    private static let topSegmentLimit = 12

    var body: some View {
        Group {
            if let all = itineraries.loaded {
                let scope = scoped(all)
                let loaded = scope.loaded
                // Journeys whose records do not say they were ridden. They are
                // in no figure on this screen (see
                // ``RailCore/RideLedger``), so the screen says how many
                // it is holding back and where to confirm them.
                let unconfirmed = scope.unconfirmed
                // A plain VStack, not Lazy: the caller is already a LazyVStack
                // inside the workspace's one ScrollView, and nesting a second
                // lazy container inside it defeats both.
                VStack(spacing: 16) {
#if DEBUG
                    statisticsDebug(loaded: loaded)
#endif
                    if progressVisible {
                        StatisticsProgressView(store: statistics)
                            // The one card on this screen that arrives and
                            // leaves on its own, and the cards below it shift
                            // by its full height when it does. §9.4's short
                            // in-place replacement is what `MapLayersView`
                            // already gives the same stage's one-line status;
                            // this is that card getting the same treatment.
                            //
                            // Opacity only, and deliberately not a `.move`: the
                            // card is not coming from anywhere, and a slide
                            // would be the "large slide" §9.4 asks to remove.
                            // That also makes it correct under Reduce Motion
                            // unchanged — only the curve degrades below.
                            .transition(.opacity)
                    }
                    if let failure = statistics.failureMessage {
                        failureCard(failure)
                    }
                    if loaded.trains.isEmpty {
                        emptyCard(unconfirmed: unconfirmed)
                    } else if let stats = statistics.view {
                        // The per-journey grouping, or nothing. It arrives one
                        // step behind the aggregate on the very first load, so
                        // every card built from it is optional rather than the
                        // whole screen waiting for the slower half.
                        let passport = statistics.passport.flatMap { $0.isEmpty ? nil : $0 }
                        passportDataPage(loaded.trains)
                        pendingMileageNote(loaded)
                        StatsWidgetGrid(
                            items: widgetItems(
                                loaded: loaded, stats: stats, passport: passport),
                            openDetails: { selectedWidgetKind = $0 })
                    }
                }
            } else {
                ProgressView(localization.text("ios.stats.calculating"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
        .background {
            // Mounted for the whole section, including the unloaded branch, so
            // the 400 ms gate keeps the same clock it had on this group.
            StatisticsProgressGate(store: statistics, progressVisible: $progressVisible)
                .allowsHitTesting(false)
        }
        .sheet(item: $selectedWidgetKind) { kind in
            NavigationStack {
                ScrollView {
                    if let all = itineraries.loaded, let stats = statistics.view {
                        let scope = scoped(all)
                        let passport = statistics.passport.flatMap { $0.isEmpty ? nil : $0 }
                        detailCard(
                            kind, loaded: scope.loaded, stats: stats, passport: passport)
                            .padding(16)
                    }
                }
                .navigationTitle(localization.text(kind.localizationKey))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(localization.text("ios.done", fallback: "Done")) {
                            selectedWidgetKind = nil
                        }
                    }
                }
            }
        }
    }

#if DEBUG
    private func statisticsDebug(loaded: ItineraryStore.Loaded) -> some View {
        let km = statistics.view.map {
            String(format: "%.1f", ($0.overall.riddenAll * 10).rounded() / 10)
        } ?? "-1"
        return Text(" ")
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Statistics debug")
            .accessibilityValue(
                "journeys=\(loaded.trains.count);km=\(km);scope=\(ticketScope)")
            .accessibilityIdentifier("statisticsDebug")
            .accessibilityHidden(false)
    }
#endif

    @ViewBuilder
    private func pendingMileageNote(_ loaded: ItineraryStore.Loaded) -> some View {
        if loaded.trains.contains(where: \.requiresRouteConfirmation) {
            Text(localization.text("ios.routeGuide.pendingMileageNote"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Full, interactive details for a summary widget selected on the dashboard.
    @ViewBuilder
    private func detailCard(
        _ kind: StatisticsCardKind, loaded: ItineraryStore.Loaded,
        stats: Statistics.MileageStatsView, passport: PassportStatistics?
    ) -> some View {
        switch kind {
        case .recordTicket:
            passportDataPage(loaded.trains)
        case .dailyTicket:
            if let daily = stats.daily { dailyTicket(daily, trains: loaded.trains) }
            else { emptyDashboardCard(kind) }
        case .rhythm:
            if let passport { rhythmCard(passport) } else { emptyDashboardCard(kind) }
        case .distance:
            if let passport { distanceCard(passport, distancePending: passport.measuredJourneys == 0) }
            else { emptyDashboardCard(kind) }
        case .time:
            if let passport { timeCard(passport) } else { emptyDashboardCard(kind) }
        case .rides:
            if let data = statistics.widgetData(
                kind, trains: loaded.trains, scopeName: scopeName ?? ticketScope,
                region: region, localization: localization) {
                StatsWidgetView(kind: kind, shape: .small, data: data)
            }
        case .coverage:
            coverageCard(stats)
        case .service:
            serviceCard(stats.overall, distancePending: loaded.trains.allSatisfy(\.requiresRouteConfirmation))
        case .stations:
            if let passport { stationsCard(passport) } else { emptyDashboardCard(kind) }
        case .operators:
            if let passport { operatorsCard(passport) } else { emptyDashboardCard(kind) }
        case .routes:
            if let passport { routesCard(passport) } else { emptyDashboardCard(kind) }
        case .topSegments:
            topSegmentsCard(stats.overall)
        case .regions:
            if let passport, passport.regions.count > 1 { regionsCard(passport) }
            else { emptyDashboardCard(kind) }
        case .lineDetail:
            lineDetailCard(stats)
        }
    }

    private func emptyDashboardCard(_ kind: StatisticsCardKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localization.text(kind.localizationKey), systemImage: kind.systemImage)
                .font(.headline)
            Text(localization.text("ios.stats.shareNoData"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passportCard(.soft)
    }

    // MARK: - ticket-module widgets

    private func widgetItems(
        loaded: ItineraryStore.Loaded,
        stats: Statistics.MileageStatsView,
        passport: PassportStatistics?
    ) -> [StatsWidgetGridItem] {
        var specs: [(StatisticsCardKind, CardShape)] = [
            (.coverage, .large), (.lineDetail, .large),
            (.distance, .medium), (.rhythm, .medium),
            (.stations, .tall), (.topSegments, .tall),
            (.operators, .small), (.routes, .small), (.time, .small),
            (.service, .medium),
        ]
        if stats.daily != nil { specs.append((.dailyTicket, .medium)) }
        if let passport, passport.regions.count > 1 { specs.append((.regions, .medium)) }
        return specs.compactMap { kind, shape in
            guard let data = statistics.widgetData(
                kind, trains: loaded.trains, scopeName: scopeName ?? ticketScope,
                region: region, localization: localization) else { return nil }
            return StatsWidgetGridItem(kind: kind, shape: shape, data: data)
        }
    }

    /// The progress card. Reading ``MileageStatisticsStore/progress`` stays in
    /// this view and in ``StatisticsProgressGate``; the dashboard reads
    /// ``progressVisible`` instead, so a progress tick does not rebuild the cards.
    private struct StatisticsProgressView: View {
        var store: MileageStatisticsStore

        var body: some View {
            if let progress = store.progress {
                StatisticsProgressSummary(progress: progress)
            }
        }
    }

    /// Owns the show/hide delay. Reading `progress` here does not rebuild the
    /// statistic cards.
    private struct StatisticsProgressGate: View {
        var store: MileageStatisticsStore
        @Binding var progressVisible: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task(id: store.progress == nil) {
                    // Both writes are animated, not just the arrival. The card leaving
                    // is the moment the five result cards take its place, and an
                    // unanimated departure is the one the reader actually sees as a
                    // jump — the arrival happens 400 ms into a wait nobody is watching
                    // closely.
                    //
                    // `withAnimation` rather than `.animation(_:value:)` on the card:
                    // the value that changes is this view's own state and the thing
                    // that must animate is a MOUNT, and a transition is inert unless
                    // the insertion happens inside an animated transaction. The same
                    // split `RideCard` makes for its detail body.
                    guard store.progress != nil else {
                        withAnimation(settle) { progressVisible = false }
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                    let visible = store.progress != nil
                    withAnimation(settle) { progressVisible = visible }
                }
        }

        private var settle: Animation {
            RailMotion.animation(RailMotion.replace, reduceMotion: reduceMotion)
        }
    }

    /// The progress card's arrival and departure, with the Reduce Motion swap
    /// already applied.
    ///
    /// `replace` rather than `spring`: this is one small thing appearing where
    /// another was, which is exactly what that token names, and a card the
    /// reader did not push has no momentum to carry.
    private var settle: Animation {
        RailMotion.animation(RailMotion.replace, reduceMotion: reduceMotion)
    }

    // MARK: - 本日乗車 — the day in scope, as a ticket of its own

    /// `#stats-daily`'s subtitle: how long, over how many trains.
    ///
    /// Spoken only now. The face states both figures in fields of their own,
    /// so this is what VoiceOver hears in place of reading a form aloud.
    private func dailySubtitle(_ daily: Statistics.DailyStats?) -> String {
        let time = daily.map { StatisticsFormat.duration($0.stats.rideMinutes, localization) }
            ?? StatisticsFormat.unset
        let trains = localization.text(
            "stat.trains",
            params: [
                "n": daily.map { Localization.Param.number(Double($0.trainCount)) }
                    ?? .string(StatisticsFormat.unset)
            ])
        return "\(localization.text("stat.time")) \(time) · \(trains)"
    }

    /// `#stats-daily`, issued as a second ticket under the record card rather
    /// than stamped inside it.
    ///
    /// The same stock, the same 組版, and its own 券種名 — which is the whole
    /// of the difference from the block this replaces. A day is not a footnote
    /// to the total above it; it is the same set of questions asked over one
    /// date, and the design's face answers a set of questions. Printing it
    /// into the middle of the record's own 券面 meant a second heading, a
    /// second date and a perforation on a card that already had a 券種名 at
    /// the top and an issuing line at the foot.
    ///
    /// Where the record card puts 集計範囲 in its corner, this one has the
    /// region too — a day in Japan and the same day counted worldwide are
    /// different figures, and the ticket says which it is holding.
    ///
    /// The web app renders this block whether or not a day is chosen, with
    /// `--` in every field, because in the browser the date bar that scopes it
    /// is a different region of the page. Here the scope control sits in the
    /// panel header — visible at every sheet stop, on this destination only —
    /// so "no day is in scope" is stated by the control that owns the scope,
    /// and no ticket is issued. A card of dashes would say the same thing a
    /// second time, in the one register §13.1 rules out.
    private func dailyTicket(_ daily: Statistics.DailyStats, trains: [Train]) -> some View {
        // The same mutually-exclusive ride groups the block carried, and the
        // same accumulating figure as its headline: the day is part of the
        // total on the card above, and a part measured on the other convention
        // is not a part of it.
        let groups = StatisticsFormat.serviceRows(daily.stats.services)
        let dayTrains = trains.filter { Dates.trainDate($0) == daily.date }
        let pending = dayTrains.contains(where: \.requiresRouteConfirmation)
        let allPending = !dayTrains.isEmpty && dayTrains.allSatisfy(\.requiresRouteConfirmation)
        let distance = allPending ? localization.text("ios.routeGuide.unknownDistance")
            : StatisticsFormat.km(daily.stats.services.km)
        let rides = daily.trainCount.formatted()
        let ridesUnit = localization.text("ios.ticket.unit.rides")
        return TicketFaceCard(
            kind: "本日乗車",
            scope: ticketScope,
            displays: [
                .figure(
                    label: pending ? localization.text("ios.routeGuide.confirmedDistance")
                        : localization.text("ios.ticket.label.distance"),
                    value: distance,
                    unit: allPending ? "" : "KM",
                    spoken: allPending ? distance : dailySpoken(daily)),
                StatisticsFormat.ticketRideTime(daily.stats.rideMinutes, localization: localization),
            ],
            // 車種 in the three fields the four-cell block has left, which is
            // the one place these two faces differ in what they print: the
            // record card qualifies its distance with what the reader has
            // covered, and a single day is better qualified by what it was
            // spent on.
            fields: [
                TicketField(
                    label: localization.text("ios.ticket.label.rides"),
                    value: rides,
                    unit: ridesUnit,
                    spoken: StatisticsFormat.ticketSpoken(rides, ridesUnit))
            ]
                + groups.map { row in
                    let km = StatisticsFormat.km(row.group.km)
                    return TicketField(
                        label: localization.statsCategoryText(row.key),
                        value: allPending ? distance : km,
                        unit: allPending ? "" : "KM",
                        spoken: allPending ? distance : "\(km) km · \(serviceDetail(row.group))")
                },
            span: localization.text(
                "ios.ticket.spanDay", params: ["date": .string(StatisticsFormat.spelledDate(daily.date, localization: localization))]),
            issued: StatisticsFormat.ticketIssued(localization: localization)
        )
        .passportCard(.feature)
    }

    private func dailySpoken(_ daily: Statistics.DailyStats?) -> String {
        guard let daily else { return localization.text("ios.stats.unsetSpoken") }
        return "\(StatisticsFormat.km(daily.stats.services.km)) km · \(dailySubtitle(daily))"
    }


    /// 集計範囲 — the region the figures are counted over, for the corner of
    /// the face.
    ///
    /// The panel header carries this scope too, and an earlier revision of
    /// this card dropped its region chip for exactly that reason (§5.1: one
    /// value, one place). This is not that chip coming back. A chip was a
    /// control that looked interactive and answered a question the header had
    /// already answered; 「（日本）」 in the corner of a 券面 is the DOCUMENT
    /// stating its own scope, which is also printed by the shared ticket face
    /// when the composer exports it without a panel header.
    private var ticketScope: String {
        StatisticsFormat.ticketScope(
            trains: itineraries.store?.trains ?? itineraries.loaded?.trains ?? [],
            groupID: statistics.selectedJourneyGroupID, scopeName: scopeName,
            region: region, localization: localization)
    }

    // MARK: - §5.7 #1 + #2 — 乗車記録, the ticket this passport is

    /// The whole record, on one 券面.
    ///
    /// §5.3.3 asks for the distance first and 旅程數 / 出行日 / 停站數 /
    /// 乘車時間 second, and that is still the order — but the shape is now the
    /// design's own 集計券 rather than a card of metric tiles: two 大字 figures
    /// across the top (乗車距離 and 乗車時間, at cx150 / cx365), the four that
    /// qualify them as a 中字 form block underneath, the 集計期間 as a printed
    /// sentence, the 色帯, and the issuing line under it. See
    /// `PassportTicketFace.swift` for the 組版規則 that lays all of that out;
    /// this method's whole job is choosing which measured number goes in which
    /// printed field.
    ///
    /// It is the one `.feature` card on the screen (§6.1's Memory personality
    /// — see `PassportCardStyle.swift`). One, because a screen where every card
    /// is loud has no hero, and this is the card that answers §5.3's question:
    /// **how much have I ridden, and which railways does that cover?**
    ///
    /// ### What left the card, and where it went
    ///
    /// The face has no captions — a printed form has a label, a figure and a
    /// counter, and nothing under them. The three this card used to carry are
    /// all still on the screen, one card further down, which is why losing
    /// them here costs nothing and gains §5.1:
    ///
    ///   - 「地球 1.4 周」 → `distanceCard`'s scale rows, which count the same
    ///     lap off the same circumference.
    ///   - 「高速鉄道 12 本」 under 旅程数 → `serviceCard`, whose entire subject
    ///     that is.
    ///   - 「4,203 / 13,608 km」 under the percentage → `coverageCard`, which
    ///     states the same fraction with its denominator.
    ///
    /// The coverage BAR went with them for a different reason: 「文字色は純黒
    /// #000 / 純白 #fff のみ。透明度は使わない」 leaves a proportion bar nothing
    /// to be drawn in that is not either a third colour on a two-plate ticket
    /// or a screened block pretending to be a chart.
    ///
    /// The unconfirmed-journeys note went for the plainest reason of all: the
    /// 券面 has no field for it. 組版規則's 位置 is a closed list — 券種名, the
    /// 識別文字, the 集計範囲, two 大字 anchors, four 中字 cells, the 集計期間,
    /// the 色帯 and one 最下行 — and every line of it is spoken for. A note
    /// printed anywhere on this face would be either type inside the band the
    /// design says carries none, or a line below the 最下行 that the design does
    /// not set.
    @ViewBuilder private func passportDataPage(_ trains: [Train]) -> some View {
        if let content = statistics.recordTicketContent(trains: trains, localization: localization) {
            TicketFaceCard(
                kind: localization.text("ios.ticket.kind.history"), scope: ticketScope,
                displays: content.displays, fields: content.fields, span: content.span,
                issued: StatisticsFormat.ticketIssued(localization: localization))
                .passportCard(.feature)
        }
    }

    // MARK: - §5.7 #3 路網覆蓋率

    private func coverageCard(_ view: Statistics.MileageStatsView) -> some View {
        let stats = view.overall
        let total = statistics.totalKm
        let overall = statistics.coverageReading(ridden: stats.networkKm, denominator: total, localization: localization)
        return VStack(alignment: .leading, spacing: 16) {
            PassportCardHeader(
                localization.text("stats.coverageTitle"),
                systemImage: "chart.bar.xaxis")
            StatisticsBar(
                label: localization.statsCategoryText("stat.all"),
                value: overall.bar,
                detail: overall.known
                    ? "\(StatisticsFormat.km(stats.networkKm)) / \(StatisticsFormat.km(total)) km"
                    : overall.text,
                fraction: overall.fraction,
                spoken: overall.spoken)
            ForEach(view.categories, id: \.mask) { category in
                let ridden = stats.riddenByMask[category.mask] ?? 0
                let categoryTotal = statistics.totalsByMask[category.mask] ?? 0
                let reading = statistics.coverageReading(ridden: ridden, denominator: categoryTotal, localization: localization)
                StatisticsBar(
                    label: localization.statsCategoryText(category.i18n),
                    value: reading.bar,
                    detail: reading.known
                        ? "\(StatisticsFormat.km(ridden)) / \(StatisticsFormat.km(categoryTotal)) km"
                        : reading.text,
                    fraction: reading.fraction,
                    spoken: reading.spoken)
            }
            // Outside the coverage fraction: historical km is not part of the
            // current-network numerator or denominator above.
            StatisticsMetricRow(
                label: localization.text("ios.stats.totalRiddenKm"),
                value: "\(StatisticsFormat.km(stats.totalRiddenKm)) km")
            StatisticsMetricRow(
                label: localization.text("ios.stats.currentRiddenKm"),
                value: "\(StatisticsFormat.km(stats.currentNetworkRiddenKm)) km")
            StatisticsMetricRow(
                label: localization.text("ios.stats.historicalKm"),
                value: "\(StatisticsFormat.km(stats.historicalUniqueKm)) km")
            StatisticsMetricRow(
                label: localization.text("ios.stats.retiredKm"),
                value: "\(StatisticsFormat.km(stats.retiredNetworkKm)) km")
            StatisticsMetricRow(
                label: localization.text("ios.stats.relocatedOldKm"),
                value: "\(StatisticsFormat.km(stats.relocatedOldKm)) km")
            StatisticsMetricRow(
                label: localization.text("ios.stats.retiredLines"),
                value: stats.historicalLineCount.formatted())
            // The one sentence that stops these being read as an accumulating
            // odometer: the numerator is a deduped union over ridden intervals,
            // the denominator the whole N02 network.
            Text(localization.text("stats.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .passportCard(.soft)
    }

    // MARK: - §5.7 #4 車種組合

    /// `stats.actualTitle` + `serviceRowsHtml` + the ride-time row.
    ///
    /// Deliberately no coverage percentage: repeat rides count each time, so
    /// there is no denominator these could be a percentage *of*. The bar is a
    /// share of the ride distance the three groups add up to, which is a ratio
    /// of numbers the aggregate already carries, and every figure it draws is
    /// spelled out beside it (§10.2).
    private func serviceCard(_ stats: Statistics.MileageStats, distancePending: Bool = false) -> some View {
        let groups = StatisticsFormat.serviceRows(stats.services)
        let totalKm = groups.reduce(0) { $0 + $1.group.km }
        return VStack(alignment: .leading, spacing: 16) {
            PassportCardHeader(
                localization.text("stats.actualTitle"),
                systemImage: "chart.bar.fill")
            ForEach(groups) { row in
                StatisticsBar(
                    label: localization.statsCategoryText(row.key),
                    value: distancePending ? localization.text("ios.routeGuide.unknownDistance")
                        : "\(StatisticsFormat.km(row.group.km)) km",
                    detail: serviceDetail(row.group),
                    fraction: totalKm > 0 ? row.group.km / totalKm : 0,
                    spoken:
                        distancePending ? localization.text("ios.routeGuide.unknownDistance")
                        : "\(StatisticsFormat.km(row.group.km)) km · \(serviceDetail(row.group))")
            }
            // `PassportRule`, not `Divider`: the system separator is a grey
            // line, and every other hairline on these cards follows the paper
            // it is drawn on. One card ruling itself differently from the nine
            // beside it is the whole reason that component exists.
            PassportRule()
            StatisticsMetricRow(
                label: localization.text("stat.time"),
                value: StatisticsFormat.duration(stats.rideMinutes, localization))
        }
        .passportCard(.soft)
    }


    private func serviceDetail(_ group: Statistics.ServiceGroup) -> String {
        let time = StatisticsFormat.duration(group.minutes, localization)
        let trains = localization.text(
            "stat.trains", params: ["n": .number(Double(group.count))])
        return "\(time) · \(trains)"
    }

    // MARK: - §5.7 #5 最常乘坐區間

    private func topSegmentsCard(_ stats: Statistics.MileageStats) -> some View {
        let top = stats.topSegments
        let sections = Self.topSegmentSections.compactMap { section -> TopSegmentSection? in
            let rows: [Statistics.TopRow]
            if let mask = section.mask {
                rows = top?.byMask.first(where: { $0.mask == mask })?.rows ?? []
            } else {
                rows = top?.all ?? []
            }
            return rows.isEmpty ? nil : TopSegmentSection(key: section.i18n, rows: rows)
        }
        // The unfiltered list's own best row is lifted out of the list and
        // into the highlight block — the reference's "Most flown aircraft"
        // — so the card opens with the answer rather than with a heading
        // over six category rows that all look alike. It is the same row,
        // read once: `summarised: false` below keeps 全部鐵道 from stating
        // it a second line later.
        let overall = sections.first(where: { $0.key == "stat.allrail" })?.rows.first
        return Group {
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    PassportCardHeader(
                        localization.text("stats.topSegmentsTitle"),
                        systemImage: "list.number")
                    if let overall {
                        PassportHighlight(
                            eyebrow: localization.text("ios.stats.topSection"),
                            title: StatisticsFormat.sectionLabel(overall, region: region, localization: localization),
                            detail:
                                "\(StatisticsFormat.rideCount(overall.count, localization: localization)) · \(StatisticsFormat.km(overall.km)) km")
                    }
                    Text(localization.text("stats.topSegmentsHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(sections) { section in
                        topSegmentSection(
                            key: section.key,
                            rows: section.rows,
                            summarised: !(overall != nil && section.key == "stat.allrail"))
                    }
                }
                .passportCard(.soft)
            }
        }
    }

    @ViewBuilder
    private func topSegmentSection(
        key: String, rows: [Statistics.TopRow], summarised: Bool = true
    ) -> some View {
        let best = rows[0]
        let count = localization.text(
            "stats.byCountCount", params: ["count": .number(Double(rows.count))])
        VStack(alignment: .leading, spacing: 8) {
            if summarised {
                adaptiveRow(
                    label: Text(localization.statsCategoryText(key)).font(.subheadline),
                    value: Text(verbatim: "\(StatisticsFormat.sectionLabel(best, region: region, localization: localization)) · \(StatisticsFormat.rideCount(best.count, localization: localization))")
                        .font(.subheadline.weight(.semibold)))
                    .accessibilityElement(children: .combine)
            }
            if rows.count > 1 {
                DisclosureGroup {
                    VStack(spacing: 10) {
                        ForEach(
                            Array(rows.prefix(Self.topSegmentLimit).enumerated()), id: \.offset
                        ) { _, row in
                            adaptiveRow(
                                label: Text(StatisticsFormat.sectionLabel(row, region: region, localization: localization)).font(.caption),
                                value: Text(verbatim:
                                    "\(StatisticsFormat.rideCount(row.count, localization: localization)) · \(StatisticsFormat.km(row.km)) km")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary))
                                .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    // The category names itself here when the row above was
                    // dropped, or the unfiltered list's disclosure would open
                    // under a bare 「12 件」 with nothing saying of what.
                    Text(verbatim: summarised ? count : "\(localization.statsCategoryText(key)) · \(count)")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    // MARK: - §5.7 #6 按線路與類別的詳細展開

    /// `categoryLineBreakdownHtml`, lifted out of the coverage rows into the
    /// detail section §5.7 puts last. Same rows, same order, same numbers.
    private func lineDetailCard(_ view: Statistics.MileageStatsView) -> some View {
        let sections = view.categories.compactMap { category -> CategoryDetail? in
            let rows = StatisticsLineCoverage.rows(
                mask: category.mask, totals: statistics.lineTotals,
                operators: statistics.lineOperators, ridden: view.overall.lineRidByCat)
            return rows.isEmpty ? nil : CategoryDetail(category: category, rows: rows)
        }
        return Group {
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // The same head row every other card on this screen opens
                    // with. The card's SURFACE stays `.plain` — §6.1 keeps the
                    // dense lists off the Memory stationery — but a card that
                    // titled itself in a different type from the nine above it
                    // read as a card from a different screen.
                    PassportCardHeader(
                        localization.text("ios.stats.detailTitle"),
                        systemImage: "list.bullet.indent")
                    ForEach(sections) { section in
                        DisclosureGroup {
                            VStack(spacing: 12) {
                                ForEach(section.rows) { row in lineRow(row) }
                            }
                            .padding(.top, 8)
                        } label: {
                            adaptiveRow(
                                label: Text(localization.statsCategoryText(section.category.i18n))
                                    .font(.subheadline.weight(.semibold)),
                                value: Text(localization.text(
                                    "stats.byLineCount",
                                    params: ["count": .number(Double(section.rows.count))]))
                                    .font(.caption)
                                    .foregroundStyle(.secondary))
                        }
                    }
                }
                .statisticsCard()
            }
        }
    }

    private func lineRow(_ line: StatisticsLineCoverage.Row) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            adaptiveRow(
                label: VStack(alignment: .leading, spacing: 1) {
                    if !line.company.isEmpty {
                        Text(line.company)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    // No line limit: a long line name wraps rather than being
                    // truncated or shrunk (§10.1, §10.4).
                    Text(line.name)
                        .font(.caption.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                },
                value: VStack(alignment: .trailing, spacing: 1) {
                    let reading = statistics.coverageReading(ridden: line.ridden, denominator: line.total, localization: localization)
                    Text(verbatim: reading.bar)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Text(verbatim: reading.known
                        ? "\(StatisticsFormat.km(line.ridden)) / \(StatisticsFormat.km(line.total)) km"
                        : reading.text)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line.company.isEmpty ? line.name : "\(line.company) \(line.name)"))
        .accessibilityValue(
            Text(statistics.coverageReading(ridden: line.ridden, denominator: line.total, localization: localization).spoken))
    }

    // MARK: - 乘坐分佈

    /// The shape of the travelling, on whichever of three axes the reader asks
    /// for.
    ///
    /// The reference draws a 0–4 scale down the left edge and leaves the
    /// columns bare. This one prints the count on every column instead — see
    /// ``StatisticsColumnChart`` for why — so the card carries no axis and the
    /// figures are exact rather than read off a rule.
    ///
    /// The one line above the chart is the answer somebody scrolling past
    /// actually wants: WHICH month, not what twelve months look like. It is
    /// the same lift `topSegmentsCard` makes for its own best row.
    private func rhythmCard(_ passport: PassportStatistics) -> some View {
        let columns = rhythmColumns(passport)
        let best = columns.max { $0.count < $1.count }
        return VStack(alignment: .leading, spacing: 14) {
            PassportCardHeader(
                localization.text("ios.stats.rhythmTitle"),
                systemImage: "chart.bar.xaxis")
            Picker(localization.text("ios.stats.scaleLabel"), selection: $rhythm) {
                ForEach(RhythmScale.allCases) { scale in
                    Text(localization.text(scale.localizationKey)).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Text(localization.text("ios.stats.scaleLabel")))

            if let best, best.count > 0 {
                PassportHighlight(
                    eyebrow: localization.text("ios.stats.mostJourneys"),
                    title: best.name,
                    detail: StatisticsFormat.journeyCount(best.count, localization: localization))
            }
            StatisticsColumnChart(columns: columns) { StatisticsFormat.journeyCount($0.count, localization: localization) }
                // The three axes share no bucket numbering — month 7 and
                // weekday 7 are different things — so the chart is REPLACED
                // rather than re-laid-out, and a crossfade is what §9.4 asks
                // for when one small thing appears where another was.
                .id(rhythm)
                .transition(.opacity)
            if passport.undated > 0 {
                Text(
                    localization.text(
                        "ios.stats.undatedHeld",
                        params: ["n": .number(Double(passport.undated))])
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(settle, value: rhythm)
        .passportCard(.soft)
    }

    private func rhythmColumns(_ passport: PassportStatistics)
        -> [StatisticsColumnChart.Column]
    {
        switch rhythm {
        case .year:
            // Four digits per column stops fitting somewhere past eight of
            // them, so a long record keeps the century for VoiceOver and the
            // highlight line and shows the axis the way every chart does.
            let abbreviate = passport.byYear.count > 8
            return passport.byYear.map { column in
                let full = String(column.id)
                return StatisticsColumnChart.Column(
                    id: column.id,
                    label: abbreviate ? String(full.suffix(2)) : full,
                    name: full,
                    count: column.count,
                    spoken: StatisticsFormat.journeyCount(column.count, localization: localization))
            }
        case .month:
            return passport.months(in: statistics.selectedYear).map { column in
                StatisticsColumnChart.Column(
                    id: column.id,
                    label: column.id.formatted(),
                    name: StatisticsFormat.monthName(column.id, localization: localization),
                    count: column.count,
                    spoken: StatisticsFormat.journeyCount(column.count, localization: localization))
            }
        case .weekday:
            return passport.weekdays(in: statistics.selectedYear).map { column in
                StatisticsColumnChart.Column(
                    id: column.id,
                    label: StatisticsFormat.weekdayLabel(column.id, short: true, localization: localization),
                    name: StatisticsFormat.weekdayLabel(column.id, short: false, localization: localization),
                    count: column.count,
                    spoken: StatisticsFormat.journeyCount(column.count, localization: localization))
            }
        }
    }

    // MARK: - 距離紀錄

    /// What the total distance means, in units nobody counts kilometres in.
    ///
    /// The total itself is not restated here — it is the passport page's own
    /// headline, three cards up. What this card adds is the three things the
    /// reference adds: the mean, the scale comparisons, and the two journeys
    /// at the ends of the range.
    private func distanceCard(_ passport: PassportStatistics, distancePending: Bool = false) -> some View {
        let scales = scaleRows(passport.totalKm)
        let longest = passport.longestByDistance
        let shortest = passport.shortestByDistance
        return VStack(alignment: .leading, spacing: 16) {
            PassportCardHeader(
                localization.text("ios.stats.distanceTitle"),
                systemImage: "ruler")
            StatisticsMetricRow(
                label: localization.text("ios.stats.perJourney"),
                value: distancePending ? localization.text("ios.routeGuide.unknownDistance")
                    : "\(StatisticsFormat.km(passport.averageKm)) km")
            if !scales.isEmpty {
                VStack(spacing: 10) { ForEach(scales) { row in row.view } }
            }
            if longest != nil || shortest != nil {
                PassportRule()
                VStack(spacing: 14) {
                    if let longest {
                        superlative(
                            "ios.stats.longestByDistance", longest,
                            value: "\(StatisticsFormat.km(longest.km)) km")
                    }
                    // Only when it is a different journey. With one record in
                    // scope the longest and the shortest are the same ride,
                    // and printing it twice under two headings says the store
                    // holds two.
                    if let shortest, shortest.id != longest?.id {
                        superlative(
                            "ios.stats.shortestByDistance", shortest,
                            value: "\(StatisticsFormat.km(shortest.km)) km")
                    }
                }
            }
        }
        .passportCard(.soft)
    }

    /// A scale row, built and kept identifiable so `ForEach` has something
    /// stable to key on.
    private struct ScaleRow: Identifiable {
        let id: String
        let view: StatisticsRankedRow
    }

    /// The comparisons that are worth drawing, and no others.
    ///
    /// A ratio under a two-hundredth reads as `0.00×`, which is a row that
    /// says nothing while taking up the space of one that does. So a short
    /// record shows the Earth row alone, and a long one shows all three.
    ///
    /// This is the only place the lap is counted now. The record card used to
    /// print 「地球 1.4 周」 under its headline as well; the design's 券面 has
    /// no caption under a 大字, and the row below states the same figure off
    /// the same circumference.
    private func scaleRows(_ km: Double) -> [ScaleRow] {
        guard km.isFinite, km > 0 else { return [] }
        return Self.scaleSpecs.compactMap { spec in
            let multiple = km / spec.km
            guard multiple >= 0.005 else { return nil }
            let label = localization.text(spec.i18n)
            let value = "\(multipleText(multiple))×"
            return ScaleRow(
                id: spec.i18n,
                view: StatisticsRankedRow(
                    label: label,
                    systemImage: spec.systemImage,
                    value: value,
                    fraction: min(1, multiple),
                    spoken: "\(value) \(label)"))
        }
    }

    /// `1.4`, `0.15`, `0.009` — enough digits that the figure is not rounded
    /// to nothing, and no more.
    private func multipleText(_ value: Double) -> String {
        let digits: Int
        switch abs(value) {
        case 10...: digits = 0
        case 0.1...: digits = 1
        case 0.01...: digits = 2
        default: digits = 3
        }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    // MARK: - 時間紀錄

    /// The ride-time total in the units it stops being imaginable in, and the
    /// two journeys at the ends of the clock.
    ///
    /// A month is 30 days and a year is 365 here, which is what makes these
    /// comparable rather than calendrical: the figure answers "how long have I
    /// spent on trains", and no reader is asking whether that stretch happened
    /// to contain a February.
    private func timeCard(_ passport: PassportStatistics) -> some View {
        let minutes = passport.totalMinutes
        let longest = passport.longestByTime
        let shortest = passport.shortestByTime
        return VStack(alignment: .leading, spacing: 16) {
            PassportCardHeader(
                localization.text("ios.stats.timeTitle"),
                systemImage: "clock")
            PassportMetricGrid(items: [
                .init(localization.text("ios.stats.days"), spanText(minutes / 1440)),
                .init(localization.text("ios.stats.weeks"), spanText(minutes / 10080)),
                .init(localization.text("ios.stats.months"), spanText(minutes / 43200)),
                .init(localization.text("ios.stats.years"), spanText(minutes / 525_600)),
            ])
            StatisticsMetricRow(
                label: localization.text("ios.stats.perJourney"),
                value: StatisticsFormat.duration(passport.averageMinutes, localization))
            if longest != nil || shortest != nil {
                PassportRule()
                VStack(spacing: 14) {
                    if let longest {
                        superlative(
                            "ios.stats.longestByTime", longest,
                            value: StatisticsFormat.duration(longest.minutes, localization))
                    }
                    if let shortest, shortest.id != longest?.id {
                        superlative(
                            "ios.stats.shortestByTime", shortest,
                            value: StatisticsFormat.duration(shortest.minutes, localization))
                    }
                }
            }
        }
        .passportCard(.soft)
    }

    /// The same digit rule the scale rows use, on a span rather than a ratio —
    /// so `0.009` years is a figure and not a zero.
    private func spanText(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return multipleText(value)
    }

    // MARK: - 常用車站、業者與路線

    /// 最常進出的車站 — where the reader has boarded and got off most.
    private func stationsCard(_ passport: PassportStatistics) -> some View {
        let rows = rankedRows(passport.stations, metric: .count) {
            StatisticsFormat.placeName($0.name, in: $0.region, region: region, localization: localization)
        }
        return rankedCard(
            title: localization.text("ios.stats.stationsTitle"),
            systemImage: "building.columns",
            total: passport.stations.count,
            unit: localization.text("ios.stats.unit.stations"),
            hint: localization.text("ios.stats.stationsHint"),
            rows: rows)
    }

    /// 最常乘坐的業者 — this app's one place
    /// where the record's own `company` is counted rather than derived from
    /// the network. Two operators can share a short label, so the tally is
    /// keyed on the raw name and only the DISPLAY is shortened.
    private func operatorsCard(_ passport: PassportStatistics) -> some View {
        let rows = rankedRows(passport.operators, metric: operatorMetric) {
            StatisticsFormat.companyLabel($0.name)
        }
        return rankedCard(
            title: localization.text("ios.stats.operatorsTitle"),
            systemImage: "building.2",
            total: passport.operators.count,
            unit: localization.text("ios.stats.unit.operators"),
            hint: nil,
            rows: rows,
            metric: $operatorMetric)
    }

    /// 最常乘坐的起訖 — the reference's Top Routes.
    ///
    /// Deliberately NOT the same list as 最常乘坐區間 below it: a route is the
    /// two ends of a journey, and a section is a stretch of track that several
    /// different journeys may each cover part of. 東京↔新大阪 ridden four
    /// times is one route and about thirty sections.
    private func routesCard(_ passport: PassportStatistics) -> some View {
        let rows = rankedRows(passport.routes, metric: routeMetric) { tally in
            "\(StatisticsFormat.placeName(tally.name, in: tally.region, region: region, localization: localization)) ↔ \(StatisticsFormat.placeName(tally.pair ?? "", in: tally.region, region: region, localization: localization))"
        }
        return rankedCard(
            title: localization.text("ios.stats.routesTitle"),
            systemImage: "arrow.left.arrow.right",
            total: passport.routes.count,
            unit: localization.text("ios.stats.unit.routes"),
            hint: localization.text("ios.stats.routesHint"),
            rows: rows,
            metric: $routeMetric,
            // Two station names and an arrow. In the gutter an inline row
            // gives them, that wraps to three lines and breaks inside a
            // reading's own brackets — 「三島（みし／ま）」 — so this list
            // takes the card's full width for its names.
            layout: .stacked)
    }

    /// One ranked card: the total, an optional 趟數/里程 control, the bars, and
    /// the sentence that says what a row counts.
    ///
    /// One function rather than three copies, because the three lists differ
    /// only in what they are lists OF — and the reference draws them
    /// identically for exactly that reason.
    @ViewBuilder
    private func rankedCard(
        title: String, systemImage: String, total: Int, unit: String, hint: String?,
        rows: [StatisticsRankedList.Row], metric: Binding<RankMetric>? = nil,
        layout: StatisticsRankedRow.Layout = .inline
    ) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PassportCardHeader(title, systemImage: systemImage)
                PassportHeadline(
                    label: title,
                    value: total.formatted(),
                    spoken: "\(total.formatted()) \(unit)",
                    unit: unit,
                    // A field, not a page headline: the one `largeTitle` on
                    // this screen belongs to the passport page.
                    prominence: .field)
                if let metric {
                    Picker(localization.text("ios.stats.rankBy"), selection: metric) {
                        ForEach(RankMetric.allCases) { option in
                            Text(localization.text(option.localizationKey)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(Text(localization.text("ios.stats.rankBy")))
                }
                StatisticsRankedList(
                    rows: rows,
                    visible: Self.rankedListLimit,
                    moreLabel: localization.text(
                        "ios.stats.showMore",
                        params: [
                            "n": .number(Double(max(0, rows.count - Self.rankedListLimit)))
                        ]),
                    layout: layout
                )
                .animation(settle, value: metric?.wrappedValue)
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .passportCard(.soft)
        }
    }

    /// A tally list, ordered and spelled for whichever metric is showing.
    ///
    /// The bars are a share of the LEADING row rather than of the total (see
    /// ``StatisticsRankedList``), and the figure beside each one is the real
    /// number, so both readings of "most" answer with the same rows in the
    /// same order whichever control is set.
    private func rankedRows(
        _ tallies: [PassportStatistics.Tally],
        metric: RankMetric,
        label: (PassportStatistics.Tally) -> String
    ) -> [StatisticsRankedList.Row] {
        // Already ordered by count; ordering by distance is the same list read
        // the other way, with the same tie-break underneath it.
        let ordered = metric == .count
            ? tallies
            : tallies.sorted { a, b in
                if a.km != b.km { return a.km > b.km }
                if a.count != b.count { return a.count > b.count }
                return StatisticsFormat.linesPrecede(a.id, b.id)
            }
        return ordered.map { tally in
            let count = StatisticsFormat.rideCount(tally.count, localization: localization)
            let km = "\(StatisticsFormat.km(tally.km)) km"
            return StatisticsRankedList.Row(
                id: tally.id,
                label: label(tally),
                value: metric == .count ? count : km,
                magnitude: metric == .count ? Double(tally.count) : tally.km,
                // Both figures, whichever is drawn: the bar is one of them and
                // a reader who cannot see it needs the other too.
                spoken: "\(count) · \(km)")
        }
    }

    // MARK: - 國家與地區

    /// Which of the five networks the passport has stamps from.
    ///
    /// Shown only when there is more than one — see the call site. The flag is
    /// decoration and is hidden from VoiceOver: the region names itself on the
    /// same row, and 「🇯🇵 日本」 read aloud is the country twice.
    private func regionsCard(_ passport: PassportStatistics) -> some View {
        let peak = Double(passport.regions.map(\.count).max() ?? 0)
        return VStack(alignment: .leading, spacing: 14) {
            PassportCardHeader(
                localization.text("ios.stats.regionsTitle"),
                systemImage: "globe.asia.australia")
            PassportHeadline(
                label: localization.text("ios.stats.regionsTitle"),
                value: passport.regions.count.formatted(),
                spoken: "\(passport.regions.count.formatted()) "
                    + localization.text("ios.stats.unit.regions"),
                unit: localization.text("ios.stats.unit.regions"),
                prominence: .field)
            VStack(spacing: 10) {
                ForEach(passport.regions) { tally in
                    StatisticsRankedRow(
                        label: StatisticsFormat.regionName(tally.region, localization: localization),
                        emblem: StatisticsFormat.flag(tally.region),
                        value: StatisticsFormat.rideCount(tally.count, localization: localization),
                        fraction: peak > 0 ? Double(tally.count) / peak : 0,
                        spoken:
                            "\(StatisticsFormat.rideCount(tally.count, localization: localization)) · \(StatisticsFormat.km(tally.km)) km")
                }
            }
        }
        .passportCard(.soft)
    }

    // MARK: - a superlative, named

    /// One end of a range — the reference's "Shortest flight" / "Longest
    /// flight", as a journey this app can name.
    private func superlative(
        _ key: String, _ journey: PassportStatistics.Journey, value: String
    ) -> some View {
        let endpoints = "\(StatisticsFormat.placeName(journey.from, in: journey.region, region: region, localization: localization)) → \(StatisticsFormat.placeName(journey.to, in: journey.region, region: region, localization: localization))"
        let caption = journeyCaption(journey)
        let train = ridden(journey)
        return StatisticsSuperlative(
            eyebrow: localization.text(key),
            title: endpoints,
            detail: caption,
            value: value,
            spoken: "\(endpoints) · \(value) · \(caption)",
            ride: train.map {
                StatisticsSuperlative.Ride(train: $0, presentation: journeyPresentation($0))
            },
            open: train.map { train in { openJourney(train) } })
    }

    /// The record a superlative is about.
    ///
    /// `PassportStatistics.Journey.id` IS the record's id — the statistics are
    /// built from these very trains — so this is a lookup rather than a match.
    /// It can still miss for a frame: the passport grouping arrives from its
    /// own store while the working set is being replaced, and a journey just
    /// deleted is named by numbers computed before it was. `nil` is what
    /// ``StatisticsSuperlative/Ride`` is optional for.
    private func ridden(_ journey: PassportStatistics.Journey) -> Train? {
        itineraries.loaded?.trains.first { $0.id == journey.id }
    }

    /// The train, and the day it ran — the reference's "WS 255 · 20 Feb 2025".
    private func journeyCaption(_ journey: PassportStatistics.Journey) -> String {
        let day = journey.date.isEmpty ? nil : StatisticsFormat.dayLabel(journey.date, localization: localization)
        return [journey.title, day].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - states that are not numbers

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                localization.text("ios.stats.failedTitle"),
                systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(localization.text("ios.stats.failedBody"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .statisticsCard()
        .accessibilityElement(children: .combine)
    }

    /// Nothing to count — and, when that is only true *until the reader says
    /// otherwise*, why.
    ///
    /// A reader whose whole store is unconfirmed journeys would otherwise be
    /// told they have ridden nothing, which is both true and useless. The
    /// second line is what makes the first one readable.
    private func emptyCard(unconfirmed: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.text("stats.empty"))
            if unconfirmed > 0 {
                Text(unconfirmedMessage(unconfirmed))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statisticsCard()
    }

    /// 「尚未確認乘坐：N 趟。在行程詳情裡確認後就會計入。」
    private func unconfirmedMessage(_ count: Int) -> String {
        localization.text(
            "ios.stats.unconfirmedHeld", params: ["n": .number(Double(count))])
    }

    // MARK: - shared bits

    /// Keep both sides readable when the card is narrow or text is enlarged.
    @ViewBuilder
    private func adaptiveRow(label: some View, value: some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                label.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                value
                    .fixedSize(horizontal: true, vertical: false)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                label
                value
                    .multilineTextAlignment(.leading)
            }
        }
    }

    /// What this screen counts, and what it is holding back.
    ///
    /// The two travel together because they are one pass over the store, and
    /// because they are read together: the second is what stops the first from
    /// looking like a loss. A reader who has just written down a journey and
    /// watched 旅程數 not move needs a line saying why, and "waiting for you to
    /// confirm it" is a very different message from a number that silently did
    /// not change.
    private struct Scope {
        let loaded: ItineraryStore.Loaded
        /// Journeys in the region scope whose records do not say they were
        /// ridden.
        let unconfirmed: Int
    }

    /// This screen's slice of the working set: one region's confirmed rides,
    /// and the date buckets they occupy.
    ///
    /// The region itself is chosen in the panel header, which offers every
    /// region rather than only the ones with rides in them: a coverage figure
    /// of 0 % for a region you have not ridden is an answer, and a region that
    /// disappeared from the picker as soon as its last ride was deleted would
    /// look like a bug.
    ///
    /// The second filter is not a scope the reader chose. 旅程數, 出行日 and
    /// 停站數 are counted HERE while every kilometre beside them is counted in
    /// the store, so both have to draw the line between a journey taken and a
    /// journey merely written down in the same place — `MileageStatisticsStore`
    /// is handed a list already filtered by ``RailCore/RideLedger``,
    /// and a card that said "8 journeys, 0 km" because two of them were never
    /// confirmed would be this screen disagreeing with itself.
    private func scoped(_ loaded: ItineraryStore.Loaded) -> Scope {
        // The region + ridden filter, memoised: this used to re-run over
        // every journey and rebuild every `days` bucket on every body
        // evaluation, including the ones a sheet drag causes while nothing
        // about the scope changed.
        let slice = derived.passportScope(
            trains: loaded.trains, days: loaded.days, region: region, year: statistics.selectedYear,
            groupID: statistics.selectedJourneyGroupID, dates: statistics.dateSelection,
            scopeKey: memberKey.map(String.init) ?? "", memberIDs: memberIDs
        )
        return Scope(
            loaded: ItineraryStore.Loaded(
                regions: region.map { [$0] } ?? Region.enabledOrdered,
                trains: slice.trains,
                days: slice.days,
                elapsed: loaded.elapsed),
            unconfirmed: slice.unconfirmed)
    }

}
