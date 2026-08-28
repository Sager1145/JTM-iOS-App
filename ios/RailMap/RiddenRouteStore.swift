import Foundation
import Observation
import RailCore

/// Precomputed ridden geometry shipped by the main fork's progressive sample
/// datasets. Each part contains one canonical train plus the exact route
/// features produced by the web solver; the native map consumes those
/// coordinates directly and never invents a straight-line fallback.
@MainActor
@Observable
final class RiddenRouteStore {
    struct DrawnSegment: Sendable {
        let segmentIndex: Int
        let from: String?
        let to: String?
        /// Canonical WGS84 geometry used by the solver, cache and statistics.
        /// It must remain in the same datum as the region's edge index.
        let sourceCoordinates: [Coordinate]
        /// Geometry presented to MapKit. This differs for Taiwan, Hong Kong,
        /// Macao and Korea, where Apple's basemap is displaced to GCJ-02.
        let coordinates: [Coordinate]

        init(
            segmentIndex: Int, from: String?, to: String?,
            coordinates: [Coordinate], country: String
        ) {
            self.segmentIndex = segmentIndex
            self.from = from
            self.to = to
            sourceCoordinates = coordinates
            self.coordinates = AppleMapDatum.display(coordinates, country: country)
        }
    }

    /// What became of one journey's route, per journey rather than per store.
    ///
    /// The store used to answer this with a single bit — a ride was in `rides`
    /// or it was not — and that bit could not tell "drew everything" from
    /// "drew four of six and dropped the rest". `solveMissing` appended a ride
    /// `if !segments.isEmpty` and discarded every section that solved to
    /// nothing, so a partly-solved journey was indistinguishable from a whole
    /// one and the interface had nothing to warn anybody with.
    ///
    /// Nothing here ever invents geometry: `partial` and `unavailable` mean a
    /// stretch of railway was **not drawn**, never that a straight line stood
    /// in for it.
    enum RouteOutcome: Sendable, Equatable {
        /// Every section the journey asked for came back with geometry.
        case resolved
        /// Some did not. `unsolved` names them the way the reader wrote them,
        /// so the interface can say which stretch is missing rather than that
        /// something, somewhere, failed.
        case partial(solved: Int, expected: Int, unsolved: [SectionGap])
        /// Not one section solved. The record is untouched and still exports.
        case unavailable(expected: Int)

        var isResolved: Bool { self == .resolved }
    }

    /// One stretch that has no drawn railway, named by its own endpoints.
    struct SectionGap: Sendable, Equatable {
        let segmentIndex: Int
        let from: String?
        let to: String?
    }

    struct DrawnRide: Identifiable, Sendable {
        let id: String
        /// The service description drives journey-station level of detail:
        /// sparse high-speed and limited services reveal their calls before a
        /// dense local service does.
        let trainType: String?
        /// The region this ride was solved against — `"jp"`, `"tw"`, `"hk"`,
        /// `"mo"` or `"kr"`.
        ///
        /// Carried on the ride rather than looked up from the train, because
        /// the map is handed rides and not journeys: the ridden-line category
        /// filter classifies a drawn segment against its own region's N02 edge
        /// index, and picking the wrong region's index would not fail — it
        /// would answer, wrongly.
        let country: String
        let colorHex: String
        let visible: Bool
        let segments: [DrawnSegment]
        /// What became of the route. See ``RouteOutcome``.
        let route: RouteOutcome
        /// The journey's stops, in order, carrying the two fields the map
        /// cannot otherwise know: which calls were ridden (`rideSegment`) and
        /// which stations are rolled through rather than called at
        /// (`stopType`). Without them every drawn segment has to be assumed
        /// ridden and every section boundary assumed a call, and a
        /// pass-through drawn as a stop is a claim about the journey that the
        /// reader did not make.
        let stops: [Stop]
        /// The calendar days this itinerary touches and where it crosses them,
        /// so an overnight ride can draw the half that runs on the other day
        /// differently — `Dates.segmentDate(_:segmentIndex:)` maps a segment to
        /// its day.
        let daySpan: Dates.DaySpan
        /// A precomputed identity for the actual vertices.
        ///
        /// The map compares rides during every SwiftUI update. Walking all
        /// coordinates there makes a sheet drag pay for route geometry on
        /// every frame; comparing only `vertexCount` misses a rebuilt route
        /// whose new geometry happens to have the same number of points.
        /// Hash once when the ride is decoded and both paths stay cheap.
        let geometryDigest: Int
        var strokes: [[Coordinate]] { segments.map(\.coordinates) }
        var vertexCount: Int { strokes.reduce(0) { $0 + $1.count } }
    }

    enum LoadState {
        case idle
        case loading
        case loaded(rides: [DrawnRide])
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var rides: [DrawnRide] = []
    /// Stable, already-filtered input for the map.
    ///
    /// Filtering in `RailWorkspaceView.body` allocated a fresh array on every
    /// sheet-height sample, defeating the renderer's shared-storage fast path
    /// even when no journey had changed.
    private(set) var visibleRides: [DrawnRide] = []
    private var loadTask: Task<Void, Never>?

