import Foundation
import RailCore
import RailPresentation

/// §5.1's journey search, over the real national store.
///
/// The interaction being modelled is a reader typing: the field publishes on
/// every keystroke, so the list is re-filtered once per character. That is what
/// the "typing" row measures — one filter per prefix of a real query — rather
/// than a single filter of the finished word, which is the number a benchmark
/// gets wrong in the app's favour.
func benchmarkSearch(root: URL) {
    let url = root.appending(path: "app/data/sample-data/sample-full.json")
    guard let data = try? Data(contentsOf: url),
          let store = try? JSONDecoder().decode(TrainStore.self, from: data)
    else {
        print("search: sample-full.json unavailable")
        return
    }
    let trains = store.trains
    let stops = trains.reduce(0) { $0 + $1.stops.count }
    print("\nsearch — \(trains.count) journeys, \(stops) stops")

    // Four queries with different selectivity, each typed one character at a
    // time. "ひかり" matches many; "9999" matches none, which is the case that
    // scans every field of every record and therefore the worst one.
    let queries = ["ひかり", "Odoriko", "東京", "9999"]
    let prefixes: [String] = queries.flatMap { query in
        (1...query.count).map { String(query.prefix($0)) }
    }

    measure("filter, whole typed query (\(queries.count) queries)") {
        var total = 0
        for query in queries {
            total += JourneySearchMatcher.filter(trains, query: query).count
        }
        return total
    }

    measure("filter, one pass per keystroke (\(prefixes.count) presses)") {
        var total = 0
        for prefix in prefixes {
            total += JourneySearchMatcher.filter(trains, query: prefix).count
        }
        return total
    }

    // Where the time actually goes. If the flat scan over the same strings
    // costs what the matcher costs, then the matcher's shape is irrelevant and
    // only the number of ICU searches matters.
    let flat = trains.flatMap { JourneySearchMatcher.fields(of: $0) }
    print("  \(flat.count) searchable strings")
    measure("ICU scan alone, same strings, same keystrokes") {
        var total = 0
        for prefix in prefixes {
            for field in flat where field.localizedCaseInsensitiveContains(prefix) {
                total += 1
            }
        }
        return total
    }

    measure("fields(of:) for every journey") {
        var total = 0
        for train in trains { total += JourneySearchMatcher.fields(of: train).count }
        return total
    }
}

// =========================================================================
//  What the localized station names cost.
//
//  `JourneySearchMatcher` gained an `alsoNamed` parameter so the search box
//  can find a station by the spelling the reader is actually shown: the
//  journey surfaces name stations through the readings table, so a Taiwanese
//  ride recorded as 台北車站 reads "Taipei Main Station" to an English reader,
//  and typing that used to return nothing.
//
//  This runs per keystroke over every journey, which is why it is measured
//  rather than reasoned about. The whole cost is in two places and they scale
//  differently:
//
//    * producing the names — one dictionary hit per stop, plus the NFKC
//      normalisation `originStationCode` performs — paid once per journey no
//      recorded field already answered for;
//    * searching them — one more `localizedCaseInsensitiveContains` per name,
//      and the baseline above says that ICU scan IS the search.
//
//  So the number that matters is how many strings are added, and the answer
//  depends on the reader's language: Traditional Chinese is what a Taiwanese
//  store is written in, so the table hands back the record's own spelling and
//  every name is dropped before the matcher sees it.
//
//  The app-target glue this cannot see is one property read: `Region.resolved`
//  returns `train.region`, which `RegionCodeIndex` stamps into every ride once
//  before it is ever published. The stores below carry it, as a saved store
//  does.
// =========================================================================

/// `StationReadingsStore`'s decode of `station-readings-*.json`.
private struct BenchReadingRow: Decodable {
    let kana: String?
    let romaji: String?
    let zhHant: String?
    let zhHans: String?
    let ja: String?
    let en: String?
    enum CodingKeys: String, CodingKey {
        case kana, romaji, ja, en
        case zhHant = "zh_Hant"
        case zhHans = "zh_Hans"
    }
    var row: Localization.StationReadingRow {
        .init(kana: kana, romaji: romaji, zhHant: zhHant, zhHans: zhHans, ja: ja, en: en)
    }
}

