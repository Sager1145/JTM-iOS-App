import Foundation
import RailCore

/// The drawn railway, built once per region and then shared.
///
/// `RouteNetwork` is what `canonicalizeRouteFeature` re-draws a solved hop
/// against, and building one means parsing the whole of `<country>-2025.json`
/// and running ``DisplayParts/parts(for:topology:)`` over every line in it —
/// 9.1 MB and 652 lines for Japan. There are two callers that want the same
/// answer, and before this they did not share it:
///
/// - ``RiddenRouteStore`` solving a journey the route cache does not hold,
///   which built its own network inside every call;
/// - ``RiddenRouteStore`` loading a journey out of a precomputed dataset,
///   which did not canonicalise at all — see ``RiddenRouteStore/datasetRides``
///   for what that cost.
///
/// An `actor` for the same reason ``EdgeIndexCache`` is one: the build is the
/// expensive part and it has to be joinable, so two callers asking for the
/// same region at once wait on one build instead of starting two.
actor DisplayNetworkCache {
    static let shared = DisplayNetworkCache()

    private var networks: [String: RouteNetwork] = [:]
    private var inFlight: [String: Task<RouteNetwork, Error>] = [:]

    /// The network one journey is canonicalised against.
    ///
    /// One region's for every journey that stays in one country, which is the
    /// same answer ``network(country:)`` always gave. A journey that crosses a
    /// border gets the two networks concatenated and filed under the scope's
    /// own key, so the second such journey in a log reuses it.
    ///
    /// Concatenation is enough because a `RouteNetwork` is a list of lines and
    /// two indexes over it, and the two packages share no line id: every id is
    /// the operator's own slug (`kenosha-streetcar-sc`, `go-transit-lw`), and
    /// no operator appears in both countries' packages. A name IS shared —
    /// exactly four of them, the *Maple Leaf*, the *Adirondack*, the *Amtrak
    /// Cascades* and VIA's *Toronto - New York*, each drawn as two lines split
    /// at the border under one name — and that is exactly what the name index
    /// has to hold both of for a crossing to canonicalise all the way through.
    ///
    /// ## The lines go in in the CATALOG's order, never the ride's
    ///
    /// ``RouteScope/graphRegions`` rather than ``RouteScope/regions``, and the
    /// difference is what makes this cache sound. The *Maple Leaf* reaches
    /// `[ca, us]` and the *Adirondack* `[us, ca]`; both file under `"us+ca"`,
    /// so whichever asked first would decide the order of the lines in the
    /// network the OTHER one then canonicalises against. `linesByName` is
    /// insertion-ordered and load-bearing — for a name held by two lines the
    /// first to reach a given score wins — so a hop over the border could
    /// canonicalise onto the American line on one launch and the Canadian one
    /// on the next, from nothing but which journey the route cache happened to
    /// be missing.
    func network(scope: RouteScope) async throws -> RouteNetwork {
        guard scope.crossesBorder else { return try await network(country: scope.code) }
        if let ready = networks[scope.key] { return ready }
        var lines: [RouteNetwork.Line] = []
        for region in scope.graphRegions {
            lines += try await network(country: region.code).lines
        }
        let merged = RouteNetwork(lines: lines)
        networks[scope.key] = merged
        return merged
    }

    /// The network for one region, building it if this is the first ask.
    func network(country: String) async throws -> RouteNetwork {
        if let ready = networks[country] { return ready }
        if let running = inFlight[country] { return try await running.value }

        let task = Task.detached(priority: .userInitiated) {
            try Self.build(country: country)
        }
        inFlight[country] = task
        // Detached, and the in-flight entry is cleared by whoever the build
        // finishes for — the reasoning is ``EdgeIndexCache/index(country:)``'s,
        // and so is the hazard: a caller cancelled mid-wait must not remove a
        // build the next caller is still waiting on.
        do {
            let built = try await task.value
            if inFlight[country] == task { inFlight[country] = nil }
            networks[country] = built
            return built
        } catch {
            if inFlight[country] == task { inFlight[country] = nil }
            throw error
        }
    }

    private nonisolated static func build(country: String) throws -> RouteNetwork {
        let interval = RailSignpost.data.begin("data.displayNetwork.build")
        defer { RailSignpost.data.end("data.displayNetwork.build", interval) }
        guard let url = Bundle.main.url(
            forResource: Region.packageResource(country: country), withExtension: "json")
        else { throw MissingPackage(country: country) }
        // Both halves of the package come off one read and one parse; see the
        // single-pass contract in `verify.sh`.
        let loaded = try DisplayParts.LoadedPackage.load(contentsOf: url)
        return RouteNetwork(lines: loaded.package.lines.map { line in
            RouteNetwork.Line(
                lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: nil,
                parts: DisplayParts.parts(
                    for: line, topology: loaded.topologyByLineID[line.id] ?? .init()))
        })
    }

    struct MissingPackage: LocalizedError {
        let country: String
        var errorDescription: String? {
            "The rail package for \(country) is missing from the app bundle."
        }
    }
}
