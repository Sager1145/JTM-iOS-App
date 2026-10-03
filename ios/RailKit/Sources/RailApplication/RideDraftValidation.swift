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
        var issues: [Issue] = []

        // -- id ------------------------------------------------------------
        let id = draft.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            issues.append(Issue(field: .id, reason: .idRequired))
        } else if !TrainValidation.matchesTrainIDPattern(draft.id) {
            issues.append(Issue(field: .id, reason: .idRule))
        } else if draft.id != originalID, existingIDs.contains(draft.id) {
            // §8.3. A warning, not an error: `ItineraryStore.replace` refuses
            // to overwrite the other journey and keeps this one's previous id,
            // so the save succeeds — just not the way it was typed.
            issues.append(
                Issue(
                    field: .id, severity: .warning, reason: .idTaken(draft.id)))
        }

        // -- date ----------------------------------------------------------
        if let date = draft.date, date != TrainValidation.undated,
            !Dates.isValidDateString(date)
        {
            issues.append(Issue(field: .date, reason: .dateRule))
        }

        // -- identity ------------------------------------------------------
        if isBlank(draft.number) {
            issues.append(Issue(field: .number, reason: .numberRequired))
        }
        if isBlank(draft.origin) {
            issues.append(Issue(field: .origin, reason: .originRequired))
        }
        if isBlank(draft.destination) {
            issues.append(
                Issue(field: .destination, reason: .destinationRequired))
        }

        // -- stops ---------------------------------------------------------
        if draft.stops.count < 2 {
            issues.append(
                Issue(
                    field: .stops, reason: .stopCount(draft.stops.count)))
        }
        for (index, stop) in draft.stops.enumerated() {
            if isBlank(stop.name) {
                issues.append(
                    Issue(field: .stop(index), reason: .stopNameRequired))
            }
            if !TrainValidation.stopTypes.contains(stop.stopType) {
                issues.append(
                    Issue(field: .stop(index), reason: .stopTypeRule))
            }
            if let code = stop.n02StationCode, !code.isEmpty,
                TrainValidation.stationCodeSystem(code) == nil
            {
                issues.append(
                    Issue(field: .stop(index), reason: .stationCodeRule))
            }
            if let platform = stop.platformNumber, platform < 0 {
                issues.append(
                    Issue(field: .stop(index), reason: .platformRule))
            }
            // The shared file schema deliberately keeps arrival and departure
            // opaque strings. The editor accepts typed clock text, so it must
            // apply its stricter grammar here before enabling Save.
            if case .invalid = EditorTime.parseTime(stop.arrival) {
                issues.append(
                    Issue(field: .stop(index), reason: .invalidArrivalTime))
            }
            if case .invalid = EditorTime.parseTime(stop.departure) {
                issues.append(
                    Issue(field: .stop(index), reason: .invalidDepartureTime))
            }
        }
        // The two cross-field rules: neither end of the journey needs both an
        // arrival and a departure.
        if let first = draft.stops.first, hasBothTimes(first) {
            issues.append(Issue(field: .stop(0), reason: .firstStopTimes))
        }
        if draft.stops.count > 1, let last = draft.stops.last, hasBothTimes(last) {
            issues.append(
                Issue(
                    field: .stop(draft.stops.count - 1), reason: .lastStopTimes))
        }

        // -- route sections ------------------------------------------------
        // Every rule `validateTrain` applies to a written section, said next
        // to the section rather than at the foot of the form. The editor is
        // where these become reachable at all: a hand-written store rarely has
        // a section with one endpoint, and an editor with an "add section"
        // button produces one on the first tap.
        for (index, section) in (draft.routeSections ?? []).enumerated() {
            let hasFrom = !isBlank(section.from ?? "")
                || !isBlank(section.fromN02StationCode ?? "")
            let hasTo = !isBlank(section.to ?? "") || !isBlank(section.toN02StationCode ?? "")
            if !hasFrom || !hasTo {
                issues.append(
                    Issue(
                        field: .routeSection(index), reason: .sectionEndpoints(index + 1)))
            }
            for code in [section.fromN02StationCode, section.toN02StationCode] {
                guard let code, !code.isEmpty else { continue }
                if TrainValidation.stationCodeSystem(code) == nil {
                    issues.append(
                        Issue(
                            field: .routeSection(index), reason: .sectionCode(index + 1)))
                    break
                }
            }
        }

        // -- route policy --------------------------------------------------
        // The three the editor actually exposes get their own message; the
        // schema constants it does not expose stay with the generic refusal
        // and its "reset to the canonical policy" repair.
        if let policy = draft.routePolicy {
            let allowed = policy.allowedInstitutionTypeCodes ?? []
            if !allowed.allSatisfy(TrainValidation.defaultAllowedInstitutionTypeCodes.contains) {
                issues.append(
                    Issue(field: .routePolicy, reason: .policyCodesRule))
            }
            if let mode = policy.institutionFilterMode, !mode.isEmpty,
                mode != "soft", mode != "hard"
            {
                issues.append(
                    Issue(field: .routePolicy, reason: .policyModeRule))
            }
        }

        // -- style ---------------------------------------------------------
        if let color = draft.style?.color, !color.isEmpty,
            !TrainValidation.isValidTrainColor(color)
        {
            issues.append(Issue(field: .color, reason: .colorRule))
        }

        // -- the authoritative pass ----------------------------------------
        if let message = schemaRefusal(draft) {
            let explained = issues.contains { $0.severity == .error }
            // Two of these are now explained field by field, so the net firing
            // means a rule moved in `TrainValidation` — which is exactly what
            // it is for.
            if !explained {
                let isPolicy = message.contains("route_policy")
                issues.append(
                    Issue(
                        field: isPolicy ? .routePolicy : .record,
                        reason: isPolicy ? .policyProblem : .schemaRefusal(message)))
            }
        }

        return issues
    }

    /// Whether `TrainValidation` — the shared, fixture-pinned rules — refuses
    /// this draft, and what it said.
    ///
    /// The draft goes through the same `Encodable` the exporter uses, so what
    /// is validated is byte-for-byte the record that would be written. `ids`
    /// starts empty on purpose: duplicate detection needs the whole store and
    /// is handled above, against the ids the workspace publishes.
    private static func schemaRefusal(_ draft: Train) -> String? {
        do {
            let data = try JSONEncoder().encode(draft)
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let json = try TrainValidation.JSON.parse(text)
            var ids: Set<String> = []
            try TrainValidation.validateTrain(json, index: 0, ids: &ids)
            return nil
        } catch let error as TrainValidation.ValidationError {
            return error.message
        } catch {
            return error.localizedDescription
        }
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func hasBothTimes(_ stop: Stop) -> Bool {
        !(stop.arrival ?? "").isEmpty && !(stop.departure ?? "").isEmpty
    }
}

