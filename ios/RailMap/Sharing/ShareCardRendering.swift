import MapKit
import Observation
import RailCore
import RailPresentation
import SwiftUI
import UIKit

enum ShareCanvasGeometry {
    @MainActor
    static func frames(model: ShareComposerModel, canvasSize: CGSize) -> [UUID: CGRect] {
        let result = model.layout
        guard let occupied = result.occupied else { return [:] }
        let short = min(canvasSize.width, canvasSize.height)
        let outer = short * 0.04
        let gap = short * 0.015
        let grid = model.grid
        let availableWidth = canvasSize.width - outer * 2 - gap * CGFloat(grid.columns - 1)
        let availableHeight = canvasSize.height - outer * 2 - gap * CGFloat(grid.rows - 1)
        let cell = min(availableWidth / CGFloat(grid.columns),
                       availableHeight / CGFloat(grid.rows))
        let blockWidth = CGFloat(occupied.columns) * cell + CGFloat(occupied.columns - 1) * gap
        let blockHeight = CGFloat(occupied.rows) * cell + CGFloat(occupied.rows - 1) * gap
        let originX = (canvasSize.width - blockWidth) / 2
        let originY = (canvasSize.height - blockHeight) / 2
        let cardsByID = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
        return result.placements.reduce(into: [:]) { frames, entry in
            let (id, placement) = entry
            let column = placement.column - occupied.column
            let row = placement.row - occupied.row
            var frame = CGRect(
                x: originX + CGFloat(column) * (cell + gap),
                y: originY + CGFloat(row) * (cell + gap),
                width: CGFloat(placement.columns) * cell + CGFloat(placement.columns - 1) * gap,
                height: CGFloat(placement.rows) * cell + CGFloat(placement.rows - 1) * gap)
            if let card = cardsByID[id], case .ticket = card.kind {
                let exactHeight = frame.width / TicketFace.aspect
                frame = CGRect(x: frame.minX, y: frame.midY - exactHeight / 2,
                               width: frame.width, height: exactHeight)
            }
            frames[id] = frame
        }
    }
}

/// One placed card, already scoped. The renderer draws this list and does not
/// walk the itinerary again to decide which journeys belong on the card.
struct ShareRenderedCard: Identifiable {
    var cardID: UUID
    var scope: StatisticsScope
    var scopeName: String
    var statistics: MileageStatisticsStore
    var trains: [Train]
    var id: UUID { cardID }
}

/// Renders cards independently so the composer can remain interactive.
@MainActor @Observable
final class ShareCardRenderController {
    private(set) var images: [UUID: UIImage] = [:]
    private(set) var isRendering = false
    private(set) var renderFailed = false
    private(set) var completedKey: String?
#if DEBUG
    private(set) var debugExportedKey: String?
#endif
    private var generation = 0
    private var cache: [String: UIImage] = [:]
    private var cacheScope: String?
    // Tasks retain the buffer reference, so invalidation can release partial
    // pixels immediately while a noncooperative snapshot is still suspended.
    // Separate operation IDs keep preview/export cleanup independent.
    private final class RenderBuffer {
        var images: [UUID: UIImage] = [:]
    }
    private var renderingBuffers: [UUID: RenderBuffer] = [:]
    private struct ExportWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var exportOwner: UUID?
    private var exportWaiters: [ExportWaiter] = []

