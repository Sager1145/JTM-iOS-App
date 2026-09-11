import CryptoKit
import Foundation
import MapKit
import RailCore
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
        /// `build-display-network.py`'s `renderGroup` — North America's
        /// operator-level identity collapse (`na-render-groups.json`,
        /// `renderGroupByRegion`), carried into the catalog next to the
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

    var format: String
    var packageSHA256: [String: String]
    var lines: [String: Line]
    var regions: [RegionRecord]

    static let shippedRegions: Set<String> = ["jp", "tw", "hk", "mo", "kr", "us", "ca"]

    func validated() throws -> Self {
        guard format == Self.format else {
            throw RailDisplayNetworkError.unsupportedFormat(format)
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
    struct LineFragment: Decodable, Sendable {
        var lineKey: String
        var lane: Double?
        /// One part per station-to-station interval — or per lane piece where
        /// a reviewed lane cuts one. The renderer culls at this granularity,
        /// so a part is both the unit of continuity and the unit of work.
        var parts: [[[Double]]]
        /// A continuous-stroke fragment (North America): the parts are one
        /// uncut chain of intervals sharing their endpoints, the reviewed lane
        /// rows ride along in metres from the chain's start, and the device
        /// bakes the screen-space offset in (`RailCore.ContinuousStroke`).
        var continuous: Bool?
        /// Which chain of the line this is; a withheld interval breaks one.
        var chain: Int?
        /// False when this chain shares a station anchor with the preceding
        /// chain but represents a different branch, not its continuation.
        var joinPrevious: Bool?
        /// `[fromMetres, toMetres, lane]` rows along the chain.
        var laneRows: [[Double]]?
        var totalMetres: Double?
        /// `[from, to, canonicalLineKey, canonicalChain, canonicalFrom,
        /// canonicalTo]`: over `from…to` this chain is drawn from that chain's
        /// alignment (see `RailCore.ContinuousStroke.Follow`).
        var follows: [FollowRow]?
        /// `[fromMetres, toMetres]` rows: spans the alignment gate withheld
        /// from the official-geometry comparison that this chain bridges
        /// rather than cuts (`build-display-network.py`'s
        /// `continuous_chains`). Metres along the chain, same ruler as
        /// `laneRows`. Absent or empty for a chain with nothing withheld.
        var withheld: [[Double]]?
        /// Family-collapse windows along this chain (`build-display-
        /// network.py`'s `chain_family_windows`, from the web agent's
        /// `familyWindowsByRegion`): a stretch this chain shares its stroke
        /// with a sibling railway of the same operator collapse
        /// (`na-render-groups.json`). Role 0 (`isLandlord`) draws the shared
        /// family stroke over the window, in that group's colour
        /// (`RailDisplayNetworkFile.families`); role 1 withholds this
        /// chain's own stroke over the window — the chain is still built
        /// whole underneath, for a ride or playback to slice, only what the
        /// network overlay draws there changes. Absent or empty for a chain
        /// with no family collapse.
        var familyWindows: [FamilyWindowRow]?
    }

    /// A family window row decodes from a mixed JSON array, the same way a
    /// `FollowRow` does.
    struct FamilyWindowRow: Decodable, Sendable {
        var from: Double
        var to: Double
        /// 0 (landlord: this chain draws the shared family stroke over the
        /// window) or 1 (tenant: this chain's own stroke is withheld over
        /// it). Kept as the raw value — see `validated()` — rather than an
        /// enum, so a role outside 0/1 is a validation failure rather than
        /// something an enum's decode silently coerces.
        var role: Int
        var groupID: String
        var isLandlord: Bool { role == 0 }

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            from = try container.decode(Double.self)
            to = try container.decode(Double.self)
            role = try container.decode(Int.self)
            groupID = try container.decode(String.self)
        }
    }

    /// One family's resolved colours (`RailDisplayNetworkFile.families`,
    /// `build-display-network.py`'s `region_families`, sourced from
    /// `na-render-groups.json`'s `groups[groupId]`).
    struct FamilyColor: Decodable, Sendable {
        var color: String
        var colorDark: String
    }

    /// A follow row decodes from a mixed JSON array.
    struct FollowRow: Decodable, Sendable {
        var from: Double
        var to: Double
        var canonicalLineKey: String
        var canonicalChain: Int
        var canonicalFrom: Double
        var canonicalTo: Double

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            from = try container.decode(Double.self)
            to = try container.decode(Double.self)
            canonicalLineKey = try container.decode(String.self)
            canonicalChain = try container.decode(Int.self)
            canonicalFrom = try container.decode(Double.self)
            canonicalTo = try container.decode(Double.self)
        }
    }

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
        detail expectedDetail: DisplayDetail? = nil
    ) throws -> Self {
        guard format == RailDisplayNetworkManifest.format else {
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
                    dependsOn: line.dependsOn ?? []))
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
        let wholeRegions = Set(manifest.regions.compactMap { record -> String? in
            if let strategy = record.loadStrategy {
                return strategy == "whole" ? record.region : nil
            }
            return record.bytes <= 1_500_000 ? record.region : nil
        })
        return RailDisplayNetworkIndex(
            entriesByRegion: entriesByRegion, recordsByRegion: recordsByRegion,
            regionFloors: regionFloors, orderedRegions: manifest.regions.map(\.region),
            entryByID: entryByID, wholeRegions: wholeRegions)
    }
}

