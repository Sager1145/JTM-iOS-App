import CryptoKit
import Darwin
import Foundation
import Testing
@testable import RailCore

/// Opt-in host benchmark of a cold full-JP route-graph build. Records build
/// time, sampled peak physical footprint, and an order-sensitive digest of the
/// built graph so two source states can be compared for identical output.
///
///     JTM_GRAPH_BENCH=1 JTM_GRAPH_BENCH_OUT=/path/out.txt \
///       swift test -c release -Xswiftc -enable-testing --filter RouteGraphBuildBenchmark
@Suite("RouteGraph build benchmark")
struct RouteGraphBuildBenchmarkTests {
    @Test("Full JP graph build: time, peak footprint and output digest",
          .enabled(if: ProcessInfo.processInfo.environment["JTM_GRAPH_BENCH"] == "1"))
    func fullJapanBuild() throws {
        let root = try PortFixtures.repositoryRoot()
        let dataRoot = root.appending(path: "app/data")
        var sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: dataRoot.appending(path: "rail-sections.json")).features
        var stationFeatures = try Stations.FeatureCollection.load(
            contentsOf: dataRoot.appending(path: "stations.json")).features
        let overlay = try RailHistoryOverlay.load(from: dataRoot.appending(path: "rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sections, stations: &stationFeatures)
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            dataRoot.appending(path: "physical-rail-junctions.json")))
        let junctions = registry.junctions(for: "jp")
        let store = RouteGraph.RouteGraphStore(
            sections: sections, policy: .physicalRailway, junctions: junctions,
            identityPeriods: overlay.identityPeriods)

        let sampler = FootprintSampler()
        let baseline = FootprintSampler.footprint()
        sampler.start()
        let clock = ContinuousClock()
        let started = clock.now
        let graph = store.fullGraph()
        let elapsed = clock.now - started
        let peak = sampler.stop()
        let retained = FootprintSampler.footprint()

        let digest = Self.digest(graph)
        let mb = { (bytes: UInt64) in String(format: "%.1f", Double(bytes) / 1_048_576) }
        let report = """
        nodes=\(graph.nodes.count) edges=\(graph.adjacency.values.reduce(0) { $0 + $1.count })
        rejected=\(graph.rejectedPhysicalJunctionIDs.count)
        build_seconds=\(elapsed.components.seconds).\(String(format: "%03lld", elapsed.components.attoseconds / 1_000_000_000_000_000))
        footprint_before_mb=\(mb(baseline)) peak_mb=\(mb(peak)) retained_mb=\(mb(retained))
        spike_over_before_mb=\(mb(peak &- baseline)) retained_over_before_mb=\(mb(retained &- baseline))
        digest=\(digest)

        """
        print(report)
        if let out = ProcessInfo.processInfo.environment["JTM_GRAPH_BENCH_OUT"] {
            try report.write(toFile: out, atomically: true, encoding: .utf8)
        }
        #expect(graph.nodes.count > 300_000)
    }

    /// Order-sensitive where the graph's order is observable (adjacency
    /// lists, grid buckets, rejection log); key-sorted elsewhere.
    static func digest(_ graph: RouteGraph.Graph) -> String {
        var hasher = SHA256()
        func put(_ s: String) { hasher.update(data: Data(s.utf8)); hasher.update(data: Data([0])) }
        func coord(_ c: Coordinate) -> String { "\(c.lon.bitPattern),\(c.lat.bitPattern)" }
        for key in graph.nodes.keys.sorted() {
            put("N"); put(key); put(coord(graph.nodes[key]!))
            for edge in graph.adjacency[key] ?? [] {
                put("E"); put(edge.to); put("\(edge.length.bitPattern)")
                put(edge.institutionTypeCode); put(edge.railwayClassCode); put(edge.lineName)
                put(edge.operator); put(edge.temporalKind.rawValue)
                put(edge.validFrom ?? "-"); put(edge.validTo ?? "-"); put(edge.historyIDs.joined(separator: "|"))
                put(edge.physicalJunction?.junction.id ?? "-")
                put(edge.physicalJunction.map { $0.institutionTypeCodes.sorted().joined(separator: "|") } ?? "-")
                put(edge.connector.map { "\($0)" } ?? "-")
                put(edge.registeredTrackLineIDs.sorted().joined(separator: "|"))
            }
            if let meta = graph.nodeMeta[key] {
                put("M")
                put(meta.lineNames.sorted().joined(separator: "|"))
                put(meta.operators.sorted().joined(separator: "|"))
                put(meta.institutionTypeCodes.sorted().joined(separator: "|"))
                put(meta.railwayClassCodes.sorted().joined(separator: "|"))
            } else {
                put("M-")
            }
        }
        put("adjacency-only")
        for key in graph.adjacency.keys.sorted() where graph.nodes[key] == nil { put(key) }
        put("meta-only")
        for key in graph.nodeMeta.keys.sorted() where graph.nodes[key] == nil { put(key) }
        for cell in graph.grid.keys.sorted() {
            put("G"); put(cell)
            for key in graph.grid[cell]! { put(key) }
        }
        for key in graph.sourceNodesByCoordinate.keys.sorted() {
            put("S"); put(key); put(graph.sourceNodesByCoordinate[key]!.sorted().joined(separator: "|"))
        }
        for (id, reason) in zip(graph.rejectedPhysicalJunctionIDs, graph.rejectedPhysicalJunctionReasons) {
            put("R"); put(id); put(reason)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Samples `phys_footprint` every 2 ms on a background thread.
private final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var peak: UInt64 = 0
    private var thread: Thread?

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    func start() {
        lock.lock(); running = true; peak = Self.footprint(); lock.unlock()
        let thread = Thread { [self] in
            while true {
                let value = Self.footprint()
                lock.lock()
                if value > peak { peak = value }
                let keepGoing = running
                lock.unlock()
                if !keepGoing { return }
                usleep(2_000)
            }
        }
        self.thread = thread
        thread.start()
    }

    func stop() -> UInt64 {
        let last = Self.footprint()
        lock.lock(); running = false; if last > peak { peak = last }; let value = peak; lock.unlock()
        return value
    }
}
