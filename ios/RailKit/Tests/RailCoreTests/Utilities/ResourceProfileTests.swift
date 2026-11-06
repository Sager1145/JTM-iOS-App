import Foundation
import RailCore
import Testing

struct ResourceProfileTests {
    private static let gib: UInt64 = 1024 * 1024 * 1024

    @Test("tier selection by RAM, launch headroom and desktop host")
    func tierSelection() {
        // A 4 GB phone, a 6 GB phone (reports a little under 6 GiB), 8 GB.
        #expect(ResourceProfile.tier(physicalMemory: 4 * Self.gib, availableMemory: nil, isDesktop: false) == .compact)
        #expect(ResourceProfile.tier(physicalMemory: 5_400_000_000, availableMemory: nil, isDesktop: false) == .compact)
        #expect(ResourceProfile.tier(physicalMemory: 5_700_000_000, availableMemory: nil, isDesktop: false) == .large)
        #expect(ResourceProfile.tier(physicalMemory: 8 * Self.gib, availableMemory: 4 * Self.gib, isDesktop: false) == .large)
        // Little headroom at launch downgrades; 0 means "no limit reported".
        #expect(ResourceProfile.tier(physicalMemory: 8 * Self.gib, availableMemory: Self.gib, isDesktop: false) == .compact)
        #expect(ResourceProfile.tier(physicalMemory: 8 * Self.gib, availableMemory: 0, isDesktop: false) == .large)
        // A Mac is desktop whatever it reports.
        #expect(ResourceProfile.tier(physicalMemory: 4 * Self.gib, availableMemory: Self.gib, isDesktop: true) == .desktop)
    }

    @Test("compact keeps the historical limits; larger tiers raise them")
    func limitsPerTier() {
        let compact = ResourceProfile(tier: .compact)
        #expect(compact.regionalGraphNodeBudget == RouteGraph.regionalGraphNodeBudget)
        #expect(compact.regionalGraphLoadNodeBudget == RouteGraph.regionalGraphLoadNodeBudget)
        #expect(compact.trimsRegionalGraphsAfterEachRide)
        #expect(compact.countryCacheSlots == 1)
        #expect(compact.displayResidentByteBudget == 16 * 1024 * 1024)
        #expect(compact.geometryFrameCapacity == 5)
        #expect(compact.mapTripLimit == 500)

        let large = ResourceProfile(tier: .large)
        #expect(large.regionalGraphNodeBudget == 450_000)
        #expect(large.regionalGraphLoadNodeBudget == 900_000)
        #expect(!large.trimsRegionalGraphsAfterEachRide)
        #expect(large.countryCacheSlots == 2)
        #expect(large.displayResidentByteBudget == 48 * 1024 * 1024)
        #expect(large.geometryFrameCapacity == 16)
        #expect(large.mapTripLimit == 500)

        let desktop = ResourceProfile(tier: .desktop)
        #expect(desktop.regionalGraphNodeBudget == 450_000)
        #expect(desktop.regionalGraphLoadNodeBudget == 900_000)
        #expect(desktop.countryCacheSlots == 2)
        #expect(desktop.displayResidentByteBudget == 128 * 1024 * 1024)
        #expect(desktop.geometryFrameCapacity == 16)
        #expect(desktop.mapTripLimit == 1_500)
    }

    @Test("the detected profile is what current reports without an override")
    func detectedIsCurrent() {
        #expect(ResourceProfile.current == ResourceProfile.detected)
        #if os(macOS)
        #expect(ResourceProfile.detected.tier == .desktop)
        #endif
    }
}
