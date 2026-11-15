import Foundation
import RailTestSupport
import Testing

/// An isolated launch must never touch the real route cache: nothing under
/// `ios/RailMap/Diagnostics` may build a `RailMap/Routes` path itself (it would
/// start from the user Caches directory); it asks `RiddenRouteStore.cachesBase`.
@Suite("RegressionGuardRouteCacheIsolation")
struct RegressionGuardRouteCacheIsolation {
    @Test func diagnosticsNeverBuildTheRoutesPathFromUserCaches() throws {
        let folder = SourceFiles.ios.appendingPathComponent("RailMap/Diagnostics")
        let walker = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(!source.contains("RailMap/Routes"), "\(url.lastPathComponent) builds RailMap/Routes itself; use RiddenRouteStore.cachesBase")
        }
        #expect(scanned > 0)
    }

    @Test func launchRedirectsTheCacheRootBeforeAnyStoreIsBuilt() throws {
        let app = try String(
            contentsOf: SourceFiles.ios.appendingPathComponent("RailMap/App/RailMapApp.swift"), encoding: .utf8)
        #expect(app.contains("RouteCachesRoot.resolve("))
        #expect(app.contains("setCacheRootForTesting("))
    }
}
