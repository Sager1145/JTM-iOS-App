import Foundation
import Testing

@testable import RailCore

/// Runs the real Japan route solver over every consecutive-stop leg of every
/// catalogued train-service pattern (one test case per pattern) and records
/// which legs fail to solve. The aggregate report is written only when
/// `TRAIN_PATTERN_ROUTE_REPORT` is set to an output file path.
struct TrainServicePatternRouteTests {
    struct Environment {
        let graph: RouteGraph.Graph
        let stations: Stations.Index
    }

    nonisolated(unsafe) static let environment: Environment = {
        let root = try! PortFixtures.repositoryRoot()
        let sections = try! RouteGraph.SectionFeatureCollection.load(
            contentsOf: root.appending(path: "app/data/rail-sections.json")).features
        let stationCollection = try! Stations.FeatureCollection.load(
            contentsOf: root.appending(path: "app/data/stations.json"))
        let stations = Stations.Index(stationCollection)
        let graph = RouteGraph.build(from: sections)
        RouteSolver.addStationTransferConnectorEdges(
            graph: graph, stations: stationCollection.features)
        return Environment(graph: graph, stations: stations)
    }()

    final class Report: @unchecked Sendable {
        static let shared = Report()
        private let lock = NSLock()
        private var entries: [String: [String: Any]] = [:]

        static var outputURL: URL? {
            guard let path = ProcessInfo.processInfo.environment["TRAIN_PATTERN_ROUTE_REPORT"]
            else { return nil }
            return URL(fileURLWithPath: path)
        }

        func record(id: String, legs: Int, failed: [String], seconds: Double) {
            lock.lock()
            defer { lock.unlock() }
            entries[id] = ["legs": legs, "failed": failed, "seconds": seconds]
            guard let url = Self.outputURL else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(
                withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func context(_ pattern: TrainServicePatterns.Pattern) -> RouteSolver.TrainContext {
        .init(
            id: pattern.id, number: pattern.name, trainType: "特急",
            company: pattern.companyLabel, origin: pattern.origin,
            destination: pattern.destination,
            preferredLineNames: [],
            preferredOperatorNames: pattern.company.split(separator: "/").map {
                $0.trimmingCharacters(in: .whitespaces)
            },
            allowedInstitutionTypeCodes: nil,
            institutionFilterMode: "soft")
    }

    @Test(arguments: TrainServicePatterns.patterns)
    func everyLegSolves(pattern: TrainServicePatterns.Pattern) throws {
        let env = Self.environment
        let train = Self.context(pattern)
        let stops = pattern.stops
        let started = Date()
        var failed: [String] = []
        var anchor: Coordinate? = nil
        let legCount = max(stops.count - 1, 0)
        for i in 0..<legCount {
            let section = RouteSection(from: stops[i], to: stops[i + 1])
            let solved = RouteSolver.solveSection(
                section, segmentIndex: i, train: train, country: "jp",
                graph: env.graph, stations: env.stations, continuityAnchor: anchor)
            if let solved, let last = solved.coordinates.last {
                anchor = last
            } else {
                failed.append("\(stops[i])→\(stops[i + 1])")
                anchor = nil
            }
        }
        let seconds = Date().timeIntervalSince(started)
        Report.shared.record(id: pattern.id, legs: legCount, failed: failed, seconds: seconds)
        #expect(failed.isEmpty, "\(pattern.id) (\(pattern.name)) failed legs: \(failed)")
    }
}