/// The station identity table for one region (`{region}.stations.json`,
/// docs §4): every line's station rows merged by package station id, with
/// homonym groups, id collisions and similar-name clusters resolved once at
/// build time. Read on demand only — nothing in the app wires this up yet.
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

enum RailDisplayNetwork {
    static let subdirectory = "rail-display-network"

    static func manifest(bundle: Bundle = .main) throws -> RailDisplayNetworkManifest {
        guard let url = bundle.url(
            forResource: "manifest", withExtension: "json", subdirectory: subdirectory)
        else { throw RailDisplayNetworkError.missingManifest }
        return try JSONDecoder().decode(
            RailDisplayNetworkManifest.self, from: Data(contentsOf: url)).validated()
    }

    /// Reads a region's blob whole via `mmap` (`Data(contentsOf:options:.alwaysMapped)`);
    /// callers slice one railway's chunk out of it with `chunk(_:blob:catalog:families:)`.
    /// The blob is never itself re-hashed — see that function's doc comment
    /// for why the whole-file SHA has been dropped at runtime.
    static func blob(
        _ record: RailDisplayNetworkManifest.RegionRecord, bundle: Bundle = .main
    ) throws -> Data {
        guard let url = bundle.url(
            forResource: record.file, withExtension: nil, subdirectory: subdirectory)
        else { throw RailDisplayNetworkError.missingRegion(record.region) }
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count == record.bytes else {
            throw RailDisplayNetworkError.corruptRegion(record.region)
        }
        return data
    }

    /// Slices one railway's chunk out of its region's `blob`, then decodes
    /// and validates it.
    ///
    /// Runtime integrity now stops at the chunk: the whole-blob SHA-256 that
    /// v1 checked on every region load is dropped here, because the blob is
    /// `mmap`ped rather than copied and hashing it would mean paging in
    /// megabytes just to load one railway. The per-chunk SHA-256 is instead
    /// verified only in `#if DEBUG` builds, as a guard against a stale or
    /// hand-edited bundle during development; a release build trusts the
    /// bundle's own code signature.
    static func chunk(
        _ entry: RailDisplayNetworkIndex.Entry, blob: Data,
        detail: DisplayDetail = .full,
        catalog: [String: RailDisplayNetworkManifest.Line],
        families: [String: RailDisplayNetworkFile.FamilyColor]
    ) throws -> RailDisplayNetworkFile {
        // The overview chunk when one was requested AND the manifest has
        // one; otherwise (including a whole-region or overview-less line)
        // the full chunk, exactly as before this field existed. The
        // detail validated below is the one actually sliced, not the one
        // asked for, so a request for an absent overview quietly loads
        // full rather than failing its own detail check.
        let usesOverview = detail == .overview && entry.overview != nil
        let sliced = usesOverview ? entry.overview! : entry.chunk
        let effectiveDetail: DisplayDetail = usesOverview ? .overview : .full
        let data: Data
        do {
            data = try DisplayChunkReader.slice(
                blob, offset: sliced.offset, length: sliced.length)
        } catch {
            throw RailDisplayNetworkError.chunkOutOfRange(entry.id)
        }
        #if DEBUG
        guard SHA256.hash(data: data).hex == sliced.sha256 else {
            throw RailDisplayNetworkError.corruptChunk(entry.id)
        }
        #endif
        return try JSONDecoder().decode(RailDisplayNetworkFile.self, from: data)
            .validated(
                region: entry.region, lineId: entry.id, catalog: catalog, families: families,
                detail: effectiveDetail)
    }

