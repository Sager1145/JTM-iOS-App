import Foundation
import SQLite3
import Testing
@testable import RailCore

/// Census for filling pass stations between the calls of a bundled service.
///
/// A timetable trip or stop pattern supplies the calls; the section planner
/// (the editor's one route mechanism) supplies the track between consecutive
/// calls, and `LocalJourneyAutofill.proposal(train:choice:span:)` writes the
/// stations passed. This suite asks, for every current stop pattern (no
/// `validUntil`) and every bundled timed trip:
///  - do the planner's endpoint codes equal the call codes of each section,
///  - does every section have exactly one candidate, several, or none,
///  - and when all sections are single, does the joined route fill the span
///    without dropping a call.
///
/// Planning is cached per station pair. The default run plans a fixed sample
/// (every 8th pattern, every 16th distinct call list) to stay near a minute in a
/// debug build; the full run (`JTM_FULL_CENSUS=1`) takes about 290 s. The summary
/// lines carry the measured time. Patterns are
/// planned forward only and on 2026-11-11; timed trips on 2026-09-30 (the last
/// bundled service date) whatever their own date, because the census asks
/// about the call lists and the current network, not history.
@Suite(.serialized)
struct PatternPassFillCensusTests {
    enum Verdict: String, CaseIterable {
        /// Every section has one candidate, they join, and the span fill keeps every call.
        case fills
        /// No section lacks a route, but at least one offers several candidates.
        case needsChoice
        /// At least one section has no corridor.
        case noRoute
        /// Every section has one candidate but the sections do not join (a line change the
        /// planner refuses at a call, or a station visited twice).
        case joinRefused
        /// The sections join but the span fill refused (a call the joined route does not pass).
        case spanRefused
        /// A call has no station code, so nothing can be planned.
        case callWithoutCode
    }

    struct Tally {
        var verdicts: [Verdict: Int] = [:]
        var sections = 0
        var sectionsSingle = 0
        var sectionsSeveral = 0
        var sectionsNone = 0
        /// Candidate corridors whose first or last code differs from the call code.
        var endpointCodeMismatches = 0
        var filledPassStops = 0
        var examples: [Verdict: [String]] = [:]

        func count(_ verdict: Verdict) -> Int { verdicts[verdict, default: 0] }
        var total: Int { verdicts.values.reduce(0, +) }

        mutating func add(_ verdict: Verdict, weight: Int, label: String) {
            verdicts[verdict, default: 0] += weight
            if verdict != .fills, examples[verdict, default: []].count < 6 {
                examples[verdict, default: []].append(label)
            }
        }

        func summary(_ title: String, seconds: Double) -> String {
            let parts = Verdict.allCases.map { "\($0.rawValue)=\(count($0))" }.joined(separator: " ")
            return "CENSUS \(title): services=\(total) \(parts) | sections=\(sections) single=\(sectionsSingle) "
                + "several=\(sectionsSeveral) none=\(sectionsNone) endpointCodeMismatches=\(endpointCodeMismatches) "
                + "passStopsFilled=\(filledPassStops) | \(String(format: "%.1f", seconds))s"
        }
    }

    /// Plans sections the way the editor does, with an outcome cache per pair.
    final class Planner {
        let package: CompactPackage
        let catalog: JapanThroughServices.Catalog
        let junctions: TripConnectivity.Junctions
        let history: RailHistoryOverlay
        var contexts: [String: RailwayRouteChoices.AdmissionContext] = [:]
        var cache: [String: TripRoutePlanner.Outcome] = [:]

        init() throws {
            package = try PortFixtures.package(country: "jp")
            catalog = try JapanThroughServices.loadBundled()
            let root = try PortFixtures.repositoryRoot()
            history = try RailHistoryOverlay.load(from: root.appending(path: "app/data/rail-history.json"))
            junctions = try TripConnectivity.Junctions(
                registryData: Data(contentsOf: root.appending(path: "app/data/physical-rail-junctions.json")),
                region: "jp")
        }

        func outcome(from: String, to: String, trainType: String, day: String) throws -> TripRoutePlanner.Outcome {
            let key = [from, to, trainType, day].joined(separator: "|")
            if let cached = cache[key] { return cached }
            let context: RailwayRouteChoices.AdmissionContext
            if let known = contexts[day] { context = known } else {
                context = try RailwayRouteChoices.AdmissionContext(history: history, civilDay: day)
                contexts[day] = context
            }
            var request = TripRoutePlanner.Request(originCode: from, destinationCode: to)
            request.trainType = trainType
            let result = TripRoutePlanner.plan(
                package: package, request: request, rideDate: day, patterns: catalog.patterns,
                connectors: catalog.connectors, junctions: junctions, admissionContext: context)
            cache[key] = result
            return result
        }

