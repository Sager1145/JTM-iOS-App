import RailCore
import Testing
@testable import RailMap

@MainActor
struct ShareComposerLayoutTests {
    @Test func miniCardsFillTheColumnBesideATicket() {
        let ticket = ShareCard(kind: .ticket, size: .init(shape: .medium))
        let distance = ShareCard(kind: .stat(.distance), size: .init(shape: .small))
        let coverage = ShareCard(kind: .stat(.coverage), size: .init(shape: .mini))
        let rides = ShareCard(kind: .stat(.rides), size: .init(shape: .mini))
        let result = ShareLayout.pack([ticket, distance, coverage, rides], columns: 6, rows: 2)

        #expect(result.overflow.isEmpty)
        #expect(result.placements[coverage.id] == GridRect(column: 5, row: 0, columns: 1, rows: 1))
        #expect(result.placements[rides.id] == GridRect(column: 5, row: 1, columns: 1, rows: 1))
        #expect(result.placements[ticket.id] == GridRect(column: 0, row: 0, columns: 3, rows: 2))
        #expect(result.placements[distance.id] == GridRect(column: 3, row: 0, columns: 2, rows: 2))
        #expect(result.placements.values.reduce(0) { $0 + $1.columns * $1.rows } == 12)
    }

    @Test func earlyMiniCardsDoNotFragmentSpaceNeededByATicket() {
        let coverage = ShareCard(kind: .stat(.coverage), size: .init(shape: .mini))
        let rides = ShareCard(kind: .stat(.rides), size: .init(shape: .mini))
        let ticket = ShareCard(kind: .ticket, size: .init(shape: .medium))
        let distance = ShareCard(kind: .stat(.distance), size: .init(shape: .small))
        let result = ShareLayout.pack([coverage, rides, ticket, distance], columns: 6, rows: 2)

        #expect(result.overflow.isEmpty)
        #expect(result.placements[ticket.id] == GridRect(column: 0, row: 0, columns: 3, rows: 2))
        #expect(result.placements[distance.id] == GridRect(column: 3, row: 0, columns: 2, rows: 2))
        #expect(result.placements[coverage.id] == GridRect(column: 5, row: 0, columns: 1, rows: 1))
        #expect(result.placements[rides.id] == GridRect(column: 5, row: 1, columns: 1, rows: 1))
    }

    @Test func stripAndMiniFillTheRowBelowATicket() {
        let ticket = ShareCard(kind: .ticket, size: .init(shape: .medium))
        let map = ShareCard(kind: .map(.region(.tw)), size: .init(shape: .large))
        let distance = ShareCard(kind: .stat(.distance), size: .init(shape: .strip))
        let coverage = ShareCard(kind: .stat(.coverage), size: .init(shape: .mini))
        let result = ShareLayout.pack([ticket, map, distance, coverage], columns: 6, rows: 3)

        #expect(result.overflow.isEmpty)
        #expect(result.placements[distance.id] == GridRect(column: 0, row: 2, columns: 2, rows: 1))
        #expect(result.placements[coverage.id] == GridRect(column: 2, row: 2, columns: 1, rows: 1))
        #expect(result.placements[ticket.id] == GridRect(column: 0, row: 0, columns: 3, rows: 2))
        #expect(result.placements[map.id] == GridRect(column: 3, row: 0, columns: 3, rows: 3))
        #expect(result.placements.values.reduce(0) { $0 + $1.columns * $1.rows } == 18)
    }

    @Test func compactShapesHaveRoomForTheirRequiredContext() {
        #expect(ShareCard(kind: .stat(.distance), size: .init(shape: .mini)).size.shape == .strip)
        #expect(ShareCard(kind: .stat(.coverage), size: .init(shape: .strip)).size.shape == .strip)
        #expect(ShareCard(kind: .map(.region(.tw)), size: .init(shape: .mini)).size.shape == .small)
        #expect(ShareCard(kind: .stat(.lineDetail), size: .init(shape: .strip)).size.shape == .small)
        #expect(ShareCard(kind: .ticket, size: .init(shape: .mini)).size.shape == .medium)
    }

    @Test func enlargedCompactCardsKeepTheirCompactPresentation() {
        #expect(CardShape.matching(CardSize(shape: .mini, scale: 3).span, preferred: .mini) == .mini)
        #expect(CardShape.matching(CardSize(shape: .strip, scale: 2).span, preferred: .strip) == .strip)
    }
}

