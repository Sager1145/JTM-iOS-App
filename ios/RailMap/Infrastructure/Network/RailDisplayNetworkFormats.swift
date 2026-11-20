import CryptoKit
import Foundation
import MapKit
import RailCore
import RailPresentation
import SwiftUI

/// The bundle format produced by `build-display-network.py`.
///
/// Geometry is absent from the manifest. It holds the small line catalog
/// needed to style a railway once its region arrives, and one record per
/// region: where that region is, the earliest zoom anything in it can be
/// drawn, and the digest its file must match. Reading the index therefore
/// costs the catalog and nothing else.
///
/// ## Why a region and not a tile
///
/// This derivative used to be a z4/z6/z8/z10 Web Mercator pyramid, and the map
/// held whichever tiles its padded viewport touched. That bounded the read, and
/// it did so by cutting every railway at the tile boundaries: what the map drew
/// was never a line but a run of fragments that happened to abut, each with its
/// own id, its own bounding box and its own moment of arrival. Panning changed
/// the resident set, so the network was rebuilt, re-decimated and re-mounted on
/// a gesture — and 49 MB of clipped pieces shipped in the bundle to make it
/// possible.
///
/// A region file is the same geometry uncut: one continuous set of parts per
/// railway, 18 MB for all seven. What keeps a national network off the GPU is
/// no longer the shape of the storage but the renderer's own viewport cull —
/// ``NetworkLOD/select(from:zoom:buildRect:)`` for the line and the
/// per-interval rect test in `RailMapView.rebuild` for the stroke, which is a
/// question about what is on screen rather than about which square of Web
/// Mercator something fell in.
struct RailDisplayNetworkManifest: Decodable, Sendable {
    static let format = "jtm-display-network-v2"
    static let temporalFormat = "jtm-display-network-v3"
    static let datedServiceFeature = "dated_service_bank_v1"

    struct TemporalBank: Decodable, Sendable, Equatable {
        var historyRevision: String
        var bankRevision: String
        var sourcePackageSHA256: String
        var managedLineIDs: [String]

        var isValid: Bool {
            !historyRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !bankRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && sourcePackageSHA256.count == 64
                && sourcePackageSHA256.allSatisfy(\.isHexDigit)
                && !managedLineIDs.isEmpty
                && managedLineIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                && Set(managedLineIDs).count == managedLineIDs.count
        }
    }

    /// A line's extent in the manifest, `nil` when the line has no
    /// drawable geometry at all — see `RegionRecord`'s bounds fields for the
    /// same convention.
    struct Bounds: Decodable, Sendable {
        var minLon: Double
        var minLat: Double
        var maxLon: Double
        var maxLat: Double
    }

    /// Where this line's fragment lives inside its region's blob
    /// (`{region}.display.bin`).
    struct Chunk: Decodable, Sendable {
        var offset: Int
        var length: Int
        var sha256: String
        /// Vertex count of this specific chunk's document — present on an
        /// overview chunk, absent (as before) on a full one and on any
        /// manifest built before this field existed.
        var vertexCount: Int?
    }

    struct Line: Decodable, Sendable {
        var id: String
        var region: String
        var name: String
        var nameRoma: String?
        var `operator`: String?
        var operatorLogo: String?
        var kind: String?
        var rank: Int
        var color: String
        var colorDark: String
        var bounds: Bounds?
        var chunk: Chunk?
        /// A Douglas–Peucker-simplified variant of `chunk`, appended after
        /// every full chunk in the same region blob — present only for a
        /// `"lines"`-strategy region's qualifying lines (builder A2), absent
        /// for a whole-region line and for any manifest built before this
        /// field existed.
        var overview: Chunk?
        var displayLabel: String?
        var nameKey: String?
        var operatorShort: String?
        var stationCount: Int?
        var vertexCount: Int?
        var chainCount: Int?
        var dependsOn: [String]?
        /// The reviewed display group's identity, carried next to the
        /// colour override it usually travels with. Absent for a line the
        /// reviewed policy does not name, and absent entirely from a stale
        /// manifest built before this field existed — `Decodable`'s
        /// synthesized init leaves an optional `nil` on a missing key, so an
        /// old manifest.json on disk decodes rather than failing outright.
        var renderGroup: String?
        var minZoomMapLibre: Int
        var lodMinZoomMapLibre: Int
        var visibilityLengthKm: Double

