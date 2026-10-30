import Foundation
import Testing

@testable import RailCore

struct RailHistoryServiceStatusTests {
    private func period(
        id: String = "isumi.suspension", from: String = "2024-10-05",
        to: Any = NSNull()
    ) -> [String: Any] {
        ["history_id": id, "lineID": "isumi", "scope": "whole_line",
         "station_membership_ids": ["005230", "005239"],
         "valid_from": from, "valid_to": to, "serviceStatus": "substitute_bus",
         "source": ["isumi-official-interruption"]]
    }

    private func document(_ periods: [[String: Any]]) -> [String: Any] {
        ["schema_version": "2", "revision": "candidate",
         "features": ["service_status_periods"],
         "sections": [], "stations": [], "retirements": [],
         "service_status_periods": periods]
    }

    private func decode(_ document: [String: Any]) throws -> RailHistoryOverlay {
        try RailHistoryOverlay.decode(JSONSerialization.data(withJSONObject: document))
    }

    @Test func acceptsDatedWholeLineRecordsWithoutGroupedMembershipOwnershipProof() throws {
        // Raw membership IDs intentionally need no current compact geometry to
        // decode: only the compiler has the raw-source ownership evidence.
        let overlay = try decode(document([period()]))
        #expect(overlay.schemaVersion == "2")
    }

