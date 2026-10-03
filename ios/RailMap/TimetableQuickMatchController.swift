import Foundation
import Observation
import RailCore

/// Owns the local timetable lookup lifecycle and its staged results. Applying a
/// trip remains the editor's command; this controller never changes the draft.
@MainActor
@Observable
final class TimetableQuickMatchController {
    struct Input: Sendable {
        let train: Train
        let serviceName: String

        var isReady: Bool {
            Region.resolved(train) == .jp
                && TrainTimetableDatabase.accepts(train)
                && train.date?.isEmpty == false
                && train.stops.first?.n02StationCode?.isEmpty == false
                && train.stops.last?.n02StationCode?.isEmpty == false
                && train.stops.first?.departure.flatMap(Dates.parseTimeToMinutes) != nil
                && train.stops.last?.arrival.flatMap(Dates.parseTimeToMinutes) != nil
        }

        /// Keep the editor's existing automatic lookup triggers. Other draft
        /// fields are still read from the latest input when Search is pressed.
        var lookupIdentity: [String?] {
            [
                Region.resolved(train).code, train.date, serviceName, train.number,
                train.stops.first?.n02StationCode, train.stops.first?.departure,
                train.stops.last?.n02StationCode, train.stops.last?.arrival,
            ]
        }
    }

    struct Matches: Sendable {
        let trips: [TrainTimetableDatabase.Trip]
        let sourcesByTripID: [String: [TrainTimetableDatabase.SourceDocument]]
    }

    typealias Lookup = @Sendable (Input) async -> Result<Matches, Error>
    typealias Debounce = @Sendable () async throws -> Void

    private(set) var matches: [TrainTimetableDatabase.Trip] = []
    private(set) var sourcesByTripID: [String: [TrainTimetableDatabase.SourceDocument]] = [:]
    private(set) var isSearching = false
    private(set) var searched = false
    private(set) var failure: String?

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var automaticTask: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private let lookup: Lookup
    @ObservationIgnored private let debounce: Debounce

    init(
        lookup: @escaping Lookup = TimetableQuickMatchLookup.lookup,
        debounce: @escaping Debounce = { try await Task.sleep(for: .milliseconds(300)) }
    ) {
        self.lookup = lookup
        self.debounce = debounce
    }

    /// Replacing the identifying fields clears the former result immediately;
    /// the automatic request still waits the editor's existing 300 ms delay.
    func updateInput(_ input: Input) {
        cancel()
        guard input.isReady else { return }
        let debounce = debounce
        automaticTask = Task { @MainActor [weak self] in
            do { try await debounce() } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.automaticTask = nil
            self.search(input)
        }
    }

    func search(_ input: Input) {
        guard input.isReady else { return }
        searchTask?.cancel()
        let id = UUID()
        requestID = id
        isSearching = true
        matches = []
        sourcesByTripID = [:]
        failure = nil
        var train = input.train
        train.region = Region.resolved(train).code
        let request = Input(train: train, serviceName: input.serviceName)
        let lookup = lookup
        // The automatic debounce is intentionally independent of a manual
        // search, matching the editor's prior .task and Button lifetimes.
        searchTask = Task { @MainActor [weak self] in
            let result = await lookup(request)
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            self.isSearching = false
            self.searchTask = nil
            self.searched = true
            switch result {
            case .success(let result):
                self.matches = result.trips
                self.sourcesByTripID = result.sourcesByTripID
            case .failure(let error):
                self.failure = error.localizedDescription
            }
        }
    }

    /// The view has already handed the chosen trip to its existing editor
    /// callback. Clear the visible choices with the same prior selection rule.
    func didSelectMatch() {
        matches = []
        searched = false
    }

    func cancel() {
        automaticTask?.cancel()
        automaticTask = nil
        searchTask?.cancel()
        searchTask = nil
        requestID = UUID()
        isSearching = false
        matches = []
        sourcesByTripID = [:]
        searched = false
        failure = nil
    }
}

/// The only local database side effect. Queries and candidate matching keep
/// running off the main actor, using the existing bundled artifact and rules.
enum TimetableQuickMatchLookup {
    nonisolated static func lookup(_ input: TimetableQuickMatchController.Input) async
        -> Result<TimetableQuickMatchController.Matches, Error>
    {
        await Task.detached(priority: .userInitiated) {
            do {
                guard let database = TrainTimetableDatabase.bundled(country: input.train.region ?? "jp") else {
                    return .failure(TrainTimetableDatabase.DatabaseError.cannotOpen("Bundled timetable unavailable"))
                }
                // Readiness is checked before this worker is submitted.
                let trips = TimetableTripMatch.candidates(
                    for: input.train, serviceName: input.serviceName,
                    among: try database.trips(on: input.train.date ?? ""))
                let sources = try Dictionary(
                    uniqueKeysWithValues: trips.map {
                        ($0.id, try database.sources(for: $0))
                    })
                return .success(.init(trips: trips, sourcesByTripID: sources))
            } catch { return .failure(error) }
        }.value
    }
}