        /// Generated thresholds are retained for format compatibility. Native
        /// policy is resolved at runtime so loading and drawing cannot disagree
        /// when the app's detail ladder changes without regenerating geometry.
        var nativeMinZoomMapLibre: Int {
            NetworkLOD.minZoomMapLibre(
                portedMinZoom: minZoomMapLibre, rank: rank,
                visibilityLengthKm: visibilityLengthKm, region: region,
                operator: `operator`, name: name)
        }
        var logo: String?
        /// The package attributes the journey-badge index needs that this line
        /// does not already carry verbatim — `package_badge_fields` in
        /// `build-display-network.py`. Absent from a manifest built before
        /// the field existed, which sends the store back to scanning the
        /// package (audit A7).
        var badge: PackageBadge?

        struct PackageBadge: Decodable, Sendable {
            /// The line's index in its package's `lines`.
            var order: Int
            /// Present only where it differs from `name`.
            var nameNorm: String?
            /// The PACKAGE's value; the line's own `operatorShort` is the
            /// label table's and is a different answer.
            var operatorShort: String?
            /// Present only where a render-group override or the grey
            /// fallback replaced the package's own colour.
            var color: String?
            var colorDark: String?
            /// `1` when the package gives the line no colour at all.
            var uncolored: Int?
        }

