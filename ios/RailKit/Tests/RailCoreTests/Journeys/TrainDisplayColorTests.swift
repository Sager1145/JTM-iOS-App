import Foundation
import Testing

@testable import RailCore

/// `Train.displayColorHex` is the one colour every trip surface draws. The
/// default is the website's `DEFAULT_TRAIN_COLOR`; nothing draws blue.
struct TrainDisplayColorTests {
    private func train(color: String?) -> Train {
        var train = Train(id: "t", number: "", origin: "", destination: "", stops: [], region: "jp")
        if let color { train.style = TrainStyle(color: color) }
        return train
    }

    @Test func defaultIsTheWebsiteRed() {
        #expect(TrainValidation.defaultTrainColor == "#d9364f")
    }

    @Test(arguments: [
        (nil as String?, "#d9364f"),
        ("", "#d9364f"),
        ("red", "#d9364f"),
        ("#12345", "#d9364f"),
        ("d9364f", "#d9364f"),
        (" #0A84FF ", "#d9364f"),
        ("#0A84FF", "#0A84FF"),
        ("#00ff00", "#00ff00"),
    ])
    func table(stored: String?, expected: String) {
        #expect(train(color: stored).displayColorHex == expected)
    }

    /// The colour drawn in the session that created a trip equals the colour
    /// after save and relaunch (the export writes the default for a missing
    /// colour and keeps an invalid one).
    @Test(arguments: [nil as String?, "", "red", "#12345", "#0A84FF"])
    func stableAcrossSave(stored: String?) throws {
        let before = train(color: stored)
        let exported = TrainValidation.normalizeExportTrain(
            before, country: "jp", stations: .empty)
        let data = try JSONEncoder().encode(exported)
        let after = try JSONDecoder().decode(Train.self, from: data)
        #expect(before.displayColorHex == after.displayColorHex)
    }
}