    /// Solve and draw every ride, whatever region each belongs to.
    ///
    /// The web app is handed one dataset and one country because it has one
    /// region open. Here each ride names its own region (`Train.region`), the
    /// pipeline groups by it, and the per-region resources — the sections
    /// file, the station table, the package, the route cache — are loaded once
    /// per region that actually has rides rather than once per app.
    func load(trains: [Train], preferredTrainID: String? = nil) {
        loadTask?.cancel()
        state = .loading
        // The status centre is how the journey detail and the editor — neither
        // of which is handed this store — learn what became of a route. See
        // `RideStatusCenter` for why that is a published projection rather
        // than an initialiser argument.
        RideStatusCenter.shared.routeStore = self
        RideStatusCenter.shared.publish(phase: .loading)
        // Duplicate ids cannot survive `StoreOperations`, but a store merged
        // out of five files once could carry one, and a trap here would be a
        // crash on a data fault rather than a drawing of it.
        let wanted = Dictionary(trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wantedIDs = trains.map(\.id)
        loadTask = Task(priority: .userInitiated) {
            do {
                // Publish the one route the reader last looked at before the
                // all-route scan. Its cache is a single small file; the old
                // path withheld even that hit until every cached route had
                // been read and every miss had been solved.
                let primed = await Self.loadPreferred(
                    id: preferredTrainID, wanted: wanted)
                try Task.checkCancellation()
                if let primed {
                    rides = [primed]
                    visibleRides = primed.visible ? [primed] : []
                    RideStatusCenter.shared.publish(
                        entries: Self.statusEntries(for: [primed], wanted: []),
                        phase: .loading)
                }

                let decoded = try await Self.decode(wanted: wanted, primed: primed)
                try Task.checkCancellation()
                rides = decoded
                visibleRides = decoded.filter(\.visible)
                state = .loaded(rides: decoded)
                RideStatusCenter.shared.publish(
                    entries: Self.statusEntries(for: decoded, wanted: wantedIDs),
                    phase: .loaded)
                Self.sweepRouteCacheOnce()
            } catch is CancellationError {
                return
            } catch {
                rides = []
                visibleRides = []
                state = .failed(error.localizedDescription)
                RideStatusCenter.shared.publish(
                    entries: [:], phase: .failed(error.localizedDescription))
            }
        }
    }

    /// Read the last-viewed route only. A miss deliberately does not solve:
    /// the complete decoder below owns expensive work and its cancellation.
    private nonisolated static func loadPreferred(
        id: String?, wanted: [String: Train]
    ) async -> DrawnRide? {
        guard let id, let train = wanted[id] else { return nil }
        let country = Region.resolved(train).code
        return loadCached([train], country: country).rides.first
    }

    func clear() {
        loadTask?.cancel()
        rides = []
        visibleRides = []
        state = .idle
        RideStatusCenter.shared.clear()
    }

    /// Solve one journey's route again, in place (§8.4).
    ///
    /// The failure this guards against: the drawn line stops being a picture
    /// of the record it claims to be — OLD geometry under a NEW section list,
    /// which is worse than showing nothing. The shell's route key now covers
    /// the whole record, so a full reload would eventually correct it; this
    /// corrects the one journey the reader just rebuilt without waiting for
    /// the other two hundred to be read back.
    ///
    /// Nothing is deleted from the itinerary store here, and nothing is
    /// straight-lined: a journey whose new sections solve to nothing keeps its
    /// record and loses its strokes, which is what "unavailable" means.
    func resolve(_ train: Train) {
        let country = Region.resolved(train).code
        let id = train.id
        RideStatusCenter.shared.beginResolving(id)
        Task {
            let solved = await Task.detached(priority: .userInitiated) { () -> DrawnRide? in
                try? Self.resolveOne(train, country: country)
            }.value

            if let solved {
                if let index = rides.firstIndex(where: { $0.id == id }) {
                    rides[index] = solved
                } else {
                    rides.append(solved)
                }
            } else {
                rides.removeAll { $0.id == id }
            }
            visibleRides = rides.filter(\.visible)
            if case .loaded = state { state = .loaded(rides: rides) }
            RideStatusCenter.shared.finishResolving(
                id,
                entry: solved.map {
                    RideStatusCenter.Entry(outcome: $0.route, drawnSegments: $0.segments.count)
                } ?? RideStatusCenter.Entry(outcome: .unavailable(expected: 0), drawnSegments: 0))
        }
    }

    /// One journey through the same cache-then-solve path a full load uses.
    ///
    /// `nil` means the journey asked for no sections at all, which the caller
    /// records as `unavailable(expected: 0)` rather than as silence.
    private nonisolated static func resolveOne(
        _ train: Train, country: String
    ) throws -> DrawnRide? {
        let cached = loadCached([train], country: country)
        if let ride = cached.rides.first { return ride }
        return try solveMissing(cached.missing, country: country).first
    }

    /// What each journey the load was asked about ended up with.
    ///
    /// A train that produced no `DrawnRide` at all is recorded as
    /// `unavailable(expected: 0)`: `solveMissing` skips a train whose
    /// canonical section list is empty, and leaving those absent would make
    /// "this journey has nothing to draw" indistinguishable from "this journey
    /// was never looked at".
    private nonisolated static func statusEntries(
        for rides: [DrawnRide], wanted: [String]
    ) -> [String: RideStatusCenter.Entry] {
        var entries: [String: RideStatusCenter.Entry] = [:]
        for ride in rides {
            entries[ride.id] = RideStatusCenter.Entry(
                outcome: ride.route, drawnSegments: ride.segments.count)
        }
        for id in wanted where entries[id] == nil {
            entries[id] = RideStatusCenter.Entry(
                outcome: .unavailable(expected: 0), drawnSegments: 0)
        }
        return entries
    }

    /// Cache, then the precomputed datasets, then solve — per region.
    ///
    /// The order is the reverse of the web app's, and the reason is the merged
    /// store. The web app reads its one dataset first because that dataset IS
    /// its store; here a reader can hold the 201-journey Japanese sample, the
    /// New Year loop and their own rides at once, so "which dataset?" has no
    /// single answer and scanning every candidate on every reload would decode
    /// 11 MB of parts to answer a question the on-disk cache has already
    /// answered. Rides that come out of a dataset are written into that cache,
    /// so the scan happens once per journey rather than once per load.
    private nonisolated static func decode(
        wanted: [String: Train], primed: DrawnRide? = nil
    ) async throws -> [DrawnRide] {
        var result: [DrawnRide] = primed.map { [$0] } ?? []
        var unresolved: [Region: [Train]] = [:]
        let remaining = wanted.values.filter { $0.id != primed?.id }
        for (region, trains) in Dictionary(grouping: remaining, by: Region.resolved) {
            let cached = await loadCachedConcurrently(trains, country: region.code)
            result += cached.rides
            if !cached.missing.isEmpty { unresolved[region] = cached.missing }
        }

        for (region, trains) in unresolved {
            var missing = Dictionary(
                trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for dataset in RideLibrary.routeDatasets(for: region) {
                if missing.isEmpty { break }
                let found = try await datasetRides(
                    dataset: dataset, country: region.code, wanted: missing)
                for ride in found { missing.removeValue(forKey: ride.id) }
                result += found
            }
            if !missing.isEmpty {
                result += try solveMissing(Array(missing.values), country: region.code)
            }
        }
        return result
    }

    /// The rides one precomputed dataset can answer for.
    ///
    /// A part is accepted only when its train's route-cache digest matches the
    /// one in the store, which is what makes searching several datasets safe:
    /// geometry solved for another itinerary is rejected rather than drawn.
    ///
    /// Which parts are even worth opening comes from ``DatasetPartIndex``.
    /// This used to walk the manifest and decode every part in it before
    /// reading the train id it had just paid for, so one journey missing from
    /// the route cache cost the whole dataset — 201 files and 7 MB for the
    /// Japanese sample — and the next journey cost it again.
    private nonisolated static func datasetRides(
        dataset: String,
        country: String,
        wanted: [String: Train]
    ) async throws -> [DrawnRide] {
        let interval = RailSignpost.data.begin("route.datasetLookup")
        defer { RailSignpost.data.end("route.datasetLookup", interval) }
        let index = try await DatasetPartIndex.shared.parts(in: dataset)
        // Sorted back into manifest order, because `wanted` is a dictionary
        // and has none of its own, and the order rides come back in is the
        // order the map is handed them in.
        let hits = wanted.keys
            .flatMap { index[$0] ?? [] }
            .sorted { $0.position < $1.position }
        var result: [DrawnRide] = []
        result.reserveCapacity(hits.count)

        for hit in hits {
            try Task.checkCancellation()
            guard let partURL = Bundle.main.url(
                forResource: hit.name,
                withExtension: "json",
                subdirectory: dataset
            ) else { throw LoadError.missingPart(dataset, hit.name) }
            let part = try JSONDecoder().decode(Part.self, from: Data(contentsOf: partURL))
            guard let train = wanted[part.train.id] else { continue }
            guard routeCacheDigest(train, country: country)
                    == routeCacheDigest(part.train, country: country) else { continue }
            let expectedTemplate = routeTemplateDigest(train, country: country)
            let matchingFeatures = part.route.features.filter { feature in
                guard let expectedTemplate else { return true }
                return feature.properties?.routeTemplateKey == expectedTemplate
            }
            let indicesAreAuthoritative = matchingFeatures
                .allSatisfy { $0.properties?.segmentIndex != nil }
            let segments = matchingFeatures.flatMap { feature in
                feature.geometry.strokes.enumerated().compactMap { pair -> DrawnSegment? in
                    let (partIndex, coordinates) = pair
                    guard coordinates.count >= 2 else { return nil }
                    return DrawnSegment(
                        segmentIndex: feature.properties?.segmentIndex ?? partIndex,
                        from: feature.properties?.from,
                        to: feature.properties?.to,
                        coordinates: coordinates,
                        country: country)
                }
            }
            guard !segments.isEmpty else { continue }
            let ride = drawnRide(
                train,
                country: country,
                segments: segments,
                expectedSections: canonicalSections(train, country: country),
                indicesAreAuthoritative: indicesAreAuthoritative)
            // Written into the same cache a solve writes to, so the next load
            // finds this journey without opening a dataset at all. That is
            // what keeps the dataset search a first-load cost rather than a
            // per-load one.
            try? saveCache(ride, train: train, country: country)
            result.append(ride)
        }
        return result
    }

    /// Build one drawn ride, deciding its ``RouteOutcome`` from which of the
    /// journey's sections actually came back with geometry.
    ///
    /// The outcome is *derived* rather than stored, which is why the on-disk
    /// route cache needed no new field and no version bump: a cached ride
    /// carries its segments' indices, and the sections it was solved for are
    /// recomputed from the train beside it. A stored copy would be a second
    /// answer that could disagree with the first.
    private nonisolated static func drawnRide(
        _ train: Train,
        country: String,
        segments: [DrawnSegment],
        expectedSections: [RouteSection],
        indicesAreAuthoritative: Bool = true
    ) -> DrawnRide {
        let expected = expectedSections.count
        let solved = Set(segments.map(\.segmentIndex))
        let unsolved: [SectionGap] = expectedSections.enumerated()
            .compactMap { index, section in
                solved.contains(index)
                    ? nil
                    : SectionGap(segmentIndex: index, from: section.from, to: section.to)
            }
        let outcome: RouteOutcome
        if expected == 0 || unsolved.isEmpty || !indicesAreAuthoritative {
            // `indicesAreAuthoritative` is false for a precomputed part whose
            // features carry no `segment_index`: there the index is the
            // stroke's position, which says nothing about which SECTION it
            // came from, and comparing it against the canonical sections would
            // manufacture gaps that are not there.
            outcome = .resolved
        } else if solved.isEmpty {
            outcome = .unavailable(expected: expected)
        } else {
            outcome = .partial(solved: solved.count, expected: expected, unsolved: unsolved)
        }
        var geometryHasher = Hasher()
        geometryHasher.combine(segments.count)
        for segment in segments {
            geometryHasher.combine(segment.segmentIndex)
            geometryHasher.combine(segment.sourceCoordinates)
        }
        return DrawnRide(
            id: train.id,
            trainType: train.trainType,
            country: country,
            colorHex: train.style?.color ?? "#0a84ff",
            visible: train.visible != false,
            segments: segments,
            route: outcome,
            stops: train.stops,
            daySpan: Dates.daySpan(train.forDates),
            geometryDigest: geometryHasher.finalize())
    }

    /// The canonical route sections a journey asks for — the same normalisation
    /// the solver and the cache digest run, so "expected" means the same thing
    /// in all three.
    private nonisolated static func canonicalSections(
        _ train: Train, country: String
    ) -> [RouteSection] {
        TrainValidation.normalizeExportTrain(
            train, country: country, stations: TrainValidation.StationTable.empty
        ).routeSections ?? []
    }

    private nonisolated static func solveMissing(
        _ trains: [Train], country: String
    ) throws -> [DrawnRide] {
        guard let sectionsURL = Bundle.main.url(
            forResource: Region.countrySuffixed("rail-sections", country: country),
            withExtension: "json"),
              let stationsURL = Bundle.main.url(
                forResource: Region.countrySuffixed("stations", country: country),
                withExtension: "json")
        else { throw LoadError.missingSolverResources(country) }
        let sections = try RouteGraph.SectionFeatureCollection.load(contentsOf: sectionsURL).features
        let stationCollection = try Stations.FeatureCollection.load(contentsOf: stationsURL)
        let stationIndex = Stations.Index(stationCollection)
        let officialIntervals = RouteSolver.OfficialIntervalIndex(sections: sections)
        let displayNetwork: RouteNetwork? = {
            // Both halves of the package come off one read and one parse.
            // Asking the compact decoder and the topology decoder separately
            // opened the same file twice and scanned it twice — 9.1 MB apiece
            // for Japan, and here that is paid on a route cache miss rather
            // than once at launch.
            guard let url = Bundle.main.url(
                forResource: Region.packageResource(country: country), withExtension: "json"),
                  let loaded = try? DisplayParts.LoadedPackage.load(contentsOf: url)
            else { return nil }
            return RouteNetwork(lines: loaded.package.lines.map { line in
                RouteNetwork.Line(
                    lineId: line.id, name: line.name, operator: line.operator,
                    isLoop: false, alignmentDirection: nil,
                    parts: DisplayParts.parts(
                        for: line,
                        topology: loaded.topologyByLineID[line.id] ?? .init()))
            })
        }()
        let graphStore = RouteGraph.RouteGraphStore(sections: sections)
        graphStore.augment = { graph, bbox in
            let features: [Stations.Feature]
            if let bbox {
                features = stationCollection.features.filter { feature in
                    guard let pair = Stations.displayCoordinate(feature),
                          let coordinate = Coordinate(pair: pair) else { return false }
                    return coordinate.lon >= bbox.minX && coordinate.lon <= bbox.maxX
                        && coordinate.lat >= bbox.minY && coordinate.lat <= bbox.maxY
                }
            } else {
                features = stationCollection.features
            }
            RouteSolver.addStationTransferConnectorEdges(graph: graph, stations: features)
        }

        var rides: [DrawnRide] = []
        for train in trains {
            try Task.checkCancellation()
            let canonical = TrainValidation.normalizeExportTrain(
                train, country: country, stations: TrainValidation.StationTable.empty)
            let sections = canonical.routeSections ?? []
            guard !sections.isEmpty else { continue }
            let context = routeContext(train)
            let cacheTrain = RouteGraph.CacheKeyTrain(
                trainType: context.trainType, company: context.company,
                preferredLineNames: context.preferredLineNames,
                preferredOperatorNames: context.preferredOperatorNames,
                allowedInstitutionTypeCodes: context.allowedInstitutionTypeCodes,
                institutionFilterMode: context.institutionFilterMode)
            let allowedCodes = RouteGraph.allowedInstitutionTypeCodes(
                cacheTrain, country: country)
            var segments: [DrawnSegment] = []
            var lastSolvedIndex: Int?
            var continuity: Coordinate?
            var displayContinuity: Coordinate?
            var projectionCache = RouteProjectionCache()
            for (index, section) in sections.enumerated() {
                try Task.checkCancellation()
                let sharesBoundary = index > 0
                    && lastSolvedIndex == index - 1
                    && routeSectionBoundarySharesExplicitStop(sections[index - 1], section)
                let anchor = sharesBoundary ? continuity : nil
                let solved = RouteSolver.solveOfficialInterval(
                    section, segmentIndex: index, train: context, country: country,
                    allowedCodes: allowedCodes, intervalIndex: officialIntervals,
                    stations: stationIndex, continuityAnchor: anchor)
                    ?? RouteSolver.solveSectionOnDemand(
                        section, segmentIndex: index, train: context, country: country,
                        graphStore: graphStore, stations: stationIndex,
                        continuityAnchor: anchor)
                if let solved, solved.coordinates.count >= 2 {
                    let hints = RouteHints(
                        requiredLineNames: (section.lineNames ?? []).map(Optional.some),
                        preferredLineNames: context.preferredLineNames.map(Optional.some),
                        requiredOperatorNames: (section.operatorNames ?? []).map(Optional.some),
                        preferredOperatorNames: context.preferredOperatorNames.map(Optional.some))
                    let canonical = displayNetwork?.canonicalizeRouteFeature(
                        RouteFeature(
                            geometry: .lineString(solved.coordinates), hints: hints),
                        continueFrom: sharesBoundary ? displayContinuity : nil,
                        cache: &projectionCache)
                    let drawnCoordinates = canonical?.geometry.lines.first
                        ?? solved.coordinates
                    segments.append(DrawnSegment(
                        segmentIndex: index,
                        from: section.from ?? stationIndex.name(forCode: section.fromN02StationCode),
                        to: section.to ?? stationIndex.name(forCode: section.toN02StationCode),
                        coordinates: drawnCoordinates,
                        country: country))
                    lastSolvedIndex = index
                    continuity = solved.coordinates.last
                    displayContinuity = drawnCoordinates.last
                }
            }
            graphStore.trimRegionalGraphCache(target: RouteGraph.regionalGraphNodeBudget)
            // Emitted even when NOTHING solved. The old code appended only
            // `if !segments.isEmpty`, which is how a journey with no drawable
            // route became a journey the interface had never heard of — and a
            // ride that is absent cannot be told from a ride that is still
            // being solved. It is reported as `unavailable` instead.
            let ride = drawnRide(
                train, country: country, segments: segments, expectedSections: sections)
            rides.append(ride)
            if !segments.isEmpty { try? saveCache(ride, train: train, country: country) }
        }
        return rides
    }

    private nonisolated static func routeContext(_ train: Train) -> RouteSolver.TrainContext {
        .init(
            id: train.id, number: train.number, trainType: train.trainType ?? "",
            company: train.company ?? "", origin: train.origin,
            destination: train.destination,
            preferredLineNames: train.routePolicy?.preferredLineNames ?? [],
            preferredOperatorNames: train.routePolicy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: train.routePolicy?.allowedInstitutionTypeCodes,
            institutionFilterMode: train.routePolicy?.institutionFilterMode ?? "soft")
    }

    private nonisolated static func routeTemplateDigest(
        _ train: Train, country: String
    ) -> String? {
        let canonical = TrainValidation.normalizeExportTrain(
            train, country: country, stations: TrainValidation.StationTable.empty)
        let canonicalSections = canonical.routeSections ?? []
        let sections: [RouteGraph.RouteSection] = canonicalSections.map { section in
            RouteGraph.RouteSection(
                from: section.from, to: section.to,
                fromStationCode: section.fromN02StationCode,
                toStationCode: section.toN02StationCode,
                lineNames: section.lineNames ?? [],
                operatorNames: section.operatorNames ?? [])
        }
        guard !sections.isEmpty else { return nil }
        return RouteGraph.keyDigest(RouteGraph.templateKey(sections: sections))
    }

    private nonisolated static func routeCacheDigest(
        _ train: Train, country: String
    ) -> String? {
        let canonical = TrainValidation.normalizeExportTrain(
            train, country: country, stations: TrainValidation.StationTable.empty)
        let canonicalSections = canonical.routeSections ?? []
        let sections = canonicalSections.map { section in
            RouteGraph.RouteSection(
                from: section.from, to: section.to,
                fromStationCode: section.fromN02StationCode,
                toStationCode: section.toN02StationCode,
                lineNames: section.lineNames ?? [],
                operatorNames: section.operatorNames ?? [])
        }
        let policy = canonical.routePolicy
        let cacheTrain = RouteGraph.CacheKeyTrain(
            trainType: canonical.trainType ?? "", company: canonical.company ?? "",
            preferredLineNames: policy?.preferredLineNames ?? [],
            preferredOperatorNames: policy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: policy?.allowedInstitutionTypeCodes,
            institutionFilterMode: policy?.institutionFilterMode)
        guard let context = RouteGraph.solveContext(
            train: cacheTrain, routeSections: sections, country: country) else { return nil }
        return RouteGraph.keyDigest(context.cacheKey)
    }

    private nonisolated static func loadCached(
        _ trains: [Train], country: String
    ) -> (rides: [DrawnRide], missing: [Train]) {
        var rides: [DrawnRide] = []
        var missing: [Train] = []
        for train in trains {
            if let ride = readCached(train, country: country) {
                rides.append(ride)
            } else {
                missing.append(train)
            }
        }
        return (rides, missing)
    }

    /// The same answer, reading several journeys' cache files at once.
    ///
    /// One journey is one small file, and 201 of them read one after another
    /// is the whole of a warm load: measured over the shipped sample's 201
    /// parts — the same count and shape as the cache files — reading and
    /// decoding them takes **58.4 ms sequentially and 25.3 ms four at a time**
    /// (`ios/tools/bench`, release, Apple silicon), against 4.7 ms for all 201
    /// cache digests. The files are independent, so the sequence was the only
    /// thing making this slow.
    ///
    /// Four rather than "as many as there are", and the reason is memory
    /// rather than politeness: each task holds one file's bytes and its
    /// decoded coordinates at once, and a journey the length of a whole
    /// Shinkansen run is not small. Four keeps the flash busy — the measured
    /// step from four to eight is a further 5 ms — without holding two hundred
    /// decodes in the air.
    ///
    /// **The order is the sequential version's, not the scheduler's.** Results
    /// are placed by index and read back in order, so this returns exactly
    /// what the loop returned — including which journeys land in `missing`,
    /// and in what order. Appending as answers arrived would have made the
    /// order a property of which file the filesystem happened to finish first,
    /// and that order reaches the map: it is the order the overlays are added
    /// in, and therefore which line is drawn over which.
    private nonisolated static func loadCachedConcurrently(
        _ trains: [Train], country: String
    ) async -> (rides: [DrawnRide], missing: [Train]) {
        guard trains.count > 1 else { return loadCached(trains, country: country) }
        let interval = RailSignpost.data.begin("route.cacheRead")
        defer { RailSignpost.data.end("route.cacheRead", interval) }
        var found = [DrawnRide?](repeating: nil, count: trains.count)
        await withTaskGroup(of: (Int, DrawnRide?).self) { group in
            var next = 0
            func addNext() {
                guard next < trains.count else { return }
                let position = next
                let train = trains[position]
                next += 1
                group.addTask {
                    guard !Task.isCancelled else { return (position, nil) }
                    return (position, readCached(train, country: country))
                }
            }
            for _ in 0..<Swift.min(cacheReadWidth, trains.count) { addNext() }
            while let (position, ride) = await group.next() {
                found[position] = ride
                addNext()
            }
        }
        var rides: [DrawnRide] = []
        var missing: [Train] = []
        for (position, ride) in found.enumerated() {
            if let ride { rides.append(ride) } else { missing.append(trains[position]) }
        }
        return (rides, missing)
    }

    /// How many cache files are read at once. See ``loadCachedConcurrently``.
    private nonisolated static let cacheReadWidth = 4

    /// One journey's cached route, or `nil` if there is not a usable one.
    private nonisolated static func readCached(
        _ train: Train, country: String
    ) -> DrawnRide? {
        guard let digest = routeCacheDigest(train, country: country),
              let data = try? Data(contentsOf: cacheURL(country: country, digest: digest)),
              let cache = try? JSONDecoder().decode(RuntimeCache.self, from: data),
              cache.version == RouteGraph.routeSolverCacheVersion,
              cache.digest == digest
        else { return nil }
        let segments = cache.segments.compactMap { cached -> DrawnSegment? in
            let coordinates = cached.coordinates.compactMap(Coordinate.init(pair:))
            guard coordinates.count >= 2 else { return nil }
            return DrawnSegment(
                segmentIndex: cached.segmentIndex, from: cached.from,
                to: cached.to, coordinates: coordinates,
                country: country)
        }
        guard !segments.isEmpty else { return nil }
        return drawnRide(
            train,
            country: country,
            segments: segments,
            expectedSections: canonicalSections(train, country: country))
    }

    private nonisolated static func saveCache(
        _ ride: DrawnRide, train: Train, country: String
    ) throws {
        guard let digest = routeCacheDigest(train, country: country) else { return }
        let directory = cacheDirectory(country: country)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let cache = RuntimeCache(
            version: RouteGraph.routeSolverCacheVersion, digest: digest,
            segments: ride.segments.map {
                CachedSegment(
                    segmentIndex: $0.segmentIndex, from: $0.from, to: $0.to,
                    coordinates: $0.sourceCoordinates.map(\.pair))
            })
        try JSONEncoder().encode(cache).write(
            to: cacheURL(country: country, digest: digest), options: .atomic)
    }

    private nonisolated static func cacheURL(country: String, digest: String) -> URL {
        cacheDirectory(country: country).appending(path: "\(digest).json")
    }

    private nonisolated static func cacheDirectory(country: String) -> URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        return base.appending(path: "RailMap/Routes/\(country)", directoryHint: .isDirectory)
    }

    /// How many solved routes one region's cache may keep.
    ///
    /// Set well above any working set that ships — the largest bundled dataset
    /// is 201 journeys and a reader can hold all three Japanese ones at once —
    /// because what fills the remainder is not journeys but revisions of them.
    /// A digest covers a journey's sections and policy, so every edit writes a
    /// new file and orphans the old one, correct and never read again.
    private nonisolated static let routeCacheEntryBudget = 512

    private static var didSweepRouteCache = false

    /// Trim the route cache once per launch, after the load that filled it.
    ///
    /// Last rather than first, so the sweep never competes with solving, and
    /// once rather than per write, so a reader who reworks one journey twenty
    /// times in a session pays for the tidying on the next launch instead of
    /// twenty times over. A cancelled load never reaches here, so the flag is
    /// only ever spent on a load that finished.
    private static func sweepRouteCacheOnce() {
        guard !didSweepRouteCache else { return }
        didSweepRouteCache = true
        // Detached and low priority: nothing waits on the answer, and the
        // reader is already looking at their map by the time it runs.
        Task.detached(priority: .utility) {
            _ = sweepRouteCache()
        }
    }

    /// Trim each region's cache back to ``routeCacheEntryBudget``, oldest
    /// first, and answer how many entries went.
    ///
    /// Bounded by count and not by age on purpose. An entry is rewritten only
    /// when its route is solved again, so a sample loaded once and never
    /// edited keeps its original dates for as long as the install lasts; an
    /// age rule would eventually delete all 201 of the Japanese sample's
    /// routes and make the next launch re-solve them, which is exactly the
    /// wait this cache exists to remove. Oldest-first still evicts a
    /// superseded revision before the replacement that outdates it, and an
    /// entry evicted while still live is solved again and rewritten with a
    /// fresh date, which moves it out of the firing line by itself.
    ///
    /// Everything it can reach is derived: only `RailMap/Routes/<code>` under
    /// the caches directory, only for the five region codes this app knows,
    /// only regular files directly inside one, and only those named `*.json`.
    /// Each is a file `solveMissing` builds again from the bundled network, so
    /// the worst a mistake here can cost is a re-solve — the same cost iOS
    /// imposes whenever it purges the caches directory on its own.
    ///
    /// The count is returned rather than reported because nothing in this app
    /// logs; it is there so a sweep that removes nothing, or everything, is
    /// visible to whoever next has a debugger on this.
    private nonisolated static func sweepRouteCache() -> Int {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        var removed = 0
        for region in Region.ordered {
            guard let contents = try? manager.contentsOfDirectory(
                at: cacheDirectory(country: region.code),
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            else { continue }
            let entries = contents.compactMap { url -> (url: URL, written: Date)? in
                guard url.pathExtension == "json",
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true
                else { return nil }
                return (url, values.contentModificationDate ?? .distantPast)
            }
            guard entries.count > routeCacheEntryBudget else { continue }
            let doomed = entries
                .sorted { $0.written < $1.written }
                .prefix(entries.count - routeCacheEntryBudget)
            for entry in doomed {
                // A failure needs no handling: the entry either went or it did
                // not, and either way the next load re-solves what is missing.
                guard (try? manager.removeItem(at: entry.url)) != nil else { continue }
                removed += 1
            }
        }
        return removed
    }

    private nonisolated static func routeSectionBoundarySharesExplicitStop(
        _ previous: RouteSection, _ next: RouteSection
    ) -> Bool {
        let previousCode = previous.toN02StationCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextCode = next.fromN02StationCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !previousCode.isEmpty, !nextCode.isEmpty { return previousCode == nextCode }
        let previousName = Stations.normalizeStationName(previous.to ?? "")
        let nextName = Stations.normalizeStationName(next.from ?? "")
        return !previousName.isEmpty && previousName == nextName
    }

    private struct Part: Decodable {
        let train: Train
        let route: CachedRoute
    }

    private struct CachedRoute: Decodable {
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let properties: Properties?
        let geometry: Geometry
    }

    private struct Properties: Decodable {
        let routeTemplateKey: String?
        let segmentIndex: Int?
        let from: String?
        let to: String?
        private enum CodingKeys: String, CodingKey {
            case routeTemplateKey = "route_template_key"
            case segmentIndex = "segment_index"
            case from, to
        }
    }

    private struct RuntimeCache: Codable {
        let version: String
        let digest: String
        let segments: [CachedSegment]
    }

    private struct CachedSegment: Codable {
        let segmentIndex: Int
        let from: String?
        let to: String?
        let coordinates: [[Double]]
    }

    private struct Geometry: Decodable {
        let strokes: [[Coordinate]]

        private enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "LineString":
                let raw = try container.decode([[Double]].self, forKey: .coordinates)
                strokes = [Self.coordinates(raw)]
            case "MultiLineString":
                let raw = try container.decode([[[Double]]].self, forKey: .coordinates)
                strokes = raw.map(Self.coordinates)
            default:
                strokes = []
            }
        }

        private static func coordinates(_ raw: [[Double]]) -> [Coordinate] {
            raw.compactMap { pair in
                guard pair.count >= 2, pair[0].isFinite, pair[1].isFinite else { return nil }
                return Coordinate(lon: pair[0], lat: pair[1])
            }
        }
    }