        /// This line's extent in projected map space — `.null` when
        /// `bounds` is absent. Same corner math as `RegionRecord.mapRect`.
        var mapRect: MKMapRect {
            guard let bounds else { return .null }
            let topLeft = MKMapPoint(
                CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.minLon))
            let bottomRight = MKMapPoint(
                CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.maxLon))
            return MKMapRect(
                x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
                width: abs(bottomRight.x - topLeft.x),
                height: abs(bottomRight.y - topLeft.y))
        }

        /// The same threshold in **this app's** zoom, which is what the
        /// camera callback carries.
        var minimumCameraZoom: Double {
            RailStyle.zoom(fromMapLibre: Double(nativeMinZoomMapLibre))
        }
    }

    struct RegionRecord: Decodable, Sendable {
        var region: String
        var file: String
        var bytes: Int
        var sha256: String
        /// Historical builder threshold, retained for bundle compatibility.
        /// `records` derives current native eligibility from the line catalog.
        var minZoomMapLibre: Int
        /// Absent for a region with no drawable geometry at all. That is not
        /// the same as a zero-sized extent: a rect at 0°N 0°E would match a
        /// camera in the Gulf of Guinea, where absent means "never".
        var minLon: Double?
        var minLat: Double?
        var maxLon: Double?
        var maxLat: Double?
        var stationsFile: String?
        var stationsBytes: Int?
        var stationsSHA256: String?
        var families: [String: RailDisplayNetworkFile.FamilyColor]?
        var lineCount: Int?
        var stationCount: Int?
        var vertexCount: Int?
        /// `"whole"` or `"lines"` (builder A1) — absent from a manifest
        /// built before this field existed, in which case
        /// `RailDisplayNetworkIndex.wholeRegions` falls back to `bytes`.
        var loadStrategy: String?
        /// Bytes of this region's full chunks, i.e. `[0, fullBytes)` of the
        /// blob. Absent when `loadStrategy` is absent.
        var fullBytes: Int?
        /// Bytes of this region's overview chunks, appended after
        /// `fullBytes` in the same blob. Absent when `loadStrategy` is
        /// absent, or zero for a `"lines"` region with no overview lines.
        var overviewBytes: Int?
        /// History side file (`{region}.display-history.json`). Legacy v2 keeps
        /// these fields optional; v3 `temporalBank` validation requires the
        /// exact file name, positive byte count, and SHA-256 before geometry.
        var historyFile: String?
        var historyBytes: Int?
        var historySHA256: String?
        var temporalBank: TemporalBank? = nil
        /// Topology file (`{region}.topology.bin`, format in
        /// `docs/reference/rail-topology-format.md`). Absent until the builder
        /// writes one; all three fields travel together.
        var topologyFile: String?
        var topologyBytes: Int?
        var topologySHA256: String?

        var hasTopology: Bool { topologyFile != nil }

        /// Either all three topology fields name a well-formed file, or none is set.
        var hasConsistentTopologyFields: Bool {
            guard let topologyFile else { return topologyBytes == nil && topologySHA256 == nil }
            return topologyFile == "\(region).topology.bin"
                && (topologyBytes ?? 0) > 0
                && topologySHA256?.count == 64
                && topologySHA256?.allSatisfy(\.isHexDigit) == true
        }

        var hasRequiredHistoryMetadata: Bool {
            historyFile == "\(region).display-history.json"
                && (historyBytes ?? 0) > 0
                && historySHA256?.count == 64
                && historySHA256?.allSatisfy(\.isHexDigit) == true
        }

        /// The same threshold in **this app's** zoom, which is what the camera
        /// callback carries.
        var minimumCameraZoom: Double {
            RailStyle.zoom(fromMapLibre: Double(minZoomMapLibre))
        }

        /// The region's extent in projected map space — data-derived, so the
        /// intersection test is against where the railways actually are rather
        /// than against a constant somebody has to keep in step with them.
        var mapRect: MKMapRect {
            guard let minLon, let minLat, let maxLon, let maxLat else { return .null }
            let topLeft = MKMapPoint(
                CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
            let bottomRight = MKMapPoint(
                CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
            return MKMapRect(
                x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
                width: abs(bottomRight.x - topLeft.x),
                height: abs(bottomRight.y - topLeft.y))
        }

        /// Whether the four bounds are all present or all absent, and sane
        /// when present.
        var hasValidBounds: Bool {
            switch (minLon, minLat, maxLon, maxLat) {
            case (nil, nil, nil, nil): true
            case let (west?, south?, east?, north?):
                west.isFinite && (-180...180).contains(west)
                    && east.isFinite && (-180...180).contains(east)
                    && south.isFinite && (-90...90).contains(south)
                    && north.isFinite && (-90...90).contains(north)
                    && west <= east && south <= north
            default: false
            }
        }
    }

    /// Reviewed display continuity only. Routing still uses the independently
    /// evidenced physical topology; a shared display point creates no edge.
    struct DisplayJoin: Decodable, Sendable {
        struct Endpoint: Decodable, Sendable {
            var lineId: String
            var lineKey: String
            var stationCode: String
            var endpointID: String
            var chain: Int
            var atEnd: Bool
            var coordinate: [Double]
        }
        var id: String
        var region: String
        var kind: String
        var stationCode: String
        var hostLineId: String
        var endpoints: [Endpoint]
        var evidence: [String]?
        var reviewedAt: String?
    }

    var format: String
    var packageSHA256: [String: String]
    var lines: [String: Line]
    var regions: [RegionRecord]
    var displayJoins: [DisplayJoin]? = nil
    var requiredFeatures: [String]? = nil

    static let shippedRegions: Set<String> = ["jp", "tw", "hk", "mo", "kr", "cn"]

    func validated() throws -> Self {
        guard format == Self.format || format == Self.temporalFormat else {
            throw RailDisplayNetworkError.unsupportedFormat(format)
        }
        if format == Self.temporalFormat {
            guard requiredFeatures == [Self.datedServiceFeature],
                  regions.contains(where: { $0.temporalBank != nil }) else {
                throw RailDisplayNetworkError.invalidRegionIndex
            }
        } else if regions.contains(where: { $0.temporalBank != nil }) || !(requiredFeatures?.isEmpty ?? true) {
            throw RailDisplayNetworkError.invalidRegionIndex
        }
        for record in regions {
            guard let bank = record.temporalBank else { continue }
            guard record.region == "jp", bank.isValid, record.hasRequiredHistoryMetadata,
                  bank.sourcePackageSHA256 == packageSHA256[record.region],
                  bank.managedLineIDs.allSatisfy({ id in
                      lines.values.contains { $0.id == id && $0.region == record.region }
                  }) else { throw RailDisplayNetworkError.invalidRegionIndex }
        }
        guard Set(regions.map(\.region)) == Self.shippedRegions,
              regions.count == Self.shippedRegions.count else {
            throw RailDisplayNetworkError.invalidRegionIndex
        }
        guard regions.allSatisfy({ record in
            record.file == "\(record.region).display.bin"
                && record.stationsFile == "\(record.region).stations.json"
                && record.bytes > 0
                && record.sha256.count == 64
                && record.sha256.allSatisfy(\.isHexDigit)
                && (0...30).contains(record.minZoomMapLibre)
                && record.hasValidBounds
                && record.hasConsistentTopologyFields
        }) else { throw RailDisplayNetworkError.invalidRegionIndex }
        guard lines.values.allSatisfy({ line in
            line.bounds != nil
                && (line.chunk.map {
                    $0.offset >= 0 && $0.length > 0 && $0.sha256.count == 64
                } ?? false)
        }) else { throw RailDisplayNetworkError.invalidRegionIndex }
        guard Set(packageSHA256.keys) == Self.shippedRegions,
              packageSHA256.values.allSatisfy({
                  $0.count == 64 && $0.allSatisfy(\.isHexDigit)
              }) else { throw RailDisplayNetworkError.invalidRegionIndex }
        return self
    }
}

/// One region's drawable geometry, whole.
struct RailDisplayNetworkFile: Decodable, Sendable {
    // The line fragment, its rows and the family colour are the document the host-side bake
    // reads too, so they live in `RailCore.DisplayChunk` (see `StrokeLineInput.make`).
    typealias LineFragment = DisplayChunk.LineFragment
    typealias FamilyWindowRow = DisplayChunk.FamilyWindowRow
    typealias FamilyColor = DisplayChunk.FamilyColor
    typealias FollowRow = DisplayChunk.FollowRow

    struct Station: Decodable, Sendable {
        var id: String
        var lineKey: String
        var stationCode: String
        var name: String
        var lon: Double
        var lat: Double
        var nameRoma: String?
        var minZoomMapLibre: Int
        var lodMinZoomMapLibre: Int
        var isTerminal: Bool
        var showsLabel: Bool
        var groupLineKeys: [String]
        var lane: Double?
        var bearing: Double?
        /// `[chain, vertexIndex]`: the vertex of the line's continuous chain
        /// this platform sits on, so its bead is that vertex's offset.
        var slot: [Int]?
    }

    var format: String
    var region: String
    /// This region's family-collapse palette (`build-display-network.py`'s
    /// `region_families`, sourced from `na-render-groups.json`), keyed by
    /// groupId — the same key a `LineFragment.familyWindows` row's
    /// `groupID` names. Empty for a region with no family windows at all,
    /// AND for an older or cached payload that predates this key entirely —
    /// see the custom `init(from:)` below. `validated()`'s own requirement
    /// that every `familyWindows` row's `groupID` resolve in `families` is
    /// unaffected: a payload with family windows but no `families` object
    /// still fails validation, exactly as before.
    var families: [String: FamilyColor]
    var lines: [LineFragment]
    var stations: [Station]
    /// The single railway this chunk holds — present in the v2 chunk
    /// document, absent from an older whole-region payload.
    var lineId: String?
    /// `"overview"` or `"full"` (builder A3) — absent from a document built
    /// before this field existed, in which case `validated(...)` accepts
    /// either detail.
    var detail: String?

    private enum CodingKeys: String, CodingKey {
        case format, region, families, lines, stations, lineId, detail
    }

    /// A hand-written decode rather than the synthesized one: `families` is
    /// declared non-optional (the normal case, and what every other reader
    /// of it wants — a plain `[String: FamilyColor]`, no unwrapping at every
    /// use), but the synthesized `Decodable` conformance for a non-optional
    /// property calls `decode`, not `decodeIfPresent`, regardless of any
    /// default value on the property — a payload built before `families`
    /// existed (or one a cache kept from before it did) would fail the
    /// WHOLE decode on a missing key, not just leave this field empty. Every
    /// other field decodes exactly as the synthesized initializer would.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        region = try container.decode(String.self, forKey: .region)
        families = try container.decodeIfPresent([String: FamilyColor].self, forKey: .families) ?? [:]
        lines = try container.decode([LineFragment].self, forKey: .lines)
        stations = try container.decode([Station].self, forKey: .stations)
        lineId = try container.decodeIfPresent(String.self, forKey: .lineId)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }

    func validated(
        region expected: String, lineId expectedLineId: String?,
        catalog: [String: RailDisplayNetworkManifest.Line],
        families: [String: FamilyColor],
        detail expectedDetail: DisplayDetail? = nil,
        expectedFormat: String = RailDisplayNetworkManifest.format
    ) throws -> Self {
        guard (expectedFormat == RailDisplayNetworkManifest.format
                || expectedFormat == RailDisplayNetworkManifest.temporalFormat),
              format == expectedFormat else {
            throw RailDisplayNetworkError.unsupportedFormat(format)
        }
        guard region == expected else {
            throw RailDisplayNetworkError.wrongRegion(expected: expected, actual: region)
        }
        if let expectedDetail {
            let expectedDetailString = expectedDetail == .overview ? "overview" : "full"
            guard detail == nil || detail == expectedDetailString else {
                throw RailDisplayNetworkError.wrongDetail(
                    expected: expectedDetailString, actual: detail ?? "nil")
            }
        }
        if let expectedLineId {
            // Rows carry the region-qualified catalog key ("jp|jp-…"); the
            // chunk header and the manifest line carry the bare id.
            let expectedRowKey = "\(expected)|\(expectedLineId)"
            guard lineId == expectedLineId,
                  lines.allSatisfy({ $0.lineKey == expectedRowKey }),
                  stations.allSatisfy({ $0.lineKey == expectedRowKey }) else {
                throw RailDisplayNetworkError.wrongLine(
                    expected: expectedLineId, actual: lineId ?? "nil")
            }
        }
        guard lines.allSatisfy({ catalog[$0.lineKey] != nil })
                && stations.allSatisfy({ catalog[$0.lineKey] != nil }) else {
            throw RailDisplayNetworkError.unknownLine(region)
        }
        let validCoordinate: ([Double]) -> Bool = { pair in
            pair.count == 2
                && pair[0].isFinite && (-180...180).contains(pair[0])
                && pair[1].isFinite && (-90...90).contains(pair[1])
        }
        guard lines.allSatisfy({ fragment in
            !fragment.parts.isEmpty
                && (fragment.lane?.isFinite ?? true)
                && abs(fragment.lane ?? 0) <= 8
                && fragment.parts.allSatisfy({
                    $0.count >= 2 && $0.allSatisfy(validCoordinate)
                })
                && (fragment.laneRows ?? []).allSatisfy({ row in
                    row.count == 3 && row.allSatisfy(\.isFinite) && abs(row[2]) <= 8
                })
                && (fragment.totalMetres.map { $0.isFinite && $0 >= 0 } ?? true)
                && (fragment.chain.map { $0 >= 0 } ?? true)
                && (fragment.follows ?? []).allSatisfy({ follow in
                    follow.from.isFinite && follow.to.isFinite && follow.to > follow.from
                        && follow.canonicalFrom.isFinite && follow.canonicalTo.isFinite
                        && follow.canonicalChain >= 0
                        && catalog[follow.canonicalLineKey] != nil
                })
                && (fragment.familyWindows ?? []).allSatisfy({ window in
                    window.from.isFinite && window.to.isFinite && window.to > window.from
                        && (window.role == 0 || window.role == 1)
                        && families[window.groupID] != nil
                })
        }), stations.allSatisfy({ station in
            station.lon.isFinite && (-180...180).contains(station.lon)
                && station.lat.isFinite && (-90...90).contains(station.lat)
                && (station.lane?.isFinite ?? true)
                && abs(station.lane ?? 0) <= 8
                && (station.bearing.map { $0.isFinite && (0...360).contains($0) } ?? true)
                && (station.slot.map { $0.count == 2 && $0[0] >= 0 && $0[1] >= 0 } ?? true)
                && !station.id.isEmpty && !station.stationCode.isEmpty
                && station.groupLineKeys.allSatisfy({ catalog[$0] != nil })
        }) else {
            throw RailDisplayNetworkError.invalidRegionPayload(region)
        }
        return self
    }
}

