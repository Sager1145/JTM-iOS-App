import RailCore
import RailPresentation
import SwiftUI

/// The mileage statistics, as a SECTION rather than as a screen.
///
/// §2.2 folds this into Passport: the statistics are one of five things that
/// workspace shows, between the coverage map above and the journey log below.
/// So this type is a stack of cards with no `ScrollView`, no navigation title
/// and no toolbar of its own — `PassportWorkspaceView` owns all three, and a
/// section that brought its own scroll view would be a scroll view inside a
/// scroll view.
///
/// It carries no scope control at all. §5.3.1 puts Scope at the top of
/// Passport and §5.1 forbids a second filter source for one value, so the
/// region and the date are both chosen in the panel header and arrive here as
/// inputs — the region as a `Binding`, the date through the statistics store.
///
/// The cards answer one question in the order §5.7 asks it: how much have I
/// ridden, over how many journeys and days, how much of the network is that,
/// what kind of trains were they, which sections do I ride most, and then the
/// line-by-line detail underneath.
///
/// Above all of it sits 當日統計, which is where `app-stats-render.js` puts it
/// too: `renderMileageStatsDom` writes `#stats-daily` before it writes the
/// all-time block, and that block is rendered whether or not a day is
/// selected — reading `--` in every field when it is not. The dashes are the
/// point. `0 km` would be an answer, and "no day is in scope" is not an
/// answer, so the combined view never spells one.
///
/// ## The stationery (§6.1)
///
/// These cards are drawn as passport pages rather than as system cards, which
/// is the Memory personality §6.1 reserves for exactly this screen —
/// "expressive / railway-signage / ticket-and-map metaphors / souvenir-like".
/// The tones come from `PassportCardStyle.swift` and are assigned here:
///
///   - `.feature`, once, for ``passportDataPage(_:_:)`` — the card that
///     answers §5.3's question.
///   - `.soft` for the three cards that carry charts, so a screen with one
///     loud card still reads as one set of pages rather than as a poster with
///     receipts stapled to it.
///   - `.plain` for the dense line-by-line lists and for every state that is
///     not a number: a failure, an empty scope, a calculation in progress.
///     §6.1 is explicit that the Memory style must not be worn by a card
///     reporting that something went wrong.
///
/// Three cards were merged into one page — §5.7 #1, #2 and 當日統計, see
/// ``passportDataPage(_:_:)`` — and one row was lifted out of a list into a
/// highlight (§5.7 #5). The date scope left with the daily card: it is in the
/// panel header now, beside the region, where §5.3.1 puts Scope and where it
/// stays visible at every sheet stop. Nothing else moved: same figures, same
/// order, same wording, and the same VoiceOver sentences over the top of them.
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

    /// §13.2: work under about 400 ms must not flash progress UI at the
    /// reader. Held here rather than inside the summary because the summary is
    /// mounted and unmounted by this decision.
    @State private var progressVisible = false

    /// Which axis 乘坐分佈 is drawn on — the reference's "FLIGHTS PER Year /
    /// Month / Weekday".
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether this is being drawn into the share image rather than onto the
    /// screen — see ``SwiftUI/EnvironmentValues/passportPoster``.
    @Environment(\.passportPoster) private var isPoster

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

    private struct ServiceRow: Identifiable {
        let key: String
        let group: Statistics.ServiceGroup
        var id: String { key }
    }

    private struct TopSegmentSection: Identifiable {
        let key: String
        let rows: [Statistics.TopRow]
        var id: String { key }
    }

    private struct CategoryDetail: Identifiable {
        let category: Statistics.Category
        let rows: [LineCoverageRow]
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
                // ``RailPresentation/RideLedger``), so the screen says how many
                // it is holding back and where to confirm them.
                let unconfirmed = scope.unconfirmed
                // A plain VStack, not Lazy: the caller is already a LazyVStack
                // inside the workspace's one ScrollView, and nesting a second
                // lazy container inside it defeats both.
                VStack(spacing: 16) {
                    if progressVisible, let progress = statistics.progress {
                        StatisticsProgressSummary(progress: progress)
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
                        passportDataPage(loaded, stats.overall, unconfirmed: unconfirmed)
                        // §5.7's order, with the reference's own sections
                        // folded into it: what the shape of the travelling was,
                        // then the two records the distance and the clock hold,
                        // then coverage and 車種, then who and where.
                        if let passport {
                            rhythmCard(passport)
                            distanceCard(passport)
                            timeCard(passport)
                        }
                        coverageCard(stats)
                        serviceCard(stats.overall)
                        if let passport {
                            stationsCard(passport)
                            operatorsCard(passport)
                            routesCard(passport)
                        }
                        topSegmentsCard(stats.overall)
                        // Only when there is more than one. Scoped to Japan,
                        // this card would be the scope control's own answer
                        // read back — a country list of length one (§5.1).
                        if let passport, passport.regions.count > 1 {
                            regionsCard(passport)
                        }
                        lineDetailCard(stats)
                    }
                }
            } else {
                ProgressView(localization.statsText("ios.stats.calculating"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
        .task(id: statistics.progress == nil) {
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
            guard statistics.progress != nil else {
                withAnimation(settle) { progressVisible = false }
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            let visible = statistics.progress != nil
            withAnimation(settle) { progressVisible = visible }
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

    // MARK: - 當日統計, as a stamp on the passport

    /// `#stats-daily`'s subtitle: how long, over how many trains.
    private func dailySubtitle(_ daily: Statistics.DailyStats?) -> String {
        let time = daily.map { StatisticsFormat.duration($0.stats.rideMinutes, localization) }
            ?? StatisticsFormat.unset
        let trains = localization.statsText(
            "stat.trains",
            params: [
                "n": daily.map { Localization.Param.number(Double($0.trainCount)) }
                    ?? .string(StatisticsFormat.unset)
            ])
        return "\(localization.statsText("stat.time")) \(time) · \(trains)"
    }

    /// `#stats-daily`, as a stamp inside the passport rather than as a card
    /// above it.
    ///
    /// The web app renders this block whether or not a day is chosen, with
    /// `--` in every field, because in the browser the date bar that scopes it
    /// is a different region of the page. Here the scope control sits in the
    /// panel header — visible at every sheet stop, on this destination only —
    /// so "no day is in scope" is stated by the control that owns the scope.
    /// A block of dashes underneath it would say the same thing a second time,
    /// in the one register §13.1 rules out.
    private func dailyStamp(_ daily: Statistics.DailyStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PassportEyebrow(localization.statsText("ios.stats.dailyHeading"))
                Spacer(minLength: 8)
                PassportEyebrow(scopeLabel(daily.date))
            }
            PassportHeadline(
                label: localization.statsText(
                    "stats.dailyTitle", params: ["date": .string(scopeLabel(daily.date))]),
                value: StatisticsFormat.km(daily.stats.riddenAll),
                spoken: dailySpoken(daily),
                unit: "km",
                caption: dailySubtitle(daily),
                // A field inside the page, not a second page headline: the
                // day is part of the total above it, and two `largeTitle`
                // figures on one card is two cards.
                prominence: .field)
            // Same mutually-exclusive ride groups as 實際乘坐量; the
            // overlapping network-category rows the panel once carried here
            // were removed.
            PassportRule()
            VStack(spacing: 8) {
                ForEach(serviceRows(daily.stats.services)) { row in
                    PassportRow(
                        label: localization.statsCategoryText(row.key),
                        value:
                            "\(StatisticsFormat.km(row.group.km)) km · \(serviceDetail(row.group))")
                }
            }
        }
        .passportBlock()
    }

    private func dailySpoken(_ daily: Statistics.DailyStats?) -> String {
        guard let daily else { return localization.statsText("ios.stats.unsetSpoken") }
        return "\(StatisticsFormat.km(daily.stats.riddenAll)) km · \(dailySubtitle(daily))"
    }

    /// `dateLabel` — the two sentinels need a word, a real bucket labels itself.
    private func scopeLabel(_ date: String) -> String {
        let key = Dates.dateLabelKey(date)
        return localization.text(key, fallback: key)
    }

    // MARK: - §5.7 #1 + #2 — the passport data page

    /// 總乘車里程, the fields that qualify it, and the day in scope — one page.
    ///
    /// §5.3.3 asks for the distance first and 旅程數 / 出行日 / 停站數 /
    /// 乘車時間 second, and that is the order here — but as ONE card rather
    /// than three, which is where this screen departs from a card-per-item
    /// reading of the spec. The reason is the thing being imitated: a passport
    /// data page is a headline with its fields under it, and on separate
    /// surfaces the total read as the answer to a different question from the
    /// journey count that produced it.
    ///
    /// One field is not in §5.3.3's list: 乗車路線, the number of distinct
    /// lines ridden and the companies that run them. It is the reference's
    /// AIRLINES field, it is free (the aggregate already carries the per-line
    /// table), and it answers the question a coverage percentage cannot —
    /// 31 % of the network is not a thing anyone has ridden, 125 lines is.
    ///
    /// It is also the one `.feature` card on the screen (§6.1's Memory
    /// personality — see `PassportCardStyle.swift`). One, because a screen
    /// where every card is loud has no hero, and this is the card that answers
    /// §5.3's question: **how much have I ridden, and which railways does that
    /// cover?**
    private func passportDataPage(
        _ loaded: ItineraryStore.Loaded, _ stats: Statistics.MileageStats,
        unconfirmed: Int
    ) -> some View {
        let total = statistics.totalKm
        let pct = total > 0 ? 100 * stats.riddenAll / total : 0
        let ridden = riddenLines(stats)
        let laps = aroundTheWorld(stats.riddenAll)
        let distance = StatisticsFormat.km(stats.riddenAll)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                // No region chip and no date menu on the card. Both scopes are
                // chosen in the panel header now — one row, always visible, on
                // this destination only — and a card that repeated either
                // would be a second place for one value to be stated (§5.1).
                PassportEyebrow(localization.statsText("ios.stats.passportTitle"))
                PassportBookletLine()
            }

            PassportHeadline(
                label: localization.statsText("ios.stats.totalDistance"),
                value: distance,
                spoken: laps.map { "\(distance) km · \($0)" } ?? "\(distance) km",
                unit: "km",
                caption: laps)

            PassportMetricGrid(items: [
                .init(
                    localization.statsText("ios.stats.journeysLabel"),
                    loaded.trains.count.formatted(),
                    caption: highSpeedCaption(stats.services)),
                .init(
                    localization.text("ios.rideTime", fallback: "Ride time"),
                    StatisticsFormat.duration(stats.rideMinutes, localization)),
                .init(
                    localization.text("ios.travelDays", fallback: "Travel days"),
                    loaded.days.count.formatted()),
                .init(
                    localization.text("ios.stops", fallback: "Stops"),
                    stopCount(loaded.trains).formatted()),
                .init(
                    localization.statsText("ios.stats.linesRidden"),
                    ridden.lines.formatted(),
                    caption: ridden.operators > 0
                        ? localization.statsText(
                            "ios.stats.operatorCount",
                            params: ["n": .number(Double(ridden.operators))])
                        : nil),
            ])

            // The same three numbers the old hero footnote carried — the
            // percentage, the denominator, and what they are a fraction of —
            // in the band the reference puts its footer chip in. Not a
            // navigation: the coverage card is the next card down in the same
            // scroll view, and a button that scrolls the reader somewhere they
            // can already see is furniture.
            PassportBand(
                label: localization.statsText("stats.coverageTitle"),
                value: "\(StatisticsFormat.percent(pct))%",
                detail: "\(distance) / \(StatisticsFormat.km(total)) km",
                fraction: total > 0 ? stats.riddenAll / total : 0,
                spoken: coverageSpoken(ridden: stats.riddenAll, total: total))

            // The selected day, stamped on the page it is part of (§5.3.3's
            // Daily module). Below the all-time block rather than above it, so
            // the passport's own headline and fields stay contiguous and the
            // day reads as what it is: one entry in them.
            if let daily = statistics.view?.daily {
                dailyStamp(daily)
            }

            // Why 旅程數 is not the number of journeys in the store. Beside
            // the field it qualifies rather than at the foot of the screen,
            // and in the same neutral register as the unmatched note below: a
            // journey nobody has confirmed riding is not a fault in the data,
            // it is a question the app has not been answered.
            if unconfirmed > 0 {
                PassportNote(
                    title: localization.statsText("ios.stats.unconfirmedTitle"),
                    message: unconfirmedMessage(unconfirmed),
                    systemImage: "checkmark.circle")
            }

            // §5.7: a neutral note, not the critical role. Unmatched distance
            // means the drawn ride left the classified network for a stretch —
            // it is information about coverage, not a data error.
            if stats.unmatchedKm > 0.01 {
                PassportNote(
                    title: localization.statsText("ios.stats.unmatchedTitle"),
                    message: localization.text(
                        "ios.unmatchedDistance",
                        params: ["km": .string(StatisticsFormat.km(stats.unmatchedKm))],
                        fallback: "\(StatisticsFormat.km(stats.unmatchedKm)) km unmatched"))
            }
        }
        .passportCard(.feature)
        .accessibilityElement(children: .contain)
    }

    /// The reference's "1.4x around the world", in the only unit that means
    /// anything to someone who has been counting kilometres: laps of the
    /// equator, at the WGS-84 circumference the map's own distances are
    /// measured on.
    ///
    /// `nil` under a twentieth of a lap, where the figure would read 「地球
    /// 0.0 周」 and say nothing. Expressive is not the same as inventing a
    /// number — §5.3 asks for both at once ("可以比编辑界面更有表现力，但数字仍
    /// 应准确、克制").
    private func aroundTheWorld(_ km: Double) -> String? {
        guard km.isFinite, km > 0 else { return nil }
        let laps = km / 40075.017
        guard laps >= 0.05 else { return nil }
        let digits = laps >= 1 ? 1 : 2
        return localization.statsText(
            "ios.stats.earthLaps",
            params: [
                "n": .string(laps.formatted(.number.precision(.fractionLength(digits))))
            ])
    }

    /// The reference's "4 Long Haul" — the one qualifier a journey count is
    /// worth carrying.
    ///
    /// `stat.hsr` is a country-variant key (新幹線 / 高鐵 / 고속철도), so it
    /// goes through `statsCategoryText` and says whichever of those the region
    /// in scope calls it.
    private func highSpeedCaption(_ services: Statistics.ServiceGroups) -> String? {
        guard services.hsr.count > 0 else { return nil }
        let trains = localization.statsText(
            "stat.trains", params: ["n": .number(Double(services.hsr.count))])
        return "\(localization.statsCategoryText("stat.hsr")) \(trains)"
    }

    /// How many distinct lines the reader has been on, and how many companies
    /// operate them — the passport's AIRLINES field, in this app's terms.
    ///
    /// Counted off `lineRidByCat` rather than off the ride records: it is
    /// keyed by line name and holds the ridden kilometres per category, so a
    /// line counts once however many categories it appears in, and a line the
    /// reader has never been on does not count at all. Operators come from the
    /// raw N02 name rather than the short label, because two companies can
    /// share a short label and the count would then be one too few.
    private func riddenLines(_ stats: Statistics.MileageStats)
        -> (lines: Int, operators: Int)
    {
        var lines = 0
        var operators: Set<String> = []
        for (name, byMask) in stats.lineRidByCat.pairs {
            guard byMask.values.contains(where: { $0 > 0 }) else { continue }
            lines += 1
            let operatorName = statistics.lineOperators[name] ?? ""
            if !operatorName.isEmpty { operators.insert(operatorName) }
        }
        return (lines, operators.count)
    }

    // MARK: - §5.7 #3 路網覆蓋率

    private func coverageCard(_ view: Statistics.MileageStatsView) -> some View {
        let stats = view.overall
        let total = statistics.totalKm
        let pctAll = total > 0 ? 100 * stats.riddenAll / total : 0
        return VStack(alignment: .leading, spacing: 16) {
            PassportCardHeader(
                localization.statsText("stats.coverageTitle"),
                systemImage: "chart.bar.xaxis")
            StatisticsBar(
                label: localization.statsCategoryText("stat.all"),
                value: "\(StatisticsFormat.percent(pctAll))%",
                detail: "\(StatisticsFormat.km(stats.riddenAll)) / \(StatisticsFormat.km(total)) km",
                fraction: total > 0 ? stats.riddenAll / total : 0,
                spoken: coverageSpoken(ridden: stats.riddenAll, total: total))
            ForEach(view.categories, id: \.mask) { category in
                let ridden = stats.riddenByMask[category.mask] ?? 0
                let categoryTotal = statistics.totalsByMask[category.mask] ?? 0
                StatisticsBar(
                    label: localization.statsCategoryText(category.i18n),
                    value: "\(StatisticsFormat.percent(percentage(ridden, categoryTotal)))%",
                    detail:
                        "\(StatisticsFormat.km(ridden)) / \(StatisticsFormat.km(categoryTotal)) km",
                    fraction: categoryTotal > 0 ? ridden / categoryTotal : 0,
                    spoken: coverageSpoken(ridden: ridden, total: categoryTotal))
            }
            // The one sentence that stops these being read as an accumulating
            // odometer: the numerator is a deduped union over ridden intervals,
            // the denominator the whole N02 network.
            Text(localization.statsText("stats.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .passportCard(.soft)
    }

    private func coverageSpoken(ridden: Double, total: Double) -> String {
        localization.statsText(
            "ios.stats.coverageA11y",
            params: [
                "pct": .string(StatisticsFormat.percent(percentage(ridden, total))),
                "ridden": .string(StatisticsFormat.km(ridden)),
                "total": .string(StatisticsFormat.km(total)),
            ])
    }

    private func percentage(_ part: Double, _ whole: Double) -> Double {
        whole > 0 ? 100 * part / whole : 0
    }

    // MARK: - §5.7 #4 車種組合

    /// `stats.actualTitle` + `serviceRowsHtml` + the ride-time row.
    ///
    /// Deliberately no coverage percentage: repeat rides count each time, so
    /// there is no denominator these could be a percentage *of*. The bar is a
    /// share of the ride distance the three groups add up to, which is a ratio
    /// of numbers the aggregate already carries, and every figure it draws is
    /// spelled out beside it (§10.2).
    private func serviceCard(_ stats: Statistics.MileageStats) -> some View {
        let groups = serviceRows(stats.services)
        let totalKm = groups.reduce(0) { $0 + $1.group.km }
        return VStack(alignment: .leading, spacing: 16) {
            PassportCardHeader(
                localization.statsText("stats.actualTitle"),
                systemImage: "chart.bar.fill")
            ForEach(groups) { row in
                StatisticsBar(
                    label: localization.statsCategoryText(row.key),
                    value: "\(StatisticsFormat.km(row.group.km)) km",
                    detail: serviceDetail(row.group),
                    fraction: totalKm > 0 ? row.group.km / totalKm : 0,
                    spoken:
                        "\(StatisticsFormat.km(row.group.km)) km · \(serviceDetail(row.group))")
            }
            Divider()
            StatisticsMetricRow(
                label: localization.statsText("stat.time"),
                value: StatisticsFormat.duration(stats.rideMinutes, localization))
        }
        .passportCard(.soft)
    }

    /// `serviceRowsHtml`'s three rows, in its order.
    private func serviceRows(_ services: Statistics.ServiceGroups) -> [ServiceRow] {
        [
            ServiceRow(key: "stat.hsr", group: services.hsr),
            ServiceRow(key: "stat.ltdexp", group: services.ltd),
            ServiceRow(key: "stat.othertrains", group: services.other),
        ]
    }

    private func serviceDetail(_ group: Statistics.ServiceGroup) -> String {
        let time = StatisticsFormat.duration(group.minutes, localization)
        let trains = localization.statsText(
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
                        localization.statsText("stats.topSegmentsTitle"),
                        systemImage: "list.number")
                    if let overall {
                        PassportHighlight(
                            eyebrow: localization.statsText("ios.stats.topSection"),
                            title: sectionLabel(overall),
                            detail:
                                "\(rideCount(overall.count)) · \(StatisticsFormat.km(overall.km)) km")
                    }
                    Text(localization.statsText("stats.topSegmentsHint"))
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
        let count = localization.statsText(
            "stats.byCountCount", params: ["count": .number(Double(rows.count))])
        VStack(alignment: .leading, spacing: 8) {
            if summarised {
                adaptiveRow(
                    label: Text(localization.statsCategoryText(key)).font(.subheadline),
                    value: Text(verbatim: "\(sectionLabel(best)) · \(rideCount(best.count))")
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
                                label: Text(sectionLabel(row)).font(.caption),
                                value: Text(verbatim:
                                    "\(rideCount(row.count)) · \(StatisticsFormat.km(row.km)) km")
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

    /// `sectionLabel` — the two endpoint names, through the readings table.
    ///
    /// `topRiddenSegments` names a section by its endpoints and carries no
    /// station codes, so this is the by-name lookup: in a region scope it is
    /// that region's table, and in the 全部 scope it is whichever table knows
    /// the name unambiguously (see `AppLocalization.regionNaming`). The web
    /// app's `topSegmentsHtml` uses `I18N.placeName` here, so a Japanese
    /// section still carries its kana or romaji reading.
    private func sectionLabel(_ row: Statistics.TopRow) -> String {
        "\(placeName(row.from)) ↔ \(placeName(row.to))"
    }

    private func placeName(_ name: String) -> String {
        localization.placeName(name, region: region ?? localization.regionNaming(name))
    }

    private func rideCount(_ count: Int) -> String {
        localization.statsText("stat.rides", params: ["n": .number(Double(count))])
    }

    // MARK: - §5.7 #6 按線路與類別的詳細展開

    /// `categoryLineBreakdownHtml`, lifted out of the coverage rows into the
    /// detail section §5.7 puts last. Same rows, same order, same numbers.
    private func lineDetailCard(_ view: Statistics.MileageStatsView) -> some View {
        let sections = view.categories.compactMap { category -> CategoryDetail? in
            // 新幹線 has only about eleven lines, so listing the unridden ones
            // keeps a 0% 山形/秋田新幹線 visible; 地下鐵 is small enough for the
            // same treatment. 在來線 / JR / 私鐵 stay ridden-only, or the list
            // would be hundreds of 0% rows.
            let rows = lineCoverageRows(
                mask: category.mask,
                includeUnridden: category.mask == Statistics.maskHSR
                    || category.mask == Statistics.maskMETRO,
                ridden: view.overall.lineRidByCat)
            return rows.isEmpty ? nil : CategoryDetail(category: category, rows: rows)
        }
        return Group {
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        localization.statsText("ios.stats.detailTitle"),
                        systemImage: "list.bullet.indent")
                        .font(.headline)
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
                                value: Text(localization.statsText(
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

    private func lineRow(_ line: LineCoverageRow) -> some View {
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
                    Text(verbatim: "\(StatisticsFormat.percent(line.percent))%")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Text(verbatim:
                        "\(StatisticsFormat.km(line.ridden)) / \(StatisticsFormat.km(line.total)) km")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line.company.isEmpty ? line.name : "\(line.company) \(line.name)"))
        .accessibilityValue(
            Text(coverageSpoken(ridden: line.ridden, total: line.total)))
    }

    private struct LineCoverageRow: Identifiable {
        let name: String
        /// The raw N02 operator, which is what the ORDER is built on.
        let operatorName: String
        /// The short label the rows are grouped by, which is what is SHOWN.
        let company: String
        let total: Double
        let ridden: Double
        var id: String { "\(operatorName)\u{001F}\(name)" }
        var percent: Double { total > 0 ? 100 * ridden / total : 0 }
    }

    private func lineCoverageRows(
        mask: Int, includeUnridden: Bool,
        ridden: Statistics.OrderedDictionary<String, [Int: Double]>
    ) -> [LineCoverageRow] {
        statistics.lineTotals.compactMap { item -> LineCoverageRow? in
            let total = item.byMask[mask] ?? 0
            guard total > 0 else { return nil }
            let riddenKm = ridden[item.name]?[mask] ?? 0
            guard riddenKm > 0 || includeUnridden else { return nil }
            let operatorName = statistics.lineOperators[item.name] ?? ""
            return LineCoverageRow(
                name: item.name, operatorName: operatorName,
                company: StatisticsFormat.companyLabel(operatorName),
                total: total, ridden: riddenKm)
        }
        // Group by operating company, then by line within the company, so a
        // near-100% aggregate can be audited in a stable, readable order
        // instead of "whatever we rode most". Lines with no known operator
        // sort last so they cannot split a company's block.
        .sorted { a, b in
            if a.operatorName != b.operatorName {
                if a.operatorName.isEmpty { return false }
                if b.operatorName.isEmpty { return true }
                if a.operatorName.localizedStandardCompare(b.operatorName) != .orderedSame {
                    return StatisticsFormat.linesPrecede(a.operatorName, b.operatorName)
                }
            }
            return StatisticsFormat.linesPrecede(a.name, b.name)
        }
    }

    // MARK: - 乘坐分佈 (the reference's "FLIGHTS PER Year / Month / Weekday")

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
                localization.statsText("ios.stats.rhythmTitle"),
                systemImage: "chart.bar.xaxis")
            if !isPoster {
                Picker(localization.statsText("ios.stats.scaleLabel"), selection: $rhythm) {
                    ForEach(RhythmScale.allCases) { scale in
                        Text(localization.statsText(scale.localizationKey)).tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(Text(localization.statsText("ios.stats.scaleLabel")))
            }
            if let best, best.count > 0 {
                PassportHighlight(
                    eyebrow: localization.statsText("ios.stats.mostJourneys"),
                    title: best.name,
                    detail: journeyCount(best.count))
            }
            StatisticsColumnChart(columns: columns) { journeyCount($0.count) }
                // The three axes share no bucket numbering — month 7 and
                // weekday 7 are different things — so the chart is REPLACED
                // rather than re-laid-out, and a crossfade is what §9.4 asks
                // for when one small thing appears where another was.
                .id(rhythm)
                .transition(.opacity)
            if passport.undated > 0 {
                Text(
                    localization.statsText(
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
                    spoken: journeyCount(column.count))
            }
        case .month:
            return passport.byMonth.map { column in
                StatisticsColumnChart.Column(
                    id: column.id,
                    label: column.id.formatted(),
                    name: monthName(column.id),
                    count: column.count,
                    spoken: journeyCount(column.count))
            }
        case .weekday:
            return passport.byWeekday.map { column in
                StatisticsColumnChart.Column(
                    id: column.id,
                    label: weekdayLabel(column.id, short: true),
                    name: weekdayLabel(column.id, short: false),
                    count: column.count,
                    spoken: journeyCount(column.count))
            }
        }
    }

    /// A calendar whose symbols are in the language the reader CHOSE, not the
    /// one the device is set to — the same rule `AppLocalization.locale`
    /// exists for, applied to month and weekday names.
    private var symbolCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = localization.locale
        return calendar
    }

    private func monthName(_ month: Int) -> String {
        let symbols = symbolCalendar.monthSymbols
        guard month >= 1, month <= symbols.count else { return month.formatted() }
        return symbols[month - 1]
    }

    /// `Calendar`'s weekday numbering — 1 is Sunday — which is why the columns
    /// carry it rather than an index of their own.
    private func weekdayLabel(_ weekday: Int, short: Bool) -> String {
        let symbols = short
            ? symbolCalendar.shortWeekdaySymbols : symbolCalendar.weekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return weekday.formatted() }
        return symbols[weekday - 1]
    }

    /// `stat.trains` — how many journeys, in the vocabulary the rest of the
    /// screen counts journeys in.
    private func journeyCount(_ count: Int) -> String {
        localization.statsText("stat.trains", params: ["n": .number(Double(count))])
    }

    // MARK: - 距離紀錄 (the reference's "Flight Distance")

    /// What the total distance means, in units nobody counts kilometres in.
    ///
    /// The total itself is not restated here — it is the passport page's own
    /// headline, three cards up. What this card adds is the three things the
    /// reference adds: the mean, the scale comparisons, and the two journeys
    /// at the ends of the range.
    private func distanceCard(_ passport: PassportStatistics) -> some View {
        let scales = scaleRows(passport.totalKm)
        let longest = passport.longestByDistance
        let shortest = passport.shortestByDistance
        return VStack(alignment: .leading, spacing: 16) {
            PassportCardHeader(
                localization.statsText("ios.stats.distanceTitle"),
                systemImage: "ruler")
            StatisticsMetricRow(
                label: localization.statsText("ios.stats.perJourney"),
                value: "\(StatisticsFormat.km(passport.averageKm)) km")
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
    /// says nothing while taking up the space of one that does — the same
    /// judgement `aroundTheWorld` already makes about the hero's caption. So a
    /// short record shows the Earth row alone, and a long one shows all three.
    private func scaleRows(_ km: Double) -> [ScaleRow] {
        guard km.isFinite, km > 0 else { return [] }
        return Self.scaleSpecs.compactMap { spec in
            let multiple = km / spec.km
            guard multiple >= 0.005 else { return nil }
            let label = localization.statsText(spec.i18n)
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

    // MARK: - 時間紀錄 (the reference's "Flight Time")

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
                localization.statsText("ios.stats.timeTitle"),
                systemImage: "clock")
            PassportMetricGrid(items: [
                .init(localization.statsText("ios.stats.days"), spanText(minutes / 1440)),
                .init(localization.statsText("ios.stats.weeks"), spanText(minutes / 10080)),
                .init(localization.statsText("ios.stats.months"), spanText(minutes / 43200)),
                .init(localization.statsText("ios.stats.years"), spanText(minutes / 525_600)),
            ])
            StatisticsMetricRow(
                label: localization.statsText("ios.stats.perJourney"),
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

    // MARK: - the ranked lists (Top Visited Airports / Airlines / Routes)

    /// 最常進出的車站 — where the reader has boarded and got off most.
    private func stationsCard(_ passport: PassportStatistics) -> some View {
        let rows = rankedRows(passport.stations, metric: .count) { placeName($0.name) }
        return rankedCard(
            title: localization.statsText("ios.stats.stationsTitle"),
            systemImage: "building.columns",
            total: passport.stations.count,
            unit: localization.statsText("ios.stats.unit.stations"),
            hint: localization.statsText("ios.stats.stationsHint"),
            rows: rows)
    }

    /// 最常乘坐的業者 — the reference's Top Airlines, and this app's one place
    /// where the record's own `company` is counted rather than derived from
    /// the network. Two operators can share a short label, so the tally is
    /// keyed on the raw name and only the DISPLAY is shortened.
    private func operatorsCard(_ passport: PassportStatistics) -> some View {
        let rows = rankedRows(passport.operators, metric: operatorMetric) {
            StatisticsFormat.companyLabel($0.name)
        }
        return rankedCard(
            title: localization.statsText("ios.stats.operatorsTitle"),
            systemImage: "building.2",
            total: passport.operators.count,
            unit: localization.statsText("ios.stats.unit.operators"),
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
            "\(placeName(tally.name)) ↔ \(placeName(tally.pair ?? ""))"
        }
        return rankedCard(
            title: localization.statsText("ios.stats.routesTitle"),
            systemImage: "arrow.left.arrow.right",
            total: passport.routes.count,
            unit: localization.statsText("ios.stats.unit.routes"),
            hint: localization.statsText("ios.stats.routesHint"),
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
                if let metric, !isPoster {
                    Picker(localization.statsText("ios.stats.rankBy"), selection: metric) {
                        ForEach(RankMetric.allCases) { option in
                            Text(localization.statsText(option.localizationKey)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(Text(localization.statsText("ios.stats.rankBy")))
                }
                StatisticsRankedList(
                    rows: rows,
                    visible: Self.rankedListLimit,
                    moreLabel: localization.statsText(
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
            let count = rideCount(tally.count)
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

    // MARK: - 國家與地區 (the reference's "Countries & Territories")

    /// Which of the five networks the passport has stamps from.
    ///
    /// Shown only when there is more than one — see the call site. The flag is
    /// decoration and is hidden from VoiceOver: the region names itself on the
    /// same row, and 「🇯🇵 日本」 read aloud is the country twice.
    private func regionsCard(_ passport: PassportStatistics) -> some View {
        let peak = Double(passport.regions.map(\.count).max() ?? 0)
        return VStack(alignment: .leading, spacing: 14) {
            PassportCardHeader(
                localization.statsText("ios.stats.regionsTitle"),
                systemImage: "globe.asia.australia")
            PassportHeadline(
                label: localization.statsText("ios.stats.regionsTitle"),
                value: passport.regions.count.formatted(),
                spoken: "\(passport.regions.count.formatted()) "
                    + localization.statsText("ios.stats.unit.regions"),
                unit: localization.statsText("ios.stats.unit.regions"),
                prominence: .field)
            VStack(spacing: 10) {
                ForEach(passport.regions) { tally in
                    StatisticsRankedRow(
                        label: regionName(tally.region),
                        emblem: flag(tally.region),
                        value: rideCount(tally.count),
                        fraction: peak > 0 ? Double(tally.count) / peak : 0,
                        spoken:
                            "\(rideCount(tally.count)) · \(StatisticsFormat.km(tally.km)) km")
                }
            }
        }
        .passportCard(.soft)
    }

    private func regionName(_ region: Region) -> String {
        localization.text(region.localizationKey, fallback: region.fallbackName)
    }

    /// The regional indicator pair for a region's ISO code — the stamp a
    /// passport would carry. A device whose own region suppresses one of these
    /// draws the two letters instead, which is still the right answer beside a
    /// row that names the place in words.
    private func flag(_ region: Region) -> String {
        switch region {
        case .jp: "🇯🇵"
        case .tw: "🇹🇼"
        case .hk: "🇭🇰"
        case .mo: "🇲🇴"
        case .kr: "🇰🇷"
        }
    }

    // MARK: - a superlative, named

    /// One end of a range — the reference's "Shortest flight" / "Longest
    /// flight", as a journey this app can name.
    private func superlative(
        _ key: String, _ journey: PassportStatistics.Journey, value: String
    ) -> some View {
        let endpoints = "\(placeName(journey.from)) → \(placeName(journey.to))"
        let caption = journeyCaption(journey)
        return StatisticsSuperlative(
            eyebrow: localization.statsText(key),
            title: endpoints,
            detail: caption,
            value: value,
            spoken: "\(endpoints) · \(value) · \(caption)")
    }

    /// The train, and the day it ran — the reference's "WS 255 · 20 Feb 2025".
    private func journeyCaption(_ journey: PassportStatistics.Journey) -> String {
        let day = journey.date.isEmpty ? nil : dayLabel(journey.date)
        return [journey.title, day].compactMap { $0 }.joined(separator: " · ")
    }

    /// A record's `YYYY-MM-DD` in the reader's own language, or unchanged when
    /// it is not a day this device can parse.
    private func dayLabel(_ date: String) -> String {
        guard let point = RecordDate.date(from: date) else { return date }
        return point.formatted(
            .dateTime.year().month(.abbreviated).day().locale(localization.locale))
    }

    // MARK: - states that are not numbers

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                localization.statsText("ios.stats.failedTitle"),
                systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(localization.statsText("ios.stats.failedBody"))
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
            Text(localization.statsText("stats.empty"))
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
        localization.statsText(
            "ios.stats.unconfirmedHeld", params: ["n": .number(Double(count))])
    }

    // MARK: - shared bits

    /// A label/value pair that turns into two stacked lines rather than
    /// squeezing either side at an accessibility text size (§10.1).
    @ViewBuilder
    private func adaptiveRow(label: some View, value: some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            label
            Spacer(minLength: 8)
            value
                .multilineTextAlignment(.trailing)
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
    /// is handed a list already filtered by ``RailPresentation/RideLedger``,
    /// and a card that said "8 journeys, 0 km" because two of them were never
    /// confirmed would be this screen disagreeing with itself.
    private func scoped(_ loaded: ItineraryStore.Loaded) -> Scope {
        var trains: [Train] = []
        var unconfirmed = 0
        trains.reserveCapacity(loaded.trains.count)
        for train in loaded.trains {
            if let region, Region.resolved(train) != region { continue }
            if RideLedger.hasBeenRidden(train) {
                trains.append(train)
            } else {
                unconfirmed += 1
            }
        }
        let ids = Set(trains.map(\.id))
        return Scope(
            loaded: ItineraryStore.Loaded(
                regions: region.map { [$0] } ?? Region.ordered,
                trains: trains,
                days: loaded.days.compactMap { day in
                    let kept = day.trains.filter { ids.contains($0.id) }
                    return kept.isEmpty
                        ? nil : ItineraryStore.Loaded.Day(date: day.date, trains: kept)
                },
                elapsed: loaded.elapsed),
            unconfirmed: unconfirmed)
    }

    private func stopCount(_ trains: [Train]) -> Int {
        trains.reduce(0) { $0 + $1.stops.count }
    }
}