    // Keep the permit until the entire writer returns, even if cancellation
    // releases partial card buffers while a noncooperative write is pending.
    private func admitExport(_ operation: UUID) async -> Bool {
        guard !Task.isCancelled else { return false }
        if exportOwner == nil {
            exportOwner = operation
            return true
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                exportWaiters.append(ExportWaiter(id: operation, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelWaitingExport(operation) }
        }
    }

    private func cancelWaitingExport(_ operation: UUID) {
        guard let index = exportWaiters.firstIndex(where: { $0.id == operation }) else { return }
        exportWaiters.remove(at: index).continuation.resume(returning: false)
    }

    private func discardWaitingExports() {
        let waiting = exportWaiters
        exportWaiters.removeAll()
        for waiter in waiting { waiter.continuation.resume(returning: false) }
    }

    private func releaseExport(_ operation: UUID) {
        precondition(exportOwner == operation)
        exportOwner = nil
        guard !exportWaiters.isEmpty else { return }
        let next = exportWaiters.removeFirst()
        exportOwner = next.id
        next.continuation.resume(returning: true)
    }

    private func discardRenderingBuffers() {
        for buffer in renderingBuffers.values { buffer.images.removeAll() }
        renderingBuffers.removeAll()
    }

    func cancel() {
        generation += 1
        discardWaitingExports()
        discardRenderingBuffers()
        isRendering = false
        renderFailed = false
        images.removeAll()
        cache.removeAll()
        cacheScope = nil
        completedKey = nil
#if DEBUG
        debugExportedKey = nil
#endif
    }

    func discardPreview() { images.removeAll() }

    func render(
        model: ShareComposerModel,
        itineraries: ItineraryStore,
        rides: [RiddenRouteStore.DrawnRide],
        prepared: [ShareRenderedCard],
        localization: AppLocalization,
        key: String,
        canvasSize: CGSize
    ) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let request = generation
        discardWaitingExports()
        discardRenderingBuffers()
        completedKey = nil
#if DEBUG
        debugExportedKey = nil
#endif
        if cacheScope != key {
            // Keep the last complete preview while replacement pixels are prepared.
            // Canvas and drag snapshots read this same owner.
            cache.removeAll()
            cacheScope = key
        }
        isRendering = true
        renderFailed = false
        defer { if generation == request { isRendering = false } }
        let operation = UUID()
        let buffer = RenderBuffer()
        renderingBuffers[operation] = buffer
        defer {
            buffer.images.removeAll()
            renderingBuffers.removeValue(forKey: operation)
        }
        guard await renderCards(
            model: model, itineraries: itineraries, rides: rides, prepared: prepared,
            localization: localization, key: key, canvasSize: canvasSize, request: request, useCache: true, buffer: buffer)
        else {
            if generation == request, !Task.isCancelled { renderFailed = true }
            return
        }
        guard generation == request, !Task.isCancelled else { return }
        images = buffer.images
        completedKey = key
    }

    private func renderCards(
        model: ShareComposerModel,
        itineraries: ItineraryStore,
        rides: [RiddenRouteStore.DrawnRide],
        prepared: [ShareRenderedCard],
        localization: AppLocalization,
        key: String,
        canvasSize: CGSize,
        request: Int,
        useCache: Bool,
        buffer: RenderBuffer
    ) async -> Bool {
        let frames = ShareCanvasGeometry.frames(model: model, canvasSize: canvasSize)
        let placedIDs = Set(model.layout.placements.keys)
        guard Set(prepared.map(\.cardID)) == placedIDs else { return false }
        let cardsByID = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
        for item in prepared {
            guard generation == request, !Task.isCancelled else { return false }
            guard let card = cardsByID[item.cardID], model.layout.placements[card.id] != nil else {
                return false
            }
            guard let frame = frames[card.id], frame.width > 0, frame.height > 0 else { return false }
            let statistics = item.statistics
            let scope = item.scope
            let scopeName = item.scopeName
            let scopedTrains = item.trains
            let cacheKey = "\(key)|\(scope.key)|\(ShareComposerModel.dateKey(statistics))|\(card.kind)|\(card.size.shape.rawValue)|\(card.span.columns)x\(card.span.rows)|\(card.mapZoom)|\(model.ratio.rawValue)|\(model.colorScheme)"
            if useCache, let cached = cache[cacheKey] {
                buffer.images[card.id] = cached
                continue
            }
            let image: UIImage?
            switch card.kind {
            case .ticket:
                image = renderRecordTicket(
                    model: model, statistics: statistics, scopeName: scopeName, itineraries: itineraries,
                    trains: scopedTrains, localization: localization, target: frame.size)
            case .stat(let kind):
                if kind == .recordTicket {
                    image = renderRecordTicket(
                        model: model, statistics: statistics, scopeName: scopeName, itineraries: itineraries,
                        trains: scopedTrains, localization: localization, target: frame.size)
                } else {
                    image = renderDashboardCard(
                        kind, shape: CardShape.matching(
                            card.span, preferred: card.size.shape),
                        model: model, statistics: statistics, scopeName: scopeName,
                        trains: scopedTrains, localization: localization, target: frame.size)
                }
            case .map(let area):
                let areaIDs = Set(area.scope.filter(scopedTrains, rides: rides).map(\.id))
                image = await StatisticsMapSnapshot.render(
                    rides: rides.filter { areaIDs.contains($0.id) }, fallback: area.mapExtent,
                    colorScheme: model.colorScheme,
                    size: CGSize(width: max(frame.width, 64), height: max(frame.height, 64)),
                    zoom: card.mapZoom, name: area.localizedName(localization))
            }
            guard generation == request, !Task.isCancelled else { return false }
            // A successful render means every placed card exists. Otherwise
            // the export would silently omit a card still shown as a skeleton.
            guard let image else { return false }
            if useCache { cache[cacheKey] = image }
            buffer.images[card.id] = image
        }
        return generation == request && !Task.isCancelled
    }