enum RailDisplayNetworkError: LocalizedError {
    case missingManifest
    case unsupportedFormat(String)
    case invalidRegionIndex
    case missingRegion(String)
    case wrongRegion(expected: String, actual: String)
    case corruptRegion(String)
    case unknownLine(String)
    case invalidRegionPayload(String)
    case corruptChunk(String)
    case wrongLine(expected: String, actual: String)
    case chunkOutOfRange(String)
    case wrongDetail(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            "rail-display-network/manifest.json is missing from the app bundle"
        case .unsupportedFormat(let value):
            "Unsupported rail display network format: \(value)"
        case .invalidRegionIndex:
            "The rail display network index contains invalid file metadata"
        case .missingRegion(let region): "Missing rail display network for \(region)"
        case .wrongRegion(let expected, let actual):
            "Rail display network for \(actual) was stored as \(expected)"
        case .corruptRegion(let region):
            "Rail display network for \(region) failed its SHA-256 check"
        case .unknownLine(let region):
            "Rail display network for \(region) refers to an unknown railway"
        case .invalidRegionPayload(let region):
            "Rail display network for \(region) contains invalid geometry"
        case .corruptChunk(let lineID):
            "Rail display network chunk for \(lineID) failed its SHA-256 check"
        case .wrongLine(let expected, let actual):
            "Rail display network chunk for \(expected) was stored as \(actual)"
        case .chunkOutOfRange(let lineID):
            "Rail display network chunk for \(lineID) is out of range of its region's blob"
        case .wrongDetail(let expected, let actual):
            "Rail display network chunk expected detail \(expected) but decoded \(actual)"
        }
    }
}

