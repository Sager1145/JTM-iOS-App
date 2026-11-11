import RailCore
import Testing
import UIKit
@testable import RailMap

/// The app-side half of the default trip colour: one red, pinned to RailCore.
struct TripColourTests {
    @Test func uiKitDefaultEqualsTheRailCoreDefault() throws {
        let expected = try #require(UIColor(railHex: TrainValidation.defaultTrainColor))
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        expected.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor.railDefaultTrip.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #expect(abs(r1 - r2) < 0.001 && abs(g1 - g2) < 0.001 && abs(b1 - b2) < 0.001)
        #expect(a1 == a2)
    }

    @Test func aStyleLessTripBrandsRed() {
        let train = Train(id: "t", number: "", origin: "", destination: "", stops: [], region: "jp")
        #expect(train.displayColorHex == "#d9364f")
    }
}
