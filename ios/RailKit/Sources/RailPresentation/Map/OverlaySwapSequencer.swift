import Foundation

/// Sequencing for replacing the overlays of one geometry level with the next.
///
/// The old overlays stay on the map until every new overlay's renderer has
/// reported that it drew, or ``fallbackFrames`` display frames have passed
/// since the new overlays were added. The caller then removes all old
/// overlays in one run-loop turn, so the map never shows neither set nor a
/// partial mix. Pure and map-free so the rule is testable on the host.
public struct OverlaySwapSequencer: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        /// Keep the old overlays mounted.
        case holdOld
        /// Remove every old overlay now.
        case retireOld
    }

    /// Display frames after which the old overlays retire whether or not
    /// every new renderer reported a draw, so a renderer that never draws
    /// cannot pin the old geometry forever.
    public static let fallbackFrames = 2

    /// Keys of the new overlays whose renderer has not reported a draw yet.
    public private(set) var undrawn: Set<String>
    public private(set) var framesSinceAdded = 0

    public init(newKeys: some Sequence<String>) {
        undrawn = Set(newKeys)
    }

    /// A new overlay's renderer finished drawing.
    public mutating func reportDrawn(key: String) {
        undrawn.remove(key)
    }

    /// One display frame passed since the new overlays were added.
    public mutating func displayFrame() {
        framesSinceAdded += 1
    }

    public var decision: Decision {
        undrawn.isEmpty || framesSinceAdded >= Self.fallbackFrames ? .retireOld : .holdOld
    }
}
