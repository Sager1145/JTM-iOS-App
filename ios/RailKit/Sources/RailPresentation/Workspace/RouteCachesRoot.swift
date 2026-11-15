import Foundation

/// Which folder the solved-route caches live under for one launch.
///
/// A launch on isolated ride storage (`RAILMAP_UI_TEST_STORAGE_ID`, or the
/// developer panel's isolated store) keeps its caches beside its rides, so it
/// starts genuinely cold and can never read, pollute or wipe the real app's
/// cache. A normal launch uses the user's Caches directory unchanged.
public enum RouteCachesRoot {
    /// The folder the isolated store with `storageID` keeps its derived caches in.
    public static func isolatedRoot(storageID: String, applicationSupport: URL) -> URL {
        applicationSupport
            .appending(path: "UITestStores/\(storageID)/Caches", directoryHint: .isDirectory)
    }

    /// `storageID` is `nil` for the real store.
    public static func resolve(storageID: String?, applicationSupport: URL, userCaches: URL) -> URL {
        guard let storageID else { return userCaches }
        return isolatedRoot(storageID: storageID, applicationSupport: applicationSupport)
    }
}
