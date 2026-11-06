import Foundation
import RailCore
import Testing

@testable import RailMap

/// Regression tests for the 2026-11-05 integration review of the day's merges.
@MainActor
struct IntegrationReviewFixesTests {

    private static func ride(_ id: String, number: String = "1") -> Train {
        Train(
            id: id, date: "2026-07-03", number: number, origin: "東京", destination: "品川",
            stops: [
                Stop(name: "東京", departure: "06:00", stopType: "origin", rideSegment: true),
                Stop(name: "品川", arrival: "07:00", stopType: "destination", rideSegment: true),
            ],
            region: "jp")
    }

    // MARK: 1. example rides stored under their legacy ids

    @Test("the bundled legacy map knows the old sample ids")
    func bundledLegacyMap() {
        let jp = SampleLegacyRideIDs.map(for: "train-store")
        #expect(jp.count == 201)
        #expect(jp["20260703_01_haruka"] == "journey_A9554752F257CDA52831A6C0EED248AF")
        #expect(SampleLegacyRideIDs.map(for: "train-store-hk").count == 1)
        #expect(SampleLegacyRideIDs.map(for: "unknown-sample").isEmpty)
    }

    @Test("loading a sample again replaces its legacy copies in place and keeps the reader's rides")
    func legacySampleCopiesAreReplaced() {
        let legacy = ["old_a": "journey_A", "old_b": "journey_B", "old_c": "journey_C"]
        let existing = TrainStore(trains: [
            Self.ride("mine_1", number: "mine"),
            Self.ride("old_a", number: "edited A"),
            Self.ride("journey_B", number: "B current"),
            Self.ride("old_b", number: "B legacy duplicate"),
            Self.ride("old_c", number: "C not in this sample"),
            Self.ride("mine_2", number: "mine too"),
        ])
        let incoming = TrainStore(trains: [
            Self.ride("journey_A", number: "A"),
            Self.ride("journey_B", number: "B"),
        ])
        let (merged, removed) = MergedStore.mergingReportingLegacy(
            incoming, into: existing, legacyIDs: legacy)
        #expect(merged.trains.map(\.id) == ["mine_1", "journey_A", "journey_B", "old_c", "mine_2"])
        #expect(merged.trains.map(\.number) == ["mine", "A", "B", "C not in this sample", "mine too"])
        #expect(Set(removed.map(\.id)) == ["old_a", "old_b"])
        // Without the map nothing but the incoming ids is touched.
        let plain = MergedStore.merging(incoming, into: existing)
        #expect(plain.trains.count == existing.trains.count + 1)
    }

    @Test("a reader ride that happens to carry a legacy id stays when the sample lacks its new id")
    func legacyIDWithoutIncomingCounterpartIsKept() {
        let existing = TrainStore(trains: [Self.ride("old_a")])
        let incoming = TrainStore(trains: [Self.ride("journey_Z")])
        let (merged, removed) = MergedStore.mergingReportingLegacy(
            incoming, into: existing, legacyIDs: ["old_a": "journey_A"])
        #expect(merged.trains.map(\.id) == ["old_a", "journey_Z"])
        #expect(removed.isEmpty)
    }

    // MARK: 2. share card distance skips unproven sections

    @Test("drawn km leaves out guard-rejected sections, as Stats does")
    func drawnKmSkipsUnproven() {
        let a = Coordinate(lon: 139.0, lat: 35.0)
        let b = Coordinate(lon: 139.0, lat: 35.1)
        let c = Coordinate(lon: 139.0, lat: 35.3)
        let train = Self.ride("r")
        var ride = RiddenRouteStore.DrawnRide(
            id: "r", trainType: nil, country: "jp", colorHex: "#000000", visible: true,
            segments: [
                .init(segmentIndex: 0, from: "A", to: "B", coordinates: [a, b], country: "jp"),
                .init(segmentIndex: 1, from: "B", to: "C", coordinates: [b, c], country: "jp"),
            ],
            route: .resolved, stops: train.stops, daySpan: Dates.daySpan(train), geometryDigest: 0)
        let both = ShareComposer.drawnKm([ride])["r"] ?? 0
        ride.physicalGaps = [.init(segmentIndex: 1, isBoundary: false, isUnproven: true)]
        let provenOnly = ShareComposer.drawnKm([ride])["r"] ?? 0
        #expect(both > 30)
        #expect(abs(provenOnly - 11.1) < 0.2)
    }

