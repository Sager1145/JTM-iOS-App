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
    /// The selected Japanese area, when Passport is narrower than Japan.
    var area: StatisticsArea?
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
    var openSettings: () -> Void

    var body: some View {
        let membership = areaMembership
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WorkspaceMenuMetrics.contentSpacing) {
                StatisticsYearBar(
                    allTimeLabel: localization.text("ios.stats.allTime"),
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
                    memberIDs: membership?.ids,
                    memberKey: membership?.key,
                    scopeName: area.map {
                        localization.text($0.localizationKey, fallback: $0.fallbackName)
                    },
                    derived: derived,
                    journeyPresentation: journeyPresentation,
                    openJourney: openJourney)

                // Pass 2: the "Replay and export" card is gone. Playback has
                // one home (the Journeys header, scoped by its filter) and
                // export has one (Data Library). See docs/ui-reorganization.md.
            }
            .padding(.horizontal, WorkspaceMenuMetrics.horizontalInset)
            .padding(.top, WorkspaceMenuMetrics.contentTopInset)
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
        itineraries.orderedJourneyGroups
    }

    private var availableYears: [Int] {
        let trains = itineraries.loaded?.trains ?? []
        return derived.availableYears(
            trains: trains, regionCode: region?.code,
            groupID: statistics.selectedJourneyGroupID, memberIDs: areaMembership?.ids,
            currentYear: Calendar(identifier: .gregorian).component(.year, from: Date()),
            selectedYear: statistics.selectedYear)
    }

    /// The same geometry-aware area membership used by the map and loader.
    private var areaMembership: (ids: Set<String>, key: Int)? {
        guard area != nil else { return nil }
        let trains = itineraries.loaded?.trains ?? []
        return derived.memberIDs(
            scope: StatisticsScope(region: region, area: area),
            trains: trains, rides: riddenRoutes.rides)
    }

    // MARK: - what is in scope
    //
    // `scopedTrains` — one region, either one day or all of them, and only
    // what the records say was ridden — used to be computed here on every
    // body evaluation. It is now `RailWorkspaceView.statisticsScope.trains`,
    // handed down as a stored property: the same three filters (region,
    // ``RailCore/RideLedger``, date), so 回放 still can never play a
    // journey the numbers above it excluded, computed once per (trains
    // generation, region, date) instead of once per screen.
}
