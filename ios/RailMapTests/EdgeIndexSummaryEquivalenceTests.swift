import RailCore
import Testing
@testable import RailMap

/// The 全部 statistics index merges every region. Regions no ride can reach
/// now contribute only their denominators (no edges, no display package).
/// These tests pin that the reduced merge answers every question the
/// statistics ask exactly as the full merge does: the same totals and line
/// rows, and, for every edge a ride in the ridden regions could match, the
/// same edge (km, classification, line, validity) on every ride date.
@Suite(.serialized)
struct EdgeIndexSummaryEquivalenceTests {
    private let everything = StatisticsScope.everything.countries

    @Test func japanOnlyRidesMatchTheFullMerge() async throws {
        try await expectEquivalent(rideCountries: [Region.jp.code])
    }

    @Test func mixedRidesMatchTheFullMerge() async throws {
        try await expectEquivalent(rideCountries: [Region.jp.code, "hk"])
    }

    @Test func pearlRiverDeltaRegionsStayMatchableTogether() {
        let set = EdgeIndexCache.matchableCountries(rideCountries: ["hk"])
        #expect(set == ["hk", "cn", "mo"])
        #expect(EdgeIndexCache.matchableCountries(rideCountries: ["jp", "jp"]) == ["jp"])
    }

    private func expectEquivalent(rideCountries: Set<String>) async throws {
        let cache = EdgeIndexCache()
        let matchable = EdgeIndexCache.matchableCountries(rideCountries: rideCountries)
        let full = try await cache.merged(countries: everything)
        let reduced = try await cache.merged(countries: everything, matchable: matchable)

        // Denominators and line rows: identical, in the same order.
        #expect(reduced.totalKm == full.totalKm)
        #expect(reduced.totalsByMask == full.totalsByMask)
        #expect(reduced.lineTotByCat.pairs.map(\.key) == full.lineTotByCat.pairs.map(\.key))
        #expect(reduced.lineTotByCat.pairs.map(\.value) == full.lineTotByCat.pairs.map(\.value))
        #expect(reduced.lineOperator.pairs.map(\.key) == full.lineOperator.pairs.map(\.key))
        #expect(reduced.lineOperator.pairs.map(\.value) == full.lineOperator.pairs.map(\.value))
        #expect(reduced.km.count < full.km.count)

        // Every edge a ride in a matchable region can hit resolves the same.
        let dates: [String?] = [nil, "1990-01-01", "2010-06-15", "2026-11-05"]
        var checked = 0
        var mismatches = 0
        var riddenFull = [Int: Double]()
        var riddenReduced = [Int: Double]()
        for country in everything where matchable.contains(country) {
            let component = try await cache.index(country: country)
            for key in Set(component.map.keys).union(component.variants.keys) {
                checked += 1
                for date in dates {
                    let a = full.edgeID(for: key, on: date)
                    let b = reduced.edgeID(for: key, on: date)
                    guard let a, let b else {
                        if (a == nil) != (b == nil) { mismatches += 1 }
                        continue
                    }
                    if full.km[a] != reduced.km[b] || full.mask[a] != reduced.mask[b]
                        || full.lineName[a] != reduced.lineName[b]
                        || full.lineMask[a] != reduced.lineMask[b]
                        || full.temporalKind[a] != reduced.temporalKind[b]
                        || full.historyId[a] != reduced.historyId[b]
                        || full.currentNetwork[a] != reduced.currentNetwork[b]
                    { mismatches += 1 }
                    if date == nil {
                        riddenFull[full.mask[a], default: 0] += full.km[a]
                        riddenReduced[reduced.mask[b], default: 0] += reduced.km[b]
                    }
                }
            }
        }
        #expect(checked > 0)
        #expect(mismatches == 0)
        // A ride over every matchable edge: identical km by class and coverage.
        #expect(riddenReduced == riddenFull)
        let coverage = { (index: Statistics.EdgeIndex, km: [Int: Double]) in
            // Sorted: two equal dictionaries may iterate in different orders.
            km.sorted { $0.key < $1.key }.reduce(0) { $0 + $1.value } / index.totalKm
        }
        #expect(coverage(reduced, riddenReduced) == coverage(full, riddenFull))
    }
}
