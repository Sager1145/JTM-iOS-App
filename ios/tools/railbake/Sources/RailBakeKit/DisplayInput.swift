import Foundation
import RailCore

/// Reads one region of a builder output directory (`build-display-network.py --output`) into the
/// engine's input: `manifest.json`, the region's `{region}.display.bin` and nothing else.
///
/// The chunk documents are decoded by `RailCore.DisplayChunk` and turned into chains by
/// `StrokeLineInput.make`, the same two calls the app makes, so the bake and the app cannot read a
/// fragment differently. What this adds is the directory layout: which chunk belongs to which
/// line, in blob order (the package's line order), and the family palette of the region.
///
/// Not read here: `display-history.json` (dated parts). Which parts of a line are historical or
/// withheld by date is attribute assignment, which the piece cutter does against the history file.
public enum DisplayInput {

    /// Which datum the chains are shifted into before anything is built.
    public enum Datum: String, Sendable {
        /// Source coordinates as the builder wrote them.
        case wgs84
        /// The GCJ-02 displacement applied to every vertex of a region in
        /// `GCJ02.candidateRegions`; other regions are unchanged, as in the app.
        case gcj02

        func shifts(region: String) -> Bool {
            self == .gcj02 && GCJ02.candidateRegions.contains(region)
        }
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case regionNotInManifest(String)
        case chunkOutOfRange(String)

        public var description: String {
            switch self {
            case .missing(let name): "builder output has no \(name)"
            case .regionNotInManifest(let region): "manifest has no region \(region)"
            case .chunkOutOfRange(let id): "chunk of \(id) lies outside its blob"
            }
        }
    }

    struct Manifest: Decodable {
        struct Chunk: Decodable {
            var offset: Int
            var length: Int
        }

        struct Line: Decodable {
            var id: String
            var region: String
            var `operator`: String?
            var color: String
            var colorDark: String
            var chunk: Chunk?
        }

        struct RegionRecord: Decodable {
            var region: String
            var file: String
            var bytes: Int
            var families: [String: DisplayChunk.FamilyColor]?
        }

        var lines: [String: Line]
        var regions: [RegionRecord]
    }

    /// The chains of `region`, in blob order, and the vertices its stations sit on.
    public static func load(
        region: String, from directory: URL, datum: Datum = .wgs84
    ) throws -> NetworkStrokeBake.Network {
        let manifestURL = directory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw Failure.missing("manifest.json")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard let record = manifest.regions.first(where: { $0.region == region }) else {
            throw Failure.regionNotInManifest(region)
        }
        let blobURL = directory.appending(path: record.file)
        guard FileManager.default.fileExists(atPath: blobURL.path) else { throw Failure.missing(record.file) }
        let blob = try Data(contentsOf: blobURL, options: .alwaysMapped)
        let families = record.families ?? [:]
        let shift = datum.shifts(region: region)

        let entries = manifest.lines.filter { $0.value.region == region && $0.value.chunk != nil }
            .sorted { ($0.value.chunk!.offset, $0.key) < ($1.value.chunk!.offset, $1.key) }
        let metadata = Dictionary(uniqueKeysWithValues: entries.map { key, line in
            (key, DisplayLineMetadata(
                id: line.id, region: line.region, operatorName: line.operator,
                color: line.color, colorDark: line.colorDark))
        })
        var lines: [StrokeLineInput] = []
        var anchors: [String: [Int]] = [:]
        for (key, line) in entries {
            let chunk = line.chunk!
            guard chunk.offset >= 0, chunk.length >= 0, chunk.offset + chunk.length <= blob.count else {
                throw Failure.chunkOutOfRange(line.id)
            }
            let start = blob.startIndex + chunk.offset
            let document = try JSONDecoder().decode(
                DisplayChunk.self, from: blob[start..<(start + chunk.length)])
            for fragment in document.lines {
                guard let meta = metadata[fragment.lineKey] ?? metadata[key],
                      let input = StrokeLineInput.make(
                        fragment: fragment, metadata: meta, families: families, shiftToGCJ02: shift)
                else { continue }
                lines.append(input)
            }
            anchors.merge(
                StrokeLineInput.anchors(stations: document.stations, lineMetadata: { metadata[$0] }),
                uniquingKeysWith: { first, _ in first })
        }
        return NetworkStrokeBake.Network(lines: lines, anchors: anchors)
    }
}
