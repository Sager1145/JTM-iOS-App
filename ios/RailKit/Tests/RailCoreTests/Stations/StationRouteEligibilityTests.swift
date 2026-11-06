import Foundation
import Testing
@testable import RailCore

struct StationRouteEligibilityTests {
    private func network(status: String? = nil) throws -> RouteNetwork {
        var line: [String: Any] = [
            "id": "physical", "name": "Administrative Surface", "nameNorm": "Surface",
            "operator": "Rail Co", "rank": 1,
            "stations": [["A", "Same Name", 139, 35], ["B", "Other", 139.01, 35]],
            "segments": [[1, 0, [[139, 35], [139.01, 35]]]],
        ]
        if let status { line["serviceStatus"] = status }
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "2025", "country": "jp", "lines": [line],
        ])
        let compact = try JSONDecoder().decode(CompactPackage.self, from: data).lines[0]
        return RouteNetwork(lines: [RouteNetwork.Line(
            lineId: compact.id, name: compact.name, operator: compact.operator,
            isLoop: false, alignmentDirection: nil, parts: CompactPackage.decodeDisplayIntervals(compact),
            intervals: RailIntervalCodes.intervals(for: compact), compactLine: compact)])
    }

    private func section(
        validFrom: String? = nil, validTo: String? = nil, history: String? = nil,
        temporal: RouteGraph.TemporalKind = .current, institution: String = "2"
    ) -> RouteGraph.SectionFeature {
        .init(properties: .init(
            lineName: "Administrative Surface", operator: "Rail Co", institutionTypeCode: institution,
            validFrom: validFrom, validTo: validTo, historyId: history, temporalKind: temporal),
            lines: [[Coordinate(lon: 139, lat: 35), Coordinate(lon: 139.01, lat: 35)]])
    }

    private func station(
        _ code: String?, group: String? = nil, line: String = "Administrative Surface",
        extra: [String: Stations.Value] = [:]
    ) -> Stations.Feature {
        var properties: [String: Stations.Value] = [
            "line_name": .string(line), "operator": .string("Rail Co"),
            "station_name": .string("Same Name"), "institution_type_code": .string("2"),
            "display_point": .array([.number(139), .number(35)]),
        ]
        if let code { properties["n02_station_code"] = .string(code) }
        if let group { properties["n02_group_code"] = .string(group) }
        properties.merge(extra) { _, new in new }
        return .init(properties: properties)
    }

    @Test func exactCodePrecedesGroupAliasAndAmbiguousGroupsReject() throws {
        let network = try network()
        let eligibility = StationRouteEligibility(network: network, sections: [section()], stations: [
            station("A", group: "B"), station("platform", group: "A"),
            station("ambiguous", group: "A"), station("ambiguous", group: "B"),
            station("nearby"),
        ])
        #expect(eligibility.stationCode("A") == "A")
        #expect(eligibility.stationCode("platform") == "A")
        #expect(eligibility.stationCode("ambiguous") == nil)
        #expect(eligibility.stationCode("nearby") == nil)
        #expect(eligibility.stationCode("unknown") == nil)
        #expect(eligibility.stationCode(nil) == nil)
        #expect(eligibility.stationCode("") == nil)
    }

    @Test func unchangedUnboundedSourceAndCompleteMembershipAdmit() throws {
        let network = try network()
        let eligibility = StationRouteEligibility(
            network: network, sections: [section()], stations: [station("A"), station("B")])
        #expect(eligibility.permits(network.lines[0], allowedInstitutionCodes: ["2"], hard: true))
        #expect(eligibility.permits(network.lines[0], allowedInstitutionCodes: [], hard: false))
    }

    @Test(arguments: ["from", "to", "history", "historical", "relocated"])
    func anyChangedSourceFamilyRejects(change: String) throws {
        let network = try network()
        let changed = section(
            validFrom: change == "from" ? "1900-01-01" : nil,
            validTo: change == "to" ? "2999-01-01" : nil,
            history: change == "history" ? "event" : nil,
            temporal: change == "historical" ? .historical : change == "relocated" ? .relocatedNew : .current)
        let eligibility = StationRouteEligibility(
            network: network, sections: [section(), changed], stations: [station("A"), station("B")])
        #expect(!eligibility.permits(network.lines[0], allowedInstitutionCodes: ["2"], hard: false))
    }

    @Test(arguments: ["valid_from", "valid_to", "history_id"])
    func anyChangedStationMemberRejects(field: String) throws {
        let network = try network()
        let eligibility = StationRouteEligibility(network: network, sections: [section()], stations: [
            station("A"), station("B", extra: [field: .string("2020-01-01")]),
        ])
        #expect(!eligibility.permits(network.lines[0], allowedInstitutionCodes: [], hard: false))
    }

    @Test func normalizedNameMemberHistoryCannotBeDiscardedWithoutSourceGeometry() throws {
        let network = try network()
        let eligibility = StationRouteEligibility(network: network, sections: [section()], stations: [
            station("A"), station("B"), station("A", line: "Surface", extra: ["history_id": .string("event")]),
        ])
        #expect(!eligibility.permits(network.lines[0], allowedInstitutionCodes: [], hard: false))
    }

    @Test func sourceAndCompleteStationCoverageAreRequired() throws {
        let network = try network()
        let missingSource = StationRouteEligibility(
            network: network, sections: [], stations: [station("A"), station("B")])
        let missingMember = StationRouteEligibility(
            network: network, sections: [section()], stations: [station("A")])
        #expect(!missingSource.permits(network.lines[0], allowedInstitutionCodes: [], hard: false))
        #expect(!missingMember.permits(network.lines[0], allowedInstitutionCodes: [], hard: false))
    }

    @Test func hardInstitutionMismatchRejectsWhileSoftRetainsUnchangedFamily() throws {
        let network = try network()
        let eligibility = StationRouteEligibility(
            network: network, sections: [section()], stations: [station("A"), station("B")])
        #expect(!eligibility.permits(network.lines[0], allowedInstitutionCodes: ["5"], hard: true))
        #expect(eligibility.permits(network.lines[0], allowedInstitutionCodes: ["5"], hard: false))
        let changed = StationRouteEligibility(network: network, sections: [section(history: "event")], stations: [station("A"), station("B")])
        #expect(!changed.permits(network.lines[0], allowedInstitutionCodes: ["5"], hard: false))
    }

    @Test func serviceStatusExceptionRejects() throws {
        let network = try network(status: "suspended")
        let eligibility = StationRouteEligibility(
            network: network, sections: [section()], stations: [station("A"), station("B")])
        #expect(!eligibility.permits(network.lines[0], allowedInstitutionCodes: [], hard: false))
    }

    @Test func uncodedStationOnlyFamilyDoesNotCrashOrCreateCoverage() throws {
        let network = try network()
        let eligibility = StationRouteEligibility(network: network, sections: [], stations: [station(nil)])
        #expect(!eligibility.permits(network.lines[0], allowedInstitutionCodes: [], hard: false))
    }
}
