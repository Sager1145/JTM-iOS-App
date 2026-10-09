import MapKit
import Observation
import RailCore
import SwiftUI

enum ShareCanvasRatio: String, CaseIterable, Identifiable {
    case square, landscape, portrait, wide, tall

    var id: String { rawValue }
    var aspect: CGFloat {
        switch self {
        case .square: 1
        case .landscape: 4 / 3
        case .portrait: 3 / 4
        case .wide: 16 / 9
        case .tall: 9 / 16
        }
    }
    var grid: (columns: Int, rows: Int) {
        switch self {
        case .square: (6, 6)
        case .landscape: (8, 6)
        case .portrait: (6, 8)
        case .wide: (12, 7)
        case .tall: (6, 11)
        }
    }
    var label: String {
        switch self {
        case .square: "1:1"
        case .landscape: "4:3"
        case .portrait: "3:4"
        case .wide: "16:9"
        case .tall: "9:16"
        }
    }
}

enum ShareCanvasSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var longEdge: CGFloat {
        switch self {
        case .small: 1080
        case .medium: 1620
        case .large: 2160
        }
    }
    func pixelSize(for ratio: ShareCanvasRatio) -> CGSize {
        ratio.aspect >= 1
            ? CGSize(width: longEdge, height: (longEdge / ratio.aspect).rounded())
            : CGSize(width: (longEdge * ratio.aspect).rounded(), height: longEdge)
    }
}

struct GridSpan: Hashable {
    var columns: Int
    var rows: Int
}

struct GridRect: Hashable {
    var column: Int
    var row: Int
    var columns: Int
    var rows: Int
}

enum ShareMapArea: Hashable, Identifiable {
    case region(Region)
    case japan(StatisticsArea)

    var id: String {
        switch self {
        case .region(let region): "region-\(region.rawValue)"
        case .japan(let area): "japan-\(area.rawValue)"
        }
    }
    var scope: StatisticsScope {
        switch self {
        case .region(let region): StatisticsScope(region: region, area: nil)
        case .japan(let area): StatisticsScope(region: .jp, area: area)
        }
    }
    @MainActor func localizedName(_ localization: AppLocalization) -> String {
        switch self {
        case .region(let region):
            localization.text(region.localizationKey, fallback: region.fallbackName)
        case .japan(let area):
            localization.text(area.localizationKey, fallback: area.fallbackName)
        }
    }
    var mapExtent: MKCoordinateRegion? {
        switch self {
        case .region(let region): region.networkExtent
        case .japan(let area): JapanAreaGrid.shared.extent(of: area.leaves)
        }
    }
    static let menuOrder: [ShareMapArea] = [
        .region(.jp), .japan(.hokkaido), .japan(.honshu),
        .japan(.tohoku), .japan(.kanto), .japan(.hokuriku), .japan(.koshin),
        .japan(.tokai), .japan(.kinki), .japan(.chugoku),
        .japan(.shikoku), .japan(.kyushu), .japan(.okinawa),
        .region(.tw), .region(.hk), .region(.mo), .region(.kr),
    ]
}

enum MapCardRatio: String, CaseIterable, Identifiable {
    case square, fourThree, threeFour, threeTwo, twoThree, twoOne, oneTwo, threeOne, oneThree
    var id: String { rawValue }
    var span: GridSpan {
        switch self {
        case .square: GridSpan(columns: 1, rows: 1)
        case .fourThree: GridSpan(columns: 4, rows: 3)
        case .threeFour: GridSpan(columns: 3, rows: 4)
        case .threeTwo: GridSpan(columns: 3, rows: 2)
        case .twoThree: GridSpan(columns: 2, rows: 3)
        case .twoOne: GridSpan(columns: 2, rows: 1)
        case .oneTwo: GridSpan(columns: 1, rows: 2)
        case .threeOne: GridSpan(columns: 3, rows: 1)
        case .oneThree: GridSpan(columns: 1, rows: 3)
        }
    }
    var label: String { "\(span.columns):\(span.rows)" }
    static func matching(_ span: GridSpan) -> MapCardRatio {
        let divisor = greatestCommonDivisor(span.columns, span.rows)
        let reduced = GridSpan(columns: span.columns / divisor, rows: span.rows / divisor)
        return allCases.min {
            abs(Double($0.span.columns) / Double($0.span.rows) - Double(reduced.columns) / Double(reduced.rows))
                < abs(Double($1.span.columns) / Double($1.span.rows) - Double(reduced.columns) / Double(reduced.rows))
        } ?? .square
    }
    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return max(x, 1)
    }
}

