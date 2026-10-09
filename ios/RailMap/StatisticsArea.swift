import Foundation
import MapKit
import RailCore
import RailPresentation

/// The mutually exclusive leaves stored in the bundled Japanese area grid.
enum JapanAreaLeaf: String, CaseIterable, Sendable, Hashable {
    case hokkaido, tohoku, kanto, hokuriku, koshin, tokai, kinki, chugoku, shikoku, kyushu, okinawa
}

/// A Japanese sub-region the statistics destination can present as a scope.
enum StatisticsArea: String, CaseIterable, Identifiable, Sendable, Hashable {
    case hokkaido, honshu, tohoku, kanto, hokuriku, koshin, tokai, kinki, chugoku, shikoku, kyushu, okinawa

    var id: String { rawValue }

    var leaves: Set<JapanAreaLeaf> {
        switch self {
        case .honshu: Set(Self.honshuAreas.compactMap { JapanAreaLeaf(rawValue: $0.rawValue) })
        default: JapanAreaLeaf(rawValue: rawValue).map { [$0] } ?? []
        }
    }

    static let islands: [StatisticsArea] = [.hokkaido, .honshu, .shikoku, .kyushu, .okinawa]
    static let honshuAreas: [StatisticsArea] = [.tohoku, .kanto, .hokuriku, .koshin, .tokai, .kinki, .chugoku]

    var localizationKey: String { "ios.area.\(rawValue)" }
    var fallbackName: String {
        switch self {
        case .hokkaido: "北海道 Hokkaido"
        case .honshu: "本州 Honshu"
        case .tohoku: "東北 Tohoku"
        case .kanto: "関東 Kanto"
        case .hokuriku: "北陸 Hokuriku"
        case .koshin: "甲信 Koshin"
        case .tokai: "東海 Tokai"
        case .kinki: "近畿 Kinki"
        case .chugoku: "中国 Chugoku"
        case .shikoku: "四国 Shikoku"
        case .kyushu: "九州 Kyushu"
        case .okinawa: "沖縄 Okinawa"
        }
    }
    var systemImage: String { "map" }
}

/// A statistics scope whose Japan member can be narrowed to grid leaves.
struct StatisticsScope: Hashable, Sendable {
    var regions: Set<Region>
    var japanLeaves: Set<JapanAreaLeaf>?

    static let everything = StatisticsScope(regions: Set(Region.enabledOrdered), japanLeaves: nil)

    init(region: Region?, area: StatisticsArea?) {
        if let region {
            self.init(regions: [region], japanLeaves: region == .jp ? area?.leaves : nil)
        } else {
            self = .everything
        }
    }

    init(regions: Set<Region>, japanLeaves: Set<JapanAreaLeaf>?) {
        self.regions = regions
        self.japanLeaves = regions.contains(.jp) ? japanLeaves : nil
    }

    var countries: [String] { Region.enabledOrdered.filter(regions.contains).map(\.code) }
    var isEmpty: Bool { regions.isEmpty || (regions == [.jp] && japanLeaves?.isEmpty == true) }

    func union(_ other: StatisticsScope) -> StatisticsScope {
        let combined = regions.union(other.regions)
        let leaves: Set<JapanAreaLeaf>?
        if !combined.contains(.jp) {
            leaves = nil
        } else if (regions.contains(.jp) && japanLeaves == nil)
                    || (other.regions.contains(.jp) && other.japanLeaves == nil) {
            leaves = nil
        } else {
            leaves = (regions.contains(.jp) ? japanLeaves ?? [] : [])
                .union(other.regions.contains(.jp) ? other.japanLeaves ?? [] : [])
        }
        return StatisticsScope(regions: combined, japanLeaves: leaves)
    }

    func intersection(_ other: StatisticsScope) -> StatisticsScope {
        var common = regions.intersection(other.regions)
        var leaves: Set<JapanAreaLeaf>?
        if common.contains(.jp) {
            switch (japanLeaves, other.japanLeaves) {
            case (nil, nil): leaves = nil
            case (let lhs?, nil): leaves = lhs
            case (nil, let rhs?): leaves = rhs
            case (let lhs?, let rhs?): leaves = lhs.intersection(rhs)
            }
            if leaves?.isEmpty == true { common.remove(.jp); leaves = nil }
        } else {
            leaves = nil
        }
        return StatisticsScope(regions: common, japanLeaves: leaves)
    }

