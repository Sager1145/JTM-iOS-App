import RailApplication
import Foundation
import RailCore

/// One reason the draft in the editor cannot be saved yet, attached to the
/// field that can fix it.
struct RideDraftIssue: Identifiable, Equatable {

    /// Where the problem lives. The cases are `RideDraftValidation.Field`;
    /// the app only adds whether focus can move into the field.
    typealias Field = RailApplication.RideDraftValidation.Field

    /// `RideDraftValidation.Severity`. A warning still saves.
    typealias Severity = RailApplication.RideDraftValidation.Severity

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
            let message = presentation(for: issue.reason)
            return RideDraftIssue(
                field: issue.field, severity: issue.severity, key: message.key,
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

extension RideDraftIssue.Field {
    /// Whether focus can be moved into it, or only scrolled to.
    ///
    /// `.stops`, `.routePolicy` and `.record` have no single text field; they
    /// anchor a section, and "查看错误" scrolls to it.
    var isTextField: Bool {
        switch self {
        case .id, .date, .number, .origin, .destination, .color: true
        default: false
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
