import Foundation
import RailApplication
import RailCore
import Testing

struct RideDraftValidationTests {
    /// The complete 36-case production harness, now also run directly
    /// against the application module without compiling app source.
    @Test func preservesAllExistingDraftCases() throws {
        let valid = Train(id: "journey_test", number: "Express 1", origin: "Tokyo",
                          destination: "Shinagawa", stops: [
                            Stop(name: "Tokyo", departure: "23:50", stopType: "origin", rideSegment: true),
                            Stop(name: "Shinagawa", arrival: "00:10+1", stopType: "destination", rideSegment: true)
                          ])
        var count = 0
        func issues(_ draft: Train) -> [RideDraftValidation.Issue] {
            RideDraftValidation.issues(for: draft, originalID: valid.id, existingIDs: [valid.id, "taken"])
        }
        func accepts(_ name: String, _ change: (inout Train) -> Void = { _ in }) {
            var draft = valid
            change(&draft)
            let result = issues(draft)
            #expect(result.blocking.isEmpty, "\(name): \(result)")
            count += 1
        }
        func rejects(_ name: String, field: RideDraftValidation.Field, _ change: (inout Train) -> Void) {
            var draft = valid
            change(&draft)
            let result = issues(draft)
            #expect(result.blocking.contains { $0.field == field }, "\(name): \(result)")
            count += 1
        }
        accepts("undated journey")
        accepts("explicit undated") { $0.date = TrainValidation.undated }
        accepts("leap day") { $0.date = "2028-02-29" }
        accepts("optional service metadata") { $0.numberEn = "Express"; $0.trainType = "Limited Express"; $0.vehicleType = "E235"; $0.company = "JR" }
        accepts("platform zero") { $0.stops[0].platformNumber = 0 }
        accepts("named route section") { $0.routeSections = [RouteSection(from: "Tokyo", to: "Shinagawa")] }
        accepts("canonical route policy") { $0.routePolicy = TrainValidation.canonicalRoutePolicy(nil) }
        accepts("valid color") { $0.style = TrainStyle(color: "#123456") }
        accepts("middle stop may have both times") {
            $0.stops.insert(Stop(name: "Intermediate", arrival: "23:55", departure: "23:56"), at: 1)
        }
        let nextDayPickerTime = EditorTime.confirmPicker(dayOffset: 1, hour: 1, minute: 10)
        #expect(nextDayPickerTime.raw == "25:10")
        #expect(nextDayPickerTime.parsed == .valid(
            raw: "25:10", time: ServiceClockTime(dayOffset: 1, hour: 1, minute: 10)))
        count += 1
        rejects("empty ID", field: .id) { $0.id = "" }
        rejects("invalid ID", field: .id) { $0.id = "invalid id" }
        rejects("blank service", field: .number) { $0.number = " \n" }
        rejects("blank origin", field: .origin) { $0.origin = " " }
        rejects("blank destination", field: .destination) { $0.destination = "" }
        // The shared schema deliberately accepts days 1...31 for legacy
        // calendar rollover, even when the month is shorter (Dates.swift).
        accepts("legacy rollover date") { $0.date = "2027-02-29" }
        rejects("out-of-range month", field: .date) { $0.date = "2027-13-01" }
        rejects("cleared enabled date", field: .date) { $0.date = "" }
        rejects("no stops", field: .stops) { $0.stops = [] }
        rejects("one stop", field: .stops) { $0.stops.removeLast() }
        rejects("blank stop", field: .stop(0)) { $0.stops[0].name = " " }
        rejects("invalid role", field: .stop(1)) { $0.stops[1].stopType = "invalid" }
        rejects("invalid station code", field: .stop(0)) { $0.stops[0].n02StationCode = "?" }
        rejects("negative platform", field: .stop(0)) { $0.stops[0].platformNumber = -1 }
        rejects("invalid departure time", field: .stop(0)) { $0.stops[0].departure = "09:99" }
        rejects("invalid arrival time", field: .stop(1)) { $0.stops[1].arrival = "10:99" }
        rejects("origin both times", field: .stop(0)) { $0.stops[0].arrival = "23:49" }
        rejects("destination both times", field: .stop(1)) { $0.stops[1].departure = "00:11+1" }
        rejects("incomplete route section", field: .routeSection(0)) { $0.routeSections = [RouteSection(from: "Tokyo")] }
        rejects("invalid section code", field: .routeSection(0)) { $0.routeSections = [RouteSection(from: "Tokyo", to: "Shinagawa", fromN02StationCode: "?")] }
        rejects("invalid policy institution", field: .routePolicy) { $0.routePolicy = TrainValidation.canonicalRoutePolicy(nil); $0.routePolicy?.allowedInstitutionTypeCodes = ["999"] }
        rejects("invalid policy filter", field: .routePolicy) { $0.routePolicy = TrainValidation.canonicalRoutePolicy(nil); $0.routePolicy?.institutionFilterMode = "invalid" }
        rejects("authoritative policy fallback", field: .routePolicy) { $0.routePolicy = TrainValidation.canonicalRoutePolicy(nil); $0.routePolicy?.allowBrowserStraightLineFallback = true }
        rejects("invalid color", field: .color) { $0.style = TrainStyle(color: "invalid") }
        var collision = valid
        collision.id = "taken"
        let collisionIssues = issues(collision)
        #expect(collisionIssues.blocking.isEmpty)
        #expect(collisionIssues.contains { $0.field == .id && $0.severity == .warning })
        count += 1
        var repaired = valid
        repaired.stops[0].name = ""
        #expect(!issues(repaired).blocking.isEmpty)
        repaired.stops[0].name = valid.stops[0].name
        #expect(issues(repaired).blocking.isEmpty)
        count += 1
        #expect(count == 36)
    }

    @Test func diagnosticsCarrySemanticValuesInExistingOrder() {
        let draft = Train(
            id: "taken", number: " ", origin: "A", destination: "B", stops: [
                Stop(name: "A", departure: "09:99"), Stop(name: "B", arrival: "10:00")])
        let issues = RideDraftValidation.issues(
            for: draft, originalID: "original", existingIDs: ["taken"])
        #expect(issues.map(\.field) == [.id, .number, .stop(0)])
        #expect(issues.map(\.severity) == [.warning, .error, .error])
        #expect(issues.map(\.reason) == [.idTaken("taken"), .numberRequired, .invalidDepartureTime])
    }

    @Test func combinedDiagnosticsPreserveRuleAndSectionOrder() {
        var draft = Train(
            id: "taken", date: "2027-13-01", number: " ", origin: " ", destination: " ",
            stops: [
                Stop(name: " ", n02StationCode: "?", platformNumber: -1,
                     arrival: "09:99", departure: "09:99", stopType: "invalid"),
                Stop(name: "B", arrival: "10:00", departure: "10:01")])
        draft.routeSections = [
            RouteSection(fromN02StationCode: "?", toN02StationCode: "?"),
            RouteSection(from: "A")]
        draft.routePolicy = TrainValidation.canonicalRoutePolicy(nil)
        draft.routePolicy?.allowedInstitutionTypeCodes = ["999"]
        draft.routePolicy?.institutionFilterMode = "invalid"
        draft.style = TrainStyle(color: "invalid")
        let issues = RideDraftValidation.issues(
            for: draft, originalID: "original", existingIDs: ["taken"])
        #expect(issues.map(\.reason) == [
            .idTaken("taken"), .dateRule, .numberRequired, .originRequired, .destinationRequired,
            .stopNameRequired, .stopTypeRule, .stationCodeRule, .platformRule,
            .invalidArrivalTime, .invalidDepartureTime, .firstStopTimes, .lastStopTimes,
            .sectionCode(1), .sectionEndpoints(2), .policyCodesRule, .policyModeRule, .colorRule])
        #expect(issues.map(\.field) == [
            .id, .date, .number, .origin, .destination,
            .stop(0), .stop(0), .stop(0), .stop(0), .stop(0), .stop(0), .stop(0), .stop(1),
            .routeSection(0), .routeSection(1), .routePolicy, .routePolicy, .color])
        #expect(issues.first?.severity == .warning)
        #expect(issues.dropFirst().allSatisfy { $0.severity == .error })
    }

    @Test func singleStopAppliesOnlyTheFirstEndpointTimeRule() {
        let draft = Train(id: "single", number: "1", origin: "A", destination: "B", stops: [
            Stop(name: "A", arrival: "09:00", departure: "09:01")])
        let issues = RideDraftValidation.issues(for: draft, originalID: "single", existingIDs: [])
        #expect(issues.map(\.field) == [.stops, .stop(0)])
        #expect(issues.map(\.reason) == [.stopCount(1), .firstStopTimes])
    }
}

private extension Array where Element == RideDraftValidation.Issue {
    var blocking: [Element] { filter { $0.severity == .error } }
}
