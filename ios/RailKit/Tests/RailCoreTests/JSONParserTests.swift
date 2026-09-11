import Testing

@testable import RailCore

@Suite("JSON parser lexical grammar")
struct JSONParserTests {
    @Test("legal JSON numbers retain JavaScript number semantics")
    func legalNumbers() throws {
        let cases: [(text: String, expected: Double)] = [
            ("0", 0),
            ("-0", -0.0),
            ("42", 42),
            ("-42", -42),
            ("0.5", 0.5),
            ("-0.5", -0.5),
            ("1e3", 1_000),
            ("1E+3", 1_000),
            ("1e-3", 0.001),
            ("10.25E-2", 0.1025),
            ("1e400", .infinity),
            ("-1e400", -.infinity),
        ]

        for testCase in cases {
            guard case .number(let actual) = try TrainValidation.JSON.parse(testCase.text) else {
                Issue.record("\(testCase.text) did not parse as a number")
                continue
            }
            #expect(actual.bitPattern == testCase.expected.bitPattern, "\(testCase.text)")
        }
    }

    @Test("numbers stop at JSON structural delimiters")
    func numbersInsideContainers() throws {
        let parsed = try TrainValidation.JSON.parse(
            """
            {"values":[0,-1,2.5,3e2],"after":true}
            """)

        #expect(parsed.canonicalText == "{\"after\":true,\"values\":[0,-1,2.5,300]}")
    }

    @Test("forms outside the JSON number grammar are rejected")
    func malformedNumbers() {
        for text in [
            "01", "-01", "00", ".5", "-.5", "1.", "-1.",
            "1.e2", "1e", "1E", "1e+", "1e-", "+1", "--1",
        ] {
            expectSyntaxError(text)
        }
    }

    @Test("JSON string escapes and Unicode remain accepted")
    func legalStrings() throws {
        let text = "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0041\\uD83D\\uDE84\""
        let expected = "\"\\/\u{08}\u{0C}\n\r\tA🚄"

        #expect(try TrainValidation.JSON.parse(text) == .string(expected))
        #expect(try TrainValidation.JSON.parse("\"日本語🚄\"") == .string("日本語🚄"))
    }

    @Test("unescaped C0 controls are rejected inside strings", arguments: Array(0...31))
    func rawControlCharacters(codePoint: Int) {
        let control = String(UnicodeScalar(codePoint)!)
        expectSyntaxError("\"before\(control)after\"")
    }

    private func expectSyntaxError(_ text: String) {
        do {
            _ = try TrainValidation.JSON.parse(text)
            Issue.record("accepted invalid JSON: \(text.debugDescription)")
        } catch let error as TrainValidation.ValidationError {
            #expect(error.kind == .syntaxError)
        } catch {
            Issue.record("wrong error for \(text.debugDescription): \(error)")
        }
    }
}