private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
    var x = a, y = b
    while y != 0 { (x, y) = (y, x % y) }
    return max(x, 1)
}

enum StatCardSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge
    var id: String { rawValue }
    var span: GridSpan {
        switch self {
        case .small: GridSpan(columns: 2, rows: 2)
        case .medium: GridSpan(columns: 4, rows: 2)
        case .large: GridSpan(columns: 4, rows: 4)
        case .extraLarge: GridSpan(columns: 6, rows: 4)
        }
    }
}

struct ShareCard: Identifiable, Hashable {
    enum Kind: Hashable {
        case ticket
        case map(ShareMapArea)
        case stat(StatisticsCardKind)
    }

    var id = UUID()
    var kind: Kind
    var span: GridSpan
    var mapRatio: MapCardRatio?
    var mapZoom: Double = 1

    init(id: UUID = UUID(), kind: Kind, span: GridSpan, mapRatio: MapCardRatio? = nil,
         mapZoom: Double = 1) {
        self.id = id
        self.kind = kind
        self.span = span
        self.mapRatio = mapRatio
        self.mapZoom = min(max(mapZoom, 0.75), 2)
    }
}

enum ShareLayout {
    struct Result {
        var placements: [UUID: GridRect]
        var overflow: [UUID]
        var occupied: GridRect?
    }

    static func pack(_ cards: [ShareCard], columns: Int, rows: Int) -> Result {
        var occupiedCells = Set<Int>()
        var placements: [UUID: GridRect] = [:]
        var overflow: [UUID] = []
        for card in cards {
            var placed: GridRect?
            if card.span.columns <= columns, card.span.rows <= rows {
                outer: for row in 0...(rows - card.span.rows) {
                    for column in 0...(columns - card.span.columns) {
                        let cells = (row..<(row + card.span.rows)).flatMap { y in
                            (column..<(column + card.span.columns)).map { y * columns + $0 }
                        }
                        if cells.allSatisfy({ !occupiedCells.contains($0) }) {
                            occupiedCells.formUnion(cells)
                            placed = GridRect(column: column, row: row,
                                            columns: card.span.columns, rows: card.span.rows)
                            break outer
                        }
                    }
                }
            }
            if let placed { placements[card.id] = placed } else { overflow.append(card.id) }
        }
        let bounds = placements.values.reduce(nil as GridRect?) { current, rect in
            guard let current else { return rect }
            let left = min(current.column, rect.column), top = min(current.row, rect.row)
            let right = max(current.column + current.columns, rect.column + rect.columns)
            let bottom = max(current.row + current.rows, rect.row + rect.rows)
            return GridRect(column: left, row: top, columns: right - left, rows: bottom - top)
        }
        return Result(placements: placements, overflow: overflow, occupied: bounds)
    }
}

enum ShareLayoutPreset: String, CaseIterable, Identifiable {
    case japanIslands, taiwan, hongKong, macau
    var id: String { rawValue }