    func export(
        model: ShareComposerModel,
        itineraries: ItineraryStore,
        rides: [RiddenRouteStore.DrawnRide],
        prepared: [ShareRenderedCard],
        localization: AppLocalization,
        key: String,
        to destination: URL? = nil
    ) async -> StatisticsShareFile? {
        guard !isRendering, !Task.isCancelled, completedKey == key else { return nil }
        let request = generation
        let operation = UUID()
        guard await admitExport(operation) else { return nil }
        defer { releaseExport(operation) }
        guard generation == request, !isRendering, !Task.isCancelled,
              completedKey == key else { return nil }
        let size = model.size.pixelSize(for: model.ratio)
        let buffer = RenderBuffer()
        renderingBuffers[operation] = buffer
        defer {
            buffer.images.removeAll()
            renderingBuffers.removeValue(forKey: operation)
        }
        guard await renderCards(
            model: model, itineraries: itineraries, rides: rides, prepared: prepared,
            localization: localization, key: key, canvasSize: size, request: request, useCache: false, buffer: buffer)
        else { return nil }
        guard generation == request, !Task.isCancelled else { return nil }
        let frames = ShareCanvasGeometry.frames(model: model, canvasSize: size)
        let placed = model.cards.filter { model.layout.placements[$0.id] != nil }
        var placedImages: [(ShareCard, CGRect, UIImage)] = []
        placedImages.reserveCapacity(placed.count)
        for card in placed {
            guard let frame = frames[card.id], frame.width > 0, frame.height > 0,
                  let image = buffer.images[card.id] else { return nil }
            placedImages.append((card, frame, image))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: model.colorScheme == .dark ? .dark : .light),
            UITraitCollection(userInterfaceLevel: .elevated),
        ])
        let background = UIColor.systemBackground.resolvedColor(with: traits)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (card, frame, image) in placedImages {
                context.cgContext.saveGState()
                if case .ticket = card.kind {} else {
                    UIBezierPath(roundedRect: frame, cornerRadius:
                        ShareCanvasGeometry.cornerRadius(card: card, frame: frame)).addClip()
                }
                let scale = min(frame.width / image.size.width, frame.height / image.size.height)
                let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let drawRect = CGRect(x: frame.midX - drawSize.width / 2,
                                      y: frame.midY - drawSize.height / 2,
                                      width: drawSize.width, height: drawSize.height)
                image.draw(in: drawRect)
                context.cgContext.restoreGState()
            }
        }
        buffer.images.removeAll()
        let file = await SharePNGWriter.write(image, to: destination)
        guard generation == request, !Task.isCancelled else { return nil }
        return file
    }

