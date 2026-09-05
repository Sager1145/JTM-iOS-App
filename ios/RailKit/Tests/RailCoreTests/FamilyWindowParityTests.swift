import Foundation
import Testing

@testable import RailCore

/// The family-collapse window partition `RailMapView.swift`'s
/// `continuousStrokeBuild` applies, against `port-fixtures/family-
/// windows.json` (the web agent's fixture, describing `rail-network.js`
/// `familyWindowRowsByPart` and `railmap.js`'s own family-window slicing).
///
/// `continuousStrokeBuild` itself lives in the `RailMap` app target, not in
/// `RailCore`, so it cannot be called directly from here. What IS in
/// `RailCore` — and is what `continuousStrokeBuild` now calls, replacing the
/// inline partition this suite used to hand-mirror — is
/// `ContinuousStroke.familyPartition(totalMetres:tenantWindows:landlordWindows:measureStart:measureEnd:)`:
/// BASE pieces cover the complement of every tenant ∪ landlord window, in
/// this line's own colour; a FAMILY piece covers each landlord window, in
/// the shared group's colour; a tenant window is drawn by neither.
/// `partition(...)` below calls that PRODUCTION function directly (merging
/// its `base`/`family` results back into the fixture's own flat, sorted
/// piece shape) and checks the answer against the fixture's own
/// `emittedPieces` — same boundaries, same colour keys — then confirms
/// `ContinuousStroke.slice` actually slices a non-empty, correctly-ordered
/// run at each of those boundaries.
///
/// The fixture's own emission keeps a piece even where it is zero-length
/// (the terminal boundary marker after a part-covering tenant window, for
/// instance) — evidence the boundary walk closed correctly, though nothing
/// draws from it either side. `continuousStrokeBuild` does not emit those
/// (`ContinuousStroke.slice` would hand back nothing for them regardless),
/// so both sides are compared with degenerate (sub-millimetre) pieces
/// dropped first.
struct FamilyWindowParityTests {

    // MARK: - the fixture

    struct WindowSpan: Decodable {
        let from: Double
        let to: Double
        let groupId: String
    }

    struct EmittedPiece: Decodable {
        let feature: String
        let from: Double
        let to: Double
        let colorKey: String
        let groupId: String?
    }

    struct Case: Decodable {
        let label: String
        let lineId: String
        let partIndex: Int
        let totalMetres: Double
        let familyWindows: [WindowSpan]
        let tenantWindows: [WindowSpan]
        let hasFamilyFeature: Bool
        let baseColor: String
        let familyColor: String?
        let emittedPieces: [EmittedPiece]
    }

    struct Fixture: Decodable {
        let cases: [Case]
    }

    static func fixtureURL() -> URL? {
        guard let root = try? PortFixtures.repositoryRoot() else { return nil }
        return root.appending(path: "port-fixtures/family-windows.json")
    }