    func cards(for ratio: ShareCanvasRatio) -> [ShareCard] {
        switch self {
        case .japanIslands:
            let specs: [(ShareMapArea?, GridSpan)]
            switch ratio {
            case .square: specs = [(nil, .init(columns: 3, rows: 2)), (.japan(.hokkaido), .init(columns: 3, rows: 2)), (.japan(.honshu), .init(columns: 4, rows: 4)), (.japan(.shikoku), .init(columns: 2, rows: 1)), (.japan(.kyushu), .init(columns: 2, rows: 2)), (.japan(.okinawa), .init(columns: 2, rows: 1))]
            case .landscape, .portrait: specs = [(nil, .init(columns: 6, rows: 4)), (.japan(.hokkaido), .init(columns: 2, rows: 2)), (.japan(.honshu), .init(columns: 4, rows: 2)), (.japan(.shikoku), .init(columns: 2, rows: 2)), (.japan(.kyushu), .init(columns: 2, rows: 2)), (.japan(.okinawa), .init(columns: 2, rows: 2))]
            case .wide: specs = [(nil, .init(columns: 6, rows: 4)), (.japan(.honshu), .init(columns: 6, rows: 4)), (.japan(.hokkaido), .init(columns: 3, rows: 3)), (.japan(.shikoku), .init(columns: 3, rows: 3)), (.japan(.kyushu), .init(columns: 3, rows: 3)), (.japan(.okinawa), .init(columns: 3, rows: 3))]
            case .tall: specs = [(nil, .init(columns: 6, rows: 4)), (.japan(.honshu), .init(columns: 4, rows: 4)), (.japan(.hokkaido), .init(columns: 2, rows: 2)), (.japan(.shikoku), .init(columns: 2, rows: 2)), (.japan(.kyushu), .init(columns: 3, rows: 3)), (.japan(.okinawa), .init(columns: 3, rows: 3))]
            }
            return specs.map { area, span in
                area.map { ShareCard(kind: .map($0), span: span, mapRatio: .matching(span)) }
                    ?? ShareCard(kind: .ticket, span: span)
            }
        case .taiwan, .hongKong, .macau:
            let region: Region = self == .taiwan ? .tw : self == .hongKong ? .hk : .mo
            let spans: (GridSpan, GridSpan)
            switch ratio {
            case .square: spans = (.init(columns: 6, rows: 4), .init(columns: 6, rows: 2))
            case .landscape: spans = (.init(columns: 6, rows: 4), .init(columns: 2, rows: 4))
            case .portrait: spans = (.init(columns: 6, rows: 4), .init(columns: 6, rows: 4))
            case .wide: spans = (.init(columns: 9, rows: 6), .init(columns: 3, rows: 6))
            case .tall: spans = (.init(columns: 6, rows: 4), .init(columns: 6, rows: 6))
            }
            return [ShareCard(kind: .ticket, span: spans.0),
                    ShareCard(kind: .map(.region(region)), span: spans.1,
                              mapRatio: .matching(spans.1))]
        }
    }

    static func debugCheck() {
#if DEBUG
        for preset in allCases {
            for ratio in ShareCanvasRatio.allCases {
                let grid = ratio.grid
                assert(ShareLayout.pack(preset.cards(for: ratio), columns: grid.columns,
                                        rows: grid.rows).overflow.isEmpty)
            }
        }
#endif
    }
}

@MainActor @Observable
final class ShareComposerModel {
    var ratio: ShareCanvasRatio = .portrait {
        didSet { guard oldValue != ratio else { return }; ratioChanged() }
    }
    var size: ShareCanvasSize = .medium
    var colorScheme: ColorScheme
    private(set) var cards: [ShareCard] = []
    var selectedCardID: UUID?
    private(set) var appliedPreset: ShareLayoutPreset?
    var baseRegion: Region?
    var baseArea: StatisticsArea?
    let statistics = MileageStatisticsStore()
#if DEBUG
    let debugExportURL: URL?
#endif

    init(region: Region?, area: StatisticsArea?, colorScheme: ColorScheme,
         adopting source: MileageStatisticsStore) {
#if DEBUG
        let debug = DebugConfiguration(
            environment: ProcessInfo.processInfo.environment)
        debugExportURL = debug.exportURL
        if let base = debug.base {
            baseRegion = base.region
            baseArea = base.area
        } else {
            baseRegion = region
            baseArea = area
        }
        ratio = debug.ratio ?? .portrait
        size = debug.size ?? .medium
        self.colorScheme = debug.colorScheme ?? colorScheme
#else
        baseRegion = region
        baseArea = area
        self.colorScheme = colorScheme
#endif
        statistics.adoptSelection(from: source)
        ShareLayoutPreset.debugCheck()
        var requestedPreset: ShareLayoutPreset?
#if DEBUG
        requestedPreset = debug.preset
#endif
        if let requestedPreset {
            apply(requestedPreset)
        } else if region == nil || (region == .jp && area == nil) {
            apply(.japanIslands)
        } else if region == .tw { apply(.taiwan) }
        else if region == .hk { apply(.hongKong) }
        else if region == .mo { apply(.macau) }
        else {
            let mapArea = area.map(ShareMapArea.japan) ?? .region(region ?? .jp)
            cards = Self.singleRegionCards(area: mapArea, ratio: ratio)
        }
#if DEBUG
        if let encodedCards = debug.cards {
            cards = parseDebugCards(encodedCards)
            selectedCardID = cards.first?.id
            appliedPreset = nil
        }
#endif
    }

