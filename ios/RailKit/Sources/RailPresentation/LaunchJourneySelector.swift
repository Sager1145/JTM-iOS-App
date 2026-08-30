import Foundation
import RailCore

/// Chooses the journey whose country should frame the map at launch.
///
/// This rule deliberately receives the complete store. UI scopes such as the
/// selected country or date describe what the reader is looking at now; they
/// must not rewrite which journey is first in the log when the app opens.
public enum LaunchJourneySelector {

    /// The first timed upcoming journey, or the first timed historical one.
    ///
    /// - Parameters:
    ///   - trains: Every journey in the store, before any UI filtering.
    ///   - today: The current civil date for a journey's own region.
    /// - Returns: `nil` when no journey has both a valid date and a stop time.
    public static func first(
        in trains: [Train],
        today: (Train) -> String?
    ) -> Train? {
        let candidates = trains.compactMap { train -> Candidate? in
            guard hasTime(train),
                  let date = Dates.normalizeDateString(train.date),
                  let today = Dates.normalizeDateString(today(train))
            else { return nil }
            return Candidate(train: train, date: date, today: today)
        }

        if let upcoming = candidates
            .filter({ $0.date >= $0.today })
            .min(by: comesBefore)
        {
            return upcoming.train
        }
        return candidates
            .filter { $0.date < $0.today }
            .min(by: comesBefore)?
            .train
    }

    /// A route-only demonstration has no time and must not decide the launch
    /// country. One arrival or departure is enough for a hand-entered journey
    /// to count; whitespace by itself is not.
    public static func hasTime(_ train: Train) -> Bool {
        train.stops.contains { stop in
            [stop.arrival, stop.departure].contains { value in
                guard let value else { return false }
                return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        }
    }

    private struct Candidate {
        let train: Train
        let date: String
        let today: String

        var sortable: Dates.Train {
            Dates.Train(
                id: train.id,
                date: date,
                stops: train.stops.map {
                    Dates.Stop(
                        arrival: $0.arrival,
                        departure: $0.departure,
                        stopType: $0.stopType)
                })
        }
    }

    private static func comesBefore(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        Dates.compareByDateAndDeparture(lhs.sortable, rhs.sortable) < 0
    }
}
