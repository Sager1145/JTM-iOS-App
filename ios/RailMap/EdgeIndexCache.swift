import Foundation
import RailCore

/// The N02 edge index, built once per region and then shared.
///
/// Building one means parsing the whole of `rail-sections*.json` and walking
/// every edge in it — seconds, not milliseconds, which is why the statistics
/// screen has a `readingNetwork` stage to show for it. The network itself
/// never changes while the app is running, so building it more than once per
/// region is pure waste, and there are now two callers that want the same
/// answer:
///
/// - `MileageStatisticsStore`, which rebuilds its numbers whenever the rides
///   change — and since the shell's route key started covering the whole
///   record rather than ids and visibility, that is every edit, not only an
///   add or a delete. Re-reading the network on each one would put seconds
///   between saving a journey and seeing its statistics move.
/// - the ridden-line category filter, which classifies a drawn segment by
///   dominant km over these same edges.
///
/// An `actor` rather than a lock: the build is the expensive part and it has
/// to be joinable, so two callers asking for the same region at once wait on
/// one build instead of starting two.
actor EdgeIndexCache {
    static let shared = EdgeIndexCache()

    private var indexes: [String: Statistics.EdgeIndex] = [:]
    private var inFlight: [String: Task<Statistics.EdgeIndex, Error>] = [:]

    /// The index for one region, building it if this is the first ask.
    func index(country: String) async throws -> Statistics.EdgeIndex {
        if let ready = indexes[country] { return ready }
        // Joined rather than started again: the second caller of a region
        // whose build is already running is exactly the case this exists for.
        if let running = inFlight[country] { return try await running.value }

        let task = Task.detached(priority: .userInitiated) {
            try Self.build(country: country)
        }
        inFlight[country] = task
        // Detached, so a caller that is cancelled while waiting does not take
        // the build down with it — the other caller is still waiting on it.
        //
        // The in-flight entry is cleared by whoever the build finishes for,
        // and only if it is still THIS task. It used to be cleared in a
        // `defer` on this function, which runs when the *awaiting caller*
        // leaves — so a caller cancelled mid-wait removed a build that was
        // still running, and the next ask started a second one over the same
        // 12 MB of Japanese sections. Cancelling one waiter must not cost the
        // next one seconds.
        do {
            let built = try await task.value
            if inFlight[country] == task { inFlight[country] = nil }
            indexes[country] = built
            return built
        } catch {
            if inFlight[country] == task { inFlight[country] = nil }
            throw error
        }
    }

    /// One index covering several regions.
    ///
    /// The all-regions statistics scope needs a single index: coverage is a
    /// fraction of a denominator, and five denominators is five answers rather
    /// than one. The networks are geographically disjoint, so laying the
    /// finished indexes side by side is arithmetic rather than a judgement —
    /// each region's masks were already decided by its OWN country's rules
    /// when its index was built, and nothing here re-decides them.
    ///
    /// The one thing that is not arithmetic is a line NAME. The packages share
    /// exactly one — 海岸線, which is a Kobe subway line in Japan and a
    /// Taiwanese main line — and a breakdown keyed on the bare name would fuse
    /// the two into one row whose kilometres belong to neither. Any name that
    /// arrives from more than one region is therefore qualified with its
    /// region, and names that are unique are left exactly as they are so the
    /// single-region case is untouched.
    ///
    /// ## The regions are built concurrently
    ///
    /// They are merged in the order they were asked for, but they are BUILT at
    /// the same time.
    ///
    /// The loop this replaces awaited one region before starting the next, so
    /// the first "全部" statistics of a launch paid five reads and five index
    /// builds back to back — for five files that share nothing and can be read
    /// at the same time. Ordering is restored explicitly afterwards because
    /// `merge` is order-sensitive: it decides which region's spelling of a
    /// shared line name comes first, and the edge offsets it lays down have to
    /// match the arrays they index into.
    ///
    /// Unbounded over five is bounded in fact rather than by a semaphore:
    /// Japan is 12.1 MB of sections and the other four are 1.7 MB together, so
    /// the peak is Japan's decode either way. A sixth region of Japan's size
    /// would be the moment to add a limit, and would be a change to this
    /// comment as much as to the code.
    func merged(countries: [String]) async throws -> Statistics.EdgeIndex {
        guard countries.count > 1 else {
            // One region needs no group, and none at all still answers what
            // the sequential version answered: `merge` of nothing.
            guard let only = countries.first else { return Self.merge([]) }
            return Self.merge([(only, try await index(country: only))])
        }
        var byPosition: [Int: Statistics.EdgeIndex] = [:]
        try await withThrowingTaskGroup(
            of: (Int, Statistics.EdgeIndex).self
        ) { group in
            for (position, country) in countries.enumerated() {
                group.addTask { (position, try await self.index(country: country)) }
            }
            for try await (position, built) in group { byPosition[position] = built }
        }
        return Self.merge(countries.enumerated().compactMap { position, country in
            byPosition[position].map { (country, $0) }
        })
    }

    nonisolated static func merge(
        _ parts: [(country: String, index: Statistics.EdgeIndex)]
    ) -> Statistics.EdgeIndex {
        if parts.count == 1 { return parts[0].index }

        // Which line names arrive from more than one region.
        var seenIn: [String: Set<String>] = [:]
        for part in parts {
            for name in part.index.lineTotByCat.keys where !name.isEmpty {
                seenIn[name, default: []].insert(part.country)
            }
        }
        let shared = Set(seenIn.filter { $0.value.count > 1 }.keys)
        func qualified(_ name: String, _ country: String) -> String {
            guard !name.isEmpty, shared.contains(name) else { return name }
            return "\(name)（\(country.uppercased())）"
        }

        var map: [String: Int] = [:]
        var km: [Double] = []
        var mask: [Int] = []
        var lineName: [String] = []
        var lineMask: [Int] = []
        var totalKm = 0.0
        var totalsByMask: [Int: Double] = [:]
        var lineTotByCat = Statistics.OrderedDictionary<String, [Int: Double]>()
        var lineOperator = Statistics.OrderedDictionary<String, String>()

        for part in parts {
            let offset = km.count
            km += part.index.km
            mask += part.index.mask
            lineName += part.index.lineName.map { qualified($0, part.country) }
            lineMask += part.index.lineMask
            totalKm += part.index.totalKm
            // Edge keys are built from coordinates, so two regions cannot
            // produce the same one — but `merging` states what happens rather
            // than trusting that, and keeping the FIRST matches the order the
            // regions were asked for.
            map.merge(part.index.map.mapValues { $0 + offset }) { first, _ in first }
            for (bucket, value) in part.index.totalsByMask {
                totalsByMask[bucket, default: 0] += value
            }
            for (name, byCategory) in part.index.lineTotByCat.pairs {
                let key = qualified(name, part.country)
                var merged = lineTotByCat[key] ?? [:]
                for (bucket, value) in byCategory { merged[bucket, default: 0] += value }
                lineTotByCat[key] = merged
            }
            for (name, owner) in part.index.lineOperator.pairs {
                let key = qualified(name, part.country)
                if lineOperator[key] == nil { lineOperator[key] = owner }
            }
        }

        return Statistics.EdgeIndex(
            map: map, km: km, mask: mask, lineName: lineName, lineMask: lineMask,
            totalKm: totalKm, totalsByMask: totalsByMask,
            lineTotByCat: lineTotByCat, lineOperator: lineOperator)
    }

    /// The index for one region if it is already built, without building one.
    ///
    /// For callers that cannot wait — the render path, which must answer
    /// "is this segment's category hidden?" synchronously and treats a missing
    /// index as "undetermined, stays visible", exactly as the web app does.
    func ready(country: String) -> Statistics.EdgeIndex? { indexes[country] }

    private nonisolated static func build(
        country: String
    ) throws -> Statistics.EdgeIndex {
        let interval = RailSignpost.data.begin("data.edgeIndex.build")
        defer { RailSignpost.data.end("data.edgeIndex.build", interval) }
        guard let url = Bundle.main.url(
            forResource: Region.countrySuffixed("rail-sections", country: country),
            withExtension: "json")
        else { throw MissingSections(country: country) }
        let sections = try Statistics.SectionFeatureCollection.load(contentsOf: url).sections
        return Statistics.buildEdgeIndex(sections: sections, country: country)
    }

    struct MissingSections: LocalizedError {
        let country: String
        var errorDescription: String? {
            "Statistics rail sections for \(country) are missing from the app bundle."
        }
    }
}
