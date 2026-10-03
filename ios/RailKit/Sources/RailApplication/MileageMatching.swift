import RailCore

/// Matches an ordered journey snapshot against one already-loaded edge index.
/// The caller owns the index identity, cache lifetime and result publication.
public enum MileageMatching {
    public struct Segment: Sendable {
        /// Canonical WGS84, before any MapKit datum conversion or simplification.
        public let sourceCoordinates: [Coordinate]
        public let segmentIndex: Int
        public let from: String?
        public let to: String?

        public init(sourceCoordinates: [Coordinate], segmentIndex: Int, from: String?, to: String?) {
            self.sourceCoordinates = sourceCoordinates
            self.segmentIndex = segmentIndex
            self.from = from
            self.to = to
        }
    }

    public struct Journey: Sendable {
        /// Date must be the same normalized bucket used in the caller's fingerprint.
        public let train: Statistics.Train
        public let entryDigest: Int
        public let segments: [Segment]
        public let routeConfirmation: RouteConfirmation?
        public let fullDistanceKnown: Bool

        public init(train: Statistics.Train, entryDigest: Int, segments: [Segment],
                    routeConfirmation: RouteConfirmation? = nil, fullDistanceKnown: Bool = true) {
            self.train = train
            self.entryDigest = entryDigest
            self.segments = segments
            self.routeConfirmation = routeConfirmation
            self.fullDistanceKnown = fullDistanceKnown
        }
    }

    public struct CachedEntry: Sendable {
        public let digest: Int
        public let entry: Statistics.TrainEntry

        public init(digest: Int, entry: Statistics.TrainEntry) {
            self.digest = digest
            self.entry = entry
        }
    }

    public struct Result: Sendable {
        public let trains: [Statistics.Train]
        public let entries: [Statistics.TrainEntry]
        /// Rebuilt from this snapshot only, so deleted journeys leave the cache.
        public let cache: [String: CachedEntry]
    }

    /// Cache entries must belong to `index`; a change of index invalidates all
    /// entries even if their journey digests have not moved. Order is preserved
    /// because Core's deduplicated union has insertion-order numeric semantics.
    public static func match(
        journeys: [Journey], index: Statistics.EdgeIndex,
        cache: [String: CachedEntry], report: @Sendable (Int) -> Void = { _ in }
    ) throws -> Result {
        var trains: [Statistics.Train] = []
        var entries: [Statistics.TrainEntry] = []
        var fresh: [String: CachedEntry] = [:]
        trains.reserveCapacity(journeys.count)
        entries.reserveCapacity(journeys.count)
        fresh.reserveCapacity(journeys.count)

        for (position, journey) in journeys.enumerated() {
            try Task.checkCancellation()
            let train = journey.train
            trains.append(train)
            if journey.routeConfirmation == .pending {
                // Cached or stale drawn geometry cannot attest a route that
                // the reader has explicitly left unconfirmed. Do not cache
                // this placeholder as a measured zero-distance journey.
                entries.append(Statistics.TrainEntry(distanceIsKnown: false))
            } else if let cached = cache[train.id], cached.digest == journey.entryDigest {
                var entry = cached.entry
                entry.distanceIsKnown = entry.distanceIsKnown && journey.fullDistanceKnown
                entry.partialDistanceIsProven = entry.partialDistanceIsProven
                    || (!journey.fullDistanceKnown && !entry.edges.isEmpty)
                entries.append(entry)
                fresh[train.id] = CachedEntry(digest: cached.digest, entry: entry)
            } else {
                let features = journey.segments.map { segment in
                    Statistics.RouteFeature(
                        lines: [segment.sourceCoordinates], hasGeometry: true,
                        rideSegment: Statistics.isRideSegment(train.stops, segmentIndex: segment.segmentIndex),
                        from: segment.from, to: segment.to)
                }
                var entry = Statistics.collectTrainStatsEntry(
                    features: features, index: index, rideDate: train.date)
                entry.distanceIsKnown = journey.fullDistanceKnown
                entry.partialDistanceIsProven = !journey.fullDistanceKnown && !entry.edges.isEmpty
                entries.append(entry)
                fresh[train.id] = CachedEntry(digest: journey.entryDigest, entry: entry)
            }
            // Preserve the store's progress cadence, including a final report
            // when the last block has exactly 25 journeys.
            if position % 25 == 24 { report(position + 1) }
        }
        report(journeys.count)
        return Result(trains: trains, entries: entries, cache: fresh)
    }
}
