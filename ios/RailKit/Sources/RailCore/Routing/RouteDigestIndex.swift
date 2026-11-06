import CryptoKit
import Foundation

/// The persisted train → route-cache digest map that lets a warm load find a
/// journey's cached route without running timetable enrichment again.
///
/// A route-cache file is named by a digest of the *enriched* canonical train,
/// so reading it used to require the timetable match for every dated Japanese
/// journey first. This index remembers, per journey content and per every
/// input that can change the enriched result or its digest, which digest that
/// produced and which canonical sections the drawn ride expects. Any change to
/// one of those inputs produces a different key and therefore a miss; a miss
/// falls back to enrichment and records the answer again. Entries are never
/// trusted across inputs, only looked up by exact key.
public struct RouteDigestIndex: Codable, Sendable, Equatable {
    public static let schema = "route-digest-index-v1"

    /// Everything other than the train that the enriched canonical input and
    /// its digest depend on. Each value is an opaque identity string.
    public struct Inputs: Sendable, Equatable {
        /// Scope home code the cache directory and normalisation rules use.
        public var country: String
        /// The resource revision the route-cache file must carry (rail revision
        /// of the train's scope, plus the timetable revision for Japan).
        public var resourceRevision: String
        /// The rail and timetable revisions the timetable matcher keys on.
        public var timetableEvidenceRevision: String
        public var solverCacheVersion: String
        public var drawnCacheVersion: String
        public var resolutionSemantics: String
        /// Canonical history revision set of the train's graph regions.
        public var historyRevision: String
        /// Registry phase and bundled-file identity of each graph region.
        public var registry: String
        /// Identity of the running code (loaded image UUIDs), so a build that
        /// changes normalisation or matching never reuses an older answer.
        public var build: String

        public init(
            country: String, resourceRevision: String, timetableEvidenceRevision: String,
            solverCacheVersion: String, drawnCacheVersion: String, resolutionSemantics: String,
            historyRevision: String, registry: String, build: String
        ) {
            self.country = country
            self.resourceRevision = resourceRevision
            self.timetableEvidenceRevision = timetableEvidenceRevision
            self.solverCacheVersion = solverCacheVersion
            self.drawnCacheVersion = drawnCacheVersion
            self.resolutionSemantics = resolutionSemantics
            self.historyRevision = historyRevision
            self.registry = registry
            self.build = build
        }

        fileprivate var fields: [String] {
            [country, resourceRevision, timetableEvidenceRevision, solverCacheVersion,
             drawnCacheVersion, resolutionSemantics, historyRevision, registry, build]
        }
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var digest: String
        /// `canonicalSections(canonical)` of the enriched train, which the
        /// drawn ride is mapped against.
        public var expectedSections: [RouteSection]
        /// Logical access time; larger is more recent.
        public var used: UInt64

        public init(digest: String, expectedSections: [RouteSection], used: UInt64 = 0) {
            self.digest = digest
            self.expectedSections = expectedSections
            self.used = used
        }
    }

    public private(set) var schema: String
    public private(set) var entries: [String: Entry]
    public private(set) var clock: UInt64

    public init() {
        schema = Self.schema
        entries = [:]
        clock = 0
    }

    /// The lookup key for one train under `inputs`, or `nil` when the train
    /// cannot be encoded. The train is encoded with sorted keys, so the same
    /// content always gives the same key; every field participates, so any
    /// edit is a miss rather than a stale hit.
    public static func key(train: Train, inputs: Inputs) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let trainBytes = try? encoder.encode(train),
              let fieldBytes = try? encoder.encode([schema] + inputs.fields)
        else { return nil }
        var hasher = SHA256()
        hasher.update(data: fieldBytes)
        hasher.update(data: Data([0]))
        hasher.update(data: trainBytes)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `sections` survive the persisted encoding unchanged. An entry
    /// whose sections would decode differently is never recorded, so a hit
    /// always hands back exactly what enrichment produced.
    public static func roundTrips(_ sections: [RouteSection]) -> Bool {
        guard let data = try? JSONEncoder().encode(sections),
              let decoded = try? JSONDecoder().decode([RouteSection].self, from: data)
        else { return false }
        return decoded == sections
    }

    /// The entry for `key`, marking it most recently used.
    public mutating func lookup(_ key: String) -> Entry? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.used = clock
        entries[key] = entry
        return entry
    }

    /// Records `digest` and `expectedSections` for `key`. Answers whether the
    /// stored content changed (a refresh of the same answer only touches its
    /// access time and needs no write).
    @discardableResult
    public mutating func record(_ key: String, digest: String, expectedSections: [RouteSection]) -> Bool {
        clock &+= 1
        if var existing = entries[key], existing.digest == digest,
           existing.expectedSections == expectedSections {
            existing.used = clock
            entries[key] = existing
            return false
        }
        entries[key] = Entry(digest: digest, expectedSections: expectedSections, used: clock)
        return true
    }

    /// Keeps at most `limit` entries, dropping the least recently used.
    public mutating func trim(to limit: Int) {
        guard entries.count > max(0, limit) else { return }
        let doomed = entries
            .sorted { $0.value.used == $1.value.used ? $0.key < $1.key : $0.value.used < $1.value.used }
            .prefix(entries.count - max(0, limit))
        for (key, _) in doomed { entries.removeValue(forKey: key) }
    }

    /// Decodes a persisted index; anything unreadable or of another schema is
    /// an empty index, never a partial one.
    public static func decoded(from data: Data) -> RouteDigestIndex {
        guard let index = try? JSONDecoder().decode(RouteDigestIndex.self, from: data),
              index.schema == schema
        else { return RouteDigestIndex() }
        return index
    }
}

/// Which route-cache files the per-region sweep removes.
public enum RouteCacheSweep {
    public struct Entry: Sendable, Equatable {
        /// File name without the `.json` extension: the route digest.
        public var digest: String
        public var written: Date

        public init(digest: String, written: Date) {
            self.digest = digest
            self.written = written
        }
    }

    /// The oldest entries over `budget`, never one whose digest is in
    /// `protected` (the digests of the journeys currently loaded). Protected
    /// entries count toward the budget, so a region whose live set alone
    /// exceeds the budget keeps all of it and drops only unprotected files.
    public static func victims(
        _ entries: [Entry], budget: Int, protected: Set<String>
    ) -> [Entry] {
        let budget = max(0, budget)
        guard entries.count > budget else { return [] }
        let excess = entries.count - budget
        return Array(entries
            .filter { !protected.contains($0.digest) }
            .sorted { $0.written == $1.written ? $0.digest < $1.digest : $0.written < $1.written }
            .prefix(excess))
    }
}
