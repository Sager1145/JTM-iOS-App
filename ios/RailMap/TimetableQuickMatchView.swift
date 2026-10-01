import RailCore
import SwiftUI

/// Local lookup follows the identifying fields before network-backed completion.
struct TimetableQuickMatchView: View {
    @Environment(AppLocalization.self) private var localization
    let train: Train
    let serviceName: String
    let onSelect: (TrainTimetableDatabase.Trip) -> Void

    @State private var matches: [TrainTimetableDatabase.Trip] = []
    @State private var sourcesByTripID: [String: [TrainTimetableDatabase.SourceDocument]] = [:]
    @State private var isSearching = false
    @State private var searched = false
    @State private var failure: String?
    @State private var searchTask: Task<Void, Never>?

    private var isReady: Bool {
        Region.resolved(train) == .jp
            && train.date?.isEmpty == false
            && train.stops.first?.n02StationCode?.isEmpty == false
            && train.stops.last?.n02StationCode?.isEmpty == false
            && train.stops.first?.departure.flatMap(Dates.parseTimeToMinutes) != nil
            && train.stops.last?.arrival.flatMap(Dates.parseTimeToMinutes) != nil
    }

    private var lookupInput: [String?] {
        [Region.resolved(train).code, train.date, serviceName, train.number,
         train.stops.first?.n02StationCode, train.stops.first?.departure,
         train.stops.last?.n02StationCode, train.stops.last?.arrival]
    }

    var body: some View {
        Section {
            Button { search() } label: {
                if isSearching {
                    Label {
                        Text(localization.editorText("ios.editor.timetableSearching"))
                    } icon: { ProgressView() }
                } else {
                    Label(localization.editorText("ios.editor.timetableSearch"),
                          systemImage: "clock.arrow.circlepath")
                }
            }
            .disabled(!isReady || isSearching)
            .accessibilityIdentifier("rideEditorTimetableMatch")

            if let failure {
                Text(failure).foregroundStyle(.secondary)
            } else if searched && matches.isEmpty {
                Text(localization.editorText("ios.editor.timetableNoMatch"))
                    .foregroundStyle(.secondary)
            }
            ForEach(matches) { trip in
                let status = localization.editorText(trip.canApplyToRouteEditor
                    ? "ios.editor.timetableVerifiedRoute"
                    : "ios.editor.timetablePublishedDraft")
                Button {
                    onSelect(trip)
                    matches = []
                    searched = false
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
                if let sources = sourcesByTripID[trip.id], !sources.isEmpty {
                    DisclosureGroup(localization.editorText("ios.editor.timetableSources")) {
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
            Text(localization.editorText("ios.editor.timetableMatchTitle"))
        } footer: {
            Text(localization.editorText(isReady
                ? "ios.editor.timetableMatchNote" : "ios.editor.timetableMatchRequirements"))
        }
        .task(id: lookupInput) {
            cancelSearch()
            guard isReady else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled else { return }
            search()
        }
        .onDisappear { cancelSearch() }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        matches = []
        sourcesByTripID = [:]
        searched = false
        failure = nil
    }

    private func search() {
        guard isReady, let date = train.date else { return }
        searchTask?.cancel()
        isSearching = true
        matches = []
        sourcesByTripID = [:]
        failure = nil
        let input = train
        let requestedName = serviceName
        searchTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                () -> Result<([TrainTimetableDatabase.Trip], [String: [TrainTimetableDatabase.SourceDocument]]), Error> in
                do {
                    guard let database = TrainTimetableDatabase.bundled() else {
                        return .failure(TrainTimetableDatabase.DatabaseError.cannotOpen("Bundled timetable unavailable"))
                    }
                    let trips = TimetableTripMatch.candidates(
                        for: input, serviceName: requestedName,
                        among: try database.trips(on: date))
                    let sources = try Dictionary(uniqueKeysWithValues: trips.map {
                        ($0.id, try database.sources(for: $0))
                    })
                    return .success((trips, sources))
                } catch { return .failure(error) }
            }.value
            guard !Task.isCancelled else { return }
            isSearching = false
            searchTask = nil
            searched = true
            switch result {
            case .success(let (trips, sources)):
                matches = trips
                sourcesByTripID = sources
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }
}
