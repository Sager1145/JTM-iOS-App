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