    static func fixtureExists() -> Bool {
        guard let url = fixtureURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Pieces shorter than this are the fixture's own boundary bookkeeping
    /// (see the type's doc comment), not something either app ever draws.
    static let degenerateMetres = 1e-6

    // MARK: - the partition under test

    struct Piece {
        let feature: String
        let from: Double
        let to: Double
        let colorKey: String
    }

    /// Calls the PRODUCTION partition — `ContinuousStroke.familyPartition`
    /// (`ios/RailKit/Sources/RailCore/ContinuousStroke.swift`), the same
    /// function `continuousStrokeBuild`'s family-window branch
    /// (`ios/RailMap/RailMapView.swift`) now calls instead of hand-mirroring
    /// — and reshapes its `{base, family}` result back into the fixture's
    /// own flat, sorted piece list: a BASE piece in this line's own colour,
    /// a FAMILY piece in the shared group's colour, a tenant window drawn by
    /// neither. A landlord window with no resolved `familyColor` (this
    /// line's family feature does not exist) contributes no piece at all,
    /// same as `continuousStrokeBuild`'s own guard.
    static func partition(
        familyWindows: [WindowSpan], tenantWindows: [WindowSpan],
        baseColor: String, familyColor: String?, total: Double
    ) -> [Piece] {
        let landlordSpans = familyWindows.map {
            ContinuousStroke.WindowSpan(from: $0.from, to: $0.to, groupID: $0.groupId)
        }
        let tenantSpans = tenantWindows.map {
            ContinuousStroke.WindowSpan(from: $0.from, to: $0.to, groupID: $0.groupId)
        }
        let result = ContinuousStroke.familyPartition(
            totalMetres: total, tenantWindows: tenantSpans, landlordWindows: landlordSpans,
            measureStart: 0, measureEnd: total)
        var pieces = result.base.map { Piece(feature: "base", from: $0.from, to: $0.to, colorKey: baseColor) }
        if let familyColor {
            pieces += result.family.map { Piece(feature: "family", from: $0.from, to: $0.to, colorKey: familyColor) }
        }
        return pieces.sorted { $0.from < $1.from }
    }

    // MARK: - the test

    @Test(.disabled(
        if: !FamilyWindowParityTests.fixtureExists(),
        "port-fixtures/family-windows.json is absent — skipping FamilyWindowParityTests until the web agent registers it"
    ))
    func partitionMatchesTheWebFixture() throws {
        guard let url = Self.fixtureURL() else {
            Issue.record("could not locate the repository root for port-fixtures/")
            return
        }
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        #expect(!fixture.cases.isEmpty, "family-windows.json fixture has no cases")

        for testCase in fixture.cases {
            let computed = Self.partition(
                familyWindows: testCase.familyWindows, tenantWindows: testCase.tenantWindows,
                baseColor: testCase.baseColor, familyColor: testCase.familyColor,
                total: testCase.totalMetres
            ).filter { $0.to - $0.from > Self.degenerateMetres }
            let expected = testCase.emittedPieces
                .filter { $0.to - $0.from > Self.degenerateMetres }

            #expect(
                computed.count == expected.count,
                "\(testCase.label): expected \(expected.count) drawn pieces, got \(computed.count)")
            for (index, (got, want)) in zip(computed, expected).enumerated() {
                #expect(
                    got.feature == want.feature,
                    "\(testCase.label) piece \(index): feature \(got.feature) != \(want.feature)")
                #expect(
                    abs(got.from - want.from) <= 0.05,
                    "\(testCase.label) piece \(index): from \(got.from) != \(want.from)")
                #expect(
                    abs(got.to - want.to) <= 0.05,
                    "\(testCase.label) piece \(index): to \(got.to) != \(want.to)")
                #expect(
                    got.colorKey == want.colorKey,
                    "\(testCase.label) piece \(index): colorKey \(got.colorKey) != \(want.colorKey)")
            }

            // The primitive both apps actually draw with: every surviving
            // boundary slices to a real, correctly-ordered run over a
            // synthetic stroke spanning the same measure range. This is
            // about the partition's boundaries and `ContinuousStroke.slice`'s
            // own correctness at them — a specific line's own projected
            // geometry is `ContinuousStrokeParityTests`'s job, not this
            // suite's.
            // One sample roughly every 50 m, capped: enough resolution to
            // exercise `slice`'s interior interpolation without allocating
            // one point per metre of a 160 km corridor.
            let sampleCount = min(2000, max(2, Int(testCase.totalMetres / 50) + 1))
            let points = (0..<sampleCount).map { ContinuousStroke.Point(x: Double($0), y: 0) }
            let measures = (0..<sampleCount).map {
                testCase.totalMetres * Double($0) / Double(sampleCount - 1)
            }
            for piece in computed {
                let sliced = ContinuousStroke.slice(
                    points: points, measures: measures, from: piece.from, to: piece.to)
                #expect(
                    sliced.count >= 2,
                    "\(testCase.label): piece \(piece.from)…\(piece.to) sliced to fewer than 2 points")
            }
        }
    }
}
