#if DEBUG
import Foundation
import RailPresentation

/// Which ride store this DEBUG launch uses, chosen once at launch.
///
/// 1. `RAILMAP_UI_TEST_STORAGE_ID` (UI tests, `app-control.py launch`) wins.
/// 2. Otherwise the developer panel's persisted override: an isolated UUID
///    store picked from the ball's Tools, kept until switched back.
/// 3. Otherwise the real (shared) store.
///
/// The override is ignored for any launch that carries a UI-test key or
/// `RAILMAP_DEVTOOLS=0`, so harnesses that rely on the shared container
/// (`UITestLaunchConfiguration.Storage.existingContainer`) are not redirected.
/// Switching takes effect on the next launch: the stores are built once.
enum DevStorage {
    enum Source: String { case environment, devtools, real }

    static let overrideKey = "devtools.storageOverride"
    /// A command to run once the next launch has mounted (e.g. load samples
    /// into the fresh store the panel just switched to).
    static let pendingCommandKey = "devtools.pendingCommand"

    static let launch: (id: String?, source: Source) = {
        let environment = ProcessInfo.processInfo.environment
        if let value = UITestLaunchConfiguration.current[.storageId], UUID(uuidString: value) != nil {
            return (value, .environment)
        }
        let harness = environment.keys.contains { $0.hasPrefix("RAILMAP_UI_TEST_") }
            || environment["RAILMAP_DEVTOOLS"] == "0" || environment["XCTestConfigurationFilePath"] != nil
        if !harness, let value = UserDefaults.standard.string(forKey: overrideKey), UUID(uuidString: value) != nil {
            return (value, .devtools)
        }
        return (nil, .real)
    }()

    static var launchID: String? { launch.id }
    static var isReal: Bool { launch.id == nil }

    /// Persists the store for the NEXT launch; `nil` means the real store.
    static func setOverride(_ id: String?) {
        if let id { UserDefaults.standard.set(id, forKey: overrideKey) }
        else { UserDefaults.standard.removeObject(forKey: overrideKey) }
    }

    static var pendingOverride: String? { UserDefaults.standard.string(forKey: overrideKey) }

    static func setPendingCommand(_ request: AppControlRequest?) {
        if let request, let data = try? JSONEncoder().encode(request) {
            UserDefaults.standard.set(data, forKey: pendingCommandKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingCommandKey)
        }
    }

    /// Returns and clears the pending command, only on a devtools-chosen store.
    static func takePendingCommand() -> AppControlRequest? {
        guard let data = UserDefaults.standard.data(forKey: pendingCommandKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingCommandKey)
        guard launch.source == .devtools else { return nil }
        return try? JSONDecoder().decode(AppControlRequest.self, from: data)
    }
}
#endif
