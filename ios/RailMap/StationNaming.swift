import Foundation
import RailCore

// =========================================================================
//  StationNaming.swift — how a JOURNEY's station names reach the readings
//  table.
//
//  The table itself is `app/data/station-readings*.json`, one per region,
//  installed into one `Localization` engine per region by `AppLocalization`.
//  Two things have to be true before a name it holds can be found, and the
//  journey surfaces used to get both of them wrong:
//
//  1. **The right engine has to be asked.** `AppLocalization.naming` picks
//     it from the station code, and `Region.fromStationCode` reads the
//     PACKAGE's ids — `tw-official-…`, `hk-official-…`, six ASCII digits for
//     Japan. A journey does not carry those. Its stops carry the OPERATOR's
//     own code (`TYMC-A13`, `AEL-MTR-HOK`, `MLM-TAIPA-MLM-BARRA`), which
//     names no region, so every Taiwanese, Hong Kong and Macanese stop fell
//     through to Japan's engine — and Japan's table annotates rather than
//     replaces, so `stationName` handed the name straight back. A caller
//     that has the journey knows better: `Region.resolved(_:)` answers from
//     the record's own `region` field, its stops, or its sections.
//
//  2. **A code has to be passed at all.** Without one the lookup is the
//     table's by-NAME fallback, which is deliberately incomplete: a name
//     that names two stations (嘉義 is both a TRA station and an Alishan
//     one) is left out of it rather than resolved by coin toss. The stop
//     carrying the name has the code — every stop in every shipped store
//     outside Japan resolves in its table's `byCode` — so it is only ever a
//     matter of handing it along.
//
//  `origin` and `destination` are the record's own two names for the ends of
//  a ride and are NOT guaranteed to be spelled the way its first and last
//  stop are (`JourneySearchMatcher` says the same thing for the same
//  reason). So a code is adopted only when the stop it comes from is the
//  same station by ``Stations/normalizeStationName(_:)`` — a code that
//  disagreed with the name would not merely fail to translate, it would
//  return a DIFFERENT station's name, `byCode` being consulted first.
// =========================================================================

extension Train {

    /// The station code the readings table should be asked with when naming
    /// ``origin`` — the origin-typed stop's, or the first stop's, and only
    /// when that stop is spelled as the same station.
    var originStationCode: String? {
        endpointStationCode(named: origin, stopType: "origin", fallback: stops.first)
    }

    /// ``originStationCode``'s mirror for ``destination``.
    var destinationStationCode: String? {
        endpointStationCode(named: destination, stopType: "destination", fallback: stops.last)
    }

    /// The code recorded for one of this journey's own stops, by name.
    ///
    /// For the surfaces that hold a name lifted out of a section or a gap
    /// rather than a stop — they know the stop INDEX, which is the better
    /// answer when they have it; this is for when they do not.
    func stationCode(named name: String) -> String? {
        let key = Stations.normalizeStationName(name)
        guard !key.isEmpty else { return nil }
        for stop in stops where Stations.normalizeStationName(stop.name) == key {
            if let code = stop.n02StationCode, !code.isEmpty { return code }
        }
        return nil
    }

    private func endpointStationCode(
        named name: String, stopType: String, fallback: Stop?
    ) -> String? {
        let key = Stations.normalizeStationName(name)
        guard !key.isEmpty else { return nil }
        func code(of stop: Stop?) -> String? {
            guard let stop, let code = stop.n02StationCode, !code.isEmpty else { return nil }
            // `stop.name == name` settles it without normalising, and in every
            // shipped store it settles nearly all of them: an endpoint is
            // spelled the way its own stop is spelled unless somebody typed it
            // twice. The shortcut cannot change an answer, because
            // `normalizeStationName` is a function of the canonical form and
            // Swift's `==` IS canonical equivalence — two strings that compare
            // equal normalise to the same key by construction.
            //
            // Worth the line: `normalizeStationName` runs NFKC and then NFC
            // over a fresh UTF-16 array, and it is the most expensive thing
            // this file does. It used to run twice per endpoint, and with the
            // search box now naming every journey's stations on every
            // keystroke (see ``localizedStationNames(of:)``) that was half the
            // cost of the whole pass — `ios/tools/bench`, `search`.
            guard stop.name == name || Stations.normalizeStationName(stop.name) == key
            else { return nil }
            return code
        }
        if let typed = code(of: stops.first(where: { $0.stopType == stopType })) { return typed }
        return code(of: fallback)
    }
}

/// What ``AppLocalization/localizedStationNames(of:)`` currently answers by.
///
/// A memoised search result is only reusable while the names behind it have
/// not moved, and two things move them without touching the store: the reader
/// changing the app's language, and one of the five readings tables landing —
/// ``StationReadingsStore`` decodes them off the main actor over the seconds
/// after launch, so a search typed in that window is answered by a table that
/// arrives a moment later. Neither is visible in a journey's fields, which is
/// why ``WorkspaceDerived`` keys its filtered days on this as well.
///
/// The three reading toggles are deliberately absent: they select the kana /
/// romaji / zh sublines under a Japanese name and cannot change what
/// `stationName` returns. See ``MapNaming``, which carries them because the
/// map draws those sublines and this does not.
struct StationNamingGeneration: Equatable {
    var language: Localization.Language
    var readings: Int
}

@MainActor
extension AppLocalization {

