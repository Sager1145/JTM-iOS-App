import CryptoKit
import Foundation
import Testing

@testable import RailCore

/// The two bundled routes used by the cold-start UI checks must carry a solve
/// identity that native code can reconstruct from the train and the exact
/// history-overlay bytes. This catches a precompute that stamps a revision or
/// hash onto geometry solved under a different snapshot.
struct SamplePrecomputeProvenanceTests {
    private struct Manifest: Decodable {
        let parts: [String]
    }

    private struct Part: Decodable {
        struct Route: Decodable {
            let cacheKey: String
            let solverContext: RailPrecomputedSolverContext

            private enum CodingKeys: String, CodingKey {
                case cacheKey = "cache_key"
                case solverContext = "solver_context"
            }
        }

        let train: Train
        let route: Route
    }

    private static func repositoryURL(_ relativePath: String) throws -> URL {
        try PortFixtures.repositoryRoot().appending(path: relativePath)
    }

    private static func dataURL(_ environmentKey: String, fallback: String) throws -> URL {
        if let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return try repositoryURL(fallback)
    }

    private static func verifyPart(
        _ filename: String,
        datasetDirectory: URL,
        historyHash: String,
        revisions: RailHistoryRevisionSet
    ) throws -> String {
        let part = try JSONDecoder().decode(
            Part.self,
            from: Data(contentsOf: datasetDirectory.appending(path: filename)))
        // Reconstruct the attested browser artifact with its original solver
        // identity, then independently prove the strict native gate rejects it.
        // Existing corridor inference remains part of normalization.
        let canonical = TokyoConventionalRouteInference.applying(to:
            TrainValidation.normalizeExportTrain(
                TrainValidation.restoringRouteSectionEndpointNames(part.train),
                country: "jp",
                stations: .empty))
        let sections = (canonical.routeSections ?? []).map { section in
            RouteGraph.RouteSection(
                from: section.from,
                to: section.to,
                fromStationCode: section.fromN02StationCode,
                toStationCode: section.toN02StationCode,
                lineNames: section.lineNames ?? [],
                operatorNames: section.operatorNames ?? [],
                lineIDs: section.lineIDs ?? [], sectionCodes: section.sectionCodes ?? [])
        }
        let policy = canonical.routePolicy
        let cacheTrain = RouteGraph.CacheKeyTrain(
            id: part.train.id,
            number: part.train.number,
            trainType: part.train.trainType ?? "",
            company: canonical.company ?? "",
            origin: part.train.origin,
            destination: part.train.destination,
            preferredLineNames: policy?.preferredLineNames ?? [],
            preferredOperatorNames: policy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: policy?.allowedInstitutionTypeCodes,
            institutionFilterMode: policy?.institutionFilterMode)
        let browserSolveContext = try #require(RouteGraph.solveContext(
            train: cacheTrain,
            routeSections: sections,
            country: "jp",
            cacheVersion: RouteGraph.legacyCoordinateSolverCacheVersion,
            rideDate: Dates.normalizeDateString(part.train.date),
            historyRevision: revisions.revisions.keys.sorted().map {
                "\($0):\(revisions.revisions[$0]!)"
            }.joined(separator: "|")))
        #expect(part.route.cacheKey == browserSolveContext.cacheKey)
        let legacySolveContext = try #require(RouteGraph.solveContext(
            train: cacheTrain,
            routeSections: sections,
            country: "jp",
            cacheVersion: RouteGraph.legacyCoordinateSolverCacheVersion,
            rideDate: Dates.normalizeDateString(part.train.date),
            historyRevision: revisions.canonical))
        let expectedDigest = RouteGraph.keyDigest(legacySolveContext.cacheKey)
        let context = part.route.solverContext

        #expect(context.routeCacheDigest == expectedDigest)
        #expect(context.historyHashes == ["jp": historyHash])
        #expect(RailPrecomputedRouteGate.accepts(
            context,
            expectedDigest: expectedDigest,
            solverVersion: RouteGraph.legacyCoordinateSolverCacheVersion,
            rideDate: Dates.normalizeDateString(part.train.date),
            revisions: revisions,
            expectedHashes: revisions.contentHashes))
        let strictSolveContext = try #require(RouteGraph.solveContext(
            train: cacheTrain, routeSections: sections, country: "jp",
            rideDate: Dates.normalizeDateString(part.train.date), historyRevision: revisions.canonical))
        let strictDigest = RouteGraph.keyDigest(strictSolveContext.cacheKey)
        #expect(strictSolveContext.cacheKey != legacySolveContext.cacheKey)
        #expect(strictDigest != expectedDigest)
        #expect(!RailPrecomputedRouteGate.accepts(
            context, expectedDigest: strictDigest,
            solverVersion: RouteGraph.routeSolverCacheVersion,
            rideDate: Dates.normalizeDateString(part.train.date),
            revisions: revisions, expectedHashes: revisions.contentHashes))
        // Even with the old digest supplied, the version gate alone must reject
        // coordinate-parity geometry for the strict native solver.
        #expect(!RailPrecomputedRouteGate.accepts(
            context, expectedDigest: expectedDigest,
            solverVersion: RouteGraph.routeSolverCacheVersion,
            rideDate: Dates.normalizeDateString(part.train.date),
            revisions: revisions, expectedHashes: revisions.contentHashes))
        return part.train.id
    }

    @Test func bundledSamplesCarryAcceptedHistoryAttestation() throws {
        let datasetDirectory = try Self.dataURL(
            "JTM_PRECOMPUTE_DATASET",
            fallback: "app/data/sample-data")
        let overlayURL = try Self.dataURL(
            "JTM_RAIL_HISTORY",
            fallback: "app/data/rail-history.json")
        let overlayData = try Data(contentsOf: overlayURL)
        let overlay = try RailHistoryOverlay.decode(overlayData)
        let historyHash = SHA256.hash(data: overlayData)
            .map { String(format: "%02x", $0) }
            .joined()
        let revisions = RailHistoryRevisionSet(
            ["jp": overlay.revision], contentHashes: ["jp": historyHash])
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: datasetDirectory.appending(path: "manifest.json")))
        #expect(manifest.parts.count == 201)

        var idsByPart: [String: String] = [:]
        for part in manifest.parts {
            idsByPart[part] = try Self.verifyPart(
                "\(part).json",
                datasetDirectory: datasetDirectory,
                historyHash: historyHash,
                revisions: revisions)
        }
        #expect(idsByPart["part-000"] == "20260703_01_haruka")
        #expect(idsByPart["part-008"] == "20260704_06_marunouchi_line")
    }

    @Test func leanSectionEndpointRestorationPreservesExplicitAndUnknownNames() {
        let train = Train(
            id: "lean", number: "", origin: "A", destination: "C",
            routeSections: [
                RouteSection(
                    from: "Explicit A", fromN02StationCode: "000001",
                    toN02StationCode: "000002"),
                RouteSection(
                    fromN02StationCode: "000002", toN02StationCode: "999999"),
            ],
            stops: [
                Stop(name: "A", n02StationCode: "000001"),
                Stop(name: "B", n02StationCode: "000002"),
                Stop(name: "C", n02StationCode: "000003"),
            ])

        let sections = TrainValidation.restoringRouteSectionEndpointNames(train).routeSections
        #expect(sections?[0].from == "Explicit A")
        #expect(sections?[0].to == "B")
        #expect(sections?[1].from == "B")
        #expect(sections?[1].to == nil)
    }
}
