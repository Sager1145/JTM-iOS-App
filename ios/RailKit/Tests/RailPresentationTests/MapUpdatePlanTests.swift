import RailPresentation
import Testing

struct MapUpdatePlanTests {
    private func changes(
        linesChanged: Bool = false,
        stationsChanged: Bool = false,
        ridesChanged: Bool = false,
        selectionChanged: Bool = false,
        visibilityChanged: Bool = false,
        indexesChanged: Bool = false,
        displayChanged: Bool = false,
        routePaintOnly: Bool = false,
        dateChanged: Bool = false,
        namingChanged: Bool = false,
        showsNetwork: Bool = true,
        hasRides: Bool = true,
        hasContinuousLines: Bool = true
    ) -> MapDrawChanges {
        MapDrawChanges(
            linesChanged: linesChanged,
            stationsChanged: stationsChanged,
            ridesChanged: ridesChanged,
            selectionChanged: selectionChanged,
            visibilityChanged: visibilityChanged,
            indexesChanged: indexesChanged,
            displayChanged: displayChanged,
            routePaintOnly: routePaintOnly,
            dateChanged: dateChanged,
            namingChanged: namingChanged,
            showsNetwork: showsNetwork,
            hasRides: hasRides,
            hasContinuousLines: hasContinuousLines)
    }

    @Test("Lines changing on a visible network rebuilds")
    func linesChangedRebuilds() {
        #expect(changes(linesChanged: true).plan == .rebuild)
    }

    @Test("Stations changing on a visible network rebuilds")
    func stationsChangedRebuilds() {
        #expect(changes(stationsChanged: true).plan == .rebuild)
    }

    @Test("Rides changing rebuilds")
    func ridesChangedRebuilds() {
        #expect(changes(ridesChanged: true).plan == .rebuild)
    }

    @Test("Visibility changing rebuilds")
    func visibilityChangedRebuilds() {
        #expect(changes(visibilityChanged: true).plan == .rebuild)
    }

    @Test("Category indexes changing rebuilds")
    func indexesChangedRebuilds() {
        #expect(changes(indexesChanged: true).plan == .rebuild)
    }

    @Test("Selected date changing rebuilds")
    func dateChangedRebuilds() {
        #expect(changes(dateChanged: true).plan == .rebuild)
    }

    @Test("Naming changing rebuilds")
    func namingChangedRebuilds() {
        #expect(changes(namingChanged: true).plan == .rebuild)
    }

    @Test("Display changing beyond route paint rebuilds")
    func displayChangedBeyondPaintRebuilds() {
        #expect(changes(displayChanged: true, routePaintOnly: false).plan == .rebuild)
    }

    @Test("Selection alone is its own plan")
    func selectionAloneIsSelectionOnly() {
        #expect(changes(selectionChanged: true).plan == .selectionOnly)
    }

    @Test("Selection wins over a simultaneous route-paint-only display change")
    func selectionWinsOverRoutePaintOnly() {
        #expect(changes(
            selectionChanged: true,
            displayChanged: true,
            routePaintOnly: true).plan == .selectionOnly)
    }

    @Test("Route paint only display change alone is paint only")
    func routePaintOnlyAloneIsPaintOnly() {
        #expect(changes(displayChanged: true, routePaintOnly: true).plan == .paintOnly)
    }

    @Test("No flags set is no plan")
    func allFalseIsNone() {
        #expect(changes().plan == .none)
    }

    @Test("Lines changing with no visible or strokeable network is no plan")
    func linesChangedWithoutVisibleOrStrokeableNetworkIsNone() {
        #expect(changes(
            linesChanged: true,
            showsNetwork: false,
            hasRides: false).plan == .none)
    }

    @Test("Lines changing with a strokeable network rebuilds even when hidden")
    func linesChangedWithStrokeableNetworkRebuilds() {
        #expect(changes(
            linesChanged: true,
            showsNetwork: false,
            hasRides: true,
            hasContinuousLines: true).plan == .rebuild)
    }

    @Test("Selection together with rides changing rebuilds")
    func selectionWithRidesChangedRebuilds() {
        #expect(changes(ridesChanged: true, selectionChanged: true).plan == .rebuild)
    }

    @Test
    func selectionWithADrawingDisplayChangeRebuilds() {
        var changes = changes()
        changes.selectionChanged = true
        changes.displayChanged = true
        changes.routePaintOnly = false
        #expect(changes.plan == .rebuild)
    }

    @Test
    func hiddenNetworkLinesWithoutContinuousLinesDoNothing() {
        var changes = changes()
        changes.linesChanged = true
        changes.showsNetwork = false
        changes.hasRides = true
        changes.hasContinuousLines = false
        #expect(changes.plan == .none)
    }
}
