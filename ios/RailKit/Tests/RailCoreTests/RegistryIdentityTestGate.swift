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

    static func withPhase<T>(
        _ provider: @escaping RegistryIdentityLookup.PhaseProvider,
        _ body: () throws -> T
    ) rethrows -> T {
        try RegistryIdentityLookup.withTestPhase(provider, operation: body)
    }

    static func withPhase<T: Sendable>(
        _ provider: @escaping RegistryIdentityLookup.PhaseProvider,
        _ body: nonisolated(nonsending) @Sendable () async throws -> T
    ) async rethrows -> T {
        try await RegistryIdentityLookup.withTestPhase(provider, operation: body)
    }
}
