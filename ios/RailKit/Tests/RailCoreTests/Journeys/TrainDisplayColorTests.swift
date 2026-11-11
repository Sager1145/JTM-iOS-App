import Testing

@testable import RailCore

struct TrainDisplayColorTests {
    private func train(color: String?) -> Train {
        var train = Train(
            id: "t", date: "2026-09-07", number: "1", origin: "A", destination: "B",
            stops: [Stop(name: "A", departure: "08:00"), Stop(name: "B", arrival: "09:00")])
        train.style = color.map { TrainStyle(color: $0) }
        return train
    }

    @Test("a stored colour is drawn, in the spellings the app has always drawn, else the default")
    func table() {
        let red = TrainValidation.defaultTrainColor
        #expect(red == "#d9364f")
        let rows: [(String?, String)] = [
            (nil, red), ("", red), ("red", red), ("#12345", red), ("#1234567", red),
            ("#12345g", red), ("+12345", red),
            ("#0A84FF", "#0A84FF"), ("#0a84ff", "#0a84ff"),
            ("d9364f", "#d9364f"), (" #0A84FF ", "#0A84FF"), ("\n#336699\n", "#336699"),
        ]
        for (stored, expected) in rows {
            #expect(train(color: stored).displayColorHex == expected, "\(stored ?? "nil")")
        }
        #expect(train(color: nil).displayColorHex == red)
    }

    @Test("the colour drawn before saving equals the colour after the export normaliser")
    func survivesNormalisation() {
        for stored in [nil, "", "red", "#12345", "#0A84FF", "d9364f", " #0A84FF "] {
            let before = train(color: stored)
            let after = TrainValidation.normalizeExportTrain(before)
            #expect(before.displayColorHex == after.displayColorHex, "\(stored ?? "nil")")
        }
    }
}