        /// One service: calls in order, planned like the editor's sections.
        func classify(
            train: Train, day: String, tally: inout Tally, weight: Int, label: String
        ) throws -> Verdict {
            let calls = train.stops
            guard calls.allSatisfy({ ($0.n02StationCode ?? "").isEmpty == false }) else {
                tally.add(.callWithoutCode, weight: weight, label: label)
                return .callWithoutCode
            }
            let codes = calls.compactMap(\.n02StationCode)
            var chosen: [TripRoutePlanner.Corridor] = []
            var anyNone = false, anySeveral = false
            for index in 0..<(codes.count - 1) {
                let outcome = try outcome(from: codes[index], to: codes[index + 1],
                                          trainType: train.trainType ?? "", day: day)
                tally.sections += weight
                guard case .corridors(let found) = outcome, !found.isEmpty else {
                    tally.sectionsNone += weight
                    anyNone = true
                    continue
                }
                let candidates = TripRoutePlanner.plausible(found, waypoints: codes)
                for corridor in candidates where corridor.choice.stations.first?.code != codes[index]
                    || corridor.choice.stations.last?.code != codes[index + 1] {
                    tally.endpointCodeMismatches += weight
                }
                if candidates.count == 1 {
                    tally.sectionsSingle += weight
                    chosen.append(candidates[0])
                } else {
                    tally.sectionsSeveral += weight
                    anySeveral = true
                }
            }
            let verdict: Verdict
            if anyNone { verdict = .noRoute }
            else if anySeveral { verdict = .needsChoice }
            else {
                switch fill(train: train, chosen: chosen, day: day) {
                case .success(let filled):
                    tally.filledPassStops += filled * weight
                    verdict = .fills
                case .failure(.join): verdict = .joinRefused
                case .failure(.span): verdict = .spanRefused
                }
            }
            tally.add(verdict, weight: weight, label: label)
            return verdict
        }

        enum FillFailure: Error { case join, span }

        /// Joined route, then one span fill over every call. Returns the number
        /// of pass stations written, or why it refused.
        func fill(train: Train, chosen: [TripRoutePlanner.Corridor], day: String) -> Result<Int, FillFailure> {
            guard case .corridors(let routes) = TripRoutePlanner.joining(
                chosen, allowUnverifiedConnections: false, rideDate: day,
                patterns: catalog.patterns, connectors: catalog.connectors,
                junctions: junctions, lineName: { _ in nil }),
                let route = routes.first else { return .failure(.join) }
            guard let proposal = LocalJourneyAutofill.proposal(
                    train: train, choice: route.choice, span: 0...(train.stops.count - 1))
            else { return .failure(.span) }
            let calls = train.stops
            let result = proposal.train.stops
            // Every call survives in order with its times, type and ridden flag.
            var cursor = 0
            for call in calls {
                guard let index = result.indices.dropFirst(cursor).first(where: {
                    result[$0].n02StationCode == call.n02StationCode && result[$0].stopType == call.stopType
                        && result[$0].arrival == call.arrival && result[$0].departure == call.departure
                        && result[$0].rideSegment == call.rideSegment
                }) else { return .failure(.span) }
                cursor = index + 1
            }
            let passes = result.filter { $0.stopType == "pass_through" }
            guard result.count == calls.count + passes.count,
                  passes.allSatisfy({ $0.arrival == nil && $0.departure == nil })
            else { return .failure(.span) }
            return .success(passes.count)
        }
    }

    /// The default run plans every `stride`-th entry in a fixed order (about a
    /// minute in a debug build instead of about 290 s; measured full run: patterns 224 services
    /// fills 92, needsChoice 118, noRoute 6, joinRefused/spanRefused 8; trips 888 services
    /// fills 241, needsChoice 577, noRoute 34, refused 36). `JTM_FULL_CENSUS=1` plans all.
    static var fullRun: Bool { ProcessInfo.processInfo.environment["JTM_FULL_CENSUS"] == "1" }
    static var patternStride: Int { fullRun ? 1 : 8 }
    static var tripStride: Int { fullRun ? 1 : 16 }
    static func sample<T>(_ items: [T], stride: Int) -> [T] {
        items.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
    }