    var key: String {
        let regionKey = regions.map(\.code).sorted().joined(separator: ",")
        let leafKey = japanLeaves.map { $0.map(\.rawValue).sorted().joined(separator: ",") } ?? "*"
        return "\(regionKey)|\(leafKey)"
    }

    var japanLeavesForIndex: Set<JapanAreaLeaf>? {
        guard regions.contains(.jp), let japanLeaves,
              japanLeaves.count != JapanAreaLeaf.allCases.count else { return nil }
        return japanLeaves
    }

    func contains(_ train: Train, rideLeaves: Set<JapanAreaLeaf>?) -> Bool {
        let region = Region.resolved(train)
        guard regions.contains(region) else { return false }
        guard region == .jp, let wanted = japanLeavesForIndex else { return true }
        guard let rideLeaves else { return false }
        return !wanted.isDisjoint(with: rideLeaves)
    }

    func filter(_ trains: [Train], rides: [RiddenRouteStore.DrawnRide]) -> [Train] {
        guard japanLeavesForIndex != nil else { return trains.filter { regions.contains(Region.resolved($0)) } }
        let byID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return trains.filter { train in
            guard regions.contains(Region.resolved(train)) else { return false }
            let leaves = byID[train.id].map(JapanAreaGrid.shared.leaves(of:))
            return contains(train, rideLeaves: leaves)
        }
    }
}

/// The decoded lookup grid shared by ride filtering, map fitting and indexes.
final class JapanAreaGrid: @unchecked Sendable {
    static let shared = JapanAreaGrid()

    private struct Payload: Decodable {
        var leaves: [String]
        var minLon: Double
        var minLat: Double
        var step: Double
        var cols: Int
        var rows: Int
        var rowsRLE: [[Int]]
        var extents: [String: [Double]]

        enum CodingKeys: String, CodingKey {
            case leaves, minLon, minLat, step, cols, rows, extents
            case rowsRLE = "rows_rle"
        }
    }

    private struct Storage {
        var memo: [String: Set<JapanAreaLeaf>] = [:]
    }

    private let payload: Payload?
    private let cells: [UInt8]
    private let lock = NSLock()
    private var storage = Storage()