    @Test func rejectsUnusableDatedContracts() throws {
        var missingCapability = document([period()])
        missingCapability.removeValue(forKey: "features")
        var unknownCapability = document([period()])
        unknownCapability["features"] = ["service_status_periods", "future_status"]
        var invalid: [[String: Any]] = [missingCapability, unknownCapability, document([])]
        for metadata in [NSNull(), "service_status_periods", ["service_status_periods", 42]] as [Any] {
            var malformedCapabilities = document([period()])
            malformedCapabilities["features"] = metadata
            invalid.append(malformedCapabilities)
        }
        for (key, value) in [
            ("scope", "partial_line" as Any), ("serviceStatus", "suspended" as Any),
            ("source", [] as [String]), ("source", [" "]),
            ("source", "reference"), ("source", [42]), ("lineID", " "), ("history_id", ""),
            ("station_membership_ids", ["005230", "005230"]),
            ("station_membership_ids", ["005230", " 005230 "]),
            ("station_membership_ids", [" "]), ("station_membership_ids", [] as [String]),
            ("valid_from", "2024-02-30"), ("valid_from", NSNull()),
            ("valid_to", "2024-10-04"), ("valid_to", "2024-10-05"),
            ("valid_to", "2025-02-29"),
        ] {
            var record = period()
            record[key] = value
            invalid.append(document([record]))
        }
        var paddedID = period()
        paddedID["history_id"] = " isumi.suspension "
        invalid.append(document([period(), period()]))
        invalid.append(document([period(), paddedID]))
        var duplicateCapabilities = document([period()])
        duplicateCapabilities["features"] = ["service_status_periods", "service_status_periods"]
        invalid.append(duplicateCapabilities)
        invalid.append(document([
            period(to: "2024-11-01"),
            period(id: "isumi.second", from: "2024-10-31"),
        ]))
        for value in invalid {
            #expect(throws: (any Error).self) { try decode(value) }
            let data = try JSONSerialization.data(withJSONObject: value)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(RailHistoryOverlay.self, from: data)
            }
        }
    }

    @Test func allowsAdjacentPeriodsAndUnknownEnds() throws {
        _ = try decode(document([
            period(to: "2024-11-01"),
            period(id: "isumi.second", from: "2024-11-01"),
        ]))
        var noEnd = period()
        noEnd.removeValue(forKey: "valid_to")
        _ = try decode(document([noEnd]))
    }

    @Test func resolvesManagedNormalBeforeAndAfterHalfOpenPeriod() throws {
        let overlay = try decode(document([period(to: "2024-11-01")]))
        for day in ["2024-10-04", "2024-11-01", "2026-10-26"] {
            #expect(try overlay.serviceStatus(lineID: "isumi", on: day) ==
                RailServiceStatusResolution(managed: true, serviceStatus: nil, historyID: nil))
        }
        for day in ["2024-10-05", "2024-10-31"] {
            #expect(try overlay.serviceStatus(lineID: "isumi", on: day) ==
                RailServiceStatusResolution(
                    managed: true, serviceStatus: "substitute_bus", historyID: "isumi.suspension"))
        }
        #expect(try overlay.serviceStatus(lineID: "other-operator", on: "2024-10-05") ==
            RailServiceStatusResolution(managed: false, serviceStatus: nil, historyID: nil))
    }

    @Test func resolvesAdjacentPeriodsByTheirOwnIdentityAndKeepsUnknownEndOpen() throws {
        let overlay = try decode(document([
            period(to: "2024-11-01"),
            period(id: "isumi.second", from: "2024-11-01"),
        ]))
        #expect(try overlay.serviceStatus(lineID: "isumi", on: "2024-10-31").historyID == "isumi.suspension")
        #expect(try overlay.serviceStatus(lineID: "isumi", on: "2024-11-01").historyID == "isumi.second")
        #expect(try overlay.serviceStatus(lineID: "isumi", on: "2099-12-31").serviceStatus == "substitute_bus")
        var noEnd = period()
        noEnd.removeValue(forKey: "valid_to")
        let absentEnd = try decode(document([noEnd]))
        #expect(try absentEnd.serviceStatus(lineID: "isumi", on: "2099-12-31").historyID == "isumi.suspension")
    }

    @Test func legacyOverlayStaysUnmanagedAndCannotDeclareDatedStatus() throws {
        let legacy: [String: Any] = [
            "schema_version": "1", "revision": "legacy", "features": ["identity_periods"],
            "sections": [], "stations": [], "retirements": [],
        ]
        let overlay = try decode(legacy)
        #expect(overlay.serviceStatusPeriods.isEmpty)
        #expect(try overlay.serviceStatus(lineID: "isumi", on: "2024-10-05") ==
            RailServiceStatusResolution(managed: false, serviceStatus: nil, historyID: nil))
        var invalid = legacy
        invalid["service_status_periods"] = [] as [String]
        #expect(throws: (any Error).self) { try decode(invalid) }
        invalid = legacy
        invalid["features"] = ["service_status_periods"]
        #expect(throws: (any Error).self) { try decode(invalid) }
    }

    @Test func legacyOptionalFeatureMetadataRemainsIgnored() throws {
        let ignoredMetadata: [Any] = [
            NSNull(), ["future_optional"], ["identity_periods", "identity_periods"],
            "future_optional", 42, ["future_optional", 42], ["future": true],
            [["nested": ["optional"]], "future_optional"],
        ]
        for metadata in ignoredMetadata {
            let input: [String: Any] = [
                "schema_version": "1", "revision": "legacy", "features": metadata,
                "sections": [], "stations": [], "retirements": [],
            ]
            let overlay = try decode(input)
            #expect(try overlay.serviceStatus(lineID: "isumi", on: "2024-10-05") ==
                RailServiceStatusResolution(managed: false, serviceStatus: nil, historyID: nil))
        }
        var reserved = document([period()])
        reserved["schema_version"] = "1"
        reserved.removeValue(forKey: "service_status_periods")
        for metadata in [
            ["service_status_periods", 42] as [Any],
            [[String: Any](), "service_status_periods"] as [Any],
        ] {
            reserved["features"] = metadata
            #expect(throws: (any Error).self) { try decode(reserved) }
        }
    }

    @Test func requiresExplicitRealCivilDayEvenForUnmanagedLines() throws {
        let overlay = try decode(document([period()]))
        for day in ["", "2024-2-05", "2024-02-30", "2025-02-29", "0000-01-01",
                    "2024-10-05T00:00:00+09:00", " 2024-10-05"] {
            #expect(throws: (any Error).self) { try overlay.serviceStatus(lineID: "other", on: day) }
        }
        #expect(try overlay.serviceStatus(lineID: "isumi", on: "2024-02-29").managed)
    }

    @Test func eventCanAlsoUnderpinLegacyRetirementAndIndependentLinePeriod() throws {
        var other = period(id: "other.suspension")
        other["lineID"] = "other"
        var input = document([period(), other])
        input["features"] = ["identity_periods", "service_status_periods"]
        input["retirements"] = [[
            "history_id": "isumi.suspension", "valid_to": "2024-10-05",
            "match": ["line_name": "Isumi", "operator": "Isumi Railway",
                      "bbox": [140.0, 35.0, 141.0, 36.0]],
        ]]
        let overlay = try decode(input)
        #expect(overlay.retirements.first?.historyId == "isumi.suspension")
        #expect(overlay.serviceStatusPeriods.first?.stationMembershipIDs == ["005230", "005239"])
        #expect(overlay.serviceStatusPeriods.first?.source == ["isumi-official-interruption"])
        #expect(try overlay.serviceStatus(lineID: "other", on: "2024-10-05").historyID == "other.suspension")
    }

}