private struct BenchReadingTable: Decodable {
    let country: String?
    let byCode: [String: BenchReadingRow]?
    let byName: [String: BenchReadingRow]?
}

/// `AppLocalization`'s one-engine-per-region arrangement, in the two regions
/// these stores use.
private struct BenchNaming {
    var engines: [String: Localization] = [:]

    /// `AppLocalization.stationName(_:code:region:)` for a region already
    /// settled by the ride's own `region` field.
    func stationName(_ name: String, code: String?, region: String) -> String {
        engines[region]?.stationName(name, code: code) ?? name
    }

    /// `AppLocalization.localizesStationNames(in:)`.
    func localizes(_ region: String) -> Bool {
        guard let engine = engines[region] else { return false }
        return Localization.localizedNameCountries.contains(engine.stationReadings.country)
    }

    func aliases(_ name: String, code: String?, region: String) -> [String] {
        engines[region]?.stationNameAliases(name, code: code) ?? []
    }
}

/// `Train.originStationCode` / `destinationStationCode` (app target,
/// `StationNaming.swift`) — a stop's code is adopted for an endpoint only when
/// the stop is the same station by the one name-key rule.
private func benchEndpointCode(_ train: Train, name: String, type: String, fallback: Stop?)
    -> String?
{
    let key = Stations.normalizeStationName(name)
    guard !key.isEmpty else { return nil }
    func code(of stop: Stop?) -> String? {
        guard let stop, let code = stop.n02StationCode, !code.isEmpty else { return nil }
        guard stop.name == name || Stations.normalizeStationName(stop.name) == key
        else { return nil }
        return code
    }
    if let typed = code(of: train.stops.first(where: { $0.stopType == type })) { return typed }
    return code(of: fallback)
}

/// `AppLocalization.localizedStationNames(of:)`, verbatim but for the region
/// lookup — see the note above.
private func benchLocalizedNames(_ naming: BenchNaming) -> (Train) -> [String] {
    { train in
        let region = train.region ?? "jp"
        guard naming.localizes(region) else { return [] }
        var names: [String] = []
        names.reserveCapacity(train.stops.count + 2)
        func add(_ recorded: String?, _ code: String?) {
            guard let recorded, !recorded.isEmpty else { return }
            let localized = naming.stationName(recorded, code: code, region: region)
            guard !localized.isEmpty, localized != recorded else { return }
            names.append(localized)
        }
        add(train.origin, benchEndpointCode(
            train, name: train.origin, type: "origin", fallback: train.stops.first))
        add(train.destination, benchEndpointCode(
            train, name: train.destination, type: "destination", fallback: train.stops.last))
        for stop in train.stops { add(stop.name, stop.n02StationCode) }
        return names
    }
}

/// The rejected alternative: every spelling the table holds rather than the
/// one the reader is shown. See `StationNaming.swift`.
private func benchAllAliases(_ naming: BenchNaming) -> (Train) -> [String] {
    { train in
        let region = train.region ?? "jp"
        var names: [String] = []
        for stop in train.stops {
            for alias in naming.aliases(stop.name, code: stop.n02StationCode, region: region)
            where alias != stop.name {
                names.append(alias)
            }
        }
        return names
    }
}

