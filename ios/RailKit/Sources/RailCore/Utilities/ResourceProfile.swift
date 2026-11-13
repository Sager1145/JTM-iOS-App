import Foundation
#if os(iOS)
import os
#endif

/// How much working memory this device gives the app, decided once at launch.
///
/// Every cache and node budget that trades memory for rebuild time reads its
/// limit here, so a small phone keeps the historical limits and a device with
/// headroom keeps more resident instead of rebuilding it. ``compact`` is
/// exactly the pre-profile behaviour.
public struct ResourceProfile: Sendable, Equatable {
    public enum Tier: String, Sendable, CaseIterable {
        /// Under ~6 GB of RAM, or a large device whose launch-time headroom is
        /// already small. Today's limits.
        case compact
        /// A phone or iPad with 6 GB or more.
        case large
        /// Mac Catalyst / an iOS app on a Mac.
        case desktop
    }

    public let tier: Tier

    public init(tier: Tier) {
        self.tier = tier
    }

    // MARK: - selection

    /// Devices sold as "6 GB" report a little under 6 GiB; "4 GB" devices
    /// report under 4 GiB. Decimal 5.5 GB separates them with margin.
    public static let largeMemoryThresholdBytes: UInt64 = 5_500_000_000
    /// A large device that can already allocate less than this at launch is
    /// treated as compact: the per-process limit, not the RAM size, is what
    /// jetsam enforces.
    public static let minimumLargeAvailableBytes: UInt64 = 2 * 1024 * 1024 * 1024

    /// The tier for a device. `availableMemory` nil or 0 means unknown (no
    /// per-process limit reported), which does not downgrade.
    public static func tier(
        physicalMemory: UInt64, availableMemory: UInt64?, isDesktop: Bool
    ) -> Tier {
        if isDesktop { return .desktop }
        guard physicalMemory >= largeMemoryThresholdBytes else { return .compact }
        if let availableMemory, availableMemory > 0, availableMemory < minimumLargeAvailableBytes {
            return .compact
        }
        return .large
    }

    /// The profile measured from this process, once.
    public static let detected: ResourceProfile = {
        #if targetEnvironment(macCatalyst) || os(macOS)
        let isDesktop = true
        #else
        let isDesktop = ProcessInfo.processInfo.isiOSAppOnMac
        #endif
        #if os(iOS)
        let available = UInt64(os_proc_available_memory())
        #else
        let available: UInt64? = nil
        #endif
        return ResourceProfile(tier: tier(
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            availableMemory: available, isDesktop: isDesktop))
    }()

    private final class OverrideBox: @unchecked Sendable {
        let lock = NSLock()
        var profile: ResourceProfile?
    }
    private static let overrideBox = OverrideBox()

    /// The profile every budget reads: the injected override when one is
    /// set, otherwise ``detected``.
    public static var current: ResourceProfile {
        overrideBox.lock.withLock { overrideBox.profile } ?? detected
    }

    /// Injects a profile for tests and diagnostics; nil restores detection.
    /// Read sites capture the profile when they create their cache, so set
    /// this before the cache under test exists.
    public static func setOverride(_ profile: ResourceProfile?) {
        overrideBox.lock.withLock { overrideBox.profile = profile }
    }

    // MARK: - limits

    /// Steady-state resident regional-graph nodes of a bounded route-graph
    /// store. Compact keeps `REGIONAL_GRAPH_NODE_BUDGET`.
    public var regionalGraphNodeBudget: Int {
        tier == .compact ? RouteGraph.regionalGraphNodeBudget : 450_000
    }

    /// Transient regional-graph nodes while a load or interactive solve is
    /// running, and the bounded node cap of an app route-graph store.
    /// Compact keeps `REGIONAL_GRAPH_LOAD_NODE_BUDGET`.
    public var regionalGraphLoadNodeBudget: Int {
        tier == .compact ? RouteGraph.regionalGraphLoadNodeBudget : 900_000
    }

    /// Compact trims a route-graph store back to the steady budget after each
    /// resolved ride. Larger tiers keep the regions for the rest of the scope;
    /// the store's own bounded cap still holds, and the store is released with
    /// its scope.
    public var trimsRegionalGraphsAfterEachRide: Bool { tier == .compact }

    /// Completed country indexes kept by the statistics edge-index and solver
    /// input caches. The second slot never evicts Japan.
    public var countryCacheSlots: Int { tier == .compact ? 1 : 2 }

    /// Resident display-network chunk bytes before eviction starts.
    public var displayResidentByteBudget: Int {
        switch tier {
        case .compact: 16 * 1024 * 1024
        case .large: 48 * 1024 * 1024
        case .desktop: 128 * 1024 * 1024
        }
    }

    /// Bytes of prepared network geometry the unpinned zoom/era frames may
    /// hold between them (the current frame and one neighbour are exempt).
    public var geometryFrameByteCap: Int { tier == .compact ? 12 * 1024 * 1024 : 24 * 1024 * 1024 }
    /// Unpinned zoom/era frames kept besides the current one and the neighbour.
    public var geometryMaxUnpinnedFrames: Int { tier == .compact ? 1 : 2 }

    /// The most trips the map draws at once: 500 on every tier, Mac included.
    /// A fixed product limit, not a resource tier choice.
    public static let mapTripLimit = 500
}