/// A one-time index over a validated manifest: which railway lives at what
/// offset inside its region's blob, in draw order, plus the extent and
/// zoom floor `lines(intersecting:cameraZoom:in:)` needs to decide what is
/// close enough to load. Built once per manifest arrival
/// (`RailDisplayNetwork.lineIndex(for:)`) and reused for every camera move.
struct RailDisplayNetworkIndex: Sendable {
    struct Entry: Sendable {
        var id: String
        var region: String
        var mapRect: MKMapRect
        var minimumCameraZoom: Double
        var chunk: RailDisplayNetworkManifest.Chunk
        /// A Douglas–Peucker-simplified variant of `chunk`, when the
        /// builder produced one (manifest A2) — `nil` for a whole-region
        /// line, a line the overview policy does not name, or a manifest
        /// built before this field existed.
        var overview: RailDisplayNetworkManifest.Chunk?
        var dependsOn: [String]
        var format: String = RailDisplayNetworkManifest.format
        var temporalBank: RailDisplayNetworkManifest.TemporalBank? = nil
    }

    /// Each region's entries in blob order — ascending `chunk.offset`,
    /// which is the package's line order and so the publish/draw order
    /// (D2).
    var entriesByRegion: [String: [Entry]]
    var recordsByRegion: [String: RailDisplayNetworkManifest.RegionRecord]
    /// The lowest native minimum zoom of any line in a region, computed
    /// once rather than on every camera move.
    var regionFloors: [String: Int]
    /// `manifest.regions`' own order — the order `publishDisplayNetwork`
    /// draws regions in.
    var orderedRegions: [String]
    /// Every entry by bare line id, for resolving `dependsOn` without
    /// rebuilding a dictionary on each camera callback.
    var entryByID: [String: Entry]
    /// Every region that lists a line id. A bare id may appear in more than
    /// one region (manifest keys are `region|id`), and the closure must keep
    /// all of them, not only the one `entryByID` happens to hold.
    var regionsByID: [String: [String]]
    /// Regions the builder loads whole rather than a line at a time
    /// (manifest A1) — `activateDisplayLines` folds every entry of one of
    /// these into a single batch once any of it is needed. A manifest
    /// built before `loadStrategy` existed falls back to the region's
    /// total byte count.
    var wholeRegions: Set<String>

