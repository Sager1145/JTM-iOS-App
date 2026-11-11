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
    /// "Did you mean …?" when the completed query matched no journey: up to
    /// three of the closest station/train/type spellings in the searched
    /// journeys (shared search engine). Empty otherwise.
    private(set) var corrections: [SearchCorrection] = []
    /// What the typed text completes to: the top matching name in the journeys.
    private(set) var completion: String?
    /// Empty box: the stations these journeys name most often.
    private(set) var frequentNames: [String] = []
    @ObservationIgnored private var vocabulary: SearchIndex?
    @ObservationIgnored private var source: [ItineraryStore.Loaded.Day] = []
    @ObservationIgnored private var naming: StationNamingGeneration?
    @ObservationIgnored private var names: [String: [String]] = [:]

    func search(_ request: Request, alsoNamed: (Train) -> [String]) async {
        guard request != completed else { return }
        guard !request.query.isEmpty else {
            let trains = request.days.flatMap(\.trains)
            let frequent = await Task.detached(priority: .userInitiated) {
                JourneySearchMatcher.frequentStationNames(in: trains)
            }.value
            guard !Task.isCancelled else { return }
            days = []; corrections = []; completion = nil; frequentNames = frequent; completed = request
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(150))
            // Localization is UI-owned. Snapshot its inexpensive lookups
            // once per store/language generation, never once per keystroke.
            if naming != request.naming || !ArrayGeneration.same(source, request.days) {
                RailSignpost.ui.mark("derived.journeySearch", request.days.count)
                var snapshot: [String: [String]] = [:]
                for day in request.days {
                    try Task.checkCancellation()
                    for train in day.trains { snapshot[train.id] = alsoNamed(train) }
                    await Task.yield()
                }
                try Task.checkCancellation()
                source = request.days; naming = request.naming; names = snapshot
                let trains = request.days.flatMap(\.trains)
                let spellings = snapshot
                vocabulary = await Task.detached(priority: .userInitiated) {
                    JourneySearchMatcher.vocabulary(of: trains, alsoNamed: { spellings[$0.id] ?? [] })
                }.value
                try Task.checkCancellation()
            }
            let names = names
            let source = request.days
            let date = request.date
            let query = request.query
            let vocabulary = vocabulary
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
                let completion = vocabulary?.query(
                    query, scope: .terms, context: SearchContext(regionCode: "", limit: 1)).completion
                guard result.isEmpty else { return (result, [SearchCorrection](), completion) }
                // Nothing matched: offer the closest spelling (typos are not matched per journey).
                let searched = source.filter { date == Dates.allDates || $0.date == date }.flatMap(\.trains)
                try Task.checkCancellation()
                let corrections = JourneySearchMatcher.suggestions(
                    for: query, in: searched, alsoNamed: { names[$0.id] ?? [] })
                return (result, corrections, completion)
            }
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            days = result.0; corrections = result.1; completion = result.2; completed = request
        } catch { }
    }
}