    var grid: (columns: Int, rows: Int) { ratio.grid }
    var layout: ShareLayout.Result {
        ShareLayout.pack(cards, columns: grid.columns, rows: grid.rows)
    }
    var baseScope: StatisticsScope { StatisticsScope(region: baseRegion, area: baseArea) }
    var effectiveScope: StatisticsScope {
        let maps = cards.compactMap { card -> StatisticsScope? in
            if case .map(let area) = card.kind { return area.scope }
            return nil
        }
        let mapScope = maps.dropFirst().reduce(maps.first ?? .everything) { $0.union($1) }
        return mapScope.intersection(baseScope)
    }
    func scopeDisplayName(_ localization: AppLocalization) -> String {
        let scope = effectiveScope
        if scope.regions == Set(Region.enabledOrdered) && scope.japanLeaves == nil {
            return localization.text("ios.region.all", fallback: "All regions")
        }
        if scope.regions == [.jp], let leaves = scope.japanLeaves,
           let area = StatisticsArea.allCases.first(where: { $0.leaves == leaves }) {
            return localization.text(area.localizationKey, fallback: area.fallbackName)
        }
        let names = Region.enabledOrdered.filter(scope.regions.contains).map {
            localization.text($0.localizationKey, fallback: $0.fallbackName)
        }
        return names.isEmpty
            ? localization.statsText("ios.stats.shareNoData")
            : names.joined(separator: "・")
    }

    func allowedSpans(for card: ShareCard) -> [GridSpan] {
        let grid = ratio.grid
        let candidates: [GridSpan]
        switch card.kind {
        case .ticket:
            candidates = (1...4).map { GridSpan(columns: 3 * $0, rows: 2 * $0) }
        case .map:
            let base = (card.mapRatio ?? .square).span
            let minimum = base.columns * base.rows >= 2 ? 1 : 2
            let maximum = max(grid.columns / base.columns, grid.rows / base.rows)
            candidates = maximum >= minimum
                ? (minimum...maximum).map { GridSpan(columns: base.columns * $0, rows: base.rows * $0) }
                : []
        case .stat:
            candidates = StatCardSize.allCases.map(\.span)
        }
        return candidates.filter { $0.columns <= grid.columns && $0.rows <= grid.rows }
    }

