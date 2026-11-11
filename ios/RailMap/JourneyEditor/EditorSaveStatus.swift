import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// The one thing a disabled Save is waiting for. `TripDraftModel.canSave` is
/// true exactly when `saveBlocker` is nil; the checks follow the same order.
enum EditorSaveBlocker: Equatable {
    case repairing
    case regionConflict
    case groupName
    case timetableStops
    case times
    case noRoute
    case chooseOrigin
    case chooseDestination
    case findingRoute
    case chooseRoute

    var key: String {
        switch self {
        case .repairing: "ios.newTrip.blocker.repairing"
        case .regionConflict: "ios.newTrip.blocker.regionConflict"
        case .groupName: "ios.newTrip.blocker.groupName"
        case .timetableStops: "ios.newTrip.blocker.timetableStops"
        case .times: "ios.newTrip.blocker.times"
        case .noRoute: "ios.newTrip.blocker.noRoute"
        case .chooseOrigin: "ios.newTrip.blocker.chooseOrigin"
        case .chooseDestination: "ios.newTrip.blocker.chooseDestination"
        case .findingRoute: "ios.newTrip.blocker.findingRoute"
        case .chooseRoute: "ios.newTrip.blocker.chooseRoute"
        }
    }

    var anchor: EditorAnchor {
        switch self {
        case .chooseOrigin, .regionConflict: .origin
        case .chooseDestination: .destination
        case .times: .time
        case .groupName: .details
        case .repairing, .timetableStops, .noRoute, .findingRoute, .chooseRoute: .route
        }
    }
}

/// Where the status row scrolls the form to.
enum EditorAnchor: String, Hashable {
    case origin = "newTripAnchorOrigin"
    case destination = "newTripAnchorDestination"
    case time = "newTripAnchorTime"
    case service = "newTripAnchorService"
    case route = "newTripAnchorRoute"
    case stops = "newTripAnchorStops"
    case details = "newTripAnchorDetails"

    init(field: RideDraftIssue.Field) {
        switch field {
        case .origin: self = .origin
        case .destination: self = .destination
        case .date: self = .time
        case .number: self = .service
        case .stops, .stop: self = .stops
        case .routeSection, .routePolicy: self = .route
        case .id, .color, .record: self = .details
        }
    }
}

extension TripDraftModel {
    /// Why Save is disabled, or nil when it is enabled. Mirrors `canSave`.
    var saveBlocker: EditorSaveBlocker? {
        if draft.journeyGroup?.name.isEmpty == true { return .groupName }
        if repair.isRunning { return .repairing }
        if !regionConflicts.isEmpty { return .regionConflict }
        if let timetableTrain {
            if timetableTrain.stops.count < 2 { return .timetableStops }
            return timesAllowSave ? nil : .times
        }
        if !routeEdited {
            if !hasRecordRoute { return .noRoute }
            return timesAllowSave ? nil : .times
        }
        if origin == nil { return .chooseOrigin }
        if destination == nil { return .chooseDestination }
        if !timesAllowSave { return .times }
        if plannedIdentity != routeIdentity || searching { return .findingRoute }
        if selectedCorridor == nil, !historicalSaveAllowed { return .chooseRoute }
        return nil
    }
}

/// The status row under the navigation bar: the errors of a save that ran,
/// or, while Save is disabled, the one thing that is missing. Tapping it
/// scrolls the form to the field.
struct EditorSaveStatusRow: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    let model: TripDraftModel
    let scrollTo: (EditorAnchor) -> Void

    var body: some View {
        if let anchor {
            Button { scrollTo(anchor) } label: {
                VStack(alignment: .leading, spacing: RailSpacing.s4) {
                    if !model.saveIssues.isEmpty {
                        ForEach(model.saveIssues) { issue in
                            RailStatusLabel(kind: .error, text: localization.text(for: issue))
                        }
                    } else if model.autofillFailed {
                        RailStatusLabel(kind: .error, text: text(
                            "autofillFailed", fallback: "This route could not be applied."))
                    } else if let blocker = model.saveBlocker {
                        Label(localization.text(blocker.key), systemImage: "info.circle")
                            .railText(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: RailSize.touch, alignment: .leading)
                .padding(.horizontal, RailSpacing.s16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.bar)
            .accessibilityIdentifier("newTripSaveStatus")
        }
    }

    private var anchor: EditorAnchor? {
        if let issue = model.saveIssues.first { return EditorAnchor(field: issue.field) }
        if model.autofillFailed { return .route }
        return model.saveBlocker?.anchor
    }
}
