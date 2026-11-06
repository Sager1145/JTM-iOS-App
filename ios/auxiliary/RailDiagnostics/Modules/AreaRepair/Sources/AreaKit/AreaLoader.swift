import Foundation
import RailCore

/// One loaded data snapshot (repository, or repository + scratch overlay):
/// the display package, solver sections with rail history applied, stations,
/// reviewed junctions, and the route graph/network built from them the same
/// way production does.
///
/// Not thread-safe: `graphStore` mutates its regional cache while solving.
/// Use one `AreaData` from one task at a time.
public final class AreaData: @unchecked Sendable {
    public let root: DataRoot
    public let region = "jp"
    public let loaded: DisplayParts.LoadedPackage
    public var package: CompactPackage { loaded.package }
    public let linesByID: [String: CompactPackage.Line]
    /// DisplayParts strokes per line ID, as the map draws them.
    public let displayParts: [String: [[Coordinate]]]
    /// Solver sections exactly as `rail-sections.json` stores them.
    public let rawSections: [RouteGraph.SectionFeature]
    /// Stations exactly as `stations.json` stores them.
    public let rawStations: [Stations.Feature]
    public let overlay: RailHistoryOverlay
    public let applyReport: RailHistory.ApplyReport
    /// Solver sections after `RailHistory.apply` (stamps + overlay sections).
    public let sections: [RouteGraph.SectionFeature]
    public let stations: Stations.FeatureCollection
    public let junctions: [RouteGraph.PhysicalJunction]
    /// Junction rows in file order, verbatim.
    public let junctionRows: [AreaJSON]
    public let sourceInputs: RideRouteResolution.SourceInputs
    public let graphStore: RouteGraph.RouteGraphStore
    public let network: RouteNetwork
    public let networkInputs: RideRouteResolution.NetworkInputs

    /// Loads all five files once. Mirrors RailHistoryPackageTests' environment
    /// (history applied, physical-railway policy, reviewed junctions) and
    /// DisplayNetworkCache.assemble (network from DisplayParts + interval codes).
    public static func load(_ root: DataRoot) throws -> AreaData { try AreaData(root: root) }

    private init(root: DataRoot) throws {
        self.root = root
        let loaded = try DisplayParts.LoadedPackage.load(contentsOf: root.url(.package))
        self.loaded = loaded
        let lines = loaded.package.lines
        linesByID = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let parts = lines.map { DisplayParts.parts(for: $0, topology: loaded.topologyByLineID[$0.id] ?? .init()) }
        displayParts = Dictionary(zip(lines.map(\.id), parts).map { ($0, $1) }, uniquingKeysWith: { first, _ in first })

        rawSections = try RouteGraph.SectionFeatureCollection.load(contentsOf: root.url(.sections)).features
        rawStations = try Stations.FeatureCollection.load(contentsOf: root.url(.stations)).features
        let overlay = try RailHistoryOverlay.load(from: root.url(.history))
        self.overlay = overlay
        var sections = rawSections
        var stationFeatures = rawStations
        applyReport = RailHistory.apply(overlay, sections: &sections, stations: &stationFeatures)
        self.sections = sections
        let stations = Stations.FeatureCollection(features: stationFeatures)
        self.stations = stations

        let junctionData = try Data(contentsOf: root.url(.junctions))
        let junctions = try PhysicalRailJunctionRegistry(data: junctionData).junctions(for: "jp")
        self.junctions = junctions
        junctionRows = try AreaJSON.parse(junctionData)["junctions"]?.arrayValue ?? []

        let sourceInputs = RideRouteResolution.SourceInputs(
            sections: sections, stationCollection: stations,
            physicalJunctions: junctions, identityPeriods: overlay.identityPeriods)
        graphStore = RouteGraph.RouteGraphStore(
            sections: sections, policy: .physicalRailway, junctions: junctions,
            cachePolicy: .bounded(maximumNodes: 100_000), identityPeriods: overlay.identityPeriods)
        self.sourceInputs = sourceInputs
        let network = RouteNetwork(lines: lines.enumerated().map { index, line in
            RouteNetwork.Line(
                lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: parts[index], intervals: RailIntervalCodes.intervals(for: line), compactLine: line)
        })
        self.network = network
        networkInputs = RideRouteResolution.NetworkInputs(network: network, inputs: sourceInputs)
    }

    /// A fresh resolver over this snapshot (resolvers own mutable state).
    public func resolver() -> RideRouteResolution {
        RideRouteResolution(inputs: sourceInputs, country: region, network: networkInputs, graphStore: graphStore)
    }

    private var historyRowsCache: (retirements: [AreaJSON], identityPeriods: [AreaJSON])?

    /// Retirement and identity-period rows of rail-history.json, verbatim
    /// (parsed on first use).
    public func historyRows() throws -> (retirements: [AreaJSON], identityPeriods: [AreaJSON]) {
        if let historyRowsCache { return historyRowsCache }
        let tree = try AreaJSON.parse(Data(contentsOf: root.url(.history)))
        let rows = (tree["retirements"]?.arrayValue ?? [], tree["identity_periods"]?.arrayValue ?? [])
        historyRowsCache = rows
        return rows
    }

    /// Network line by ID.
    public func networkLine(_ id: String) -> RouteNetwork.Line? { network.lines.first { $0.lineId == id } }

    /// Solver features (history applied) whose identity is the package line's
    /// N02 name and operator.
    public func featureIndices(lineName: String, operatorName: String?, in indices: [Int]) -> [Int] {
        indices.filter {
            sections[$0].properties.lineName == lineName && sections[$0].properties.operator == (operatorName ?? "")
        }
    }
}