    func apply(_ preset: ShareLayoutPreset) {
        appliedPreset = preset
        cards = preset.cards(for: ratio)
        selectedCardID = cards.first?.id
    }
    func add(_ kind: ShareCard.Kind) {
        if case .ticket = kind, cards.contains(where: { if case .ticket = $0.kind { true } else { false } }) { return }
        let span: GridSpan
        let mapRatio: MapCardRatio?
        switch kind {
        case .ticket:
            span = allowedTicketDefault()
            mapRatio = nil
        case .map:
            span = GridSpan(columns: 2, rows: 2)
            mapRatio = .square
        case .stat:
            span = StatCardSize.medium.span.columns <= grid.columns ? StatCardSize.medium.span : StatCardSize.small.span
            mapRatio = nil
        }
        let card = ShareCard(kind: kind, span: span, mapRatio: mapRatio)
        cards.append(card)
        selectedCardID = card.id
        appliedPreset = nil
    }
    func remove(_ id: UUID) {
        cards.removeAll { $0.id == id }
        if selectedCardID == id { selectedCardID = cards.first?.id }
        appliedPreset = nil
    }
    func move(_ id: UUID, to index: Int) {
        guard let from = cards.firstIndex(where: { $0.id == id }) else { return }
        let card = cards.remove(at: from)
        cards.insert(card, at: min(max(index, 0), cards.count))
        appliedPreset = nil
    }
    func moveEarlier(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), index > 0 else { return }
        cards.swapAt(index, index - 1); appliedPreset = nil
    }
    func moveLater(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), index + 1 < cards.count else { return }
        cards.swapAt(index, index + 1); appliedPreset = nil
    }
    func setSpan(_ span: GridSpan, for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), allowedSpans(for: cards[index]).contains(span) else { return }
        cards[index].span = span
        appliedPreset = nil
    }
    func stepSize(_ id: UUID, by delta: Int) {
        guard let card = cards.first(where: { $0.id == id }) else { return }
        let options = allowedSpans(for: card)
        guard let current = options.firstIndex(of: card.span) else {
            if let nearest = nearestSpan(to: card.span, among: options) { setSpan(nearest, for: id) }
            return
        }
        setSpan(options[min(max(current + delta, 0), options.count - 1)], for: id)
    }
    func setMapRatio(_ mapRatio: MapCardRatio, for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), case .map = cards[index].kind else { return }
        let oldArea = cards[index].span.columns * cards[index].span.rows
        cards[index].mapRatio = mapRatio
        let options = allowedSpans(for: cards[index])
        cards[index].span = options.min { abs($0.columns * $0.rows - oldArea) < abs($1.columns * $1.rows - oldArea) }
            ?? GridSpan(columns: min(mapRatio.span.columns, grid.columns), rows: min(mapRatio.span.rows, grid.rows))
        appliedPreset = nil
    }
    func setZoom(_ zoom: Double, for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), case .map = cards[index].kind else { return }
        cards[index].mapZoom = min(max(zoom, 0.75), 2)
    }

    private func ratioChanged() {
        if let appliedPreset { cards = appliedPreset.cards(for: ratio); selectedCardID = cards.first?.id; return }
        for index in cards.indices {
            let options = allowedSpans(for: cards[index])
            if let nearest = nearestSpan(to: cards[index].span, among: options) { cards[index].span = nearest }
        }
    }
    private func allowedTicketDefault() -> GridSpan {
        let desired = GridSpan(columns: 6, rows: 4)
        let probe = ShareCard(kind: .ticket, span: desired)
        return allowedSpans(for: probe).last(where: { $0.columns <= desired.columns && $0.rows <= desired.rows })
            ?? allowedSpans(for: probe).last ?? GridSpan(columns: 3, rows: 2)
    }
    private func nearestSpan(to span: GridSpan, among options: [GridSpan]) -> GridSpan? {
        options.min {
            abs($0.columns - span.columns) + abs($0.rows - span.rows)
                < abs($1.columns - span.columns) + abs($1.rows - span.rows)
        }
    }
    private static func singleRegionCards(area: ShareMapArea, ratio: ShareCanvasRatio) -> [ShareCard] {
        let source = ShareLayoutPreset.taiwan.cards(for: ratio)
        return source.map { card in
            guard case .map = card.kind else { return card }
            return ShareCard(kind: .map(area), span: card.span, mapRatio: card.mapRatio)
        }
    }

