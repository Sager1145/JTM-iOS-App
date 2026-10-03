import RailCore
import RailPresentation
import SwiftUI

/// §5.3 — the recollection surface.
///
/// One question: **how much have I ridden, and which railways does that
/// cover?** Everything on it answers that, in the order §5.3 lists:
///
///   Scope → Coverage map → Statistics → Replay / Export
///
/// It is a container, not a screen of its own: every part below already exists
/// and is composed rather than reimplemented.
///
/// ## Where the journey log went
///
/// §5.3.4's 乘車記録 list is gone from this screen, at the reader's own
/// request. It was the whole log a second time — the same rows, opening the
/// same `RideDetailView`, under a different heading — and it sat at the bottom
/// of the one screen whose question is *how much does it all add up to*. The
/// journeys themselves have a destination of their own, one tab away, which
/// now carries the same date and region scopes this screen does; what is left
/// here is the answer rather than the working.
///
/// The header owns the day and region controls. The year bar below it owns
/// the overall time range through `MileageStatisticsStore.selectedYear`.
/// All cards, map coverage, replay and sharing use that same year scope.
struct PassportWorkspaceView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var itineraries: ItineraryStore
    @Bindable var statistics: MileageStatisticsStore
    @Bindable var riddenRoutes: RiddenRouteStore
    @Bindable var network: RailNetworkStore
    @Bindable var controller: RailMapController
    @Bindable var playback: PlaybackController
    /// `nil` is 全部 — see `StatisticsView.region`.
    @Binding var region: Region?
    /// `RailWorkspaceView.statisticsScope.trains`, computed once there and
    /// handed down rather than re-filtered here: the two used to run the same
    /// region + ridden + date scan over every journey on every body
    /// evaluation — once for the map's scope, once for this screen's replay
    /// button — and a sheet drag is one body evaluation per frame.
    var scopedTrains: [Train]
    /// The workspace's shared memoisation cache — see ``WorkspaceDerived`` —
    /// threaded through so ``StatisticsDashboardContent`` can cache its own
    /// region-scoped slice the same way rather than rebuilding a whole
    /// `ItineraryStore.Loaded` on every body evaluation.
    var derived: WorkspaceDerived
    /// Threaded straight through to ``StatisticsDashboardContent`` — see the
    /// two properties there for why the resolver and the record sheet are the
    /// workspace's to supply rather than the statistics screen's to reach for.
    var journeyPresentation: (Train) -> JourneyPresentation
    var openJourney: (Train) -> Void
    var openData: () -> Void
    var openSettings: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                StatisticsYearBar(
                    allTimeLabel: localization.statsText("ios.stats.allTime"),
                    years: availableYears,
                    selectedYear: statistics.selectedYear,
                    accessibilityPrefix: "statisticsYear",
                    select: statistics.selectYear)
                    .accessibilityIdentifier("statisticsYearBar")

                // §5.3.2's coverage map is the ROOT map, and there is no card
                // here that says so.
                //
                // There were two, and both were furniture. The region picker
                // moved to the panel header (§9.5.6's one row per
                // destination); the note that replaced the old 280 pt inline
                // map was left explaining a picture the reader can already see
                // through the glass, above the numbers they opened this screen
                // for. §2.1 keeps "Shared Map Coverage Mode" as a mode of the
                // shared basemap, not as a card — the map draws this region's
                // network with the scoped rides on top, and the statistics
                // below name the region in every percentage they state.

                // The statistics themselves, unchanged — the same cards the
                // dashboard rendered, composed here rather than copied.
                StatisticsDashboardContent(
                    itineraries: itineraries,
                    statistics: statistics,
                    region: $region,
                    derived: derived,
                    journeyPresentation: journeyPresentation,
                    openJourney: openJourney)

                PassportShareCard(
                    canReplay: !scopedTrains.isEmpty,
                    onReplay: { replay(scopedTrains) },
                    onExport: openData)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            // The shared menu viewport provides the tab bar's safe-area inset.
            .padding(.bottom, 8)
        }
        .onChange(of: availableJourneyGroups.map(\.id), initial: true) { _, groupIDs in
            guard let selectedID = statistics.selectedJourneyGroupID,
                  !groupIDs.contains(selectedID) else { return }
            statistics.selectJourneyGroup(nil)
        }
        // No navigation title and no toolbar: §9.5.6 put both in the bottom
        // chrome's own header, which is the same row on every destination.
        // A NavigationStack in here would have added a second one.
    }

    private var availableJourneyGroups: [JourneyGroup] {
        let trains = itineraries.store?.trains ?? itineraries.loaded?.trains ?? []
        var seen = Set<String>()
        return trains.compactMap(\.journeyGroup).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var availableYears: [Int] {
        let trains = itineraries.loaded?.trains ?? []
        var years = Set(trains.compactMap { train -> Int? in
            if let region, Region.resolved(train) != region { return nil }
            guard RideLedger.hasBeenRidden(train), statistics.includesJourneyGroup(train) else { return nil }
            return MileageStatisticsStore.year(of: train)
        })
        years.insert(Calendar(identifier: .gregorian).component(.year, from: Date()))
        if let year = statistics.selectedYear { years.insert(year) }
        return years.sorted(by: >)
    }

    // MARK: - what is in scope
    //
    // `scopedTrains` — one region, either one day or all of them, and only
    // what the records say was ridden — used to be computed here on every
    // body evaluation. It is now `RailWorkspaceView.statisticsScope.trains`,
    // handed down as a stored property: the same three filters (region,
    // ``RailPresentation/RideLedger``, date), so 回放 still can never play a
    // journey the numbers above it excluded, computed once per (trains
    // generation, region, date) instead of once per screen.

    private func replay(_ trains: [Train]) {
        guard !trains.isEmpty else { return }
        _ = playback.start(
            trains: trains, rides: riddenRoutes.rides, reducedMotion: reduceMotion,
            restoringSelection: itineraries.selectedTrainID)
    }
}

/// §5.3.5 Replay & Share — two entry points into flows that already exist: the
/// transport Journeys uses, and the Data Library's export.
private struct PassportShareCard: View {
    @Environment(AppLocalization.self) private var localization
    var canReplay: Bool
    var onReplay: () -> Void
    var onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                localization.text("grp.passportShare", fallback: "Replay and export"),
                systemImage: "square.and.arrow.up")
                .font(.headline)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { replayButton; exportButton }
                VStack(spacing: 10) { replayButton; exportButton }
            }

            // §2.3 / §2.4: the film is a recording, not a broadcast. Saying so
            // plainly is what keeps Flighty's "Live Share" from being implied
            // by a share button on a journey screen.
            Text(localization.journeyText(
                "ios.passport.shareNote",
                fallback: "Playback is exported as a video file. Nothing is shared live."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("passportShareNote")
        }
        .statisticsCard()
    }

    private var replayButton: some View {
        Button(action: onReplay) {
            Label(
                localization.countryText("btn.play", fallback: "Play"),
                systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .railMinimumTouchTarget()
        .disabled(!canReplay)
    }

    private var exportButton: some View {
        Button(action: onExport) {
            Label(
                localization.countryText("btn.exportJson", fallback: "Export JSON"),
                systemImage: "arrow.down.doc")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .railMinimumTouchTarget()
    }
}