    private static func patternTrain(_ pattern: TrainServicePatterns.Pattern) -> Train {
        TrainServicePatterns.apply(pattern, to: Train(
            id: pattern.id, date: nil, number: "", origin: "", destination: "", stops: []))
    }

    @Test("Current stop patterns: how many fill, need a choice or have no route")
    func patterns() throws {
        let started = Date()
        let planner = try Planner()
        var tally = Tally()
        let current = TrainServicePatterns.patterns.filter { $0.validUntil == nil }
            .sorted { $0.id < $1.id }
        let sampled = Self.sample(current, stride: Self.patternStride)
        for pattern in sampled {
            _ = try planner.classify(train: Self.patternTrain(pattern), day: "2026-11-11",
                                     tally: &tally, weight: 1, label: pattern.id)
        }
        print(tally.summary("patterns", seconds: Date().timeIntervalSince(started)))
        for (verdict, labels) in tally.examples.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("CENSUS patterns \(verdict.rawValue) e.g. \(labels.joined(separator: ", "))")
        }
        print("CENSUS patterns: current=\(current.count) planned=\(sampled.count) (stride \(Self.patternStride))")
        #expect(tally.total == sampled.count)
        #expect(current.count >= 200)
        // Floors, well under the measured counts, so a planner regression shows
        // but a data refresh does not fail the build.
        #expect(tally.count(.fills) >= (Self.fullRun ? 40 : 4), "\(tally.summary("patterns", seconds: 0))")
        #expect(tally.count(.callWithoutCode) == 0)
        #expect(tally.endpointCodeMismatches == 0, "planner codes differ from pattern codes")
        // The one rule unit 1 promises: a span fill never refuses.
        #expect(tally.count(.spanRefused) == 0, "\(tally.summary("patterns", seconds: 0))")
        #expect(tally.count(.noRoute) <= 15, "\(tally.summary("patterns", seconds: 0))")
        #expect(tally.count(.joinRefused) <= 20, "\(tally.summary("patterns", seconds: 0))")
    }

    @Test("Patterns with no corridor stay recorded as no route")
    func noRoutePatterns() throws {
        let planner = try Planner()
        for id in ["tsubasa-tokyo-shinjo", "komachi-tokyo-akita"] {
            let pattern = try #require(TrainServicePatterns.patterns.first { $0.id == id })
            var tally = Tally()
            let verdict = try planner.classify(train: Self.patternTrain(pattern), day: "2026-11-11",
                                               tally: &tally, weight: 1, label: id)
            #expect(verdict == .noRoute, "\(id) \(verdict)")
        }
    }

    @Test("のぞみ, ひかり and こだま 東京 to 新大阪 fill to the 17 Tokaido Shinkansen stations")
    func tokaidoFills() throws {
        let planner = try Planner()
        for id in ["nozomi-tokyo-shin-osaka", "hikari-tokyo-shin-osaka", "kodama-tokyo-shin-osaka"] {
            let pattern = try #require(TrainServicePatterns.patterns.first { $0.id == id })
            let train = Self.patternTrain(pattern)
            var tally = Tally()
            let verdict = try planner.classify(train: train, day: "2026-11-11", tally: &tally,
                                               weight: 1, label: id)
            #expect(verdict == .fills, "\(id) \(verdict)")
            let codes = train.stops.compactMap(\.n02StationCode)
            var chosen: [TripRoutePlanner.Corridor] = []
            for index in 0..<(codes.count - 1) {
                guard case .corridors(let found) = try planner.outcome(
                    from: codes[index], to: codes[index + 1], trainType: train.trainType ?? "",
                    day: "2026-11-11") else { Issue.record("\(id) section \(index)"); return }
                chosen.append(TripRoutePlanner.plausible(found, waypoints: codes)[0])
            }
            guard case .corridors(let routes) = TripRoutePlanner.joining(
                chosen, allowUnverifiedConnections: false, rideDate: "2026-11-11",
                patterns: planner.catalog.patterns, connectors: planner.catalog.connectors,
                junctions: planner.junctions, lineName: { _ in nil }),
                let route = routes.first else { Issue.record("\(id) did not join"); return }
            let proposal = try #require(LocalJourneyAutofill.proposal(
                train: train, choice: route.choice, span: 0...(train.stops.count - 1)))
            #expect(proposal.train.stops.count == 17, "\(id): \(proposal.train.stops.map(\.name))")
            #expect(proposal.train.stops.first?.name == "東京")
            #expect(proposal.train.stops.last?.name == "新大阪")
            for name in ["小田原", "熱海", "三島", "新富士", "静岡", "掛川", "浜松", "豊橋", "三河安城", "岐阜羽島", "米原"] {
                let found = proposal.train.stops.first { $0.name == name }
                if id.hasPrefix("kodama") {
                    #expect(found?.stopType == "passenger_stop", "\(id) \(name)")
                } else {
                    #expect(found?.stopType == "pass_through" && found?.arrival == nil && found?.departure == nil,
                            "\(id) \(name) should be an untimed pass_through")
                }
            }
        }
    }

    /// First service date of each bundled trip, read from the calendar rows.
    private static func firstServiceDates() throws -> (rows: [(tripID: String, date: String)], tripCount: Int) {
        let url = try #require(TrainTimetableDatabase.bundledURL(in: .module))
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle
        else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(db) }
        let sql = """
            SELECT t.trip_id, MIN(e.service_date) FROM trips t
            JOIN calendar_exceptions e ON e.calendar_id = t.calendar_id AND e.exception_type = 'add'
            GROUP BY t.trip_id ORDER BY t.trip_id
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [(String, String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((String(cString: sqlite3_column_text(statement, 0)),
                         String(cString: sqlite3_column_text(statement, 1))))
        }
        var countStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM trips", -1, &countStatement, nil) == SQLITE_OK,
              sqlite3_step(countStatement) == SQLITE_ROW else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_finalize(countStatement) }
        return (rows, Int(sqlite3_column_int64(countStatement, 0)))
    }

    @Test("Bundled timed trips: planner codes against timetable codes, and how many fill")
    func timedTrips() throws {
        let started = Date()
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let planner = try Planner()
        let (dates, tripCount) = try Self.firstServiceDates()
        var tally = Tally()
        var loaded = 0
        var unreadable = 0
        // Trips with one call list and one train type plan once; weight counts the rest.
        var signatures: [String: (train: Train, weight: Int, label: String)] = [:]
        for (tripID, date) in dates {
            guard let trip = try database.trip(id: tripID, on: date),
                  let train = trip.publishedStopsDraft(to: Train(
                    id: tripID, number: "", origin: "", destination: "", stops: [], region: "jp"))
            else { unreadable += 1; continue }
            loaded += 1
            let signature = (train.trainType ?? "") + "|"
                + train.stops.map { $0.n02StationCode ?? "?" }.joined(separator: ",")
            if var known = signatures[signature] { known.weight += 1; signatures[signature] = known }
            else { signatures[signature] = (train, 1, "\(trip.service.canonicalName) \(trip.publicNumber ?? trip.trainNumber)") }
        }
        let ordered = signatures.sorted { $0.key < $1.key }.map(\.value)
        let planned = Self.sample(ordered, stride: Self.tripStride)
        for entry in planned {
            _ = try planner.classify(train: entry.train, day: "2026-09-30", tally: &tally,
                                     weight: entry.weight, label: entry.label)
        }
        print("CENSUS trips: bundled=\(dates.count) loaded=\(loaded) unreadable=\(unreadable) distinctCallLists=\(signatures.count)")
        print(tally.summary("trips", seconds: Date().timeIntervalSince(started)))
        for (verdict, labels) in tally.examples.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("CENSUS trips \(verdict.rawValue) e.g. \(labels.joined(separator: ", "))")
        }
        // Every bundled trip has an 'add' calendar date, so none dropped out of the join.
        #expect(dates.count == tripCount, "trips without an add exception: \(tripCount - dates.count)")
        #expect(loaded + unreadable == dates.count)
        #expect(loaded >= 800)
        print("CENSUS trips: planned \(planned.count) of \(signatures.count) distinct call lists (stride \(Self.tripStride)), \(tally.total) trips")
        #expect(tally.total >= loaded / (Self.tripStride * 3))
        let full = Self.fullRun
        #expect(tally.count(.fills) >= (full ? 100 : 4), "\(tally.summary("trips", seconds: 0))")
        #expect(tally.endpointCodeMismatches == 0, "planner codes differ from timetable codes")
        #expect(tally.count(.callWithoutCode) == 0)
        #expect(tally.count(.spanRefused) == 0, "\(tally.summary("trips", seconds: 0))")
        #expect(tally.count(.noRoute) <= (full ? 80 : 20), "\(tally.summary("trips", seconds: 0))")
        #expect(tally.count(.joinRefused) <= (full ? 80 : 20), "\(tally.summary("trips", seconds: 0))")
    }
}
