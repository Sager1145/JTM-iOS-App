import Foundation
import Testing

@testable import RailCore

/// Regression coverage for the record produced by the service-pattern picker.
///
/// The selected pattern itself is editor-session state. Once the user saves,
/// the durable contract is the applied train: its date, ordered station names
/// and codes, times, and per-leg ride state. These tests carry that record
/// through both persistence doors and then rebuild the route input from the
/// restored stops, as a cold route cache does.
@Suite("Train service pattern persistence")
struct TrainServicePatternPersistenceTests {
    private struct StopSnapshot: Equatable {
        let name: String
        let code: String?
        let arrival: String?
        let departure: String?
        let stopType: String
        let ridden: Bool
    }

    private struct RouteEndpointSnapshot: Equatable {
        let from: String?
        let to: String?
        let fromCode: String?
        let toCode: String?
    }

    @Test(
        "applied records survive reopen, export/import, and a cold route rebuild",
        arguments: [false, true]
    )
    func appliedRecordRoundTrips(reversed: Bool) throws {
        let pattern = try #require(
            TrainServicePatterns.patterns.first {
                $0.id == "haruka-kyoto-kansai-airport"
            })
        var applied = TrainServicePatterns.apply(
            pattern,
            to: Train(
                id: reversed ? "haruka-reverse" : "haruka-forward",
                date: "2026-09-24",
                number: "",
                origin: "",
                destination: "",
                stops: []),
            reversed: reversed)

        applied.stops[0].departure = "07:15"
        applied.stops[1].arrival = "07:40"
        applied.stops[1].departure = "07:42"
        applied.stops[1].rideSegment = false
        applied.stops[applied.stops.count - 1].arrival = "08:42"

        let expectedStops = Self.stopSnapshot(applied)
        let expectedRefs = reversed
            ? Array(pattern.stopRefs.reversed())
            : pattern.stopRefs
        #expect(expectedStops.map(\.name) == expectedRefs.map(\.name))
        #expect(expectedStops.map(\.code) == expectedRefs.map { Optional($0.sourceCode) })

        // Pin the Codable contract independently from canonical normalization.
        let savedStore = try JSONEncoder().encode(TrainStore(trains: [applied]))
        let reopenedStore = try JSONDecoder().decode(TrainStore.self, from: savedStore)
        let reopened = try #require(reopenedStore.trains.first)
        #expect(reopened.date == "2026-09-24")
        #expect(Self.stopSnapshot(reopened) == expectedStops)

        // App persistence writes a canonical store and decodes it on reopen.
        let workspace = StoreOperations.Workspace(
            store: TrainStore(trains: [reopened]), country: "jp")
        let exported = StoreOperations.exportTrainStore(workspace)
        let diskStore = try JSONDecoder().decode(TrainStore.self, from: Data(exported.utf8))
        let diskReopened = try #require(diskStore.trains.first)
        #expect(diskReopened.date == "2026-09-24")
        #expect(Self.stopSnapshot(diskReopened) == expectedStops)

        // The user-facing import door performs another normalization pass and
        // must retain the same user record as a normal reopen.
        let parsed = try TrainValidation.JSON.parse(exported)
        try TrainValidation.validateTrainStore(parsed)
        guard case .array(let rows)? = parsed["trains"] else {
            Issue.record("canonical export did not contain a trains array")
            return
        }
        let row = try #require(rows.first)
        var importedWorkspace = StoreOperations.Workspace(country: "jp")
        _ = try StoreOperations.appendImportedTrain(row, in: &importedWorkspace)
        let imported = try #require(importedWorkspace.store.trains.first)
        #expect(imported.date == "2026-09-24")
        #expect(Self.stopSnapshot(imported) == expectedStops)

