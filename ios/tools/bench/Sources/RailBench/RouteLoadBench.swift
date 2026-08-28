import Foundation
import RailCore

/// The route store's warm path.
///
/// `loadCached` asks two questions per journey — what is this route's cache
/// digest, and what sections did it ask for — and each of them normalises the
/// whole record through `TrainValidation.normalizeExportTrain`. A cache HIT
/// therefore normalises twice, and a solve that is then written back
/// normalises a third time for the file name.
func benchmarkRouteLoad(root: URL) {
    let storeURL = root.appending(path: "app/data/sample-data/sample-full.json")
    guard let data = try? Data(contentsOf: storeURL),
          let store = try? JSONDecoder().decode(TrainStore.self, from: data)
    else {
        print("routes: sample-full.json unavailable")
        return
    }
    let trains = store.trains
    let sections = trains.reduce(0) { $0 + ($1.routeSections?.count ?? 0) }
    print("\nroute load — \(trains.count) journeys, \(sections) route sections")

    measure("normalizeExportTrain ×\(trains.count)", repeats: 7) {
        var total = 0
        for train in trains {
            let canonical = TrainValidation.normalizeExportTrain(
                train, country: "jp", stations: TrainValidation.StationTable.empty)
            total += canonical.routeSections?.count ?? 0
        }
        return total
    }

    measure("cache digest ×\(trains.count) (normalize + solveContext + keyDigest)", repeats: 7) {
        var total = 0
        for train in trains {
            let canonical = TrainValidation.normalizeExportTrain(
                train, country: "jp", stations: TrainValidation.StationTable.empty)
            let canonicalSections = canonical.routeSections ?? []
            let mapped = canonicalSections.map { section in
                RouteGraph.RouteSection(
                    from: section.from, to: section.to,
                    fromStationCode: section.fromN02StationCode,
                    toStationCode: section.toN02StationCode,
                    lineNames: section.lineNames ?? [],
                    operatorNames: section.operatorNames ?? [])
            }
            let policy = canonical.routePolicy
            let cacheTrain = RouteGraph.CacheKeyTrain(
                trainType: canonical.trainType ?? "", company: canonical.company ?? "",
                preferredLineNames: policy?.preferredLineNames ?? [],
                preferredOperatorNames: policy?.preferredOperatorNames ?? [],
                allowedInstitutionTypeCodes: policy?.allowedInstitutionTypeCodes,
                institutionFilterMode: policy?.institutionFilterMode)
            if let context = RouteGraph.solveContext(
                train: cacheTrain, routeSections: mapped, country: "jp") {
                total += RouteGraph.keyDigest(context.cacheKey).count
            }
        }
        return total
    }
}

/// Reading a route cache: 201 small files, one per journey.
///
/// `loadCached` walks the journeys in a `for` loop, and each turn is a
/// `Data(contentsOf:)` and a `JSONDecoder().decode` — synchronous, one after
/// another. The files are independent, so the only question is whether the
/// concurrency is worth having; this measures the same bytes read both ways.
/// The parts of the shipped sample dataset stand in for the cache files: same
/// count, same shape (one journey's solved segments), same order of size.
func benchmarkRouteCacheIO(root: URL) {
    let directory = root.appending(path: "app/data/sample-data")
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
    else { return }
    let urls = names.sorted()
        .filter { $0.hasPrefix("part-") && $0.hasSuffix(".json") }
        .map { directory.appending(path: $0) }
    let bytes = urls.reduce(0) { $0 + ((try? Data(contentsOf: $1))?.count ?? 0) }
    print("\nroute cache I/O — \(urls.count) files, \(bytes / 1024) KB")

    measure("read + decode sequentially", repeats: 7) {
        var total = 0
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            total += object.count
        }
        return total
    }

    for width in [4, 8] {
        measure("read + decode, \(width) at a time", repeats: 7) {
            let counter = Counter()
            DispatchQueue.concurrentPerform(iterations: width) { slot in
                var local = 0
                for index in Swift.stride(from: slot, to: urls.count, by: width) {
                    guard let data = try? Data(contentsOf: urls[index]),
                          let object = try? JSONSerialization
                            .jsonObject(with: data) as? [String: Any]
                    else { continue }
                    local += object.count
                }
                counter.add(local)
            }
            return counter.value
        }
    }
}

/// A lock around one integer, so the concurrent variant can be summed without
/// pretending a data race is a measurement.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0
    func add(_ amount: Int) {
        lock.lock(); total += amount; lock.unlock()
    }
    var value: Int { lock.lock(); defer { lock.unlock() }; return total }
}


/// The editor's authoritative validation, per keystroke.
///
/// `RideEditorView` re-runs the whole of `TrainValidation.validateTrain` on
/// every change to the draft — which is every character typed into any field —
/// and the authoritative half of that encodes the record to JSON first. This
/// measures it on the longest real journeys in the store, which is what a
/// long stop list costs.
func benchmarkEditorValidation(root: URL) {
    let storeURL = root.appending(path: "app/data/sample-data/sample-full.json")
    guard let data = try? Data(contentsOf: storeURL),
          let store = try? JSONDecoder().decode(TrainStore.self, from: data)
    else { return }
    let longest = store.trains
        .sorted { $0.stops.count > $1.stops.count }
        .prefix(5)
    print("\neditor validation — longest 5 journeys, "
        + "\(longest.map(\.stops.count).map(String.init).joined(separator: "/")) stops")

    let encoder = JSONEncoder()
    for train in longest.prefix(1) {
        measure("encode + validateTrain, \(train.stops.count) stops", repeats: 25) {
            guard let encoded = try? encoder.encode(train),
                  let text = String(data: encoded, encoding: .utf8),
                  let json = try? TrainValidation.JSON.parse(text)
            else { return 0 }
            var ids = Set<String>()
            do {
                try TrainValidation.validateTrain(json, index: 0, ids: &ids)
            } catch {
                return 1
            }
            return 2
        }
    }
}
