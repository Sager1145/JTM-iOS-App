import Foundation
import RailCore
import Testing
@testable import RailMap

/// Launch indexes journey badges from the display-network manifest instead of
/// scanning every package's line headers (audit A7). The badges must not move:
/// for every shipped region the manifest's attributes, and the index built
/// from them, equal what the package scan produces.
@Suite(.serialized)
struct RouteBadgeIndexManifestParityTests {

    @Test func manifestBadgeIndexEqualsPackageScanForEveryRegion() throws {
        let manifest = try RailDisplayNetwork.manifest()
        var scannedAll = RouteBadgeIndex()
        var manifestAll = RouteBadgeIndex()
        for region in Region.ordered {
            let url = try #require(Bundle.main.url(
                forResource: region.packageResource, withExtension: "json"))
            let headers = try CompactPackage.Headers.load(contentsOf: url)
            let sources = try #require(
                manifest.badgeSources(region: region.code),
                "manifest carries no badge attributes for \(region.code)")
            let scannedSources = headers.lines.map(RouteBadgeIndex.Source.init(header:))
            #expect(sources.count == scannedSources.count, "\(region.code) line count")
            for (left, right) in zip(sources, scannedSources) where left != right {
                Issue.record("\(region.code): manifest \(left) != package \(right)")
            }
            let fromManifest = RouteBadgeIndex(region: region, lines: sources)
            let fromScan = RouteBadgeIndex(region: region, headers: headers)
            #expect(fromManifest == fromScan, "\(region.code) badge index")
            scannedAll.merge(fromScan)
            manifestAll.merge(fromManifest)
        }
        #expect(manifestAll == scannedAll)
    }

    /// Not an assertion — the before/after cost of the launch index on this
    /// host, printed for the record. "Before" is the package scan the store
    /// used to run per region; "after" is the projection out of an already
    /// decoded manifest (launch decodes it for the map either way).
    @Test func reportIndexingCost() throws {
        let clock = ContinuousClock()
        var manifest: RailDisplayNetworkManifest?
        let manifestDecode = clock.measure { manifest = try? RailDisplayNetwork.manifest() }
        let decoded = try #require(manifest)
        var scanTotal = Duration.zero
        var manifestTotal = Duration.zero
        for region in Region.ordered {
            let url = try #require(Bundle.main.url(
                forResource: region.packageResource, withExtension: "json"))
            var scanned = RouteBadgeIndex()
            let scan = try clock.measure {
                scanned = RouteBadgeIndex(
                    region: region, headers: try CompactPackage.Headers.load(contentsOf: url))
            }
            var projected = RouteBadgeIndex()
            let fromManifest = try clock.measure {
                projected = RouteBadgeIndex(
                    region: region,
                    lines: try #require(decoded.badgeSources(region: region.code)))
            }
            #expect(scanned == projected)
            scanTotal += scan
            manifestTotal += fromManifest
            print("A7 badge index \(region.code): scan \(scan) manifest \(fromManifest)")
        }
        print("A7 badge index total: scan \(scanTotal) manifest \(manifestTotal); "
            + "manifest decode (shared with the map) \(manifestDecode)")
    }
}
