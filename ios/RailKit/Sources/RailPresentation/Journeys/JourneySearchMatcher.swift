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
    /// An operator query matches `operatorID` only. A ride with no id does not
    /// match that query by its company string.
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
        return matches(train, prepared: SearchTextQuery(needle), needle: needle, alsoNamed: alsoNamed)
    }

    /// A prepared query is shared across all journeys in a filter operation.
    ///
    /// Matching is the shared engine's (`SearchTextQuery`): simplified/traditional
    /// and shinjitai variants, kana, romaji spelling variants and cross-language
    /// synonyms, as exact/prefix/substring. Typos are not matched per journey —
    /// they would widen every list; ``suggestion(for:in:alsoNamed:)`` offers the
    /// corrected spelling instead.
    private static func matches(
        _ train: Train, prepared: SearchTextQuery, needle: String,
        alsoNamed: (Train) -> [String]
    ) -> Bool {
        guard !prepared.isEmpty else { return false }
        let operatorIDs = queryOperatorIDs(needle, region: train.region)
        if !operatorIDs.isEmpty {
            var ride: Set<String> = []
            if let operatorID = train.operatorID, !operatorID.isEmpty { ride.insert(operatorID) }
            if let more = train.operatorIDs { ride.formUnion(more) }
            guard !ride.isEmpty else { return false }
            return !ride.isDisjoint(with: operatorIDs)
        }
        func hit(_ field: String?) -> Bool {
            guard let field, !field.isEmpty else { return false }
            return prepared.matchesAll(fields: [field])
        }
        if hit(train.number) || hit(train.numberEn) || hit(train.origin) || hit(train.destination) {
            return true
        }
        for stop in train.stops where hit(stop.name) { return true }
        if train.date?.localizedCaseInsensitiveContains(needle) == true
            || hit(train.direction) || hit(train.trainType)
            || train.id.localizedCaseInsensitiveContains(needle) {
            return true
        }
        return alsoNamed(train).contains(where: { hit($0) })
    }

    /// Operator ids the query names in this ride's region. Empty when the query is not an operator.
    private static func queryOperatorIDs(_ query: String, region: String?) -> Set<String> {
        guard let region, !region.isEmpty,
              let identity = RegistryIdentityCache.identity(forRegion: region) else { return [] }
        return identity.operatorIDs(matchingQuery: query)
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
        let prepared = SearchTextQuery(needle)
        return trains.filter { matches($0, prepared: prepared, needle: needle, alsoNamed: alsoNamed) }
    }

    /// "Did you mean …?" for a journey query: the closest station name, train
    /// name or type spelled in these journeys, when the query matches none of them.
    /// Nil when the query already matches, or nothing is close.
    public static func suggestion(
        for query: String, in trains: [Train], alsoNamed: (Train) -> [String] = { _ in [] }
    ) -> SearchCorrection? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, filter(trains, query: needle, alsoNamed: alsoNamed).isEmpty else { return nil }
        return vocabulary(of: trains, alsoNamed: alsoNamed)
            .query(needle, scope: .terms, context: SearchContext(regionCode: "", limit: 5)).didYouMean
    }

    /// Completion candidates for a journey search box: names spelled in these
    /// journeys, ranked exact > prefix > substring > typo, frequent first.
    public static func completions(
        for query: String, in trains: [Train], alsoNamed: (Train) -> [String] = { _ in [] }, limit: Int = 8
    ) -> [SearchResult] {
        vocabulary(of: trains, alsoNamed: alsoNamed)
            .query(query, scope: .terms, context: SearchContext(regionCode: "", limit: limit)).results
    }

    /// Station, train and type names in these journeys, weighted by how often they occur.
    /// Build once per store generation when used per keystroke.
    public static func vocabulary(
        of trains: [Train], alsoNamed: (Train) -> [String] = { _ in [] }
    ) -> SearchIndex {
        var counts: [String: Int] = [:]
        var order: [String] = []
        func add(_ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            if counts[value] == nil { order.append(value) }
            counts[value, default: 0] += 1
        }
        for train in trains {
            add(train.number); add(train.numberEn); add(train.origin); add(train.destination)
            add(train.trainType); add(train.company)
            for stop in train.stops { add(stop.name) }
            for name in alsoNamed(train) { add(name) }
        }
        let top = Float(counts.values.max() ?? 1)
        return SearchIndexBuilder.vocabulary(
            order, weights: counts.mapValues { log2(1 + Float($0)) / log2(1 + top) })
    }
}
