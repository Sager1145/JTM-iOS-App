import Foundation
import RailCore

/// What a cold launch reads, per country.
///
/// The app holds seven networks and reads three families of file for them: the
/// rail package (the drawn network, and the line attributes a journey's badge
/// comes from), `rail-sections*.json` (the N02 edge index the statistics and
/// the ridden-line filter are built on, and the solver's graph), and
/// `stations*.json` (the solver's station table). This prints the cost of each
/// one for each region, which is the measurement `Region.DataWeight` is a
/// decision about: Japan and the United States are an order of magnitude past
/// the other five, and a launch that reads all seven of anything eagerly is a
/// launch spent in those two.
func benchmarkLaunchLoad(root: URL) {
    print("\n-- what one country costs to read --")
    let rail = root.appending(path: "app/public/rail")
    let data = root.appending(path: "app/data")
    let countries = ["mo", "hk", "tw", "kr", "ca", "jp", "us"]

    for country in countries {
        let url = rail.appending(path: "\(country)-2025.json")
        let kilobytes = ((try? Data(contentsOf: url).count) ?? 0) / 1024
        measure("package.full     \(country) (\(kilobytes) KB)", repeats: 5, warmup: 1) {
            try! DisplayParts.LoadedPackage.load(contentsOf: url).package.lines.count
        }
    }

    // The same file, read for its line ATTRIBUTES only — what the launch badge
    // index takes. See `CompactPackage.Headers`: no coordinate is
    // materialised, and the difference is the whole reason the index moved to
    // it.
    for country in countries {
        let url = rail.appending(path: "\(country)-2025.json")
        let kilobytes = ((try? Data(contentsOf: url).count) ?? 0) / 1024
        measure("package.headers  \(country) (\(kilobytes) KB)", repeats: 5, warmup: 1) {
            try! CompactPackage.Headers.load(contentsOf: url).lines.count
        }
    }

    for country in countries {
        let suffix = country == "jp" ? "" : "-\(country)"
        let url = data.appending(path: "rail-sections\(suffix).json")
        let kilobytes = ((try? Data(contentsOf: url).count) ?? 0) / 1024
        measure("sections.load    \(country) (\(kilobytes) KB)", repeats: 5, warmup: 1) {
            try! RouteGraph.SectionFeatureCollection.load(contentsOf: url).features.count
        }
    }

    for country in countries {
        let suffix = country == "jp" ? "" : "-\(country)"
        let url = data.appending(path: "stations\(suffix).json")
        let kilobytes = ((try? Data(contentsOf: url).count) ?? 0) / 1024
        measure("stations.load    \(country) (\(kilobytes) KB)", repeats: 5, warmup: 1) {
            try! Stations.FeatureCollection.load(contentsOf: url).features.count
        }
    }
}
