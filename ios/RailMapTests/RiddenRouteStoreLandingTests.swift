import Foundation
@_spi(Testing) import RailCore
import Testing

@testable import RailMap

/// A single-journey resolve that lands while a load is running must survive
/// the load's later publishes: ride, status entry and completed input.
@MainActor
struct RiddenRouteStoreLandingTests {
    /// A region with no data: every solve ends as a deterministic non-ride outcome.
    private func train(_ id: String) -> Train {
        Train(
            id: id, number: id, company: "JR東日本",
            origin: "東京", destination: "品川",
            routeSections: [
                RouteSection(
                    from: "東京", to: "品川",
                    fromN02StationCode: "003700", toN02StationCode: "116021"),
            ],
            stops: [
                Stop(
                    name: "東京", n02StationCode: "003700", departure: "06:00",
                    stopType: "origin", rideSegment: true),
                Stop(name: "品川", arrival: "07:00", stopType: "destination", rideSegment: true),
            ],
            region: "jp")
    }

    private func settle(_ store: RiddenRouteStore, until done: () -> Bool) async {
        for _ in 0..<600 where !done() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func landedResolveSurvivesLaterLoadPublishes() async {
        let store = RiddenRouteStore()
        let a = train("a"), b = train("b")
        store.load(trains: [a, b])
        store.resolve(a)
        // Item 3: while the solve is in flight no partial publish may clear it.
        var sawLanding = false
        await settle(store) {
            if store.routeEntries["a"] == nil {
                #expect(store.resolvingIDs.contains("a"))
            } else {
                sawLanding = true
            }
            return sawLanding
        }
        #expect(sawLanding)
        let landedEntry = store.routeEntries["a"]
        #expect(!store.resolvingIDs.contains("a"))
        await settle(store) {
            if case .loaded = store.state { return true }
            if case .failed = store.state { return true }
            return false
        }
        // Items 1 and 2: the final (or failure) publish keeps the landing.
        #expect(store.routeEntries["a"] == landedEntry)
        #expect(store.routeEntries["a"] != nil)
        #expect(!store.resolvingIDs.contains("a"))
        store.clear()
    }
}
