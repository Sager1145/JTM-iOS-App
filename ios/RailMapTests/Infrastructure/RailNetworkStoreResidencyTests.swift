import CoreLocation
import CryptoKit
import Foundation
import MapKit
import Testing

@testable import RailMap

/// Residency by line id (trip-loading plan, U4): lines asked for by id, and
/// the `dependsOn` lines they need, survive viewport moves and the byte
/// budget until every holder releases them. Reads the bundled display network.
@MainActor
struct RailNetworkStoreResidencyTests {
    private struct Fixture {
        let store: RailNetworkStore
        let index: RailDisplayNetworkIndex
        /// A small jp line that names a dependency, and that dependency.
        let dependent: RailDisplayNetworkIndex.Entry
        let dependency: RailDisplayNetworkIndex.Entry
    }

    private func fixture() throws -> Fixture {
        let manifest = try RailDisplayNetwork.manifest()
        let index = RailDisplayNetworkIndex.lineIndex(for: manifest)
        let dependent = try #require(
            index.entriesByRegion["jp"]?
                .filter { !$0.dependsOn.isEmpty && $0.chunk.length < 80_000 }
                .first { index.entryByID[$0.dependsOn[0]]?.dependsOn.isEmpty == true })
        let dependency = try #require(index.entryByID[dependent.dependsOn[0]])
        let store = RailNetworkStore()
        // Tiny budget: anything not protected is evicted after every batch.
        store.residentByteBudget = 1
        store.installDisplayManifest(manifest)
        return Fixture(store: store, index: index, dependent: dependent, dependency: dependency)
    }

    private func rect(lat: Double, lon: Double, span: Double = 0.2) -> MKMapRect {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: lat + span, longitude: lon - span))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: lat - span, longitude: lon + span))
        return MKMapRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    @Test func heldLinesLoadWithTheirDependenciesAndSurviveViewportMovesAndBudget() async throws {
        let f = try fixture()
        f.store.ensure(lineIDs: [f.dependent.id], owner: "rides", cameraZoom: 12)
        await f.store.waitForDisplayIdle()
        #expect(f.store.residentDisplayLineIDs.isSuperset(of: [f.dependent.id, f.dependency.id]))

        // Pan across two cities that have nothing to do with the held line,
        // with a one-byte budget: unheld lines are evicted, held ones stay.
        for (lat, lon) in [(35.68, 139.76), (34.70, 135.50)] {
            f.store.ensure(regionsIntersecting: rect(lat: lat, lon: lon), cameraZoom: 12)
            await f.store.waitForDisplayIdle()
            #expect(f.store.residentDisplayLineIDs.isSuperset(of: [f.dependent.id, f.dependency.id]))
        }
        #expect(f.store.evictedLineTotal > 0)
    }

    @Test func heldLinesFromARegionWithFailedHistoryDoNotLoad() async throws {
        let f = try fixture()
        f.store.displayHistoryFailures[f.dependent.region] = "history failed"
        f.store.ensure(lineIDs: [f.dependent.id], owner: "rides", cameraZoom: 12)
        await f.store.waitForDisplayIdle()
        #expect(f.store.residentDisplayLineIDs.isDisjoint(with: [f.dependent.id, f.dependency.id]))
    }

    @Test func releasingMakesLinesEvictable() async throws {
        let f = try fixture()
        f.store.ensure(lineIDs: [f.dependent.id], owner: "rides", cameraZoom: 12)
        await f.store.waitForDisplayIdle()
        f.store.release(owner: "rides")
        #expect(f.store.residentDisplayLineIDs.isDisjoint(with: [f.dependent.id, f.dependency.id]))
    }

    @Test func aLineIsKeptWhileAnyOwnerOrDependentStillHoldsIt() async throws {
        let f = try fixture()
        f.store.ensure(lineIDs: [f.dependency.id], owner: "a", cameraZoom: 12)
        f.store.ensure(lineIDs: [f.dependent.id], owner: "b", cameraZoom: 12)
        await f.store.waitForDisplayIdle()
        // The dependency's own holder leaves; the dependent still needs it.
        f.store.release(owner: "a")
        #expect(f.store.residentDisplayLineIDs.isSuperset(of: [f.dependent.id, f.dependency.id]))
        f.store.release(owner: "b")
        #expect(f.store.residentDisplayLineIDs.isDisjoint(with: [f.dependent.id, f.dependency.id]))
    }

    @Test func replacingAnOwnersSetReleasesWhatItNoLongerNames() async throws {
        let f = try fixture()
        f.store.ensure(lineIDs: [f.dependent.id], owner: "rides", cameraZoom: 12)
        await f.store.waitForDisplayIdle()
        let other = try #require(f.index.entriesByRegion["jp"]?.first {
            $0.dependsOn.isEmpty && $0.id != f.dependency.id && $0.chunk.length < 50_000
        })
        f.store.ensure(lineIDs: [other.id], owner: "rides", cameraZoom: 12)
        await f.store.waitForDisplayIdle()
        #expect(f.store.residentDisplayLineIDs.contains(other.id))
        // Not held any more; the next batch's eviction removes it.
        f.store.ensure(regionsIntersecting: rect(lat: 35.68, lon: 139.76), cameraZoom: 12)
        await f.store.waitForDisplayIdle()
        #expect(!f.store.residentDisplayLineIDs.contains(f.dependent.id))
    }

    @Test func fullDetailUpgradesAnOverviewHold() async throws {
        let f = try fixture()
        let entry = try #require(f.index.entriesByRegion["jp"]?.first {
            $0.overview != nil && $0.dependsOn.isEmpty && $0.chunk.length < 120_000
                && f.store.wantedDisplayDetail(lineID: $0.id, cameraZoom: 3) == .overview
        })
        f.store.ensure(lineIDs: [entry.id], owner: "rides", cameraZoom: 3)
        await f.store.waitForDisplayIdle()
        #expect(f.store.residentDisplayDetail(lineID: entry.id) == .overview)
        f.store.ensure(lineIDs: [entry.id], owner: "rides", cameraZoom: 3, fullDetail: true)
        await f.store.waitForDisplayIdle()
        #expect(f.store.residentDisplayDetail(lineID: entry.id) == .full)
    }

    @Test func unknownIDsAreIgnoredAndEmptySetReleases() async throws {
        let f = try fixture()
        f.store.ensure(lineIDs: ["no-such-line"], owner: "rides", cameraZoom: 12)
        await f.store.waitForDisplayIdle()
        #expect(f.store.residentDisplayLineIDs.isEmpty)
        f.store.ensure(lineIDs: [f.dependent.id], owner: "rides", cameraZoom: 12)
        await f.store.waitForDisplayIdle()
        f.store.ensure(lineIDs: [], owner: "rides", cameraZoom: 12)
        #expect(f.store.residentDisplayLineIDs.isDisjoint(with: [f.dependent.id]))
    }

    @Test func topologyIsAbsentWhenTheManifestNamesNone() throws {
        let f = try fixture()
        for record in f.index.recordsByRegion.values where record.topologyFile == nil {
            #expect(try RailDisplayNetwork.topology(record) == nil)
        }
    }

    /// RailKit's `topology-mini.bin` (region jp, display sha 0x22 x 32),
    /// embedded so the hosted test does not read the repository.
    private static let miniTopology = Data(base64Encoded:
        "SlRNVAEAoABqcAAAAAAAABERERERERERERERERERERERERERERERERERERERERERIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiLMAwAAAAAAAKAAAAACAAAAEAEAAAYAAAC4AQAABQAAADACAAAEAAAAgAIAAAIAAACwAgAAAQAAAMQCAAADAAAA9AIAAAQAAAAEAwAAxwAAAAIAAAANAAAAHQAAACwAAAABAAEAAAABAAAAAAAAAAAAAAAAAAMAAAAAAAAAAgAAAAAAAAABAAAAOQAAAEQAAABUAAAAAAAAAAIAAgAZAAIAnisBAOI5AQADAAAAAwAAAAIAAAADAAAAAQAAAAAAAABpAAAAAAAAAAAAAAAAAAtDAAAMQgAAAAAAAAAAbgAAAPBJAgDgIgIAjwILQwAADEIAAAAAAAAAAHMAAACyGgYA/////64HC0M9CgxCAAAAAAAAAAB4AAAAAAAAAAAAAACPAgtDAAAMQgEAAAAAAAAA/////1DDAACAuwAAHwULQwAADEIBAAAAAQAAAH0AAAAgTgAAOEoAAB8FC0N7FAxCAQABAAAAAADwSQIAAAAAAAAAAAAAAAAAAwAAAAAAAADC0AMA8EkCAJ4rAQAAAAAABQAAAAAAAABQwwAAAAAAAAAAAAAAAAAACwABAAAAAACQXwEAUMMAAAAAAAAAAAAACwACAAEAAAAwdQAA4CICAAAAAAAAAAAACwABAAMAAAAAAAAAAAAAAFDDAAAAAAAAgLsAAAAAAABQwwAAgDgBAIC7AADgKAEAAQAAAAAAAAAgTgAAAAAAADhKAAABAAAAIE4AAFDDAAA4SgAAmLcAAAEAAAADAAAAAQAAAJ4rAQAAAAAAggAAAAIAAAAFAAAAAgEAAAAAAAAAAAAAjgAAAAAAAACZAAAAqwAAACcLAQCeKwEAaQAAAAMAAQAAAAAAAQAAAHgAAAADAAEAAQAAAAEAAAC6AAAACwACAAIAAAACAAAAAAAAAAMAAAABAAAAAwAAAAAACQBqcC50ZXN0LWEOAHRlc3Qtb3AvdGVzdC1hDQDjg4bjgrnjg4hB57eaCwBB57eaH1Rlc3QgQQkAanAudGVzdC1iDgB0ZXN0LW9wL3Rlc3QtYhMA44OG44K544OIQueSsOeKtue3mgMAQTAxAwBBMDIDAEEwMwMAQjAxAwBCMDMKAGpjdC10ZXN0LTEJAHRzLXRlc3QtMRAA5pen44OG44K544OIQee3mg0AdGVzdC1vcC9vbGQtYQsAc3Q6dGVzdC1hMDIA")!

    /// Writes `data` as `{region}.topology.bin` into a throwaway bundle and returns
    /// the bundle with a record that describes it (correct size and digest).
    private func topologyBundle(
        data: Data, region: String, displaySHA256: String
    ) throws -> (Bundle, RailDisplayNetworkManifest.RegionRecord, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "com.jtm.topology-fixture", "CFBundleName": "T"],
            format: .xml, options: 0).write(to: root.appendingPathComponent("Info.plist"))
        let dir = root.appendingPathComponent("rail-display-network")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("\(region).topology.bin"))
        let record = try JSONDecoder().decode(
            RailDisplayNetworkManifest.RegionRecord.self,
            from: JSONSerialization.data(withJSONObject: [
                "region": region, "file": "\(region).display.bin", "bytes": 1, "sha256": displaySHA256,
                "minZoomMapLibre": 0, "topologyFile": "\(region).topology.bin",
                "topologyBytes": data.count,
                "topologySHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            ] as [String: Any]))
        #expect(record.hasConsistentTopologyFields)
        return (Bundle(url: root)!, record, root)
    }

    /// Size and digest match, so each of these reaches the format parser or
    /// the header checks rather than the integrity guard.
    @Test func aCorruptTopologyFileIsRejectedByTheFormatParser() throws {
        let (bundle, record, root) = try topologyBundle(
            data: Data(repeating: 7, count: 64), region: "jp",
            displaySHA256: String(repeating: "11", count: 32))
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) {
            _ = try RailDisplayNetwork.topology(record, bundle: bundle)
        }
    }

    @Test func aTopologyForAnotherRegionOrDisplayBlobIsRejected() throws {
        let good = String(repeating: "22", count: 32)
        let (okBundle, okRecord, okRoot) = try topologyBundle(
            data: Self.miniTopology, region: "jp", displaySHA256: good)
        defer { try? FileManager.default.removeItem(at: okRoot) }
        #expect(try RailDisplayNetwork.topology(okRecord, bundle: okBundle) != nil)

        let (wrongRegionBundle, wrongRegion, wrongRegionRoot) = try topologyBundle(
            data: Self.miniTopology, region: "kr", displaySHA256: good)
        defer { try? FileManager.default.removeItem(at: wrongRegionRoot) }
        do {
            _ = try RailDisplayNetwork.topology(wrongRegion, bundle: wrongRegionBundle)
            Issue.record("expected invalidRegionPayload")
        } catch RailDisplayNetworkError.invalidRegionPayload(let region) {
            #expect(region == "kr")
        }

        let (wrongShaBundle, wrongSha, wrongShaRoot) = try topologyBundle(
            data: Self.miniTopology, region: "jp",
            displaySHA256: String(repeating: "11", count: 32))
        defer { try? FileManager.default.removeItem(at: wrongShaRoot) }
        do {
            _ = try RailDisplayNetwork.topology(wrongSha, bundle: wrongShaBundle)
            Issue.record("expected invalidRegionPayload")
        } catch RailDisplayNetworkError.invalidRegionPayload(let region) {
            #expect(region == "jp")
        }
    }
}
