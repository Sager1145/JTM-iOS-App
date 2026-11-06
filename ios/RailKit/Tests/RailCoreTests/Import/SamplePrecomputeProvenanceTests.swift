import CryptoKit
import Foundation
import Testing

@_spi(Testing) @testable import RailCore

/// The two bundled routes used by the cold-start UI checks must carry a solve
/// identity that native code can reconstruct from the train and the exact
/// history-overlay bytes. This catches a precompute that stamps a revision or
/// hash onto geometry solved under a different snapshot.
struct SamplePrecomputeProvenanceTests {
    private struct Manifest: Decodable {
        let parts: [String]
        let total: Int
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
        revisions: RailHistoryRevisionSet,
        registry: RegistryBundle
    ) throws -> String {
        let part = try JSONDecoder().decode(
            Part.self,
            from: Data(contentsOf: datasetDirectory.appending(path: filename)))
        // Browser parts are produced by precompute-train-parts.mjs under the same
        // solver namespace as native (`ROUTE_SOLVER_CACHE_VERSION` ==
        // `RouteGraph.routeSolverCacheVersion`), so the stored key must equal the
        // key native rebuilds, and the strict gate must accept the part.
        //
        // Built the way the app's on-demand solve builds it
        // (`RiddenRouteStore.canonicalRouteInput` + `routeCacheDigest`): the
        // registry upgrade `BundledRegistry.upgradeIfReady` applies once jp is
        // ready, export normalization, the corridor preference, and the
        // operator ids the solve context and service inference read. The
        // app-target timetable enrichment is not reproduced here.
        let raw = RegistryIdentityUpgrade.apply(part.train, bundle: registry)
        let canonical = RecordedRouteAdmission.applyingCorridorPreference(to:
            TrainValidation.normalizeExportTrain(
                TrainValidation.restoringRouteSectionEndpointNames(raw),
                country: "jp",
                stations: .empty))
        let sections = (canonical.routeSections ?? []).map { RouteGraph.RouteSection($0) }
        let policy = canonical.routePolicy
        let cacheTrain = RouteGraph.CacheKeyTrain(
            id: raw.id,
            number: raw.number,
            trainType: raw.trainType ?? "",
            company: canonical.company ?? "",
            origin: raw.origin,
            destination: raw.destination,
            preferredLineNames: policy?.preferredLineNames ?? [],
            preferredOperatorNames: policy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: policy?.allowedInstitutionTypeCodes,
            institutionFilterMode: policy?.institutionFilterMode,
            operatorID: raw.operatorID ?? canonical.operatorID,
            operatorIDs: raw.operatorIDs ?? canonical.operatorIDs ?? [])
        let rideDate = Dates.normalizeDateString(canonical.date)
        // `cache_key` is the browser RouteService key, whose history identity is
        // revisions only. The attested digest inserts `|hashes:` right after
        // `|history:` (app-precompute-adapter.js `serializedPrecomputeSolveContext`),
        // which is where `RailHistoryRevisionSet.canonical` places it natively.
        let browserContext = try #require(RouteGraph.solveContext(
            train: cacheTrain,
            routeSections: sections,
            country: "jp",
            rideDate: rideDate,
            historyRevision: RailHistoryRevisionSet(
                revisions.revisions.mapValues { Optional($0) }).canonical))
        #expect(part.route.cacheKey == browserContext.cacheKey, "\(filename)")
        let nativeContext = try #require(RouteGraph.solveContext(
            train: cacheTrain,
            routeSections: sections,
            country: "jp",
            rideDate: rideDate,
            historyRevision: revisions.canonical))
        let expectedDigest = RouteGraph.keyDigest(nativeContext.cacheKey)
        let context = part.route.solverContext

        #expect(context.routeCacheDigest == expectedDigest, "\(filename)")
        #expect(context.historyHashes == ["jp": historyHash])
        #expect(RailPrecomputedRouteGate.accepts(
            context,
            expectedDigest: expectedDigest,
            solverVersion: RouteGraph.routeSolverCacheVersion,
            rideDate: rideDate,
            revisions: revisions,
            expectedHashes: revisions.contentHashes), "\(filename)")
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
        // Derived, not pinned: the manifest total is the sample store's train
        // count, and every train has exactly one part.
        let storeObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: datasetDirectory.appending(path: "sample-full.json")))
        let storeTrains = try #require((storeObject as? [String: Any])?["trains"] as? [Any])
        #expect(manifest.parts.count == manifest.total)
        #expect(manifest.total == storeTrains.count)

        // Normalization needs the jp registry (part-171 journey_680A26B9C2D06FDE49DABFF6A02DF17C (Narita Express)
        // relies on the Tokyo corridor inference), as production loads it.
        let bundleData = try Data(contentsOf: Self.repositoryURL("app/data/registry-bundle/jp.json"))
        let registry = try JSONDecoder().decode(RegistryBundle.self, from: bundleData)
        let identity = RegistryIdentity(bundle: registry)
        var idsByPart: [String: String] = [:]
        try RegistryIdentityLookup.withTestProvider({ region in
            region.lowercased() == "jp" ? identity : nil
        }) {
            for part in manifest.parts {
                idsByPart[part] = try Self.verifyPart(
                    "\(part).json",
                    datasetDirectory: datasetDirectory,
                    historyHash: historyHash,
                    revisions: revisions,
                    registry: registry)
            }
        }
        #expect(idsByPart["part-000"] == "journey_A9554752F257CDA52831A6C0EED248AF")
        #expect(idsByPart["part-008"] == "journey_09AC64CFCEE12C93E83510873DD6FEC1")
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
