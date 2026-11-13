import Foundation
import Testing
@testable import RailPresentation

@Suite("RouteCachesRoot")
struct RouteCachesRootTests {
    private let support = URL(fileURLWithPath: "/app/Support", isDirectory: true)
    private let caches = URL(fileURLWithPath: "/user/Caches", isDirectory: true)

    @Test func isolatedLaunchUsesAFolderUnderItsStorageRoot() {
        let root = RouteCachesRoot.resolve(storageID: "ABC", applicationSupport: support, userCaches: caches)
        #expect(root.path == "/app/Support/UITestStores/ABC/Caches")
        #expect(!root.path.hasPrefix(caches.path))
    }

    @Test func normalLaunchUsesTheUserCachesUnchanged() {
        let root = RouteCachesRoot.resolve(storageID: nil, applicationSupport: support, userCaches: caches)
        #expect(root == caches)
    }
}