func benchmarkLocalizedSearch(root: URL) {
    func store(_ path: String, region: String) -> [Train]? {
        guard let data = try? Data(contentsOf: root.appending(path: path)),
              let store = try? JSONDecoder().decode(TrainStore.self, from: data)
        else { return nil }
        // What `RegionCodeIndex.tagging` writes before a ride is published.
        return store.trains.map { train in
            var copy = train
            copy.region = region
            return copy
        }
    }
    guard let japan = store("app/data/sample-data/sample-full.json", region: "jp"),
          let taiwan = store("app/data/train-store-tw.json", region: "tw"),
          let readingsData = try? Data(
              contentsOf: root.appending(path: "app/data/station-readings-tw.json")),
          let raw = try? JSONDecoder().decode(BenchReadingTable.self, from: readingsData),
          let catalog = try? Localization.Catalog(
              data: Data(#"{"sourceLanguage":"en","version":"1.0","strings":{}}"#.utf8))
    else {
        print("\nlocalized names: fixtures unavailable")
        return
    }
    let table = Localization.StationReadings(
        country: raw.country,
        byCode: (raw.byCode ?? [:]).mapValues(\.row),
        byName: (raw.byName ?? [:]).mapValues(\.row))

    func naming(_ language: Localization.Language) -> BenchNaming {
        BenchNaming(engines: [
            // Japan's engine annotates rather than replaces, exactly as the
            // app's does — the table is never even consulted here, because
            // `localizes("jp")` is false.
            "jp": Localization(catalog: catalog, language: language),
            "tw": Localization(catalog: catalog, language: language, stationReadings: table),
        ])
    }

    // The mixed store is the realistic one: this app draws all five networks
    // at once and a reader's saved store is whatever they have ridden. The
    // Taiwan-only store is the adversarial one — every journey pays.
    let stores: [(name: String, trains: [Train])] = [
        ("mixed jp+tw", japan + taiwan),
        ("tw only", taiwan),
    ]
    // The English name of a Taiwanese station, typed one character at a time,
    // plus a query that matches nothing — the case that scans every field of
    // every record, which is where an added field costs the most.
    let query = "Taipei Main Station"
    let prefixes = (1...query.count).map { String(query.prefix($0)) } + ["9999"]

    for (storeName, trains) in stores {
        print("\nlocalized names — \(storeName): \(trains.count) journeys, "
            + "\(trains.reduce(0) { $0 + $1.stops.count }) stops, "
            + "\(trains.flatMap { JourneySearchMatcher.fields(of: $0) }.count) searchable strings")

        for language in [Localization.Language.zhHant, .en] {
            let alsoNamed = benchLocalizedNames(naming(language))
            let added = trains.reduce(0) { $0 + alsoNamed($1).count }
            let hits = JourneySearchMatcher.filter(
                trains, query: query, alsoNamed: alsoNamed).count
            let before = JourneySearchMatcher.filter(trains, query: query).count
            print("  \(language.rawValue): +\(added) strings, "
                + "\"\(query)\" finds \(before) → \(hits) journeys")
            measure("  \(language.rawValue) — before, \(prefixes.count) keystrokes") {
                var total = 0
                for prefix in prefixes {
                    total += JourneySearchMatcher.filter(trains, query: prefix).count
                }
                return total
            }
            measure("  \(language.rawValue) — after, \(prefixes.count) keystrokes") {
                var total = 0
                for prefix in prefixes {
                    total += JourneySearchMatcher.filter(
                        trains, query: prefix, alsoNamed: alsoNamed).count
                }
                return total
            }
            // The two halves of that difference, separated: this is the
            // producing, and the rest of it is one more ICU scan per name.
            // A worst case — the matcher asks only for a journey no recorded
            // field has already answered for.
            measure("  \(language.rawValue) — producing the names alone, same passes") {
                var total = 0
                for _ in prefixes {
                    for train in trains { total += alsoNamed(train).count }
                }
                return total
            }
        }

        // The alternative that was not taken, on the same store.
        let everySpelling = benchAllAliases(naming(.en))
        let addedAll = trains.reduce(0) { $0 + everySpelling($1).count }
        print("  every spelling the table holds: +\(addedAll) strings")
        measure("  all six spellings, \(prefixes.count) keystrokes") {
            var total = 0
            for prefix in prefixes {
                total += JourneySearchMatcher.filter(
                    trains, query: prefix, alsoNamed: everySpelling).count
            }
            return total
        }
    }
}
