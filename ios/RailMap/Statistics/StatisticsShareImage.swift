import Foundation
import MapKit
import RailCore
import RailPresentation
import SwiftUI
import UIKit

/// A fresh map for the passport's selected date and region. The caller passes
/// exactly the rides counted by that scope, so the image never inherits the
/// reader's unrelated pan or zoom on the live workspace map.
enum StatisticsMapSnapshot {
    private struct SnapshotBox: @unchecked Sendable {
        let value: MKMapSnapshotter.Snapshot?
    }

    private final class SnapshotContinuation: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<SnapshotBox, Never>?
        private var result: SnapshotBox?
        private var hasResult = false

        func install(_ continuation: CheckedContinuation<SnapshotBox, Never>) {
            lock.lock()
            if hasResult, let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }

        func resume(_ result: SnapshotBox) {
            lock.lock()
            guard !hasResult else { lock.unlock(); return }
            hasResult = true
            self.result = result
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: result)
        }
    }

    @MainActor
    static func render(
        rides: [RiddenRouteStore.DrawnRide],
        fallback: MKCoordinateRegion?,
        colorScheme: ColorScheme,
        size: CGSize = CGSize(width: 736, height: 736),
        zoom: Double = 1,
        name: String? = nil,
        minimumSpan: Double = 1_000_000
    ) async -> UIImage? {
        let segments = rides.flatMap(\.segments).filter { !$0.boundingRect.isNull }
        let bounds = segments.reduce(MKMapRect.null) { $0.union($1.boundingRect) }
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.traitCollection = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let baseRect: MKMapRect
        if let fallback {
            baseRect = MapProjection.mapRect(of: fallback)
        } else if !bounds.isNull {
            baseRect = bounds
        } else {
            return placeholder(size: size, colorScheme: colorScheme, name: name)
        }
        options.mapRect = fitted(
            baseRect, aspect: size.width / max(size.height, 1), zoom: zoom, minimumSpan: minimumSpan)

        let snapshotSize = options.size
        let snapshotter = MKMapSnapshotter(options: options)
        let resumeOnce = SnapshotContinuation()
        let result: SnapshotBox = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                resumeOnce.install(continuation)
                guard !Task.isCancelled else {
                    snapshotter.cancel()
                    resumeOnce.resume(SnapshotBox(value: nil))
                    return
                }
                snapshotter.start(with: .main) { snapshot, _ in
                    resumeOnce.resume(SnapshotBox(value: snapshot))
                }
            }
        } onCancel: {
            snapshotter.cancel()
            resumeOnce.resume(SnapshotBox(value: nil))
        }
        guard !Task.isCancelled else { return nil }
        guard let snapshot = result.value else {
            return placeholder(size: snapshotSize, colorScheme: colorScheme, name: name)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: snapshotSize, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for ride in rides {
                guard let color = UIColor(railHex: ride.colorHex) else { continue }
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(max(2, min(size.width, size.height) / 180))
                for segment in ride.segments where segment.coordinates.count > 1 {
                    let points = segment.coordinates.map {
                        snapshot.point(for: CLLocationCoordinate2D(
                            latitude: $0.lat, longitude: $0.lon))
                    }
                    cg.beginPath()
                    cg.move(to: points[0])
                    for point in points.dropFirst() { cg.addLine(to: point) }
                    cg.strokePath()
                }
            }
            if let name {
                let font = UIFont.systemFont(ofSize: max(12, min(size.width, size.height) / 24),
                                             weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.label,
                ]
                let measured = (name as NSString).size(withAttributes: attributes)
                let inset = max(10, min(size.width, size.height) / 40)
                let rect = CGRect(x: inset, y: inset,
                                  width: measured.width + inset * 1.4,
                                  height: measured.height + inset)
                cg.setFillColor((colorScheme == .dark
                    ? UIColor.black.withAlphaComponent(0.76)
                    : UIColor.systemBackground.withAlphaComponent(0.86)).cgColor)
                cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).cgPath)
                cg.fillPath()
                (name as NSString).draw(at: CGPoint(x: rect.minX + inset * 0.7,
                                                    y: rect.minY + inset * 0.5),
                                        withAttributes: attributes)
            }
        }
    }

    private static func placeholder(
        size: CGSize, colorScheme: ColorScheme, name: String?
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let traits = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBackground.resolvedColor(with: traits).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.secondarySystemFill.resolvedColor(with: traits).setFill()
            let inset = max(8, min(size.width, size.height) * 0.08)
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(
                dx: inset, dy: inset), cornerRadius: inset).fill()
            guard let name, !name.isEmpty else { return }
            let font = UIFont.systemFont(
                ofSize: max(13, min(size.width, size.height) / 18), weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.label.resolvedColor(with: traits),
            ]
            let measured = (name as NSString).size(withAttributes: attributes)
            (name as NSString).draw(
                at: CGPoint(x: (size.width - measured.width) / 2,
                            y: (size.height - measured.height) / 2),
                withAttributes: attributes)
        }
    }

    /// `minimumSpan` keeps a region map from zooming into one station; a
    /// share card passes a small one so a 40-minute ride fills its frame.
    private static func fitted(
        _ rect: MKMapRect, aspect: CGFloat, zoom: Double, minimumSpan: Double
    ) -> MKMapRect {
        let margin = minimumSpan < 1_000_000 ? 1.3 : 1
        var width = max(rect.width * margin, minimumSpan)
        var height = max(rect.height * margin, minimumSpan)
        let current = width / height
        if current < aspect { width = height * aspect } else { height = width / aspect }
        let scale = 1 / min(max(zoom, 0.75), 2)
        return MKMapRect(x: rect.midX - width * scale / 2, y: rect.midY - height * scale / 2,
                         width: width * scale, height: height * scale)
    }
}