    enum LoadError: LocalizedError {
        case missingManifest(String)
        case missingPart(String, String)
        case missingSolverResources(String)

        var errorDescription: String? {
            switch self {
            case .missingManifest(let dataset):
                "\(dataset)/manifest.json is missing from the app bundle."
            case .missingPart(let dataset, let name):
                "\(dataset)/\(name).json is missing from the app bundle."
            case .missingSolverResources(let country):
                "Runtime solver resources for \(country) are missing from the app bundle."
            }
        }
    }
}

/// Which precomputed part holds which journey, built once per dataset.
///
/// The scan it replaces was paid per journey rather than per dataset: with a
/// cold route cache, every train the load could not answer for reopened and
/// re-decoded all 201 parts of the Japanese sample to discover that 200 of
/// them belonged to somebody else.
///
/// The FIRST ask still opens every part, because the manifest names the parts
/// and nothing else. It is not extended with an id index here: that file is
/// written by the JavaScript precompute pipeline in the main fork and read by
/// both apps, so its shape is settled somewhere this repository cannot see.
///
/// An `actor` rather than a lock, for the reason ``EdgeIndexCache`` is one:
/// two regions can be decoding at the same time, and the second must wait on
/// the first build instead of starting a second one beside it.
private actor DatasetPartIndex {
    static let shared = DatasetPartIndex()

    /// One part, and where it sat in the manifest.
    ///
    /// The position is carried so the rides a dataset answers for come back in
    /// manifest order on every run. Dictionary iteration order is not stable
    /// between launches, and this order is the order the map draws in.
    struct PartRef: Sendable {
        let name: String
        let position: Int
    }

    private var indexes: [String: [String: [PartRef]]] = [:]
    private var inFlight: [String: Task<[String: [PartRef]], Error>] = [:]

    /// The index for one dataset, building it if this is the first ask.
    func parts(in dataset: String) async throws -> [String: [PartRef]] {
        if let ready = indexes[dataset] { return ready }
        if let running = inFlight[dataset] { return try await running.value }

        let task = Task.detached(priority: .userInitiated) {
            try Self.build(dataset: dataset)
        }
        inFlight[dataset] = task
        defer { inFlight[dataset] = nil }
        // Detached, so a load cancelled halfway through the scan does not take
        // it down and leave the next load to start it over. The scan is worth
        // finishing: it is the only thing that ever has to read these files.
        let built = try await task.value
        indexes[dataset] = built
        return built
    }

    /// Read every part once, for its train id and nothing else.
    ///
    /// ``PartIdentity`` deliberately cannot see the route: the coordinate
    /// arrays are nearly all of a part's bytes and the scan needs none of
    /// them, so what would have been a full geometry decode is now a parse
    /// that keeps one string.
    private nonisolated static func build(dataset: String) throws -> [String: [PartRef]] {
        guard let manifestURL = Bundle.main.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: dataset
        ) else { throw RiddenRouteStore.LoadError.missingManifest(dataset) }

        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: manifestURL)
        )
        var index: [String: [PartRef]] = [:]
        index.reserveCapacity(manifest.parts.count)
        for (position, name) in manifest.parts.enumerated() {
            guard let partURL = Bundle.main.url(
                forResource: name,
                withExtension: "json",
                subdirectory: dataset
            ) else { throw RiddenRouteStore.LoadError.missingPart(dataset, name) }
            let identity = try JSONDecoder().decode(
                PartIdentity.self, from: Data(contentsOf: partURL))
            // Appended rather than assigned. The datasets that ship carry one
            // part per journey, but a dataset that ever carried two for the
            // same id would have had both searched before, and dropping one
            // here would silently stop drawing a route that used to draw.
            index[identity.train.id, default: []].append(
                PartRef(name: name, position: position))
        }
        return index
    }

    private struct Manifest: Decodable {
        let parts: [String]
    }

    private struct PartIdentity: Decodable {
        let train: TrainIdentity

        struct TrainIdentity: Decodable {
            let id: String
        }
    }
}
