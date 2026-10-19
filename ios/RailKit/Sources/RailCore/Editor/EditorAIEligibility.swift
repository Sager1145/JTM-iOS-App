import Foundation

public enum EditorAIDenial: Hashable, Sendable {
    case noResolvedStation
    case noExplicitTime
    case invalidTime
    case timeNotOnThatStation
    case providerUnavailable
    case requestInFlight
}

