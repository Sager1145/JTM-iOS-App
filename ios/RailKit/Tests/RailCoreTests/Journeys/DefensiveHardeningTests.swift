import Foundation
import Testing

@testable import RailCore

/// Focused regression coverage for the overflow / recursion / duplicate-key /
/// large-batch hardening fixes: none of these should crash, and normal
/// inputs must keep behaving exactly as before.
@Suite("Defensive hardening")
struct DefensiveHardeningTests {

    // MARK: - V01: day-offset overflow

    @Test func hugeDayOffsetDoesNotCrashAndIsRejected() {
        let minutes = Dates.parseTimeToMinutes("10:00+999999999999999999999999")
        #expect(minutes == nil)
    }

    @Test func normalDayOffsetStillParses() {
        #expect(Dates.parseTimeToMinutes("10:00+1") == 2_040.0)
        #expect(Dates.parseTimeToMinutes("10:00") == 600.0)
    }

    @Test func dayOffsetPastCapIsRejected() {
        #expect(Dates.parseTimeToMinutes("10:00+\(Dates.maxDayOffset + 1)") == nil)
        #expect(Dates.parseTimeToMinutes("10:00+\(Dates.maxDayOffset)") != nil)
    }

    // MARK: - V02: JSON parser hardening

    @Test func deeplyNestedJSONThrowsNotCrashes() {
        let text = String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        #expect(throws: TrainValidation.ValidationError.self) {
            _ = try TrainValidation.JSON.parse(text)
        }
    }

    @Test func moderateNestingStillParses() throws {
        let depth = 50
        let text = String(repeating: "[", count: depth) + "1" + String(repeating: "]", count: depth)
        _ = try TrainValidation.JSON.parse(text)
    }

    /// The parser's own `Parser.maxNestingDepth` is `private` and 256; not
    /// referenceable from here, so the boundary is pinned by value instead —
    /// this test is the thing that has to change if that constant ever does.
    @Test func nestingAtCapParsesOneDeeperThrows() throws {
        let atCap = 256
        let okText = String(repeating: "[", count: atCap) + "1" + String(repeating: "]", count: atCap)
        _ = try TrainValidation.JSON.parse(okText)

        let overCap = atCap + 1
        let badText =
            String(repeating: "[", count: overCap) + "1" + String(repeating: "]", count: overCap)
        #expect(throws: TrainValidation.ValidationError.self) {
            _ = try TrainValidation.JSON.parse(badText)
        }
    }

    @Test func duplicateKeysStillResolveToLastValueFirstPosition() throws {
        let parsed = try TrainValidation.JSON.parse(#"{"a":1,"b":2,"a":3}"#)
        guard case .object(let object) = parsed else {
            Issue.record("expected an object")
            return
        }
        #expect(object.keys == ["a", "b"])
        #expect(object["a"] == .number(3))
        #expect(object["b"] == .number(2))
    }

    /// Duplicate-key resolution is UTF-16 code-unit equality
    /// (`jsStringEquals`), not Swift's canonically-equivalent `String ==` —
    /// precomposed "é" (U+00E9) and decomposed "é" (U+0065 U+0301) are the
    /// SAME string under `==` but different UTF-16 sequences, and JavaScript
    /// treats them as different object keys, so this parser must too.
    @Test func precomposedAndDecomposedKeysStayDistinct() throws {
        let precomposed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        let text = #"{"\#(precomposed)":1,"\#(decomposed)":2}"#
        let parsed = try TrainValidation.JSON.parse(text)
        guard case .object(let object) = parsed else {
            Issue.record("expected an object")
            return
        }
        #expect(object.keys.count == 2)
        #expect(object[precomposed] == .number(1))
        #expect(object[decomposed] == .number(2))
    }

    // MARK: - I01: appendImportedTrain over many rows

    @Test func appendImportedTrainProducesUniqueIdsOverManyRows() throws {
        var session = ImportEngine.Session(trains: [], selectedDate: "", country: "jp", stations: .empty)
        var ids: [String] = []
        for i in 0..<300 {
            let raw = try TrainValidation.JSON.parse(
                """
                {"id":"t\(i)","number":"N\(i)","origin":"A","destination":"B",
                 "stops":[{"name":"A"},{"name":"B"}]}
                """)
            ids.append(try session.appendImportedTrain(raw))
        }
        #expect(Set(ids).count == ids.count)
        #expect(session.trains.count == 300)
    }

    /// `trains`' `didSet` must invalidate the id cache on ANY external
    /// write, not just one that changes the count — otherwise a same-count
    /// reassignment (an edit, a fold) that swaps one id for another the
    /// cache has never seen leaves the stale cache in place, and the next
    /// `appendImportedTrain` fails to notice the collision it just created.
    @Test func externalEqualCountReassignmentInvalidatesIDCache() throws {
        var session = ImportEngine.Session(trains: [], selectedDate: "", country: "jp", stations: .empty)
        for i in 0..<2 {
            let raw = try TrainValidation.JSON.parse(
                """
                {"id":"t\(i)","number":"N\(i)","origin":"A","destination":"B",
                 "stops":[{"name":"A"},{"name":"B"}]}
                """)
            _ = try session.appendImportedTrain(raw)
        }
        // Same count as before (2), but done directly through `trains`
        // rather than `appendImportedTrain`, and the id at index 0 becomes
        // one the cache built above has never indexed.
        var external = session.trains
        external[0].id = "dup"
        session.trains = external

        let raw = try TrainValidation.JSON.parse(
            """
            {"id":"dup","number":"N9","origin":"A","destination":"B",
             "stops":[{"name":"A"},{"name":"B"}]}
            """)
        let newID = try session.appendImportedTrain(raw)
        #expect(newID != "dup")
        #expect(Set(session.trains.map(\.id)).count == session.trains.count)
    }
}
