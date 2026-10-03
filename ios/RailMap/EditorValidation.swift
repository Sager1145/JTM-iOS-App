import RailApplication
import Foundation
import RailCore

/// One reason the draft in the editor cannot be saved yet, attached to the
/// field that can fix it.
struct RideDraftIssue: Identifiable, Equatable {

    /// Where the problem lives, and therefore where the message goes.
    ///
    /// §5.4: "校验必须尽量在字段旁实时显示，不能只在表单底部给一个泛化错误."
    /// The cases that are *not* a text field — `.stops`, `.routePolicy`,
    /// `.record` — are the rules that genuinely have no single field to stand
    /// next to; they anchor a section instead, and "查看错误" scrolls to it.
    enum Field: Hashable {
        case id
        case date
        case number
        case origin
        case destination
        case color
        /// The stop list as a whole (its length).
        case stops
        /// One row of it.
        case stop(Int)
        /// One written route section. The editor can add, reorder and edit
        /// them, so its rules need somewhere to be said other than the
        /// catch-all at the bottom of the form.
        case routeSection(Int)
        /// `route_policy`'s structural invariants — no field of their own,
        /// because the editor exposes the two the reader can choose and the
        /// rest are schema constants.
        case routePolicy
        /// A rule the field-level checks did not account for. Never expected;
        /// present so a validator change cannot silently produce a draft that
        /// is refused with no explanation.
        case record

        /// Whether focus can be moved into it, or only scrolled to.
        var isTextField: Bool {
            switch self {
            case .id, .date, .number, .origin, .destination, .color: true
            default: false
            }
        }
    }

    enum Severity: Equatable {
        /// Blocks the save.
        case error
        /// Saving works, but not the way the reader expects. §8.3's id
        /// collision is the one that matters: the record is written under its
        /// previous id rather than overwriting somebody else's journey.
        case warning
    }

    let field: Field
    let severity: Severity
    /// A key for ``AppLocalization/editorText(_:_:)``, or — for `.record` — a
    /// message out of `TrainValidation` that is not translatable.
    let key: String
    let params: [String: Localization.Param]
    /// Set only when `key` is not a catalog key: the validator's own English.
    let literal: String?

    var id: String { "\(field)-\(key)-\(literal ?? "")" }

    init(
        field: Field,
        severity: Severity = .error,
        key: String,
        params: [String: Localization.Param] = [:],
        literal: String? = nil
    ) {
        self.field = field
        self.severity = severity
        self.key = key
        self.params = params
        self.literal = literal
    }
}

/// Maps application diagnostics to localized form messages and focus targets.
enum RideDraftValidation {
    static func issues(
        for draft: Train, originalID: String, existingIDs: Set<String>
    ) -> [RideDraftIssue] {
        RailApplication.RideDraftValidation.issues(
            for: draft, originalID: originalID, existingIDs: existingIDs
        ).map { issue in
            let field: RideDraftIssue.Field = switch issue.field {
            case .id: .id
            case .date: .date
            case .number: .number
            case .origin: .origin
            case .destination: .destination
            case .color: .color
            case .stops: .stops
            case .stop(let index): .stop(index)
            case .routeSection(let index): .routeSection(index)
            case .routePolicy: .routePolicy
            case .record: .record
            }
            let severity: RideDraftIssue.Severity = switch issue.severity {
            case .error: .error
            case .warning: .warning
            }
            let message = presentation(for: issue.reason)
            return RideDraftIssue(
                field: field, severity: severity, key: message.key,
                params: message.params, literal: message.literal)
        }
    }

    private static func presentation(for reason: RailApplication.RideDraftValidation.Reason)
        -> (key: String, params: [String: Localization.Param], literal: String?)
    {
        switch reason {
        case .idRequired: ("ios.editor.idRequired", [:], nil)
        case .idRule: ("ios.editor.idRule", [:], nil)
        case .dateRule: ("ios.editor.dateRule", [:], nil)
        case .numberRequired: ("ios.editor.numberRequired", [:], nil)
        case .originRequired: ("ios.editor.originRequired", [:], nil)
        case .destinationRequired: ("ios.editor.destinationRequired", [:], nil)
        case .stopNameRequired: ("ios.editor.stopNameRequired", [:], nil)
        case .stopTypeRule: ("ios.editor.stopTypeRule", [:], nil)
        case .stationCodeRule: ("ios.editor.stationCodeRule", [:], nil)
        case .platformRule: ("ios.editor.platformRule", [:], nil)
        case .invalidArrivalTime: ("ios.editor.invalidArrivalTime", [:], nil)
        case .invalidDepartureTime: ("ios.editor.invalidDepartureTime", [:], nil)
        case .firstStopTimes: ("ios.editor.firstStopTimes", [:], nil)
        case .lastStopTimes: ("ios.editor.lastStopTimes", [:], nil)
        case .policyCodesRule: ("ios.editor.policyCodesRule", [:], nil)
        case .policyModeRule: ("ios.editor.policyModeRule", [:], nil)
        case .colorRule: ("ios.editor.colorRule", [:], nil)
        case .policyProblem: ("ios.editor.policyProblem", [:], nil)
        case .idTaken(let id): ("ios.editor.idTaken", ["id": .string(id)], nil)
        case .stopCount(let count):
            ("ios.editor.stopCountRule", ["count": .number(Double(count))], nil)
        case .sectionEndpoints(let index):
            ("ios.editor.sectionEndpoints", ["index": .number(Double(index))], nil)
        case .sectionCode(let index):
            ("ios.editor.sectionCodeRule", ["index": .number(Double(index))], nil)
        case .schemaRefusal(let message): ("ios.editor.otherProblem", [:], message)
        }
    }
}

extension Array where Element == RideDraftIssue {
    /// Every blocking issue, in the order the form shows the fields.
    var blocking: [RideDraftIssue] { filter { $0.severity == .error } }

    func first(for field: RideDraftIssue.Field) -> RideDraftIssue? {
        first { $0.field == field }
    }

    func all(for field: RideDraftIssue.Field) -> [RideDraftIssue] {
        filter { $0.field == field }
    }
}