    // MARK: 3. one ride duration for passport, share card and dashboard

    @Test("an overnight ride has the same minutes in the passport, the share card and the dashboard")
    func overnightMinutesAgree() throws {
        var train = Self.ride("night")
        train.stops[0].departure = "23:30"
        train.stops[1].arrival = "00:10"
        let expected = try #require(Statistics.trainRideMinutes(train, clock: train.journeyClock))
        #expect(expected == 40)
        let passport = try #require(PassportStatistics.build(
            trains: [train], entries: [Statistics.TrainEntry(km: 10)]))
        #expect(passport.journeyMinutes[train.id] == expected)
        // The share card falls back to the same rule without a passport.
        let card = ShareCardBuilder(localization: AppLocalization(), passport: nil).journey(train, stops: .key)
        let withPassport = ShareCardBuilder(localization: AppLocalization(), passport: passport)
            .journey(train, stops: .key)
        #expect(card.facts.first { $0.id == "time" }?.value == withPassport.facts.first { $0.id == "time" }?.value)
        #expect(Statistics.sumRideMinutes([train], clock: { $0.journeyClock }) == expected)
        #expect(Statistics.sumRideMinutes([train]) == expected)
    }

    // MARK: 4. editor: one message per failed section

    private static func section(
        _ outcome: TripRoutePlanner.Outcome, probe: JourneyEditorView.PlannedSection.HistoricalProbe?
    ) -> JourneyEditorView.PlannedSection {
        JourneyEditorView.PlannedSection(
            key: "k", fromName: "A", toName: "B", outcome: outcome, geometry: [:],
            proven: [], proofFailure: nil, removedByDate: false, historicalProbe: probe)
    }

    @Test("a section with a historical notice hides the red no-route error")
    func historicalNoticeHidesRouteError() {
        // Closed line: the notice says the trip works on its date.
        #expect(JourneyEditorView.routeErrorCoveredByNotice(
            [Self.section(.noRoute, probe: .historicalOnly)]) { _ in nil })
        #expect(JourneyEditorView.routeErrorCoveredByNotice(
            [Self.section(.disconnected([]), probe: .historicalOnly)]) { _ in nil })
        // No line on the date either: the orange notice is the one no-route message.
        #expect(JourneyEditorView.routeErrorCoveredByNotice(
            [Self.section(.noRoute, probe: PlannedSection.HistoricalProbe.none)]) { _ in nil })
        // Not probed yet (or no historical data): the red error is the only message.
        #expect(!JourneyEditorView.routeErrorCoveredByNotice(
            [Self.section(.noRoute, probe: nil)]) { _ in nil })
        #expect(!JourneyEditorView.routeErrorCoveredByNotice(
            [Self.section(.sameStation, probe: .historicalOnly)]) { _ in nil })
    }

    private typealias PlannedSection = JourneyEditorView.PlannedSection

    // MARK: 5. memory pressure releases the probe graph

    #if DEBUG
    @Test("memory pressure clears the historical-probe graph")
    func memoryPressureClearsProbeGraph() async {
        RiddenRouteStore.seedProbeGraphCacheForTesting()
        #expect(RiddenRouteStore.probeGraphIsCached)
        await RiddenRouteStore.releaseCachesForMemoryPressure()
        #expect(!RiddenRouteStore.probeGraphIsCached)
    }
    #endif
}
