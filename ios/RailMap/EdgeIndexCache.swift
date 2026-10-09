import Foundation
import RailCore

/// Shares one completed statistics index and coalesces active country builds.
/// Evicted countries rebuild on demand; active callers retain their own value.
actor EdgeIndexCache {
    static let shared = EdgeIndexCache()

    private typealias BuiltIndex = (index: Statistics.EdgeIndex, denominatorEdgeCount: Int)
    private enum CacheKey: Equatable {
        case country(String)
        case merged([String], String)
        case scoped([String], String)
    }
    private var completed: (key: CacheKey, value: BuiltIndex)?
    private var inFlight: [String: Task<BuiltIndex, Error>] = [:]
    // Independent of route and display admission: country construction awaits
    // DisplayNetworkCache while holding this permit. Merges acquire it only
    // after fetching their components, so they never await a nested index build.
    private let buildLimiter = RouteSolveLimiter(limit: 1)

    private func cached(_ key: CacheKey) -> BuiltIndex? {
        completed?.key == key ? completed?.value : nil
    }

    private func releaseCompleted() { completed = nil }

    private func retain(_ value: BuiltIndex, key: CacheKey) {
        completed = (key, value)
    }

    private nonisolated static func countryCacheKey(_ country: String) -> String {
        "\(country)|attribution-policy-v2"
    }

    func index(country: String) async throws -> Statistics.EdgeIndex {
        try await countryIndex(country).index
    }

    private func countryIndex(_ country: String) async throws -> BuiltIndex {
        let key = Self.countryCacheKey(country)
        if let ready = cached(.country(key)) { return ready }
        if let running = inFlight[key] { return try await running.value }
        let limiter = buildLimiter
        let task = Task.detached(priority: .userInitiated) { () async throws -> BuiltIndex in
            try await limiter.withPermit {
                await self.releaseCompleted()
                let n02 = try Self.build(country: country)
                let count = n02.km.count
                let index: Statistics.EdgeIndex
                if let network = try? await DisplayNetworkCache.shared.network(country: country) {
                    index = Self.appendingVector(to: n02, network: network)
                } else {
                    index = n02
                }
                let built = (index: index, denominatorEdgeCount: count)
                // Publish under admission; waiters must not restore an older
                // country after its replacement has started allocating.
                await self.retain(built, key: .country(key))
                return built
            }
        }
        inFlight[key] = task
        do {
            let built = try await task.value
            if inFlight[key] == task { inFlight[key] = nil }
            return built
        } catch {
            if inFlight[key] == task { inFlight[key] = nil }
            throw error
        }
    }

    /// Preserve the caller's order, including duplicate countries and line-name
    /// qualification. Components are fetched before admitting the pure merge.
    func merged(countries: [String]) async throws -> Statistics.EdgeIndex {
        guard countries.count > 1 else {
            guard let only = countries.first else { return Self.merge([]) }
            return Self.merge([(only, try await index(country: only))])
        }
        let key = CacheKey.merged(countries, "attribution-policy-v2")
        if let ready = cached(key) { return ready.index }
        var parts: [(country: String, index: Statistics.EdgeIndex)] = []
        for country in countries {
            parts.append((country, try await index(country: country)))
        }
        return try await mergedResult(parts, key: key)
    }

    private func mergedResult(
        _ parts: [(country: String, index: Statistics.EdgeIndex)], key: CacheKey
    ) async throws -> Statistics.EdgeIndex {
        try await buildLimiter.withPermit {
            if let ready = await self.cached(key) { return ready.index }
            await self.releaseCompleted()
            let result = Self.merge(parts)
            await self.retain((result, 0), key: key)
            return result
        }
    }

    /// The N02 denominator count travels with its country result. A country
    /// eviction cannot make Japan clipping count appended display-only edges.
    func scoped(
        countries: [String], japanLeaves: Set<JapanAreaLeaf>?
    ) async throws -> Statistics.EdgeIndex {
        guard let japanLeaves else { return try await merged(countries: countries) }
        let leavesKey = japanLeaves.map(\.rawValue).sorted().joined(separator: ",")
        let key = CacheKey.scoped(countries, leavesKey)
        if let ready = cached(key) { return ready.index }
        let japan = try await restrictedJapan(to: japanLeaves)
        var parts: [(country: String, index: Statistics.EdgeIndex)] = []
        for country in countries {
            parts.append((country, country == Region.jp.code ? japan : try await index(country: country)))
        }
        return try await mergedResult(parts, key: key)
    }

    // End the full-country result's lifetime before fetching other regions.
    // The clipped value retains only the immutable arrays it actually shares.
    private func restrictedJapan(to leaves: Set<JapanAreaLeaf>) async throws -> Statistics.EdgeIndex {
        let built = try await countryIndex(Region.jp.code)
        return try await buildLimiter.withPermit {
            await self.releaseCompleted()
            return JapanAreaGrid.restricting(
                built.index, country: Region.jp.code, to: leaves, grid: .shared,
                denominatorEdgeCount: built.denominatorEdgeCount)
        }
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

        var map: [Statistics.EdgeKey: Int] = [:]
        var km: [Double] = []
        var mask: [Int] = []
        var lineName: [String] = []
        var lineMask: [Int] = []
        var temporalKind: [RouteGraph.TemporalKind] = []
        var validFrom: [String?] = []
        var validTo: [String?] = []
        var historyId: [String?] = []
        var currentNetwork: [Bool] = []
        var variants: [Statistics.EdgeKey: [Int]] = [:]
        // Allocate final parallel buffers once. Repeated growth briefly keeps
        // both old and replacement buffers beside all country components.
        let edgeCount = parts.reduce(0) { $0 + $1.index.km.count }
        km.reserveCapacity(edgeCount)
        mask.reserveCapacity(parts.reduce(0) { $0 + $1.index.mask.count })
        lineName.reserveCapacity(parts.reduce(0) { $0 + $1.index.lineName.count })
        lineMask.reserveCapacity(parts.reduce(0) { $0 + $1.index.lineMask.count })
        temporalKind.reserveCapacity(edgeCount)
        validFrom.reserveCapacity(edgeCount)
        validTo.reserveCapacity(edgeCount)
        historyId.reserveCapacity(edgeCount)
        currentNetwork.reserveCapacity(edgeCount)
        map.reserveCapacity(parts.reduce(0) { $0 + $1.index.map.count })
        var totalKm = 0.0
        var totalsByMask: [Int: Double] = [:]
        var lineTotByCat = Statistics.OrderedDictionary<String, [Int: Double]>()
        var lineOperator = Statistics.OrderedDictionary<String, String>()

        for part in parts {
            let offset = km.count
            km += part.index.km
            mask += part.index.mask
            for name in part.index.lineName { lineName.append(qualified(name, part.country)) }
            lineMask += part.index.lineMask
            temporalKind += Self.padded(part.index.temporalKind, count: part.index.km.count, fill: .current)
            validFrom += Self.padded(part.index.validFrom, count: part.index.km.count, fill: nil)
            validTo += Self.padded(part.index.validTo, count: part.index.km.count, fill: nil)
            historyId += Self.padded(part.index.historyId, count: part.index.km.count, fill: nil)
            currentNetwork += Self.padded(part.index.currentNetwork, count: part.index.km.count, fill: true)
            for (key, ids) in part.index.variants {
                variants[key, default: []].append(contentsOf: ids.map { $0 + offset })
            }
            totalKm += part.index.totalKm
            // Edge keys are built from coordinates, so two regions cannot
            // produce the same one — but `merging` states what happens rather
            // than trusting that, and keeping the FIRST matches the order the
            // regions were asked for.
            // Offset directly into the destination instead of allocating a
            // complete temporary dictionary. Caller order still wins collisions.
            for (key, id) in part.index.map where map[key] == nil {
                map[key] = id + offset
            }
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
            lineTotByCat: lineTotByCat, lineOperator: lineOperator,
            temporalKind: temporalKind, validFrom: validFrom, validTo: validTo,
            historyId: historyId, currentNetwork: currentNetwork, variants: variants)
    }

    private nonisolated static func padded<T>(
        _ values: [T], count: Int, fill: T
    ) -> [T] {
        if values.count == count { return values }
        if values.count > count { return Array(values.prefix(count)) }
        return values + Array(repeating: fill, count: count - values.count)
    }

    /// The index for one region if it is already built, without building one.
    ///
    /// For callers that cannot wait — the render path, which must answer
    /// "is this segment's category hidden?" synchronously and treats a missing
    /// index as "undetermined, stays visible", exactly as the web app does.
    func ready(country: String) -> Statistics.EdgeIndex? {
        cached(.country(Self.countryCacheKey(country)))?.index
    }

    private nonisolated static func build(
        country: String
    ) throws -> Statistics.EdgeIndex {
        let interval = RailSignpost.data.begin("data.edgeIndex.build")
        defer { RailSignpost.data.end("data.edgeIndex.build", interval) }
        guard let url = Bundle.main.url(
            forResource: Region.countrySuffixed("rail-sections", country: country),
            withExtension: "json")
        else { throw MissingSections(country: country) }
        let loaded = try Statistics.SectionFeatureCollection.load(contentsOf: url).sections
        let overlay: RailHistoryOverlay?
        if let historyURL = Bundle.main.url(
            forResource: Region.countrySuffixed("rail-history", country: country),
            withExtension: "json")
        {
            overlay = try? RailHistoryOverlay.load(from: historyURL)
        } else {
            overlay = nil
        }
        let sections = Statistics.applyingHistoryOverlay(overlay, to: loaded)
        return Statistics.buildEdgeIndex(sections: sections, country: country)
    }

    /// The vector package's own track, appended behind N02 so a ride drawn on
    /// display geometry is still measured.
    ///
    /// **N02 stays the authority.** It is inserted first and it wins every key
    /// collision, it alone defines the denominator (`totalKm`, `totalsByMask`,
    /// `lineTotByCat` are left exactly as `buildEdgeIndex` computed them), and
    /// a vector edge does not classify itself — it inherits the mask of the
    /// N02 line it belongs to, matched by operator and name. There is one
    /// classification authority in this app and it is `classifySectionMask`.
    ///
    /// ## Why the fallback has to exist
    ///
    /// A ride carries ONE geometry and two things read it. The map draws it,
    /// and `RiddenRouteStore` re-draws a solved hop against the display line so
    /// it shares the network's centreline; the statistics match it, and they
    /// match against N02. Those are not the same geometry: the package cuts
    /// station intervals out of N02 but grooms them, welds junction anchors,
    /// and — at 東京駅 — draws both Shinkansen on surveyed OpenStreetMap track
    /// that N02 does not carry at all. Measured over the Japanese package,
    /// 11 089 of its 375 801 drawn edges (673 km) are absent from N02.
    ///
    /// Before this, every one of those hops matched nothing and its whole
    /// distance was filed as the unattributable remainder: canonicalising the
    /// sample's rides took `unmatchedKm` from 3.3 km to 95.3 km, which is what
    /// this index is here to make impossible.
    ///
    /// ## What it costs
    ///
    /// A section ridden once on N02 vertices and once on drawn vertices holds
    /// two edge ids, so the deduped union counts it twice. The whole surface
    /// that can happen over is those 673 km, against a denominator two orders
    /// of magnitude larger — and the alternative is losing the distance
    /// outright, which is the error this replaces.
    private nonisolated static func appendingVector(
        to n02: Statistics.EdgeIndex, network: RouteNetwork
    ) -> Statistics.EdgeIndex {
        // What N02 says each line is. Read off the finished index rather than
        // re-derived, so the two can never disagree.
        var maskByLine: [String: (mask: Int, lineMask: Int)] = [:]
        for edge in n02.km.indices where !n02.lineName[edge].isEmpty {
            let name = n02.lineName[edge]
            if maskByLine[name] == nil {
                maskByLine[name] = (n02.mask[edge], n02.lineMask[edge])
            }
        }
        var operatorByLine: [String: String] = [:]
        for (name, owner) in n02.lineOperator.pairs where operatorByLine[name] == nil {
            operatorByLine[name] = owner
        }

        var map = n02.map
        var km = n02.km
        var mask = n02.mask
        var lineName = n02.lineName
        var lineMask = n02.lineMask
        var temporalKind = Self.padded(n02.temporalKind, count: n02.km.count, fill: .current)
        var validFrom = Self.padded(n02.validFrom, count: n02.km.count, fill: nil)
        var validTo = Self.padded(n02.validTo, count: n02.km.count, fill: nil)
        var historyId = Self.padded(n02.historyId, count: n02.km.count, fill: nil)
        var currentNetwork = Self.padded(n02.currentNetwork, count: n02.km.count, fill: true)

        for line in network.lines {
            guard let name = line.name, !name.isEmpty else { continue }
            // A drawn line with no N02 line of that name is a line N02 files
            // under another name — 京王新線 is 京王線 there, and it is the only
            // one in the five shipped packages. Skipping it costs the fallback
            // and nothing else: its track is N02's under the other name, so
            // riding it still matches wherever the vertices agree.
            guard let classified = maskByLine[name] else { continue }
            // The operator check is a guard against two railways sharing a
            // name, not a requirement: `lineOperator` holds the company owning
            // MOST of the N02 line's track, and a drawn line may name a
            // subsidiary. Only a positive disagreement rejects.
            if let owner = operatorByLine[name], let drawn = line.operator,
                !owner.isEmpty, !drawn.isEmpty, owner != drawn
            { continue }

            for part in line.parts where part.count >= 2 {
                for index in 1..<part.count {
                    let key = Statistics.packedEdgeKey(part[index - 1], part[index])
                    // N02 first, and first wins.
                    if map[key] != nil { continue }
                    map[key] = km.count
                    km.append(Statistics.equirectKm(
                        part[index - 1].lon, part[index - 1].lat,
                        part[index].lon, part[index].lat))
                    mask.append(classified.mask)
                    lineName.append(name)
                    lineMask.append(classified.lineMask)
                    temporalKind.append(.current)
                    validFrom.append(nil)
                    validTo.append(nil)
                    historyId.append(nil)
                    currentNetwork.append(true)
                }
            }
        }

        return Statistics.EdgeIndex(
            map: map, km: km, mask: mask, lineName: lineName, lineMask: lineMask,
            // The denominator is the classified network and nothing else.
            totalKm: n02.totalKm, totalsByMask: n02.totalsByMask,
            lineTotByCat: n02.lineTotByCat, lineOperator: n02.lineOperator,
            temporalKind: temporalKind, validFrom: validFrom, validTo: validTo,
            historyId: historyId, currentNetwork: currentNetwork, variants: n02.variants)
    }

    struct MissingSections: LocalizedError {
        let country: String
        var errorDescription: String? {
            "Statistics rail sections for \(country) are missing from the app bundle."
        }
    }
}
