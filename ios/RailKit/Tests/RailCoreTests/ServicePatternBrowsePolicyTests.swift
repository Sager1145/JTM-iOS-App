import Testing
@testable import RailCore

struct ServicePatternBrowsePolicyTests {
    private func input(query: String = "", date: String? = "2024-10-01",
                       patterns: [TrainServicePatterns.Pattern]? = nil,
                       occurrences: [TrainTimetableDatabase.Trip] = [],
                       excerpts: [LineServiceCatalog.TimetableTrip] = [],
                       availability: ServicePatternBrowsePolicy.OccurrenceAvailability = .ready(.verified),
                       allHistory: Bool = false,
                       company: String? = nil, line: String? = nil) -> ServicePatternBrowsePolicy.SearchInput {
        .init(query: query, region: "jp", rideDate: date, companyFilter: company, lineFilter: line,
              showsAllHistory: allHistory, language: "en",
              sources: .init(availability: availability, occurrences: occurrences,
                             patterns: patterns ?? TrainServicePatterns.patterns, excerpts: excerpts,
                             patternCatalog: .loaded, excerptCatalog: .loaded), generation: 7)
    }

    private var pattern: TrainServicePatterns.Pattern {
        .init(id: "pattern-only", serviceId: "fixture", name: "Route pattern", company: "東日本旅客鉄道", label: "A → B",
              origin: "A", destination: "B", stopRefs: [], optionalStopRefs: [], via: [],
              confidence: nil, source: nil, lines: ["中央本線"])
    }

