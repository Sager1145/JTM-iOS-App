import Foundation
import RailCore
import RailPresentation

/// Reads one region of a builder output directory (`build-display-network.py --output`) into the
/// engine's input: `manifest.json`, the region's `{region}.display.bin` and nothing else.
///
/// The chunk documents are decoded by `RailCore.DisplayChunk` and turned into chains by
/// `StrokeLineInput.make`, the same two calls the app makes, so the bake and the app cannot read a
/// fragment differently. What this adds is the directory layout: which chunk belongs to which
/// line, in blob order (the package's line order), and the family palette of the region.
///
/// Also read here: `{region}.display-history.json` when present, for the date span each part
/// carries (a region without one has no dated parts). Which spans draw, and solid or dashed, is
/// decided on the device by the era; the pack only stores the spans.
public enum DisplayInput {

    /// A half-open day range in the topology file's day numbers (`RailTopologyFormat.dayNumber`).
    /// An open bound is 0 (from) or `Int32.max` (to).
    public struct DaySpan: Hashable, Sendable {
        public var fromDay: Int32
        public var toDay: Int32
        public init(fromDay: Int32, toDay: Int32) {
            self.fromDay = fromDay
            self.toDay = toDay
        }
    }

    /// One drawn fragment of a package line, in the order the display chunk lists them.
    public struct Fragment: Sendable, Equatable {
        /// Index into `Region.network.lines`.
        public var inputIndex: Int
        public var continuous: Bool
        /// `fragment.chain` for a continuous fragment (the topology's chain number); 0 otherwise.
        public var chainNumber: Int
        /// One entry per interval of the input; the app's `partSpans`. A continuous fragment is
        /// dated as a whole by its first part, as `MapLineGeometry.prepare` does.
        public var partSpans: [DaySpan?]
    }

    /// One package line of the manifest, in blob order (the topology's line order).
    public struct LineInfo: Sendable, Equatable {
        public var id: String
        /// `lodMinZoom` x 4: the line's tier in the app's zoom (`RailStyle.zoom(fromMapLibre:)`).
        public var tierQuarterZoom: Int16
        public var fragments: [Fragment]
    }

    /// What one region of a builder directory holds for the bake.
    public struct Region: Sendable {
        public var network: NetworkStrokeBake.Network
        public var lines: [LineInfo]
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
            var name: String?
            var rank: Int?
            var minZoomMapLibre: Int?
            var visibilityLengthKm: Double?
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

    /// The part rows of `{region}.display-history.json` the pack needs.
    struct History: Decodable {
        struct Row: Decodable {
            var id: String
            var index: Int
            var validFrom: String?
            var validTo: String?
        }

        var parts: [Row]

        /// Draw id -> source part index -> span. A row with no dates is undated.
        func spans() -> [String: [Int: DaySpan]] {
            var rows: [String: [Int: DaySpan]] = [:]
            for row in parts {
                let from = row.validFrom.flatMap { $0.isEmpty ? nil : RailTopologyFormat.dayNumber(ofISODate: $0) }
                let to = row.validTo.flatMap { $0.isEmpty ? nil : RailTopologyFormat.dayNumber(ofISODate: $0) }
                guard from != nil || to != nil else { continue }
                rows[row.id, default: [:]][row.index] = DaySpan(
                    fromDay: Int32(clamping: from ?? 0), toDay: Int32(clamping: to ?? UInt32(Int32.max)))
            }
            return rows
        }
    }

    /// The chains of `region`, in blob order, the vertices its stations sit on, and per package
    /// line its tier and the date span of each part.
    public static func load(
        region: String, from directory: URL
    ) throws -> Region {
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

        let entries = manifest.lines.filter { $0.value.region == region && $0.value.chunk != nil }
            .sorted { ($0.value.chunk!.offset, $0.key) < ($1.value.chunk!.offset, $1.key) }
        let metadata = Dictionary(uniqueKeysWithValues: entries.map { key, line in
            (key, DisplayLineMetadata(
                id: line.id, region: line.region, operatorName: line.operator,
                color: line.color, colorDark: line.colorDark))
        })
        let historyURL = directory.appending(path: "\(region).display-history.json")
        let dated = FileManager.default.fileExists(atPath: historyURL.path)
            ? try JSONDecoder().decode(History.self, from: Data(contentsOf: historyURL)).spans() : [:]
        var lines: [StrokeLineInput] = []
        var anchors: [String: [Int]] = [:]
        var infos: [LineInfo] = []
        for (key, line) in entries {
            var fragments: [Fragment] = []
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
                        fragment: fragment, metadata: meta, families: families, shiftToGCJ02: false,
                        stampedPartIndices: Set((dated[drawID(fragment)] ?? [:]).keys))
                else { continue }
                let rows = dated[input.id] ?? [:]
                fragments.append(Fragment(
                    inputIndex: lines.count, continuous: input.continuous,
                    chainNumber: input.continuous ? (fragment.chain ?? 0) : 0,
                    partSpans: input.sourcePartIndices.map { rows[$0] }))
                lines.append(input)
            }
            let native = NetworkVisibilityPolicy.lineMinZoomMapLibre(
                portedMinZoom: line.minZoomMapLibre ?? 0, rank: line.rank,
                visibilityLengthKm: line.visibilityLengthKm ?? 0, region: region,
                operator: line.operator, name: line.name)
            infos.append(LineInfo(
                id: line.id, tierQuarterZoom: Int16(clamping: (native + 1) * 4), fragments: fragments))
            anchors.merge(
                StrokeLineInput.anchors(stations: document.stations, lineMetadata: { metadata[$0] }),
                uniquingKeysWith: { first, _ in first })
        }
        return Region(network: NetworkStrokeBake.Network(lines: lines, anchors: anchors), lines: infos)
    }

    /// The draw id `StrokeLineInput.make` gives a fragment, the key of the history rows.
    private static func drawID(_ fragment: DisplayChunk.LineFragment) -> String {
        fragment.continuous == true
            ? "\(fragment.lineKey)#\(fragment.chain ?? 0)"
            : "\(fragment.lineKey)@\(fragment.lane ?? 0)"
    }
}
