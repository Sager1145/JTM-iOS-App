import RailApplication
import RailCore
import RailPresentation
import SwiftUI

extension JourneyEditorView {
    enum HistoricalNotice { case info, warning }

    static func historicalNotice(for section: PlannedSection, choice: String?) -> HistoricalNotice? {
        if let id = choice, section.historical.contains(id) { return .info }
        if section.historicalProbe == .historicalOnly { return .info }
        switch section.outcome {
        case .noRoute, .disconnected:
            return section.historicalProbe == PlannedSection.HistoricalProbe.none ? .warning : nil
        default: return nil
        }
    }

    /// The first failed section sets the trip's outcome (`rejoin`). When that
    /// section shows a historical notice, the red noRoute/disconnected error
    /// would contradict it ("closed line") or repeat it ("no line on this
    /// date"), so only the notice is shown.
    static func routeErrorCoveredByNotice(
        _ sections: [PlannedSection], choice: (PlannedSection) -> String?
    ) -> Bool {
        guard let failed = sections.first(where: {
            if case .corridors = $0.outcome { return false }
            return true
        }) else { return false }
        switch failed.outcome {
        case .noRoute, .disconnected: return historicalNotice(for: failed, choice: choice(failed)) != nil
        default: return false
        }
    }

    // MARK: - sections

    /// One station-to-station stretch of the trip, planned on its own.
    struct PlannedSection: Equatable {
        var key: String
        var fromName: String
        var toName: String
        var outcome: TripRoutePlanner.Outcome
        var geometry: [String: [TripRouteGeometry.Piece]]
        /// Corridors the dated network proved, by id.
        var proven: Set<String>
        var proofFailure: String?
        var removedByDate: Bool
        /// Corridors that resolve only on the ride date (a line closed since).
        var historical: Set<String> = []
        /// For a section the planner could not connect: what the dated network says.
        var historicalProbe: HistoricalProbe?

        enum HistoricalProbe: Equatable {
            case historicalOnly
            case none
        }

        var candidates: [TripRoutePlanner.Corridor] {
            if case .corridors(let corridors) = outcome { return corridors }
            return []
        }
    }
}

/// Planning the trip section by section, checking it against the dated
/// network, and joining the reader's choices into one route.
extension TripDraftModel {
    /// A section's cache key: everything its plan depends on, nothing else.
    func sectionKey(_ request: TripRoutePlanner.Request, rideDate: String) -> String {
        [request.originCode, request.destinationCode, request.originLineID ?? "", request.destinationLineID ?? "",
         request.trainType ?? "", request.operatorName ?? "", rideDate,
         request.allowUnverifiedConnections ? "1" : "0"].joined(separator: "\u{1f}")
    }

    /// Sections the reader still has to choose.
    var pendingSections: [Int] {
        sections.indices.filter { sections[$0].candidates.count > 1 && choice(for: sections[$0]) == nil }
    }

    /// A choice is kept by the section's shape (its ends and lines), so a new
    /// date, company or "Continue anyway" keeps it while it is still offered.
    func choiceKey(_ section: PlannedSection) -> String {
        section.key.split(separator: "\u{1f}", omittingEmptySubsequences: false).prefix(4).joined(separator: "\u{1f}")
    }

