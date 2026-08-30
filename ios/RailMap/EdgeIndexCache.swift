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
            let n02 = try Self.build(country: country)
            // The drawn network behind it — see ``appendingVector(to:network:)``.
            // `try?` keeps N02 alone as the answer when the package is absent:
            // a bundle without it can still measure a ride, it just cannot
            // measure the parts of one that only the package draws.
            guard let network = try? await DisplayNetworkCache.shared.network(
                country: country)
            else { return n02 }
            return Self.appendingVector(to: n02, network: network)
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
    /// Unbounded over the compact regions; the large ones one at a time.
    ///
    /// The note this replaces said a sixth region of Japan's size would be the
    /// moment to add a limit. That region arrived: the United States is
    /// 7.1 MB of sections over Japan's 11.8, and the two of them plus Canada
    /// are 20.5 of the 22.2 MB the seven come to.
    ///
    /// Building one index is not a decode of its file — it is the file's
    /// coordinates as Swift values, the edge table over them, AND the region's
    /// whole 6–9 MB package underneath for the drawn network the index is
    /// vectored against (``appendingVector(to:network:)``). Seven of those in
    /// flight at once holds every large intermediate the app can produce
    /// simultaneously, and the two that dominate it are exactly the two that
    /// need the most room. On a phone that peak is the difference between a
    /// slow screen and a terminated one, and it buys nothing: the wall clock
    /// of a set whose two big members are CPU-bound is those two, whether they
    /// overlap or queue.
    ///
    /// So: the five compact regions concurrently, because together they are
    /// smaller than either large one and their latency is the group's; then
    /// the large ones in catalog order, one at a time. See
    /// ``Region/DataWeight`` for where the line is drawn and why.
    ///
    /// **The merge order is unchanged.** Results are placed by the caller's
    /// own position and read back in it, exactly as the all-concurrent version
    /// did — `merge` decides which region's spelling of a shared line name
    /// comes first and lays down edge offsets that index into the arrays it
    /// builds, so the order it sees may not become a property of the schedule.
    func merged(countries: [String]) async throws -> Statistics.EdgeIndex {
        guard countries.count > 1 else {
            // One region needs no group, and none at all still answers what
            // the sequential version answered: `merge` of nothing.
            guard let only = countries.first else { return Self.merge([]) }
            return Self.merge([(only, try await index(country: only))])
        }
        var byPosition: [Int: Statistics.EdgeIndex] = [:]
        // By POSITION rather than by country, so a list that names a country
        // twice still gets both of its slots filled and the merge still sees
        // the caller's own sequence.
        let weighed = countries.enumerated().map {
            (position: $0, country: $1, weight: Region.dataWeight(country: $1))
        }

        try await withThrowingTaskGroup(
            of: (Int, Statistics.EdgeIndex).self
        ) { group in
            for entry in weighed where entry.weight == .compact {
                group.addTask {
                    (entry.position, try await self.index(country: entry.country))
                }
            }
            for try await (position, built) in group { byPosition[position] = built }
        }

        for entry in weighed where entry.weight == .large {
            byPosition[entry.position] = try await index(country: entry.country)
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
                    let key = Statistics.edgeKey(part[index - 1], part[index])
                    // N02 first, and first wins.
                    if map[key] != nil { continue }
                    map[key] = km.count
                    km.append(Statistics.equirectKm(
                        part[index - 1].lon, part[index - 1].lat,
                        part[index].lon, part[index].lat))
                    mask.append(classified.mask)
                    lineName.append(name)
                    lineMask.append(classified.lineMask)
                }
            }
        }

        return Statistics.EdgeIndex(
            map: map, km: km, mask: mask, lineName: lineName, lineMask: lineMask,
            // The denominator is the classified network and nothing else.
            totalKm: n02.totalKm, totalsByMask: n02.totalsByMask,
            lineTotByCat: n02.lineTotByCat, lineOperator: n02.lineOperator)
    }

    struct MissingSections: LocalizedError {
        let country: String
        var errorDescription: String? {
            "Statistics rail sections for \(country) are missing from the app bundle."
        }
    }
}
