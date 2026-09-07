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

/// What the decode actually spends, now that the index build no longer hides it.
///
/// Three files dominate a Japanese launch — the package, the sections and the
/// stations. The first two use `JSONDecoder`; stations now uses a measured
/// `JSONSerialization` reader. Both approaches first read the file and then
/// parse/build models. This separates file I/O from the parser floor, then
/// directly compares the two output-equivalent station readers below.
func benchmarkDecodeBreakdown(root: URL) {
    print("\n-- where the decode goes --")
    let rail = root.appending(path: "app/public/rail")
    let data = root.appending(path: "app/data")
    let files: [(String, URL)] = [
        ("package    jp", rail.appending(path: "jp-2025.json")),
        ("sections   jp", data.appending(path: "rail-sections.json")),
        ("stations   jp", data.appending(path: "stations.json")),
    ]

    for (name, url) in files {
        let kilobytes = ((try? Data(contentsOf: url).count) ?? 0) / 1024
        print("  \(name) — \(kilobytes) KB")
        measure("    Data(contentsOf:) plain", repeats: 5, warmup: 1) {
            (try? Data(contentsOf: url))?.count ?? 0
        }
        measure("    Data(contentsOf:, .mappedIfSafe)", repeats: 5, warmup: 1) {
            (try? Data(contentsOf: url, options: .mappedIfSafe))?.count ?? 0
        }
        measure("    JSONSerialization over the bytes", repeats: 5, warmup: 1) {
            guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let object = try? JSONSerialization.jsonObject(with: bytes)
            else { return 0 }
            return (object as? [String: Any])?.count ?? 0
        }
    }

    let stationsURL = data.appending(path: "stations.json")
    guard let stationBytes = try? Data(contentsOf: stationsURL, options: .mappedIfSafe),
          let production = try? Stations.FeatureCollection.decode(json: stationBytes),
          let reference = try? JSONDecoder().decode(
              Stations.FeatureCollection.self, from: stationBytes),
          production.features == reference.features
    else {
        print("\n-- stations.json readers, jp --\n  candidate refused: reader outputs differ")
        return
    }
    print("\n-- stations.json readers, jp --")
    print("  parity: \(production.features.count) features are identical")
    measure("production: JSONSerialization → FeatureCollection", repeats: 5, warmup: 1) {
        (try? Stations.FeatureCollection.decode(json: stationBytes).features.count) ?? 0
    }
    measure("reference: JSONDecoder → FeatureCollection", repeats: 5, warmup: 1) {
        (try? JSONDecoder().decode(
            Stations.FeatureCollection.self, from: stationBytes).features.count) ?? 0
    }
}

/// Is the sections file worth the same treatment the stations file got?
///
/// `stations.json` moved from `JSONDecoder` to `JSONSerialization` because its
/// values are untyped and `Decodable` could only discriminate them by throwing.
/// `rail-sections.json` is the opposite case: fully typed, decoded straight
/// into `[[Double]]`. So the question is whether `JSONSerialization` still
/// wins once the NSNumber boxes it hands back have to be unboxed again —
/// 377,620 edges' worth of coordinate pairs. Measured before anything ships.
func benchmarkSectionsReaderCandidates(root: URL) {
    let url = root.appending(path: "app/data/rail-sections.json")
    guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
    print("\n-- rail-sections.json readers, jp --")

    guard let reference = try? Statistics.SectionFeatureCollection.load(contentsOf: url).sections,
          let candidate = try? decodeSectionsWithJSONSerialization(bytes),
          reference.count == candidate.count,
          zip(reference, candidate).allSatisfy({ lhs, rhs in
              lhs.properties == rhs.properties && lhs.coordinates == rhs.coordinates
          })
    else {
        print("candidate refused: it did not produce the same [Section]")
        return
    }
    print("  parity: \(reference.count) sections are identical")

    measure("today: JSONDecoder → Statistics.SectionFeatureCollection", repeats: 5, warmup: 1) {
        (try? Statistics.SectionFeatureCollection.load(contentsOf: url).sections.count) ?? 0
    }

    measure("candidate: JSONSerialization → the same [Section]", repeats: 5, warmup: 1) {
        (try? decodeSectionsWithJSONSerialization(bytes).count) ?? 0
    }
}

/// A benchmark candidate, not a production reader. It intentionally builds
/// every value the `Decodable` implementation builds; measuring a geometry-only
/// count would omit the properties and would not answer the question above.
private func decodeSectionsWithJSONSerialization(_ data: Data) throws
    -> [Statistics.Section]
{
    enum CandidateError: Error { case invalidShape }

    func value(_ raw: Any?) -> Statistics.JSValue? {
        guard let raw else { return nil }
        if raw is NSNull { return .null }
        if let text = raw as? String { return .string(text) }
        if let number = raw as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID()
                ? .bool(number.boolValue)
                : .number(number.doubleValue)
        }
        // `SectionProperties.read` also returns nil for unsupported values.
        return nil
    }

    func properties(_ raw: Any?) throws -> Statistics.SectionProperties {
        guard let object = raw as? [String: Any] else { throw CandidateError.invalidShape }
        return Statistics.SectionProperties(
            n02_001: value(object["N02_001"]),
            n02_002: value(object["N02_002"]),
            n02_003: value(object["N02_003"]),
            n02_004: value(object["N02_004"]),
            railwayClassCode: value(object["railway_class_code"]),
            institutionTypeCode: value(object["institution_type_code"]),
            lineName: value(object["line_name"]),
            operatorName: value(object["operator"])
        )
    }

    func rawLine(_ raw: Any) throws -> [[Double]] {
        guard let points = raw as? [Any] else { throw CandidateError.invalidShape }
        return try points.map { rawPoint in
            guard let point = rawPoint as? [Any] else { throw CandidateError.invalidShape }
            return try point.map { rawComponent in
                guard let number = rawComponent as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID()
                else { throw CandidateError.invalidShape }
                return number.doubleValue
            }
        }
    }

    func line(_ raw: Any) throws -> [Coordinate] {
        try rawLine(raw).compactMap(Coordinate.init(pair:))
    }

    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let features = root["features"] as? [Any]
    else { throw CandidateError.invalidShape }

    var sections: [Statistics.Section] = []
    for rawFeature in features {
        guard let feature = rawFeature as? [String: Any] else {
            throw CandidateError.invalidShape
        }
        let sectionProperties = try properties(feature["properties"])
        guard let rawGeometry = feature["geometry"] else { continue }
        if rawGeometry is NSNull { continue }
        guard let geometry = rawGeometry as? [String: Any],
              let type = geometry["type"] as? String
        else { throw CandidateError.invalidShape }

        let lines: [[Coordinate]]
        switch type {
        case "LineString":
            guard let coordinates = geometry["coordinates"] else {
                throw CandidateError.invalidShape
            }
            lines = [try line(coordinates)]
        case "MultiLineString":
            guard let rawLines = geometry["coordinates"] as? [Any] else {
                throw CandidateError.invalidShape
            }
            lines = try rawLines.map(line)
        default:
            // The production decoder deliberately ignores coordinates for an
            // unknown geometry type and emits no sections.
            lines = []
        }
        sections.append(contentsOf: lines.map {
            Statistics.Section(properties: sectionProperties, coordinates: $0)
        })
    }
    return sections
}
