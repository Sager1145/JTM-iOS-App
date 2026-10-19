import RailCore
import SwiftUI

/// Local lookup follows the identifying fields before network-backed completion.
struct TimetableQuickMatchView: View {
    @Environment(AppLocalization.self) private var localization
    let train: Train
    let serviceName: String
    let onSelect: (TrainTimetableDatabase.Trip) -> Void

    @State private var controller = TimetableQuickMatchController()

    private var input: TimetableQuickMatchController.Input {
        .init(train: train, serviceName: serviceName)
    }

    var body: some View {
        Section {
            Button { controller.search(input) } label: {
                if controller.isSearching {
                    Label {
                        Text(localization.text("ios.editor.timetableSearching"))
                    } icon: { ProgressView() }
                } else {
                    Label(localization.text("ios.editor.timetableSearch"),
                          systemImage: "clock.arrow.circlepath")
                }
            }
            .disabled(!input.isReady || controller.isSearching)
            .accessibilityIdentifier("rideEditorTimetableMatch")

            if let failure = controller.failure {
                Text(failure).foregroundStyle(.secondary)
            } else if controller.searched && controller.matches.isEmpty {
                Text(localization.text("ios.editor.timetableNoMatch"))
                    .foregroundStyle(.secondary)
            }
            ForEach(controller.matches) { trip in
                let status = localization.text(trip.canApplyToRouteEditor
                    ? "ios.editor.timetableVerifiedRoute"
                    : "ios.editor.timetablePublishedDraft")
                Button {
                    onSelect(trip)
                    controller.didSelectMatch()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(trip.displayName) \(trip.publicNumber ?? trip.trainNumber)")
                            .font(.headline)
                        Text("\(trip.timetableEditionName) · \(status)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("rideEditorTimetableMatch-\(trip.id)")
                if let sources = controller.sourcesByTripID[trip.id], !sources.isEmpty {
                    DisclosureGroup(localization.text("ios.editor.timetableSources")) {
                        ForEach(sources) { source in
                            if let url = URL(string: source.urlOrLocator),
                               ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                                Link(source.title, destination: url)
                            } else {
                                Text(source.title).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text(localization.text("ios.editor.timetableMatchTitle"))
        } footer: {
            Text(localization.text(input.isReady
                ? "ios.editor.timetableMatchNote" : "ios.editor.timetableMatchRequirements"))
        }
        .task(id: input.lookupIdentity) {
            guard !Task.isCancelled else { return }
            controller.updateInput(input)
        }
        .onDisappear { controller.cancel() }
    }
}