    @Test func exactDatedRowsCarryTheSelectedOccurrenceAndItsSource() throws {
        let fixture = try FixtureDatabase()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let sources = TimetableKnowledgeQuery.sources(
            country: "jp", serviceDate: "2026-09-29", serviceID: "shinano",
            database: .success(database), patterns: .success([]), excerpts: [])
        let trip = try #require(sources.occurrences.first { $0.id == "shinano-1" })
        let result = ServicePatternBrowsePolicy.makeSearchSnapshot(input(
            query: trip.trainNumber, date: trip.serviceDate, patterns: [], occurrences: [trip]))
        let row = try #require(result.groups.first?.rows.first)
        guard case .occurrence(let selected) = row else {
            Issue.record("An exact occurrence became a route pattern")
            return
        }
        #expect(selected == trip)
        #expect(selected.serviceDate == "2026-09-29")
        #expect(selected.timetableVersionID == trip.timetableVersionID)
        #expect(selected.direction == trip.direction)
        #expect(selected.stops == trip.stops)
        #expect(result.groups.first?.name == trip.service.canonicalName)
        #expect(result.generation == 7)
        #expect(result.filters.rideDate == trip.serviceDate)
        #expect(!result.primaryRowsArePatterns)
        #expect(ServicePatternBrowsePolicy.makeSearchSnapshot(input(
            patterns: [], occurrences: [trip], company: "西日本旅客鉄道")).groups.isEmpty)
        #expect(ServicePatternBrowsePolicy.makeSearchSnapshot(input(
            patterns: [], occurrences: [trip], line: "東海道本線")).groups.isEmpty)
    }

    @Test func physicalLineBoundaryDoesNotRequireAPassengerOnlyPattern() throws {
        let fixture = try FixtureDatabase(routeOnlyLineBoundary: true)
        defer { fixture.remove() }
        let queried = try TrainTimetableDatabase(url: fixture.url).trip(id: "shinano-1", on: "2026-09-29")
        let trip = try #require(queried)
        #expect(trip.canApplyToRouteEditor)
        #expect(trip.compatibilityPattern() == nil)
        let result = ServicePatternBrowsePolicy.makeSearchSnapshot(input(patterns: [], occurrences: [trip]))
        let row = try #require(result.groups.first?.rows.first)
        guard case .occurrence(let selected) = row else {
            Issue.record("Lost the occurrence at a physical line boundary")
            return
        }
        #expect(selected == trip)
        #expect(selected.lineSegments.count == 2)
        #expect(!selected.passengerStops.contains { $0.station.name == "日暮里" })
        #expect(result.incompleteTrips.isEmpty)
    }

    @Test func incompleteOccurrencesRemainTripsForReviewAndPublishedDrafts() throws {
        let fixture = try FixtureDatabase(stationValidUntil: "2026-09-29")
        defer { fixture.remove() }
        let queried = try TrainTimetableDatabase(url: fixture.url).trip(id: "shinano-1", on: "2026-09-29")
        let trip = try #require(queried)
        #expect(!trip.canApplyToRouteEditor)
        let result = ServicePatternBrowsePolicy.makeSearchSnapshot(input(patterns: [], occurrences: [trip]))
        #expect(result.groups.isEmpty)
        #expect(result.incompleteTrips == [trip])
        #expect(ServicePatternBrowsePolicy.makeSearchSnapshot(input(
            query: "does not exist", patterns: [], occurrences: [trip])).incompleteTrips.isEmpty)
        #expect(ServicePatternBrowsePolicy.makeSearchSnapshot(input(
            patterns: [], occurrences: [trip], company: "西日本旅客鉄道")).incompleteTrips.isEmpty)
    }

    @Test func undatedBrowseUsesTheProvidedPatternCatalog() throws {
        let result = ServicePatternBrowsePolicy.makeSearchSnapshot(input(
            query: "Route", date: nil, patterns: [pattern], availability: .notRequested))
        let row = try #require(result.groups.first?.rows.first)
        guard case .pattern(let selected) = row else {
            Issue.record("A route pattern became an occurrence")
            return
        }
        #expect(selected.id == pattern.id)
        #expect(result.primaryRowsArePatterns)
        #expect(result.companyLabels.contains("jp.jr-east"))
        #expect(result.lineNames == ["中央本線"])
        #expect(ServicePatternBrowsePolicy.makeSearchSnapshot(input(
            date: nil, patterns: [pattern], company: "西日本旅客鉄道")).groups.isEmpty)
    }

    @Test func verifiedCoverageAndHardFailuresDoNotSubstituteLegacyRows() {
        let verified = ServicePatternBrowsePolicy.makeSearchSnapshot(input(query: "はちおうじ"))
        #expect(verified.groups.isEmpty)
        #expect(verified.unknownPatterns.isEmpty)
        #expect(!verified.primaryRowsArePatterns)
        for availability: ServicePatternBrowsePolicy.OccurrenceAvailability in [.missing, .damaged, .queryFailed] {
            let failed = ServicePatternBrowsePolicy.makeSearchSnapshot(
                input(query: "はちおうじ", availability: availability))
            #expect(failed.groups.isEmpty)
            #expect(failed.unknownPatterns.isEmpty)
        }
    }

    @Test func partialCoverageKeepsProvidedPatternsSeparateFromOccurrences() {
        let result = ServicePatternBrowsePolicy.makeSearchSnapshot(input(
            patterns: [pattern], availability: .ready(.partial)))
        #expect(result.groups.isEmpty)
        #expect(result.unknownPatterns.map(\.id) == [pattern.id])
        #expect(result.incompleteTrips.isEmpty)
    }

    @Test func endedPatternOnlyAppearsInOutsideHistoryOnLaterDate() {
        let result = ServicePatternBrowsePolicy.makeSearchSnapshot(input(
            query: "はちおうじ", date: "2026-10-01", availability: .queryFailed, allHistory: true))
        #expect(!result.unknownPatterns.contains { $0.id == "hachioji-tokyo-hachioji" })
        #expect(result.outsidePatterns.contains { $0.id == "hachioji-tokyo-hachioji" })
    }

    @Test func classifiedExcerptsRemainDatedEvidenceWithoutBecomingSelectableOccurrences() throws {
        let fixture = try FixtureDatabase(nationalZeroInterval: true)
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let excerpt = LineServiceCatalog.TimetableTrip(
            id: "excerpt-only", trainNumber: "102C", trainType: "普通", operatorName: "JR西日本",
            lineIDs: ["line"], serviceDates: ["1945-01-01"], sourceURL: "https://example.invalid",
            coverage: .unknown, note: "", stops: [], previousTrainIDs: nil, nextTrainIDs: nil,
            sourceOperatorID: nil, sourceRailwayID: nil, sourceTrainTypeID: nil, sourceCalendarID: nil)
        let sources = TimetableKnowledgeQuery.sources(
            country: "jp", serviceDate: "1945-01-01", database: .success(database),
            patterns: .success([pattern]), excerpts: [excerpt])
        #expect(sources.isLegalZero)
        let searchInput = ServicePatternBrowsePolicy.SearchInput(
            query: "", region: "jp", rideDate: excerpt.serviceDates[0],
            companyFilter: nil, lineFilter: nil, showsAllHistory: false, language: "en",
            sources: sources, generation: 1)
        #expect(searchInput.sources.excerpts.map(\.id) == [excerpt.id])
        #expect(searchInput.sources.excerptCatalog == .loaded)
        let result = ServicePatternBrowsePolicy.makeSearchSnapshot(searchInput)
        #expect(result.groups.isEmpty)
        #expect(result.incompleteTrips.isEmpty)
    }
}
