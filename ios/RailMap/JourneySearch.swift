import Foundation
import Observation
import RailCore
import RailPresentation

@MainActor
@Observable
final class JourneySearch {
    struct Request: Equatable {
        let days: [ItineraryStore.Loaded.Day]
        let date: String
        let query: String
        let naming: StationNamingGeneration

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.date == rhs.date && lhs.query == rhs.query && lhs.naming == rhs.naming
                && ArrayGeneration.same(lhs.days, rhs.days)
        }
    }

    private(set) var completed: Request?
    private(set) var days: [ItineraryStore.Loaded.Day] = []
    @ObservationIgnored private var source: [ItineraryStore.Loaded.Day] = []
    @ObservationIgnored private var naming: StationNamingGeneration?
    @ObservationIgnored private var names: [String: [String]] = [:]

    func search(_ request: Request, alsoNamed: (Train) -> [String]) async {
        guard request != completed else { return }
        guard !request.query.isEmpty else {
            days = []; completed = request
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(150))
            // Localization is UI-owned. Snapshot its inexpensive lookups
            // once per store/language generation, never once per keystroke.
            if naming != request.naming || !ArrayGeneration.same(source, request.days) {
                var snapshot: [String: [String]] = [:]
                for day in request.days {
                    try Task.checkCancellation()
                    for train in day.trains { snapshot[train.id] = alsoNamed(train) }
                    await Task.yield()
                }
                try Task.checkCancellation()
                source = request.days; naming = request.naming; names = snapshot
            }
            let names = names
            let source = request.days
            let date = request.date
            let query = request.query
            let worker = Task.detached(priority: .userInitiated) {
                var result: [ItineraryStore.Loaded.Day] = []
                for day in source where date == Dates.allDates || day.date == date {
                    var trains: [Train] = []
                    for train in day.trains {
                        try Task.checkCancellation()
                        if JourneySearchMatcher.matches(train, query: query, alsoNamed: { names[$0.id] ?? [] }) {
                            trains.append(train)
                        }
                    }
                    if !trains.isEmpty { result.append(.init(date: day.date, trains: trains)) }
                }
                return result
            }
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            days = result; completed = request
        } catch { }
    }
}
