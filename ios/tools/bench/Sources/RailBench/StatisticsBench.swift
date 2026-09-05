import Foundation
import RailCore

/// The mileage statistics, phase by phase.
///
/// `MileageStatisticsStore` runs three of them — read the network, match every
/// ride onto its edges, aggregate — and reloads all three whenever the record
/// changes, which since the shell's route key covered the whole record means
/// on every edit. Knowing which of the three that costs is the difference
/// between caching the right thing and adding a cache that buys nothing.
private func benchDates(_ train: Train) -> Dates.Train {
    Dates.Train(
        id: train.id, date: train.date,
        stops: train.stops.map {
            Dates.Stop(arrival: $0.arrival, departure: $0.departure, stopType: $0.stopType)
        })
}

func benchmarkStatistics(root: URL) {
    let sectionsURL = root.appending(path: "app/data/rail-sections.json")
    let storeURL = root.appending(path: "app/data/sample-data/sample-full.json")
    guard let sectionsData = try? Data(contentsOf: sectionsURL),
          let storeData = try? Data(contentsOf: storeURL),
          let store = try? JSONDecoder().decode(TrainStore.self, from: storeData)
    else {
        print("statistics: rail-sections.json or sample-full.json unavailable")
        return
    }
    print("\nstatistics — jp sections \(sectionsData.count / 1_048_576) MB, "
        + "\(store.trains.count) journeys")

    var index: Statistics.EdgeIndex?
    measure("read + index rail-sections.json (jp)", repeats: 3, warmup: 0) {
        let sections = (try? Statistics.SectionFeatureCollection.load(contentsOf: sectionsURL))?
            .sections ?? []
        let built = Statistics.buildEdgeIndex(sections: sections, country: "jp")
        index = built
        return built.km.count
    }
    guard let index else { return }
    print("  \(index.km.count) edges, \(index.totalKm.rounded()) km")

    // The ridden geometry, keyed the way the store keys it.
    let rides = loadBenchRides(root: root)
    let ridesByID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let trains = store.trains

    func features(for train: Train) -> [Statistics.RouteFeature] {
        let stops = train.stops.map {
            Statistics.Stop(
                arrival: $0.arrival, departure: $0.departure,
                stopType: $0.stopType, rideSegment: $0.rideSegment)
        }
        return (ridesByID[train.id]?.strokes ?? []).enumerated().map { offset, stroke in
            Statistics.RouteFeature(
                lines: [stroke], hasGeometry: true,
                rideSegment: Statistics.isRideSegment(stops, segmentIndex: offset),
                from: nil, to: nil)
        }
    }
    let prepared = trains.map { (train: $0, features: features(for: $0)) }

    measure("match every ride onto edges (collectTrainStatsEntry ×\(trains.count))", repeats: 5) {
        var entries: [Statistics.TrainEntry] = []
        entries.reserveCapacity(prepared.count)
        for item in prepared {
            entries.append(
                Statistics.collectTrainStatsEntry(features: item.features, index: index))
        }
        return entries.count
    }

    // What one edit re-matches if only the edited journey is re-matched.
    if let one = prepared.first(where: { !$0.features.isEmpty }) {
        measure("match ONE ride", repeats: 25) {
            Statistics.collectTrainStatsEntry(features: one.features, index: index).edges.count
        }
    }

    let statisticsTrains = trains.map { train in
        Statistics.Train(
            id: train.id, trainType: train.trainType,
            date: Dates.trainDate(benchDates(train)),
            stops: train.stops.map {
                Statistics.Stop(
                    arrival: $0.arrival, departure: $0.departure,
                    stopType: $0.stopType, rideSegment: $0.rideSegment)
            })
    }
    let entries = prepared.map {
        Statistics.collectTrainStatsEntry(features: $0.features, index: index)
    }
    measure("aggregate (buildMileageStatsView, all dates)", repeats: 7) {
        Statistics.buildMileageStatsView(
            index: index, trains: statisticsTrains, entries: entries,
            country: "jp", selectedDate: Dates.allDates,
            trainDate: { $0.date ?? Dates.undated }, dateLabel: { $0 }
        ).overall.lineRidByCat.pairs.count
    }
}

/// Where the 1.4 s of "read + index rail-sections.json" actually goes.
///
/// The combined figure is the one `MileageStatisticsStore` pays on the first
/// statistics of a launch, per region. It hides a decode and a build, and the
/// build hides the cost of its dictionary KEY: `Statistics.edgeKey` is four
/// `JSNumber.string` calls — a full ECMAScript shortest-round-trip formatter —
/// and three concatenations, per edge. This splits the three so the next
/// change is aimed at the one that costs.
func benchmarkEdgeIndexPhases(root: URL) {
    let sectionsURL = root.appending(path: "app/data/rail-sections.json")
    guard let data = try? Data(contentsOf: sectionsURL) else {
        print("edge index: rail-sections.json unavailable")
        return
    }
    print("\nedge index phases — jp rail-sections.json, \(data.count / 1024) KB")

    var sections: [Statistics.Section] = []
    measure("decode SectionFeatureCollection", repeats: 5, warmup: 1) {
        sections = (try? Statistics.SectionFeatureCollection.load(contentsOf: sectionsURL))?
            .sections ?? []
        return sections.count
    }
    print("  \(sections.count) sections")

    measure("buildEdgeIndex over the decoded sections", repeats: 5, warmup: 1) {
        Statistics.buildEdgeIndex(sections: sections, country: "jp").km.count
    }

    // The key alone, over exactly the pairs the build hashes.
    var pairs: [(Coordinate, Coordinate)] = []
    for section in sections where section.coordinates.count >= 2 {
        for i in 1..<section.coordinates.count {
            pairs.append((section.coordinates[i - 1], section.coordinates[i]))
        }
    }
    print("  \(pairs.count) edge keys built per index")

    measure("  edgeKey (String) ×\(pairs.count)", repeats: 5, warmup: 1) {
        var sink = 0
        for pair in pairs { sink &+= Statistics.edgeKey(pair.0, pair.1).utf8.count }
        return sink
    }

    // The production replacement: the same quantised grid and ordering, with
    // each Double stored by bit pattern rather than formatted as digits.
    measure("  packedEdgeKey (production) ×\(pairs.count)", repeats: 5, warmup: 1) {
        var sink = 0
        for pair in pairs {
            let key = Statistics.packedEdgeKey(pair.0, pair.1)
            sink &+= Int(truncatingIfNeeded: key.px &+ key.py &+ key.qx &+ key.qy)
        }
        return sink
    }

    // And the dictionary each key type builds, which is where hashing shows up.
    measure("  Dictionary<String, Int> insert ×\(pairs.count)", repeats: 3, warmup: 1) {
        var map: [String: Int] = [:]
        for (i, pair) in pairs.enumerated() {
            let key = Statistics.edgeKey(pair.0, pair.1)
            if map[key] == nil { map[key] = i }
        }
        return map.count
    }

    measure("  Dictionary<EdgeKey, Int> insert ×\(pairs.count)", repeats: 3, warmup: 1) {
        var map: [Statistics.EdgeKey: Int] = [:]
        for (i, pair) in pairs.enumerated() {
            let key = Statistics.packedEdgeKey(pair.0, pair.1)
            if map[key] == nil { map[key] = i }
        }
        return map.count
    }
}
