import Testing

@testable import RailCore

/// Coverage is expressed on the tenant's ruler after resolving reviewed follows.
/// It describes family ink actually selected for drawing, not resident data.
struct FamilyInkOwnershipTests {
    typealias Window = ContinuousStroke.WindowSpan

    private let tenant = Window(from: 20, to: 80, groupID: "shared")

    @Test func absentLandlordLeavesAContinuousTenantFallback() {
        let fallback = ContinuousStroke.familyFallbackWindows(
            tenantWindows: [tenant], drawnLandlordCoverage: [])

        #expect(fallback == [tenant])
        let stroke = [ContinuousStroke.Point(x: 0, y: 0), .init(x: 100, y: 0)]
        let base = ContinuousStroke.familyPartition(
            totalMetres: 100, tenantWindows: [tenant], landlordWindows: []).base
        let baseRuns = base.map {
            ContinuousStroke.slice(points: stroke, measures: [0, 100], from: $0.from, to: $0.to)
        }
        let fallbackRuns = fallback.map {
            ContinuousStroke.slice(points: stroke, measures: [0, 100], from: $0.from, to: $0.to)
        }
        #expect(fallbackRuns.count == 1)
        #expect(baseRuns.first?.last == fallbackRuns.first?.first)
        #expect(fallbackRuns.last?.last == baseRuns.last?.first)
    }

    @Test func drawnOwnerSuppressesDuplicateTenantInk() {
        #expect(ContinuousStroke.familyFallbackWindows(
            tenantWindows: [tenant], drawnLandlordCoverage: [tenant]).isEmpty)
    }

    @Test func partialOwnerCoverageRestoresOnlyTheMissingStretch() {
        #expect(ContinuousStroke.familyFallbackWindows(
            tenantWindows: [tenant],
            drawnLandlordCoverage: [.init(from: 40, to: 80, groupID: "shared")])
            == [.init(from: 20, to: 40, groupID: "shared")])
    }

    @Test func unrelatedFamilyOrDisjointOwnerCannotSuppressFallback() {
        #expect(ContinuousStroke.familyFallbackWindows(
            tenantWindows: [tenant], drawnLandlordCoverage: [
                .init(from: 20, to: 80, groupID: "other"),
                .init(from: 85, to: 95, groupID: "shared"),
            ]) == [tenant])
    }

    @Test func reviewedFollowMapsSelectedOwnerInkOntoTenantRuler() {
        let coverage = ContinuousStroke.mappedFamilyCoverage(
            ownerWindows: [.init(from: 110, to: 130, groupID: "shared")],
            from: 20, to: 80, canonicalFrom: 100, canonicalTo: 140)
        #expect(coverage == [.init(from: 35, to: 65, groupID: "shared")])
        #expect(ContinuousStroke.familyFallbackWindows(
            tenantWindows: [tenant], drawnLandlordCoverage: coverage)
            == [.init(from: 20, to: 35, groupID: "shared"),
                .init(from: 65, to: 80, groupID: "shared")])
    }

    @Test func reversedReviewedFollowClipsOwnerInkBeforeMapping() {
        let coverage = ContinuousStroke.mappedFamilyCoverage(
            ownerWindows: [.init(from: 110, to: 160, groupID: "shared")],
            from: 20, to: 80, canonicalFrom: 140, canonicalTo: 100)
        #expect(coverage == [.init(from: 20, to: 65, groupID: "shared")])
        #expect(ContinuousStroke.familyFallbackWindows(
            tenantWindows: [tenant], drawnLandlordCoverage: coverage)
            == [.init(from: 65, to: 80, groupID: "shared")])
    }

    @Test func partialFallbackKeepsOriginalViewportChunkBudget() {
        let points = (0...384).map { ContinuousStroke.Point(x: Double($0), y: 0) }
        let measures = (0...384).map(Double.init)
        let chunks = ContinuousStroke.measuredSliceChunks(
            points: points, measures: measures, from: 0, to: 384)
        #expect(chunks.map { ContinuousStroke.Interval(from: $0.from, to: $0.to) }
            == [.init(from: 0, to: 128), .init(from: 128, to: 256), .init(from: 256, to: 384)])
        let ranges = ContinuousStroke.intersectingChunkRanges(
            ranges: [.init(from: 100, to: 384)],
            chunks: chunks.map { .init(from: $0.from, to: $0.to) })
        let visible = ranges.filter { $0.from <= 240 && $0.to >= 200 }
        #expect(visible == [.init(from: 128, to: 256)])
        let submitted = visible.reduce(0) {
            $0 + ContinuousStroke.slice(points: points, measures: measures, from: $1.from, to: $1.to).count
        }
        #expect(submitted == 129)
        #expect(submitted <= 137)
    }

    @Test func croppedLandlordChunkDoesNotClaimSiblingWindowCoverage() {
        let tenant = Window(from: 0, to: 300, groupID: "shared")
        // Only the second chunk survived viewport selection. The first
        // landlord window has no selected ink, despite sharing its group.
        let retained = [Window(from: 200, to: 300, groupID: "shared")]
        #expect(ContinuousStroke.familyFallbackWindows(
            tenantWindows: [tenant], drawnLandlordCoverage: retained)
            == [.init(from: 0, to: 200, groupID: "shared")])
    }
}