    /// Reads and format-checks a region's station identity table
    /// (`{region}.stations.json`, docs §4). Nothing in the app currently
    /// loads this — it exists for a future station-identity feature — so
    /// this is a plain read rather than an `mmap`, and there is no chunk to
    /// slice.
    static func stationIdentity(
        region record: RailDisplayNetworkManifest.RegionRecord, bundle: Bundle = .main
    ) throws -> RailDisplayStationTable {
        guard let stationsFile = record.stationsFile,
              let url = bundle.url(
                  forResource: stationsFile, withExtension: nil, subdirectory: subdirectory)
        else { throw RailDisplayNetworkError.missingRegion(record.region) }
        let data = try Data(contentsOf: url)
        let table = try JSONDecoder().decode(RailDisplayStationTable.self, from: data)
        guard table.format == RailDisplayStationTable.format else {
            throw RailDisplayNetworkError.unsupportedFormat(table.format)
        }
        return table
    }

    /// Region records the padded map rect touches, and whose railways this
    /// camera is close enough in to draw.
    ///
    /// MapKit's world can repeat horizontally, so a rect that has wrapped past
    /// the eastern edge is tested against the world-shifted copies of each
    /// region as well as the region itself.
    static func records(
        intersecting rect: MKMapRect,
        cameraZoom: Double,
        in manifest: RailDisplayNetworkManifest
    ) -> [RailDisplayNetworkManifest.RegionRecord] {
        let world = MKMapRect.world.size.width
        let regionFloors = manifest.lines.values.reduce(into: [String: Int]()) { floors, line in
            floors[line.region] = min(floors[line.region] ?? Int.max, line.nativeMinZoomMapLibre)
        }
        return manifest.regions.filter { record in
            guard let floor = regionFloors[record.region],
                  RailStyle.zoom(fromMapLibre: Double(floor)) <= cameraZoom else { return false }
            let extent = record.mapRect
            guard !extent.isNull else { return false }
            return [-world, 0, world].contains { shift in
                extent.offsetBy(dx: shift, dy: 0).intersects(rect)
            }
        }
    }

    /// Same test, against a precomputed `RailDisplayNetworkIndex` instead of
    /// walking the manifest's line dictionary on every call.
    static func records(
        intersecting rect: MKMapRect,
        cameraZoom: Double,
        in index: RailDisplayNetworkIndex
    ) -> [RailDisplayNetworkManifest.RegionRecord] {
        let world = MKMapRect.world.size.width
        return index.orderedRegions.compactMap { region in
            guard let record = index.recordsByRegion[region],
                  let floor = index.regionFloors[region],
                  RailStyle.zoom(fromMapLibre: Double(floor)) <= cameraZoom else { return nil }
            let extent = record.mapRect
            guard !extent.isNull else { return nil }
            guard [-world, 0, world].contains(where: { shift in
                extent.offsetBy(dx: shift, dy: 0).intersects(rect)
            }) else { return nil }
            return record
        }
    }

    /// How far past a line's own minimum camera zoom the loader still
    /// prefetches it — in this app's zoom units, same ruler as
    /// `minimumCameraZoom`.
    static let zoomPrefetchMargin = 1.0

