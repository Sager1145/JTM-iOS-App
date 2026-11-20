import Foundation
import RailTestSupport
import Testing

/// `RailDisplayNetwork.closure` runs on the main thread several times per
/// `activateDisplayLines` call. It must walk only regions that hold a
/// selected line; walking every manifest region (the disabled China region's
/// line list is most of the manifest) cost 40 ms in one window. The
/// behavioural equality test is `RegressionGuardDisplayClosureBehaviourTests`
/// in `RailMapTests`.
@Suite("RegressionGuardDisplayClosure")
struct RegressionGuardDisplayClosure {
    @Test("closure walks only regions that hold a selected line")
    func closureWalksOnlySelectedRegions() throws {
        let text = try SourceFiles.text("RailMap/Infrastructure/Network/RailDisplayNetwork.swift")
        let start = try #require(text.range(of: "static func closureScanningRegions("))
        let tail = String(text[start.lowerBound...])
        let end = try #require(tail.range(of: "static func popup("))
        let body = String(tail[..<end.lowerBound])
        #expect(body.contains("where selectedRegions.contains(region)"),
                "closure must skip regions with no selected line")
        #expect(!body.contains("index.orderedRegions.flatMap"),
                "closure must not filter every region's entries")
    }
}
