import Foundation
import RailCore

/// Which journeys a search box is asking for (§5.1).
///
/// The spec names the fields, and it names them for both platforms at once:
///
/// > 统一目标搜索字段为记录 ID、车次/班次名称、日期、方向、起终站、途中站、
/// > 车种与运营方；当前 iOS 已覆盖除日期/方向外的字段，Web 已覆盖全部，重构时
/// > 补齐 iOS parity。
///
/// So the list is a contract rather than a convenience, and a contract spelled
/// out inline in a `filter` closure is one that drifts the next time somebody
/// adds a field. Two fields — `date` and `direction` — were missing on iOS
/// exactly because that closure was the only place the list existed.
///
/// It lives here rather than in `RailCore` for the reason the whole target
/// exists: there is no JavaScript function this is a port of. The web app
/// spreads the same rule across `renderTrainList`'s predicate, so a parity
/// fixture would have nothing to compare against — but the *field list* still
/// has to be checkable, and `swift test` can reach this.
///
/// ## The names the record does not carry
///
/// A journey stores the station names it was written with — 台北車站 for a
/// Taiwanese ride — and the journey surfaces have since stopped showing those
/// verbatim: `StationNaming` sends every one through the readings table, so a
/// reader with the app in English is looking at "Taipei Main Station". Typing
/// what is on the screen then found nothing, because the store is the only
/// thing this file could see.
///
/// So every entry point takes ``alsoNamed``: a caller's answer to "what else
/// is this journey's stations called". It defaults to *nothing*, which is what
/// keeps the field list a contract this target can check on its own — the
/// table it would need is a megabyte of JSON in the app bundle, reached
/// through a `@MainActor` object that `RailPresentation` cannot import and
/// `swift test` cannot run. The one caller that can reach it passes it in.
public enum JourneySearchMatcher {

    /// Whether one journey answers a query.
    ///
    /// Case- and diacritic-insensitive substring matching, in the reader's
    /// locale: `localizedCaseInsensitiveContains` is what makes ｶﾞ find が and
    /// what keeps `odoriko` finding a record typed `Odoriko`. A `lowercased()`
    /// comparison would do neither, and would additionally get Turkish wrong.
    ///
    /// An empty or whitespace-only query matches everything, so a caller can
    /// hand the raw text field through without deciding first whether the
    /// reader has typed anything.
    ///
    /// - Parameter alsoNamed: the journey's station names as some other
    ///   language spells them — see the type's note. Called at most once per
    ///   journey, and only for a journey no recorded field has already
    ///   answered for.
    public static func matches(
        _ train: Train, query: String, alsoNamed: (Train) -> [String] = { _ in [] }
    ) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return matches(train, trimmed: needle, alsoNamed: alsoNamed)
    }

    /// The same answer, over a query that has already been trimmed.
    ///
    /// Two things are avoided by having this separately, and both were paid
    /// per JOURNEY rather than per query: `trimmingCharacters` allocates a new
    /// `String` and ``filter(_:query:)`` had already done it once; and
    /// ``fields(of:)`` builds and filters an array of up to forty strings
    /// before the first comparison is made, when the great majority of
    /// journeys are settled by their number — the first field.
    ///
    /// The membership of the fields is ``fields(of:)``'s and is checked
    /// against it by ``JourneySearchMatcherTests``, so this stays a faster
    /// spelling of the same contract rather than a second one.
    ///
    /// The *order* is ``fields(of:)``'s in one place only: ``alsoNamed`` is
    /// asked last here and listed beside the names it re-spells there. Both
    /// placements are deliberate. In the field list it belongs next to
    /// `origin`, `destination` and the stops, because that is what a reviewer
    /// checking §5.1 needs to see it as — the same stations, spelled again.
    /// Here it belongs after everything the record already carries, because it
    /// is the only field that costs a dictionary lookup per stop to produce,
    /// and a journey settled by its number must not pay for it. Which of two
    /// fields is compared first cannot change the answer, so the two orders
    /// are free to differ.
    static func matches(
        _ train: Train, trimmed needle: String, alsoNamed: (Train) -> [String] = { _ in [] }
    ) -> Bool {
        func hit(_ field: String?) -> Bool {
            guard let field, !field.isEmpty else { return false }
            return field.localizedCaseInsensitiveContains(needle)
        }
        if hit(train.number) || hit(train.origin) || hit(train.destination) {
            return true
        }
        for stop in train.stops where hit(stop.name) { return true }
        if hit(train.date) || hit(train.direction) || hit(train.trainType)
            || hit(train.company) || hit(train.id)
        {
            return true
        }
        return alsoNamed(train).contains(where: { hit($0) })
    }

    /// Every string one journey is searchable by, in §3.2's scan order.
    ///
    /// The order is the order a reader reads the record in, which is not an
    /// aesthetic choice: it is what makes the list reviewable against §5.1
    /// without cross-referencing the struct's field order, and it is why the
    /// identifier is last rather than first — §3.2 forbids the record id
    /// leading the journey's identity, and a list that leads with it invites
    /// exactly that mistake into the next surface that renders it.
    public static func fields(
        of train: Train, alsoNamed: (Train) -> [String] = { _ in [] }
    ) -> [String] {
        var fields: [String] = [
            train.number,
            train.origin,
            train.destination,
        ]
        // Intermediate stops. `origin` and `destination` are the record's own
        // two names for the ends of the ride and are NOT guaranteed to be
        // spelled the same as the first and last stop, so both are searched.
        fields.append(contentsOf: train.stops.map(\.name))
        // The same stations under another language's spelling, from a caller
        // that can reach the readings table. Here rather than at the end
        // because that is what they are — `origin`, `destination` and the
        // stops again — and §5.1 is reviewable only if they read that way.
        fields.append(contentsOf: alsoNamed(train).filter { !$0.isEmpty })
        fields.append(contentsOf: [
            train.date,
            train.direction,
            train.trainType,
            train.company,
        ].compactMap { $0 })
        fields.append(train.id)
        return fields.filter { !$0.isEmpty }
    }

    /// The journeys of one day that answer a query, in store order.
    public static func filter(
        _ trains: [Train], query: String, alsoNamed: (Train) -> [String] = { _ in [] }
    ) -> [Train] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return trains }
        return trains.filter { matches($0, trimmed: needle, alsoNamed: alsoNamed) }
    }
}