@MainActor
struct ShareComposerScopeTests {
    @Test func emptyLoadedScopeRendersAnExplicitNoDataWidget() throws {
        let store = MileageStatisticsStore()
        let localization = AppLocalization()
        #expect(store.widgetData(.coverage, trains: [], scopeName: "Honshu", localization: localization) == nil)
        store.load(countries: ["jp"], trains: [], rides: [])
        let data = try #require(store.widgetData(
            .coverage, trains: [], scopeName: "Honshu", localization: localization))
        #expect(data.isEmpty)
        #expect(data.scopeLabel == "Honshu")
        #expect(data.emptyMessage == localization.text("ios.stats.shareNoData"))
    }

    private func model() -> ShareComposerModel {
        ShareComposerModel(region: .tw, area: nil, colorScheme: .light,
                           adopting: MileageStatisticsStore())
    }

    @Test func multipleTicketsKeepDistinctIdentitiesAndDateSelections() {
        let model = model()
        model.statistics.selectYear(2025)
        model.add(.ticket)
        model.add(.ticket)
        let tickets = model.cards.filter { $0.kind == .ticket }
        #expect(tickets.count == 3)
        #expect(Set(tickets.map(\.id)).count == 3)
        let first = tickets[0], second = tickets[1]
        model.customizeDates(for: first.id)
        model.customizeDates(for: second.id)
        let firstStore = model.statistics(for: first)
        let secondStore = model.statistics(for: second)
        #expect(firstStore.selectedYear == nil)
        #expect(secondStore.selectedYear == nil)
        #expect(model.statistics.selectedYear == 2025)
        firstStore.tapDate("2026-08-02", availableDates: ["2026-08-02", "2026-08-12"])
        secondStore.tapDate("2026-08-12", availableDates: ["2026-08-02", "2026-08-12"])
        model.statistics.tapDate("2025-01-01", availableDates: ["2025-01-01"])
        model.prepareCardStatistics()
        #expect(firstStore.dateSelection.start == "2026-08-02")
        #expect(secondStore.dateSelection.start == "2026-08-12")
        #expect(model.statistics.dateSelection.start == "2025-01-01")
    }

    @Test func cardRegionOverridesCanvasAndInheritedDatesStillFollowPage() {
        let model = model()
        model.add(.stat(.coverage))
        let id = model.selectedCardID!
        model.setScope(.japan(.honshu), for: id)
        let card = model.cards.first { $0.id == id }!
        #expect(model.effectiveScope.regions == [.tw])
        #expect(model.scope(for: card).regions == [.jp])
        #expect(model.scope(for: card).japanLeaves == StatisticsArea.honshu.leaves)
        model.statistics.tapDate("2026-08-02", availableDates: ["2026-08-02"])
        model.prepareCardStatistics()
        #expect(model.statistics(for: card).dateSelection.start == "2026-08-02")
        model.setScope(nil, for: id)
        let inherited = model.cards.first { $0.id == id }!
        #expect(model.scope(for: inherited) == model.effectiveScope)
        #expect(model.statistics(for: inherited) === model.statistics)
    }

    @Test func identicalInFlightInputsPublishTheLatestCallerKey() async throws {
        let store = MileageStatisticsStore()
        defer { store.cancelAll() }
        let train = Train(id: "share-key-regression", date: "2026-08-02", number: "100",
                          origin: "台北", destination: "板橋",
                          stops: [Stop(name: "台北", departure: "09:00"),
                                  Stop(name: "板橋", arrival: "09:08")], region: "tw")
        store.load(countries: ["tw"], trains: [train], rides: [], inputsKey: "first")
        store.load(countries: ["tw"], trains: [train], rides: [], inputsKey: "second")
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while store.publishedInputsKey == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.publishedInputsKey == "second")
        #expect(store.view != nil)
        if case .loaded = store.state {} else { Issue.record("Statistics did not finish loading") }
        let localization = AppLocalization()
        let ticket = try #require(store.recordTicketContent(trains: [train], localization: localization))
        #expect(Array(ticket.fields.map(\.value).prefix(2)) == ["1", "2"])
        #expect(ticket.displays.count == 2)
        #expect(ticket.span == localization.text("ios.ticket.spanDay", params: [
            "date": .string(StatisticsFormat.spelledDate("2026-08-02", localization: localization))]))
        let coverage = try #require(store.widgetData(
            .coverage, trains: [train], scopeName: "Taiwan", localization: localization))
        #expect(coverage.scopeLabel == "Taiwan")
        #expect(coverage.rows.first?.fraction == 0)
        #expect(!coverage.title.isEmpty)
    }

    @Test func scopedLoadAppliesRegionYearAndRiddenMembershipBeforeLoadingNetwork() {
        let store = MileageStatisticsStore()
        defer { store.cancelAll() }
        store.selectYear(2025)
        let template = Train(id: "outside-year", date: "2026-08-02", number: "100",
                             origin: "台北", destination: "板橋",
                             stops: [Stop(name: "台北"), Stop(name: "板橋")], region: "tw")
        var otherRegion = template
        otherRegion.id = "outside-region"
        otherRegion.date = "2025-08-02"
        otherRegion.region = "jp"
        var unconfirmed = RideLedger.setRidden(template, false)
        unconfirmed.id = "not-ridden"
        unconfirmed.date = "2025-08-02"
        store.load(scope: StatisticsScope(region: .tw, area: nil),
                   trains: [template, otherRegion, unconfirmed], rides: [])
        if case .loaded = store.state {} else { Issue.record("An empty scoped load started network work") }
        #expect(store.progress == nil)
        #expect(store.view == nil)
        #expect(store.passport == nil)
    }

    @Test func scopedLoadAppliesDateAndGroupSelectionInsideTheStore() {
        let store = MileageStatisticsStore()
        defer { store.cancelAll() }
        store.tapDate("2026-08-12", availableDates: ["2026-08-02", "2026-08-12"])
        let train = Train(id: "outside-selected-date", date: "2026-08-02", number: "100",
                          origin: "台北", destination: "板橋",
                          stops: [Stop(name: "台北"), Stop(name: "板橋")], region: "tw")
        store.load(scope: StatisticsScope(region: .tw, area: nil), trains: [train], rides: [])
        if case .loaded = store.state {} else { Issue.record("An excluded date started network work") }
        #expect(store.progress == nil)
        #expect(store.view == nil)
        store.selectJourneyGroup("another-group")
        store.load(scope: StatisticsScope(region: .tw, area: nil), trains: [train], rides: [])
        if case .loaded = store.state {} else { Issue.record("An excluded journey group started network work") }
        #expect(store.view == nil)
        var grouped = train
        grouped.journeyGroup = JourneyGroup(id: "another-group", name: "Summer")
        #expect(StatisticsFormat.ticketScope(
            trains: [grouped], groupID: store.selectedJourneyGroupID,
            scopeName: "Taiwan", region: .tw, localization: AppLocalization()) == "Summer")
    }

    @Test func independentlyScopedTicketCanExportWithoutInheritedOverlap() {
        let model = model()
        for card in model.cards {
            if case .map = card.kind { model.remove(card.id) }
        }
        model.add(.map(.japan(.honshu)))
        #expect(model.effectiveScope.isEmpty)
        #expect(ShareResourceRevision.failureMessage(for: model.effectiveScope.countries) == nil)
        #expect(ShareResourceRevision.token(for: model.effectiveScope.countries).isEmpty)
        let ticket = model.cards.first { $0.kind == .ticket }!
        model.setScope(.region(.tw), for: ticket.id)
        #expect(model.hasScopedContent)
    }

    @Test func legacyJapanSubregionsBecomeWholeIslands() {
        let map = ShareCard(kind: .map(.japan(.kanto)), size: .init(shape: .small))
        #expect(map.kind == .map(.japan(.honshu)))
        let model = ShareComposerModel(region: .jp, area: .tohoku, colorScheme: .light,
                                       adopting: MileageStatisticsStore())
        #expect(model.baseArea == .honshu)
        model.add(.stat(.coverage))
        let id = model.selectedCardID!
        model.setScope(.japan(.kinki), for: id)
        #expect(model.cards.first { $0.id == id }?.scopeOverride == .japan(.honshu))
        #expect(StatisticsArea.islands.count == 5)
    }
}