    /// Railway lines the padded map rect touches, this camera is close
    /// enough in to draw, or that one of those lines names in `dependsOn`
    /// (a continuous-stroke line drawn partly from another line's alignment
    /// — see `RailCore.ContinuousStroke.Follow`). A dependency is pulled in
    /// regardless of its own rect or zoom eligibility, because the line that
    /// depends on it needs its geometry to draw at all.
    ///
    /// Output is grouped by `index.orderedRegions`, each region's lines in
    /// blob order (D2) — the same order `publishDisplayNetwork` draws in.
    static func lines(
        intersecting rect: MKMapRect,
        cameraZoom: Double,
        in index: RailDisplayNetworkIndex
    ) -> [RailDisplayNetworkIndex.Entry] {
        let world = MKMapRect.world.size.width
        let regions = records(intersecting: rect, cameraZoom: cameraZoom, in: index)

        var base: [RailDisplayNetworkIndex.Entry] = []
        for record in regions {
            for entry in index.entriesByRegion[record.region] ?? [] {
                guard entry.minimumCameraZoom <= cameraZoom + zoomPrefetchMargin,
                      !entry.mapRect.isNull,
                      [-world, 0, world].contains(where: { shift in
                          entry.mapRect.offsetBy(dx: shift, dy: 0).intersects(rect)
                      })
                else { continue }
                base.append(entry)
            }
        }

        return closure(of: base, in: index)
    }

    /// The transitive closure of `entries` over `dependsOn`: every entry
    /// named, directly or indirectly, by one already in the list, added
    /// regardless of its own rect or zoom eligibility — a line that depends
    /// on another needs that line's geometry to draw at all. Output is
    /// grouped by `index.orderedRegions`, each region's lines in blob order
    /// (D2), same as ``lines(intersecting:cameraZoom:in:)``.
    static func closure(
        of entries: [RailDisplayNetworkIndex.Entry],
        in index: RailDisplayNetworkIndex
    ) -> [RailDisplayNetworkIndex.Entry] {
        let allEntries = index.entryByID
        var selected = Set(entries.map(\.id))
        var frontier = Array(selected)
        while !frontier.isEmpty {
            var next: [String] = []
            for id in frontier {
                guard let entry = allEntries[id] else { continue }
                for dependencyID in entry.dependsOn where !selected.contains(dependencyID) {
                    guard allEntries[dependencyID] != nil else { continue }
                    selected.insert(dependencyID)
                    next.append(dependencyID)
                }
            }
            frontier = next
        }
        return index.orderedRegions.flatMap { region in
            (index.entriesByRegion[region] ?? []).filter { selected.contains($0.id) }
        }
    }

    static func popup(
        for station: RailDisplayNetworkFile.Station,
        catalog: [String: RailDisplayNetworkManifest.Line]
    ) -> StationDisplay.PopupModel {
        var seen: Set<String> = []
        var rows: [StationDisplay.PopupRow] = []
        for key in station.groupLineKeys {
            guard let line = catalog[key] else { continue }
            // See `StationDisplay.buildPopupModel`'s identical rule: a
            // render group collapses two administratively distinct lines
            // (LIRR's branches, Metro-North, Metrolink) into one popup row —
            // and, since `RailMapAnnotations`' interchange test is this
            // row count, into one railway rather than a false interchange.
            let displayKey = line.renderGroup.map { "group\u{0}\($0)" }
                ?? "\(line.operator ?? "")\u{0}\(line.name)"
            guard seen.insert(displayKey).inserted else { continue }
            let branding = OperatorBranding.Line(
                lineId: line.id, operator: line.operator, logo: line.logo ?? line.operatorLogo)
            let logo = OperatorBranding.logoForLine(branding)
            let label = line.nameRoma.flatMap { $0.isEmpty ? nil : "\(line.name) (\($0))" }
                ?? line.name
            rows.append(.init(
                lineID: line.id,
                company: OperatorBranding.companyFor(
                    operator: line.operator, lineName: line.name),
                label: label, color: line.color, logo: logo,
                logoNeedsDarkMatte: OperatorBranding.logoNeedsDarkMatte(logo)))
        }
        rows.sort {
            $0.label.compare($1.label, options: [], locale: Locale(identifier: "en_US"))
                == .orderedAscending
        }
        return .init(
            name: station.name, nameRoma: station.nameRoma ?? "", readings: nil, lines: rows)
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
