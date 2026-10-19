import RailPresentation
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

struct ShareCard: Identifiable, Hashable {
    enum Kind: Hashable {
        case ticket
        case map(ShareMapArea)
        case stat(StatisticsCardKind)

        var allowedShapes: [CardShape] {
            switch self {
            case .ticket: [.medium]
            case .map: CardShape.standardShapes
            case .stat(let kind): kind.widgetShapes
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var size: CardSize
    var mapZoom: Double = 1
    var parked: Bool = false
    var scopeOverride: ShareMapArea?
    var usesCustomDates = false
    var span: GridSpan { size.span }

    init(id: UUID = UUID(), kind: Kind, size: CardSize,
         mapZoom: Double = 1, parked: Bool = false) {
        var normalizedSize = size
        normalizedSize.scale = min(max(normalizedSize.scale, 1), 3)
        if case .ticket = kind { normalizedSize.shape = .medium }
        else if !kind.allowedShapes.contains(normalizedSize.shape) {
            normalizedSize.shape = normalizedSize.shape == .mini && kind.allowedShapes.contains(.strip)
                ? .strip : .small
        }
        self.id = id
        if case .map(.japan(let area)) = kind {
            self.kind = .map(.japan(ShareComposerModel.islandArea(area) ?? .honshu))
        } else { self.kind = kind }
        self.size = normalizedSize
        self.mapZoom = min(max(mapZoom, 0.75), 2)
        self.parked = parked
    }
}

enum ShareLayout {
    struct Result {
        var placements: [UUID: GridRect]
        var overflow: [UUID]
        var occupied: GridRect?
    }

    static func pack(_ cards: [ShareCard], columns: Int, rows: Int) -> Result {
        let ordered = packInOrder(cards, columns: columns, rows: rows)
        guard !ordered.overflow.isEmpty, cards.contains(where: { $0.size.shape.isCompact }) else {
            return ordered
        }
        // Early fillers can fragment the space needed by a ticket. Keep the
        // user's order whenever it fits; only try larger modules first when
        // doing so actually reduces overflow. Both groups keep stable order.
        let modules = cards.filter { !$0.size.shape.isCompact }
        let fillers = cards.filter { $0.size.shape.isCompact }
        let filled = packInOrder(modules + fillers, columns: columns, rows: rows)
        return filled.overflow.count < ordered.overflow.count ? filled : ordered
    }

    private static func packInOrder(_ cards: [ShareCard], columns: Int, rows: Int) -> Result {
        var occupiedCells = Set<Int>()
        var placements: [UUID: GridRect] = [:]
        var overflow: [UUID] = []
        for card in cards {
            guard !card.parked else { continue }
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
        // Generated exhaustively by ios/tools/search-share-presets.py.
        let specs: [(ShareCard.Kind, CardSize)]
        switch self {
        case .japanIslands:
            switch ratio {
            case .square:
                specs = [
                    (.map(.japan(.hokkaido)), .init(shape: .medium)),
                    (.map(.japan(.honshu)), .init(shape: .medium)),
                    (.map(.japan(.kyushu)), .init(shape: .medium)),
                    (.map(.japan(.okinawa)), .init(shape: .medium)),
                    (.map(.japan(.shikoku)), .init(shape: .medium)),
                    (.ticket, .init(shape: .medium)),
                ]
            case .landscape:
                specs = [
                    (.map(.japan(.hokkaido)), .init(shape: .medium)),
                    (.map(.japan(.honshu)), .init(shape: .medium)),
                    (.map(.japan(.kyushu)), .init(shape: .small)),
                    (.map(.japan(.okinawa)), .init(shape: .small)),
                    (.ticket, .init(shape: .medium, scale: 2)),
                    (.map(.japan(.shikoku)), .init(shape: .small)),
                ]
            case .portrait:
                specs = [
                    (.map(.japan(.hokkaido)), .init(shape: .medium)),
                    (.map(.japan(.honshu)), .init(shape: .medium)),
                    (.map(.japan(.kyushu)), .init(shape: .small)),
                    (.map(.japan(.okinawa)), .init(shape: .small)),
                    (.map(.japan(.shikoku)), .init(shape: .small)),
                    (.ticket, .init(shape: .medium, scale: 2)),
                ]
            case .wide:
                specs = [
                    (.map(.japan(.hokkaido)), .init(shape: .large)),
                    (.map(.japan(.kyushu)), .init(shape: .large)),
                    (.map(.japan(.honshu)), .init(shape: .medium, scale: 2)),
                    (.ticket, .init(shape: .medium, scale: 2)),
                    (.map(.japan(.okinawa)), .init(shape: .large)),
                    (.map(.japan(.shikoku)), .init(shape: .large)),
                ]
            case .tall:
                specs = [
                    (.map(.japan(.hokkaido)), .init(shape: .large)),
                    (.map(.japan(.honshu)), .init(shape: .small, scale: 2)),
                    (.map(.japan(.kyushu)), .init(shape: .large)),
                    (.map(.japan(.okinawa)), .init(shape: .small)),
                    (.map(.japan(.shikoku)), .init(shape: .small)),
                    (.ticket, .init(shape: .medium, scale: 2)),
                ]
            }
        case .taiwan, .hongKong, .macau:
            let region: Region = self == .taiwan ? .tw : self == .hongKong ? .hk : .mo
            let mapShape: CardShape
            let mapScale: Int
            let ticketScale: Int
            switch ratio {
            case .square:
                mapShape = .medium; mapScale = 1; ticketScale = 2
            case .landscape:
                mapShape = self == .hongKong ? .medium : .tall
                mapScale = 1; ticketScale = 2
            case .portrait:
                mapShape = .medium; mapScale = 2; ticketScale = 2
            case .wide:
                mapShape = .large; mapScale = 1; ticketScale = 3
            case .tall:
                mapShape = .small; mapScale = 3; ticketScale = 2
            }
            specs = [
                (.map(.region(region)), .init(shape: mapShape, scale: mapScale)),
                (.ticket, .init(shape: .medium, scale: ticketScale)),
            ]
        }
        return specs.map { ShareCard(kind: $0.0, size: $0.1) }
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

/// Scope identity comes from the same validated resource owner as routing.
/// An unavailable attestation is visible and blocks export, never a cache identity.
enum ShareResourceRevision {
    private static var revisions: Result<RailResourceRevisions, Error> {
        Result { try RailResourceRevisions.bundled() }
    }

    static func failureMessage(for countries: [String]) -> String? {
        guard !countries.isEmpty else { return nil }
        do {
            _ = try revisions.get().requiredRevision(for: countries.joined(separator: "+"))
            return nil
        } catch { return error.localizedDescription }
    }

    static func token(for countries: [String]) -> String {
        guard !countries.isEmpty else { return "" }
        do {
            return try revisions.get().requiredRevision(for: countries.joined(separator: "+"))
        } catch {
            return "unavailable"
        }
    }
}

/// One statistics computation shared by every card of the same scope.
struct ShareScopeComputation: Identifiable {
    var identity: String
    var scope: StatisticsScope
    var statistics: MileageStatisticsStore
    var cardIDs: [UUID]
    var id: String { identity }
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
    /// Inherited scope overrides, keyed by scope, page dates and resource revision.
    private var sharedStatistics: [String: MileageStatisticsStore] = [:]
    /// Cards the reader dated independently. These never share a store.
    private var customStatistics: [UUID: MileageStatisticsStore] = [:]
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
            baseArea = Self.islandArea(base.area)
        } else {
            baseRegion = region
            baseArea = Self.islandArea(area)
        }
        ratio = debug.ratio ?? .portrait
        size = debug.size ?? .medium
        self.colorScheme = debug.colorScheme ?? colorScheme
#else
        baseRegion = region
        baseArea = Self.islandArea(area)
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
            let mapArea = Self.islandArea(area).map(ShareMapArea.japan) ?? .region(region ?? .jp)
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
        let placements = layout.placements
        let maps = cards.compactMap { card -> StatisticsScope? in
            if placements[card.id] != nil, case .map(let area) = card.kind { return area.scope }
            return nil
        }
        let mapScope = maps.dropFirst().reduce(maps.first ?? .everything) { $0.union($1) }
        return mapScope.intersection(baseScope)
    }
    func scopeDisplayName(_ localization: AppLocalization) -> String {
        scopeDisplayName(effectiveScope, localization: localization)
    }

    func scopeDisplayName(_ scope: StatisticsScope, localization: AppLocalization) -> String {
        if scope.regions == Set(Region.enabledOrdered) && scope.japanLeaves == nil {
            return localization.text("ios.region.all", fallback: "All regions")
        }
        var names: [String] = []
        if scope.regions.contains(.jp) {
            names.append(contentsOf: japanScopeDisplayNames(
                scope.japanLeaves, localization: localization))
        }
        names.append(contentsOf: Region.enabledOrdered.filter {
            $0 != .jp && scope.regions.contains($0)
        }.map {
            localization.text($0.localizationKey, fallback: $0.fallbackName)
        })
        return names.isEmpty
            ? localization.text("ios.stats.shareNoData")
            : names.joined(separator: "・")
    }

    private func japanScopeDisplayNames(
        _ leaves: Set<JapanAreaLeaf>?, localization: AppLocalization
    ) -> [String] {
        let countryName = localization.text(
            Region.jp.localizationKey, fallback: Region.jp.fallbackName)
        guard let leaves, leaves != Set(JapanAreaLeaf.allCases) else { return [countryName] }
        let localized: (StatisticsArea) -> String = { area in
            localization.text(area.localizationKey, fallback: area.fallbackName)
        }
        let honshuLeaves = StatisticsArea.honshu.leaves
        if honshuLeaves.isSubset(of: leaves) {
            return [StatisticsArea.honshu, .hokkaido, .shikoku, .kyushu, .okinawa]
                .filter { $0 == .honshu || !$0.leaves.isDisjoint(with: leaves) }
                .map(localized)
        }
        return StatisticsArea.islands
            .filter { !$0.leaves.isDisjoint(with: leaves) }
            .map(localized)
    }

    nonisolated static func islandArea(_ area: StatisticsArea?) -> StatisticsArea? {
        guard let area else { return nil }
        return StatisticsArea.honshuAreas.contains(area) ? .honshu : area
    }

    func scope(for card: ShareCard) -> StatisticsScope {
        (cards.first { $0.id == card.id } ?? card).scopeOverride?.scope ?? effectiveScope
    }

    var hasScopedContent: Bool {
        let placements = layout.placements
        return cards.contains { placements[$0.id] != nil && !scope(for: $0).isEmpty }
    }

    func statistics(for card: ShareCard) -> MileageStatisticsStore {
        // Callers often hold a copy from before a date or scope edit. The
        // store follows the card the model still has, looked up by id.
        let live = cards.first { $0.id == card.id } ?? card
        if live.usesCustomDates, let store = customStatistics[live.id] { return store }
        if live.scopeOverride != nil,
           let store = sharedStatistics[inheritedStoreKey(scope: scope(for: live))] {
            return store
        }
        return statistics
    }

    /// The page computation plus one entry for each distinct placed override.
    /// Identical region, date, group, resource revision and itinerary generation
    /// share one store. Custom-dated cards stay separate.
    func scopeComputations(itineraryGeneration: Int, placedIDs: Set<UUID>) -> [ShareScopeComputation] {
        var pageCardIDs: [UUID] = []
        var extras: [ShareScopeComputation] = []
        var inherited: [String: ShareScopeComputation] = [:]
        for card in cards where placedIDs.contains(card.id) {
            if card.usesCustomDates, let store = customStatistics[card.id] {
                let scope = scope(for: card)
                extras.append(ShareScopeComputation(
                    identity: Self.computationIdentity(
                        scope: scope, selection: store, generation: itineraryGeneration,
                        distinction: "dates:\(card.id.uuidString)"),
                    scope: scope, statistics: store, cardIDs: [card.id]))
            } else if card.scopeOverride != nil {
                let scope = scope(for: card)
                let storeKey = inheritedStoreKey(scope: scope)
                guard let store = sharedStatistics[storeKey] else { continue }
                if var existing = inherited[storeKey] {
                    existing.cardIDs.append(card.id)
                    inherited[storeKey] = existing
                } else {
                    inherited[storeKey] = ShareScopeComputation(
                        identity: Self.computationIdentity(
                            scope: scope, selection: statistics, generation: itineraryGeneration,
                            distinction: "scope"),
                        scope: scope, statistics: store, cardIDs: [card.id])
                }
            } else {
                pageCardIDs.append(card.id)
            }
        }
        let page = ShareScopeComputation(
            identity: Self.computationIdentity(
                scope: effectiveScope, selection: statistics, generation: itineraryGeneration,
                distinction: "page"),
            scope: effectiveScope, statistics: statistics, cardIDs: pageCardIDs)
        return ([page] + inherited.values + extras).sorted { $0.identity < $1.identity }
    }

    static func dateKey(_ store: MileageStatisticsStore) -> String {
        "\(store.selectedYear.map(String.init) ?? "*")|\(store.selectedJourneyGroupID ?? "*")|\(store.dateSelection)"
    }

    func setScope(_ scope: ShareMapArea?, for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].scopeOverride = scope.map {
            if case .japan(let area) = $0 { return .japan(Self.islandArea(area) ?? .honshu) }
            return $0
        }
        prepareCardStatistics()
    }

    func customizeDates(for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        if !cards[index].usesCustomDates {
            let store = MileageStatisticsStore()
            store.adoptSelection(from: statistics(for: cards[index]))
            store.removeYearRestriction()
            customStatistics[id] = store
            cards[index].usesCustomDates = true
        }
        prepareCardStatistics()
    }

    func inheritDates(for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].usesCustomDates = false
        customStatistics[id]?.cancelAll()
        customStatistics.removeValue(forKey: id)
        prepareCardStatistics()
    }

    func prepareCardStatistics() {
        let activeIDs = Set(cards.map(\.id))
        for (id, store) in customStatistics where !activeIDs.contains(id) { store.cancelAll() }
        customStatistics = customStatistics.filter { activeIDs.contains($0.key) }

        var needed: [String: StatisticsScope] = [:]
        for card in cards where activeIDs.contains(card.id) {
            if card.usesCustomDates {
                if customStatistics[card.id] == nil {
                    let store = MileageStatisticsStore()
                    store.adoptSelection(from: statistics)
                    store.removeYearRestriction()
                    customStatistics[card.id] = store
                }
                continue
            }
            guard card.scopeOverride != nil else { continue }
            let scope = scope(for: card)
            needed[inheritedStoreKey(scope: scope)] = scope
        }
        for (key, store) in sharedStatistics where needed[key] == nil { store.cancelAll() }
        for (key, _) in needed where sharedStatistics[key] == nil {
            let store = MileageStatisticsStore()
            store.adoptSelection(from: statistics)
            sharedStatistics[key] = store
        }
        sharedStatistics = sharedStatistics.filter { needed[$0.key] != nil }
    }

    func cancelStatistics() {
        statistics.cancelAll()
        for store in sharedStatistics.values { store.cancelAll() }
        for store in customStatistics.values { store.cancelAll() }
    }

    private func inheritedStoreKey(scope: StatisticsScope) -> String {
        let revision = ShareResourceRevision.token(for: scope.countries)
        return "scope:\(scope.key)|\(Self.dateKey(statistics))|\(revision)"
    }

    private static func computationIdentity(
        scope: StatisticsScope, selection: MileageStatisticsStore,
        generation: Int, distinction: String
    ) -> String {
        let revision = ShareResourceRevision.token(for: scope.countries)
        return "\(distinction)|\(scope.key)|\(dateKey(selection))|\(revision)|\(generation)"
    }

    func allowedScales(for card: ShareCard) -> ClosedRange<Int> {
        let shape = card.kind == .ticket ? CardShape.medium : card.size.shape
        let base = shape.baseSpan
        let maximum = min(3, min(grid.columns / base.columns, grid.rows / base.rows))
        return 1...max(1, maximum)
    }

    func apply(_ preset: ShareLayoutPreset) {
        appliedPreset = preset
        cards = preset.cards(for: ratio)
        selectedCardID = cards.first?.id
    }
    func add(_ kind: ShareCard.Kind, shape: CardShape? = nil) {
        var cardSize: CardSize
        switch kind {
        case .ticket:
            cardSize = allowedTicketDefault()
        case .map:
            cardSize = CardSize(shape: .small)
        case .stat(let statisticsKind):
            cardSize = CardSize(shape: statisticsKind.preferredWidgetShape)
        }
        if let shape, kind.allowedShapes.contains(shape) { cardSize = CardSize(shape: shape) }
        let card = ShareCard(kind: kind, size: cardSize)
        cards.append(card)
        selectedCardID = card.id
        appliedPreset = nil
    }
    func remove(_ id: UUID) {
        cards.removeAll { $0.id == id }
        if selectedCardID == id { selectedCardID = cards.first?.id }
        appliedPreset = nil
        prepareCardStatistics()
    }
    func move(_ id: UUID, to index: Int) {
        guard let from = cards.firstIndex(where: { $0.id == id }) else { return }
        let destination = from < index ? index - 1 : index
        let card = cards.remove(at: from)
        cards.insert(card, at: min(max(destination, 0), cards.count))
        appliedPreset = nil
    }
    func reorder(_ ids: [UUID]) {
        guard ids.count == cards.count, Set(ids).count == ids.count,
              Set(ids) == Set(cards.map(\.id)) else { return }
        let byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        cards = ids.compactMap { byID[$0] }
        appliedPreset = nil
    }
    func setParked(_ parked: Bool, for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }),
              cards[index].parked != parked else { return }
        cards[index].parked = parked
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
    func setScale(_ scale: Int, for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let allowed = allowedScales(for: cards[index])
        cards[index].size.scale = min(max(scale, allowed.lowerBound), allowed.upperBound)
        appliedPreset = nil
    }
    func stepSize(_ id: UUID, by delta: Int) {
        guard let card = cards.first(where: { $0.id == id }) else { return }
        setScale(card.size.scale + delta, for: id)
    }
    func setShape(_ shape: CardShape, for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        guard case .map = cards[index].kind else {
            guard case .stat = cards[index].kind else { return }
            return setNonTicketShape(shape, at: index)
        }
        setNonTicketShape(shape, at: index)
    }
    private func setNonTicketShape(_ shape: CardShape, at index: Int) {
        guard cards[index].kind.allowedShapes.contains(shape) else { return }
        cards[index].size.shape = shape
        let maximum = allowedScales(for: cards[index]).upperBound
        cards[index].size.scale = min(cards[index].size.scale, maximum)
        appliedPreset = nil
    }
    func setZoom(_ zoom: Double, for id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), case .map = cards[index].kind else { return }
        cards[index].mapZoom = min(max(zoom, 0.75), 2)
    }