    private init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "jp-area-grid", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            self.payload = nil
            cells = []
            return
        }
        var decoded: [UInt8] = []
        decoded.reserveCapacity(payload.rows * payload.cols)
        for row in payload.rowsRLE.prefix(payload.rows) {
            var values: [UInt8] = []
            var index = 0
            while index + 1 < row.count {
                values.append(contentsOf: repeatElement(UInt8(clamping: row[index]), count: max(0, row[index + 1])))
                index += 2
            }
            decoded.append(contentsOf: values.prefix(payload.cols))
            if values.count < payload.cols { decoded.append(contentsOf: repeatElement(0, count: payload.cols - values.count)) }
        }
        if decoded.count < payload.rows * payload.cols {
            decoded.append(contentsOf: repeatElement(0, count: payload.rows * payload.cols - decoded.count))
        }
        self.payload = payload
        cells = Array(decoded.prefix(payload.rows * payload.cols))
    }

    var isAvailable: Bool { payload != nil }

    func leaf(lat: Double, lon: Double) -> JapanAreaLeaf? {
        guard let payload, lon >= payload.minLon, lat >= payload.minLat else { return nil }
        let column = Int(floor((lon - payload.minLon) / payload.step))
        let row = Int(floor((lat - payload.minLat) / payload.step))
        guard row >= 0, row < payload.rows, column >= 0, column < payload.cols else { return nil }
        let value = Int(cells[row * payload.cols + column])
        guard value > 0, value <= payload.leaves.count else { return nil }
        return JapanAreaLeaf(rawValue: payload.leaves[value - 1])
    }

    /// A ride belongs to every area containing any drawn vertex, while an edge
    /// is assigned only to the area containing its midpoint. This mismatch is
    /// a known, accepted limitation of area-scoped statistics.
    func leaves(of ride: RiddenRouteStore.DrawnRide) -> Set<JapanAreaLeaf> {
        let digest = ride.geometryDigest
        let key = "\(ride.id)|\(digest)"
        lock.lock()
        if let cached = storage.memo[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let coordinates = ride.segments.flatMap(\.coordinates)
        let result = Set(coordinates.compactMap { leaf(lat: $0.lat, lon: $0.lon) })
        lock.lock()
        let prefix = "\(ride.id)|"
        storage.memo = storage.memo.filter { !$0.key.hasPrefix(prefix) }
        storage.memo[key] = result
        lock.unlock()
        return result
    }

    func extent(of leaves: Set<JapanAreaLeaf>) -> MKCoordinateRegion? {
        guard let payload else { return nil }
        let boxes = leaves.compactMap { payload.extents[$0.rawValue] }.filter { $0.count == 4 }
        guard let first = boxes.first else { return nil }
        let minLon = boxes.dropFirst().reduce(first[0]) { min($0, $1[0]) }
        let minLat = boxes.dropFirst().reduce(first[1]) { min($0, $1[1]) }
        let maxLon = boxes.dropFirst().reduce(first[2]) { max($0, $1[2]) }
        let maxLat = boxes.dropFirst().reduce(first[3]) { max($0, $1[3]) }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: maxLat - minLat, longitudeDelta: maxLon - minLon))
    }

    /// Rebuilds only the totals whose denominator changes with an area scope.
    nonisolated static func restricting(
        _ index: Statistics.EdgeIndex, country: String,
        to leaves: Set<JapanAreaLeaf>, grid: JapanAreaGrid,
        denominatorEdgeCount: Int = .max
    ) -> Statistics.EdgeIndex {
        var retained = Set<Int>()
        for (key, primary) in index.map {
            let lon = (Double(bitPattern: key.px) + Double(bitPattern: key.qx)) / 2
            let lat = (Double(bitPattern: key.py) + Double(bitPattern: key.qy)) / 2
            guard let leaf = grid.leaf(lat: lat, lon: lon), leaves.contains(leaf) else { continue }
            retained.insert(primary)
            retained.formUnion(index.variants[key] ?? [])
        }
        var km = index.km
        for i in km.indices where !retained.contains(i) { km[i] = 0 }
        let categories = Statistics.categories(country: country)
        var totalKm = 0.0
        var totalsByMask: [Int: Double] = Dictionary(uniqueKeysWithValues: categories.map { ($0.mask, 0) })
        var lineTotals = Statistics.OrderedDictionary<String, [Int: Double]>()
        for i in km.indices where i < denominatorEdgeCount
            && (index.currentNetwork.isEmpty || index.currentNetwork[i]) {
            totalKm += km[i]
            for category in categories where index.mask[i] & category.mask != 0 { totalsByMask[category.mask]! += km[i] }
            let line = index.lineName[i]
            guard !line.isEmpty else { continue }
            var values = lineTotals[line] ?? Statistics.zeroCategoryKm(country: country)
            for category in categories where index.lineMask[i] & category.mask != 0 { values[category.mask]! += km[i] }
            lineTotals[line] = values
        }
        for line in lineTotals.keys where lineTotals[line]?.values.allSatisfy({ $0 == 0 }) == true { lineTotals[line] = nil }
        var operators = Statistics.OrderedDictionary<String, String>()
        // EdgeIndex has no per-edge operator, so retain the existing line-level owner for surviving lines.
        for (line, value) in index.lineOperator.pairs where lineTotals[line] != nil { operators[line] = value }
        return Statistics.EdgeIndex(
            map: index.map, km: km, mask: index.mask, lineName: index.lineName, lineMask: index.lineMask,
            totalKm: totalKm, totalsByMask: totalsByMask, lineTotByCat: lineTotals,
            lineOperator: operators, temporalKind: index.temporalKind, validFrom: index.validFrom,
            validTo: index.validTo, historyId: index.historyId, currentNetwork: index.currentNetwork,
            variants: index.variants)
    }
}