    /// One of a journey's station names, as the reader's language spells it.
    ///
    /// The region comes from the journey rather than from the code, for the
    /// reason this file exists. `code` is the stop's when the caller has the
    /// stop in hand; when it is nil the journey is searched for one by name
    /// before the table's by-name fallback is relied on.
    func stationName(_ name: String?, in train: Train, code: String? = nil) -> String {
        guard let name, !name.isEmpty else { return "" }
        return stationName(
            name,
            code: code ?? train.stationCode(named: name),
            region: Region.resolved(train))
    }

    /// The journey's origin, named.
    func originName(of train: Train) -> String {
        stationName(train.origin, in: train, code: train.originStationCode)
    }

    /// The journey's destination, named.
    func destinationName(of train: Train) -> String {
        stationName(train.destination, in: train, code: train.destinationStationCode)
    }

    /// The current value of everything ``localizedStationNames(of:)`` reads
    /// besides the journey itself.
    var stationNamingGeneration: StationNamingGeneration {
        StationNamingGeneration(language: language, readings: readingsGeneration)
    }

    /// Every station on a journey under the spelling the reader is actually
    /// shown, minus the ones the record already spells that way — what
    /// `JourneySearchMatcher`'s `alsoNamed` wants.
    ///
    /// The search box used to see only the store. A Taiwanese journey records
    /// 台北車站 and an English reader is looking at "Taipei Main Station", so
    /// typing what was on the screen returned nothing at all.
    ///
    /// ## What it deliberately does not return
    ///
    /// The names the reader is *shown*, not every name the table holds.
    /// ``Localization/stationNameAliases(_:code:)`` would return all six
    /// spellings of every station, which is the right answer for
    /// `StationPlaceLink` — it matches against Apple Maps, which answers in
    /// the DEVICE's language rather than the app's — and the wrong one here.
    /// This is a per-keystroke scan over every journey and each extra spelling
    /// is another locale-aware substring search per stop; `ios/tools/bench`
    /// prints what all six cost beside what one costs. The defect being fixed
    /// is "the name on the screen finds nothing", and the name on the screen
    /// is one name.
    ///
    /// ## Why it is nearly free for a Japanese journey
    ///
    /// Japan's readings table *annotates* a name with kana and romaji rather
    /// than replacing it, so `stationName` hands a Japanese name straight
    /// back and every entry here would be dropped by the equality test below.
    /// ``localizesStationNames(in:)`` says so before the loop rather than
    /// after it, which is what keeps the national store's search at the cost
    /// it had. It is also what a region whose table has not landed yet
    /// answers, and that is correct: the surfaces are still showing the
    /// record's own spelling in that window, so it is still the only spelling
    /// worth searching.
    ///
    /// The region is resolved ONCE. ``stationName(_:in:code:)`` re-resolves it
    /// per name, which is a scan of the journey's stops for a code that names
    /// a region — affordable when a card draws one name, not when a keystroke
    /// draws forty per journey over two hundred journeys.
    func localizedStationNames(of train: Train) -> [String] {
        let region = Region.resolved(train)
        guard localizesStationNames(in: region) else { return [] }
        var names: [String] = []
        names.reserveCapacity(train.stops.count + 2)
        func add(_ recorded: String?, code: String?) {
            guard let recorded, !recorded.isEmpty else { return }
            let localized = stationName(recorded, code: code, region: region)
            // A spelling the record already carries is one `fields(of:)`
            // already searches, and searching it twice is the whole per-stop
            // cost paid for no possible extra hit. In Traditional Chinese —
            // which is what a Taiwanese store is usually written in — that is
            // every station on the journey.
            guard !localized.isEmpty, localized != recorded else { return }
            names.append(localized)
        }
        // `origin` and `destination` before the stops, and by their own codes:
        // they are the record's own two names for the ends of the ride and are
        // not guaranteed to be spelled the way the first and last stop are.
        // See this file's note, and `JourneySearchMatcher.fields(of:)`.
        //
        // Usually they ARE spelled that way, so two of the names below are
        // repeats of two others, and they are left in rather than deduplicated:
        // the endpoints are two entries out of a journey's twenty, and a
        // `contains` per name would cost more compares than the two repeated
        // substring searches it saves. Measured — `ios/tools/bench`, `search`.
        add(train.origin, code: train.originStationCode)
        add(train.destination, code: train.destinationStationCode)
        for stop in train.stops { add(stop.name, code: stop.n02StationCode) }
        return names
    }

    /// Which region's readings table knows a station by NAME alone, when
    /// exactly one of them does.
    ///
    /// For the surfaces that hold a name and nothing else — the statistics
    /// screen's frequently-ridden sections are named by
    /// `topRiddenSegments`, whose rows carry the two endpoint names and no
    /// codes, and whose scope can be every region at once. Asking each table
    /// in turn is the only thing left, so the answer is only accepted when it
    /// is unambiguous: two regions offering DIFFERENT names for one spelling
    /// means the name does not identify a station, and the record's own
    /// spelling stands.
    ///
    /// Japan can never be the answer, and that is correct rather than a gap:
    /// its table annotates a name with kana and romaji instead of replacing
    /// it, so `stationName` hands a Japanese name straight back and there is
    /// nothing here to choose it by. `nil` reaches Japan's engine anyway.
    func regionNaming(_ name: String?) -> Region? {
        guard let name, !name.isEmpty else { return nil }
        var claimed: (region: Region, named: String)?
        for region in Region.allCases {
            let named = stationName(name, region: region)
            guard named != name else { continue }
            if let claimed, claimed.named != named { return nil }
            if claimed == nil { claimed = (region, named) }
        }
        return claimed?.region
    }
}