    static func lineIndex(for manifest: RailDisplayNetworkManifest) -> RailDisplayNetworkIndex {
        var entriesByRegion: [String: [Entry]] = [:]
        for line in manifest.lines.values {
            guard let chunk = line.chunk else { continue }
            entriesByRegion[line.region, default: []].append(
                Entry(
                    id: line.id, region: line.region, mapRect: line.mapRect,
                    minimumCameraZoom: line.minimumCameraZoom, chunk: chunk,
                    overview: line.overview,
                    dependsOn: line.dependsOn ?? [], format: manifest.format,
                    temporalBank: manifest.regions.first(where: { $0.region == line.region })?.temporalBank))
        }
        for region in entriesByRegion.keys {
            entriesByRegion[region]?.sort { $0.chunk.offset < $1.chunk.offset }
        }
        let recordsByRegion = Dictionary(
            uniqueKeysWithValues: manifest.regions.map { ($0.region, $0) })
        let regionFloors = manifest.lines.values.reduce(into: [String: Int]()) { floors, line in
            floors[line.region] = min(floors[line.region] ?? Int.max, line.nativeMinZoomMapLibre)
        }
        var entryByID: [String: Entry] = [:]
        for entries in entriesByRegion.values {
            for entry in entries { entryByID[entry.id] = entry }
        }
        var regionsByID: [String: [String]] = [:]
        for (region, entries) in entriesByRegion {
            for entry in entries { regionsByID[entry.id, default: []].append(region) }
        }
        let wholeRegions = Set(manifest.regions.compactMap { record -> String? in
            if let strategy = record.loadStrategy {
                return strategy == "whole" ? record.region : nil
            }
            return record.bytes <= 1_500_000 ? record.region : nil
        })
        return RailDisplayNetworkIndex(
            entriesByRegion: entriesByRegion, recordsByRegion: recordsByRegion,
            regionFloors: regionFloors, orderedRegions: manifest.regions.map(\.region),
            entryByID: entryByID, regionsByID: regionsByID, wholeRegions: wholeRegions)
    }
}

/// The station identity table for one region (`{region}.stations.json`,
/// docs §4): every line's station rows merged by package station id, with
/// homonym groups, id collisions and similar-name clusters resolved once at
/// build time. Read on demand for selected-journey station priorities.
struct RailDisplayStationTable: Decodable, Sendable {
    struct Station: Decodable, Sendable {
        var key: String
        var id: String
        var name: String
        var nameKey: String
        var nameRoma: String?
        var lon: Double
        var lat: Double
        var spreadMetres: Double
        var lines: [String]
        var operators: [String]
        var hubId: String?
        var displayLabel: String
        var homonymGroup: String?
        var idCollision: Bool
    }