        // Pattern application intentionally clears stale route sections. A
        // reopen or cache miss must reconstruct the same code-based endpoints
        // solely from the durable stop records.
        let expectedRoute = Self.routeSnapshot(
            StoreOperations.rideRouteSections(for: applied))
        #expect(expectedRoute.count == max(expectedStops.count - 1, 0))
        #expect(expectedRoute == zip(expectedStops, expectedStops.dropFirst()).map {
            RouteEndpointSnapshot(
                from: $0.0.name,
                to: $0.1.name,
                fromCode: $0.0.code,
                toCode: $0.1.code)
        })
        #expect(Self.routeSnapshot(StoreOperations.rideRouteSections(for: reopened)) == expectedRoute)
        #expect(Self.routeSnapshot(StoreOperations.rideRouteSections(for: diskReopened)) == expectedRoute)
        #expect(Self.routeSnapshot(StoreOperations.rideRouteSections(for: imported)) == expectedRoute)

        var cacheCleared = imported
        cacheCleared.routeSections = nil
        let rebuilt = StoreOperations.rideRouteSections(for: cacheCleared)
        #expect(Self.routeSnapshot(rebuilt) == expectedRoute)
        #expect(Self.routeTemplate(rebuilt) == Self.routeTemplate(
            StoreOperations.rideRouteSections(for: applied)))
    }

    @Test("pattern station codes resolve, but AI stays gated until a resolved stop has a time")
    func aiGateUsesResolvedTimedStop() throws {
        let pattern = try #require(
            TrainServicePatterns.patterns.first {
                $0.id == "haruka-kyoto-kansai-airport"
            })
        var applied = TrainServicePatterns.apply(
            pattern,
            to: Train(
                id: "haruka-ai", date: "2026-09-24", number: "",
                origin: "", destination: "", stops: []))
        let catalog = try Self.jpEditorCatalog()

        // Draft pins look up the same key and read CatalogStation latitude/longitude.
        // This catalog has no station at 0,0, so a zero axis is not a real pin.
        var pinOffenders: [String] = []
        #expect(!applied.stops.isEmpty)
        for stop in applied.stops {
            guard let code = stop.n02StationCode, !code.isEmpty else {
                pinOffenders.append("missing code for \(stop.name)")
                continue
            }
            guard let station = catalog.station(StationKey(regionCode: "jp", sourceCode: code)) else {
                pinOffenders.append("unresolved \(stop.name) / \(code)")
                continue
            }
            if station.name != stop.name {
                pinOffenders.append("\(code) names \(station.name), expected \(stop.name)")
            }
            if !station.latitude.isFinite || !station.longitude.isFinite
                || station.latitude == 0 || station.longitude == 0
            {
                pinOffenders.append("\(code) coordinates \(station.latitude),\(station.longitude)")
            }
        }
        #expect(pinOffenders.isEmpty, "\(pinOffenders)")
        #expect(JourneyCompletion.requestDenial(train: applied, catalog: catalog) == .noExplicitTime)
        #expect(JourneyCompletion.isRequestEligible(applied, catalog: catalog) == false)

        applied.stops[0].departure = "07:15"
        #expect(JourneyCompletion.requestDenial(train: applied, catalog: catalog) == nil)
        #expect(JourneyCompletion.isRequestEligible(applied, catalog: catalog))
    }

    private static func stopSnapshot(_ train: Train) -> [StopSnapshot] {
        train.stops.map {
            StopSnapshot(
                name: $0.name,
                code: $0.n02StationCode,
                arrival: $0.arrival,
                departure: $0.departure,
                stopType: $0.stopType,
                ridden: $0.rideSegment)
        }
    }

    private static func routeSnapshot(_ sections: [RouteSection]) -> [RouteEndpointSnapshot] {
        sections.map {
            RouteEndpointSnapshot(
                from: $0.from,
                to: $0.to,
                fromCode: $0.fromN02StationCode,
                toCode: $0.toN02StationCode)
        }
    }

    private static func routeTemplate(_ sections: [RouteSection]) -> String {
        RouteGraph.templateKey(sections: sections.map {
            RouteGraph.RouteSection(
                from: $0.from,
                to: $0.to,
                fromStationCode: $0.fromN02StationCode,
                toStationCode: $0.toN02StationCode,
                lineNames: $0.lineNames ?? [],
                operatorNames: $0.operatorNames ?? [])
        })
    }

    private static func jpEditorCatalog() throws -> EditorCatalog {
        let packageURL = try repositoryRoot().appending(path: "app/public/rail/jp-2025.json")
        let directory = try JSONDecoder().decode(
            CompactPackage.StationDirectory.self,
            from: Data(contentsOf: packageURL))
        return EditorCatalogBuilder.build(directory.lineSources(regionCode: "jp"))
    }

    private static func repositoryRoot(from file: StaticString = #filePath) throws -> URL {
        var directory = URL(filePath: "\(file)").deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: directory.appending(path: "app/public/rail/jp-2025.json").path)
            {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