#if DEBUG
    private struct DebugConfiguration {
        let preset: ShareLayoutPreset?
        let ratio: ShareCanvasRatio?
        let colorScheme: ColorScheme?
        let size: ShareCanvasSize?
        let base: (region: Region?, area: StatisticsArea?)?
        let cards: String?
        let exportURL: URL?

        init(environment: [String: String]) {
            preset = environment["RAILMAP_UI_TEST_SHARE_PRESET"].flatMap(ShareLayoutPreset.init)
            ratio = environment["RAILMAP_UI_TEST_SHARE_RATIO"].flatMap(ShareCanvasRatio.init)
            switch environment["RAILMAP_UI_TEST_SHARE_SCHEME"] {
            case "light": colorScheme = .light
            case "dark": colorScheme = .dark
            default: colorScheme = nil
            }
            size = environment["RAILMAP_UI_TEST_SHARE_SIZE"].flatMap(ShareCanvasSize.init)
            base = Self.parseBase(environment["RAILMAP_UI_TEST_SHARE_BASE"])
            cards = environment["RAILMAP_UI_TEST_SHARE_CARDS"]
            if let directory = environment["RAILMAP_UI_TEST_SHARE_EXPORT_DIR"],
               !directory.isEmpty {
                let name = environment["RAILMAP_UI_TEST_SHARE_NAME"].flatMap {
                    $0.isEmpty ? nil : $0
                } ?? "share"
                exportURL = URL(fileURLWithPath: directory, isDirectory: true)
                    .appendingPathComponent(name).appendingPathExtension("png")
            } else {
                exportURL = nil
            }
        }

        private static func parseBase(
            _ encoded: String?
        ) -> (region: Region?, area: StatisticsArea?)? {
            guard let encoded else { return nil }
            if encoded == "all" { return (nil, nil) }
            let parts = encoded.split(separator: ":", omittingEmptySubsequences: false)
            guard let region = parts.first.flatMap({ Region(rawValue: String($0)) }) else {
                return nil
            }
            if region == .jp, parts.count == 2,
               let area = StatisticsArea(rawValue: String(parts[1])) {
                return (.jp, area)
            }
            guard parts.count == 1 else { return nil }
            return (region, nil)
        }
    }

    private func parseDebugCards(_ encoded: String) -> [ShareCard] {
        let parsed = encoded.split(separator: ",").compactMap { item -> ShareCard? in
            let parts = item.split(separator: ":").map(String.init)
            guard let kind = parts.first else { return nil }
            switch kind {
            case "ticket":
                guard parts.count == 2, let span = Self.parseDebugSpan(parts[1]) else { return nil }
                return debugCard(kind: .ticket, requestedSpan: span)
            case "stat":
                guard parts.count == 3,
                      let stat = StatisticsCardKind(rawValue: parts[1]),
                      let span = Self.parseDebugSpan(parts[2]) else { return nil }
                return debugCard(kind: .stat(stat), requestedSpan: span)
            case "map":
                guard parts.count >= 3, let region = Region(rawValue: parts[1]) else { return nil }
                var spanIndex = 2
                let area: ShareMapArea
                if region == .jp, Self.parseDebugSpan(parts[spanIndex]) == nil {
                    guard let japanArea = StatisticsArea(rawValue: parts[spanIndex]) else { return nil }
                    area = .japan(japanArea)
                    spanIndex += 1
                } else {
                    area = .region(region)
                }
                guard parts.indices.contains(spanIndex),
                      let span = Self.parseDebugSpan(parts[spanIndex]),
                      parts.count <= spanIndex + 2 else { return nil }
                let zoom = parts.indices.contains(spanIndex + 1)
                    ? Double(parts[spanIndex + 1]) ?? 1 : 1
                return debugCard(kind: .map(area), requestedSpan: span,
                                 mapRatio: .matching(span), mapZoom: zoom)
            default:
                return nil
            }
        }
        let current = ShareLayout.pack(parsed, columns: grid.columns, rows: grid.rows)
        guard !current.overflow.isEmpty else { return parsed }
        let largestFirst = parsed.enumerated().sorted { lhs, rhs in
            let lhsArea = lhs.element.span.columns * lhs.element.span.rows
            let rhsArea = rhs.element.span.columns * rhs.element.span.rows
            return lhsArea == rhsArea ? lhs.offset < rhs.offset : lhsArea > rhsArea
        }.map(\.element)
        let repacked = ShareLayout.pack(largestFirst, columns: grid.columns, rows: grid.rows)
        return repacked.overflow.isEmpty ? largestFirst : parsed
    }

    private func debugCard(
        kind: ShareCard.Kind,
        requestedSpan: GridSpan,
        mapRatio: MapCardRatio? = nil,
        mapZoom: Double = 1
    ) -> ShareCard {
        var card = ShareCard(kind: kind, span: requestedSpan,
                             mapRatio: mapRatio, mapZoom: mapZoom)
        if let nearest = nearestSpan(to: requestedSpan, among: allowedSpans(for: card)) {
            card.span = nearest
        }
        return card
    }

    private static func parseDebugSpan(_ encoded: String) -> GridSpan? {
        let values = encoded.lowercased().split(separator: "x")
        guard values.count == 2, let columns = Int(values[0]), let rows = Int(values[1]),
              columns > 0, rows > 0 else { return nil }
        return GridSpan(columns: columns, rows: rows)
    }
#endif
}