    func choice(for section: PlannedSection) -> String? {
        guard let id = sectionChoices[choiceKey(section)],
              section.candidates.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func planRoute() async {
        // Typing a number or nudging a time changes the identity on every
        // keystroke. Wait for the input to settle before solving; a newer
        // identity cancels this task during the wait.
        if routeEdited, origin != nil, destination != nil {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        let generation = draftGeneration
        let identity = routeIdentity
        plannedIdentity = ""
        autofillFailed = false
        guard routeEdited, let origin, let destination, let package, let geometryCache else {
            searching = false
            sections = []
            outcome = nil
            selectedCorridorID = nil
            refreshDrawnRoutes()
            return
        }
        let rideDate = dayString(departure)
        let viaCodes = vias.map(\.station.key.sourceCode)
        let operatorName = companyName.isEmpty || !companyOptions.contains(companyName)
            ? nil : (packageOperatorByDisplayName[companyName] ?? companyName)
        let base = TripRoutePlanner.Request(
            originCode: origin.key.sourceCode, destinationCode: destination.key.sourceCode,
            trainType: trainType, operatorName: operatorName,
            originLineID: originLine?.id, destinationLineID: destinationLine?.id,
            allowUnverifiedConnections: allowUnverifiedConnections)
        let requests = TripRoutePlanner.sectionRequests(base, viaCodes: viaCodes)
        let keys = requests.map { sectionKey($0, rideDate: rideDate) }
        let wholeKey = viaCodes.isEmpty ? nil : "whole\u{1e}" + sectionKey(base, rideDate: rideDate)
            + "\u{1e}" + viaCodes.joined(separator: ",")
        let missing = zip(requests, keys).filter { sectionCache[$0.1] == nil }
        let needsWhole = wholeKey.map { wholeTripCache[$0] == nil } ?? false
        let names = Dictionary(
            ([origin, destination] + vias.map(\.station)).map { ($0.key.sourceCode, $0.name) },
            uniquingKeysWith: { first, _ in first })
        searching = !missing.isEmpty || needsWhole
        if !missing.isEmpty || needsWhole {
            let codes = [base.originCode, base.destinationCode] + viaCodes
            let worker = Task.detached(priority: .userInitiated) { () throws -> ([(String, TripRoutePlanner.Outcome, [String: [TripRouteGeometry.Piece]])], [TripRoutePlanner.Corridor]?, [String: String]) in
                let aliases = try loadJourneyStationAliases(for: codes, package: package)
                let context = try loadJourneyAdmissionContext(rideDate: rideDate, package: package)
                var solved: [(String, TripRoutePlanner.Outcome, [String: [TripRouteGeometry.Piece]])] = []
                for (request, key) in missing {
                    try Task.checkCancellation()
                    var request = request
                    request.stationAliases = aliases
                    let outcome = try TripRoutePlanner.plan(
                        package: package, request: request, rideDate: rideDate, admissionContext: context)
                    var geometry: [String: [TripRouteGeometry.Piece]] = [:]
                    if case .corridors(let corridors) = outcome {
                        for corridor in corridors.prefix(JourneyEditorView.maximumDrawnRoutes) {
                            geometry[corridor.id] = TripRouteGeometry.pieces(for: corridor.choice, cache: geometryCache)
                        }
                    }
                    solved.append((key, outcome, geometry))
                }
                var whole: [TripRoutePlanner.Corridor]?
                if needsWhole {
                    var request = base
                    request.stationAliases = aliases
                    if case .corridors(let corridors) = try TripRoutePlanner.plan(
                        package: package, request: request, rideDate: rideDate, admissionContext: context) {
                        whole = corridors
                    } else {
                        whole = []
                    }
                }
                return (solved, whole, aliases)
            }
            let result: ([(String, TripRoutePlanner.Outcome, [String: [TripRouteGeometry.Piece]])], [TripRoutePlanner.Corridor]?, [String: String])
            do {
                result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, identity == routeIdentity, generation == draftGeneration else { return }
                searching = false
                routeProofFailure = error.localizedDescription
                // The previous route is not this trip's any more.
                sections = []
                outcome = nil
                selectedCorridorID = nil
                drawnRoutes = []
                return
            }
            guard !Task.isCancelled, generation == draftGeneration else { return }
            for (key, outcome, geometry) in result.0 {
                let request = zip(requests, keys).first { $0.1 == key }?.0
                var section = PlannedSection(
                    key: key,
                    fromName: request.flatMap { names[$0.originCode] } ?? "",
                    toName: request.flatMap { names[$0.destinationCode] } ?? "",
                    outcome: outcome, geometry: geometry, proven: [], proofFailure: nil, removedByDate: false)
                await validateDates(
                    &section, rideDate: rideDate,
                    endpoints: request.map { ($0.originCode, $0.destinationCode) })
                guard !Task.isCancelled, generation == draftGeneration else { return }
                sectionCache[key] = section
            }
            if let wholeKey, let whole = result.1 { wholeTripCache[wholeKey] = whole }
            sectionAliases.merge(result.2) { current, _ in current }
            // Each section result is kept for this session; the cache only
            // grows with the stations the reader actually tried.
            if sectionCache.count > 64 { sectionCache = sectionCache.filter { keys.contains($0.key) } }
        }
        guard !Task.isCancelled, identity == routeIdentity, generation == draftGeneration else { return }
        // A path through another of the trip's stops is not a real choice.
        let waypoints = [base.originCode] + viaCodes + [base.destinationCode]
        sections = keys.compactMap { key -> PlannedSection? in
            guard var section = sectionCache[key] else { return nil }
            if case .corridors(let corridors) = section.outcome {
                section.outcome = .corridors(TripRoutePlanner.plausible(
                    corridors, waypoints: waypoints, stationAliases: sectionAliases))
            }
            return section
        }
        wholeTrip = wholeKey.flatMap { wholeTripCache[$0] } ?? []
        for section in sections where section.candidates.count == 1 {
            sectionChoices[choiceKey(section)] = section.candidates[0].id
        }
        // Stay on the section the reader is looking at while it still exists.
        if let key = activeSectionKey, let kept = sections.firstIndex(where: { choiceKey($0) == key }) {
            activeSection = kept
        } else {
            activeSection = pendingSections.first ?? 0
        }
        activeSectionKey = sections.indices.contains(activeSection) ? choiceKey(sections[activeSection]) : nil
        searching = false
        plannedIdentity = identity
        rejoin()
        // Frame the route once per set of stations; a time or train edit
        // replans without moving a camera the reader may have panned.
        if routeFitIdentity != endpointIdentity {
            routeFitIdentity = endpointIdentity
            mapFitRevision += 1
        }
    }

    /// The dated network may have opened a candidate after the ride date.
    /// Filters this section's candidates and records which were proven.
    func validateDates(
        _ section: inout PlannedSection, rideDate: String, endpoints: (from: String, to: String)?
    ) async {
        let hasDatedNetwork = RiddenRouteStore.hasDatedNetwork(region: region.code)
        guard hasDatedNetwork else { return }
        var corridors: [TripRoutePlanner.Corridor] = []
        var unconnected = false
        switch section.outcome {
        case .noRoute, .disconnected:
            unconnected = true
        case .corridors(let found) where !found.isEmpty:
            corridors = found
        default:
            return
        }
        let latestValidFrom: String?
        do { latestValidFrom = try RiddenRouteStore.latestValidFrom(region: region.code) }
        catch {
            // Unknown date bounds cannot exclude otherwise valid corridors.
            if !unconnected { section.proofFailure = error.localizedDescription }
            return
        }
        let normalized = Dates.normalizeDateString(rideDate)
        if unconnected {
            guard latestValidFrom.map({ rideDate < $0 }) == true else { return }
            await probeHistorical(&section, rideDate: rideDate, endpoints: endpoints)
            return
        }
        guard normalized != rideDate || latestValidFrom.map({ rideDate < $0 }) == true else { return }
        let candidates = corridors.compactMap { corridor in
            candidateTrain(for: corridor).map { TripRouteValidation.Candidate(id: corridor.id, train: $0) }
        }
        do {
            let validation = try await TripRouteValidation.validate(candidates: candidates) { trains in
                try await RiddenRouteStore.routeAvailabilities(trains).map {
                    .init(datedResolved: $0.datedResolved, undatedResolved: $0.undatedResolved)
                }
            }
            section.proven = validation.unprovenReason == nil ? validation.physicallyResolvedIDs : []
            section.historical = validation.historicalOnlyIDs
            section.proofFailure = validation.unprovenReason
            let kept = corridors.filter { validation.retainedIDs.contains($0.id) }
            section.removedByDate = kept.count < corridors.count
            section.outcome = .corridors(kept)
        } catch {
            section.proven = []
            section.historical = []
            section.proofFailure = "Route proof is unavailable, so these records stay savable and unproven."
        }
    }

    /// The planner knows only current lines. Ask the dated network whether
    /// this unconnected pair was joined by a since-closed line on the ride date.
    func probeHistorical(
        _ section: inout PlannedSection, rideDate: String, endpoints: (from: String, to: String)?
    ) async {
        guard let endpoints, !section.fromName.isEmpty, !section.toName.isEmpty else { return }
        let probeKey = [endpoints.from, endpoints.to, rideDate].joined(separator: "\u{1e}")
        if let cached = historicalProbeCache[probeKey] {
            section.historicalProbe = cached
            return
        }
        var scaffold = Train(id: draft.id, number: "check", origin: section.fromName, destination: section.toName, stops: [
            Stop(name: section.fromName, n02StationCode: endpoints.from, stopType: "origin", rideSegment: true),
            Stop(name: section.toName, n02StationCode: endpoints.to, stopType: "destination", rideSegment: true),
        ])
        scaffold.region = region.code
        scaffold.date = rideDate
        scaffold.routeConfirmation = .confirmed
        guard let catalog,
              let from = catalog.station(StationKey(regionCode: region.code, sourceCode: endpoints.from)),
              let to = catalog.station(StationKey(regionCode: region.code, sourceCode: endpoints.to)) else { return }
        // Dated only and near the two stations: the planner already found no
        // route on today's network, and the national graph is never built.
        // A failed call stays uncached so the next plan retries it.
        guard let connected = try? await RiddenRouteStore.historicalConnection(
            scaffold,
            between: Coordinate(lon: from.longitude, lat: from.latitude),
            and: Coordinate(lon: to.longitude, lat: to.latitude)) else { return }
        guard !Task.isCancelled else { return }
        let probe: PlannedSection.HistoricalProbe = connected ? .historicalOnly : .none
        historicalProbeCache[probeKey] = probe
        section.historicalProbe = probe
    }

    /// A two-stop trip along one section's corridor, for date validation.
    func candidateTrain(for corridor: TripRoutePlanner.Corridor) -> Train? {
        guard let first = corridor.choice.stations.first, let last = corridor.choice.stations.last else { return nil }
        var scaffold = Train(id: draft.id, number: "check", origin: first.name, destination: last.name, stops: [
            Stop(name: first.name, n02StationCode: first.code, stopType: "origin", rideSegment: true),
            Stop(name: last.name, n02StationCode: last.code, stopType: "destination", rideSegment: true),
        ])
        scaffold.region = region.code
        scaffold.date = dayString(departure)
        return LocalJourneyAutofill.proposal(train: scaffold, choice: corridor.choice)?.train
    }

    /// Joins the chosen corridor of every section into the trip's route.
    /// Cheap: changing one section's choice never re-plans the others.
    func rejoin() {
        corridorsRemovedByDate = sections.contains(where: \.removedByDate)
        routeProofFailure = sections.compactMap(\.proofFailure).first
        if let failed = sections.first(where: { if case .corridors = $0.outcome { return false }; return true }) {
            outcome = failed.outcome
            selectedCorridorID = nil
            refreshDrawnRoutes()
            return
        }
        if sections.contains(where: \.candidates.isEmpty) {
            outcome = .corridors([])
            selectedCorridorID = nil
            refreshDrawnRoutes()
            return
        }
        let chosen = sections.compactMap { section in
            section.candidates.first { $0.id == choice(for: section) }
        }
        guard chosen.count == sections.count else {
            outcome = nil
            selectedCorridorID = nil
            refreshDrawnRoutes()
            return
        }
        let lineNames = Dictionary((package?.lines ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let joined = TripRoutePlanner.joining(
            chosen, wholeTrip: wholeTrip, allowUnverifiedConnections: allowUnverifiedConnections,
            stationAliases: sectionAliases, region: package?.country, rideDate: dayString(departure)) { lineNames[$0] }
        outcome = joined
        if case .corridors(let route) = joined, let corridor = route.first {
            corridorGeometry = [corridor.id: zip(sections.indices, chosen).flatMap { pieces(for: $1, inSection: $0) }]
            physicallyResolvedCorridorIDs = zip(sections, chosen).allSatisfy({ $0.proven.contains($1.id) })
                ? [corridor.id] : []
            selectedCorridorID = corridor.id
        } else {
            selectedCorridorID = nil
        }
        refreshDrawnRoutes()
    }

    func choose(_ corridorID: String, inSection index: Int) {
        guard sections.indices.contains(index) else { return }
        sectionChoices[choiceKey(sections[index])] = corridorID
        // Move on to the next section that still needs a choice.
        activeSection = pendingSections.first ?? index
        activeSectionKey = choiceKey(sections[activeSection])
        rejoin()
    }

    /// Track for a candidate. Only the first few are drawn ahead of time; a
    /// later one is built when the reader picks it.
    func pieces(for corridor: TripRoutePlanner.Corridor, inSection index: Int) -> [TripRouteGeometry.Piece] {
        if let pieces = sections[index].geometry[corridor.id] { return pieces }
        guard let geometryCache else { return [] }
        let pieces = TripRouteGeometry.pieces(for: corridor.choice, cache: geometryCache)
        sections[index].geometry[corridor.id] = pieces
        sectionCache[sections[index].key]?.geometry[corridor.id] = pieces
        return pieces
    }
}