#if DEBUG
    func writeDebugExport(
        model: ShareComposerModel, itineraries: ItineraryStore,
        rides: [RiddenRouteStore.DrawnRide], prepared: [ShareRenderedCard],
        localization: AppLocalization,
        to url: URL, key: String
    ) async {
        let request = generation
        guard completedKey == key,
              await export(
                model: model, itineraries: itineraries, rides: rides, prepared: prepared,
                localization: localization, key: key, to: url) != nil
        else { return }
        guard generation == request, completedKey == key, !Task.isCancelled else { return }
        debugExportedKey = key
    }
#endif

    private func renderRecordTicket(
        model: ShareComposerModel,
        statistics: MileageStatisticsStore, scopeName: String,
        itineraries: ItineraryStore, trains: [Train],
        localization: AppLocalization, target: CGSize
    ) -> UIImage? {
        guard let content = statistics.recordTicketContent(trains: trains, localization: localization) else { return nil }
        let scope = StatisticsFormat.ticketScope(
            trains: itineraries.store?.trains ?? itineraries.loaded?.trains ?? [],
            groupID: statistics.selectedJourneyGroupID, scopeName: scopeName,
            region: nil, localization: localization)
        let face = TicketFaceCard(
            kind: localization.text("ios.ticket.kind.history"), scope: scope,
            displays: content.displays, fields: content.fields, span: content.span,
            issued: StatisticsFormat.ticketIssued(localization: localization))
            .passportCard(.feature)
            .frame(width: TicketFace.width, height: TicketFace.height)
            .environment(localization)
            .environment(\.colorScheme, model.colorScheme)
            .environment(\.passportPoster, true)
        let widthScale = target.width / TicketFace.width
        return renderTransparentCard(face, scale: min(max(widthScale, 1), 4))
    }

    private func renderDashboardCard(
        _ kind: StatisticsCardKind, shape: CardShape,
        model: ShareComposerModel,
        statistics: MileageStatisticsStore, scopeName: String, trains: [Train],
        localization: AppLocalization, target: CGSize
    ) -> UIImage? {
        guard let data = statistics.widgetData(
            kind, trains: trains, scopeName: scopeName, localization: localization) else { return nil }
        let face = StatsWidgetView(kind: kind, shape: shape, data: data)
            .frame(width: shape.designSize.width, height: shape.designSize.height)
            .environment(localization)
            .environment(\.colorScheme, model.colorScheme)
            .environment(\.passportPoster, true)
        let fitScale = min(target.width / shape.designSize.width,
                           target.height / shape.designSize.height)
        let budgetScale = sqrt(16_000_000 / max(
            shape.designSize.width * shape.designSize.height, 1))
        let maximumScale: CGFloat = shape.isCompact ? budgetScale : 4
        return renderTransparentCard(face, scale: min(max(fitScale, 1), budgetScale, maximumScale))
    }

    private func renderTransparentCard<Content: View>(_ content: Content, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: content)
        // Preserve rounded stock and widget surfaces; opaque rendering turns
        // their transparent corner pixels black before preview/export clipping.
        renderer.isOpaque = false
        renderer.scale = scale
        return renderer.uiImage
    }
}

private enum SharePNGWriter {
    private static let sessionStarted = Date()

    static func write(_ image: UIImage, to destination: URL? = nil) async -> StatisticsShareFile? {
        let url = destination ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("rail-statistics-\(UUID().uuidString).png")
        guard let data = image.pngData() else { return nil }
        let retirementDate = sessionStarted
        let written = await Task.detached(priority: .userInitiated) {
            let directory = FileManager.default.temporaryDirectory
            if let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for file in files where file.lastPathComponent.hasPrefix("rail-statistics")
                    && file.pathExtension == "png" {
                    guard let date = try? file.resourceValues(
                        forKeys: [.contentModificationDateKey]).contentModificationDate,
                          date < retirementDate else { continue }
                    try? FileManager.default.removeItem(at: file)
                }
            }
            do {
                if destination != nil {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                }
                try data.write(to: url, options: .atomic)
                return true
            } catch { return false }
        }.value
        return written ? StatisticsShareFile(url: url, image: image) : nil
    }

}