    private func ratioChanged() {
        for index in cards.indices {
            let maximum = allowedScales(for: cards[index]).upperBound
            cards[index].size.scale = min(cards[index].size.scale, maximum)
        }
        appliedPreset = nil
    }
    private func allowedTicketDefault() -> CardSize {
        let desired = CardSize(shape: .medium, scale: 2)
        let probe = ShareCard(kind: .ticket, size: desired)
        return CardSize(shape: .medium, scale: min(2, allowedScales(for: probe).upperBound))
    }
    private static func singleRegionCards(area: ShareMapArea, ratio: ShareCanvasRatio) -> [ShareCard] {
        let source = ShareLayoutPreset.taiwan.cards(for: ratio)
        return source.map { card in
            guard case .map = card.kind else { return card }
            return ShareCard(kind: .map(area), size: card.size)
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
            let launch = UITestLaunchConfiguration(environment: environment)
            preset = launch[.sharePreset].flatMap(ShareLayoutPreset.init)
            ratio = launch[.shareRatio].flatMap(ShareCanvasRatio.init)
            switch launch[.shareScheme] {
            case "light": colorScheme = .light
            case "dark": colorScheme = .dark
            default: colorScheme = nil
            }
            size = launch[.shareSize].flatMap(ShareCanvasSize.init)
            base = Self.parseBase(launch[.shareBase])
            cards = launch[.shareCards]
            if let directory = launch[.shareExportDir],
               !directory.isEmpty {
                let name = launch[.shareName].flatMap {
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
                guard parts.count == 2 else { return nil }
                if let scale = Self.parseDebugScale(parts[1]) {
                    return debugCard(kind: .ticket, requestedSize: .init(shape: .medium, scale: scale))
                }
                guard let span = Self.parseDebugSpan(parts[1]) else { return nil }
                return debugCard(kind: .ticket, legacySpan: span)
            case "stat":
                guard let stat = parts.indices.contains(1)
                    ? StatisticsCardKind(rawValue: parts[1]) : nil else { return nil }
                if parts.count == 4, let shape = CardShape(rawValue: parts[2]),
                   let scale = Self.parseDebugScale(parts[3]) {
                    return debugCard(kind: .stat(stat), requestedSize: .init(shape: shape, scale: scale))
                }
                guard parts.count == 3, let span = Self.parseDebugSpan(parts[2]) else { return nil }
                return debugCard(kind: .stat(stat), legacySpan: span)
            case "map":
                guard parts.count >= 3, let region = Region(rawValue: parts[1]) else { return nil }
                var sizeIndex = 2
                let area: ShareMapArea
                if region == .jp, CardShape(rawValue: parts[sizeIndex]) == nil,
                   Self.parseDebugSpan(parts[sizeIndex]) == nil {
                    guard let japanArea = StatisticsArea(rawValue: parts[sizeIndex]) else { return nil }
                    area = .japan(japanArea)
                    sizeIndex += 1
                } else {
                    area = .region(region)
                }
                guard parts.indices.contains(sizeIndex) else { return nil }
                if let shape = CardShape(rawValue: parts[sizeIndex]) {
                    guard parts.indices.contains(sizeIndex + 1),
                          let scale = Self.parseDebugScale(parts[sizeIndex + 1]),
                          parts.count <= sizeIndex + 3 else { return nil }
                    let zoom = parts.indices.contains(sizeIndex + 2)
                        ? Double(parts[sizeIndex + 2]) ?? 1 : 1
                    return debugCard(kind: .map(area),
                                     requestedSize: .init(shape: shape, scale: scale),
                                     mapZoom: zoom)
                }
                guard let span = Self.parseDebugSpan(parts[sizeIndex]),
                      parts.count <= sizeIndex + 2 else { return nil }
                let zoom = parts.indices.contains(sizeIndex + 1)
                    ? Double(parts[sizeIndex + 1]) ?? 1 : 1
                return debugCard(kind: .map(area), legacySpan: span, mapZoom: zoom)
            default:
                return nil
            }
        }
        return parsed
    }

    private func debugCard(
        kind: ShareCard.Kind,
        requestedSize: CardSize,
        mapZoom: Double = 1
    ) -> ShareCard {
        var size = requestedSize
        if case .ticket = kind { size.shape = .medium }
        var card = ShareCard(kind: kind, size: size, mapZoom: mapZoom)
        card.size.scale = min(card.size.scale, allowedScales(for: card).upperBound)
        return card
    }

    private func debugCard(
        kind: ShareCard.Kind,
        legacySpan: GridSpan,
        mapZoom: Double = 1
    ) -> ShareCard {
        let shapes: [CardShape]
        shapes = kind.allowedShapes
        let candidates = shapes.flatMap { shape in
            (1...3).map { CardSize(shape: shape, scale: $0) }
        }.filter {
            $0.span.columns <= grid.columns && $0.span.rows <= grid.rows
        }
        let nearest = candidates.min {
            let lhs = abs($0.span.columns - legacySpan.columns)
                + abs($0.span.rows - legacySpan.rows)
            let rhs = abs($1.span.columns - legacySpan.columns)
                + abs($1.span.rows - legacySpan.rows)
            if lhs != rhs { return lhs < rhs }
            return abs($0.span.columns * $0.span.rows - legacySpan.columns * legacySpan.rows)
                < abs($1.span.columns * $1.span.rows - legacySpan.columns * legacySpan.rows)
        } ?? CardSize(shape: .medium)
        return ShareCard(kind: kind, size: nearest, mapZoom: mapZoom)
    }

    private static func parseDebugScale(_ encoded: String) -> Int? {
        guard let scale = Int(encoded), (1...3).contains(scale) else { return nil }
        return scale
    }

    private static func parseDebugSpan(_ encoded: String) -> GridSpan? {
        let values = encoded.lowercased().split(separator: "x")
        guard values.count == 2, let columns = Int(values[0]), let rows = Int(values[1]),
              columns > 0, rows > 0 else { return nil }
        return GridSpan(columns: columns, rows: rows)
    }
#endif
}
