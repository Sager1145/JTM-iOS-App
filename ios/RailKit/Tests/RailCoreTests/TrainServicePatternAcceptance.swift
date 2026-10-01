import Foundation

/// Shared judgments for the service-pattern acceptance report.
///
/// Case identity is `patternId|rideDate|direction|variant`. A second direction
/// or date must not replace another case. `runComplete` is true only when the
/// recorded case keys equal the expected set.
enum TrainServicePatternAcceptance {
    static let historicalUnverified =
        "unverified: dated connectivity does not establish exact historical via"
    static let viaUnverified = "unverified: catalog has no per-leg evidence/constraints"
    static let variantDefault = "default"

    struct CaseKey: Hashable, Sendable {
        var patternId: String
        var rideDate: String
        var direction: String
        var variant: String

        var storageKey: String {
            "\(patternId)|\(rideDate)|\(direction)|\(variant)"
        }
    }

    struct Ledger {
        private(set) var cases: [String: [String: Any]] = [:]

        mutating func record(storageKey: String, result: [String: Any]) {
            cases[storageKey] = result
        }

        func runComplete(expected: Set<String>) -> Bool {
            !expected.isEmpty && Set(cases.keys) == expected
        }
    }

    static func rideDateKey(validityComplete: Bool, hasSource: Bool, validFrom: String?) -> String {
        if validityComplete, hasSource, let validFrom, !validFrom.isEmpty {
            return validFrom
        }
        return "undated"
    }

    static func expectedCaseKeys(_ patterns: [(id: String, rideDate: String)]) -> Set<String> {
        Set(patterns.flatMap { pattern in
            ["forward", "reverse"].map { direction in
                CaseKey(
                    patternId: pattern.id, rideDate: pattern.rideDate,
                    direction: direction, variant: variantDefault
                ).storageKey
            }
        })
    }

    /// The saved identity remains the fixed directory code. A solved N02
    /// membership may carry a different line/operator code only after the
    /// station index proves it is the same physical station; a name or nearby
    /// platform alone never satisfies this contract.
    static func referenceIntegrity(
        expectedCode: String, actualCode: String?, sameStationIdentity: Bool = false
    ) -> String {
        guard !expectedCode.isEmpty, actualCode != nil,
              actualCode == expectedCode || sameStationIdentity
        else { return "failed" }
        return "passed"
    }

    /// An empty solve on a dated, non-exempt leg is a route failure.
    /// Missing date evidence stays unverified instead of becoming a pass.
    static func routeConnectivity(
        hasRideDate: Bool, failedLegCount: Int, unsolvableLegCount: Int
    ) -> String {
        guard hasRideDate else { return "unverified" }
        if failedLegCount > 0 { return "failed" }
        if unsolvableLegCount > 0 { return "incomplete" }
        return "passed"
    }

    static func historicalCorrectness(independentEvidenceMatches: Bool) -> String {
        independentEvidenceMatches ? "passed" : historicalUnverified
    }

    static func patternRollup(_ directions: [String: [String: Any]]) -> [String: Any] {
        let ordered = ["forward", "reverse"].compactMap { directions[$0] }
        func strings(_ key: String) -> [String] {
            ordered.flatMap { $0[key] as? [String] ?? [] }
        }
        func statuses(_ key: String) -> [String] {
            ordered.compactMap { $0[key] as? String }
        }
        var merged: [String: Any] = [:]
        merged["failed"] = strings("failed")
        merged["unresolvedReferences"] = strings("unresolvedReferences")
        merged["saveReopenFailures"] = strings("saveReopenFailures")
        merged["legs"] = ordered.reduce(0) { $0 + int($1["legs"]) }
        merged["attemptedLegs"] = ordered.reduce(0) { $0 + int($1["attemptedLegs"]) }
        merged["unsolvable"] = ordered.reduce(0) { $0 + int($1["unsolvable"]) }
        merged["solvedLegs"] = ordered.flatMap { $0["solvedLegs"] as? [[String: Any]] ?? [] }
        merged["seconds"] = ordered.reduce(0.0) { $0 + double($1["seconds"]) }
        merged["referenceIntegrity"] = rollupStatus(statuses("referenceIntegrity"))
        merged["routeConnectivity"] = rollupStatus(statuses("routeConnectivity"))
        merged["historicalCorrectness"] = rollupHistorical(statuses("historicalCorrectness"))
        merged["viaCorrectness"] = rollupHistorical(statuses("viaCorrectness"))
        merged["saveReopenConsistency"] = rollupStatus(statuses("saveReopenConsistency"))
        merged["dateApplicability"] = rollupApplicability(statuses("dateApplicability"))
        merged["structuralIntegrity"] = rollupStatus(statuses("structuralIntegrity"))
        if let testDate = ordered.compactMap({ $0["testDate"] }).first {
            merged["testDate"] = testDate
        }
        if let dateSource = ordered.compactMap({ $0["dateSource"] }).first {
            merged["dateSource"] = dateSource
        }
        return merged
    }

    /// Writes a complete document, replacing any previous file only after the
    /// new bytes are durable. A failed write leaves the previous file unchanged,
    /// and that previous file is not acceptable for the new `runId`.
    static func write(document: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: [.atomic])
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    static func caseObject(_ cases: [String: [String: Any]]) -> [String: Any] {
        var object: [String: Any] = [:]
        for (key, value) in cases {
            object[key] = value
        }
        return object
    }

    static func accepts(document: [String: Any], runId: String, expectedCaseKeys: Set<String>) -> Bool {
        guard let metadata = document["_metadata"] as? [String: Any],
              metadata["runId"] as? String == runId,
              bool(metadata["runComplete"]) == true,
              let cases = document["_cases"] as? [String: Any] else { return false }
        return Set(cases.keys) == expectedCaseKeys
    }

    private static func rollupStatus(_ values: [String]) -> String {
        if values.contains("failed") { return "failed" }
        if values.contains("incomplete") { return "incomplete" }
        if values.contains("unverified") || values.isEmpty { return "unverified" }
        return values.allSatisfy { $0 == "passed" } ? "passed" : "unverified"
    }

    private static func rollupApplicability(_ values: [String]) -> String {
        if values.contains("unverified") || values.isEmpty { return "unverified" }
        return values.allSatisfy { $0 == "catalog-covered" } ? "catalog-covered" : "unverified"
    }

    private static func rollupHistorical(_ values: [String]) -> String {
        guard !values.isEmpty, values.allSatisfy({ $0 == "passed" }) else {
            return values.first { $0 != "passed" } ?? historicalUnverified
        }
        return "passed"
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}
