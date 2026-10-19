import Foundation
import RailCore

/// Installs a task-local registry lookup so parallel tests keep the process-wide one unset.
enum RegistryIdentityTestGate {
    static func withProvider<T>(
        _ provider: @escaping RegistryIdentityLookup.Provider,
        _ body: () throws -> T
    ) rethrows -> T {
        try RegistryIdentityLookup.withTestProvider(provider, operation: body)
    }
}