    struct HomonymGroup: Decodable, Sendable {
        var keys: [String]
        var maxSeparationKm: Double
    }

    struct IDCollision: Decodable, Sendable {
        struct Member: Decodable, Sendable {
            var lineId: String
            var lon: Double
            var lat: Double
        }
        var key: String
        var spreadMetres: Double
        var members: [Member]
    }

    struct SimilarNameGroup: Decodable, Sendable {
        var core: String
        var keys: [String]
        var names: [String]
    }

    static let format = "jtm-display-stations-v2"

    var format: String
    var region: String
    var stations: [Station]
    var homonymGroups: [String: HomonymGroup]
    var idCollisions: [IDCollision]
    var similarNameGroups: [SimilarNameGroup]
}

/// `{region}.display-history.json` (`jtm-display-history-v1`). Not part of
/// the geometry blob. `LineFragment` is unchanged.
struct RailDisplayHistoryFile: Decodable, Sendable {
    static let format = "jtm-display-history-v1"

    struct PartRow: Decodable, Sendable {
        var id: String
        var index: Int
        var kind: String
        var validFrom: String?
        var validTo: String?
        var historyId: String?
        var suspensionPeriodID: String? = nil
    }

    struct LinePart: Decodable, Sendable {
        var coordinates: [[Double]]
        var kind: String
        var validFrom: String?
        var validTo: String?
    }

    struct Line: Decodable, Sendable {
        var historyId: String
        var name: String
        var `operator`: String
        var color: String
        var colorDark: String
        var kind: String
        var rank: Int
        var minZoomMapLibre: Int
        var visibilityLengthKm: Double
        var parts: [LinePart]
    }

    struct Station: Decodable, Sendable {
        var historyId: String
        var name: String
        var nameRoma: String?
        var lineName: String
        var `operator`: String
        var lon: Double
        var lat: Double
        var kind: String
        var color: String
        var minZoomMapLibre: Int
        var lineHistoryId: String
        var validFrom: String?
        var validTo: String?
    }

    struct StationStamp: Decodable, Sendable {
        var id: String
        var kind: String
        var validFrom: String?
        var validTo: String?
        var historyId: String?
        var suspensionPeriodID: String? = nil
    }

    var format: String
    var region: String
    var parts: [PartRow]
    var lines: [Line]
    var stations: [Station]
    var stationStamps: [StationStamp]
    var revision: String? = nil
    var temporalBank: RailDisplayNetworkManifest.TemporalBank? = nil

    /// A required v3 temporal side file must stamp every managed line and
    /// station with its separate suspension-period id before geometry use.
    func validateTemporalStamps(managedLineIDs: Set<String>) throws {
        func validDay(_ value: String) -> Bool {
            guard Dates.isValidDateString(value), let year = Int(value.prefix(4)), year > 0,
                  let month = Int(value.dropFirst(5).prefix(2)), let day = Int(value.suffix(2)) else { return false }
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            return day <= monthDays[month - 1]
        }
        func validStamp(id: String?, from: String?, to: String?) -> Bool {
            guard let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let to, validDay(to) else { return false }
            return from.map { validDay($0) && $0 < to } ?? true
        }
        var partKeys = Set<String>()
        var stationKeys = Set<String>()
        var stampedLines = Set<String>()
        var stampedStationLines = Set<String>()
        for part in parts {
            guard part.index >= 0, partKeys.insert("\(part.id)\u{1f}\(part.index)").inserted else {
                throw RailDisplayNetworkError.invalidRegionPayload(region)
            }
            let lineID = Self.bareLineID(fromDrawID: part.id)
            if managedLineIDs.contains(lineID) {
                guard validStamp(id: part.suspensionPeriodID, from: part.validFrom, to: part.validTo),
                      RouteGraph.TemporalKind(rawValue: part.kind) != nil else {
                    throw RailDisplayNetworkError.invalidRegionPayload(region)
                }
                stampedLines.insert(lineID)
            }
        }
        for station in stationStamps {
            guard stationKeys.insert(station.id).inserted else {
                throw RailDisplayNetworkError.invalidRegionPayload(region)
            }
            let lineID = String(station.id.prefix { $0 != ":" })
            if managedLineIDs.contains(lineID) {
                guard validStamp(id: station.suspensionPeriodID, from: station.validFrom, to: station.validTo),
                      RouteGraph.TemporalKind(rawValue: station.kind) != nil else {
                    throw RailDisplayNetworkError.invalidRegionPayload(region)
                }
                stampedStationLines.insert(lineID)
            }
        }
        guard stampedLines == managedLineIDs, stampedStationLines == managedLineIDs else {
            throw RailDisplayNetworkError.invalidRegionPayload(region)
        }
    }

