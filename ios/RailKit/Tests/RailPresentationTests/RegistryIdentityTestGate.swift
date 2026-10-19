import Foundation
import RailCore

/// Serializes tests that install the process-global registry lookup.
enum RegistryIdentityTestGate {
    private static let lock = NSLock()

    static func withProvider<T>(
        _ provider: @escaping RegistryIdentityLookup.Provider,
        _ body: () throws -> T
    ) rethrows -> T {
        lock.lock()
        RegistryIdentityLookup.install(provider)
        defer {
            RegistryIdentityLookup.install(nil)
            lock.unlock()
        }
        return try body()
    }
}
