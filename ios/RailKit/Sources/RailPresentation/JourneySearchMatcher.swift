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
    /// Multilingual folded matching for names; dates and IDs retain separators.
    /// Operator aliases
    /// and related operator families included in company discovery.
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
        return matches(train, prepared: SearchFold.PreparedQuery(needle), needle: needle,
                       operatorCodes: OperatorIdentity.exactCodes(query: needle), alsoNamed: alsoNamed)
    }

    /// A prepared query is shared across all journeys in a filter operation.
    private static func matches(
        _ train: Train, prepared: SearchFold.PreparedQuery, needle: String,
        operatorCodes: Set<String>?, alsoNamed: (Train) -> [String]
    ) -> Bool {
        guard !prepared.whole.isEmpty else { return false }
        if let operatorCodes {
            return !Set(OperatorIdentity.codes(forJoined: train.company ?? "")).isDisjoint(with: operatorCodes)
        }
        func hit(_ field: String?) -> Bool {
            guard let field, !field.isEmpty else { return false }
            return prepared.matches(fields: [field])
        }
        if hit(train.number) || hit(train.numberEn) || hit(train.origin) || hit(train.destination) {
            return true
        }
        for stop in train.stops where hit(stop.name) { return true }
        if train.date?.localizedCaseInsensitiveContains(needle) == true
            || hit(train.direction) || hit(train.trainType)
            || train.company.map({ prepared.matches(fields: OperatorIdentity.searchNames(for: $0)) }) == true
            || train.id.localizedCaseInsensitiveContains(needle) {
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
        var fields: [String] = [train.number]
        if let numberEn = train.numberEn, !numberEn.isEmpty {
            fields.append(numberEn)
        }
        fields.append(contentsOf: [
            train.origin,
            train.destination,
        ])
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
        let prepared = SearchFold.PreparedQuery(needle)
        let operatorCodes = OperatorIdentity.exactCodes(query: needle)
        return trains.filter { matches($0, prepared: prepared, needle: needle,
                                       operatorCodes: operatorCodes, alsoNamed: alsoNamed) }
    }
}