    /// Full managed chunks (including preview requests promoted from overview)
    /// require complete suspension stamps; partial banks cannot appear current.
    func validateTemporalGeometry(_ file: RailDisplayNetworkFile) throws {
        guard !file.lines.isEmpty else { throw RailDisplayNetworkError.invalidRegionPayload(region) }
        let rows = partRows
        let stamps = stationStampRows
        for fragment in file.lines {
            let drawID = fragment.continuous == true
                ? "\(fragment.lineKey)#\(fragment.chain ?? 0)"
                : "\(fragment.lineKey)@\(fragment.lane ?? 0)"
            guard fragment.parts.indices.allSatisfy({
                !(rows[drawID]?[$0]?.suspensionPeriodID?.isEmpty ?? true)
            }) else { throw RailDisplayNetworkError.invalidRegionPayload(region) }
        }
        guard file.stations.allSatisfy({ !(stamps[$0.id]?.suspensionPeriodID?.isEmpty ?? true) }) else {
            throw RailDisplayNetworkError.invalidRegionPayload(region)
        }
    }

    /// Draw id (`lineKey#chain` or `lineKey@lane`) → part index → decoration.
    var partRows: [String: [Int: DisplayTemporalDecoration]] {
        var rows: [String: [Int: DisplayTemporalDecoration]] = [:]
        for part in parts {
            rows[part.id, default: [:]][part.index] = DisplayTemporalDecoration(
                historyId: part.historyId, validFrom: part.validFrom, validTo: part.validTo,
                kind: RouteGraph.TemporalKind(rawValue: part.kind) ?? .current,
                suspensionPeriodID: part.suspensionPeriodID)
        }
        return rows
    }

    var stationStampRows: [String: DisplayTemporalDecoration] {
        Dictionary(uniqueKeysWithValues: stationStamps.map { stamp in
            (stamp.id, DisplayTemporalDecoration(
                historyId: stamp.historyId, validFrom: stamp.validFrom, validTo: stamp.validTo,
                kind: RouteGraph.TemporalKind(rawValue: stamp.kind) ?? .current,
                suspensionPeriodID: stamp.suspensionPeriodID))
        })
    }

    /// Bare package line ids that have at least one stamped part. Those lines
    /// stay on the full chunk: overview vertices are not the stamped parts.
    var fullDetailLineIDs: Set<String> {
        Set(parts.map { Self.bareLineID(fromDrawID: $0.id) })
    }

    static func bareLineID(fromDrawID id: String) -> String {
        let head: String
        if let hash = id.lastIndex(of: "#") {
            head = String(id[..<hash])
        } else if let at = id.lastIndex(of: "@") {
            head = String(id[..<at])
        } else {
            head = id
        }
        guard let bar = head.firstIndex(of: "|") else { return head }
        return String(head[head.index(after: bar)...])
    }
}


extension RailDisplayNetworkManifest {
    /// One region's lines as the badge index reads them, in package order —
    /// equal to `RouteBadgeIndex.Source(header:)` over the package's headers
    /// (both canonical, see ``RouteBadgeIndex/Source``), taken from the
    /// manifest the map already decodes instead of a scan of the package.
    ///
    /// `nil` when no line of the region carries ``Line/badge`` (a manifest
    /// built before the field existed), so the caller can fall back.
    func badgeSources(region: String) -> [RouteBadgeIndex.Source]? {
        let rows = lines.values
            .compactMap { line in
                line.region == region ? line.badge.map { (line, $0) } : nil
            }
            .sorted { $0.1.order < $1.1.order }
        guard !rows.isEmpty else { return nil }
        return rows.map { line, badge in
            let uncolored = (badge.uncolored ?? 0) != 0
            return RouteBadgeIndex.Source(
                id: line.id, name: line.name, nameNorm: badge.nameNorm,
                operator: line.operator, operatorShort: badge.operatorShort,
                operatorLogo: line.operatorLogo,
                color: uncolored ? nil : (badge.color ?? line.color),
                colorDark: uncolored ? nil : (badge.colorDark ?? line.colorDark),
                hasLogo: line.logo != nil)
        }
    }
}
