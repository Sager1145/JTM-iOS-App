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
        let cellWidth = availableWidth / CGFloat(grid.columns)
        let cellHeight = availableHeight / CGFloat(grid.rows)
        let blockWidth = CGFloat(occupied.columns) * cellWidth + CGFloat(occupied.columns - 1) * gap
        let blockHeight = CGFloat(occupied.rows) * cellHeight + CGFloat(occupied.rows - 1) * gap
        let originX = (canvasSize.width - blockWidth) / 2
        let originY = (canvasSize.height - blockHeight) / 2
        return result.placements.mapValues { placement in
            let column = placement.column - occupied.column
            let row = placement.row - occupied.row
            return CGRect(
                x: originX + CGFloat(column) * (cellWidth + gap),
                y: originY + CGFloat(row) * (cellHeight + gap),
                width: CGFloat(placement.columns) * cellWidth + CGFloat(placement.columns - 1) * gap,
                height: CGFloat(placement.rows) * cellHeight + CGFloat(placement.rows - 1) * gap)
        }
    }
}

/// Renders cards independently so the composer can remain interactive.
@MainActor @Observable
final class ShareCardRenderController {
    private(set) var images: [UUID: UIImage] = [:]
    private(set) var isRendering = false
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
        images.removeAll()
        cache.removeAll()
        cacheScope = nil
        completedKey = nil
#if DEBUG
        debugExportedKey = nil
#endif
    }

    func render(
        model: ShareComposerModel,
        itineraries: ItineraryStore,
        rides: [RiddenRouteStore.DrawnRide],
        localization: AppLocalization,
        journeyPresentation: @escaping (Train) -> JourneyPresentation,
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
            images.removeAll()
            cache.removeAll()
            cacheScope = key
        }
        isRendering = true
        defer { if generation == request { isRendering = false } }
        let operation = UUID()
        let buffer = RenderBuffer()
        renderingBuffers[operation] = buffer
        defer {
            buffer.images.removeAll()
            renderingBuffers.removeValue(forKey: operation)
        }
        guard await renderCards(
            model: model, itineraries: itineraries, rides: rides,
            localization: localization, journeyPresentation: journeyPresentation,
            key: key, canvasSize: canvasSize, request: request, useCache: true, buffer: buffer)
        else { return }
        guard generation == request, !Task.isCancelled else { return }
        images = buffer.images
        completedKey = key
    }

    private func renderCards(
        model: ShareComposerModel,
        itineraries: ItineraryStore,
        rides: [RiddenRouteStore.DrawnRide],
        localization: AppLocalization,
        journeyPresentation: @escaping (Train) -> JourneyPresentation,
        key: String,
        canvasSize: CGSize,
        request: Int,
        useCache: Bool,
        buffer: RenderBuffer
    ) async -> Bool {
        let frames = ShareCanvasGeometry.frames(model: model, canvasSize: canvasSize)
        let scopedTrains = model.effectiveScope.filter(
            itineraries.loaded?.trains ?? [], rides: rides).filter { train in
                RideLedger.hasBeenRidden(train)
                    && model.statistics.includesYear(train)
                    && model.statistics.includesJourneyGroup(train)
                    && model.statistics.includesDate(train)
            }
        let memberIDs = Set(scopedTrains.map(\.id))
        for card in model.cards where model.layout.placements[card.id] != nil {
            guard generation == request, !Task.isCancelled else { return false }
            let frame = frames[card.id] ?? CGRect(x: 0, y: 0, width: 600, height: 600)
            let cacheKey = "\(key)|\(card.kind)|\(card.span.columns)x\(card.span.rows)|\(card.mapZoom)|\(model.ratio.rawValue)|\(model.colorScheme)"
            if useCache, let cached = cache[cacheKey] {
                buffer.images[card.id] = cached
                continue
            }
            let image: UIImage?
            switch card.kind {
            case .ticket:
                image = renderRecordTicket(
                    model: model, itineraries: itineraries,
                    memberIDs: memberIDs, localization: localization,
                    journeyPresentation: journeyPresentation, target: frame.size)
            case .stat(let kind):
                if kind == .recordTicket {
                    image = renderRecordTicket(
                        model: model, itineraries: itineraries,
                        memberIDs: memberIDs, localization: localization,
                        journeyPresentation: journeyPresentation, target: frame.size)
                } else {
                    image = renderDashboardCard(
                        kind, model: model, itineraries: itineraries,
                        memberIDs: memberIDs, localization: localization,
                        journeyPresentation: journeyPresentation, target: frame.size)
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
            if let image {
                if useCache { cache[cacheKey] = image }
                buffer.images[card.id] = image
            }
        }
        return generation == request && !Task.isCancelled
    }

    func export(
        model: ShareComposerModel,
        itineraries: ItineraryStore,
        rides: [RiddenRouteStore.DrawnRide],
        localization: AppLocalization,
        journeyPresentation: @escaping (Train) -> JourneyPresentation,
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
            model: model, itineraries: itineraries, rides: rides,
            localization: localization, journeyPresentation: journeyPresentation,
            key: key, canvasSize: size, request: request, useCache: false, buffer: buffer)
        else { return nil }
        guard generation == request, !Task.isCancelled else { return nil }
        let frames = ShareCanvasGeometry.frames(model: model, canvasSize: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let traits = UITraitCollection(userInterfaceStyle: model.colorScheme == .dark ? .dark : .light)
        let background = UIColor.systemBackground.resolvedColor(with: traits)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let radius = min(size.width, size.height) * 0.018
            for card in model.cards {
                guard let frame = frames[card.id], let image = buffer.images[card.id] else { continue }
                context.cgContext.saveGState()
                if case .ticket = card.kind {} else {
                    UIBezierPath(roundedRect: frame, cornerRadius: radius).addClip()
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
        rides: [RiddenRouteStore.DrawnRide], localization: AppLocalization,
        journeyPresentation: @escaping (Train) -> JourneyPresentation,
        to url: URL, key: String
    ) async {
        let request = generation
        guard completedKey == key,
              await export(
                model: model, itineraries: itineraries, rides: rides,
                localization: localization, journeyPresentation: journeyPresentation,
                key: key, to: url) != nil
        else { return }
        guard generation == request, completedKey == key, !Task.isCancelled else { return }
        debugExportedKey = key
    }
#endif

    private func renderRecordTicket(
        model: ShareComposerModel,
        itineraries: ItineraryStore,
        memberIDs: Set<String>,
        localization: AppLocalization,
        journeyPresentation: @escaping (Train) -> JourneyPresentation,
        target: CGSize
    ) -> UIImage? {
        let face = StatisticsDashboardContent(
            itineraries: itineraries, statistics: model.statistics,
            region: .constant(nil), memberIDs: memberIDs,
            scopeName: model.scopeDisplayName(localization),
            journeyPresentation: journeyPresentation, openJourney: { _ in },
            recordTicketFaceOnly: true)
            .frame(width: TicketFace.width, height: TicketFace.height)
            .environment(localization)
            .environment(\.colorScheme, model.colorScheme)
            .environment(\.passportPoster, true)
        let renderer = ImageRenderer(content: face)
        renderer.isOpaque = true
        let fitScale = min(target.width / TicketFace.width, target.height / TicketFace.height)
        renderer.scale = min(max(fitScale, 1), 4)
        return renderer.uiImage
    }

    private func renderDashboardCard(
        _ kind: StatisticsCardKind,
        model: ShareComposerModel,
        itineraries: ItineraryStore,
        memberIDs: Set<String>,
        localization: AppLocalization,
        journeyPresentation: @escaping (Train) -> JourneyPresentation,
        target: CGSize
    ) -> UIImage? {
        let page = StatisticsDashboardContent(
            itineraries: itineraries, statistics: model.statistics,
            region: .constant(nil), memberIDs: memberIDs,
            scopeName: model.scopeDisplayName(localization),
            journeyPresentation: journeyPresentation, openJourney: { _ in }, cards: [kind])
            .padding(16)
            .frame(width: 400, alignment: .top)
            .background(Color.railElevated(.systemBackground))
            .environment(localization)
            .environment(\.colorScheme, model.colorScheme)
            .environment(\.passportPoster, true)
        let renderer = ImageRenderer(content: page)
        renderer.isOpaque = true
        var natural = CGSize.zero
        renderer.render { size, _ in natural = size }
        guard natural.width > 0, natural.height > 0 else { return nil }
        let targetScale = max(target.width / natural.width, 1)
        let budgetScale = sqrt(16_000_000 / max(natural.width * natural.height, 1))
        renderer.scale = min(targetScale, budgetScale, 4)
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
