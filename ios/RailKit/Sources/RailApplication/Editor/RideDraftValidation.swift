import Foundation
import RailCore

/// Validates a candidate edit against the canonical schema and editor input
/// grammar, without reading or changing a live store. ID collisions remain
/// warnings because the app preserves the original identity when saving.
public enum RideDraftValidation {

    public enum Field: Hashable, Sendable {
        case id, date, number, origin, destination, color, stops
        case stop(Int)
        case routeSection(Int)
        case routePolicy, record
    }

    public enum Severity: Equatable, Sendable {
        case error, warning
    }

    /// Semantic diagnostics; the app chooses their localized text and focus.
    public enum Reason: Equatable, Sendable {
        case idRequired, idRule
        case idTaken(String)
        case dateRule, numberRequired, originRequired, destinationRequired
        case stopCount(Int)
        case stopNameRequired, stopTypeRule, stationCodeRule, platformRule
        case invalidArrivalTime, invalidDepartureTime, firstStopTimes, lastStopTimes
        case sectionEndpoints(Int), sectionCode(Int)
        case policyCodesRule, policyModeRule, colorRule, policyProblem
        case schemaRefusal(String)
    }

    public struct Issue: Equatable, Sendable {
        public let field: Field
        public let severity: Severity
        public let reason: Reason

        init(field: Field, severity: Severity = .error, reason: Reason) {
            self.field = field
            self.severity = severity
            self.reason = reason
        }
    }

    public static func issues(
        for draft: Train, originalID: String, existingIDs: Set<String>
    ) -> [Issue] {
        // Empty on purpose: a collision with another journey is the editor's
        // warning below, not the schema's duplicate-id error.
        var ids = Set<String>()
        var pending = TrainValidation.recordDiagnostics(draft, index: 0, ids: &ids)
        var issues: [Issue] = []

        let trimmedID = draft.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID.isEmpty {
            issues.append(Issue(field: .id, reason: .idRequired))
        } else if !TrainValidation.matchesTrainIDPattern(draft.id) {
            issues.append(Issue(field: .id, reason: .idRule))
        } else if draft.id != originalID, existingIDs.contains(draft.id) {
            // §8.3. A warning, not an error: saving keeps this journey's
            // previous id rather than overwriting somebody else's.
            issues.append(
                Issue(field: .id, severity: .warning, reason: .idTaken(draft.id)))
        }
        pending.removeAll { $0.path == "id" }

        if let date = draft.date, date != TrainValidation.undated,
            !Dates.isValidDateString(date)
        {
            issues.append(Issue(field: .date, reason: .dateRule))
        }
        pending.removeAll { $0.path == "date" }

        if isBlank(draft.number) {
            issues.append(Issue(field: .number, reason: .numberRequired))
        }
        if isBlank(draft.origin) {
            issues.append(Issue(field: .origin, reason: .originRequired))
        }
        if isBlank(draft.destination) {
            issues.append(Issue(field: .destination, reason: .destinationRequired))
        }
        pending.removeAll { ["number", "origin", "destination"].contains($0.path) }

        if draft.stops.count < 2 {
            issues.append(Issue(field: .stops, reason: .stopCount(draft.stops.count)))
        }
        pending.removeAll { $0.path == "stops" }

        for (index, stop) in draft.stops.enumerated() {
            if isBlank(stop.name) {
                issues.append(Issue(field: .stop(index), reason: .stopNameRequired))
            }
            if !TrainValidation.stopTypes.contains(stop.stopType) {
                issues.append(Issue(field: .stop(index), reason: .stopTypeRule))
            }
            if let code = stop.n02StationCode, !code.isEmpty,
                TrainValidation.stationCodeSystem(code) == nil
            {
                issues.append(Issue(field: .stop(index), reason: .stationCodeRule))
            }
            if let platform = stop.platformNumber, platform < 0 {
                issues.append(Issue(field: .stop(index), reason: .platformRule))
            }
            // The file schema keeps times opaque. The editor's clock grammar
            // is stricter, and it is the only place that grammar is applied.
            if case .invalid = EditorTime.parseTime(stop.arrival) {
                issues.append(Issue(field: .stop(index), reason: .invalidArrivalTime))
            }
            if case .invalid = EditorTime.parseTime(stop.departure) {
                issues.append(Issue(field: .stop(index), reason: .invalidDepartureTime))
            }
            pending.removeAll { $0.path.hasPrefix("stops[\(index)].") }
        }
        if let first = draft.stops.first, hasBothTimes(first) {
            issues.append(Issue(field: .stop(0), reason: .firstStopTimes))
        }
        if draft.stops.count > 1, let last = draft.stops.last, hasBothTimes(last) {
            issues.append(
                Issue(field: .stop(draft.stops.count - 1), reason: .lastStopTimes))
        }
        pending.removeAll {
            $0.reason.hasPrefix("first stop") || $0.reason.hasPrefix("final stop")
        }

        for (index, section) in (draft.routeSections ?? []).enumerated() {
            let hasFrom = !isBlank(section.from ?? "")
                || !isBlank(section.fromN02StationCode ?? "")
            let hasTo = !isBlank(section.to ?? "")
                || !isBlank(section.toN02StationCode ?? "")
            if !hasFrom || !hasTo {
                issues.append(
                    Issue(field: .routeSection(index), reason: .sectionEndpoints(index + 1)))
            }
            for code in [section.fromN02StationCode, section.toN02StationCode] {
                guard let code, !code.isEmpty else { continue }
                if TrainValidation.stationCodeSystem(code) == nil {
                    issues.append(
                        Issue(field: .routeSection(index), reason: .sectionCode(index + 1)))
                    break
                }
            }
            pending.removeAll { $0.path.hasPrefix("route_sections[\(index)]") }
        }

        if let policy = draft.routePolicy {
            let allowed = policy.allowedInstitutionTypeCodes ?? []
            if !allowed.allSatisfy(TrainValidation.defaultAllowedInstitutionTypeCodes.contains) {
                issues.append(Issue(field: .routePolicy, reason: .policyCodesRule))
            }
            if let mode = policy.institutionFilterMode, !mode.isEmpty,
                mode != "soft", mode != "hard"
            {
                issues.append(Issue(field: .routePolicy, reason: .policyModeRule))
            }
        }
        pending.removeAll {
            $0.path == "route_policy.allowed_institution_type_codes"
                || $0.path == "route_policy.institution_filter_mode"
        }

        if let color = draft.style?.color, !color.isEmpty,
            !TrainValidation.isValidTrainColor(color)
        {
            issues.append(Issue(field: .color, reason: .colorRule))
        }
        pending.removeAll { $0.path == "style.color" }

        // A schema fact the field checks do not name. Shown only when nothing
        // else already explains why the draft cannot be saved.
        let explained = issues.contains { $0.severity == .error }
        if !explained, let leftover = pending.first {
            let isPolicy = leftover.path.hasPrefix("route_policy")
                || leftover.reason.contains("route_policy")
            issues.append(
                Issue(
                    field: isPolicy ? .routePolicy : .record,
                    reason: isPolicy ? .policyProblem : .schemaRefusal(leftover.reason)))
        }
        return issues
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func hasBothTimes(_ stop: Stop) -> Bool {
        !(stop.arrival ?? "").isEmpty && !(stop.departure ?? "").isEmpty
    }
}

